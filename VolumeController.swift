import Foundation
import CoreAudio

// Reads and writes the system's default output device volume via CoreAudio.
final class VolumeController {
    static let shared = VolumeController()

    private(set) var volume: Float = 0      // 0.0 ... 1.0
    private(set) var isMuted: Bool = false
    var invertScroll: Bool = false

    // Called after any change so the menu-bar icon can update.
    var onChange: ((Float, Bool) -> Void)?
    // Called only for changes the user makes here (scroll / slider / mute),
    // used to pop the on-screen HUD. Not fired by background refresh.
    var onUserChange: ((Float, Bool) -> Void)?

    private var deviceID = AudioDeviceID(kAudioObjectUnknown)

    private init() { refresh() }

    func refresh() {
        deviceID = Self.defaultOutputDevice()
        let v = readVolume()
        let m = readMute()
        let changed = (v != volume) || (m != isMuted)
        volume = v
        isMuted = m
        if changed { notify() }
    }

    private func notify() { onChange?(volume, isMuted) }
    private func userChanged() { onUserChange?(volume, isMuted) }

    // MARK: - Scroll entry point

    func applyScroll(_ change: Float) {
        nudge(by: invertScroll ? -change : change)
    }

    func nudge(by delta: Float) { setVolume(volume + delta) }

    // MARK: - Default device

    private static func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &address, 0, nil, &size, &device)
        return device
    }

    // MARK: - Volume

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    private func readVolume() -> Float {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return 0 }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        var master = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &master),
           AudioObjectGetPropertyData(deviceID, &master, 0, nil, &size, &value) == noErr {
            return value
        }
        var channel = volumeAddress(element: 1)
        if AudioObjectHasProperty(deviceID, &channel),
           AudioObjectGetPropertyData(deviceID, &channel, 0, nil, &size, &value) == noErr {
            return value
        }
        return 0
    }

    func setVolume(_ newValue: Float) {
        let clamped = max(0, min(1, newValue))
        volume = clamped
        defer { notify() }
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }

        var v = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)

        var master = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &master), isSettable(&master) {
            AudioObjectSetPropertyData(deviceID, &master, 0, nil, size, &v)
        } else {
            for element in UInt32(1)...UInt32(2) {
                var addr = volumeAddress(element: element)
                if AudioObjectHasProperty(deviceID, &addr), isSettable(&addr) {
                    AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &v)
                }
            }
        }
        if clamped > 0 && isMuted { setMute(false) }
        userChanged()
    }

    // MARK: - Mute

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func readMute() -> Bool {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return false }
        var addr = muteAddress()
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    func setMute(_ mute: Bool) {
        isMuted = mute
        defer { notify() }
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        var addr = muteAddress()
        guard AudioObjectHasProperty(deviceID, &addr), isSettable(&addr) else { return }
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &value)
        userChanged()
    }

    func toggleMute() { setMute(!isMuted) }

    // MARK: - Helpers

    private func isSettable(_ addr: inout AudioObjectPropertyAddress) -> Bool {
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &addr, &settable)
        return status == noErr && settable.boolValue
    }
}
