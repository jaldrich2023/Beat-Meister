//
//  DeckModel.swift
//  Beat Meister
//

import Foundation
import Observation

/// A track that can be loaded onto a deck.
struct Track: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var artist: String
    var album: String
    var bpm: Double
    var key: String
    var duration: TimeInterval

    /// Placeholder tracks until real file import is added.
    static let samples: [Track] = [
        Track(title: "Midnight Drive", artist: "Neon Avenue", album: "City Lights", bpm: 124, key: "8A", duration: 372),
        Track(title: "Pulse Theory", artist: "Kilowatt", album: "Voltage", bpm: 128, key: "5A", duration: 341),
        Track(title: "Afterglow", artist: "Static Bloom", album: "Night Garden", bpm: 122, key: "11B", duration: 405),
        Track(title: "Concrete Jungle", artist: "Sub Level", album: "Underpass", bpm: 174, key: "2A", duration: 298),
        Track(title: "Velvet Room", artist: "Low Hours", album: "Late Sessions", bpm: 118, key: "9B", duration: 389),
        Track(title: "Signal Lost", artist: "Echo Chamber", album: "Reverb", bpm: 130, key: "4A", duration: 356)
    ]
}

/// UI state for a single deck. Audio playback is not wired up yet.
@Observable
final class DeckModel {
    let name: String
    var track: Track?
    var isPlaying = false
    /// Playback position as a fraction of the track (0...1).
    var position: Double = 0
    /// Pitch adjustment in percent (-8...8).
    var pitch: Double = 0
    var cuePoint: Double = 0

    // Channel strip
    var volume: Double = 0.8
    var high: Double = 0
    var mid: Double = 0
    var low: Double = 0

    init(name: String) {
        self.name = name
    }

    /// BPM after applying the pitch adjustment.
    var effectiveBPM: Double? {
        track.map { $0.bpm * (1 + pitch / 100) }
    }

    func load(_ track: Track) {
        self.track = track
        isPlaying = false
        position = 0
        cuePoint = 0
    }

    /// Moves the playhead by a number of seconds, clamped to the track.
    func skip(seconds: TimeInterval) {
        guard let duration = track?.duration, duration > 0 else { return }
        position = min(max(position + seconds / duration, 0), 1)
    }

    /// Loads the adjacent track from the sample list (wrapping around).
    func loadAdjacent(offset: Int) {
        let tracks = Track.samples
        guard !tracks.isEmpty else { return }
        let currentIndex = track.flatMap { current in tracks.firstIndex { $0.id == current.id } } ?? 0
        let nextIndex = (currentIndex + offset + tracks.count) % tracks.count
        load(tracks[nextIndex])
    }

    func togglePlay() {
        guard track != nil else { return }
        isPlaying.toggle()
    }

    func cue() {
        isPlaying = false
        position = cuePoint
    }
}
