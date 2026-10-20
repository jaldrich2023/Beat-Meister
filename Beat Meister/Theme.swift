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
}

/// A panel with a thick, steady neon border. The border never pulses or
/// reacts to audio; it is only brighter while `isLit` is true.
struct NeonPane: ViewModifier {
    var color: Color
    var isLit: Bool

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.panel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(color.opacity(isLit ? 1 : 0.4), lineWidth: 4)
                    .shadow(color: color.opacity(isLit ? 0.9 : 0.3), radius: isLit ? 10 : 4)
            }
    }
}

extension View {
    func neonPane(_ color: Color, isLit: Bool = false) -> some View {
        modifier(NeonPane(color: color, isLit: isLit))
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
                Circle()
                    .fill(Theme.background)
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 10)
                    .offset(y: -11)
                    .rotationEffect(.degrees(-135 + 270 * fraction))
            }
            .frame(width: 36, height: 36)
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
