// FineTune/Audio/Engine/MixCaptureDevice.swift
import AudioToolbox
import Foundation
import os

private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "MixCaptureDevice")

/// Publishes "FineTune Mix", a system-wide input device carrying FineTune's processed output,
/// so recorders (QuickTime, OBS) can capture what the user hears on any output device.
///
/// It is a public, tap-only aggregate: one unmuted stereo-mixdown tap of FineTune's own
/// process, no hardware sub-devices, so it exposes input streams only. The UID is fixed
/// so recorders remember the selection across launches. FineTune hides it from its own
/// pickers (see `AudioDeviceMonitor`).
@MainActor
enum MixCaptureDevice {
    nonisolated static let uid = "com.finetuneapp.FineTune.mix"
    nonisolated static let name = "FineTune Mix"

    private static var tapID: AudioObjectID = .unknown
    private static var aggregateID: AudioObjectID = .unknown

    static func start() {
        guard !aggregateID.isValid else { return }

        // A previous session that crashed leaves the device behind with a dead tap.
        destroyStaleDevices()

        guard let selfProcess = ownProcessObject() else {
            logger.error("Could not resolve FineTune's own audio process object")
            return
        }

        let tap = CATapDescription(stereoMixdownOfProcesses: [selfProcess])
        tap.uuid = UUID()
        tap.name = name
        // Unmuted: this tap observes FineTune's output, it must never silence it.
        tap.muteBehavior = .unmuted
        tap.isPrivate = false

        var newTapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tap, &newTapID)
        guard err == noErr else {
            logger.error("Failed to create mix tap: OSStatus \(err)")
            return
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: false,
                    kAudioSubTapUIDKey: tap.uuid.uuidString
                ]
            ]
        ]

        var newAggregateID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
        guard err == noErr else {
            logger.error("Failed to create mix device: OSStatus \(err)")
            AudioHardwareDestroyProcessTap(newTapID)
            return
        }
        CrashGuard.trackDevice(newAggregateID)

        tapID = newTapID
        aggregateID = newAggregateID
        logger.info("Published \(name, privacy: .public) (device \(newAggregateID), tap \(newTapID))")
    }

    static func stop() {
        if aggregateID.isValid {
            CrashGuard.untrackDevice(aggregateID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    private static func destroyStaleDevices() {
        guard let devices = try? AudioObjectID.readDeviceList() else { return }
        for device in devices where (try? device.readDeviceUID()) == uid {
            let err = AudioHardwareDestroyAggregateDevice(device)
            logger.info("Destroyed stale mix device \(device): OSStatus \(err)")
        }
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObject: AudioObjectID = .unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(
            .system, &address,
            UInt32(MemoryLayout<pid_t>.size), &pid,
            &size, &processObject
        )
        guard err == noErr, processObject.isValid else { return nil }
        return processObject
    }
}
