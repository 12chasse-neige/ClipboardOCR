import AppKit
import SwiftUI

@MainActor final class AppController: ObservableObject {
    static let shared = AppController()
    @Published var status = "Ready"
    @Published var busy = false
    @Published var modelLoaded = false
    @Published var error: String?
    @Published var needsCopy = false
    @Published var shortcut = Shortcut.load()
    @Published var shortcutError: String?
    private let backend = Backend()
    private let hotkey = GlobalHotkey()
    private let clipboard: ClipboardAccess
    private var latestResult: String?
    private var requestID: String?
    private var snapshotCount: Int?
    private var inputFile: URL?
    private var timeout: Timer?
    private var confirmationID = UUID()
    static var inputs: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/ClipboardOCR/inputs", isDirectory: true) }

    init(clipboard: ClipboardAccess = ClipboardAccess()) {
        self.clipboard = clipboard
        let bundleID = Bundle.main.bundleIdentifier ?? "local.ClipboardOCR"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        backend.onEvent = { [weak self] in self?.handle($0) }
        backend.onCrash = { [weak self] in
            guard let self else { return }
            self.modelLoaded = false
            if self.busy { self.fail("The OCR backend stopped unexpectedly. Retry.") }
            else { self.status = "Model unloaded" }
        }
        hotkey.action = { [weak self] in self?.recognize() }
        if !hotkey.register(shortcut) { shortcutError = "This shortcut is unavailable. Choose another in Settings." }
        // Crash recovery: inputs are temporary, never a recognition history.
        try? FileManager.default.createDirectory(at: Self.inputs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.inputs, includingPropertiesForKeys: nil) {
            for file in files where ["png", "tiff"].contains(file.pathExtension) { try? FileManager.default.removeItem(at: file) }
        }
    }
    func recognize() {
        guard !busy else { return }
        error = nil
        confirmationID = UUID()
        do {
            let snapshot = try clipboard.snapshot()
            let id = UUID().uuidString
            let file = Self.inputs.appendingPathComponent(id).appendingPathExtension(snapshot.fileExtension)
            inputFile = file
            try snapshot.data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            inputFile = file; snapshotCount = snapshot.changeCount; requestID = id
            busy = true; status = modelLoaded ? "Recognizing…" : "Loading model…"
            try backend.send(id: id, path: file.path)
            timeout = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.busy else { return }
                    self.backend.stop(); self.modelLoaded = false
                    self.fail("Recognition timed out. Retry with a smaller image.")
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    private func handle(_ event: [String: Any]) {
        guard let id = event["id"] as? String, id == requestID, busy else { return }
        switch event["type"] as? String {
        case "progress":
            status = event["stage"] as? String == "loading" ? "Loading model…" : "Recognizing…"
        case "success":
            guard let markdown = event["markdown"] as? String, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("No text was recognized. Copy a clearer image and retry."); return
            }
            latestResult = markdown
            modelLoaded = true
            if let count = snapshotCount, clipboard.copy(markdown, ifUnchangedSince: count) {
                needsCopy = false; confirmCopied()
            } else {
                needsCopy = true; status = "Result ready · clipboard changed"
            }
            finish()
        case "error":
            backend.stop()
            modelLoaded = false
            fail(event["message"] as? String ?? "Recognition failed. Retry.")
        default: break
        }
    }
    func copyResult() {
        guard let latestResult else { return }
        if clipboard.copy(latestResult) { needsCopy = false; confirmCopied() }
        else { error = "Could not write to the clipboard. Try Copy OCR Result again." }
    }
    private func confirmCopied() {
        status = "Markdown copied"
        let id = UUID(); confirmationID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.confirmationID == id, !self.busy else { return }
            self.status = "Ready · model loaded"
        }
    }
    private func finish() {
        timeout?.invalidate(); timeout = nil
        if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        inputFile = nil; snapshotCount = nil; requestID = nil; busy = false
    }
    private func fail(_ message: String) { error = message; status = "OCR failed"; finish() }
    func unload() {
        guard !busy else { return }
        busy = true; status = "Unloading model…"; confirmationID = UUID()
        backend.stop { [weak self] in
            self?.busy = false; self?.modelLoaded = false; self?.status = "Model unloaded"
        }
    }
    func changeShortcut(_ candidate: Shortcut) {
        if hotkey.register(candidate) {
            shortcut = candidate
            UserDefaults.standard.set(try? JSONEncoder().encode(candidate), forKey: "shortcut")
            shortcutError = nil
        } else {
            let restored = hotkey.register(shortcut)
            shortcutError = restored ? "That shortcut is already in use. Your previous shortcut is still active." : "Shortcut registration failed. Choose a different combination."
        }
    }
    func shutdown(_ completion: @escaping () -> Void) {
        finish(); backend.stop(completion: completion)
    }
}
