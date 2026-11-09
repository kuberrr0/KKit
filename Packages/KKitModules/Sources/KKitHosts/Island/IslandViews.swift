import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

/// Where an Island panel sits: notch size, or a virtual notch on screens without one.
struct IslandGeometry: Equatable {
    var displayID: UInt32
    var hasNotch: Bool
    /// Width of the real notch, or the gap between the ears of the pill.
    var centerWidth: CGFloat
    /// Height of the notch, or of the menu bar on screens without a notch.
    var barHeight: CGFloat

    /// The black "shoulders" that blend the Island into the top edge on notch screens.
    var shoulder: CGFloat { hasNotch ? 6 : 0 }
}

/// What the Island shows right now.
enum IslandMode: Hashable {
    case hidden
    case idle
    case compact
    case hud
    case banner
    case expanded
    /// Something is being dragged to the Island: one zone per drop target.
    case drop
}

/// Actions the panel's view sends back to the host.
@MainActor
struct IslandViewActions {
    var hoverChanged: @MainActor (Bool) -> Void
    var tapped: @MainActor (IslandModel.Entry?) -> Void
    var selectPage: @MainActor (String) -> Void
    var dropEntered: @MainActor () -> Void
    var dropExited: @MainActor () -> Void
    var dropHovered: @MainActor (String?) -> Void
    var drop: @MainActor (String?, [NSItemProvider]) -> Void
}

/// The black shape and its content, top-centred in the Island panel.
struct IslandRootView: View {
    let model: IslandModel
    let geometry: IslandGeometry
    let isEnabled: @MainActor () -> Bool
    let pages: @MainActor () -> [IslandPageItem]
    let dropZones: @MainActor () -> [IslandDropZoneItem]
    let actions: IslandViewActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let compactEar: CGFloat = 76
    static let hudEar: CGFloat = 116
    static let bannerExtra: CGFloat = 30
    static let expandedContentHeight: CGFloat = 168
    static let expandedMinWidth: CGFloat = 480
    static let dropHeight: CGFloat = 96

    var body: some View {
        let pages = self.pages()
        let zones = dropZones()
        let mode = mode(pages: pages, zones: zones)
        let size = size(for: mode)
        VStack(spacing: 0) {
            island(mode: mode, size: size, pages: pages, zones: zones)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Mode and size

    private func mode(pages: [IslandPageItem], zones: [IslandDropZoneItem]) -> IslandMode {
        guard isEnabled() else { return geometry.hasNotch ? .idle : .hidden }
        if model.dropDisplay == geometry.displayID, !zones.isEmpty {
            return .drop
        }
        if model.expandedDisplay == geometry.displayID, !pages.isEmpty {
            return .expanded
        }
        if let hud = model.hud {
            return hud.hud.title == nil ? .hud : .banner
        }
        if model.compactEntry != nil {
            return .compact
        }
        return geometry.hasNotch ? .idle : .hidden
    }

    private func size(for mode: IslandMode) -> CGSize {
        let center = geometry.centerWidth
        let height = geometry.barHeight
        let shoulders = geometry.shoulder * 2
        switch mode {
        case .hidden:
            return CGSize(width: center, height: 0)
        case .idle:
            return CGSize(width: center + shoulders, height: height)
        case .compact:
            return CGSize(width: center + 2 * Self.compactEar + shoulders, height: height)
        case .hud:
            return CGSize(width: center + 2 * Self.hudEar + shoulders, height: height)
        case .banner:
            return CGSize(width: center + 2 * Self.hudEar + shoulders, height: height + Self.bannerExtra)
        case .expanded:
            return CGSize(
                width: max(center + 2 * 150, Self.expandedMinWidth) + shoulders,
                height: height + Self.expandedContentHeight
            )
        case .drop:
            return CGSize(
                width: max(center + 2 * 150, Self.expandedMinWidth) + shoulders,
                height: height + Self.dropHeight
            )
        }
    }

    /// The width the drop zones share, inside the padding.
    private func dropContentWidth(_ size: CGSize) -> CGFloat {
        size.width - 2 * geometry.shoulder - 2 * KKSpacing.l
    }

    // MARK: Island

    private func island(mode: IslandMode, size: CGSize, pages: [IslandPageItem], zones: [IslandDropZoneItem]) -> some View {
        let radius: CGFloat = (mode == .expanded || mode == .drop) ? 26 : (mode == .banner ? 18 : min(geometry.barHeight / 2, 12))
        let shape = IslandShape(bottomRadius: radius, shoulder: geometry.shoulder)
        let dropSize = self.size(for: .drop)
        return ZStack(alignment: .top) {
            Color.black
            content(mode: mode, size: size, pages: pages, zones: zones)
                .padding(.horizontal, geometry.shoulder)
                .transition(.opacity)
                .id(mode)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .onDrop(of: IslandHost.dropTypes, delegate: IslandDropDelegate(
            zones: zones.map(\.id),
            leading: (size.width - dropSize.width) / 2 + geometry.shoulder + KKSpacing.l,
            width: dropContentWidth(dropSize),
            actions: actions
        ))
        .shadow(color: .black.opacity(mode == .expanded ? 0.45 : 0), radius: 12, y: 6)
        .opacity(mode == .hidden ? 0 : 1)
        .onHover { actions.hoverChanged($0) }
        .onTapGesture {
            if mode != .expanded {
                actions.tapped(model.compactEntry)
            }
        }
        .animation(KKMotion.adapted(KKMotion.island, reduceMotion: reduceMotion), value: mode)
        .animation(KKMotion.adapted(KKMotion.island, reduceMotion: reduceMotion), value: size.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Island"))
    }

    @ViewBuilder
    private func content(mode: IslandMode, size: CGSize, pages: [IslandPageItem], zones: [IslandDropZoneItem]) -> some View {
        switch mode {
        case .drop:
            IslandDropAreaView(
                zones: zones,
                hovered: model.hoveredDropZone,
                barHeight: geometry.barHeight,
                centerWidth: geometry.centerWidth
            )
        case .hidden, .idle:
            Color.clear
        case .compact:
            if let entry = model.compactEntry {
                ears(
                    width: Self.compactEar,
                    leading: entry.activity.compactLeading,
                    trailing: entry.activity.compactTrailing
                )
                .accessibilityLabel(Text(entry.activity.title))
            }
        case .hud, .banner:
            if let hud = model.hud?.hud {
                VStack(spacing: 0) {
                    ears(
                        width: Self.hudEar,
                        leading: AnyView(HUDSymbol(hud: hud)),
                        trailing: AnyView(HUDTrailing(hud: hud))
                    )
                    if mode == .banner, let title = hud.title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, KKSpacing.m)
                            .frame(maxWidth: .infinity, minHeight: Self.bannerExtra - 4, alignment: .center)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        case .expanded:
            IslandExpandedView(
                model: model,
                geometry: geometry,
                width: size.width - geometry.shoulder * 2,
                pages: pages,
                selectPage: actions.selectPage
            )
        }
    }

    /// Two ears either side of the notch.
    private func ears(width: CGFloat, leading: AnyView?, trailing: AnyView?) -> some View {
        HStack(spacing: 0) {
            (leading ?? AnyView(EmptyView()))
                .frame(width: width - KKSpacing.m, alignment: .leading)
                .padding(.leading, KKSpacing.m)
            Spacer(minLength: geometry.centerWidth)
            (trailing ?? AnyView(EmptyView()))
                .frame(width: width - KKSpacing.m, alignment: .trailing)
                .padding(.trailing, KKSpacing.m)
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(height: geometry.barHeight)
    }
}

/// Hands drags over the Island to the host, and works out which zone is under the
/// cursor from its position (zones share the width equally).
struct IslandDropDelegate: DropDelegate {
    let zones: [String]
    /// Where the zones start, from the Island's left edge.
    let leading: CGFloat
    let width: CGFloat
    let actions: IslandViewActions

    private func zone(at location: CGPoint) -> String? {
        guard let index = IslandDropZoneItem.index(at: location.x - leading, width: width, count: zones.count) else {
            return nil
        }
        return zones[index]
    }

    func validateDrop(info: DropInfo) -> Bool {
        !zones.isEmpty && info.hasItemsConforming(to: IslandHost.dropTypes)
    }

    func dropEntered(info: DropInfo) {
        actions.dropEntered()
        actions.dropHovered(zone(at: info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        actions.dropHovered(zone(at: info.location))
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        actions.dropExited()
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: IslandHost.dropTypes)
        guard !providers.isEmpty else { return false }
        actions.drop(zone(at: info.location), providers)
        return true
    }
}

/// The drop area: one tile per zone, the one under the cursor lit up.
struct IslandDropAreaView: View {
    let zones: [IslandDropZoneItem]
    let hovered: String?
    let barHeight: CGFloat
    let centerWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Drop to…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: centerWidth)
            }
            .padding(.horizontal, KKSpacing.l)
            .frame(height: barHeight)
            HStack(spacing: KKSpacing.s) {
                ForEach(zones) { item in
                    let isHovered = item.id == hovered
                    VStack(spacing: KKSpacing.xs) {
                        Image(systemName: item.zone.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text(item.zone.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isHovered ? Color.black : Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                            .fill(isHovered ? Color.white : Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .animation(KKMotion.quick, value: isHovered)
                    .accessibilityLabel(Text(item.zone.title))
                }
            }
            .padding(.horizontal, KKSpacing.l)
            .padding(.bottom, KKSpacing.m)
            .padding(.top, KKSpacing.xs)
        }
    }
}

/// The left ear of a HUD.
struct HUDSymbol: View {
    let hud: IslandHUD

    var body: some View {
        Image(systemName: hud.symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(hud.tint.color)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The right ear of a HUD: a level bar and/or short detail.
struct HUDTrailing: View {
    let hud: IslandHUD

    var body: some View {
        HStack(spacing: KKSpacing.s) {
            if let level = hud.level {
                KKLevelBar(value: level, tint: hud.tint.color)
                    .frame(height: 5)
            }
            if let detail = hud.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
            }
        }
    }
}

extension IslandHUD.HUDTint {
    var color: Color {
        switch self {
        case .normal: .white
        case .accent: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// The expanded Island: a header row around the notch (page title on the left, page
/// picker on the right), then the selected page.
struct IslandExpandedView: View {
    let model: IslandModel
    let geometry: IslandGeometry
    let width: CGFloat
    let pages: [IslandPageItem]
    let selectPage: @MainActor (String) -> Void

    var body: some View {
        let selected = pages.first { $0.id == model.selectedPageID } ?? pages.first
        let side = max(0, (width - geometry.centerWidth) / 2 - KKSpacing.l)
        VStack(spacing: 0) {
            // A HUD (volume, brightness, …) replaces the header row around the notch
            // while it's up, so changes made while expanded (scrolling on the Island,
            // the volume keys) stay visible.
            ZStack {
                if let hud = model.hud?.hud {
                    ExpandedHUDHeader(hud: hud, side: side, centerWidth: geometry.centerWidth)
                        .transition(.opacity)
                } else {
                    header(selected: selected, side: side)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.hud == nil)
            .frame(height: geometry.barHeight)

            Group {
                if let selected {
                    selected.makeView()
                } else {
                    Text("Nothing here yet")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, KKSpacing.l + KKSpacing.xs)
            .padding(.top, KKSpacing.s)
            .padding(.bottom, KKSpacing.m)
        }
    }

    /// The page title on the left of the notch and the page picker on the right.
    private func header(selected: IslandPageItem?, side: CGFloat) -> some View {
        HStack(spacing: 0) {
            if let selected {
                Label(selected.title, systemImage: selected.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: side, alignment: .leading)
            }
            Spacer(minLength: geometry.centerWidth)
            HStack(spacing: KKSpacing.xs) {
                ForEach(pages) { page in
                    Button {
                        selectPage(page.id)
                    } label: {
                        Image(systemName: page.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 18)
                            .foregroundStyle(page.id == selected?.id ? Color.white : Color.white.opacity(0.45))
                            .background(
                                Capsule().fill(Color.white.opacity(page.id == selected?.id ? 0.18 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(page.title)
                    .accessibilityLabel(Text(page.title))
                    .accessibilityAddTraits(page.id == selected?.id ? .isSelected : [])
                }
            }
            .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, KKSpacing.l)
        .frame(height: geometry.barHeight)
    }
}

/// A HUD in the expanded Island's header row: symbol (and title) left of the notch,
/// level bar and detail right of it, like the compact HUD.
struct ExpandedHUDHeader: View {
    let hud: IslandHUD
    let side: CGFloat
    let centerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: KKSpacing.s) {
                HUDSymbol(hud: hud)
                if let title = hud.title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: side, alignment: .leading)
            Spacer(minLength: centerWidth)
            HUDTrailing(hud: hud)
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, KKSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// The Island's outline: flat top, rounded bottom corners, and small concave
/// "shoulders" at the top so it melts into the screen edge like the notch.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set {
            bottomRadius = newValue.first
            shoulder = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 4)
        let r = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
