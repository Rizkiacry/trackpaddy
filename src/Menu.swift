import AppKit
import Cocoa
import SwiftUI

enum Theme {
    static let bg = Color(red: 27 / 255, green: 39 / 255, blue: 25 / 255)
    static let bgTop = Color(red: 30 / 255, green: 54 / 255, blue: 36 / 255)
    static let panel = Color(red: 32 / 255, green: 52 / 255, blue: 36 / 255)
    static let panelHi = Color(red: 43 / 255, green: 53 / 255, blue: 50 / 255)
    static let stroke = Color(red: 51 / 255, green: 62 / 255, blue: 59 / 255)
    static let green = Color(red: 102 / 255, green: 255 / 255, blue: 102 / 255)
    static let greenDark = Color(red: 79 / 255, green: 204 / 255, blue: 79 / 255)
    static let text = Color(red: 235 / 255, green: 243 / 255, blue: 239 / 255)
    static let textDim = Color(red: 140 / 255, green: 154 / 255, blue: 148 / 255)
}
enum Torus {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Torus-Bold"
        case .semibold, .medium: name = "Torus-SemiBold"
        case .light, .ultraLight, .thin: name = "Torus-Light"
        default: name = "Torus-Regular"
        }
        return .custom(name, size: size)
    }
}

enum Corner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

struct RoundedCornersShape: Shape {
    var radius: CGFloat
    var corners: Set<Corner>

    func path(in rect: CGRect) -> Path {
        let tl = corners.contains(.topLeading) ? radius : 0
        let tr = corners.contains(.topTrailing) ? radius : 0
        let bl = corners.contains(.bottomLeading) ? radius : 0
        let br = corners.contains(.bottomTrailing) ? radius : 0

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(
            center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct GridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1..<3 {
            let x = rect.width * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return p
    }
}

struct NumberSlider<V: BinaryFloatingPoint>: View {
    @Binding var value: V
    let range: ClosedRange<V>

    private let trackHeight: CGFloat = 5
    private let knob: CGFloat = 14

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let lo = Double(range.lowerBound)
            let hi = Double(range.upperBound)
            let span = max(hi - lo, .ulpOfOne)
            let usable = max(geo.size.width - knob, 0)
            let frac = min(max((Double(value) - lo) / span, 0), 1)
            let x = knob / 2 + usable * frac

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.panel)
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.green, Theme.greenDark],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: x, height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Theme.green, lineWidth: 2))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: dragging ? 3 : 1, y: 1)
                    .scaleEffect(dragging ? 1.18 : 1)
                    .position(x: x, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let f = min(max((v.location.x - knob / 2) / max(usable, .ulpOfOne), 0), 1)
                        value = V(lo + f * span)
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: dragging)
        }
        .frame(height: knob)
    }
}

struct NumberField<V: BinaryFloatingPoint, F: Hashable>: View {
    let title: String
    @Binding var value: V
    var format: String = "%g"
    var focusedField: FocusState<F?>.Binding
    var fieldId: F
    var range: ClosedRange<V>? = nil
    var showSlider: Bool = false

    @State private var text: String = ""

    private var isFocused: Bool {
        focusedField.wrappedValue == fieldId
    }

    private func clamp(_ v: V) -> V {
        guard let range = range else { return v }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Torus.font(11, weight: .medium))
                .foregroundColor(Theme.text)
            Spacer()
            if showSlider, let range = range {
                NumberSlider(value: $value, range: range)
                    .frame(width: 90)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Torus.font(12, weight: .semibold))
                .foregroundColor(isFocused ? Theme.text : Theme.textDim)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isFocused ? Theme.green : Theme.stroke, lineWidth: 1)
                )
                .focused(focusedField, equals: fieldId)
                .onAppear {
                    text = String(format: format, Double(value))
                }
                .onChange(of: text) { _, newValue in
                    if let d = Double(newValue) {
                        value = clamp(V(d))
                    }
                }
                .onChange(of: value) { _, newValue in
                    if !isFocused {
                        text = String(format: format, Double(newValue))
                    }
                }
                .onSubmit {
                    text = String(format: format, Double(value))
                }
        }
    }
}

struct TPRegionEditor: View {
    @Binding var rect: CGRect
    let aspect: CGFloat
    let title: String
    let glyph: String
    let usePercentage: Bool

    enum FocusedField: Hashable {
        case x
        case y
        case width
        case height
    }
    @FocusState private var focusedField: FocusedField?

    @State private var startRect: CGRect? = nil
    private let minSize: CGFloat = 0.1
    private let handle: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: glyph)
                    .font(.system(size: 10))
                Text(title)
                    .font(Torus.font(11, weight: .semibold))
                Spacer()
                // Text(
                //     String(
                //         format: usePercentage ? "%.0f%%×%.0f%%" : "%.0f×%.0f",
                //         usePercentage ? rect.width * 100 : rect.width,
                //         usePercentage ? rect.height * 100 : rect.height)
                // )
                // .font(Torus.font(9, weight: .medium))
                // .foregroundColor(Theme.green)
            }
            .foregroundColor(Theme.textDim)

            HStack {
                GeometryReader { geo in
                    let pad: CGFloat = handle / 2 + 1
                    let inner = CGSize(
                        width: max(0, geo.size.width - pad * 2),
                        height: max(0, geo.size.height - pad * 2))
                    let box = fitted(inner, aspect)
                    let offX = pad + (inner.width - box.width) / 2
                    let offY = pad + (inner.height - box.height) / 2
                    let r = CGRect(
                        x: offX + rect.minX * box.width,
                        y: offY + rect.minY * box.height,
                        width: rect.width * box.width,
                        height: rect.height * box.height)

                    ZStack(alignment: .topLeading) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.bg.opacity(0.6))
                            GridShape().stroke(Theme.stroke.opacity(0.5), lineWidth: 0.5)
                            RoundedRectangle(cornerRadius: 4).strokeBorder(
                                Theme.stroke, lineWidth: 1)
                        }
                        .frame(width: box.width, height: box.height)
                        .position(x: offX + box.width / 2, y: offY + box.height / 2)

                        ZStack {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.green.opacity(0.2))
                            RoundedRectangle(cornerRadius: 3).strokeBorder(
                                Theme.green, lineWidth: 1.5)
                        }
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .gesture(dragGesture(box: box))

                        handleCircle(.topLeading, r: r, box: box)
                        handleCircle(.topTrailing, r: r, box: box)
                        handleCircle(.bottomLeading, r: r, box: box)
                        handleCircle(.bottomTrailing, r: r, box: box)
                    }
                }
                .frame(height: 100)
                VStack {
                    NumberField(
                        title: "X", value: $rect.origin.x, focusedField: $focusedField,
                        fieldId: .x, range: 0...1)
                    NumberField(
                        title: "Y", value: $rect.origin.y, focusedField: $focusedField,
                        fieldId: .y, range: 0...1)
                    NumberField(
                        title: "W", value: $rect.size.width, focusedField: $focusedField,
                        fieldId: .width, range: 0...1)
                    NumberField(
                        title: "H", value: $rect.size.height, focusedField: $focusedField,
                        fieldId: .height, range: 0...1)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedField = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func handleCircle(_ corner: Corner, r: CGRect, box: CGSize) -> some View {
        let p = handlePoint(corner, r)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Theme.green, lineWidth: 1.5))
            .frame(width: handle, height: handle)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .position(x: p.x, y: p.y)
            .gesture(resizeGesture(corner: corner, box: box))
    }

    private func dragGesture(box: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let s = startRect ?? rect
                if startRect == nil { startRect = rect }
                let dx = v.translation.width / box.width
                let dy = v.translation.height / box.height
                let nx = min(max(0, s.minX + dx), 1 - s.width)
                let ny = min(max(0, s.minY + dy), 1 - s.height)
                rect = CGRect(x: nx, y: ny, width: s.width, height: s.height)
            }
            .onEnded { _ in startRect = nil }
    }

    private func resizeGesture(corner: Corner, box: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let s = startRect ?? rect
                if startRect == nil { startRect = rect }
                let dx = v.translation.width / box.width
                let dy = v.translation.height / box.height
                var minX = s.minX
                var minY = s.minY
                var maxX = s.maxX
                var maxY = s.maxY
                switch corner {
                case .topLeading:
                    minX += dx
                    minY += dy
                case .topTrailing:
                    maxX += dx
                    minY += dy
                case .bottomLeading:
                    minX += dx
                    maxY += dy
                case .bottomTrailing:
                    maxX += dx
                    maxY += dy
                }
                minX = min(max(0, minX), maxX - minSize)
                minY = min(max(0, minY), maxY - minSize)
                maxX = max(min(1, maxX), minX + minSize)
                maxY = max(min(1, maxY), minY + minSize)
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in startRect = nil }
    }

    private func handlePoint(_ c: Corner, _ r: CGRect) -> CGPoint {
        switch c {
        case .topLeading: return CGPoint(x: r.minX, y: r.minY)
        case .topTrailing: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeading: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomTrailing: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func fitted(_ avail: CGSize, _ aspect: CGFloat) -> CGSize {
        if avail.width <= 0 || avail.height <= 0 { return .zero }
        var w = avail.width
        var h = w / aspect
        if h > avail.height {
            h = avail.height
            w = h * aspect
        }
        return CGSize(width: w, height: h)
    }
}

struct TPToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.green)
                    .frame(width: configuration.isOn ? 47 : 36, height: 20)
                    .opacity(configuration.isOn ? 1 : 0)
                    .scaleEffect(configuration.isOn ? 1 : 0.55)

                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.green, lineWidth: 2)
                    .frame(width: configuration.isOn ? 47 : 36, height: 20)
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isOn)
            .contentShape(Rectangle())
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

struct TPDropdown<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    @State private var expanded = false
    @State private var hovered: T? = nil
    @State private var headerHovered = false

    private let radius: CGFloat = 8
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Torus.font(11, weight: .semibold))
            }
            .foregroundColor(Theme.text)

            // VStack(spacing: 0) {
            //     header
            //     if expanded { menu }
            // }
            // .background(
            //     RoundedCornersShape(radius: radius, corners: .all)
            //         .stroke(Theme.stroke, lineWidth: 1)
            // )
            // .clipShape(RoundedCornersShape(radius: radius, corners: .all))
            header
                .background(
                    RoundedCornersShape(radius: radius, corners: .all)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .clipShape(RoundedCornersShape(radius: radius, corners: .all))
                .overlay(alignment: .top) {
                    if expanded {
                        menu
                            .alignmentGuide(.top) { d in -d.height }
                            .clipShape(RoundedCornersShape(radius: radius, corners: .all))
                            .background(
                                RoundedCornersShape(radius: radius, corners: .all)
                                    .stroke(Theme.stroke, lineWidth: 1)
                            )
                            .zIndex(10)
                    }
                }
        }.zIndex(expanded ? 100 : 0)
    }

    private var topCorners: Set<Corner> {
        expanded ? [.topLeading, .topTrailing] : .all
    }

    private var orderedOptions: [T] {
        guard let idx = options.firstIndex(of: selection) else { return options }
        var rest = options
        let selected = rest.remove(at: idx)
        return [selected] + rest
    }

    private var header: some View {
        Button(action: { withAnimation(spring) { expanded.toggle() } }) {
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(Torus.font(12, weight: .semibold))
                    .foregroundColor(expanded ? Theme.text : Theme.textDim)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(expanded || headerHovered ? Theme.green : Theme.textDim)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedCornersShape(radius: radius, corners: topCorners)
                    .fill(headerHovered ? Theme.panelHi : Theme.panel)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { headerHovered = $0 }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
            ForEach(Array(orderedOptions.enumerated()), id: \.element) { index, option in
                let isHovered = hovered == option
                let isSelected = selection == option
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Theme.green)
                        .frame(width: 3)
                        .opacity(isSelected ? 1 : 0)
                    Text(label(option))
                        .font(Torus.font(12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(
                            isHovered ? .white : (isSelected ? Theme.green : Theme.text))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isHovered ? .white : Theme.green)
                            .padding(.trailing, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .background(Theme.green.opacity(isHovered ? 0.9 : 0))
                .contentShape(Rectangle())
                .onHover { hovered = $0 ? option : (hovered == option ? nil : hovered) }
                .onTapGesture {
                    selection = option
                    withAnimation(spring) { expanded = false }
                }

                if index < orderedOptions.count - 1 {
                    Rectangle()
                        .fill(Theme.stroke.opacity(0.5))
                        .frame(height: 1)
                }
            }
        }
        .background(Theme.bgTop)
        // .clipShape(RoundedCornersShape(radius: radius, corners: [.bottomLeading, .bottomTrailing]))
        // .overlay(
        //     RoundedCornersShape(radius: radius, corners: [.bottomLeading, .bottomTrailing])
        //         .stroke(Theme.stroke, lineWidth: 1)
        // )
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(10)
    }
}

extension Set where Element == Corner {
    static var all: Set<Corner> { [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing] }
}

struct PreferenceView: View {
    var statusMenu: StatusMenu

    @Bindable var settings = driverSettings

    @State private var displays: [String] = []
    @State private var applied = false

    private var trackpadRect: Binding<CGRect> {
        Binding(
            get: {
                settings.trackpadArea.map(rectFrom) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            },
            set: { settings.trackpadArea = rangeFrom($0) }
        )
    }

    private var display: Binding<String> {
        Binding(
            get: {
                NSScreen.screens.first(where: {
                    Int($0.cgDirectDisplayID ?? 0) == settings.displayId
                })?.localizedName ?? (displays.first ?? "Unknown")
            },
            set: { name in
                settings.displayId = Int(
                    NSScreen.screens.first(where: { $0.localizedName == name })?
                        .cgDirectDisplayID ?? 0)
            }
        )
    }

    enum FocusedField: Hashable {
        case smoothingFactor
        case jitterThreshold
        case trackingSensitivity
    }
    @FocusState private var focusedField: FocusedField?

    private var screenAspect: CGFloat {
        if let s = NSScreen.main?.frame.size, s.height > 0 {
            return s.width / s.height
        }
        return 16.0 / 9.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.enabled) {
                Text("Enable driver")
                    .font(Torus.font(11, weight: .medium))
                    .foregroundColor(Theme.text)
            }
            .toggleStyle(TPToggle())
            .onChange(of: settings.enabled) { oldValue, newValue in
                updateDriverState()
            }

            // TPRegionEditor(
            //     rect: $screenRect,
            //     aspect: screenAspect,
            //     title: "Screen",
            //     glyph: "display",
            //     usePercentage: false
            // )

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 2)
                .cornerRadius(1)

            TPDropdown(
                title: "Mapping mode",
                selection: $settings.trackingMode,
                options: [
                    DriverSettings.TrackingMode.absolute, DriverSettings.TrackingMode.relative,
                ],
                label: { $0.rawValue }
            )

            if settings.trackingMode == .absolute {
                TPRegionEditor(
                    rect: trackpadRect,
                    aspect: 1.6,
                    title: "Trackpad",
                    glyph: "rectangle.dashed",
                    usePercentage: true
                )
                TPDropdown(
                    title: "Display",
                    selection: display,
                    options: displays,
                    label: { String(format: "Display %@", $0) }
                )
            } else {
                // HStack {
                //     Spacer()
                //     Text("1.0 = full area")
                //         .font(Torus.font(11, weight: .medium))
                //         .foregroundColor(Theme.textDim)
                //         .multilineTextAlignment(.center)
                //     // Spacer()
                // }
               
                NumberField(
                    title: "Tracking sensitivity",
                    value: $settings.trackingSensitivity,
                    format: "%.2f",
                    focusedField: $focusedField,
                    fieldId: .trackingSensitivity,
                    range: 0.05...10,
                    showSlider: true
                )
            }

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 2)
                .cornerRadius(1)

            NumberField(
                title: "Smoothing factor",
                value: $settings.smoothingFactor,
                format: "%.2f",
                focusedField: $focusedField,
                fieldId: .smoothingFactor,
                range: 0.1...1,
                showSlider: true
            )
            NumberField(
                title: "Jitter threshold",
                value: $settings.jitterThreshold,
                format: "%.0f",
                focusedField: $focusedField,
                fieldId: .jitterThreshold,
                range: 0...10,
                showSlider: true
            )

            // Toggle(isOn: $emitMouseEvent) {
            //     Text("Emit mouse events")
            //         .font(Torus.font(11, weight: .medium))
            //         .foregroundColor(Theme.text)
            // }
            // .toggleStyle(TPToggle())

            Button(action: {
                updateDriverState()
                withAnimation { applied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation { applied = false }
                }
            }) {
                HStack(spacing: 4) {
                    // Image(systemName: applied ? "checkmark" : "arrow.down.circle.fill")
                    //     .font(.system(size: 10))
                    Text(applied ? "Applied" : "Apply")
                        .font(Torus.font(11, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Theme.green, Theme.greenDark],
                                startPoint: .top, endPoint: .bottom))
                )
            }
            .buttonStyle(.plain)

            // Text(settings.lastSaved == nil ? "Driver settings up to date!" : "Driver synced: \(settings.lastSaved!.formatted())")
            //     .font(Torus.font(11, weight: .medium))
            //     .foregroundColor(Theme.textDim)
        }
        .padding(12)
        .frame(width: 400, alignment: .top)
        .fixedSize(horizontal: false, vertical: false)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            load()
            DispatchQueue.main.async {
                focusedField = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func load() {
        displays = NSScreen.screens.map { "\($0.localizedName)" }
    }

    private func updateDriverState() {
        settings.save()

        if settings.enabled {
            restartDriver()
        } else {
            stopDriver()
        }
    }

    private func rectFrom(_ r: DriverSettings.Rectangle) -> CGRect {
        CGRect(
            x: r.low.x, y: r.low.y,
            width: r.up.x - r.low.x, height: r.up.y - r.low.y)
    }

    private func rangeFrom(_ c: CGRect) -> DriverSettings.Rectangle {
        DriverSettings.Rectangle(
            low: NSPoint(x: c.minX, y: c.minY),
            up: NSPoint(x: c.maxX, y: c.maxY))
    }
}

class StatusMenu: NSObject {
    let popover = NSPopover()
    let statusItem: NSStatusItem
    private var hosting: NSHostingController<PreferenceView>!

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()

        hosting = NSHostingController(rootView: PreferenceView(statusMenu: self))
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            hosting.view.layoutSubtreeIfNeeded()
            popover.contentSize = hosting.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            let window = popover.contentViewController?.view.window
            window?.makeKey()
            DispatchQueue.main.async {
                window?.makeFirstResponder(nil)
            }
        }
    }
}
