import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder の「このアプリケーションで開く」や `open -a VisualTouch ファイル…` で渡された項目を一覧に追加する。
    func application(_ application: NSApplication, open urls: [URL]) {
        FileStore.shared.add(urls: urls, recurse: false)
    }
}

@main
struct VisualTouchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // WindowGroup だと open で渡されたファイルごとにウインドウが増えるので、単一ウインドウにする
        Window("VisualTouch", id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Divider()
                Button("コマンドラインツール「vtouch」をインストール…") {
                    CLIInstaller.installWithPrompt()
                }
            }
        }
    }
}
