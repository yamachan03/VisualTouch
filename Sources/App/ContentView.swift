import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ApplyScope: Hashable {
    case all, selection
}

struct ContentView: View {
    @ObservedObject private var store = FileStore.shared

    @State private var targetDate = Date()
    @State private var second = Calendar.current.component(.second, from: Date())
    @State private var applyCreation = true
    @State private var applyModification = true
    @State private var applyAccess = false
    @State private var recurse = false
    @State private var scope: ApplyScope = .all
    @State private var selection = Set<FileEntry.ID>()
    @State private var isTargeted = false
    /// 直近にコピーした日時。クリップボードにも同じ値を入れている。
    @State private var copied: Date?

    /// ピッカーの日付と秒を合成した、実際に書き込む日時。
    private var composedDate: Date {
        Calendar.current.date(bySetting: .second, value: second, of: targetDate) ?? targetDate
    }

    /// 適用対象の ID 集合。すべてが対象のときは空集合を渡す。
    private var targetIDs: Set<FileEntry.ID> {
        scope == .all ? [] : selection
    }

    private var targetCount: Int {
        scope == .all ? store.entries.count : selection.count
    }

    var body: some View {
        VStack(spacing: 0) {
            fileList
            Divider()
            inspector
            Divider()
            controls
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { handleDrop($0) }
    }

    // MARK: - ファイル一覧

    private var fileList: some View {
        ZStack {
            Table(store.entries, selection: $selection) {
                TableColumn("名前") { e in
                    Label {
                        Text(e.name).lineLimit(1).truncationMode(.middle)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: e.url.path))
                            .resizable().frame(width: 16, height: 16)
                    }
                    .help(e.url.path)
                }
                .width(min: 150, ideal: 220)

                TableColumn("元の作成日") { e in
                    Text(format(e.original.creation))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 130, ideal: 155)

                TableColumn("現在の作成日") { e in
                    Text(format(e.current.creation))
                        .monospacedDigit()
                        .fontWeight(e.creationChanged ? .semibold : .regular)
                        .foregroundStyle(e.creationChanged ? Color.accentColor : Color.primary)
                }
                .width(min: 130, ideal: 155)

                TableColumn("変更日") { e in
                    Text(format(e.current.modification)).monospacedDigit()
                }
                .width(min: 130, ideal: 155)

                TableColumn("状態") { e in
                    Text(e.status.label)
                        .foregroundStyle(statusColor(e.status))
                        .lineLimit(1)
                        .help(e.status.label)
                }
                .width(min: 90, ideal: 130)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
                Button("作成日をコピー") { copyDates(ids: ids, kind: .creation) }
                Button("変更日をコピー") { copyDates(ids: ids, kind: .modification) }
                Divider()
                Button("Finder で表示") { revealInFinder(ids: ids) }
                Button("一覧から外す") { store.remove(ids: ids); selection.subtract(ids) }
            }
            .opacity(store.entries.isEmpty ? 0 : 1)

            if store.entries.isEmpty { emptyState }

            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 220)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("ファイルやフォルダをここにドラッグ＆ドロップ")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("複数まとめて追加できます（「追加…」ボタンからも可）")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 選択中ファイルの日時内訳

    @ViewBuilder
    private var inspector: some View {
        let picked = store.entries.filter { selection.contains($0.id) }
        Group {
            if let e = picked.first, picked.count == 1 {
                let spot = FileDateIO.spotlightDates(e.url)
                // 7 項目を 1 行に並べると幅が足りないので 2 段に分ける
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        dateField("作成日（変更前）", e.original.creation)
                        dateField("作成日（現在）", e.current.creation, highlight: e.creationChanged)
                        dateField("変更日", e.current.modification)
                        dateField("アクセス日", e.current.access)
                    }
                    GridRow {
                        dateField("追加日", e.current.added)
                        dateField("Spotlight 作成日", spot.fsCreation)
                        dateField("コンテンツ作成日", spot.contentCreation,
                                  help: "写真の撮影日など、ファイル内部のメタデータに記録された日時。ファイルシステムの作成日とは別物で、このアプリでは変更しません。")
                    }
                }
            } else {
                Text(picked.isEmpty
                     ? "行を選ぶと、そのファイルが持つ日時の内訳を表示します"
                     : "\(picked.count) 件を選択中")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func dateField(_ title: LocalizedStringKey, _ date: Date?,
                           highlight: Bool = false, help: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(format(date))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(highlight ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .help(help ?? title)
    }

    // MARK: - 操作パネル

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("追加…") { openPanel() }
                Button("一覧から外す") { store.remove(ids: selection); selection.removeAll() }
                    .disabled(selection.isEmpty)
                Button("すべてクリア") { store.removeAll(); selection.removeAll() }
                    .disabled(store.entries.isEmpty)
                Toggle("フォルダの中身も追加", isOn: $recurse).toggleStyle(.checkbox)
                Spacer()
                Text(store.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            HStack(spacing: 12) {
                Text("設定する日時").fontWeight(.medium)

                DatePicker("", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .fixedSize()

                HStack(spacing: 4) {
                    Text("秒")
                    Stepper(value: $second, in: 0...59) {
                        Text(String(format: "%02d", second)).monospacedDigit().frame(width: 22)
                    }
                }

                Button("現在時刻") { setNow() }

                Divider().frame(height: 16)

                Button("作成日をコピー") { copyDates(ids: selection, kind: .creation) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selection.isEmpty)

                Button("ペースト") { pasteDate() }
                    .keyboardShortcut("v", modifiers: .command)

                if let copied {
                    Text("コピー中: \(DateText.string(from: copied))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Text("変更する日時").fontWeight(.medium)
                Toggle("作成日", isOn: $applyCreation).toggleStyle(.checkbox)
                Toggle("変更日", isOn: $applyModification).toggleStyle(.checkbox)
                Toggle("アクセス日", isOn: $applyAccess).toggleStyle(.checkbox)
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("適用先", selection: $scope) {
                    Text("すべて（\(store.entries.count) 件）").tag(ApplyScope.all)
                    Text("選択中のみ（\(selection.count) 件）").tag(ApplyScope.selection)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button("元の日時に戻す") { store.revert(ids: targetIDs) }
                    .disabled(targetCount == 0)

                Button {
                    store.apply(date: composedDate,
                                ids: targetIDs,
                                creation: applyCreation,
                                modification: applyModification,
                                access: applyAccess)
                } label: {
                    Text("\(targetCount) 件に適用").frame(minWidth: 90)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(targetCount == 0 || !(applyCreation || applyModification || applyAccess))
            }
        }
        .padding(14)
        .background(.bar)
    }

    // MARK: - アクション

    private func setNow() {
        let now = Date()
        targetDate = now
        second = Calendar.current.component(.second, from: now)
    }

    private enum DateKind { case creation, modification }

    /// 選択行の日時をクリップボードへ。複数選択なら「名前<TAB>日時」の行を並べる。
    private func copyDates(ids: Set<FileEntry.ID>, kind: DateKind) {
        let keyPath: KeyPath<FileDates, Date?> = kind == .creation ? \.creation : \.modification
        let picked = store.entries.filter { ids.contains($0.id) }
        let dates = picked.compactMap { $0.current[keyPath: keyPath] }
        guard !dates.isEmpty else {
            store.message = kind == .creation
                ? String(localized: "コピーできる作成日がありません")
                : String(localized: "コピーできる変更日がありません")
            return
        }
        if picked.count == 1, let d = dates.first {
            let text = DateText.string(from: d)
            DateClipboard.copy(text)
            store.message = kind == .creation
                ? String(localized: "作成日をコピーしました: \(text)")
                : String(localized: "変更日をコピーしました: \(text)")
        } else {
            let lines = picked.compactMap { e -> String? in
                guard let d = e.current[keyPath: keyPath] else { return nil }
                return e.name + "\t" + DateText.string(from: d)
            }
            DateClipboard.copy(lines.joined(separator: "\n"))
            store.message = kind == .creation
                ? String(localized: "\(lines.count) 件の作成日をコピーしました")
                : String(localized: "\(lines.count) 件の変更日をコピーしました")
        }
        copied = dates.first
    }

    /// クリップボードの日時を「設定する日時」に流し込む。
    private func pasteDate() {
        guard let d = DateClipboard.paste() else {
            store.message = String(localized: "クリップボードから日時を読み取れませんでした")
            return
        }
        targetDate = d
        second = Calendar.current.component(.second, from: d)
        copied = d
        store.message = String(localized: "日時をペーストしました: \(DateText.string(from: d))")
    }

    private func revealInFinder(ids: Set<FileEntry.ID>) {
        let urls = store.entries.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "日時を変更するファイル／フォルダを選択")
        panel.prompt = String(localized: "追加")
        if panel.runModal() == .OK {
            store.add(urls: panel.urls, recurse: recurse)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                let url: URL?
                switch item {
                case let data as Data: url = URL(dataRepresentation: data, relativeTo: nil)
                case let u as URL: url = u
                default: url = nil
                }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            store.add(urls: urls, recurse: recurse)
        }
        return true
    }

    // MARK: - 表示

    private func statusColor(_ s: FileEntry.Status) -> Color {
        switch s {
        case .none: return .secondary
        case .success: return .green
        case .failure: return .orange
        }
    }

    private func format(_ date: Date?) -> String { DateText.string(from: date) }
}
