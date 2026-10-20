//
//  DeckView.swift
//  Beat Meister
//

import SwiftUI

/// A CDJ-style player: display and needle search on top, with search and
/// transport buttons left of the jog wheel and the tempo fader on the right.
struct DeckView: View {
    @Bindable var deck: DeckModel
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            DeckDisplay(deck: deck, color: color)

            VStack(spacing: 3) {
                NeedleSearchStrip(position: $deck.position, color: color)
                    .accessibilityLabel("\(deck.name) Needle Search")
                SilkLabel("Needle Search")
            }
            .disabled(deck.track == nil)

            HStack(alignment: .center, spacing: 14) {
                buttonColumn
                JogWheel(color: color, isPlaying: deck.isPlaying, position: deck.position)
                    .frame(maxWidth: .infinity)
                tempoColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text("BEAT MEISTER")
                .font(.system(size: 11, weight: .black))
                .italic()
                .tracking(2)
                .foregroundStyle(Theme.silkscreen.opacity(0.7))
        }
    }

    /// Track search, search, CUE and PLAY/PAUSE, stacked as on a CDJ.
    private var buttonColumn: some View {
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    rubberButton("backward.end.fill", label: "Previous Track") { deck.loadAdjacent(offset: -1) }
                    rubberButton("forward.end.fill", label: "Next Track") { deck.loadAdjacent(offset: 1) }
                }
                SilkLabel("Track Search")
            }
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    rubberButton("backward.fill", label: "Back 10 Seconds") { deck.skip(seconds: -10) }
                    rubberButton("forward.fill", label: "Forward 10 Seconds") { deck.skip(seconds: 10) }
                }
                SilkLabel("Search")
            }
            VStack(spacing: 3) {
                Button("CUE", action: deck.cue)
                    .buttonStyle(RoundTransportButtonStyle(color: Theme.cueOrange,
                                                           isLit: deck.track != nil && !deck.isPlaying))
                SilkLabel("Cue")
            }
            VStack(spacing: 3) {
                Button {
                    deck.togglePlay()
                } label: {
                    Image(systemName: "playpause.fill")
                }
                .buttonStyle(RoundTransportButtonStyle(color: Theme.playGreen, isLit: deck.isPlaying))
                .accessibilityLabel(deck.isPlaying ? "Pause" : "Play")
                SilkLabel("Play/Pause")
            }
        }
        .disabled(deck.track == nil)
    }

    private func rubberButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(RubberButtonStyle(width: 40))
        .accessibilityLabel(label)
    }

    private var tempoColumn: some View {
        VStack(spacing: 6) {
            VStack(spacing: 3) {
                Button("SYNC") {}
                    .buttonStyle(RubberButtonStyle(width: 52, ledColor: color))
                    .disabled(deck.track == nil)
                SilkLabel("Beat Sync")
            }
            HStack(spacing: 2) {
                VStack {
                    SilkLabel("−", size: 10)
                    Spacer()
                    SilkLabel("0", size: 8)
                    Spacer()
                    SilkLabel("+", size: 10)
                }
                // Up is slower and down is faster, matching the tempo fader
                // direction on Pioneer CDJs.
                VerticalFader(value: Binding(get: { -deck.pitch }, set: { deck.pitch = -$0 }),
                              range: -8...8, color: color, tickCount: 17, centerDetent: true)
                    .frame(width: 44)
                    .accessibilityLabel("\(deck.name) Tempo")
            }
            .frame(height: 190)
            SilkLabel("Tempo ±8%")
        }
    }
}

/// The player's main screen: status tags, album art, track details,
/// boxed readouts and the waveform.
struct DeckDisplay: View {
    var deck: DeckModel
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                AlbumArtView(track: deck.track, color: color)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        tag("DECK \(deck.name)", inverted: true)
                        tag("TRACK \(trackNumber)")
                        tag(deck.isPlaying ? "PLAYING" : "PAUSED", inverted: deck.isPlaying)
                    }
                    .padding(.bottom, 2)
                    Text(deck.track?.title.uppercased() ?? "NO TRACK LOADED")
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                    Text(deck.track?.artist ?? "Use Load to choose a track")
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                    Text(deck.track?.album ?? " ")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.lcdDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                readout("REMAIN", remainingString, size: 18)
                readout("BPM", deck.effectiveBPM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "---.-", size: 18)
                readout("TEMPO", deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%", size: 13)
                readout("KEY", deck.track?.key ?? "--", size: 13)
            }

            WaveformView(seed: deck.track?.title ?? "", position: deck.position, color: color)
                .frame(height: 40)
                .opacity(deck.track == nil ? 0.3 : 1)
        }
        .lcdPanel(accent: color)
    }

    private var trackNumber: String {
        guard let track = deck.track,
              let index = Track.samples.firstIndex(where: { $0.id == track.id }) else { return "--" }
        return (index + 1).formatted(.number.precision(.integerLength(2)))
    }

    private var remainingString: String {
        guard let duration = deck.track?.duration else { return "-0:00" }
        return "-" + Duration.seconds(duration * (1 - deck.position)).formatted(.time(pattern: .minuteSecond))
    }

    /// A small status tag; inverted tags are drawn as lit blocks.
    private func tag(_ text: String, inverted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(inverted ? Color.black : Theme.lcdDim)
            .background(inverted ? Theme.lcdText : .clear, in: .rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.lcdDim, lineWidth: inverted ? 0 : 0.5))
            .fixedSize()
    }

    /// A boxed readout with a small caption, like a CDJ info field.
    private func readout(_ label: String, _ value: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.lcdDim)
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.lcdDim.opacity(0.6), lineWidth: 0.5))
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
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .bold))
                    Text(track.album)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                .foregroundStyle(.white.opacity(0.9))
            } else {
                Color.black.opacity(0.3)
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.lcdDim)
            }
        }
        .clipShape(.rect(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.lcdText.opacity(0.3), lineWidth: 1))
        .accessibilityLabel(track.map { "Album art for \($0.album)" } ?? "No album art")
    }
}

/// Placeholder waveform drawn from a deterministic pseudo-random sequence,
/// so each track gets a stable, distinct shape until real analysis exists.
/// Styled like a player overview: beat grid, bright peaks and a playhead.
struct WaveformView: View {
    var seed: String
    var position: Double
    var color: Color

    var body: some View {
        Canvas { context, size in
            let barCount = 160
            let barWidth = size.width / CGFloat(barCount)

            // Beat grid every 8 bars, plus a faint center line.
            for index in stride(from: 0, to: barCount, by: 8) {
                let x = CGFloat(index) * barWidth
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(.white.opacity(index % 32 == 0 ? 0.22 : 0.08)))
            }
            context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.25, width: size.width, height: 0.5)),
                         with: .color(.white.opacity(0.12)))

            var state = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) })
            for index in 0..<barCount {
                // Simple LCG for repeatable bar heights.
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let amplitude = 0.2 + 0.8 * Double(state >> 40) / Double(1 << 24)
                let height = size.height * amplitude
                let x = CGFloat(index) * barWidth
                let width = max(barWidth - 0.6, 0.8)
                let played = Double(index) / Double(barCount) < position
                context.fill(Path(CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)),
                             with: .color(color.opacity(played ? 0.3 : 0.85)))
                // Bright core, like the white peaks on a player waveform.
                let core = height * 0.4
                context.fill(Path(CGRect(x: x, y: (size.height - core) / 2, width: width, height: core)),
                             with: .color(.white.opacity(played ? 0.2 : 0.6)))
            }

            let playheadX = size.width * position
            context.fill(Path(CGRect(x: playheadX - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
        }
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

#Preview {
    let deck = DeckModel(name: "A")
    deck.load(Track.samples[0])
    deck.position = 0.35
    return DeckView(deck: deck, color: Theme.deckA)
        .frame(width: 440)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
