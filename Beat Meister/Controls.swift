//
//  Controls.swift
//  Beat Meister
//
//  Hardware-style controls modeled on professional DJ players and mixers.
//

import SwiftUI

// MARK: - Knobs

/// Rubberized knob skirt with fine radial grip ridges.
struct KnurledRing: View {
    var ridges = 36

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(white: 0.24), Color(white: 0.06)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for index in 0..<ridges {
                let angle = Double(index) / Double(ridges) * 2 * .pi
                var ridge = Path()
                ridge.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.80,
                                       y: center.y + sin(angle) * radius * 0.80))
                ridge.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.98,
                                          y: center.y + sin(angle) * radius * 0.98))
                context.stroke(ridge, with: .color(.white.opacity(0.10)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Mixer-style rotary knob: printed scale dots, steady neon value arc,
/// knurled rubber skirt and a white pointer. Drag vertically to turn;
/// double-click resets to center.
struct Knob: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var color: Color
    var size: CGFloat = 34

    @State private var dragStart: Double?

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var angle: Angle { .degrees(-135 + 270 * fraction) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                scale
                // Value arc grows from the center detent.
                Circle()
                    .trim(from: 0.75 * min(0.5, fraction), to: 0.75 * max(0.5, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: color.opacity(0.7), radius: 2)
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 4, height: size + 4)
                cap
            }
            .frame(width: size + 16, height: size + 16)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let span = range.upperBound - range.lowerBound
                        let newValue = start - drag.translation.height / 150 * span
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            // Simultaneous, so the drag (which starts on mouse-down) doesn't
            // swallow the clicks.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = (range.lowerBound + range.upperBound) / 2
            })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))
            .accessibilityAdjustableAction { direction in
                adjust(&value, in: range, direction: direction)
            }

            SilkLabel(label)
        }
    }

    /// Printed tick dots around the 270° sweep; the center one is larger.
    private var scale: some View {
        ForEach(0..<11) { index in
            let isMajor = index == 0 || index == 5 || index == 10
            Circle()
                .fill(Theme.silkscreen.opacity(isMajor ? 0.9 : 0.45))
                .frame(width: isMajor ? 3 : 2, height: isMajor ? 3 : 2)
                .offset(y: -(size / 2 + 6))
                .rotationEffect(.degrees(-135 + Double(index) * 27))
        }
    }

    private var cap: some View {
        ZStack {
            KnurledRing()
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.32), Color(white: 0.10)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.6))
                .padding(size * 0.15)
            Circle()
                .strokeBorder(Metal.bevel, lineWidth: 1)
                .padding(size * 0.15)
            Capsule()
                .fill(.white)
                .frame(width: 2.5, height: size * 0.32)
                .offset(y: -size * 0.2)
                .rotationEffect(angle)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.7), radius: 2, y: 2)
    }
}

// MARK: - Faders

/// Rubber fader cap with grip ridges and a steady neon center line.
/// `axis` is the direction the fader travels.
struct FaderCap: View {
    var color: Color
    var axis: Axis = .vertical

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Metal.rubber)
            RoundedRectangle(cornerRadius: 3).fill(Metal.gloss)
            ridges
            RoundedRectangle(cornerRadius: 3).strokeBorder(Metal.bevel, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.75), radius: 2, y: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ridges: some View {
        let ridge = Color.white.opacity(0.12)
        if axis == .vertical {
            VStack(spacing: 3) {
                ridge.frame(height: 1)
                ridge.frame(height: 1)
                color.frame(height: 2).shadow(color: color, radius: 2)
                ridge.frame(height: 1)
                ridge.frame(height: 1)
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 3) {
                ridge.frame(width: 1)
                color.frame(width: 2).shadow(color: color, radius: 2)
                ridge.frame(width: 1)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Printed tick marks along a fader's travel, on both sides of the slot.
struct FaderScale: View {
    var tickCount = 11
    var axis: Axis = .vertical
    /// Emphasizes the middle tick (e.g. 0% on a tempo fader).
    var centerDetent = false

    var body: some View {
        Canvas { context, size in
            let length = axis == .vertical ? size.height : size.width
            let breadth = axis == .vertical ? size.width : size.height
            let middle = tickCount / 2
            for index in 0..<tickCount {
                let isMajor = index == 0 || index == tickCount - 1 || (centerDetent && index == middle)
                let tick: CGFloat = isMajor ? 8 : 5
                let along = length * CGFloat(index) / CGFloat(tickCount - 1)
                let opacity = isMajor ? 0.9 : 0.45
                let rects: [CGRect]
                if axis == .vertical {
                    rects = [CGRect(x: 0, y: along - 0.5, width: tick, height: 1),
                             CGRect(x: breadth - tick, y: along - 0.5, width: tick, height: 1)]
                } else {
                    rects = [CGRect(x: along - 0.5, y: 0, width: 1, height: tick),
                             CGRect(x: along - 0.5, y: breadth - tick, width: 1, height: tick)]
                }
                for rect in rects {
                    context.fill(Path(rect), with: .color(Theme.silkscreen.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Long-throw vertical fader with a printed scale. Up increases the value;
/// double-click resets to center.
struct VerticalFader: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color
    var tickCount = 11
    var centerDetent = false

    private let capHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let travel = geometry.size.height - capHeight
            ZStack(alignment: .top) {
                FaderScale(tickCount: tickCount, axis: .vertical, centerDetent: centerDetent)
                    .padding(.vertical, capHeight / 2)
                FaderSlot()
                    .frame(width: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FaderCap(color: color, axis: .vertical)
                    .frame(width: min(geometry.size.width * 0.6, 30), height: capHeight)
                    .offset(y: travel * (1 - fraction))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newFraction = 1 - (drag.location.y - capHeight / 2) / travel
                        value = range.lowerBound + min(max(newFraction, 0), 1) * span
                    }
            )
            // Simultaneous, so the drag (which starts on mouse-down) doesn't
            // swallow the clicks.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = (range.lowerBound + range.upperBound) / 2
            })
        }
        .accessibilityElement()
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
        .accessibilityAdjustableAction { direction in
            adjust(&value, in: range, direction: direction)
        }
    }
}

/// Horizontal fader with a printed scale, used for the crossfader.
struct HorizontalFader: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color
    var tickCount = 11

    private let capWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let travel = geometry.size.width - capWidth
            ZStack(alignment: .leading) {
                FaderScale(tickCount: tickCount, axis: .horizontal, centerDetent: true)
                    .padding(.horizontal, capWidth / 2)
                FaderSlot()
                    .frame(height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FaderCap(color: color, axis: .horizontal)
                    .frame(width: capWidth, height: 26)
                    .offset(x: travel * fraction)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newFraction = (drag.location.x - capWidth / 2) / travel
                        value = range.lowerBound + min(max(newFraction, 0), 1) * span
                    }
            )
            // Simultaneous, so the drag (which starts on mouse-down) doesn't
            // swallow the clicks.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                value = (range.lowerBound + range.upperBound) / 2
            })
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))
        .accessibilityAdjustableAction { direction in
            adjust(&value, in: range, direction: direction)
        }
    }
}

/// The recessed slot a fader cap rides in.
struct FaderSlot: View {
    var body: some View {
        Capsule()
            .fill(.black)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Steps a value 5% of its range for VoiceOver increment/decrement.
private func adjust(_ value: inout Double, in range: ClosedRange<Double>, direction: AccessibilityAdjustmentDirection) {
    let step = (range.upperBound - range.lowerBound) / 20
    switch direction {
    case .increment: value = min(value + step, range.upperBound)
    case .decrement: value = max(value - step, range.lowerBound)
    @unknown default: break
    }
}

/// CDJ-style needle search strip: tap or drag anywhere to jump to that point.
struct NeedleSearchStrip: View {
    @Binding var position: Double
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.85))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.22))
                    .frame(width: max(width * position, 0))
                Canvas { context, size in
                    for index in 1..<10 {
                        let x = size.width * CGFloat(index) / 10
                        context.fill(Path(CGRect(x: x, y: size.height * 0.3, width: 1, height: size.height * 0.4)),
                                     with: .color(Theme.silkscreen.opacity(0.25)))
                    }
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3)
                    .shadow(color: color, radius: 4)
                    .offset(x: (width - 3) * position)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Metal.bevel, lineWidth: 1)
                    .rotationEffect(.degrees(180))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        position = min(max(drag.location.x / width, 0), 1)
                    }
            )
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityValue(position.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            adjust(&position, in: 0...1, direction: direction)
        }
    }
}

// MARK: - Buttons

/// Large round CUE / PLAY button: rubber face, illuminated ring and a
/// chrome bezel. The ring is steady; it's simply on or off.
struct RoundTransportButtonStyle: ButtonStyle {
    var color: Color
    var isLit: Bool
    var size: CGFloat = 54

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
            .foregroundStyle(isLit ? color : Theme.silkscreen)
            .shadow(color: isLit ? color.opacity(0.8) : .clear, radius: 4)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    Circle().fill(configuration.isPressed ? Metal.rubberPressed : Metal.rubber)
                    Circle().fill(Metal.gloss).padding(5)
                    Circle()
                        .strokeBorder(color.opacity(isLit ? 1 : 0.3), lineWidth: 3)
                        .shadow(color: color.opacity(isLit ? 0.9 : 0), radius: 5)
                }
            }
            .padding(3)
            .background(Circle().fill(Metal.spun))
            .overlay(Circle().strokeBorder(Metal.bevel, lineWidth: 1))
            .shadow(color: .black.opacity(0.7), radius: configuration.isPressed ? 1 : 4, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.55)
    }
}

/// Small rectangular rubber button with an optional steady LED strip.
struct RubberButtonStyle: ButtonStyle {
    var width: CGFloat = 44
    var height: CGFloat = 28
    var ledColor: Color?
    var isLit = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        configuration.label
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(isLit ? (ledColor ?? Theme.silkscreen) : Theme.silkscreen)
            .frame(width: width, height: height)
            .background {
                ZStack {
                    shape.fill(configuration.isPressed ? Metal.rubberPressed : Metal.rubber)
                    shape.fill(Metal.gloss)
                    shape.strokeBorder(Metal.bevel, lineWidth: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if let ledColor {
                    Capsule()
                        .fill(ledColor.opacity(isLit ? 1 : 0.4))
                        .frame(height: 2)
                        .shadow(color: ledColor.opacity(isLit ? 0.9 : 0.3), radius: 3)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 3)
                }
            }
            .shadow(color: .black.opacity(0.7), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 2)
            .opacity(isEnabled ? 1 : 0.55)
    }
}

// MARK: - Jog Wheel

/// CDJ-style jog wheel: chrome bezel, steady illumination ring, knurled
/// rubber edge, brushed-aluminium top plate and a center jog display.
struct JogWheel: View {
    /// The part of the wheel a drag started on, which sets the seek rate.
    enum Zone {
        /// The top platter: coarse seeking.
        case platter
        /// The knurled outer ring: fine seeking.
        case ring

        /// Seconds of track traveled per full clockwise revolution.
        var secondsPerRevolution: Double {
            switch self {
            case .platter: 16
            case .ring: 1.8   // About one turn of a 33⅓ RPM record.
            }
        }
    }

    var color: Color
    var isPlaying: Bool
    var position: Double
    /// Track position at which the jog display's marker points to 12 o'clock.
    var markerOrigin: Double = 0
    var size: CGFloat = 170
    /// Called while the wheel is turned, with seconds to move (negative is backward).
    var onSeek: (TimeInterval) -> Void = { _ in }
    /// Called with true when the wheel starts turning and false when it's released.
    var onTouch: (Bool) -> Void = { _ in }
    /// Called when the wheel is double-clicked.
    var onDoubleClick: () -> Void = {}

    @State private var dragZone: Zone?
    @State private var lastAngle: Angle?
    /// True once the drag has actually turned the wheel.
    @State private var isTurning = false
    /// Rotation collected before the turn threshold is reached.
    @State private var pendingDegrees: Double = 0

    /// Rotation needed before a press counts as turning. Keeps clicks and
    /// double-clicks from interrupting playback.
    private let turnThreshold: Double = 1.5

    var body: some View {
        ZStack {
            Circle().fill(Metal.spun)
            Circle().strokeBorder(Metal.bevel, lineWidth: 1.5)
            Circle()
                .strokeBorder(color.opacity(isPlaying ? 1 : 0.55), lineWidth: 3)
                .shadow(color: color.opacity(isPlaying ? 0.9 : 0.45), radius: 5)
                .padding(5)
            KnurledRing(ridges: 110)
                .padding(9)
            topPlate
                .padding(size * (0.5 - platterRadiusFraction))
            JogDisplay(color: color, position: position, markerOrigin: markerOrigin, diameter: size * 0.42)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(rotation)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleClick() })
        .shadow(color: .black.opacity(0.7), radius: 8, y: 5)
        .accessibilityElement()
        .accessibilityLabel("Jog Wheel")
        .accessibilityHint("Turn to seek through the track. Double-click to reset the marker to 12 o’clock.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(1)
            case .decrement: onSeek(-1)
            @unknown default: break
            }
        }
    }

    /// Converts circular dragging into seek amounts. The zone is chosen where
    /// the drag begins, so sliding across the boundary mid-turn doesn't
    /// change the rate.
    private var rotation: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let center = CGPoint(x: size / 2, y: size / 2)
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                // Ignore the dead spot at the very center, where angles jump.
                guard hypot(dx, dy) > size * 0.06 else { return }
                // Screen y points down, so increasing angles run clockwise.
                let angle = Angle(radians: atan2(dy, dx))

                if dragZone == nil {
                    let start = drag.startLocation
                    let startRadius = hypot(start.x - center.x, start.y - center.y)
                    dragZone = startRadius < size * platterRadiusFraction ? .platter : .ring
                }
                if let lastAngle, let dragZone {
                    var delta = angle.degrees - lastAngle.degrees
                    // Unwrap across the ±180° seam.
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }

                    if !isTurning {
                        pendingDegrees += delta
                        if abs(pendingDegrees) >= turnThreshold {
                            isTurning = true
                            onTouch(true)
                            delta = pendingDegrees
                        }
                    }
                    if isTurning {
                        onSeek(delta / 360 * dragZone.secondsPerRevolution)
                    }
                }
                lastAngle = angle
            }
            .onEnded { _ in
                if isTurning {
                    onTouch(false)
                }
                dragZone = nil
                lastAngle = nil
                isTurning = false
                pendingDegrees = 0
            }
    }

    /// Radius of the top platter as a fraction of the wheel's diameter.
    /// Also sets the platter's inset, so the drawing and the zones agree.
    private let platterRadiusFraction: CGFloat = 0.38

    private var topPlate: some View {
        ZStack {
            Circle().fill(Metal.platter)
            ForEach(0..<7) { ring in
                Circle()
                    .stroke(.black.opacity(0.07), lineWidth: 1)
                    .padding(CGFloat(4 + ring * 5))
            }
            Circle().fill(Metal.gloss)
            Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1)
        }
    }
}

/// Small round screen in the jog center showing track progress and a
/// marker that rotates with the playback position.
struct JogDisplay: View {
    var color: Color
    var position: Double
    /// Position at which the marker points to 12 o'clock.
    var markerOrigin: Double = 0
    var diameter: CGFloat

    var body: some View {
        let radius = diameter / 2
        ZStack {
            Circle().fill(Color(red: 0.02, green: 0.06, blue: 0.07))
            ForEach(0..<24) { index in
                Capsule()
                    .fill(Theme.lcdDim.opacity(0.6))
                    .frame(width: 1.5, height: 4)
                    .offset(y: -radius + 7)
                    .rotationEffect(.degrees(Double(index) * 15))
            }
            Circle()
                .trim(from: 0, to: position)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: color, radius: 2)
                .rotationEffect(.degrees(-90))
                .padding(12)
            // One revolution per ~8% of the track, like a turntable marker.
            Capsule()
                .fill(.white)
                .frame(width: 3, height: 9)
                .offset(y: -radius + 8)
                .rotationEffect(.degrees((position - markerOrigin) * 360 * 12))
            Circle()
                .strokeBorder(.black, lineWidth: 3)
            Circle()
                .strokeBorder(Metal.bevel, lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Meters

/// Segmented LED level meter. Not yet driven by audio, so with the default
/// level of 0 every segment shows unlit.
struct LEDMeter: View {
    var level: Double = 0
    var segments = 15

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array((0..<segments).reversed()), id: \.self) { index in
                let isLit = Double(index + 1) / Double(segments) <= level
                RoundedRectangle(cornerRadius: 1)
                    .fill(segmentColor(index).opacity(isLit ? 1 : 0.16))
            }
        }
        .padding(2)
        .background(.black, in: .rect(cornerRadius: 2))
        .accessibilityHidden(true)
    }

    private func segmentColor(_ index: Int) -> Color {
        if index >= segments - 2 { return .red }
        if index >= segments - 5 { return .orange }
        return .green
    }
}
