import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let volume = VolumeController.shared
    private let monitor = GlobalScrollMonitor.shared
    private let hud = VolumeHUD()

    private var slider: NSSlider?
    private var muteItem: NSMenuItem?
    private var invertItem: NSMenuItem?
    private var statusLine: NSMenuItem?

    private var refreshTimer: Timer?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // background app, no Dock icon

        setupStatusItem()
        volume.onChange = { [weak self] _, _ in self?.updateButton() }
        volume.onUserChange = { [weak self] vol, muted in
            self?.hud.show(volume: vol, muted: muted)
        }
        volume.refresh()

        requestAccessibilityAndStart()

        // Keep the tray icon in sync even if volume changes elsewhere.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.volume.refresh()
        }
    }

    // MARK: - Status item + menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusLine = status
        menu.addItem(status)
        menu.addItem(.separator())

        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 226, height: 34))
        let label = NSTextField(labelWithString: "Volume")
        label.frame = NSRect(x: 14, y: 8, width: 54, height: 18)
        let s = NSSlider(value: Double(volume.volume), minValue: 0, maxValue: 1,
                         target: self, action: #selector(sliderChanged(_:)))
        s.frame = NSRect(x: 72, y: 5, width: 140, height: 24)
        s.isContinuous = true
        slider = s
        container.addSubview(label)
        container.addSubview(s)
        sliderItem.view = container
        menu.addItem(sliderItem)

        let mute = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        mute.target = self
        muteItem = mute
        menu.addItem(mute)

        let invert = NSMenuItem(title: "Invert scroll direction",
                                action: #selector(toggleInvert), keyEquivalent: "")
        invert.target = self
        invertItem = invert
        menu.addItem(invert)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Volume Lite", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateButton()
    }

    func menuWillOpen(_ menu: NSMenu) {
        volume.refresh()
        syncMenu()
    }

    // MARK: - Accessibility permission

    private func requestAccessibilityAndStart() {
        // String literal avoids CFString/Unmanaged import differences.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            monitor.start()
        }
        syncMenu()

        // Poll until access is granted, then start without requiring a relaunch.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                if !self.monitor.isActive { self.monitor.start() }
                self.syncMenu()
                if self.monitor.isActive { t.invalidate() }
            }
        }
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) { volume.setVolume(Float(sender.doubleValue)) }
    @objc private func toggleMute() { volume.toggleMute(); syncMenu() }
    @objc private func toggleInvert() { volume.invertScroll.toggle(); syncMenu() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - UI

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let pct = Int((volume.volume * 100).rounded())

        button.title = " \(pct)"
    }

    private func syncMenu() {
        slider?.doubleValue = Double(volume.volume)
        muteItem?.state = volume.isMuted ? .on : .off
        invertItem?.state = volume.invertScroll ? .on : .off

        if monitor.isActive {
            statusLine?.title = "Active — scroll the bottom screen edge"
        } else if AXIsProcessTrusted() {
            statusLine?.title = "Inactive — turn off App Sandbox, relaunch"
        } else {
            statusLine?.title = "Grant Accessibility access, then relaunch"
        }
    }
}
