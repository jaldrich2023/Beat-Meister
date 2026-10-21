//
//  DeckModel.swift
//  Beat Meister
//

import AVFoundation
import AppKit
import Foundation
import Observation

/// A track that can be loaded onto a deck.
struct Track: Identifiable, Hashable {
    let id = UUID()
    /// The audio file on disk; nil for preview placeholders.
    var url: URL? = nil
    var title: String
    var artist: String
    var album: String
    /// From the file's tags, when present.
    var bpm: Double?
    /// Musical key from the file's tags, when present.
    var key: String?
    var duration: TimeInterval
    var artworkData: Data? = nil

    /// Placeholder tracks for SwiftUI previews.
    static let samples: [Track] = [
        Track(title: "Midnight Drive", artist: "Neon Avenue", album: "City Lights", bpm: 124, key: "8A", duration: 372),
        Track(title: "Pulse Theory", artist: "Kilowatt", album: "Voltage", bpm: 128, key: "5A", duration: 341),
        Track(title: "Afterglow", artist: "Static Bloom", album: "Night Garden", bpm: 122, key: "11B", duration: 405)
    ]
}

/// State for a single deck. Tracks are loaded from real audio files and
/// played through the deck's `DeckAudio` chain once attached to an engine.
@Observable
final class DeckModel {
    let name: String
    var track: Track?
    /// Tracks most recently imported onto this deck; Track Search steps through these.
    private(set) var playlist: [Track] = []
    /// Album art decoded from the current track's tags.
    private(set) var artwork: NSImage?
    /// Normalized waveform peaks for the current track; nil until analysis finishes.
    private(set) var waveform: [Float]?
    private(set) var isImporting = false
    private(set) var isAnalyzing = false
    var loadError: String?

    private(set) var isPlaying = false
    /// Playback position as a fraction of the track (0...1). Use `seek(to:)` to move it.
    private(set) var position: Double = 0
    /// Pitch adjustment in percent (-8...8).
    var pitch: Double = 0 {
        didSet { audio?.rate = Float(1 + pitch / 100) }
    }
    private(set) var cuePoint: Double = 0
    /// True while the jog wheel is held.
    private(set) var isJogging = false
    /// Position at which the jog display's marker points to 12 o'clock.
    private(set) var jogMarkerOrigin: Double = 0

    // Channel strip
    var volume: Double = 0.8 {
        didSet { applyGain() }
    }
    var high: Double = 0 {
        didSet { applyEQ() }
    }
    var mid: Double = 0 {
        didSet { applyEQ() }
    }
    var low: Double = 0 {
        didSet { applyEQ() }
    }
    /// Set by the crossfader.
    var crossfaderGain: Float = 1 {
        didSet { applyGain() }
    }

    @ObservationIgnored private var audio: DeckAudio?
    @ObservationIgnored private var resumeAfterJog = false
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var waveformTask: Task<Void, Never>?
    /// Files the sandbox has granted access to; held open while they're in the playlist.
    @ObservationIgnored private var accessedURLs: [URL] = []

    init(name: String) {
        self.name = name
    }

    /// Connects this deck to the shared engine so it can play audio.
    func attach(to engine: AVAudioEngine, format: AVAudioFormat?) {
        let audio: DeckAudio
        do {
            audio = try DeckAudio(engine: engine, format: format)
        } catch {
            loadError = "Deck \(name)’s audio couldn’t be set up: \(error.localizedDescription)"
            return
        }
        audio.onFinished = { [weak self] in self?.trackDidFinish() }
        audio.onError = { [weak self] in self?.loadError = $0 }
        self.audio = audio
        audio.rate = Float(1 + pitch / 100)
        applyGain()
        applyEQ()
    }

    /// Tempo and key estimated from the audio, used when the file has no tags.
    private(set) var detectedBPM: Double?
    private(set) var detectedKeys: [KeySection] = []

    /// The track's original tempo: from its tags, otherwise detected.
    var originalBPM: Double? {
        track?.bpm ?? detectedBPM
    }

    /// BPM after applying the tempo fader.
    var effectiveBPM: Double? {
        originalBPM.map { $0 * (1 + pitch / 100) }
    }

    /// The track's keys in the order they appear. A key tag is used unless
    /// the audio shows the track changing key, which a single tag can't express.
    var keySections: [KeySection] {
        if detectedKeys.count > 1 {
            return detectedKeys
        }
        if let tagged = track?.key.flatMap(CamelotKey.init(tag:)) {
            return [KeySection(key: tagged, start: 0)]
        }
        return detectedKeys
    }

    /// Index into `keySections` for the current playback position.
    var currentKeyIndex: Int? {
        let sections = keySections
        guard !sections.isEmpty else { return nil }
        let seconds = position * (track?.duration ?? 0)
        return sections.lastIndex { $0.start <= seconds } ?? 0
    }

    /// The key at the current playback position.
    var camelotKey: CamelotKey? {
        currentKeyIndex.map { keySections[$0].key }
    }

    /// True when the tempo fader is at the track's original tempo.
    var isAtOriginalTempo: Bool {
        abs(pitch) < 0.05
    }

    /// Returns the tempo fader to 0%, the track's original tempo.
    func resetTempo() {
        pitch = 0
    }

    /// 1-based position of the current track in the playlist.
    var trackNumber: Int? {
        guard let track, let index = playlist.firstIndex(where: { $0.id == track.id }) else { return nil }
        return index + 1
    }

    /// Reads the given audio files, replaces the playlist with them and loads
    /// the first one onto the deck. Non-audio files are skipped.
    func importTracks(from urls: [URL]) {
        let audioURLs = urls.filter(TrackLoader.isAudioFile)
        guard !audioURLs.isEmpty else {
            loadError = "None of the selected files are audio files."
            return
        }

        importTask?.cancel()
        releaseFileAccess()
        // Files chosen in the open panel are security-scoped; keep access
        // open for as long as they're in the playlist.
        for url in audioURLs where url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }

        isImporting = true
        importTask = Task {
            var loaded: [Track] = []
            var failures: [String] = []
            for url in audioURLs {
                do {
                    loaded.append(try await TrackLoader.loadTrack(from: url))
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            guard !Task.isCancelled else { return }

            isImporting = false
            playlist = loaded
            if let first = loaded.first {
                load(first)
            }
            if !failures.isEmpty {
                loadError = failures.joined(separator: "\n")
            }
        }
    }

    func load(_ track: Track) {
        stopProgressUpdates()
        isPlaying = false
        self.track = track
        position = 0
        cuePoint = 0
        jogMarkerOrigin = 0
        detectedBPM = nil
        detectedKeys = []
        artwork = track.artworkData.flatMap(NSImage.init(data:))
        waveform = nil

        if let url = track.url {
            do {
                try audio?.load(url: url)
            } catch {
                audio?.unload()
                loadError = "“\(track.title)” couldn’t be opened for playback: \(error.localizedDescription)"
            }
        } else {
            audio?.unload()
        }

        waveformTask?.cancel()
        guard let url = track.url else {
            isAnalyzing = false
            return
        }
        isAnalyzing = true
        waveformTask = Task {
            let decoded = try? await TrackLoader.decode(url: url)
            // Ignore results for a track that's no longer loaded.
            guard !Task.isCancelled, self.track?.id == track.id else { return }
            waveform = decoded?.peaks
            detectedBPM = decoded?.detectedBPM
            detectedKeys = decoded?.detectedKeys ?? []
            isAnalyzing = false
            if let decoded {
                // Playback still works if this fails; only jog audio is unavailable.
                audio?.installScrubber(decoded)
            }
        }
    }

    /// Moves the playhead to a fraction of the track, keeping play/pause state.
    func seek(to fraction: Double) {
        guard track != nil else { return }
        position = min(max(fraction, 0), 1)
        audio?.seek(toFraction: position, resume: isPlaying)
    }

    /// Moves the playhead by a number of seconds, clamped to the track.
    func skip(seconds: TimeInterval) {
        guard let duration = track?.duration, duration > 0 else { return }
        seek(to: position + seconds / duration)
    }

    /// Loads the adjacent track from the playlist (wrapping around).
    func loadAdjacent(offset: Int) {
        guard !playlist.isEmpty else { return }
        let currentIndex = (trackNumber ?? 1) - 1
        let nextIndex = (currentIndex + offset % playlist.count + playlist.count) % playlist.count
        load(playlist[nextIndex])
    }

    // MARK: Jog wheel

    /// Points the jog display's marker back to 12 o'clock without moving
    /// the playhead.
    func resetJogMarker() {
        jogMarkerOrigin = position
    }

    /// The jog wheel was touched. Playback pauses while it's held so the
    /// scrub audio follows the hand.
    func beginJog() {
        guard track != nil, !isJogging else { return }
        isJogging = true
        resumeAfterJog = isPlaying
        if isPlaying {
            audio?.pause()
            stopProgressUpdates()
        }
        audio?.beginScrub(atFraction: position)
    }

    /// The jog wheel turned by `seconds` of track (negative is backward).
    func jog(seconds: TimeInterval) {
        guard isJogging else {
            skip(seconds: seconds)
            return
        }
        guard let duration = track?.duration, duration > 0 else { return }
        position = min(max(position + seconds / duration, 0), 1)
        audio?.scrub(toFraction: position)
    }

    /// The jog wheel was released; playback resumes from the new position if
    /// the track was playing.
    func endJog() {
        guard isJogging else { return }
        isJogging = false
        audio?.endScrub()
        audio?.seek(toFraction: position, resume: resumeAfterJog && isPlaying)
        if resumeAfterJog && isPlaying {
            startProgressUpdates()
        }
    }

    func togglePlay() {
        // Releases a held jog first so playback state stays consistent.
        endJog()
        guard track != nil else { return }
        if isPlaying {
            audio?.pause()
            isPlaying = false
            stopProgressUpdates()
            return
        }

        // Pressing play at the end of the track starts again from the cue point.
        if position >= 1 {
            seek(to: cuePoint)
        }
        if let audio, audio.isLoaded {
            guard audio.play() else {
                loadError = "The audio output isn’t available."
                return
            }
            startProgressUpdates()
        }
        isPlaying = true
    }

    /// CDJ-style cue: while playing, returns to the cue point and pauses;
    /// while paused, sets the cue point at the current position.
    func cue() {
        guard track != nil else { return }
        if isPlaying {
            audio?.pause()
            isPlaying = false
            stopProgressUpdates()
            seek(to: cuePoint)
        } else {
            cuePoint = position
        }
    }

    /// The engine stopped (e.g. the output device changed); pause in place.
    func engineDidReset() {
        guard track != nil else { return }
        isPlaying = false
        stopProgressUpdates()
        audio?.seek(toFraction: position, resume: false)
    }

    // MARK: Playback internals

    private func trackDidFinish() {
        isPlaying = false
        stopProgressUpdates()
        position = 1
    }

    /// Polls the player for its position while playing so the display,
    /// waveform, needle search and jog display follow along.
    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let fraction = self.audio?.currentFraction {
                    self.position = fraction
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func applyGain() {
        // Squared taper so the fader feels even across its travel.
        audio?.gain = Float(volume * volume) * crossfaderGain
    }

    private func applyEQ() {
        audio?.setEQ(low: low, mid: mid, high: high)
    }

    private func releaseFileAccess() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }
}
