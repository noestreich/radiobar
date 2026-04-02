import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Shared state
    let store   = StationStore()
    let player  = RadioPlayer()
    let hotkeys = HotkeyManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    // MARK: – Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        observeState()
        setupHotkeys()
    }

    // MARK: – Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        if let btn = statusItem.button {
            btn.action = #selector(handleClick(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.target  = self
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    // MARK: – Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior      = .transient
        popover.contentSize   = NSSize(width: 270, height: 300)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environmentObject(store)
                .environmentObject(player)
        )
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: – Context menu (right-click)

    private func showContextMenu() {
        let menu = NSMenu()

        // Mute toggle
        let muteItem = NSMenuItem(
            title:  player.isMuted ? "Ton einschalten" : "Stumm schalten",
            action: #selector(toggleMute),
            keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)

        // Stop if playing
        if player.isPlaying {
            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopPlayback), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())

        // Quick station list
        for (idx, station) in store.stations.enumerated() {
            let item = NSMenuItem(
                title:         station.name,
                action:        #selector(selectStation(_:)),
                keyEquivalent: idx < 9 ? "\(idx + 1)" : "")
            item.keyEquivalentModifierMask = idx < 9 ? [.option] : []
            item.target             = self
            item.representedObject  = station.id.uuidString
            item.state              = station.id == store.currentStationId ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleMute()   { player.toggleMute() }
    @objc private func stopPlayback() { player.stop(); store.currentStationId = nil }
    private func setupHotkeys() {
        hotkeys.onMute  = { [weak self] in self?.player.toggleMute() }
        hotkeys.onCycle = { [weak self] in self?.cycleStation() }
    }

    func cycleStation() {
        let stations = store.stations
        guard !stations.isEmpty else { return }
        let nextIndex: Int
        if let currentId = store.currentStationId,
           let currentIndex = stations.firstIndex(where: { $0.id == currentId }) {
            nextIndex = (currentIndex + 1) % stations.count
        } else {
            nextIndex = 0
        }
        let next = stations[nextIndex]
        store.currentStationId = next.id
        player.play(station: next)
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectStation(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id    = UUID(uuidString: idStr),
              let s     = store.stations.first(where: { $0.id == id }) else { return }
        store.currentStationId = id
        player.play(station: s)
    }

    // MARK: – Status bar icon

    private func observeState() {
        store.$currentStationId
            .combineLatest(store.$stations, player.$isMuted, player.$isPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let color: NSColor
        if !player.isPlaying || player.isMuted {
            color = .tertiaryLabelColor
        } else if let s = store.currentStation {
            color = s.nsColor
        } else {
            color = .tertiaryLabelColor
        }
        statusItem.button?.image = makeCircleImage(color: color)
    }

    private func makeCircleImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img  = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
