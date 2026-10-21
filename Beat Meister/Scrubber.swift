//
//  Scrubber.swift
//  Beat Meister
//
//  Real-time jog audio. While the jog wheel is held, a read head chases the
//  position the hand has turned to and plays the decoded track at whatever
//  speed and direction that takes, like a record under a finger.
//

import AVFoundation
import Synchronization

/// Renders scrub audio from a decoded track.
///
/// `render` runs on the real-time audio thread, so it never locks or
/// allocates: the main actor talks to it only through atomics, and the
/// samples live in buffers allocated once up front.
nonisolated final class Scrubber: @unchecked Sendable {
    let sampleRate: Double
    let frameCount: Int

    private let left: UnsafeMutableBufferPointer<Float>
    private let right: UnsafeMutableBufferPointer<Float>?

    // Shared with the main actor.
    private let targetFrame = Atomic<Int>(0)
    private let isActive = Atomic<Bool>(false)
    /// Bumped by `begin` so the render thread snaps its read head to the target.
    private let resetCount = Atomic<Int>(0)

    // Owned by the render thread.
    private var readHead: Double = 0
    private var gain: Float = 0
    private var seenResetCount = 0

    /// How quickly the read head catches up with the hand (seconds).
    private static let followTime = 0.04
    /// Fastest playback speed while scrubbing, as a multiple of normal speed.
    private static let maxSpeed = 8.0

    init(_ audio: DecodedAudio) {
        sampleRate = audio.sampleRate
        frameCount = audio.left.count
        left = .allocate(capacity: max(audio.left.count, 1))
        _ = left.initialize(from: audio.left)
        if audio.right.count == audio.left.count, !audio.right.isEmpty {
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: audio.right.count)
            _ = buffer.initialize(from: audio.right)
            right = buffer
        } else {
            right = nil
        }
    }

    deinit {
        left.deallocate()
        right?.deallocate()
    }

    /// Starts scrubbing from a frame; the read head jumps there.
    func begin(atFrame frame: Int) {
        targetFrame.store(clamp(frame), ordering: .sequentiallyConsistent)
        resetCount.add(1, ordering: .sequentiallyConsistent)
        isActive.store(true, ordering: .sequentiallyConsistent)
    }

    /// Moves the point the read head is chasing.
    func move(toFrame frame: Int) {
        targetFrame.store(clamp(frame), ordering: .sequentiallyConsistent)
    }

    /// Stops scrubbing; the output fades to silence.
    func end() {
        isActive.store(false, ordering: .sequentiallyConsistent)
    }

    /// Creates the engine node that pulls audio from this scrubber.
    func makeSourceNode() -> AVAudioSourceNode? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }
        return AVAudioSourceNode(format: format) { [self] isSilence, _, frames, bufferList in
            render(frames: Int(frames), into: UnsafeMutableAudioBufferListPointer(bufferList), isSilence: isSilence)
            return noErr
        }
    }

    // MARK: Render thread

    private func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer,
                        isSilence: UnsafeMutablePointer<ObjCBool>) {
        guard let outLeft = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let outRight = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        let active = isActive.load(ordering: .sequentiallyConsistent)
        let target = Double(targetFrame.load(ordering: .sequentiallyConsistent))
        let resets = resetCount.load(ordering: .sequentiallyConsistent)
        if resets != seenResetCount {
            seenResetCount = resets
            readHead = target
        }

        // Nothing to play and already faded out.
        if !active && gain < 0.0001 {
            gain = 0
            for index in 0..<frames {
                outLeft[index] = 0
                outRight?[index] = 0
            }
            isSilence.pointee = true
            return
        }

        let follow = 1 / (Self.followTime * sampleRate)
        for index in 0..<frames {
            // Velocity is in frames per output frame, so 1.0 is normal speed
            // and negative values play backward.
            let velocity = min(max((target - readHead) * follow, -Self.maxSpeed), Self.maxSpeed)
            readHead += velocity

            // Louder the faster the hand moves (up to normal speed), so a
            // still hand is silent rather than holding a single sample.
            let targetGain: Float = active ? Float(min(abs(velocity), 1)) : 0
            gain += (targetGain - gain) * 0.003

            let (sampleLeft, sampleRight) = sample(at: readHead)
            outLeft[index] = sampleLeft * gain
            outRight?[index] = sampleRight * gain
        }
    }

    /// Linearly interpolated sample at a fractional frame position.
    private func sample(at position: Double) -> (Float, Float) {
        guard frameCount > 1 else { return (0, 0) }
        let clamped = min(max(position, 0), Double(frameCount - 2))
        let index = Int(clamped)
        let fraction = Float(clamped - Double(index))
        let leftValue = left[index] + (left[index + 1] - left[index]) * fraction
        guard let right else { return (leftValue, leftValue) }
        let rightValue = right[index] + (right[index + 1] - right[index]) * fraction
        return (leftValue, rightValue)
    }

    private func clamp(_ frame: Int) -> Int {
        min(max(frame, 0), max(frameCount - 1, 0))
    }
}
