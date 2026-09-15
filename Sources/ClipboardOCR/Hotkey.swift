import AppKit
import Carbon
import SwiftUI

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘O")
    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "shortcut"),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .standard }
        return shortcut
    }
}
final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
            hotkey.action?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut) -> Bool {
        guard handler != nil else { return false }
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let id = EventHotKeyID(signature: 0x434F4352, id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetEventDispatcherTarget(), 0, &reference) == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    var onRecord: (Shortcut) -> Void
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.onRecord = onRecord; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.onRecord = onRecord }
}
final class RecorderView: NSView {
    var onRecord: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.command),
              let key = event.charactersIgnoringModifiers, !key.isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        label += key.uppercased()
        onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
}
