import Carbon
import Foundation

/// Carbon hot keys require no event monitoring or Accessibility permission.
final class GlobalHotKeys {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    var onPress: ((UInt32) -> Void)?
    func register(send: Bool) -> Bool {
        unregister()
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                if result == noErr {
                    let owner = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                    owner.onPress?(id.id)
                }
                return result
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return false }
        // Command + Option + Shift + S (send), R (copy received text).
        for (key, id) in [send ? (kVK_ANSI_S, UInt32(1)) : (kVK_ANSI_R, UInt32(2))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(key), UInt32(cmdKey | optionKey | shiftKey),
                EventHotKeyID(signature: 0x4D52_4C59, id: id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                unregister()
                return false
            }
            references.append(ref)
        }
        return true
    }
    private func unregister() {
        for ref in references { UnregisterEventHotKey(ref) }
        references.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
    deinit { unregister() }
}
