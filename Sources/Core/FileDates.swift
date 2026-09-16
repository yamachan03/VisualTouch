import Foundation
import CoreServices

/// ファイルが持つ日時の一式。
struct FileDates: Hashable {
    var creation: Date?         // birthtime（Finder の「作成日」）
    var modification: Date?     // mtime（Finder の「変更日」）
    var access: Date?           // atime
    var added: Date?            // このフォルダに追加された日（Finder の「追加日」）
    var isDirectory: Bool = false
}

/// GUI と vtouch コマンドが共有する、日時の読み書き。
enum FileDateIO {
    private static let fm = FileManager.default

    // MARK: - 読み取り

    /// URL リソース値だけを見る軽い読み取り。
    ///
    /// URL は一度取得したリソース値をインスタンスに溜め込むため、保持している
    /// URL のまま読み直すと書き込み前の値が返る。毎回作り直して素の値を読む。
    static func read(_ original: URL) -> FileDates {
        let url = URL(fileURLWithPath: original.path)
        let v = try? url.resourceValues(forKeys: [.creationDateKey,
                                                  .contentModificationDateKey,
                                                  .contentAccessDateKey,
                                                  .addedToDirectoryDateKey,
                                                  .isDirectoryKey])
        return FileDates(creation: v?.creationDate,
                         modification: v?.contentModificationDate,
                         access: v?.contentAccessDate,
                         added: v?.addedToDirectoryDate,
                         isDirectory: v?.isDirectory ?? isDirectory(url))
    }

    /// Spotlight が持つ日時。写真の撮影日など、ファイルシステムの作成日とは別物。
    static func spotlightDates(_ url: URL) -> (fsCreation: Date?, contentCreation: Date?) {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return (nil, nil) }
        return (MDItemCopyAttribute(item, kMDItemFSCreationDate) as? Date,
                MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date)
    }

    static func exists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    /// フォルダ配下を列挙する。パッケージ（.app 等）の中には入らない。
    static func descendants(of url: URL, includeHidden: Bool) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.isDirectoryKey],
                                    options: options) else { return [] }
        return e.compactMap { $0 as? URL }.map { $0.standardizedFileURL }
    }

    // MARK: - 書き込み

    /// 指定された日時だけを書く。nil の項目は触らない。
    ///
    /// mtime を先に、birthtime を後に書く。逆順だと mtime 書き込みで
    /// 作成日が引きずられる環境があるため。
    static func write(creation: Date?, modification: Date?, access: Date?, to url: URL) throws {
        if let access { try setAccessDate(access, url: url) }
        if let modification {
            try fm.setAttributes([.modificationDate: modification], ofItemAtPath: url.path)
        }
        if let creation {
            try fm.setAttributes([.creationDate: creation], ofItemAtPath: url.path)
        }
    }

    /// 書き込み後に読み直し、狙った日時になっているかを 1 秒の許容で確かめる。
    /// アクセス日は読み取っただけでも OS が書き換えるため検証しない。
    /// 問題があればその説明を返す。
    static func verify(creation: Date?, modification: Date?, actual: FileDates) -> String? {
        func off(_ want: Date?, _ got: Date?) -> Bool {
            guard let want else { return false }
            guard let got else { return true }
            return abs(got.timeIntervalSince(want)) > 1
        }
        if off(creation, actual.creation) { return String(localized: "作成日を変更できませんでした") }
        if off(modification, actual.modification) { return String(localized: "変更日を変更できませんでした") }
        return nil
    }

    /// 空ファイルを作る（touch と同じ振る舞い）。
    static func createEmptyFile(at url: URL) throws {
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }

    /// アクセス日は FileManager から書けないので utimes(2) を使う。
    /// 変更日を巻き添えにしないよう、現在の mtime をそのまま書き戻す。
    private static func setAccessDate(_ date: Date, url: URL) throws {
        let current = (try? URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        var times = [timeval(from: date), timeval(from: current)]
        let r = url.path.withCString { utimes($0, &times) }
        if r != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM) }
    }

    // MARK: - エラー表示

    static func describe(_ error: Error) -> String {
        if let e = error as? SimpleError { return e.message }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteNoPermissionError: return String(localized: "権限がありません")
            case NSFileWriteVolumeReadOnlyError: return String(localized: "読み取り専用のボリュームです")
            case NSFileNoSuchFileError: return String(localized: "ファイルが見つかりません")
            default: break
            }
        }
        if let e = error as? POSIXError {
            switch e.code {
            case .EPERM, .EACCES: return String(localized: "権限がありません")
            case .ENOENT: return String(localized: "ファイルが見つかりません")
            case .EROFS: return String(localized: "読み取り専用のボリュームです")
            default: break
            }
        }
        return error.localizedDescription
    }
}

struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension timeval {
    init(from date: Date) {
        let t = date.timeIntervalSince1970
        let sec = floor(t)
        self.init(tv_sec: Int(sec), tv_usec: Int32((t - sec) * 1_000_000))
    }
}
