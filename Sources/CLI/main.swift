import Foundation

// vtouch — touch(1) の拡張。作成日（birthtime）も書け、フォルダの中まで再帰できる。

let version = "1.0"

let usage = """
vtouch — touch の拡張。作成日（birthtime）も書け、フォルダの中まで再帰できます。

使い方: vtouch [オプション] <ファイル/フォルダ>...

日時（いずれか 1 つ。省略時は現在時刻）:
  -t STAMP            touch 互換の [[CC]YY]MMDDhhmm[.SS]   例: -t 202608310640.55
  -d DATETIME         "2026/08/31 06:40:55" "2026-08-31T06:40" "2026年8月31日" など
  --reference FILE    FILE の作成日／変更日／アクセス日をそのまま写す

変更する日時（省略時は 3 つとも）:
  -b                  作成日 (birthtime)
  -m                  変更日
  -a                  アクセス日

対象の選び方（rm 風）:
  -r, -R              フォルダの中のファイル／サブフォルダにも再帰して適用
  -H                  再帰時に隠しファイル（. で始まる名前）も含める
  -f                  存在しないパスやエラーを無視して続行し、終了コードも 0 にする
  -i                  1 件ずつ確認してから変更する
  -c                  存在しないファイルを作らない（既定では touch と同じく空ファイルを作る）

その他:
  -l                  日時を表示するだけで変更しない
  -n                  ドライラン（変更せず、対象と日時だけ表示）
  -v                  変更したファイルを 1 件ずつ表示
  -h, --help          このヘルプ
  --version           バージョン

例:
  vtouch -r -t 202001010000 ~/Pictures/旅行        # フォルダごと 2020/01/01 00:00 に
  vtouch -b -d "2026/08/31 06:40:55" 報告書.pages   # 作成日だけ変更
  vtouch -r --reference 元.txt 編集後/              # 元.txt の日時を編集後/ 以下すべてに写す
  vtouch -rl ~/Documents                           # 日時を一覧表示するだけ
"""

struct Options {
    var date: Date?
    var reference: URL?
    var creation = false
    var modification = false
    var access = false
    var recursive = false
    var includeHidden = false
    var force = false
    var interactive = false
    var noCreate = false
    var listOnly = false
    var dryRun = false
    var verbose = false
    var paths: [String] = []

    /// -b/-m/-a のどれも無ければ 3 つとも。
    mutating func finalizeKinds() {
        if !(creation || modification || access) {
            creation = true; modification = true; access = true
        }
    }
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(("vtouch: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func warn(_ message: String) {
    FileHandle.standardError.write(("vtouch: " + message + "\n").data(using: .utf8)!)
}

// MARK: - 引数解釈

func parseArguments(_ args: [String]) -> Options {
    var o = Options()
    var i = 0
    var dateSpecified = 0

    func takeValue(after flag: String, inline: Substring?) -> String {
        if let inline, !inline.isEmpty { return String(inline) }
        i += 1
        guard i < args.count else { fail("\(flag) には値が必要です") }
        return args[i]
    }

    while i < args.count {
        let a = args[i]
        if a == "--" {
            o.paths.append(contentsOf: args[(i + 1)...]); break
        }
        if a.hasPrefix("--") {
            switch a {
            case "--help": print(usage); exit(0)
            case "--version": print("vtouch \(version)"); exit(0)
            case "--reference":
                o.reference = URL(fileURLWithPath: takeValue(after: a, inline: nil))
                dateSpecified += 1
            case "--recursive": o.recursive = true
            case "--hidden": o.includeHidden = true
            case "--force": o.force = true
            case "--interactive": o.interactive = true
            case "--no-create": o.noCreate = true
            case "--list": o.listOnly = true
            case "--dry-run": o.dryRun = true
            case "--verbose": o.verbose = true
            default: fail("不明なオプション: \(a)\n\n" + usage)
            }
            i += 1
            continue
        }
        if a.hasPrefix("-"), a.count > 1 {
            var chars = a.dropFirst()
            while let ch = chars.first {
                chars = chars.dropFirst()
                switch ch {
                case "t":
                    let v = takeValue(after: "-t", inline: chars)
                    guard let d = DateText.parseTouchStamp(v) else { fail("-t の形式が不正です: \(v)（[[CC]YY]MMDDhhmm[.SS]）") }
                    o.date = d; dateSpecified += 1; chars = ""
                case "d":
                    let v = takeValue(after: "-d", inline: chars)
                    guard let d = DateText.parse(v) else { fail("-d の日時を解釈できません: \(v)") }
                    o.date = d; dateSpecified += 1; chars = ""
                case "b": o.creation = true
                case "m": o.modification = true
                case "a": o.access = true
                case "r", "R": o.recursive = true
                case "H": o.includeHidden = true
                case "f": o.force = true
                case "i": o.interactive = true
                case "c": o.noCreate = true
                case "l": o.listOnly = true
                case "n": o.dryRun = true
                case "v": o.verbose = true
                case "h": print(usage); exit(0)
                default: fail("不明なオプション: -\(ch)\n\n" + usage)
                }
            }
            i += 1
            continue
        }
        o.paths.append(a)
        i += 1
    }

    if dateSpecified > 1 { fail("-t / -d / --reference は 1 つだけ指定してください") }
    if o.paths.isEmpty { fail("対象のファイルを指定してください\n\n" + usage) }
    o.finalizeKinds()
    return o
}

// MARK: - 対象の展開

/// 与えられたパスを、再帰時は深いものから順に並べて返す。
/// 親フォルダより先に中身を処理しておけば、あとから親の日時が動く心配がない。
func expand(_ paths: [String], options: Options) -> [(url: URL, given: Bool)] {
    var result: [(URL, Bool)] = []
    var seen = Set<String>()
    for p in paths {
        let url = URL(fileURLWithPath: p).standardizedFileURL
        if options.recursive, FileDateIO.isDirectory(url) {
            let kids = FileDateIO.descendants(of: url, includeHidden: options.includeHidden)
                .sorted { $0.pathComponents.count > $1.pathComponents.count }
            for k in kids where seen.insert(k.path).inserted { result.append((k, false)) }
        }
        if seen.insert(url.path).inserted { result.append((url, true)) }
    }
    return result
}

// MARK: - 1 件の処理

enum Outcome { case done, skipped, failed }

func confirm(_ prompt: String) -> Bool {
    FileHandle.standardError.write((prompt + " [y/N] ").data(using: .utf8)!)
    guard let line = readLine() else { return false }
    return ["y", "yes"].contains(line.trimmingCharacters(in: .whitespaces).lowercased())
}

/// カレントディレクトリ配下なら相対パスで見せる。
/// /tmp → /private/tmp のようなシンボリックリンク差を吸収するため、両方とも実体で比べる。
let cwdPrefix = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path + "/"
func shown(_ url: URL) -> String {
    let p = url.resolvingSymlinksInPath().path
    return p.hasPrefix(cwdPrefix) ? String(p.dropFirst(cwdPrefix.count)) : url.path
}

func process(_ url: URL, given: Bool, options: Options,
             creation: Date?, modification: Date?, access: Date?) -> Outcome {
    let path = shown(url)

    if !FileDateIO.exists(url) {
        // touch と同じく、指定されたファイルが無ければ作る。
        // ただし -c のとき、また表示だけの -l / -n のときは作らない。
        if options.noCreate { return .skipped }
        if options.listOnly {
            if !options.force { warn("\(path): ファイルが見つかりません") }
            return .failed
        }
        guard given else { return .failed }
        if options.dryRun {
            print("(dry-run) 作成: \(path)")
            return .done
        }
        if options.interactive, !confirm("\(path) は存在しません。空のファイルを作りますか?") {
            return .skipped
        }
        do { try FileDateIO.createEmptyFile(at: url) }
        catch {
            if !options.force { warn("\(path): 作成できません — \(FileDateIO.describe(error))") }
            return .failed
        }
    }

    if options.listOnly {
        let d = FileDateIO.read(url)
        print("\(DateText.string(from: d.creation))  \(DateText.string(from: d.modification))  \(DateText.string(from: d.access))  \(path)")
        return .done
    }

    if options.dryRun {
        let d = FileDateIO.read(url)
        var parts: [String] = []
        if let c = creation { parts.append("作成日 \(DateText.string(from: d.creation)) → \(DateText.string(from: c))") }
        if let m = modification { parts.append("変更日 \(DateText.string(from: d.modification)) → \(DateText.string(from: m))") }
        if let a = access { parts.append("アクセス日 \(DateText.string(from: d.access)) → \(DateText.string(from: a))") }
        print("(dry-run) \(path)\n    " + parts.joined(separator: "\n    "))
        return .done
    }

    if options.interactive, !confirm("\(path) を変更しますか?") {
        return .skipped
    }

    do {
        try FileDateIO.write(creation: creation, modification: modification, access: access, to: url)
        let after = FileDateIO.read(url)
        if let problem = FileDateIO.verify(creation: creation, modification: modification, actual: after) {
            if !options.force { warn("\(path): \(problem)") }
            return .failed
        }
        if options.verbose { print("✓ \(path)") }
        return .done
    } catch {
        if !options.force { warn("\(path): \(FileDateIO.describe(error))") }
        return .failed
    }
}

// MARK: - main

let options = parseArguments(Array(CommandLine.arguments.dropFirst()))

// 書き込む日時を決める。--reference は種類ごとに写す。
var creationDate: Date?
var modificationDate: Date?
var accessDate: Date?
if let ref = options.reference {
    guard FileDateIO.exists(ref) else { fail("--reference のファイルが見つかりません: \(ref.path)") }
    let r = FileDateIO.read(ref)
    creationDate = options.creation ? r.creation : nil
    modificationDate = options.modification ? r.modification : nil
    accessDate = options.access ? r.access : nil
} else {
    let d = options.date ?? Date()
    creationDate = options.creation ? d : nil
    modificationDate = options.modification ? d : nil
    accessDate = options.access ? d : nil
}

if options.listOnly {
    print("作成日              変更日              アクセス日          パス")
}

var done = 0, failed = 0, skipped = 0
for (url, given) in expand(options.paths, options: options) {
    switch process(url, given: given, options: options,
                   creation: creationDate, modification: modificationDate, access: accessDate) {
    case .done: done += 1
    case .skipped: skipped += 1
    case .failed: failed += 1
    }
}

if options.verbose || options.dryRun {
    var summary = "\(done) 件"
    if skipped > 0 { summary += " / \(skipped) 件スキップ" }
    if failed > 0 { summary += " / \(failed) 件失敗" }
    FileHandle.standardError.write((summary + "\n").data(using: .utf8)!)
}

exit(failed > 0 && !options.force ? 1 : 0)
