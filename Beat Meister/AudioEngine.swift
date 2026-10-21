//
//  AudioEngine.swift
//  Beat Meister
//
//  Audio playback: one AVAudioEngine shared by both decks.
//
//  Per deck:  player  ─┐
//              scrubber ─┴→ channel (gain + format conversion) → varispeed (tempo) → EQ
//  Then both decks → main mixer → output. The scrubber sounds only while the
//  jog wheel is held.
//

import AVFoundation
import Observation
import Synchronization

/// Owns the audio engine, both decks and the crossfader.
@Observable
final class MixEngine {
    let deckA = DeckModel(name: "A")
    let deckB = DeckModel(name: "B")

    /// Crossfader position: -1 is full Deck A, 1 is full Deck B.
    var crossfader: Double = 0 {
        didSet { applyCrossfader() }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var configurationTask: Task<Void, Never>?

    init() {
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 44_100, channels: 2)
        deckA.attach(to: engine, format: format)
        deckB.attach(to: engine, format: format)
        applyCrossfader()

        engine.prepare()
        startEngine()

        // The engine stops when the output device changes (e.g. headphones
        // plugged in); restart it and leave both decks paused.
        configurationTask = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange)
            for await _ in changes {
                guard let self else { return }
                self.startEngine()
                self.deckA.engineDidReset()
                self.deckB.engineDidReset()
            }
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            deckA.loadError = "The audio output couldn’t be started: \(error.localizedDescription)"
        }
    }

    /// DJ-style curve: both decks are at full volume in the middle, and each
    /// fades out smoothly over the far half of the crossfader's travel.
    private func applyCrossfader() {
        let gainA = crossfader <= 0 ? 1 : cos(crossfader * .pi / 2)
        let gainB = crossfader >= 0 ? 1 : cos(-crossfader * .pi / 2)
        deckA.crossfaderGain = Float(gainA)
        deckB.crossfaderGain = Float(gainB)
    }
}

/// The audio nodes for one deck, plus the bookkeeping needed to seek and to
/// report the playback position.
///
/// `AVAudioPlayerNode.stop()` blocks until AVFoundation's file-reading thread
/// (default priority) finishes, so calling it from the main thread causes a
/// priority inversion. Every player and graph operation therefore runs, in
/// order, on `controlQueue`; the main thread only enqueues work and reads the
/// small amount of shared state it needs from behind a mutex.
nonisolated final class DeckAudio: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let channel = AVAudioMixerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)

    private let controlQueue = DispatchQueue(label: "BeatMeister.DeckAudio", qos: .default)

    // Accessed only on `controlQueue`.
    private var file: AVAudioFile?
    /// Bumped whenever a segment is replaced, so stale completion callbacks are ignored.
    private var generation = 0
    private var scrubNode: AVAudioSourceNode?

    /// State the main thread reads while `controlQueue` updates it.
    private struct Shared {
        /// File frame the current segment started at.
        var segmentStart: AVAudioFramePosition = 0
        var fileLength: AVAudioFramePosition = 0
        /// Queued operations not yet run; position reports pause meanwhile.
        var pendingOperations = 0
        /// Jog audio for the loaded track, once it has been decoded.
        var scrubber: Scrubber?
        /// Incremented per seek, so queued seeks that a newer one replaces can be skipped.
        var seekSerial = 0
    }
    private let shared = Mutex(Shared())

    /// Called on the main actor when the track plays to the end.
    @MainActor var onFinished: (() -> Void)?
    /// Called on the main actor when a queued operation fails.
    @MainActor var onError: ((String) -> Void)?

    init(engine: AVAudioEngine, format: AVAudioFormat?) throws {
        self.engine = engine
        for node in [player, channel, varispeed, eq] as [AVAudioNode] {
            engine.attach(node)
        }
        configureEQ()
        // The channel mixer converts each file's format to the engine's format.
        try engine.connectNode(player, to: channel, format: format)
        try engine.connectNode(channel, to: varispeed, format: format)
        try engine.connectNode(varispeed, to: eq, format: format)
        try engine.connectNode(eq, to: engine.mainMixerNode, format: format)
    }

    var isLoaded: Bool {
        shared.withLock { $0.fileLength > 0 }
    }

    /// Current position as a fraction of the track, or nil when not playing
    /// or while a seek is still being applied.
    var currentFraction: Double? {
        let (segmentStart, length, pending) = shared.withLock { ($0.segmentStart, $0.fileLength, $0.pendingOperations) }
        guard length > 0, pending == 0,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        let frame = segmentStart + playerTime.sampleTime
        return min(max(Double(frame) / Double(length), 0), 1)
    }

    /// Opens the file immediately (so errors are reported to the caller) and
    /// queues the switch-over to it.
    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        shared.withLock {
            $0.fileLength = file.length
            $0.segmentStart = 0
            $0.scrubber = nil
        }
        perform { [self] in
            stopPlayer()
            removeScrubberNode()
            self.file = file
            do {
                // Mixer inputs can be reconnected while the engine runs.
                try engine.connectNode(player, to: channel, format: file.processingFormat)
            } catch {
                report("The track couldn’t be connected for playback: \(error.localizedDescription)")
            }
            schedule(fromFraction: 0)
        }
    }

    func unload() {
        shared.withLock {
            $0.fileLength = 0
            $0.segmentStart = 0
            $0.scrubber = nil
        }
        perform { [self] in
            stopPlayer()
            removeScrubberNode()
            file = nil
        }
    }

    /// Starts playback; returns false if the engine isn't running.
    @discardableResult
    func play() -> Bool {
        guard isLoaded else { return false }
        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return false }
        perform { [self] in
            do {
                try player.playAudio()
            } catch {
                report("Playback couldn’t start: \(error.localizedDescription)")
            }
        }
        return true
    }

    func pause() {
        perform { [self] in player.pause() }
    }

    /// Jumps to a position, continuing playback if `resume` is true.
    /// Rapid seeks (dragging the needle strip) coalesce: only the newest runs.
    func seek(toFraction fraction: Double, resume: Bool) {
        let serial = shared.withLock { state -> Int in
            state.seekSerial += 1
            return state.seekSerial
        }
        perform { [self] in
            guard shared.withLock({ $0.seekSerial }) == serial else { return }
            schedule(fromFraction: fraction)
            if resume {
                try? player.playAudio()
            }
        }
    }

    // MARK: Jog scrubbing

    /// Adds jog audio for the loaded track from its decoded samples. The
    /// sample copy and graph change happen on the control queue.
    func installScrubber(_ audio: DecodedAudio) {
        perform { [self] in
            removeScrubberNode()
            let scrubber = Scrubber(audio)
            guard let node = scrubber.makeSourceNode() else { return }
            engine.attach(node)
            do {
                try engine.connectNode(node, to: channel, fromBus: 0, toBus: channel.nextAvailableInputBus,
                                       format: node.outputFormat(forBus: 0))
            } catch {
                engine.detach(node)
                report("Jog audio isn’t available: \(error.localizedDescription)")
                return
            }
            scrubNode = node
            shared.withLock { $0.scrubber = scrubber }
        }
    }

    func beginScrub(atFraction fraction: Double) {
        guard let scrubber = shared.withLock({ $0.scrubber }) else { return }
        scrubber.begin(atFrame: Int(fraction * Double(scrubber.frameCount)))
    }

    func scrub(toFraction fraction: Double) {
        guard let scrubber = shared.withLock({ $0.scrubber }) else { return }
        scrubber.move(toFrame: Int(fraction * Double(scrubber.frameCount)))
    }

    func endScrub() {
        shared.withLock { $0.scrubber }?.end()
    }

    // MARK: Channel controls
    // Audio unit parameters are safe to set from any thread.

    /// Tempo adjustment; 1.0 is the original speed. Pitch follows speed, like vinyl.
    var rate: Float {
        get { varispeed.rate }
        set { varispeed.rate = newValue }
    }

    var gain: Float {
        get { channel.outputVolume }
        set { channel.outputVolume = newValue }
    }

    /// Sets the three EQ bands from knob values in -1...1.
    /// The knob range maps to -26 dB (near kill) through +6 dB.
    func setEQ(low: Double, mid: Double, high: Double) {
        func decibels(_ value: Double) -> Float {
            Float(value < 0 ? value * 26 : value * 6)
        }
        eq.bands[0].gain = decibels(low)
        eq.bands[1].gain = decibels(mid)
        eq.bands[2].gain = decibels(high)
    }

    // MARK: Control queue

    /// Runs `work` on the control queue, in order. Submitted at the queue's
    /// own priority rather than the caller's, so the queue doesn't inherit
    /// the main thread's priority and recreate the inversion.
    private func perform(_ work: @escaping @Sendable () -> Void) {
        shared.withLock { $0.pendingOperations += 1 }
        controlQueue.async(qos: .default, flags: .enforceQoS) { [self] in
            work()
            shared.withLock { $0.pendingOperations -= 1 }
        }
    }

    /// Control queue only.
    private func stopPlayer() {
        generation += 1
        player.stop()
    }

    /// Control queue only.
    private func removeScrubberNode() {
        if let scrubNode {
            // Detaching stops the engine from rendering the node before the
            // scrubber (and its sample buffers) are released.
            engine.disconnectNodeOutput(scrubNode)
            engine.detach(scrubNode)
        }
        scrubNode = nil
        shared.withLock { $0.scrubber = nil }
    }

    /// Replaces whatever is scheduled with the rest of the file from `fraction`.
    /// Leaves the player stopped. Control queue only.
    private func schedule(fromFraction fraction: Double) {
        stopPlayer()
        guard let file else { return }

        let start = AVAudioFramePosition(Double(file.length) * min(max(fraction, 0), 1))
        shared.withLock { $0.segmentStart = start }
        let remaining = file.length - start
        guard remaining > 0 else { return }

        let token = generation
        player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            // Ignore callbacks from segments that were replaced or stopped.
            self.controlQueue.async(qos: .default, flags: .enforceQoS) {
                guard self.generation == token else { return }
                Task { @MainActor in self.onFinished?() }
            }
        }
    }

    private func report(_ message: String) {
        Task { @MainActor in onError?(message) }
    }

    private func configureEQ() {
        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 100

        let mid = eq.bands[1]
        mid.filterType = .parametric
        mid.frequency = 1_000
        mid.bandwidth = 2

        let high = eq.bands[2]
        high.filterType = .highShelf
        high.frequency = 10_000

        for band in eq.bands {
            band.gain = 0
            band.bypass = false
        }
    }
}
