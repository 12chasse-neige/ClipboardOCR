import AppKit
@main struct ControllerChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let controller = AppController(clipboard: ClipboardAccess(board))
        precondition(controller.shortcutError == nil, "Global hotkey registration failed")
        func waitUntilIdle() async throws {
            let deadline = Date().addingTimeInterval(180)
            while controller.busy && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
            precondition(!controller.busy, "Controller timed out")
        }
        controller.recognize()
        precondition(controller.error?.contains("No image") == true)
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        board.clearContents(); board.setData(try Data(contentsOf: fixture),forType: .png)
        controller.recognize()
        precondition(controller.busy)
        controller.recognize() // Duplicate trigger must leave the active request alone.
        try await waitUntilIdle()
        precondition(controller.error == nil, controller.error ?? "error")
        precondition(board.string(forType:.string)?.contains("\\tag*{(1)}") == true)
        precondition(controller.modelLoaded)
        board.clearContents(); board.setData(try Data(contentsOf: fixture),forType: .png)
        controller.recognize()
        board.clearContents(); board.setString("newer text",forType:.string)
        try await waitUntilIdle()
        precondition(board.string(forType:.string) == "newer text")
        precondition(controller.needsCopy)
        controller.copyResult()
        precondition(!controller.needsCopy)
        precondition(board.string(forType:.string)?.contains("\\begin{pmatrix}") == true)
        controller.unload()
        try await waitUntilIdle()
        precondition(!controller.modelLoaded)
        print("PASS: controller no-image error, recognition action/clipboard loop, duplicate triggers, changed clipboard, explicit copy, unload")
    }
}
