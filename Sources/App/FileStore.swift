import Foundation
import SwiftUI

struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    /// 一覧に追加した時点で記録した、変更前の日時。以後書き換えない。
    let original: FileDates
    /// 現在ディスク上にある日時。
    var current: FileDates
    var status: Status = .none

    enum Status: Hashable {
        case none
        case success
        case failure(String)

        var label: String {
            switch self {
            case .none: return ""
            case .success: return "✓ 変更済み"
            case .failure(let m): return "⚠︎ " + m
            }
        }
    }

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { current.isDirectory }
    /// 追加時から作成日が動いているか。
    var creationChanged: Bool {
        guard let a = original.creation, let b = current.creation else { return false }
        return abs(a.timeIntervalSince(b)) > 1
    }
}

@MainActor
final class FileStore: ObservableObject {
    /// ウインドウと AppDelegate（Finder / open コマンドからの受け取り）で同じ一覧を使う。
    static let shared = FileStore()

    @Published var entries: [FileEntry] = []
    @Published var message: String = ""

    // MARK: - 一覧の出し入れ

    /// URL 群を一覧に追加する。recurse が true のときフォルダは中身も展開する。
    func add(urls: [URL], recurse: Bool) {
        var added = 0
        for url in urls {
            let std = url.standardizedFileURL
            added += insert(std)
            if recurse, FileDateIO.isDirectory(std) {
                for child in FileDateIO.descendants(of: std, includeHidden: false) {
                    added += insert(child)
                }
            }
        }
        message = added > 0 ? "\(added) 件を追加しました" : "追加できる項目がありませんでした（重複の可能性）"
    }

    @discardableResult
    private func insert(_ url: URL) -> Int {
        guard FileDateIO.exists(url) else { return 0 }
        guard !entries.contains(where: { $0.url == url }) else { return 0 }
        let dates = FileDateIO.read(url)
        entries.append(FileEntry(url: url, original: dates, current: dates))
        return 1
    }

    func remove(ids: Set<FileEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        message = ""
    }

    func removeAll() {
        entries.removeAll()
        message = ""
    }

    // MARK: - 適用

    /// 指定した日時を対象へ書き込み、書けたかどうかを読み直して検証する。
    /// ids が空なら全件が対象。
    func apply(date: Date, ids: Set<FileEntry.ID>, creation: Bool, modification: Bool, access: Bool) {
        guard creation || modification || access else {
            message = "変更する項目にチェックを入れてください"
            return
        }
        run(on: ids) { url in
            let c = creation ? date : nil
            let m = modification ? date : nil
            try FileDateIO.write(creation: c, modification: m, access: access ? date : nil, to: url)
            return (c, m)
        }
    }

    /// 一覧に追加した時点の日時へ戻す。
    func revert(ids: Set<FileEntry.ID>) {
        let originals = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0.original) })
        run(on: ids) { url in
            guard let o = originals[url] else { throw SimpleError("元の日時が記録されていません") }
            try FileDateIO.write(creation: o.creation, modification: o.modification,
                                 access: o.access, to: url)
            return (o.creation, o.modification)
        }
    }

    /// body は書き込みを行い、検証すべき (作成日, 変更日) を返す。
    private func run(on ids: Set<FileEntry.ID>,
                     body: (URL) throws -> (creation: Date?, modification: Date?)) {
        let targets = ids.isEmpty ? Set(entries.map(\.id)) : ids
        guard !targets.isEmpty else {
            message = "対象のファイルがありません"
            return
        }
        var ok = 0, ng = 0
        for i in entries.indices where targets.contains(entries[i].id) {
            let url = entries[i].url
            do {
                let expected = try body(url)
                entries[i].current = FileDateIO.read(url)
                if let problem = FileDateIO.verify(creation: expected.creation,
                                                   modification: expected.modification,
                                                   actual: entries[i].current) {
                    entries[i].status = .failure(problem)
                    ng += 1
                } else {
                    entries[i].status = .success
                    ok += 1
                }
            } catch {
                entries[i].status = .failure(FileDateIO.describe(error))
                ng += 1
            }
        }
        message = ng == 0 ? "\(ok) 件を変更しました" : "\(ok) 件成功 / \(ng) 件失敗"
    }
}
