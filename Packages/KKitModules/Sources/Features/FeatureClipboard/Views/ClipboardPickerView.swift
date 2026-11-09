import KKitCore
import KKitUI
import SwiftUI

/// Which items the picker lists.
enum PickerFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case pinned
    case text
    case links
    case images
    case files
    case colors
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .pinned: String(localized: "Pinned")
        case .text: String(localized: "Text")
        case .links: String(localized: "Links")
        case .images: String(localized: "Images")
        case .files: String(localized: "Files")
        case .colors: String(localized: "Colours")
        case .snippets: String(localized: "Snippets")
        }
    }

    var kinds: Set<ClipboardKind>? {
        switch self {
        case .text: [.text, .richText]
        case .links: [.link]
        case .images: [.image]
        case .files: [.files]
        case .colors: [.color]
        case .all, .pinned, .snippets: nil
        }
    }
}

/// A row in the picker.
enum PickerRow: Identifiable, Hashable {
    case item(ClipboardItem)
    case snippet(Snippet)

    var id: String {
        switch self {
        case .item(let item): "item:\(item.id)"
        case .snippet(let snippet): "snippet:\(snippet.id.uuidString)"
        }
    }
}

/// The clipboard picker (⇧⌘V): a Floating Bar mode with search, filters, a list and
/// a preview. ↵ pastes, ⌘↵ pastes as plain text, ⌘1…9 quick-paste, ⌘P pins,
/// ⌘⌫ deletes, Tab changes the filter, ⎋ closes.
struct ClipboardPickerView: View {
    let controller: ClipboardController
    let context: FloatingBarModeContext

    @State private var query = ""
    @State private var filter: PickerFilter = .all
    @State private var rows: [PickerRow] = []
    @State private var selectedID: String?
    @State private var revision = 0

    private var refreshKey: String {
        "\(query)|\(filter.rawValue)|\(revision)|\(controller.itemCount)|\(controller.recent.first?.id ?? 0)|\(controller.snippets.count)"
    }

    private var selectedRow: PickerRow? {
        rows.first { $0.id == selectedID } ?? rows.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KKSpacing.s) {
                Image(systemName: "list.clipboard")
                    .foregroundStyle(.secondary)
                KKSearchField(text: $query, placeholder: String(localized: "Search clipboard history"), onKey: handle)
                if controller.isPaused {
                    KKStatusBadge(String(localized: "Paused"), tone: .warning)
                }
            }
            .padding(.horizontal, KKSpacing.l)
            .frame(height: 44)
            filters
                .padding(.horizontal, KKSpacing.l)
                .padding(.bottom, KKSpacing.s)
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: 330)
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
                .padding(.horizontal, KKSpacing.l)
                .frame(height: 30)
        }
        .task(id: refreshKey) {
            await refresh()
        }
    }

    // MARK: Parts

    private var filters: some View {
        HStack(spacing: KKSpacing.xs) {
            ForEach(PickerFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, KKSpacing.s)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(filter == option ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05)))
                        .foregroundStyle(filter == option ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(controller.itemCount) items")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, index: index)
                            .id(row.id)
                            .onTapGesture(count: 2) { choose(row, plain: false) }
                            .onTapGesture { selectedID = row.id }
                    }
                }
                .padding(KKSpacing.xs)
            }
            .overlay {
                if rows.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .onChange(of: selectedID) { _, id in
                if let id {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private var emptyText: String {
        if filter == .snippets {
            return String(localized: "No snippets yet. Add them in Settings › Clipboard History.")
        }
        return query.isEmpty ? String(localized: "Nothing copied yet.") : String(localized: "No matches.")
    }

    private func rowView(_ row: PickerRow, index: Int) -> some View {
        let isSelected = row.id == (selectedRow?.id)
        return HStack(spacing: KKSpacing.s) {
            switch row {
            case .item(let item):
                ClipboardItemIcon(item: item, imageURL: controller.imageURL(for: item))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .lineLimit(1)
                    Text([item.sourceAppName, item.lastUsedAt.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .snippet(let snippet):
                Image(systemName: "text.badge.plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.name)
                        .lineLimit(1)
                    Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if index < 9 {
                KKKeyCap("⌘\(index + 1)")
            }
        }
        .padding(.horizontal, KKSpacing.s)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: KKRadius.control, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onDrag { dragProvider(for: row) }
    }

    @ViewBuilder
    private var preview: some View {
        switch selectedRow {
        case .item(let item):
            ClipboardPreview(item: item, imageURL: controller.imageURL(for: item))
        case .snippet(let snippet):
            VStack(alignment: .leading, spacing: KKSpacing.s) {
                ScrollView {
                    Text(SnippetExpander.expand(snippet.text, clipboard: controller.recent.first?.text))
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Text(SnippetExpander.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(KKSpacing.m)
        case nil:
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: KKSpacing.s) {
            KKKeyCap("↵")
            Text("Paste")
            KKKeyCap("⌘↵")
            Text("Plain Text")
            KKKeyCap("⌘P")
            Text("Pin")
            KKKeyCap("⌘⌫")
            Text("Delete")
            Spacer()
            KKKeyCap("Tab")
            Text("Filter")
            KKKeyCap("⎋")
            Text("Close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Data

    private func refresh() async {
        var newRows: [PickerRow] = []
        switch filter {
        case .snippets:
            newRows = controller.matchingSnippets(query).map { .snippet($0.snippet) }
        case .pinned:
            newRows = await controller.search(query, pinnedOnly: true).map { .item($0) }
        case .all:
            if !query.isEmpty {
                newRows = controller.matchingSnippets(query).prefix(3).map { .snippet($0.snippet) }
            }
            let items = await controller.search(query)
            newRows += items.map { PickerRow.item($0) }
        default:
            newRows = await controller.search(query, kinds: filter.kinds).map { .item($0) }
        }
        guard !Task.isCancelled else { return }
        rows = newRows
        if selectedID == nil || !rows.contains(where: { $0.id == selectedID }) {
            selectedID = rows.first?.id
        }
    }

    // MARK: Keys

    private func handle(_ key: KKFieldKey) -> Bool {
        switch key {
        case .up:
            move(-1)
        case .down:
            move(1)
        case .submit(let command, _):
            if let row = selectedRow {
                choose(row, plain: command)
            }
        case .cancel:
            if query.isEmpty {
                context.dismiss()
            } else {
                query = ""
            }
        case .tab(let backwards):
            let all = PickerFilter.allCases
            let index = all.firstIndex(of: filter) ?? 0
            filter = all[(index + (backwards ? all.count - 1 : 1)) % all.count]
        case .commandDelete, .deleteWhenEmpty:
            guard case .item(let item)? = selectedRow else { return false }
            delete(item)
        case .command(let character):
            if let digit = Int(character), (1...9).contains(digit) {
                guard digit <= rows.count else { return true }
                choose(rows[digit - 1], plain: false)
            } else if character == "p", case .item(let item)? = selectedRow {
                Task {
                    await controller.togglePin(item)
                    revision += 1
                }
            } else if character == "c", case .item(let item)? = selectedRow {
                Task { await controller.copy(item) }
                context.dismiss()
            } else {
                return false
            }
        }
        return true
    }

    private func move(_ step: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedRow?.id } ?? 0
        let next = min(max(current + step, 0), rows.count - 1)
        selectedID = rows[next].id
    }

    private func choose(_ row: PickerRow, plain: Bool) {
        context.dismiss()
        let controller = controller
        switch row {
        case .item(let item):
            if controller.settings[ClipboardSettings.pasteOnSelect] {
                Task { await controller.paste(item, plain: plain) }
            } else {
                Task { await controller.copy(item, plain: plain) }
            }
        case .snippet(let snippet):
            Task { await controller.pasteSnippet(snippet) }
        }
    }

    private func delete(_ item: ClipboardItem) {
        let index = rows.firstIndex { $0.id == PickerRow.item(item).id } ?? 0
        Task {
            await controller.delete(item)
            revision += 1
            if rows.indices.contains(index) {
                selectedID = rows[min(index, rows.count - 1)].id
            }
        }
    }

    /// Drag an item out (onto the Island's Shelf, Finder, another app).
    private func dragProvider(for row: PickerRow) -> NSItemProvider {
        switch row {
        case .item(let item):
            switch item.kind {
            case .files:
                return item.fileURLs.first.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
            case .image:
                return controller.imageURL(for: item).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
            case .link:
                if let url = item.url {
                    return NSItemProvider(object: url as NSURL)
                }
                return NSItemProvider(object: item.text as NSString)
            default:
                return NSItemProvider(object: item.text as NSString)
            }
        case .snippet(let snippet):
            return NSItemProvider(object: snippet.text as NSString)
        }
    }
}
