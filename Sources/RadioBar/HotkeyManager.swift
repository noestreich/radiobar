import Carbon
import AppKit

// MARK: – Global C callback (no captures allowed)

private func carbonHotkeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let ptr = userData else { return OSStatus(eventNotHandledErr) }

    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )

    let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    Task { @MainActor in mgr.handleHotkey(id: hkID.id) }
    return noErr
}

// MARK: – HotkeyManager

@MainActor
final class HotkeyManager: ObservableObject {

    @Published var muteConfig:       HotkeyConfig
    @Published var cycleConfig:      HotkeyConfig
    @Published var cycleBackConfig:  HotkeyConfig
    @Published var volumeUpConfig:   HotkeyConfig
    @Published var volumeDownConfig: HotkeyConfig

    var onMute:       (() -> Void)?
    var onCycle:      (() -> Void)?
    var onCycleBack:  (() -> Void)?
    var onVolumeUp:   (() -> Void)?
    var onVolumeDown: (() -> Void)?
    /// Sender-UUID → Callback; befüllt von AppDelegate nach jedem Stations-Update.
    var onStation:    [String: () -> Void] = [:]

    // nonisolated(unsafe): plain C pointers; accessed only from main thread at runtime.
    nonisolated(unsafe) private var muteRef:       EventHotKeyRef?
    nonisolated(unsafe) private var cycleRef:      EventHotKeyRef?
    nonisolated(unsafe) private var cycleBackRef:  EventHotKeyRef?
    nonisolated(unsafe) private var volumeUpRef:   EventHotKeyRef?
    nonisolated(unsafe) private var volumeDownRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef:    EventHandlerRef?

    /// id (≥100) → (stationUUID, EventHotKeyRef)
    nonisolated(unsafe) private var stationRefs: [UInt32: (String, EventHotKeyRef)] = [:]
    private var nextStationHotkeyID: UInt32 = 100

    private static let signature:      FourCharCode = 0x52424152  // "RBAR"
    private static let muteID:         UInt32 = 1
    private static let cycleID:        UInt32 = 2
    private static let cycleBackID:    UInt32 = 3
    private static let volumeUpID:     UInt32 = 4
    private static let volumeDownID:   UInt32 = 5

    private static let muteKey       = "hotkey_mute"
    private static let cycleKey      = "hotkey_cycle"
    private static let cycleBackKey  = "hotkey_cycle_back"
    private static let volumeUpKey   = "hotkey_volume_up"
    private static let volumeDownKey = "hotkey_volume_down"

    init() {
        muteConfig       = Self.load(key: Self.muteKey,       fallback: .disabled)
        cycleConfig      = Self.load(key: Self.cycleKey,      fallback: .disabled)
        cycleBackConfig  = Self.load(key: Self.cycleBackKey,  fallback: .disabled)
        volumeUpConfig   = Self.load(key: Self.volumeUpKey,   fallback: .disabled)
        volumeDownConfig = Self.load(key: Self.volumeDownKey, fallback: .disabled)
        installCarbonHandler()
        registerAll()
    }

    // MARK: – Public update API

    func updateMute(_ config: HotkeyConfig) {
        unregister(&muteRef)
        muteConfig = config
        Self.save(config, key: Self.muteKey)
        if config.isEnabled { register(config, id: Self.muteID, ref: &muteRef) }
    }

    func updateCycle(_ config: HotkeyConfig) {
        unregister(&cycleRef)
        cycleConfig = config
        Self.save(config, key: Self.cycleKey)
        if config.isEnabled { register(config, id: Self.cycleID, ref: &cycleRef) }
    }

    func updateCycleBack(_ config: HotkeyConfig) {
        unregister(&cycleBackRef)
        cycleBackConfig = config
        Self.save(config, key: Self.cycleBackKey)
        if config.isEnabled { register(config, id: Self.cycleBackID, ref: &cycleBackRef) }
    }

    func updateVolumeUp(_ config: HotkeyConfig) {
        unregister(&volumeUpRef)
        volumeUpConfig = config
        Self.save(config, key: Self.volumeUpKey)
        if config.isEnabled { register(config, id: Self.volumeUpID, ref: &volumeUpRef) }
    }

    func updateVolumeDown(_ config: HotkeyConfig) {
        unregister(&volumeDownRef)
        volumeDownConfig = config
        Self.save(config, key: Self.volumeDownKey)
        if config.isEnabled { register(config, id: Self.volumeDownID, ref: &volumeDownRef) }
    }

    // MARK: – Sender-Hotkeys (dynamisch, registriert von AppDelegate)

    /// Alle Sender-Hotkeys neu registrieren. Wird nach jeder Stations-Änderung aufgerufen.
    func updateStationHotkeys(stations: [Station]) {
        // Alle alten Sender-Registrierungen entfernen
        for (_, (_, ref)) in stationRefs { UnregisterEventHotKey(ref) }
        stationRefs.removeAll()
        nextStationHotkeyID = 100

        for station in stations {
            guard let cfg = station.hotkeyConfig, cfg.isEnabled else { continue }
            let hotkeyID = nextStationHotkeyID
            nextStationHotkeyID += 1
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.signature, id: hotkeyID)
            RegisterEventHotKey(
                UInt32(cfg.keyCode),
                cfg.carbonModifiers,
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref { stationRefs[hotkeyID] = (station.id.uuidString, ref) }
        }
    }

    // MARK: – Called by C callback

    func handleHotkey(id: UInt32) {
        switch id {
        case Self.muteID:       onMute?()
        case Self.cycleID:      onCycle?()
        case Self.cycleBackID:  onCycleBack?()
        case Self.volumeUpID:   onVolumeUp?()
        case Self.volumeDownID: onVolumeDown?()
        default:
            // Sender-Hotkey?
            if let (stationUUID, _) = stationRefs[id] {
                onStation[stationUUID]?()
            }
        }
    }

    // MARK: – Carbon plumbing

    private func installCarbonHandler() {
        var evType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1, &evType,
            selfPtr,
            &handlerRef
        )
    }

    private func registerAll() {
        if muteConfig.isEnabled       { register(muteConfig,       id: Self.muteID,       ref: &muteRef) }
        if cycleConfig.isEnabled      { register(cycleConfig,      id: Self.cycleID,      ref: &cycleRef) }
        if cycleBackConfig.isEnabled  { register(cycleBackConfig,  id: Self.cycleBackID,  ref: &cycleBackRef) }
        if volumeUpConfig.isEnabled   { register(volumeUpConfig,   id: Self.volumeUpID,   ref: &volumeUpRef) }
        if volumeDownConfig.isEnabled { register(volumeDownConfig, id: Self.volumeDownID, ref: &volumeDownRef) }
    }

    private func register(_ config: HotkeyConfig, id: UInt32, ref: inout EventHotKeyRef?) {
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(
            UInt32(config.keyCode),
            config.carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }

    private func unregister(_ ref: inout EventHotKeyRef?) {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    // MARK: – Persistence

    private static func load(key: String, fallback: HotkeyConfig) -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg  = try? JSONDecoder().decode(HotkeyConfig.self, from: data)
        else { return fallback }
        return cfg
    }

    private static func save(_ config: HotkeyConfig, key: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    deinit {
        if let r = muteRef       { UnregisterEventHotKey(r) }
        if let r = cycleRef      { UnregisterEventHotKey(r) }
        if let r = cycleBackRef  { UnregisterEventHotKey(r) }
        if let r = volumeUpRef   { UnregisterEventHotKey(r) }
        if let r = volumeDownRef { UnregisterEventHotKey(r) }
        for (_, (_, ref)) in stationRefs { UnregisterEventHotKey(ref) }
        if let h = handlerRef    { RemoveEventHandler(h) }
    }
}
