import CoreGraphics

/// How the tiles are arranged: a grid that fits on the screen, shrinking the tiles when
/// there are many windows and scrolling when even the smallest don't fit.
struct SwitcherLayout: Equatable {
    var columns: Int
    var rows: Int
    /// Rows that fit without scrolling.
    var visibleRows: Int
    var tileSize: CGSize
    /// The preview area inside a tile.
    var thumbnailSize: CGSize
    var panelSize: CGSize

    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    /// Inside a tile, around the preview and title.
    static let tileInset: CGFloat = 6
    static let titleHeight: CGFloat = 26
    /// Tiles without previews show a large app icon instead.
    static let iconOnlyWidth: CGFloat = 112
    static let iconSize: CGFloat = 64

    /// - Parameters:
    ///   - count: tiles to show.
    ///   - preferredTileWidth: the size setting's width; ignored without previews.
    ///   - area: the screen's visible size. The panel uses at most 90 % of its width
    ///     and 80 % of its height.
    static func make(count: Int, preferredTileWidth: CGFloat, showsPreviews: Bool, in area: CGSize) -> SwitcherLayout {
        let count = max(count, 1)
        let maxWidth = area.width * 0.9
        let maxHeight = area.height * 0.8
        var width = showsPreviews ? preferredTileWidth : iconOnlyWidth
        let minimumWidth = min(width, showsPreviews ? 130 : 90)

        func tile(_ width: CGFloat) -> (tile: CGSize, thumbnail: CGSize) {
            let thumbnailWidth = width - 2 * tileInset
            let thumbnailHeight = showsPreviews ? (thumbnailWidth * 0.625).rounded() : iconSize
            let tile = CGSize(width: width, height: thumbnailHeight + titleHeight + 2 * tileInset)
            return (tile, CGSize(width: thumbnailWidth, height: thumbnailHeight))
        }
        func fittingColumns(_ tileWidth: CGFloat) -> Int {
            max(1, min(count, Int((maxWidth - 2 * padding + spacing) / (tileWidth + spacing))))
        }
        func height(rows: Int, tileHeight: CGFloat) -> CGFloat {
            2 * padding + CGFloat(rows) * tileHeight + CGFloat(max(rows - 1, 0)) * spacing
        }

        var sizes = tile(width)
        var columns = fittingColumns(width)
        var rows = (count + columns - 1) / columns
        while height(rows: rows, tileHeight: sizes.tile.height) > maxHeight, width > minimumWidth {
            width = max(minimumWidth, width - 10)
            sizes = tile(width)
            columns = fittingColumns(width)
            rows = (count + columns - 1) / columns
        }
        let fitRows = Int((maxHeight - 2 * padding + spacing) / (sizes.tile.height + spacing))
        let visibleRows = min(rows, max(1, fitRows))
        let panelWidth = 2 * padding + CGFloat(columns) * width + CGFloat(columns - 1) * spacing
        return SwitcherLayout(
            columns: columns,
            rows: rows,
            visibleRows: visibleRows,
            tileSize: sizes.tile,
            thumbnailSize: sizes.thumbnail,
            panelSize: CGSize(width: panelWidth, height: height(rows: visibleRows, tileHeight: sizes.tile.height))
        )
    }

    /// The panel's frame, centred in `visibleFrame`, in whole points.
    func frame(centeredIn visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: (visibleFrame.midX - panelSize.width / 2).rounded(),
            y: (visibleFrame.midY - panelSize.height / 2).rounded(),
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
