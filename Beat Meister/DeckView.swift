//
//  DeckView.swift
//  Beat Meister
//

import SwiftUI

struct DeckView: View {
    @Bindable var deck: DeckModel
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            WaveformView(seed: deck.track?.title ?? "", position: deck.position, color: color)
                .frame(height: 70)
                .opacity(deck.track == nil ? 0.25 : 1)

            HStack(alignment: .center, spacing: 20) {
                PlatterView(color: color, isPlaying: deck.isPlaying)
                    .frame(width: 150, height: 150)
                pitchControl
            }
            .frame(maxWidth: .infinity)

            transport
        }
        .frame(maxWidth: .infinity)
        .neonPane(color, isLit: deck.isPlaying)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(deck.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(deck.track?.title ?? "No Track Loaded")
                    .font(.headline)
                    .lineLimit(1)
                Text(deck.track?.artist ?? "Load a track from the library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(deck.effectiveBPM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--.-")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                Text("BPM · \(deck.track?.key ?? "--")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pitchControl: some View {
        VStack(spacing: 6) {
            Text("PITCH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VerticalSlider(value: $deck.pitch, range: -8...8, color: color)
                .frame(width: 30, height: 120)
            Text(deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%")
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button("CUE", action: deck.cue)
                .buttonStyle(DeckButtonStyle(color: .orange))
            Button {
                deck.togglePlay()
            } label: {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(DeckButtonStyle(color: .green))
            .accessibilityLabel(deck.isPlaying ? "Pause" : "Play")
            Button("SYNC") {}
                .buttonStyle(DeckButtonStyle(color: color))
            Spacer()
            Text(timeString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .disabled(deck.track == nil)
    }

    private var timeString: String {
        guard let duration = deck.track?.duration else { return "0:00 / 0:00" }
        let elapsed = Duration.seconds(duration * deck.position)
        let total = Duration.seconds(duration)
        return "\(elapsed.formatted(.time(pattern: .minuteSecond))) / \(total.formatted(.time(pattern: .minuteSecond)))"
    }
}

struct DeckButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.bold))
            .frame(width: 64, height: 36)
            .foregroundStyle(color)
            .background(color.opacity(configuration.isPressed ? 0.35 : 0.12), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 2))
    }
}

/// Placeholder waveform drawn from a deterministic pseudo-random sequence,
/// so each track gets a stable, distinct shape until real analysis exists.
struct WaveformView: View {
    var seed: String
    var position: Double
    var color: Color

    var body: some View {
        Canvas { context, size in
            let barCount = 160
            let barWidth = size.width / CGFloat(barCount)
            var state = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) })
            for index in 0..<barCount {
                // Simple LCG for repeatable bar heights.
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let amplitude = 0.2 + 0.8 * Double(state >> 40) / Double(1 << 24)
                let height = size.height * amplitude
                let rect = CGRect(x: CGFloat(index) * barWidth,
                                  y: (size.height - height) / 2,
                                  width: max(barWidth - 1, 1),
                                  height: height)
                let played = Double(index) / Double(barCount) < position
                context.fill(Path(rect), with: .color(color.opacity(played ? 0.35 : 0.85)))
            }
            let playheadX = size.width * position
            context.fill(Path(CGRect(x: playheadX - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
        }
        .background(Theme.background, in: .rect(cornerRadius: 6))
    }
}

/// Static jog wheel graphic.
struct PlatterView: View {
    var color: Color
    var isPlaying: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.background)
            Circle()
                .strokeBorder(color.opacity(isPlaying ? 1 : 0.5), lineWidth: 4)
            ForEach(0..<12) { index in
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 2, height: 14)
                    .offset(y: -58)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 50, height: 50)
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
        }
        .accessibilityHidden(true)
    }
}

/// A vertical fader. Dragging up increases the value.
struct VerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let capHeight: CGFloat = 16
            let travel = geometry.size.height - capHeight
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.background)
                    .frame(width: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width, height: capHeight)
                    .offset(y: travel * (1 - fraction))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newFraction = 1 - (drag.location.y - capHeight / 2) / travel
                        let clamped = min(max(newFraction, 0), 1)
                        value = range.lowerBound + clamped * span
                    }
            )
            .onTapGesture(count: 2) {
                value = (range.lowerBound + range.upperBound) / 2
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
    }
}
