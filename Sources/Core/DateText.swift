import Foundation

/// 日時と文字列の相互変換。GUI のコピー／ペーストと vtouch の -d / -t で共用する。
enum DateText {
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    static func string(from date: Date) -> String { display.string(from: date) }

    static func string(from date: Date?) -> String {
        date.map(string(from:)) ?? "—"
    }

    /// 日付だけ / 秒なし / 区切り違いを許容して日時を拾う。
    /// 「2026/08/31 06:40:55」「2026-08-31T06:40」「2026年8月31日」など。
    /// 「日」の前に \s* を置くと空白を貪欲に食って時刻が取れなくなるので置かない。
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }

        let pattern = #"(\d{4})\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})日?(?:[\sT]+(\d{1,2})\s*[:時]\s*(\d{1,2})(?:\s*[:分]\s*(\d{1,2}))?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else { return nil }

        func number(_ index: Int) -> Int? {
            guard let r = Range(m.range(at: index), in: trimmed) else { return nil }
            return Int(trimmed[r])
        }

        var c = DateComponents()
        c.year = number(1)
        c.month = number(2)
        c.day = number(3)
        c.hour = number(4) ?? 0
        c.minute = number(5) ?? 0
        c.second = number(6) ?? 0
        return Calendar.current.date(from: c)
    }

    /// touch(1) の -t 形式 [[CC]YY]MMDDhhmm[.SS] を解釈する。
    /// 年の省略時は今年、YY だけのときは POSIX に倣い 69–99 → 19xx、00–68 → 20xx。
    static func parseTouchStamp(_ stamp: String) -> Date? {
        let parts = stamp.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        let main = String(parts[0])
        var second = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let s = Int(parts[1]), (0...61).contains(s) else { return nil }
            second = s
        }

        var c = DateComponents()
        let cal = Calendar.current
        var rest = main[...]
        switch main.count {
        case 12:
            c.year = Int(rest.prefix(4)); rest = rest.dropFirst(4)
        case 10:
            let yy = Int(rest.prefix(2)) ?? 0
            c.year = yy >= 69 ? 1900 + yy : 2000 + yy
            rest = rest.dropFirst(2)
        case 8:
            c.year = cal.component(.year, from: Date())
        default:
            return nil
        }
        c.month = Int(rest.prefix(2)); rest = rest.dropFirst(2)
        c.day = Int(rest.prefix(2)); rest = rest.dropFirst(2)
        c.hour = Int(rest.prefix(2)); rest = rest.dropFirst(2)
        c.minute = Int(rest.prefix(2))
        c.second = second

        guard let month = c.month, (1...12).contains(month),
              let day = c.day, (1...31).contains(day),
              let hour = c.hour, (0...23).contains(hour),
              let minute = c.minute, (0...59).contains(minute) else { return nil }
        return cal.date(from: c)
    }
}
