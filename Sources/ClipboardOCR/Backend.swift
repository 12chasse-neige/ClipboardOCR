import Foundation

@MainActor final class Backend {
    var onEvent: (([String: Any]) -> Void)?
    var onCrash: (() -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var generation = UUID()
    private var retiring: [Process] = []
    var loaded: Bool { process?.isRunning == true }
    static var runtime: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ClipboardOCR/runtime/bin/python")
    }
    func send(id: String, path: String) throws {
        if process?.isRunning != true { try start() }
        let request: [String: Any] = ["action": "recognize", "id": id, "path": path]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(10)
        try input?.fileHandleForWriting.write(contentsOf: data)
    }
    private func start() throws {
        guard FileManager.default.isExecutableFile(atPath: Self.runtime.path),
              let resources = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("backend/worker.py").path) else {
            throw NSError(domain: "ClipboardOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "The OCR runtime is missing. Run setup.command, then retry."])
        }
        stop()
        let session = UUID()
        generation = session
        let child = Process()
        let stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        child.arguments = ["-f", resources.appendingPathComponent("backend/local-only.sb").path, Self.runtime.path, "-u", resources.appendingPathComponent("backend/worker.py").path]
        child.standardInput = stdin
        child.standardOutput = stdout
        // The worker emits only allowlisted status codes; no persistent logs/history.
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        child.environment = environment
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data, session: session) }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.onCrash?()
            }
        }
        process = child; input = stdin; output = stdout
        do { try child.run() }
        catch { stop(); throw error }
    }
    private func receive(_ data: Data, session: UUID) {
        guard generation == session else { return }
        buffer.append(data)
        if buffer.count > 8_000_000 { stop(); onCrash?(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                stop(); onCrash?(); return
            }
            onEvent?(event)
        }
    }
    func stop(completion: (() -> Void)? = nil) {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        retiring = retiring.filter { $0.isRunning }
        if let child = process, child.isRunning { retiring.append(child) }
        let children = retiring
        for child in children where child.isRunning { child.terminate() }
        process = nil; input = nil; output = nil; buffer = Data()
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(8)
            while children.contains(where: { $0.isRunning }) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            for child in children where child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // The MLX child also has a parent-death watchdog (one-second interval).
            if !children.isEmpty { Thread.sleep(forTimeInterval: 1.1) }
            DispatchQueue.main.async { completion?() }
        }
    }
}
