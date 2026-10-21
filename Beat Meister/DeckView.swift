//
//  DeckView.swift
//  Beat Meister
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A CDJ-style player: display and needle search on top, with search and
/// transport buttons left of the jog wheel and the tempo fader on the right.
struct DeckView: View {
    /// Minimum width of the deck's content, excluding the panel padding.
    static let minimumWidth: CGFloat = 590

    @Bindable var deck: DeckModel
    var color: Color

    @State private var isChoosingFiles = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            DeckDisplay(deck: deck, color: color, isDropTargeted: isDropTargeted)

            // Key sections on the same timeline as the needle search strip below.
            VStack(spacing: 3) {
                KeyStrip(sections: deck.keySections, currentIndex: deck.currentKeyIndex,
                         duration: deck.track?.duration ?? 0, position: deck.position,
                         isAnalyzing: deck.isAnalyzing)
                    .frame(height: 20)
                    .opacity(deck.track == nil ? 0.4 : 1)
                SilkLabel("Key Map")
            }

            VStack(spacing: 3) {
                NeedleSearchStrip(position: Binding(get: { deck.position }, set: { deck.seek(to: $0) }), color: color)
                    .accessibilityLabel("\(deck.name) Needle Search")
                SilkLabel("Needle Search")
            }
            .disabled(deck.track == nil)

            HStack(alignment: .center, spacing: 24) {
                buttonColumn
                JogWheel(color: color, isPlaying: deck.isPlaying, position: deck.position,
                         markerOrigin: deck.jogMarkerOrigin, size: 250,
                         onSeek: { deck.jog(seconds: $0) },
                         onTouch: { $0 ? deck.beginJog() : deck.endJog() },
                         onDoubleClick: { deck.resetJogMarker() })
                .disabled(deck.track == nil)
                    .frame(maxWidth: .infinity)
                tempoColumn
            }
        }
        .frame(minWidth: DeckView.minimumWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .neonPane(color, isLit: deck.isPlaying)
        .fileImporter(isPresented: $isChoosingFiles,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): deck.importTracks(from: urls)
            case .failure(let error): deck.loadError = error.localizedDescription
            }
        }
        // Drop audio files from Finder anywhere on the deck to load them.
        .dropDestination(for: URL.self) { urls, _ in
            deck.importTracks(from: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert("Couldn’t Load Track", isPresented: Binding(
            get: { deck.loadError != nil },
            set: { if !$0 { deck.loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deck.loadError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(deck.name)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.7), radius: 4)
            Menu("Load") {
                Button("Open Tracks…") { isChoosingFiles = true }
                if !deck.playlist.isEmpty {
                    Divider()
                    ForEach(deck.playlist) { track in
                        Toggle("\(track.title) — \(track.artist)", isOn: Binding(
                            get: { deck.track?.id == track.id },
                            set: { _ in deck.load(track) }
                        ))
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel("Load Deck \(deck.name)")
            Spacer()
            TempoIndicator(deck: deck)
            CamelotKeyBadge(sections: deck.keySections, currentIndex: deck.currentKeyIndex)
            Text("BEAT MEISTER")
                .font(.system(size: 11, weight: .black))
                .italic()
                .tracking(2)
                .foregroundStyle(Theme.silkscreen.opacity(0.7))
        }
    }

    /// Track search, search, CUE and PLAY/PAUSE, stacked as on a CDJ.
    private var buttonColumn: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    rubberButton("backward.end.fill", label: "Previous Track") { deck.loadAdjacent(offset: -1) }
                    rubberButton("forward.end.fill", label: "Next Track") { deck.loadAdjacent(offset: 1) }
                }
                SilkLabel("Track Search")
            }
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    rubberButton("backward.fill", label: "Back 10 Seconds") { deck.skip(seconds: -10) }
                    rubberButton("forward.fill", label: "Forward 10 Seconds") { deck.skip(seconds: 10) }
                }
                SilkLabel("Search")
            }
            VStack(spacing: 3) {
                Button("CUE", action: deck.cue)
                    .buttonStyle(RoundTransportButtonStyle(color: Theme.cueOrange,
                                                           isLit: deck.track != nil && !deck.isPlaying,
                                                           size: 66))
                SilkLabel("Cue")
            }
            VStack(spacing: 3) {
                Button {
                    deck.togglePlay()
                } label: {
                    Image(systemName: "playpause.fill")
                }
                .buttonStyle(RoundTransportButtonStyle(color: Theme.playGreen, isLit: deck.isPlaying, size: 66))
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
        .buttonStyle(RubberButtonStyle(width: 50, height: 32))
        .accessibilityLabel(label)
    }

    private var tempoColumn: some View {
        VStack(spacing: 6) {
            VStack(spacing: 3) {
                Button("SYNC") {}
                    .buttonStyle(RubberButtonStyle(width: 64, height: 32, ledColor: color))
                    .disabled(deck.track == nil)
                SilkLabel("Beat Sync")
            }
            HStack(spacing: 2) {
                VStack {
                    SilkLabel("−", size: 10)
                    Spacer()
                    // Lit while the track plays at its original tempo.
                    let isLit = deck.track != nil && deck.isAtOriginalTempo
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Theme.playGreen.opacity(isLit ? 1 : 0.18))
                            .frame(width: 6, height: 6)
                            .shadow(color: Theme.playGreen.opacity(isLit ? 0.8 : 0), radius: 3)
                        SilkLabel("0", size: 8)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(deck.isAtOriginalTempo ? "At original tempo" : "Tempo adjusted")
                    Spacer()
                    SilkLabel("+", size: 10)
                }
                // Up is slower and down is faster, matching the tempo fader
                // direction on Pioneer CDJs.
                VerticalFader(value: Binding(get: { -deck.pitch }, set: { deck.pitch = -$0 }),
                              range: -8...8, color: color, tickCount: 17, centerDetent: true)
                    .frame(width: 50)
                    .accessibilityLabel("\(deck.name) Tempo")
                    .accessibilityHint("Double-click to return to the track’s original tempo")
                    .help("Double-click to return to the track’s original tempo")
            }
            .frame(height: 260)
            SilkLabel("Tempo ±8%")
        }
    }
}

/// Header readout of the deck's current tempo, with the original tempo
/// or adjustment underneath and a light that's on at the original tempo.
struct TempoIndicator: View {
    var deck: DeckModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.playGreen.opacity(deck.track != nil && deck.isAtOriginalTempo ? 1 : 0.18))
                .frame(width: 6, height: 6)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(bpmText)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.lcdText)
                    Text("BPM")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.lcdDim)
                }
                Text(detailText)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.lcdDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(white: 0.03), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lcdDim.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue(deck.effectiveBPM.map { "\($0.formatted(.number.precision(.fractionLength(1)))) BPM, \(detailText)" } ?? "Unknown")
    }

    private var bpmText: String {
        deck.effectiveBPM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "---.-"
    }

    /// The original tempo when unchanged, otherwise the adjustment.
    private var detailText: String {
        guard let original = deck.originalBPM else {
            return deck.isAnalyzing ? "DETECTING" : "NO TEMPO"
        }
        if deck.isAtOriginalTempo {
            return "ORIG \(original.formatted(.number.precision(.fractionLength(1))))"
        }
        return deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "% TEMPO"
    }
}

/// Header badge showing the Camelot key at the playhead, colored by its
/// position on the Camelot wheel, with the conventional key name beside it.
/// Tracks that change key also list every key in the order it appears, with
/// the current one highlighted.
struct CamelotKeyBadge: View {
    var sections: [KeySection]
    var currentIndex: Int?

    private var currentKey: CamelotKey? {
        currentIndex.map { sections[$0].key }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(currentKey?.code ?? "--")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(currentKey == nil ? Theme.lcdDim : .black)
                .frame(minWidth: 34)
                .padding(.vertical, 2)
                .background(Self.color(for: currentKey), in: .rect(cornerRadius: 5))
            if sections.count > 1 {
                keySequence
            } else {
                Text(currentKey?.musicalName ?? "KEY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.lcdDim)
                    .frame(minWidth: 26, alignment: .leading)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color(white: 0.03), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lcdDim.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sections.count > 1 ? "Camelot Keys" : "Camelot Key")
        .accessibilityValue(accessibilityText)
    }

    /// Every key in order, e.g. 8A › 9A › 8A, with the current one lit.
    private var keySequence: some View {
        let visible = Array(sections.prefix(4).enumerated())
        return HStack(spacing: 2) {
            ForEach(visible, id: \.offset) { index, section in
                if index > 0 {
                    Text("›")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.lcdDim)
                }
                let isCurrent = index == currentIndex
                Text(section.key.code)
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(isCurrent ? .black : Self.color(for: section.key))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(isCurrent ? Self.color(for: section.key) : .clear, in: .rect(cornerRadius: 3))
            }
            if sections.count > visible.count {
                Text("+\(sections.count - visible.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.lcdDim)
            }
        }
    }

    private var accessibilityText: String {
        guard !sections.isEmpty else { return "Unknown" }
        let keys = sections.map { "\($0.key.code), \($0.key.musicalName)" }
        guard sections.count > 1, let currentKey else { return keys.joined() }
        return "Now \(currentKey.code). In order: " + keys.joined(separator: "; then ")
    }

    /// Standard Camelot wheel coloring; minor keys are a lighter tint.
    static func color(for key: CamelotKey?) -> Color {
        guard let key else { return Color(white: 0.12) }
        return Color(hue: key.wheelHue, saturation: key.isMinor ? 0.55 : 0.75, brightness: 0.95)
    }
}

/// The player's main screen: status tags, album art, track details,
/// boxed readouts and the waveform.
struct DeckDisplay: View {
    var deck: DeckModel
    var color: Color
    var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                AlbumArtView(track: deck.track, artwork: deck.artwork, color: color)
                    .frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        tag("DECK \(deck.name)", inverted: true)
                        tag("TRACK \(trackNumber)")
                        if deck.isImporting {
                            tag("LOADING…", inverted: true)
                        } else {
                            tag(deck.isPlaying ? "PLAYING" : "PAUSED", inverted: deck.isPlaying)
                        }
                    }
                    .padding(.bottom, 2)
                    Text(deck.track?.title.uppercased() ?? "NO TRACK LOADED")
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                    Text(deck.track?.artist ?? "Use Load or drop audio files here")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Text(deck.track.map { $0.album.isEmpty ? " " : $0.album } ?? " ")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.lcdDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                readout("REMAIN", remainingString, size: 24)
                readout("BPM", deck.effectiveBPM.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "---.-", size: 24)
                readout("TEMPO", deck.pitch.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%", size: 18)
                readout(keyLabel, deck.camelotKey.map { "\($0.code) \($0.musicalName)" } ?? "--", size: 18)
            }

            WaveformView(seed: deck.track?.title ?? "", peaks: deck.waveform,
                         isAnalyzing: deck.isAnalyzing, position: deck.position, color: color)
                .frame(height: 64)
                .opacity(deck.track == nil ? 0.3 : 1)
        }
        .lcdPanel(accent: color)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.black.opacity(0.65))
                    .overlay {
                        Text("DROP TO LOAD DECK \(deck.name)")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.lcdText)
                    }
                    .padding(7)
            }
        }
    }

    /// "KEY", or "KEY 2/3" for tracks that change key.
    private var keyLabel: String {
        let count = deck.keySections.count
        guard count > 1, let index = deck.currentKeyIndex else { return "KEY" }
        return "KEY \(index + 1)/\(count)"
    }

    private var trackNumber: String {
        deck.trackNumber?.formatted(.number.precision(.integerLength(2))) ?? "--"
    }

    private var remainingString: String {
        guard let duration = deck.track?.duration else { return "-0:00" }
        return "-" + Duration.seconds(duration * (1 - deck.position)).formatted(.time(pattern: .minuteSecond))
    }

    /// A small status tag; inverted tags are drawn as lit blocks.
    private func tag(_ text: String, inverted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10.625, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(inverted ? Color.black : Theme.lcdDim)
            .background(inverted ? Theme.lcdText : .clear, in: .rect(cornerRadius: 5))
            // A full 1pt border on whole-point padding keeps every edge pixel-aligned,
            // so the bottom line doesn't fade out.
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.lcdDim, lineWidth: inverted ? 0 : 1))
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
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.lcdDim.opacity(0.6), lineWidth: 0.5))
    }
}

/// Album art for the loaded track. Tracks without embedded artwork get a
/// placeholder cover tinted with the deck color.
struct AlbumArtView: View {
    var track: Track?
    var artwork: NSImage? = nil
    var color: Color

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else if let track {
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
        .accessibilityLabel(track.map { "Album art for \($0.album.isEmpty ? $0.title : $0.album)" } ?? "No album art")
    }
}

/// A map of the track's keys along the track's timeline: one segment per key
/// section, placed from where that key starts to where the next begins,
/// colored on the Camelot wheel. The section under the playhead is brighter.
struct KeyStrip: View {
    var sections: [KeySection]
    var currentIndex: Int?
    var duration: TimeInterval
    var position: Double
    var isAnalyzing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                if duration > 0, !sections.isEmpty {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        let (start, end) = bounds(of: index)
                        let segmentWidth = max(width * (end - start) / duration - 1, 1)
                        let isCurrent = index == currentIndex
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CamelotKeyBadge.color(for: section.key).opacity(isCurrent ? 0.95 : 0.45))
                            .overlay(alignment: .leading) {
                                // Show as much as fits: key and start time, key only, or nothing.
                                Group {
                                    if segmentWidth > 80 {
                                        Text("\(section.key.code) · \(time(start))")
                                    } else if segmentWidth > 28 {
                                        Text(section.key.code)
                                    }
                                }
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.black.opacity(isCurrent ? 0.9 : 0.7))
                                .lineLimit(1)
                                .padding(.leading, 6)
                            }
                            .overlay(alignment: .leading) {
                                // Divider marking where this key begins.
                                if index > 0 {
                                    Rectangle()
                                        .fill(.black.opacity(0.8))
                                        .frame(width: 2)
                                        .offset(x: -1.5)
                                }
                            }
                            .frame(width: segmentWidth)
                            .offset(x: width * start / duration)
                            .help("\(section.key.code) \(section.key.musicalName): \(time(start))–\(time(end))")
                    }
                } else {
                    Text(isAnalyzing ? "ANALYZING KEYS…" : "NO KEY DATA")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.lcdDim)
                        .frame(maxWidth: .infinity)
                }
                // Playhead, matching the waveform's.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: width * position - 1)
            }
        }
        .padding(2)
        .background(.black.opacity(0.85), in: .rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Metal.bevel, lineWidth: 1).rotationEffect(.degrees(180)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key Map")
        .accessibilityValue(accessibilityText)
    }

    /// Start and end time of a section; each runs until the next begins.
    private func bounds(of index: Int) -> (TimeInterval, TimeInterval) {
        let start = min(sections[index].start, duration)
        let end = index + 1 < sections.count ? min(sections[index + 1].start, duration) : duration
        return (start, max(end, start))
    }

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private var accessibilityText: String {
        guard duration > 0, !sections.isEmpty else { return isAnalyzing ? "Analyzing" : "No key data" }
        return sections.indices.map { index in
            let (start, end) = bounds(of: index)
            let key = sections[index].key
            return "\(key.code) \(key.musicalName) from \(time(start)) to \(time(end))"
        }.joined(separator: "; ")
    }
}

/// Overview waveform styled like a player display: beat grid, bright peaks
/// and a playhead. Draws the analyzed `peaks` when available; otherwise a
/// deterministic placeholder shape seeded from `seed` (used for an empty
/// deck and previews).
struct WaveformView: View {
    var seed: String
    var peaks: [Float]? = nil
    var isAnalyzing = false
    var position: Double
    var color: Color

    var body: some View {
        Canvas { context, size in
            // Beat grid, plus a faint center line.
            let gridCount = 160
            for index in stride(from: 0, to: gridCount, by: 8) {
                let x = size.width * CGFloat(index) / CGFloat(gridCount)
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(.white.opacity(index % 32 == 0 ? 0.22 : 0.08)))
            }
            context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.25, width: size.width, height: 0.5)),
                         with: .color(.white.opacity(0.12)))

            let amplitudes = barAmplitudes(width: size.width)
            let barWidth = size.width / CGFloat(max(amplitudes.count, 1))
            for (index, amplitude) in amplitudes.enumerated() {
                let height = max(size.height * CGFloat(amplitude), 1)
                let x = CGFloat(index) * barWidth
                let width = max(barWidth - 0.6, 0.8)
                let played = Double(index) / Double(amplitudes.count) < position
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
        .overlay {
            if isAnalyzing {
                Text("ANALYZING…")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.lcdDim)
            }
        }
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 3))
        .accessibilityHidden(true)
    }

    /// Bar heights (0...1) to draw across the given width.
    private func barAmplitudes(width: CGFloat) -> [Float] {
        if let peaks, !peaks.isEmpty {
            // Resample the analyzed peaks to one bar every ~2pt, keeping the
            // loudest value in each group so transients stay visible.
            let barCount = min(max(Int(width / 2), 1), peaks.count)
            return (0..<barCount).map { bar in
                let start = bar * peaks.count / barCount
                let end = max((bar + 1) * peaks.count / barCount, start + 1)
                return peaks[start..<end].max() ?? 0
            }
        }
        if isAnalyzing { return [] }

        var state = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) })
        return (0..<160).map { _ in
            // Simple LCG for repeatable bar heights.
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return 0.2 + 0.8 * Float(state >> 40) / Float(1 << 24)
        }
    }
}

#Preview {
    let deck = DeckModel(name: "A")
    deck.load(Track.samples[0])
    deck.seek(to: 0.35)
    return DeckView(deck: deck, color: Theme.deckA)
        .frame(width: 680)
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("Key Badges") {
    let gMinor = CamelotKey(pitchClass: 7, isMinor: true)
    let eFlatMajor = CamelotKey(pitchClass: 3, isMinor: false)
    VStack(alignment: .trailing, spacing: 12) {
        CamelotKeyBadge(sections: [], currentIndex: nil)
        CamelotKeyBadge(sections: [KeySection(key: gMinor, start: 0)], currentIndex: 0)
        CamelotKeyBadge(sections: [KeySection(key: gMinor, start: 0), KeySection(key: eFlatMajor, start: 37),
                                   KeySection(key: gMinor, start: 67)], currentIndex: 1)
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Key Strip") {
    let gMinor = CamelotKey(pitchClass: 7, isMinor: true)
    let eFlatMajor = CamelotKey(pitchClass: 3, isMinor: false)
    let sections = [KeySection(key: gMinor, start: 0), KeySection(key: eFlatMajor, start: 96),
                    KeySection(key: gMinor, start: 212)]
    VStack(spacing: 10) {
        KeyStrip(sections: sections, currentIndex: 1, duration: 300, position: 0.45)
        KeyStrip(sections: [KeySection(key: gMinor, start: 0)], currentIndex: 0, duration: 300, position: 0.2)
        KeyStrip(sections: [], currentIndex: nil, duration: 300, position: 0, isAnalyzing: true)
    }
    .frame(width: 520)
    .frame(height: 90)
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
