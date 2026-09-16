import AppKit
import Foundation

/// アプリに同梱した vtouch を /usr/local/bin へコピーする。
enum CLIInstaller {
    static let destination = "/usr/local/bin/vtouch"
    static var source: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vtouch")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: destination)
    }

    /// 同梱版とインストール済みの中身が一致しているか。
    static var isUpToDate: Bool {
        guard isInstalled,
              let a = try? Data(contentsOf: source),
              let b = try? Data(contentsOf: URL(fileURLWithPath: destination)) else { return false }
        return a == b
    }

    @MainActor
    static func installWithPrompt() {
        guard FileManager.default.fileExists(atPath: source.path) else {
            alert("vtouch が見つかりません",
                  "アプリ内に vtouch が同梱されていません。build.sh で作り直してください。", style: .critical)
            return
        }
        if isUpToDate {
            alert("インストール済みです", "\(destination) は最新の vtouch です。\n\nターミナルで vtouch --help を実行すると使い方が出ます。")
            return
        }

        let command = "mkdir -p /usr/local/bin && cp \(shellQuoted(source.path)) \(destination) && chmod 755 \(destination)"
        if let error = run(command) {
            alert("インストールできませんでした", error, style: .critical)
            return
        }
        alert("vtouch をインストールしました",
              "\(destination) に置きました。\n\n例:\n  vtouch -r -t 202001010000 ~/Pictures/旅行\n  vtouch --help")
    }

    /// まず素で試し、書けなければ管理者権限で実行する。エラーメッセージを返す。
    private static func run(_ command: String) -> String? {
        let plain = Process()
        plain.executableURL = URL(fileURLWithPath: "/bin/sh")
        plain.arguments = ["-c", command]
        plain.standardError = FileHandle.nullDevice
        plain.standardOutput = FileHandle.nullDevice
        if (try? plain.run()) != nil {
            plain.waitUntilExit()
            if plain.terminationStatus == 0 { return nil }
        }

        let script = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return "キャンセルされました" }
        return (error[NSAppleScript.errorMessage] as? String) ?? "不明なエラー"
    }

    private static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor
    private static func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.runModal()
    }
}
