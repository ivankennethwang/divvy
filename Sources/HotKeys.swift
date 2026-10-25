import Carbon

/// Global hotkeys via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                HotKeyCenter.shared.actions[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        guard let code = combo.keyCode else {
            NSLog("Divvy: unknown key \"\(combo.key)\"")
            return false
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, combo.carbonModifiers, EventHotKeyID(signature: OSType(0x4456_4E56), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Divvy: could not register \(combo.display) (status \(status))")
            return false
        }
        refs.append(ref)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}
