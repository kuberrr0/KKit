import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import KKitCore
import KKitServicesAPI

/// Per-app volume with Core Audio process taps (macOS 14.2+).
///
/// For an app turned below 100%, each of its audio processes gets a private tap that
/// mutes the process's own output, and a private aggregate device (the current output
/// device plus the tap) whose IO block plays the tapped audio back at the chosen gain.
/// Apps at 100% have no tap at all. Taps are rebuilt when the output device changes and
/// added when the app starts a new audio process (a browser tab).
@MainActor
final class ProcessTapMixer {
    /// The name of the mixer's private aggregate devices, so device lists can skip them.
    nonisolated static let aggregateName = "KKit app volume"

    private var volumes: [String: Double] = [:]
    private var taps: [AudioObjectID: AppTap] = [:]
    private var processListener: CoreAudioListener?
    private var outputUID: String?
    private let log = KKitLog.logger("audio.mixer")
    private let ownBundleID = Bundle.main.bundleIdentifier

    func volume(for bundleID: String) -> Double {
        volumes[bundleID] ?? 1
    }

    func setVolume(_ volume: Double, for bundleID: String) {
        let clamped = min(max(volume, 0), 1)
        if clamped >= 0.999 {
            volumes[bundleID] = nil
        } else {
            volumes[bundleID] = clamped
        }
        sync()
    }

    /// The default output device changed: every tap plays to the old one, so rebuild.
    func outputDeviceChanged(uid: String?) {
        guard uid != outputUID else { return }
        outputUID = uid
        removeAllTaps()
        sync()
    }

    /// Apps with audio clients, grouped by app (helpers under their parent).
    func apps() -> [AudioApp] {
        var byApp: [String: AudioApp] = [:]
        for process in Self.processes() {
            guard let owner = owningApp(of: process.bundleID, pid: process.pid) else { continue }
            var entry = byApp[owner.bundleID] ?? AudioApp(bundleID: owner.bundleID, name: owner.name, isPlaying: false)
            entry.isPlaying = entry.isPlaying || process.isRunningOutput
            byApp[owner.bundleID] = entry
        }
        // Apps the user turned down stay listed while they're running.
        return byApp.values.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Private

    private struct ProcessRecord {
        var object: AudioObjectID
        var pid: pid_t
        var bundleID: String
        var isRunningOutput: Bool
    }

    private static func processes() -> [ProcessRecord] {
        CA.objectIDs(CA.systemObject, CA.address(kAudioHardwarePropertyProcessObjectList)).compactMap { object in
            guard let bundleID = CA.string(object, CA.address(kAudioProcessPropertyBundleID)), !bundleID.isEmpty else {
                return nil
            }
            return ProcessRecord(
                object: object,
                pid: CA.int32(object, CA.address(kAudioProcessPropertyPID)) ?? 0,
                bundleID: bundleID,
                isRunningOutput: (CA.uint32(object, CA.address(kAudioProcessPropertyIsRunningOutput)) ?? 0) != 0
            )
        }
    }

    /// The regular app a process belongs to: itself, or the running app whose bundle id
    /// is a prefix of the helper's ("com.google.Chrome.helper" → Chrome).
    private func owningApp(of bundleID: String, pid: pid_t) -> (bundleID: String, name: String)? {
        guard bundleID != ownBundleID else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
           let id = app.bundleIdentifier {
            return (id, app.localizedName ?? id)
        }
        let parent = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, bundleID.hasPrefix(id + ".") else { return nil }
                return (id, app.localizedName ?? id)
            }
            .max { $0.0.count < $1.0.count }
        return parent.map { (bundleID: $0.0, name: $0.1) }
    }

    private func belongs(_ processBundleID: String, to appBundleID: String) -> Bool {
        processBundleID == appBundleID || processBundleID.hasPrefix(appBundleID + ".")
    }

    /// Makes the taps match `volumes`.
    private func sync() {
        if volumes.isEmpty {
            removeAllTaps()
            processListener?.remove()
            processListener = nil
            return
        }
        if processListener == nil {
            processListener = CoreAudioListener(
                object: CA.systemObject,
                address: CA.address(kAudioHardwarePropertyProcessObjectList)
            ) { [weak self] in
                self?.sync()
            }
        }
        if outputUID == nil {
            outputUID = CA.defaultDevice(input: false).flatMap { CA.string($0, CA.address(kAudioDevicePropertyDeviceUID)) }
        }
        guard let outputUID else { return }

        var wanted: [AudioObjectID: Double] = [:]
        for process in Self.processes() {
            if let entry = volumes.first(where: { belongs(process.bundleID, to: $0.key) }) {
                wanted[process.object] = entry.value
            }
        }
        for (object, tap) in taps where wanted[object] == nil {
            tap.invalidate()
            taps[object] = nil
        }
        for (object, volume) in wanted {
            if let tap = taps[object] {
                tap.gain.value = Float(volume)
                continue
            }
            do {
                taps[object] = try AppTap(process: object, outputUID: outputUID, gain: Float(volume))
            } catch {
                log.error("Couldn't tap audio process \(object): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func removeAllTaps() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
    }
}

/// The gain the IO block reads on Core Audio's real-time thread. A torn read of a
/// `Float` isn't possible on Apple hardware, so no lock is needed.
final class TapGain: @unchecked Sendable {
    var value: Float

    init(_ value: Float) {
        self.value = value
    }
}

struct AudioTapError: LocalizedError {
    var step: String
    var status: OSStatus

    var errorDescription: String? { "\(step) failed (\(status))" }
}

/// One process tap plus its aggregate device and IO block.
final class AppTap {
    let gain: TapGain
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.kv.kkit.audio-tap", qos: .userInteractive)

    init(process: AudioObjectID, outputUID: String, gain: Float) throws {
        self.gain = TapGain(gain)

        let description = CATapDescription(stereoMixdownOfProcesses: [NSNumber(value: process)])
        description.uuid = UUID()
        description.name = "KKit app volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw AudioTapError(step: "AudioHardwareCreateProcessTap", status: status) }
        tapID = tap

        // Keys are the values of the kAudioAggregateDevice…Key / kAudioSub…Key constants.
        let aggregate: [String: Any] = [
            "name": ProcessTapMixer.aggregateName,
            "uid": UUID().uuidString,
            "master": outputUID,
            "private": true,
            "stacked": false,
            "tapautostart": true,
            "subdevices": [["uid": outputUID]],
            "taps": [["uid": description.uuid.uuidString, "drift": true]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else {
            invalidate()
            throw AudioTapError(step: "AudioHardwareCreateAggregateDevice", status: status)
        }
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue, Self.makeIOBlock(gain: self.gain))
        guard status == noErr, let proc else {
            invalidate()
            throw AudioTapError(step: "AudioDeviceCreateIOProcIDWithBlock", status: status)
        }
        procID = proc
        status = AudioDeviceStart(device, proc)
        guard status == noErr else {
            invalidate()
            throw AudioTapError(step: "AudioDeviceStart", status: status)
        }
    }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Copies the tapped audio (the input side) to the output device at `gain`. Built
    /// outside any actor: Core Audio calls it on its own real-time thread.
    nonisolated private static func makeIOBlock(gain: TapGain) -> AudioDeviceIOBlock {
        return { _, inputData, _, outputData, _ in
            let level = gain.value
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            for (index, output) in outputs.enumerated() {
                guard let outData = output.mData else { continue }
                let outSamples = Int(output.mDataByteSize) / MemoryLayout<Float>.size
                let out = outData.assumingMemoryBound(to: Float.self)
                guard !inputs.isEmpty else {
                    out.update(repeating: 0, count: outSamples)
                    continue
                }
                if inputs.count == outputs.count, let inData = inputs[index].mData {
                    // Same layout: scale and copy.
                    let input = inData.assumingMemoryBound(to: Float.self)
                    let count = min(outSamples, Int(inputs[index].mDataByteSize) / MemoryLayout<Float>.size)
                    for sample in 0..<count {
                        out[sample] = input[sample] * level
                    }
                    if count < outSamples {
                        (out + count).update(repeating: 0, count: outSamples - count)
                    }
                } else if let inData = inputs[0].mData {
                    // One interleaved input, several output buffers: take each output
                    // buffer's channel from the interleaved frames.
                    let input = inData.assumingMemoryBound(to: Float.self)
                    let inChannels = max(Int(inputs[0].mNumberChannels), 1)
                    let outChannels = max(Int(output.mNumberChannels), 1)
                    let frames = min(
                        Int(inputs[0].mDataByteSize) / MemoryLayout<Float>.size / inChannels,
                        outSamples / outChannels
                    )
                    for frame in 0..<frames {
                        for channel in 0..<outChannels {
                            let source = min(index * outChannels + channel, inChannels - 1)
                            out[frame * outChannels + channel] = input[frame * inChannels + source] * level
                        }
                    }
                    let written = frames * outChannels
                    if written < outSamples {
                        (out + written).update(repeating: 0, count: outSamples - written)
                    }
                } else {
                    out.update(repeating: 0, count: outSamples)
                }
            }
        }
    }
}
