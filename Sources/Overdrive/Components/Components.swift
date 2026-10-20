import SwiftUI

// MARK: - Surfaces

struct Backdrop: View {
    var accent: [Color]

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [accent[0].opacity(0.16), .clear], center: UnitPoint(x: 0.95, y: 0.0),
                           startRadius: 0, endRadius: 720)
            RadialGradient(colors: [accent[1].opacity(0.11), .clear], center: UnitPoint(x: 0.1, y: 1.05),
                           startRadius: 0, endRadius: 640)
        }
        .drawingGroup()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: accent)
    }
}

struct CardBackground: View {
    var highlight: Color?
    var cornerRadius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color.white.opacity(0.058), Color.white.opacity(0.022)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [(highlight ?? .white).opacity(highlight == nil ? 0.13 : 0.55),
                                            Color.white.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var highlight: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CardBackground(highlight: highlight))
    }
}

struct IconBadge: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        shape
            .fill(LinearGradient(colors: colors.map { $0.opacity(0.24) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(colors[0].opacity(0.35), lineWidth: 0.6))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let colors: [Color]
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 11) {
            IconBadge(symbol: symbol, colors: colors, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.rounded(14.5)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.bottom, 14)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String, colors: [Color]) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, colors: colors) { EmptyView() }
    }
}

struct PageScaffold<Trailing: View, Content: View>: View {
    let page: Page
    let subtitle: String
    /// Pages holding long lists pass false and scroll inside a window-height card instead: a card as
    /// tall as 500 rows gets one backing layer of half a gigabyte.
    var scrolls = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        if scrolls {
            ScrollView { stack }
        } else {
            stack.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 15) {
                IconBadge(symbol: page.symbol, colors: page.accent, size: 46)
                    .shadow(color: page.accent[1].opacity(0.45), radius: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(Theme.rounded(29, .bold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.bottom, 4)
            content()
        }
        .padding(.horizontal, 30)
        .padding(.top, 44)
        .padding(.bottom, scrolls ? 32 : 24)
    }
}

extension PageScaffold where Trailing == EmptyView {
    init(page: Page, subtitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(page: page, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Gauges and charts

struct RingGauge<Center: View>: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat = 12
    @ViewBuilder var center: () -> Center
    @State private var appeared = false

    var body: some View {
        // Sweeps in once per appearance. Live updates are deliberately not animated: a 120 Hz animation
        // on every sample re-lays out the window and costs ~15% CPU, which a monitor must not do.
        let clamped = appeared ? max(0, min(1, value.isFinite ? value : 0)) : 0
        let glow = lineWidth * 1.4
        ZStack {
            // Rasterized on the GPU as one layer; the sweep animation touches nothing but this layer.
            ZStack {
                Circle().stroke(Theme.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.004, clamped))
                    .stroke(
                        AngularGradient(colors: colors, center: .center, startAngle: .degrees(0),
                                        endAngle: .degrees(max(1, 360 * clamped))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colors.last!.opacity(0.55), radius: lineWidth * 0.7)
            }
            .padding(glow)
            .drawingGroup()
            .padding(-glow)
            center()
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { appeared = true } }
    }
}

struct ChartSeries: Identifiable {
    let id: String
    let points: [ChartPoint]
    let color: Color
    var fill = true
}

struct LiveChart: View {
    let series: [ChartSeries]
    let xDomain: ClosedRange<Int>
    var yMax: Double
    var height: CGFloat = 180
    var showAxis = true
    var format: (Double) -> String = { "\(Int($0))%" }

    private static let gridFractions: [Double] = [1, 0.75, 0.5, 0.25, 0]

    var body: some View {
        let top = max(yMax, 0.0001)
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if showAxis {
                    GridLines(fractions: Self.gridFractions)
                        .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                }
                ForEach(series) { s in
                    if s.fill {
                        TracePath(points: s.points, xDomain: xDomain, yMax: top, closed: true)
                            .fill(LinearGradient(colors: [s.color.opacity(0.32), s.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    TracePath(points: s.points, xDomain: xDomain, yMax: top, closed: false)
                        .stroke(s.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .drawingGroup()
            if showAxis {
                GeometryReader { geo in
                    ForEach(Self.gridFractions, id: \.self) { f in
                        Text(format(top * f))
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize()
                            .position(x: geo.size.width / 2, y: geo.size.height * (1 - f))
                    }
                }
                .frame(width: 52)
            }
        }
        .frame(height: height)
    }
}

/// One series as a single path: smoothed through segment midpoints, which never overshoots the data.
struct TracePath: Shape {
    let points: [ChartPoint]
    let xDomain: ClosedRange<Int>
    let yMax: Double
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let span = Double(max(1, xDomain.upperBound - xDomain.lowerBound))
        let pts = points.map { p in
            CGPoint(x: rect.minX + rect.width * CGFloat(Double(p.id - xDomain.lowerBound) / span),
                    y: rect.maxY - rect.height * CGFloat(min(max(p.value, 0), yMax) / yMax))
        }
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts[pts.count - 1])
        if closed {
            path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: rect.maxY))
            path.addLine(to: CGPoint(x: pts[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private struct GridLines: Shape {
    let fractions: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for f in fractions {
            let y = rect.maxY - rect.height * CGFloat(f)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

struct Sparkline: View {
    let series: Series
    let color: Color
    var yMax: Double = 100
    var height: CGFloat = 34

    var body: some View {
        // Scale to recent peaks (never below a quarter of the range) so a quiet Mac still draws a visible line.
        let top = min(yMax, max(yMax / 4, series.maxValue * 1.25))
        LiveChart(series: [ChartSeries(id: "s", points: series.points, color: color)],
                  xDomain: series.xDomain, yMax: top, height: height, showAxis: false)
    }
}

/// A rate chart whose ceiling snaps to a round number so the scale does not jitter every tick.
func niceCeiling(_ value: Double, minimum: Double) -> Double {
    let v = max(value * 1.15, minimum)
    let exponent = pow(10, floor(log10(v)))
    for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * exponent >= v {
        return step * exponent
    }
    return 10 * exponent
}

struct Segment: Identifiable {
    let id: String
    let value: Double
    let color: Color
}

struct SegmentBar: View {
    let segments: [Segment]
    let total: Double
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let visible = segments.filter { $0.value > 0 }
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, visible.count - 1)))
            HStack(spacing: gap) {
                ForEach(visible) { s in
                    RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                        .fill(LinearGradient(colors: [s.color, s.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: total > 0 ? usable * CGFloat(s.value / total) : 0)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: height * 0.3, style: .continuous).fill(Theme.track))
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
        }
    }
}

struct LegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var caption: String?
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
            Text(value).font(Theme.rounded(19)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.6))
    }
}

struct BigNumber: View {
    let value: String
    var unit: String?
    var size: CGFloat = 34
    var colors: [Color]?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(Theme.rounded(size, .bold)).monospacedDigit()
                .foregroundStyle(colors.map { AnyShapeStyle(LinearGradient(colors: $0, startPoint: .leading, endPoint: .trailing)) }
                                 ?? AnyShapeStyle(Theme.text))
            if let unit {
                Text(unit).font(Theme.rounded(size * 0.42, .semibold)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - Buttons

struct GlowButtonStyle: ButtonStyle {
    var colors: [Color]
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GlowLabel(configuration: configuration, colors: colors, compact: compact)
    }

    private struct GlowLabel: View {
        let configuration: Configuration
        let colors: [Color]
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 12 : 17)
                .padding(.vertical, compact ? 6 : 9)
                .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.6))
                .shadow(color: colors.last!.opacity(isEnabled ? (configuration.isPressed ? 0.25 : 0.5) : 0), radius: 12, y: 3)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.38)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.text
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GhostLabel(configuration: configuration, tint: tint, compact: compact)
    }

    private struct GhostLabel: View {
        let configuration: Configuration
        let tint: Color
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, compact ? 11 : 15)
                .padding(.vertical, compact ? 6 : 9)
                .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.1 : 0.065))))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6))
                .opacity(isEnabled ? 1 : 0.38)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}

struct IconButton: View {
    let symbol: String
    var tint: Color = Theme.secondary
    var help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Theme.text : tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0.05)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct Checkbox: View {
    @Binding var isOn: Bool
    var mixed = false
    var color: Color = Theme.cleanup[1]

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn || mixed ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isOn || mixed ? color.opacity(0.6) : Color.white.opacity(0.22), lineWidth: 1))
                .frame(width: 17, height: 17)
                .overlay(
                    Image(systemName: mixed && !isOn ? "minus" : "checkmark")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(.white)
                        .opacity(isOn || mixed ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}

struct SegmentedTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var colors: [Color]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button { withAnimation(.snappy) { selection = value } } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == value ? .white : Theme.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background {
                            if selection == value {
                                Capsule().fill(LinearGradient(colors: colors.map { $0.opacity(0.55) }, startPoint: .leading, endPoint: .trailing))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 170)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6))
    }
}
