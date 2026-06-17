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
            VolumeController.shared.applyScroll(Float(change))
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
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
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
            return CGFloat(p) * pixelSensitivity
        } else {
            let line = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let clamped = max(-3.0, min(3.0, line))
            return CGFloat(clamped) * lineSensitivity
        }
    }
}
