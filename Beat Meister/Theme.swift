//
//  Theme.swift
//  Beat Meister
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let panel = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let deckA = Color(red: 0.0, green: 0.9, blue: 1.0)
    static let deckB = Color(red: 1.0, green: 0.2, blue: 0.75)
    static let mixer = Color(red: 0.6, green: 0.4, blue: 1.0)

    /// Backlit LCD text color.
    static let lcdText = Color(red: 0.62, green: 0.98, blue: 0.90)
    static let lcdDim = Color(red: 0.62, green: 0.98, blue: 0.90).opacity(0.55)
}

// MARK: - Metal

/// Shared gradients for the glossy gunmetal finish.
enum Metal {
    /// Panel face: dark gunmetal with a soft horizontal reflection band.
    static let panel = LinearGradient(
        stops: [
            .init(color: Color(white: 0.30), location: 0),
            .init(color: Color(white: 0.20), location: 0.18),
            .init(color: Color(white: 0.13), location: 0.55),
            .init(color: Color(white: 0.17), location: 0.85),
            .init(color: Color(white: 0.11), location: 1)
        ],
        startPoint: .top, endPoint: .bottom)

    /// Raised control surface (buttons, fader caps).
    static let raised = LinearGradient(
        colors: [Color(white: 0.58), Color(white: 0.34), Color(white: 0.22), Color(white: 0.30)],
        startPoint: .top, endPoint: .bottom)

    /// Raised surface while pressed: darker and inverted.
    static let pressed = LinearGradient(
        colors: [Color(white: 0.16), Color(white: 0.24), Color(white: 0.30)],
        startPoint: .top, endPoint: .bottom)

    /// Bevel edge: bright top-left, dark bottom-right.
    static let bevel = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.08), .black.opacity(0.7)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Glossy highlight laid over the top half of a surface.
    static let gloss = LinearGradient(
        colors: [.white.opacity(0.28), .white.opacity(0.06), .clear],
        startPoint: .top, endPoint: .center)

    /// Spun-metal look for round controls.
    static let spun = AngularGradient(
        colors: [Color(white: 0.75), Color(white: 0.35), Color(white: 0.85), Color(white: 0.30),
                 Color(white: 0.75), Color(white: 0.35), Color(white: 0.85), Color(white: 0.30),
                 Color(white: 0.75)],
        center: .center)

    /// Recessed slot for fader tracks.
    static let slot = LinearGradient(
        colors: [.black, Color(white: 0.12)],
        startPoint: .top, endPoint: .bottom)
}

/// Fine horizontal lines that give a brushed-metal texture.
/// Drawn from a fixed seed so the pattern is identical on every render.
struct BrushedTexture: View {
    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x9E3779B97F4A7C15
            var y: CGFloat = 0
            while y < size.height {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let shade = Double(state >> 40) / Double(1 << 24)
                let color: Color = shade > 0.5 ? .white : .black
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(color.opacity(0.03 + 0.04 * abs(shade - 0.5))))
                y += 1.5
            }
        }
        .allowsHitTesting(false)
    }
}

/// A glossy brushed-metal panel with a thick, steady neon border and neon
/// corner accents. Nothing pulses or reacts to audio; the neon is only
/// brighter while `isLit` is true.
struct NeonPane: ViewModifier {
    var color: Color
    var isLit: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        content
            .padding(16)
            .background {
                ZStack {
                    shape.fill(Metal.panel)
                    BrushedTexture().clipShape(shape)
                    shape.fill(Metal.gloss)
                    shape.strokeBorder(Metal.bevel, lineWidth: 1.5)
                        .padding(4)
                }
            }
            .overlay {
                shape
                    .strokeBorder(color.opacity(isLit ? 1 : 0.45), lineWidth: 4)
                    .shadow(color: color.opacity(isLit ? 0.9 : 0.35), radius: isLit ? 10 : 5)
            }
            .overlay(alignment: .top) {
                NeonLine(color: color, isLit: isLit)
                    .frame(width: 90)
                    .padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                NeonLine(color: color, isLit: isLit)
                    .frame(width: 90)
                    .padding(.bottom, 8)
            }
    }
}

extension View {
    func neonPane(_ color: Color, isLit: Bool = false) -> some View {
        modifier(NeonPane(color: color, isLit: isLit))
    }
}

/// A thin, steady neon accent strip.
struct NeonLine: View {
    var color: Color
    var isLit: Bool = false
    var thickness: CGFloat = 2

    var body: some View {
        Capsule()
            .fill(color.opacity(isLit ? 1 : 0.7))
            .frame(height: thickness)
            .shadow(color: color.opacity(isLit ? 0.9 : 0.6), radius: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - LCD

/// A backlit LCD screen: dark tinted glass, faint scanlines, a recessed
/// metal bezel and a diagonal glass reflection.
struct LCDPanel: ViewModifier {
    var accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        content
            .padding(12)
            .foregroundStyle(Theme.lcdText)
            .fontDesign(.monospaced)
            .shadow(color: Theme.lcdText.opacity(0.45), radius: 2)
            .background {
                ZStack {
                    shape.fill(LinearGradient(
                        colors: [Color(red: 0.05, green: 0.13, blue: 0.14),
                                 Color(red: 0.02, green: 0.07, blue: 0.08)],
                        startPoint: .top, endPoint: .bottom))
                    Canvas { context, size in
                        var y: CGFloat = 0
                        while y < size.height {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(.black.opacity(0.22)))
                            y += 3
                        }
                    }
                    .clipShape(shape)
                    // Inner shadow so the screen sits below the panel face.
                    shape.strokeBorder(.black.opacity(0.8), lineWidth: 6)
                        .blur(radius: 4)
                        .clipShape(shape)
                }
            }
            .overlay {
                // Glass reflection.
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0.10), location: 0),
                            .init(color: .white.opacity(0.02), location: 0.45),
                            .init(color: .clear, location: 0.46)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(accent.opacity(0.55), lineWidth: 1)
                    .shadow(color: accent.opacity(0.5), radius: 3)
            }
            .padding(3)
            .background {
                // Metal bezel around the screen.
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.black.opacity(0.8), Color(white: 0.45)],
                                         startPoint: .top, endPoint: .bottom))
            }
    }
}

extension View {
    func lcdPanel(accent: Color) -> some View {
        modifier(LCDPanel(accent: accent))
    }
}

// MARK: - Controls

/// Glossy metal push button with a steady neon LED strip and tinted label.
struct MetalButtonStyle: ButtonStyle {
    var color: Color
    var width: CGFloat = 64
    var isActive = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.heavy))
            .foregroundStyle(color)
            .shadow(color: color.opacity(isActive ? 0.9 : 0.4), radius: isActive ? 4 : 2)
            .frame(width: width, height: 36)
            .background {
                ZStack {
                    shape.fill(configuration.isPressed ? Metal.pressed : Metal.raised)
                    shape.fill(Metal.gloss)
                    shape.strokeBorder(Metal.bevel, lineWidth: 1)
                }
            }
            .overlay(alignment: .bottom) {
                NeonLine(color: color, isLit: isActive, thickness: 2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            .shadow(color: .black.opacity(0.6), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 2)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A rotary knob controlled by vertical dragging. Double-click resets to center.
struct Knob: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var color: Color

    @State private var dragStart: Double?

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Neon value arc around the knob.
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: color.opacity(0.7), radius: 3)
                    .rotationEffect(.degrees(135))
                // Metal cap.
                Group {
                    Circle().fill(Metal.spun)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.35), .clear],
                                                 center: .topLeading, startRadius: 0, endRadius: 22))
                    Circle().strokeBorder(Metal.bevel, lineWidth: 1)
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 9)
                        .offset(y: -8)
                        .rotationEffect(.degrees(-135 + 270 * fraction))
                }
                .padding(5)
                .shadow(color: .black.opacity(0.7), radius: 2, y: 2)
            }
            .frame(width: 40, height: 40)
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
            .onTapGesture(count: 2) {
                value = (range.lowerBound + range.upperBound) / 2
            }
            .accessibilityLabel(label)
            .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))

            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Metal fader cap with a neon center line, shared by vertical and horizontal faders.
struct FaderCap: View {
    var color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Metal.raised)
            RoundedRectangle(cornerRadius: 3).fill(Metal.gloss)
            RoundedRectangle(cornerRadius: 3).strokeBorder(Metal.bevel, lineWidth: 1)
            NeonLine(color: color, isLit: true, thickness: 2)
                .padding(.horizontal, 4)
        }
        .shadow(color: .black.opacity(0.7), radius: 2, y: 2)
    }
}

/// A horizontal metal fader with a neon fill, used for seek and crossfade.
struct MetalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color
    /// When true the neon fill grows from the center (for the crossfader).
    var fillFromCenter = false

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let capWidth: CGFloat = 14
            let travel = geometry.size.width - capWidth
            let thumbX = travel * fraction + capWidth / 2
            let fillStart = fillFromCenter ? geometry.size.width / 2 : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Metal.slot)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .frame(height: 6)
                Capsule()
                    .fill(color)
                    .shadow(color: color.opacity(0.7), radius: 3)
                    .frame(width: abs(thumbX - fillStart), height: 4)
                    .offset(x: min(thumbX, fillStart))
                FaderCap(color: color)
                    .frame(width: capWidth, height: 22)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newFraction = (drag.location.x - capWidth / 2) / travel
                        value = range.lowerBound + min(max(newFraction, 0), 1) * span
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))
    }
}
