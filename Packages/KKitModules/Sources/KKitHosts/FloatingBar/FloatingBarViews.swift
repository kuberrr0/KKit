import AppKit
import KKitCore
import KKitUI
import SwiftUI

/// Fixed sizes, shared by the view and the host (which sizes the panel to fit).
enum FloatingBarLayout {
    static let width: CGFloat = 680
    static let previewWidth: CGFloat = 280
    static let headerHeight: CGFloat = 54
    static let rowHeight: CGFloat = 40
    static let sectionHeight: CGFloat = 24
    static let footerHeight: CGFloat = 30
    static let messageHeight: CGFloat = 30
    static let listPadding: CGFloat = 6
    static let maxVisibleRows = 8
    static let hintHeight: CGFloat = 130
    static let noResultsHeight: CGFloat = 56
    static let modeHeaderHeight: CGFloat = 40
    static let actionRowHeight: CGFloat = 28

    @MainActor
    static func size(for model: FloatingBarModel) -> CGSize {
        if let mode = model.activeMode {
            return CGSize(width: width, height: modeHeaderHeight + mode.mode.height)
        }
        var height = headerHeight + footerHeight
        if model.message != nil {
            height += messageHeight
        }
        let rows = model.rows
        if rows.isEmpty {
            if model.isEmptyState {
                height += hintHeight
            } else if model.message == nil {
                height += noResultsHeight
            }
        } else {
            height += listHeight(rows)
        }
        // The preview (Tab) takes its width from the results; the bar never widens.
        if model.showsPreview {
            height = max(height, headerHeight + footerHeight + 6 * rowHeight)
        }
        if model.actionsShown {
            let menu = CGFloat(min(model.currentActions.count, 10)) * actionRowHeight + 44
            height = max(height, headerHeight + footerHeight + menu + 12)
        }
        return CGSize(width: width, height: height)
    }

    static func listHeight(_ rows: [FloatingBarRow]) -> CGFloat {
        let visible = rows.prefix(maxVisibleRows)
        var sections = 0
        var previous: FloatingBarRow.Section?
        for row in visible {
            if let section = row.section, section != previous {
                sections += 1
            }
            previous = row.section
        }
        return CGFloat(visible.count) * rowHeight + CGFloat(sections) * sectionHeight + 2 * listPadding
    }
}

extension ResultKind {
    /// The ↵ label when a result doesn't give one.
    var defaultActionTitle: String {
        switch self {
        case .command, .custom: String(localized: "Run")
        case .application, .file, .url: String(localized: "Open")
        case .text: String(localized: "Copy")
        }
    }
}

/// A prefix shown in the empty bar's hint.
struct PrefixHint: Identifiable {
    let id: String
    let prefix: String
    let name: String
}

/// What the view asks of the host.
@MainActor
struct FloatingBarViewActions {
    var run: @MainActor (FloatingBarRow, Bool) -> Void
    var runAction: @MainActor (ResultAction) -> Void
    var modeContext: @MainActor (ActiveMode) -> FloatingBarModeContext
    var prefixes: @MainActor () -> [PrefixHint]
    /// Leaves a mode for search, whichever way the mode was opened.
    var backToSearch: @MainActor () -> Void
}

struct FloatingBarRootView: View {
    let model: FloatingBarModel
    let actions: FloatingBarViewActions

    var body: some View {
        let size = FloatingBarLayout.size(for: model)
        ZStack(alignment: .top) {
            KKVisualEffect(material: .popover, cornerRadius: KKRadius.panel)
            if let mode = model.activeMode {
                ModeContainer(mode: mode, context: actions.modeContext(mode), backToSearch: actions.backToSearch)
                    .id(mode.id)
            } else {
                searchContent
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: KKRadius.panel, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            FloatingBarHeader(model: model)
            Divider()
            if let message = model.message {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, KKSpacing.l)
                    .frame(maxWidth: .infinity, minHeight: FloatingBarLayout.messageHeight, alignment: .leading)
            }
            HStack(spacing: 0) {
                results
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsPreview {
                    Divider()
                    FloatingBarPreview(result: model.selectedResult)
                        .frame(width: FloatingBarLayout.previewWidth)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            FloatingBarFooter(model: model)
        }
        .overlay(alignment: .bottomTrailing) {
            if model.actionsShown {
                FloatingBarActionsMenu(
                    actions: model.currentActions,
                    selection: model.actionSelection,
                    run: actions.runAction
                )
                .padding(.trailing, KKSpacing.m)
                .padding(.bottom, FloatingBarLayout.footerHeight + KKSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.rows.isEmpty {
            if model.isEmptyState {
                FloatingBarEmptyHint(prefixes: actions.prefixes())
            } else if model.message == nil {
                Text(model.isSearching ? String(localized: "Searching…") : String(localized: "No results"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        } else {
            FloatingBarResultList(model: model, run: actions.run)
        }
    }
}

struct FloatingBarHeader: View {
    let model: FloatingBarModel

    var body: some View {
        HStack(spacing: KKSpacing.m) {
            if let pending = model.pending {
                Label(CommandSearchProvider.trimmingEllipsis(pending.title), systemImage: pending.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, KKSpacing.s)
                    .padding(.vertical, KKSpacing.xs)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .fixedSize()
            } else {
                Image(systemName: model.scopedProvider?.provider.symbol ?? "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            FloatingBarSearchField(
                text: Binding(get: { model.query }, set: { model.query = $0 }),
                placeholder: model.pending?.hint ?? String(localized: "Search or type a command…"),
                focusToken: model.focusToken
            )
            if let scope = model.scopedProvider {
                Text(scope.provider.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, KKSpacing.s)
                    .padding(.vertical, KKSpacing.xxs)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            KKKeyCap("⌘K")
        }
        .padding(.horizontal, KKSpacing.l)
        .frame(height: FloatingBarLayout.headerHeight)
    }
}

struct FloatingBarResultList: View {
    let model: FloatingBarModel
    let run: @MainActor (FloatingBarRow, Bool) -> Void

    var body: some View {
        let rows = model.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if let section = row.section, index == 0 || rows[index - 1].section != section {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, KKSpacing.l)
                                .frame(maxWidth: .infinity, minHeight: FloatingBarLayout.sectionHeight, alignment: .leading)
                        }
                        FloatingBarResultRow(row: row, isSelected: index == model.selection)
                            .id(row.id)
                            .onTapGesture {
                                model.select(row.id)
                                run(row, false)
                            }
                    }
                }
                .padding(.vertical, FloatingBarLayout.listPadding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, selection in
                guard rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }
}

struct FloatingBarResultRow: View {
    let row: FloatingBarRow
    let isSelected: Bool

    var body: some View {
        let result = row.result
        HStack(spacing: KKSpacing.m) {
            ResultIconView(icon: result.icon)
                .frame(width: 24, height: 24)
            HStack(alignment: .firstTextBaseline, spacing: KKSpacing.s) {
                Text(result.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: KKSpacing.s)
            if let accessory = result.accessory {
                Text(accessory)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, KKSpacing.m)
        .frame(height: FloatingBarLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: KKRadius.row - 2, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .padding(.horizontal, KKSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

struct ResultIconView: View {
    let icon: ResultIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        case .glyph(let text):
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.5)
        }
    }
}

struct FloatingBarEmptyHint: View {
    let prefixes: [PrefixHint]

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            Text("Search apps, files, commands, System Settings and the web. ⌘K on a result shows more actions, like Add to Favourites.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: KKSpacing.m, alignment: .leading)],
                alignment: .leading,
                spacing: KKSpacing.xs
            ) {
                ForEach(prefixes) { hint in
                    HStack(spacing: KKSpacing.xs) {
                        KKKeyCap(hint.prefix.trimmingCharacters(in: .whitespaces))
                        Text(hint.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(KKSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FloatingBarFooter: View {
    let model: FloatingBarModel

    var body: some View {
        HStack(spacing: KKSpacing.m) {
            if let result = model.selectedResult {
                hint("↵", model.actionsShown ? String(localized: "Choose") : (result.actionTitle ?? result.kind.defaultActionTitle))
                if !model.actionsShown {
                    hint("⌘↵", String(localized: "Keep Open"))
                }
                hint("⌘K", String(localized: "Actions"))
            }
            hint("Tab", model.showsPreview ? String(localized: "Hide Preview") : String(localized: "Preview"))
            Spacer()
            if model.isSearching {
                ProgressView()
                    .controlSize(.mini)
            }
            hint("⎋", model.actionsShown || model.pending != nil ? String(localized: "Back") : String(localized: "Close"))
        }
        .padding(.horizontal, KKSpacing.l)
        .frame(height: FloatingBarLayout.footerHeight)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: KKSpacing.xs) {
            KKKeyCap(key)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct FloatingBarActionsMenu: View {
    let actions: [ResultAction]
    let selection: Int
    let run: @MainActor (ResultAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, KKSpacing.s + 2)
                .frame(height: 24, alignment: .leading)
            ForEach(Array(actions.prefix(10).enumerated()), id: \.element.id) { index, action in
                HStack(spacing: KKSpacing.s) {
                    Image(systemName: action.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 18)
                    Text(action.title)
                        .lineLimit(1)
                    Spacer(minLength: KKSpacing.s)
                    if index == 0 {
                        KKKeyCap("↵")
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, KKSpacing.s + 2)
                .frame(height: FloatingBarLayout.actionRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: KKRadius.control, style: .continuous)
                        .fill(index == selection ? Color.accentColor.opacity(0.22) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { run(action) }
                .accessibilityAddTraits(index == selection ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(KKSpacing.xs + 2)
        .frame(width: 300)
        .background(KKVisualEffect(material: .menu, cornerRadius: KKRadius.row))
        .overlay(
            RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// The preview pane (Tab): the result's own preview, or a summary by kind.
struct FloatingBarPreview: View {
    let result: SearchResult?

    var body: some View {
        Group {
            if let result {
                if let preview = result.preview {
                    preview()
                } else {
                    defaultPreview(result)
                }
            } else {
                Text("Nothing selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(KKSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func defaultPreview(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            ResultIconView(icon: result.icon)
                .frame(width: 44, height: 44)
            Text(result.title)
                .font(.headline)
                .lineLimit(3)
            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            ForEach(Self.details(for: result)) { detail in
                VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                    Text(detail.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(detail.value)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .truncationMode(.middle)
                }
            }
        }
    }

    struct Detail: Identifiable {
        let label: String
        let value: String

        var id: String { label }

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    static func details(for result: SearchResult) -> [Detail] {
        var details: [Detail] = []
        switch result.kind {
        case .command(let id, let argument):
            details.append(Detail(String(localized: "Command"), id.rawValue))
            if let argument {
                details.append(Detail(String(localized: "Value"), CommandArgumentParser.display(argument)))
            }
            let link = KKitLink.run(id, value: argument.map { Self.rawValue($0) })
            details.append(Detail(String(localized: "Link"), link.url.absoluteString))
        case .application(let url), .file(let url):
            details.append(Detail(String(localized: "Where"), (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        case .url(let url):
            details.append(Detail(String(localized: "Address"), url.absoluteString))
        case .text(let text):
            details.append(Detail(String(localized: "Copies"), text))
        case .custom:
            break
        }
        if let accessory = result.accessory {
            details.append(Detail(String(localized: "Status"), accessory))
        }
        return details
    }

    /// An argument as a `kkit://` link's `value`.
    static func rawValue(_ argument: CommandArgument) -> String {
        switch argument {
        case .percent(let value):
            value.rounded() == value ? String(Int(value)) : String(value)
        case .duration(let duration):
            "\(duration.components.seconds)s"
        case .text(let text), .choice(let text):
            text
        }
    }
}

/// A feature's mode with a small title bar.
struct ModeContainer: View {
    let mode: ActiveMode
    let context: FloatingBarModeContext
    let backToSearch: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KKSpacing.s) {
                Button {
                    backToSearch()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Back to search"))
                .accessibilityLabel(String(localized: "Back to search"))
                Image(systemName: mode.mode.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(mode.mode.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    context.exit()
                } label: {
                    HStack(spacing: KKSpacing.xs) {
                        KKKeyCap("⎋")
                        Text(mode.returnsToSearch ? String(localized: "Back") : String(localized: "Close"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, KKSpacing.l)
            .frame(height: FloatingBarLayout.modeHeaderHeight)
            Divider()
            mode.mode.makeView(context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
