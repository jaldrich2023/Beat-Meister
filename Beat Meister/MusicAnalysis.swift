//
//  MusicAnalysis.swift
//  Beat Meister
//
//  Camelot keys, plus tempo and key detection for tracks without tags,
//  including tracks that change key.
//

import Accelerate
import Foundation

/// A key on the Camelot wheel: 1–12 around the wheel, A for minor, B for major.
/// Neighboring numbers and the same number in the other letter mix harmonically.
nonisolated struct CamelotKey: Hashable, Sendable {
    /// 1...12
    let number: Int
    let isMinor: Bool

    init?(number: Int, isMinor: Bool) {
        guard (1...12).contains(number) else { return nil }
        self.number = number
        self.isMinor = isMinor
    }

    /// Creates the key for a tonic pitch class (0 = C … 11 = B).
    init(pitchClass: Int, isMinor: Bool) {
        // Each step clockwise on the wheel is a fifth (7 semitones); C major is 8B
        // and a minor key shares a number with its relative major.
        let majorPitchClass = isMinor ? pitchClass + 3 : pitchClass
        let number = ((majorPitchClass % 12 + 12) % 12 * 7 + 7) % 12 + 1
        self.number = number
        self.isMinor = isMinor
    }

    /// Parses a key tag written in Camelot ("8A"), Open Key ("1m", "1d") or
    /// standard notation ("Am", "A minor", "F#", "Bbm", "Eb major").
    init?(tag: String) {
        let text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard !text.isEmpty else { return nil }

        // Camelot or Open Key: a number followed by A/B or m/d.
        if let match = text.wholeMatch(of: /0?(\d{1,2})\s*([ABab]|[mMdD])/),
           let value = Int(match.1), (1...12).contains(value) {
            switch match.2.lowercased() {
            case "a": self.init(number: value, isMinor: true)
            case "b": self.init(number: value, isMinor: false)
            // Open Key 1 is C major / A minor, which is Camelot 8.
            case "m": self.init(number: (value + 6) % 12 + 1, isMinor: true)
            default: self.init(number: (value + 6) % 12 + 1, isMinor: false)
            }
            return
        }

        // Standard notation: note letter, optional accidental, optional mode.
        guard let match = text.wholeMatch(of: /([A-Ga-g])\s*([#b]?)\s*([A-Za-z]*)/) else { return nil }
        let letters: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard var pitchClass = letters[match.1.uppercased()] else { return nil }
        if match.2 == "#" { pitchClass += 1 }
        if match.2 == "b" { pitchClass -= 1 }

        let mode = String(match.3)
        let isMinor: Bool
        switch mode.lowercased() {
        case "": isMinor = false
        case "m" where mode == "M": isMinor = false   // Capital M means major.
        case "m", "min", "minor", "mi": isMinor = true
        case "maj", "major": isMinor = false
        default: return nil
        }
        self.init(pitchClass: pitchClass, isMinor: isMinor)
    }

    /// Camelot code, e.g. "8A".
    var code: String { "\(number)\(isMinor ? "A" : "B")" }

    /// Conventional key name, e.g. "Am" or "E♭".
    var musicalName: String {
        // Invert the wheel mapping to get the major tonic, then shift for minor.
        let majorPitchClass = ((number - 8) * 7 % 12 + 12) % 12
        if isMinor {
            let names = ["Cm", "C♯m", "Dm", "E♭m", "Em", "Fm", "F♯m", "Gm", "G♯m", "Am", "B♭m", "Bm"]
            return names[(majorPitchClass + 9) % 12]
        }
        let names = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return names[majorPitchClass]
    }

    /// Position around the wheel (0...1), used for its standard color coding.
    var wheelHue: Double {
        Double(number - 1) / 12
    }
}

/// A stretch of a track in one key.
nonisolated struct KeySection: Hashable, Sendable {
    var key: CamelotKey
    /// Seconds from the start of the track.
    var start: TimeInterval
}

/// Tempo and key estimation from decoded audio.
nonisolated enum MusicAnalysis {
    // MARK: Tempo

    /// Estimates beats per minute from the track's onset envelope.
    ///
    /// Builds an energy envelope, keeps only rises in energy (where beats hit),
    /// then finds the beat period by autocorrelation in the 70–180 BPM range.
    static func detectBPM(mono samples: [Float], sampleRate: Double) -> Double? {
        let hop = max(Int(sampleRate / 344), 1)       // ~344 envelope frames per second
        let window = hop * 8
        let frameCount = (samples.count - window) / hop
        guard frameCount > 1_000 else { return nil }

        var envelope = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buffer in
            for frame in 0..<frameCount {
                var rms: Float = 0
                vDSP_rmsqv(buffer.baseAddress! + frame * hop, 1, &rms, vDSP_Length(window))
                envelope[frame] = log1p(1_000 * rms)
            }
        }

        // Onset strength: positive changes in energy, with the mean removed.
        var onset = [Float](repeating: 0, count: frameCount)
        for frame in 1..<frameCount {
            onset[frame] = max(0, envelope[frame] - envelope[frame - 1])
        }
        // A steady sound has no real onsets, only numerical ripple.
        guard vDSP.maximum(onset) > 0.05 else { return nil }
        let mean = vDSP.mean(onset)
        onset = vDSP.add(-mean, onset)

        let frameRate = sampleRate / Double(hop)
        let minLag = Int(frameRate * 60 / 180)
        let maxLag = Int(frameRate * 60 / 70)
        guard maxLag * 4 < frameCount else { return nil }

        // Autocorrelation for every lag up to four beats.
        var correlation = [Float](repeating: 0, count: maxLag * 4 + 2)
        onset.withUnsafeBufferPointer { buffer in
            for lag in minLag..<correlation.count {
                var dot: Float = 0
                vDSP_dotpr(buffer.baseAddress!, 1, buffer.baseAddress! + lag, 1, &dot, vDSP_Length(frameCount - lag))
                correlation[lag] = dot / Float(frameCount - lag)
            }
        }

        // Reward lags whose multiples also line up (bars of 2 and 4 beats),
        // which favors the true beat over off-beat patterns.
        func score(_ lag: Int) -> Float {
            correlation[lag] + 0.5 * correlation[lag * 2] + 0.25 * correlation[lag * 4]
        }
        var bestLag = minLag
        for lag in minLag...maxLag where score(lag) > score(bestLag) {
            bestLag = lag
        }
        // No periodic onsets (silence, ambient pads): no tempo to report.
        let energy = correlation[minLag...maxLag].map { abs($0) }.max() ?? 0
        guard energy > 1e-6, score(bestLag) > 0 else { return nil }

        // Refine using the peak four beats out: the same timing error spread
        // over four beats gives four times the precision. Parabolic
        // interpolation then adds sub-frame accuracy.
        var fourBeatLag = bestLag * 4
        for lag in max(fourBeatLag - 4, minLag)...min(fourBeatLag + 4, correlation.count - 2)
        where correlation[lag] > correlation[fourBeatLag] {
            fourBeatLag = lag
        }
        var refinedFourBeatLag = Double(fourBeatLag)
        let left = Double(correlation[fourBeatLag - 1])
        let center = Double(correlation[fourBeatLag])
        let right = Double(correlation[fourBeatLag + 1])
        let denominator = left - 2 * center + right
        if denominator != 0 {
            refinedFourBeatLag += 0.5 * (left - right) / denominator
        }
        let refinedLag = refinedFourBeatLag / 4

        let bpm = 60 * frameRate / refinedLag
        guard (65...185).contains(bpm) else { return nil }
        // Most tracks are produced at a whole-number tempo; snap when close.
        if abs(bpm - bpm.rounded()) < 0.15 {
            return bpm.rounded()
        }
        return (bpm * 10).rounded() / 10
    }

    // MARK: Key

    /// Estimates the key over time, returning each key in the order it
    /// appears. Most tracks yield one section; tracks that modulate yield one
    /// per key change.
    ///
    /// The track is split into ~7-second blocks. Each block gets a 12-note
    /// chroma profile from the spectrum, scored against all 24 major/minor key
    /// profiles (Krumhansl–Schmuckler), with a bonus for the key whose tonic
    /// the bass dwells on. A best-path search with a penalty for changing key
    /// then smooths the per-block guesses, so a single odd block doesn't
    /// register as a modulation but a sustained change does.
    static func detectKeys(mono samples: [Float], sampleRate: Double) -> [KeySection] {
        // Work at ~11 kHz; the notes that define the key are well below that.
        let factor = max(Int(sampleRate / 11_025), 1)
        let rate = sampleRate / Double(factor)
        let reducedCount = samples.count / factor - 1
        guard reducedCount > 0 else { return [] }
        var reduced = [Float](repeating: 0, count: reducedCount)
        let averagingFilter = [Float](repeating: 1 / Float(factor), count: factor)
        vDSP_desamp(samples, vDSP_Stride(factor), averagingFilter, &reduced,
                    vDSP_Length(reducedCount), vDSP_Length(factor))

        let size = 8_192
        guard reduced.count > size * 4,
              let dft = try? vDSP.DiscreteFourierTransform(previous: nil, count: size, direction: .forward,
                                                           transformType: .complexComplex, ofType: Float.self)
        else { return [] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        let frameDuration = Double(size) / rate

        // Map each FFT bin between ~A1 and ~C7 to a pitch class, and note
        // which bins are bass. The bass band starts above most kick-drum
        // fundamentals (40–65 Hz) so the kick doesn't drown out the bass line.
        var binPitchClass = [Int](repeating: -1, count: size / 2)
        var isBassBin = [Bool](repeating: false, count: size / 2)
        for bin in 1..<size / 2 {
            let frequency = Double(bin) * rate / Double(size)
            guard (55...2_100).contains(frequency) else { continue }
            let midiNote = 69 + 12 * log2(frequency / 440)
            binPitchClass[bin] = (Int(midiNote.rounded()) % 12 + 12) % 12
            isBassBin[bin] = (65...160).contains(frequency)
        }

        // Chroma for each block of frames.
        let framesPerBlock = 10
        var blockChroma: [[Double]] = []
        var blockBass: [[Double]] = []
        var chroma = [Double](repeating: 0, count: 12)
        var bass = [Double](repeating: 0, count: 12)
        var framesInBlock = 0
        let zeros = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: size)
        var imaginary = [Float](repeating: 0, count: size)
        for offset in stride(from: 0, through: reduced.count - size, by: size) {
            let frame = vDSP.multiply(window, reduced[offset..<offset + size])
            dft.transform(inputReal: frame, inputImaginary: zeros, outputReal: &real, outputImaginary: &imaginary)
            for bin in 1..<size / 2 where binPitchClass[bin] >= 0 {
                let magnitude = (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]).squareRoot()
                let weight = Double(log1p(magnitude))
                chroma[binPitchClass[bin]] += weight
                if isBassBin[bin] {
                    bass[binPitchClass[bin]] += weight
                }
            }
            framesInBlock += 1
            if framesInBlock == framesPerBlock {
                blockChroma.append(chroma)
                blockBass.append(bass)
                chroma = [Double](repeating: 0, count: 12)
                bass = [Double](repeating: 0, count: 12)
                framesInBlock = 0
            }
        }
        // Keep a partial final block only if it's substantial.
        if framesInBlock >= framesPerBlock / 2 || blockChroma.isEmpty {
            blockChroma.append(chroma)
            blockBass.append(bass)
        }

        // Score every key for every block. Near-silent blocks score 0 for all
        // keys, so they never cause a change on their own.
        let candidates = (0..<12).flatMap { tonic in
            [CamelotKey(pitchClass: tonic, isMinor: false), CamelotKey(pitchClass: tonic, isMinor: true)]
        }
        let tonics = (0..<12).flatMap { [$0, $0] }
        let profiles = (0..<candidates.count).map { index in
            let profile = candidates[index].isMinor ? minorProfile : majorProfile
            return (0..<12).map { profile[($0 - tonics[index] + 12) % 12] }
        }
        let loudestBlock = blockChroma.map { $0.reduce(0, +) }.max() ?? 0
        guard loudestBlock > 0 else { return [] }
        let scores: [[Double]] = zip(blockChroma, blockBass).map { chroma, bass in
            guard chroma.reduce(0, +) > loudestBlock * 0.1 else {
                return [Double](repeating: 0, count: candidates.count)
            }
            let loudestBass = bass.max() ?? 0
            return (0..<candidates.count).map { index in
                let tonicBass = loudestBass > 0 ? bass[tonics[index]] / loudestBass : 0
                return correlation(chroma, profiles[index]) + 0.3 * tonicBass
            }
        }

        // Best path through the blocks (Viterbi), paying `changePenalty`
        // every time the key changes.
        let changePenalty = 0.6
        var total = scores[0]
        var cameFrom = [[Int]](repeating: [Int](repeating: 0, count: candidates.count), count: scores.count)
        for block in 1..<scores.count {
            let bestPrevious = total.indices.max { total[$0] < total[$1] } ?? 0
            var next = total
            for key in candidates.indices {
                let stay = total[key]
                let change = total[bestPrevious] - changePenalty
                if stay >= change {
                    next[key] = stay + scores[block][key]
                    cameFrom[block][key] = key
                } else {
                    next[key] = change + scores[block][key]
                    cameFrom[block][key] = bestPrevious
                }
            }
            total = next
        }
        var path = [Int](repeating: 0, count: scores.count)
        path[scores.count - 1] = total.indices.max { total[$0] < total[$1] } ?? 0
        for block in stride(from: scores.count - 1, to: 0, by: -1) {
            path[block - 1] = cameFrom[block][path[block]]
        }

        // Collapse the path into runs, absorbing runs shorter than ~22 s into
        // the preceding (or, at the start, the following) run.
        var runs: [(key: Int, start: Int, length: Int)] = []
        for (block, key) in path.enumerated() {
            if let last = runs.last, last.key == key {
                runs[runs.count - 1].length += 1
            } else {
                runs.append((key, block, 1))
            }
        }
        let minimumBlocks = 3
        var merged: [(key: Int, start: Int, length: Int)] = []
        for run in runs {
            if run.length < minimumBlocks, var last = merged.popLast() {
                last.length += run.length
                merged.append(last)
            } else if let last = merged.last, last.key == run.key {
                merged[merged.count - 1].length += run.length
            } else {
                merged.append(run)
            }
        }
        if merged.count > 1, merged[0].length < minimumBlocks {
            merged[1].start = 0
            merged[1].length += merged[0].length
            merged.removeFirst()
        }

        let blockDuration = frameDuration * Double(framesPerBlock)
        return merged.map { run in
            KeySection(key: candidates[run.key], start: Double(run.start) * blockDuration)
        }
    }

    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Pearson correlation of two equal-length series.
    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let meanA = vDSP.mean(a), meanB = vDSP.mean(b)
        let centeredA = vDSP.add(-meanA, a), centeredB = vDSP.add(-meanB, b)
        let denominator = (vDSP.sumOfSquares(centeredA) * vDSP.sumOfSquares(centeredB)).squareRoot()
        return denominator > 0 ? vDSP.dot(centeredA, centeredB) / denominator : 0
    }
}
