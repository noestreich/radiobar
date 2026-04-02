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
    // Carbon fires on the main thread; Task ensures @MainActor isolation is respected.
    Task { @MainActor in mgr.handleHotkey(id: hkID.id) }
    return noErr
}

// MARK: – HotkeyManager

@MainActor
final class HotkeyManager: ObservableObject {

    @Published var muteConfig:  HotkeyConfig
    @Published var cycleConfig: HotkeyConfig

    /// Called when the mute hotkey fires.
    var onMute:  (() -> Void)?
    /// Called when the cycle hotkey fires.
    var onCycle: (() -> Void)?

    // nonisolated(unsafe): plain C pointers; accessed only from main thread at runtime.
    nonisolated(unsafe) private var muteRef:    EventHotKeyRef?
    nonisolated(unsafe) private var cycleRef:   EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?

    private static let signature: FourCharCode = 0x52424152  // "RBAR"
    private static let muteID:    UInt32 = 1
    private static let cycleID:   UInt32 = 2

    private static let muteKey  = "hotkey_mute"
    private static let cycleKey = "hotkey_cycle"

    init() {
        muteConfig  = Self.load(key: Self.muteKey,  fallback: .disabled)
        cycleConfig = Self.load(key: Self.cycleKey, fallback: .disabled)
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

    // MARK: – Called by C callback

    func handleHotkey(id: UInt32) {
        switch id {
        case Self.muteID:  onMute?()
        case Self.cycleID: onCycle?()
        default: break
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
        if muteConfig.isEnabled  { register(muteConfig,  id: Self.muteID,  ref: &muteRef) }
        if cycleConfig.isEnabled { register(cycleConfig, id: Self.cycleID, ref: &cycleRef) }
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
        if let r = muteRef    { UnregisterEventHotKey(r) }
        if let r = cycleRef   { UnregisterEventHotKey(r) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
