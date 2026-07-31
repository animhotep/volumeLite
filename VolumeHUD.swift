import AppKit

// A small, click-through overlay shown near the bottom-center of whichever
// screen the cursor is on. Displays the current volume percentage and a bar,
// then fades out shortly after. A fresh window is built each time the HUD
// reappears so it always adopts the current screen and Space (fullscreen
// apps create their own Space, which can otherwise trap a reused window).
final class VolumeHUD {
    private let panelSize = NSSize(width: 200, height: 76)
    private let barHeight: CGFloat = 3

    private var window: NSWindow?
    private var label: NSTextField!
    private var barTrack: NSView!
    private var barFill: NSView!
    private var hideWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    init() {
        // Also rebuild on display-layout changes (sleep/wake, resolution,
        // rearranging, plugging in a monitor).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.dropWindow()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show(volume: Float, muted: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.show(volume: volume, muted: muted) }
            return
        }

        // If the HUD isn't currently on screen, rebuild it fresh so it lands
        // on the current screen/Space. While visible (a continuous scroll) the
        // window is reused as-is.
        if let w = window, !w.isVisible {
            dropWindow()
        }
        buildIfNeeded()
        guard let window else { return }

        let pct = Int((volume * 100).rounded())
        label.stringValue = muted ? "Muted" : "\(pct)%"

        let level = max(0, min(1, muted ? 0 : CGFloat(volume)))
        let fullWidth = barTrack.bounds.width
        var fillFrame = barFill.frame
        fillFrame.size.width = level <= 0 ? 0 : max(barHeight, fullWidth * level)
        barFill.frame = fillFrame

        positionWindow(window)
        window.alphaValue = 0.5
        window.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: - Build (lazy)

    private func buildIfNeeded() {
        guard window == nil else { return }

        let w = NSWindow(contentRect: NSRect(origin: .zero, size: panelSize),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .ignoresCycle, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        w.alphaValue = 1

        let bg = NSView(frame: NSRect(origin: .zero, size: panelSize))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 0.92).cgColor
        bg.layer?.cornerRadius = 18
        bg.layer?.masksToBounds = true
        w.contentView = bg

        let lb = NSTextField(labelWithString: "0%")
        lb.font = .systemFont(ofSize: 24, weight: .semibold)
        lb.alignment = .center
        lb.textColor = .white
        lb.isBezeled = false
        lb.drawsBackground = false
        lb.frame = NSRect(x: 0, y: 30, width: panelSize.width, height: 28)
        bg.addSubview(lb)
        label = lb

        let track = NSView(frame: NSRect(x: 24, y: 19, width: panelSize.width - 48, height: barHeight))
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        track.layer?.cornerRadius = barHeight / 2
        track.layer?.masksToBounds = true
        bg.addSubview(track)
        barTrack = track

        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: barHeight))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.cgColor
        fill.layer?.cornerRadius = barHeight / 2
        track.addSubview(fill)
        barFill = fill

        window = w
    }

    // MARK: - Teardown / hide

    private func dropWindow() {
        hideWork?.cancel()
        window?.orderOut(nil)
        window = nil
        label = nil
        barTrack = nil
        barFill = nil
    }

    private func fadeOut() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { window.orderOut(nil) })
    }

    // MARK: - Placement

    private func positionWindow(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let f = screen.frame
        let x = f.midX - panelSize.width / 2
        let y = f.minY + 10          // ~120pt above the bottom edge, centered
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
