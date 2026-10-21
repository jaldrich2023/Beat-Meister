//
//  TrackLoader.swift
//  Beat Meister
//
//  Reads metadata and decodes audio files on disk.
//

import AVFoundation
import Accelerate
import UniformTypeIdentifiers

enum TrackLoaderError: LocalizedError {
    case noAudio(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .noAudio(let name): "“\(name)” doesn’t contain any audio."
        case .unreadable(let name): "“\(name)” couldn’t be decoded."
        }
    }
}

/// A fully decoded track: waveform peaks plus the samples themselves.
struct DecodedAudio: Sendable {
    /// Normalized waveform peaks (0...1).
    var peaks: [Float]
    var left: [Float]
    /// Empty for mono files.
    var right: [Float]
    var sampleRate: Double
    /// Tempo detected from the audio, if it could be estimated.
    var detectedBPM: Double?
    /// Keys detected from the audio, in the order they appear.
    var detectedKeys: [KeySection] = []
}

enum TrackLoader {
    /// Returns true if the file at `url` is an audio file the decks can load.
    nonisolated static func isAudioFile(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .audio) ?? false
    }

    /// Reads a file's tags (title, artist, album, artwork, BPM, key) and duration.
    /// Missing tags fall back to the file name or are left empty.
    static func loadTrack(from url: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        let fileName = url.deletingPathExtension().lastPathComponent

        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw TrackLoaderError.noAudio(url.lastPathComponent)
        }
        let (duration, commonMetadata, allMetadata) = try await asset.load(.duration, .commonMetadata, .metadata)

        let title = await string(for: .commonIdentifierTitle, in: commonMetadata)
        let artist = await string(for: .commonIdentifierArtist, in: commonMetadata)
        let album = await string(for: .commonIdentifierAlbumName, in: commonMetadata)
        let artwork = await data(for: .commonIdentifierArtwork, in: commonMetadata)
        let bpm = await number(for: [.id3MetadataBeatsPerMinute, .iTunesMetadataBeatsPerMin], in: allMetadata)
        let key = await string(for: .id3MetadataInitialKey, in: allMetadata)

        return Track(url: url,
                     title: title ?? fileName,
                     artist: artist ?? "Unknown Artist",
                     album: album ?? "",
                     bpm: bpm,
                     key: key,
                     duration: duration.seconds.isFinite ? duration.seconds : 0,
                     artworkData: artwork)
    }

    /// Decodes the whole file into memory (for jog scrubbing), reduces it to
    /// `binCount` normalized peak values (0...1) for drawing the waveform, and
    /// estimates tempo and key. Runs off the main actor.
    @concurrent
    nonisolated static func decode(url: URL, binCount: Int = 800) async throws -> DecodedAudio {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TrackLoaderError.unreadable(url.lastPathComponent)
        }
        let format = file.processingFormat
        let totalFrames = Int(file.length)
        let isStereo = format.channelCount > 1
        let chunkSize: AVAudioFrameCount = 1 << 16
        guard totalFrames > 0, binCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw TrackLoaderError.unreadable(url.lastPathComponent)
        }

        // Keep at most two channels; mono files leave `right` empty.
        var left = [Float]()
        var right = [Float]()
        left.reserveCapacity(totalFrames)
        if isStereo { right.reserveCapacity(totalFrames) }

        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: chunkSize)
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0, let channels = buffer.floatChannelData else { break }
            left.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: frameCount))
            if isStereo {
                right.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: frameCount))
            }
        }

        // Loudest sample across both channels in each bin.
        let framesPerBin = max(left.count / binCount, 1)
        var peaks = [Float](repeating: 0, count: binCount)
        for bin in 0..<binCount {
            let start = bin * framesPerBin
            guard start < left.count else { break }
            let end = bin == binCount - 1 ? left.count : min(start + framesPerBin, left.count)
            for channel in isStereo ? [left, right] : [left] {
                channel.withUnsafeBufferPointer { samples in
                    var peak: Float = 0
                    vDSP_maxmgv(samples.baseAddress! + start, 1, &peak, vDSP_Length(end - start))
                    peaks[bin] = max(peaks[bin], peak)
                }
            }
        }
        // Normalize so the loudest peak fills the display.
        if let loudest = peaks.max(), loudest > 0 {
            vDSP.divide(peaks, loudest, result: &peaks)
        }

        try Task.checkCancellation()
        let mono = isStereo ? vDSP.multiply(0.5, vDSP.add(left, right)) : left
        let bpm = MusicAnalysis.detectBPM(mono: mono, sampleRate: format.sampleRate)
        try Task.checkCancellation()
        let keys = MusicAnalysis.detectKeys(mono: mono, sampleRate: format.sampleRate)

        return DecodedAudio(peaks: peaks, left: left, right: right, sampleRate: format.sampleRate,
                            detectedBPM: bpm, detectedKeys: keys)
    }

    // MARK: - Metadata helpers

    private static func items(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) -> [AVMetadataItem] {
        AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
    }

    private static func string(for identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        for item in items(identifier, in: metadata) {
            if let value = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func data(for identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> Data? {
        for item in items(identifier, in: metadata) {
            if let value = try? await item.load(.dataValue) {
                return value
            }
        }
        return nil
    }

    /// BPM tags may be stored as numbers or as text, depending on the format.
    private static func number(for identifiers: [AVMetadataIdentifier], in metadata: [AVMetadataItem]) async -> Double? {
        for identifier in identifiers {
            for item in items(identifier, in: metadata) {
                if let value = try? await item.load(.numberValue)?.doubleValue, value > 0 {
                    return value
                }
                if let text = try? await item.load(.stringValue), let value = Double(text), value > 0 {
                    return value
                }
            }
        }
        return nil
    }
}
