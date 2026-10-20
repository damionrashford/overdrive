import OverdriveCore
import SwiftUI

/// Squarified treemap of a folder's children. Each tile is a real view so hovering and clicking work.
struct TreemapView: View {
    let nodes: [SpaceNode]
    let total: UInt64
    let colors: [Color]
    var onOpen: (SpaceNode) -> Void
    var onHover: (SpaceNode?) -> Void

    var body: some View {
        GeometryReader { geo in
            let tiles = Squarify.layout(values: nodes.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(nodes, tiles)), id: \.0.id) { node, rect in
                    Tile(node: node, rect: rect, fraction: total > 0 ? Double(node.size) / Double(total) : 0,
                         colors: colors, onOpen: onOpen, onHover: onHover)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder map")
    }

    private struct Tile: View {
        let node: SpaceNode
        let rect: CGRect
        let fraction: Double
        let colors: [Color]
        let onOpen: (SpaceNode) -> Void
        let onHover: (SpaceNode?) -> Void
        @State private var hovering = false

        var body: some View {
            let inset: CGFloat = 1.5
            let shade = 0.25 + 0.55 * min(1, fraction * 3)
            let color = node.isSummary ? Theme.tertiary : (node.isDirectory && !node.isPackage ? colors[1] : colors[0])
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(hovering ? shade + 0.2 : shade))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.background.opacity(0.6), lineWidth: 1))
                if rect.width > 56, rect.height > 30 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        if rect.height > 44 {
                            Text(Fmt.storage(node.size)).font(.system(size: 10).monospacedDigit()).opacity(0.8)
                        }
                    }
                    .foregroundStyle(Theme.onAccent)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(6)
                }
            }
            .frame(width: max(0, rect.width - inset * 2), height: max(0, rect.height - inset * 2))
            .offset(x: rect.minX + inset, y: rect.minY + inset)
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                onHover(h ? node : nil)
            }
            .onTapGesture { onOpen(node) }
            .help("\(node.name) · \(Fmt.storage(node.size))")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(node.name), \(Fmt.storage(node.size))")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Bruls, Huizing and van Wijk's squarified layout: rows of tiles with aspect ratios kept near 1.
enum Squarify {
    static func layout(values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let scale = bounds.width * bounds.height / total
        var rects = [CGRect](repeating: .zero, count: values.count)
        var remaining = bounds
        var index = 0
        while index < values.count {
            // Grow a row while it keeps the worst aspect ratio from getting worse.
            let side = min(remaining.width, remaining.height)
            var row: [Int] = [index]
            var rowArea = values[index] * scale
            var next = index + 1
            while next < values.count {
                let candidate = rowArea + values[next] * scale
                if worst(row.map { values[$0] * scale } + [values[next] * scale], side: side, area: candidate)
                    <= worst(row.map { values[$0] * scale }, side: side, area: rowArea) {
                    row.append(next)
                    rowArea = candidate
                    next += 1
                } else {
                    break
                }
            }
            // Lay the row along the shorter side.
            if remaining.width >= remaining.height {
                let width = side > 0 ? rowArea / side : 0
                var y = remaining.minY
                for i in row {
                    let h = width > 0 ? values[i] * scale / width : 0
                    rects[i] = CGRect(x: remaining.minX, y: y, width: width, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(0, remaining.width - width), height: remaining.height)
            } else {
                let height = side > 0 ? rowArea / side : 0
                var x = remaining.minX
                for i in row {
                    let w = height > 0 ? values[i] * scale / height : 0
                    rects[i] = CGRect(x: x, y: remaining.minY, width: w, height: height)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(0, remaining.height - height))
            }
            index = next
        }
        return rects
    }

    private static func worst(_ areas: [Double], side: Double, area: Double) -> Double {
        guard side > 0, area > 0, let maxA = areas.max(), let minA = areas.min(), minA > 0 else { return .infinity }
        let s2 = side * side
        let a2 = area * area
        return max(s2 * maxA / a2, a2 / (s2 * minA))
    }
}
