//
//  Theme.swift
//  Beat Meister
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let deckA = Color(red: 0.0, green: 0.9, blue: 1.0)
    static let deckB = Color(red: 1.0, green: 0.2, blue: 0.75)
    static let mixer = Color(red: 0.6, green: 0.4, blue: 1.0)

    /// Screen-printed label ink on the faceplate.
    static let silkscreen = Color(white: 0.86)

    /// Transport button illumination, matching standard CDJ colors.
    static let cueOrange = Color(red: 1.0, green: 0.58, blue: 0.12)
    static let playGreen = Color(red: 0.25, green: 0.95, blue: 0.45)

    /// Backlit LCD text color.
    static let lcdText = Color(red: 0.62, green: 0.98, blue: 0.90)
    static let lcdDim = Color(red: 0.62, green: 0.98, blue: 0.90).opacity(0.55)
}

// MARK: - Materials

/// Shared gradients for the hardware finish.
enum Metal {
    /// Dark anodized aluminium faceplate with a soft reflection band.
    static let faceplate = LinearGradient(
        stops: [
            .init(color: Color(white: 0.24), location: 0),
            .init(color: Color(white: 0.16), location: 0.15),
            .init(color: Color(white: 0.11), location: 0.55),
            .init(color: Color(white: 0.14), location: 0.85),
            .init(color: Color(white: 0.09), location: 1)
        ],
        startPoint: .top, endPoint: .bottom)

    /// Black rubber button and fader-cap surface.
    static let rubber = LinearGradient(
        colors: [Color(white: 0.26), Color(white: 0.13), Color(white: 0.08)],
        startPoint: .top, endPoint: .bottom)

    /// Rubber while pressed: darker and inverted.
    static let rubberPressed = LinearGradient(
        colors: [Color(white: 0.06), Color(white: 0.12)],
        startPoint: .top, endPoint: .bottom)

    /// Bevel edge: bright top-left, dark bottom-right.
    static let bevel = LinearGradient(
        colors: [.white.opacity(0.45), .white.opacity(0.06), .black.opacity(0.7)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Subtle gloss over the top half of a surface.
    static let gloss = LinearGradient(
        colors: [.white.opacity(0.16), .white.opacity(0.03), .clear],
        startPoint: .top, endPoint: .center)

    /// Chrome bezels and screw heads.
    static let spun = AngularGradient(
        colors: [Color(white: 0.75), Color(white: 0.35), Color(white: 0.85), Color(white: 0.30),
                 Color(white: 0.75), Color(white: 0.35), Color(white: 0.85), Color(white: 0.30),
                 Color(white: 0.75)],
        center: .center)

    /// Brushed aluminium jog-wheel top plate.
    static let platter = AngularGradient(
        colors: [Color(white: 0.55), Color(white: 0.36), Color(white: 0.62), Color(white: 0.34),
                 Color(white: 0.55), Color(white: 0.36), Color(white: 0.62), Color(white: 0.34),
                 Color(white: 0.55)],
        center: .center)
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
                             with: .color(color.opacity(0.025 + 0.035 * abs(shade - 0.5))))
                y += 1.5
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Faceplate

/// An anodized faceplate panel with corner screws, a thick steady neon
/// border and neon accent strips. Nothing pulses or reacts to audio; the
/// neon is only brighter while `isLit` is true.
struct NeonPane: ViewModifier {
    var color: Color
    var isLit: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        content
            .padding(18)
            .background {
                ZStack {
                    shape.fill(Metal.faceplate)
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
            .overlay(alignment: .topLeading) { Screw().padding(10) }
            .overlay(alignment: .topTrailing) { Screw().padding(10) }
            .overlay(alignment: .bottomLeading) { Screw().padding(10) }
            .overlay(alignment: .bottomTrailing) { Screw().padding(10) }
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

/// Phillips-head panel screw.
struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(Metal.spun)
            Circle().strokeBorder(.black.opacity(0.6), lineWidth: 0.5)
            Capsule().fill(.black.opacity(0.6)).frame(width: 1.2).padding(.vertical, 1.5)
            Capsule().fill(.black.opacity(0.6)).frame(height: 1.2).padding(.horizontal, 1.5)
        }
        .rotationEffect(.degrees(20))
        .frame(width: 8, height: 8)
        .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// Small screen-printed label, as found under hardware controls.
struct SilkLabel: View {
    var text: String
    var size: CGFloat = 8.5

    init(_ text: String, size: CGFloat = 8.5) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.silkscreen.opacity(0.8))
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

// MARK: - LCD

/// A backlit player display: dark tinted glass, faint scanlines, a black
/// plastic surround inside a metal bezel, and a glass reflection.
struct LCDPanel: ViewModifier {
    var accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        content
            .padding(10)
            .foregroundStyle(Theme.lcdText)
            .fontDesign(.monospaced)
            .shadow(color: Theme.lcdText.opacity(0.35), radius: 1.5)
            .background {
                ZStack {
                    shape.fill(LinearGradient(
                        colors: [Color(red: 0.04, green: 0.11, blue: 0.12),
                                 Color(red: 0.01, green: 0.05, blue: 0.06)],
                        startPoint: .top, endPoint: .bottom))
                    Canvas { context, size in
                        var y: CGFloat = 0
                        while y < size.height {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(.black.opacity(0.18)))
                            y += 2
                        }
                    }
                    .clipShape(shape)
                    // Inner shadow so the screen sits below the surround.
                    shape.strokeBorder(.black.opacity(0.85), lineWidth: 6)
                        .blur(radius: 4)
                        .clipShape(shape)
                }
            }
            .overlay {
                // Glass reflection.
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0.08), location: 0),
                            .init(color: .white.opacity(0.015), location: 0.42),
                            .init(color: .clear, location: 0.43)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(accent.opacity(0.5), lineWidth: 1)
                    .shadow(color: accent.opacity(0.5), radius: 3)
            }
            // Black plastic surround.
            .padding(5)
            .background(Color(white: 0.04), in: .rect(cornerRadius: 9))
            // Metal bezel.
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 11)
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
