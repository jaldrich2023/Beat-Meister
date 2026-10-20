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
            nowPlaying
            WaveformView(seed: deck.track?.title ?? "", position: deck.position, color: color)
                .frame(height: 56)
                .opacity(deck.track == nil ? 0.25 : 1)
            seekBar

            HStack(alignment: .center, spacing: 20) {
                PlatterView(color: color, isPlaying: deck.isPlaying)
                    .frame(width: 130, height: 130)
                pitchControl
            }
            .frame(maxWidth: .infinity)

            transport
        }
        .frame(maxWidth: .infinity)
        .neonPane(color, isLit: deck.isPlaying)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(deck.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Menu("Load") {
                ForEach(Track.samples) { track in
                    Button("\(track.title) — \(track.artist)") { deck.load(track) }
                }
            }
            .fixedSize()
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

    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 14) {
            AlbumArtView(track: deck.track, color: color)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.track?.title ?? "No Track Loaded")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(deck.track?.album ?? "Use Load to choose a track")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(deck.track?.artist ?? " ")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var seekBar: some View {
        VStack(spacing: 2) {
            Slider(value: $deck.position, in: 0...1)
                .tint(color)
                .accessibilityLabel("\(deck.name) Seek")
            HStack {
                Text(elapsedString)
                Spacer()
                Text(remainingString)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .disabled(deck.track == nil)
    }

    private var pitchControl: some View {
        VStack(spacing: 6) {
            Text("PITCH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VerticalSlider(value: $deck.pitch, range: -8...8, color: color)
                .frame(width: 30, height: 100)
            Text(deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%")
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button("CUE", action: deck.cue)
                .buttonStyle(DeckButtonStyle(color: .orange, width: 52))
            Spacer(minLength: 0)
            transportButton("backward.end.fill", label: "Previous Track") { deck.loadAdjacent(offset: -1) }
            transportButton("gobackward.10", label: "Back 10 Seconds") { deck.skip(seconds: -10) }
            Button {
                deck.togglePlay()
            } label: {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(DeckButtonStyle(color: .green, width: 52))
            .accessibilityLabel(deck.isPlaying ? "Pause" : "Play")
            transportButton("goforward.10", label: "Forward 10 Seconds") { deck.skip(seconds: 10) }
            transportButton("forward.end.fill", label: "Next Track") { deck.loadAdjacent(offset: 1) }
            Spacer(minLength: 0)
            Button("SYNC") {}
                .buttonStyle(DeckButtonStyle(color: color, width: 56))
        }
        .disabled(deck.track == nil)
    }

    private func transportButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(DeckButtonStyle(color: .white.opacity(0.8), width: 40))
        .accessibilityLabel(label)
    }

    private var elapsedString: String {
        let duration = deck.track?.duration ?? 0
        return Duration.seconds(duration * deck.position).formatted(.time(pattern: .minuteSecond))
    }

    private var remainingString: String {
        guard let duration = deck.track?.duration else { return "0:00" }
        return "-" + Duration.seconds(duration * (1 - deck.position)).formatted(.time(pattern: .minuteSecond))
    }
}

/// Album art for the loaded track. Real artwork isn't available yet, so this
/// draws a placeholder cover tinted with the deck color.
struct AlbumArtView: View {
    var track: Track?
    var color: Color

    var body: some View {
        ZStack {
            if let track {
                LinearGradient(colors: [color.opacity(0.7), Theme.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .bold))
                    Text(track.album)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .foregroundStyle(.white.opacity(0.9))
            } else {
                Theme.background
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.5), lineWidth: 1))
        .accessibilityLabel(track.map { "Album art for \($0.album)" } ?? "No album art")
    }
}

struct DeckButtonStyle: ButtonStyle {
    var color: Color
    var width: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.bold))
            .frame(width: width, height: 36)
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

#Preview {
    let deck = DeckModel(name: "A")
    deck.load(Track.samples[0])
    deck.position = 0.35
    return DeckView(deck: deck, color: Theme.deckA)
        .frame(width: 420)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
