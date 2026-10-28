import AppKit
import Carbon
import Foundation

/// Global hotkey via Carbon — works without Accessibility permission.
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var current: HotKeySpec?
    var onHotKey: (() -> Void)?

    private static let signature: OSType = 0x434C4950 // 'CLIP'
    private static let hotKeyID: UInt32 = 1

    init() {}

    /// Registers `spec`; returns false when the system refuses it (e.g. taken by another app).
    @discardableResult
    func register(_ spec: HotKeySpec) -> Bool {
        unregister()
        guard spec.isValid else { return false }
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(spec.keyCode),
            Self.carbonModifiers(spec.modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            current = spec
            return true
        }
        AppLogger.error("Hotkey registration failed (status \(status))", logger: AppLogger.ui)
        hotKeyRef = nil
        current = nil
        return false
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.signature == HotKeyManager.signature, hotKeyID.id == HotKeyManager.hotKeyID {
                    DispatchQueue.main.async {
                        manager.onHotKey?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    static func carbonModifiers(_ modifiers: HotKeyModifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}

extension HotKeyModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var value: HotKeyModifiers = []
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.control) { value.insert(.control) }
        self = value
    }
}
