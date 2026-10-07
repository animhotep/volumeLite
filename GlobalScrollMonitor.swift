import Foundation
import CoreGraphics

// Top-level C callback (no captures) required by CGEvent.tapCreate.
private func scrollTapCallback(proxy: CGEventTapProxy,
                               type: CGEventType,
                               event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GlobalScrollMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // The system disables the tap if it ever blocks; just re-enable it.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reEnable()
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    if monitor.isAtBottomEdge(event.location) {
        let change = monitor.scrollChange(from: event)
        if change != 0 {
            let delta = Float(change)
            DispatchQueue.main.async {
                VolumeController.shared.applyScroll(delta)
            }
        }
        return nil   // swallow it so the window underneath doesn't scroll
    }
    return Unmanaged.passUnretained(event)
}

// Watches every scroll-wheel event system-wide and acts only when the
// cursor sits in a thin band along the bottom edge of its screen.
final class GlobalScrollMonitor {
    static let shared = GlobalScrollMonitor()

    private(set) var isActive = false

    var bandHeight: CGFloat = 40      // px from the bottom edge that counts as "the bottom"
    var lineSensitivity: CGFloat = 0.04
    var pixelSensitivity: CGFloat = 0.0015

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    private init() {}

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = src

        // Run the tap on its own thread so a busy main thread can't stall (and get the tap disabled).
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self?.tapRunLoop = rl
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "GlobalScrollMonitor.eventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        ready.wait()
        isActive = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop {
            if let source { CFRunLoopRemoveSource(rl, source, .commonModes) }
            CFRunLoopStop(rl)
        }
        tap = nil
        source = nil
        tapRunLoop = nil
        tapThread = nil
        isActive = false
    }

    func reEnable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // event.location is top-left origin global coordinates; so is CGDisplayBounds.
    func isAtBottomEdge(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        if count > 0 {
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetActiveDisplayList(count, &displays, &count)
            for d in displays {
                let b = CGDisplayBounds(d)
                if point.x >= b.minX && point.x < b.maxX &&
                   point.y >= b.minY && point.y < b.maxY {
                    return point.y >= b.maxY - bandHeight
                }
            }
        }
        let b = CGDisplayBounds(CGMainDisplayID())
        return point.y >= b.maxY - bandHeight
    }

    func scrollChange(from event: CGEvent) -> CGFloat {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            let p = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            // Trackpad: reverse direction relative to the mouse wheel.
            return -(CGFloat(p) * pixelSensitivity)
        } else {
            let line = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let clamped = max(-3.0, min(3.0, line))
            return CGFloat(clamped) * lineSensitivity
        }
    }
}
