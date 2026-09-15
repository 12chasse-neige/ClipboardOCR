import SwiftUI
import AppKit

@main struct ClipboardOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var controller = AppController.shared
    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Label(controller.busy ? controller.status : controller.status == "Markdown copied" ? "Copied" : controller.error != nil ? "OCR !" : controller.needsCopy ? "OCR •" : "OCR",
                  systemImage: controller.busy ? "hourglass" : "doc.text.viewfinder")

        }

    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController.shared
    static weak var current: AppDelegate?
    private var settingsWindow: NSWindow?
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 478, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Clipboard OCR Settings"
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: SettingsContent(controller: controller))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 478, height: 530))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.ClipboardOCR")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
struct MenuContent: View {
    @ObservedObject var controller: AppController
    var body: some View {
        Text(controller.status)
        if let error = controller.error { Text(error); Button("Retry") { controller.recognize() }.disabled(controller.busy) }
        if let error = controller.shortcutError { Text(error) }
        Divider()
        Button("Recognize Clipboard  \(controller.shortcut.label)") { controller.recognize() }.disabled(controller.busy)
        if controller.needsCopy { Button("Copy OCR Result") { controller.copyResult() }.disabled(controller.busy) }
        Button("Unload Model") { controller.unload() }.disabled(controller.busy || !controller.modelLoaded)
        Divider()
        Button("Settings…") { AppDelegate.current?.showSettings() }
        Button("Quit Clipboard OCR") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
struct SettingsContent: View {
    @ObservedObject var controller: AppController
    @State private var recording = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clipboard OCR").font(.title2.bold())
                    Text("Local text & equations → Markdown").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Copy an image, press your shortcut, then paste Markdown.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Recognize clipboard")
                Spacer()
                Button(recording ? "Press shortcut…" : controller.shortcut.label) { recording.toggle() }
                    .buttonStyle(.bordered)
            }
            if recording {
                Text("Press a key with Control or Command. Click the button again to cancel.").font(.caption)
                ShortcutRecorder { candidate in controller.changeShortcut(candidate); recording = false }.frame(height: 1)
            }
            if let error = controller.shortcutError { Text(error).foregroundStyle(.red).font(.caption) }
            Button("Restore default shortcut") { controller.changeShortcut(.standard); recording = false }
            Label(controller.status, systemImage: controller.busy ? "hourglass" : "checkmark.circle").font(.callout)
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Text("Runs locally with PaddleOCR-VL-1.6. The model loads on first use and stays loaded until you unload it or quit.").font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("If the clipboard changes during recognition, use Copy OCR Result in the menu. No images or results are saved as history.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 478, height: 530, alignment: .topLeading)
    }
}
