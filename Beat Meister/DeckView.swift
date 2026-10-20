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
            infoScreen
            WaveformView(seed: deck.track?.title ?? "", position: deck.position, color: color)
                .frame(height: 56)
                .opacity(deck.track == nil ? 0.35 : 1)
            seekBar

            HStack(alignment: .center, spacing: 20) {
                PlatterView(color: color, isPlaying: deck.isPlaying)
                    .frame(width: 130, height: 130)
                pitchControl
            }
            .frame(maxWidth: .infinity)

            NeonLine(color: color, isLit: deck.isPlaying, thickness: 1.5)
            transport
        }
        .frame(maxWidth: .infinity)
        .neonPane(color, isLit: deck.isPlaying)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(deck.name)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.7), radius: 4)
            Menu("Load") {
                ForEach(Track.samples) { track in
                    Button("\(track.title) — \(track.artist)") { deck.load(track) }
                }
            }
            .fixedSize()
            Spacer()
            Text("DECK \(deck.name)")
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Backlit LCD showing album art, track details, BPM and key.
    private var infoScreen: some View {
        HStack(alignment: .center, spacing: 12) {
            AlbumArtView(track: deck.track, color: color)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.track?.title.uppercased() ?? "NO TRACK LOADED")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                Text(deck.track?.album ?? "Use Load to choose a track")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.lcdDim)
                    .lineLimit(1)
                Text(deck.track?.artist ?? " ")
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    lcdReadout(deck.effectiveBPM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "---.-",
                               label: "BPM", size: 22)
                    lcdReadout(deck.track?.key ?? "--", label: "KEY", size: 15)
                    lcdReadout(deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%",
                               label: "PITCH", size: 15)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 96)
        .lcdPanel(accent: color)
    }

    private func lcdReadout(_ value: String, label: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.lcdDim)
        }
    }

    private var seekBar: some View {
        VStack(spacing: 2) {
            MetalSlider(value: $deck.position, range: 0...1, color: color)
                .accessibilityLabel("\(deck.name) Seek")
            HStack {
                Text(elapsedString)
                Spacer()
                Text(remainingString)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
        }
        .disabled(deck.track == nil)
    }

    private var pitchControl: some View {
        VStack(spacing: 6) {
            Text("PITCH")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white.opacity(0.7))
            VerticalSlider(value: $deck.pitch, range: -8...8, color: color)
                .frame(width: 30, height: 100)
                .accessibilityLabel("\(deck.name) Pitch")
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button("CUE", action: deck.cue)
                .buttonStyle(MetalButtonStyle(color: .orange, width: 52))
            Spacer(minLength: 0)
            transportButton("backward.end.fill", label: "Previous Track") { deck.loadAdjacent(offset: -1) }
            transportButton("gobackward.10", label: "Back 10 Seconds") { deck.skip(seconds: -10) }
            Button {
                deck.togglePlay()
            } label: {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(MetalButtonStyle(color: .green, width: 52, isActive: deck.isPlaying))
            .accessibilityLabel(deck.isPlaying ? "Pause" : "Play")
            transportButton("goforward.10", label: "Forward 10 Seconds") { deck.skip(seconds: 10) }
            transportButton("forward.end.fill", label: "Next Track") { deck.loadAdjacent(offset: 1) }
            Spacer(minLength: 0)
            Button("SYNC") {}
                .buttonStyle(MetalButtonStyle(color: color, width: 56))
        }
        .disabled(deck.track == nil)
    }

    private func transportButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(MetalButtonStyle(color: .white.opacity(0.9), width: 40))
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
                        .font(.system(size: 30, weight: .bold))
                    Text(track.album)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .foregroundStyle(.white.opacity(0.9))
            } else {
                Color.black.opacity(0.3)
                Image(systemName: "photo")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.lcdDim)
            }
        }
        .clipShape(.rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.lcdText.opacity(0.3), lineWidth: 1))
        .shadow(radius: 0)
        .accessibilityLabel(track.map { "Album art for \($0.album)" } ?? "No album art")
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
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.75), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Metal.bevel, lineWidth: 1).rotationEffect(.degrees(180)))
    }
}

/// Static jog wheel graphic: chrome rim, steady neon ring, vinyl grooves
/// and a spun-metal center cap.
struct PlatterView: View {
    var color: Color
    var isPlaying: Bool

    var body: some View {
        ZStack {
            // Chrome outer rim.
            Circle().fill(Metal.spun)
            Circle().fill(Metal.gloss)
            Circle().strokeBorder(Metal.bevel, lineWidth: 1.5)
            // Neon ring.
            Circle()
                .strokeBorder(color.opacity(isPlaying ? 1 : 0.6), lineWidth: 3)
                .shadow(color: color.opacity(isPlaying ? 0.9 : 0.5), radius: 5)
                .padding(8)
            // Vinyl with grooves.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)],
                                     center: .center, startRadius: 0, endRadius: 55))
                .padding(12)
            ForEach(0..<6) { ring in
                Circle()
                    .stroke(.white.opacity(0.05), lineWidth: 1)
                    .padding(CGFloat(18 + ring * 6))
            }
            // Glossy vinyl sheen.
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear, .clear,
                                               .white.opacity(0.10), .clear, .clear],
                                      center: .center))
                .padding(12)
            // Center cap with a neon position marker.
            ZStack {
                Circle().fill(Metal.spun)
                Circle().strokeBorder(Metal.bevel, lineWidth: 1)
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 12)
                    .offset(y: -12)
            }
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
        }
        .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
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
            let capHeight: CGFloat = 18
            let travel = geometry.size.height - capHeight
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Metal.slot)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FaderCap(color: color)
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
