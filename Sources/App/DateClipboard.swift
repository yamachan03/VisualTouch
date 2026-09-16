import Foundation
import AppKit

/// 日時をクリップボード経由でやり取りする。整形と解釈は DateText に任せる。
enum DateClipboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// クリップボードの文字列から最初に見つかった日時を読み取る。
    static func paste() -> Date? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return DateText.parse(text)
    }
}
