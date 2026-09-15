import AppKit
@main struct ClipboardChecks {
    static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let access = ClipboardAccess(board)
        do { _ = try access.snapshot(); fatalError("Empty clipboard accepted") } catch ClipboardFailure.noImage {}
        board.setString("plain text", forType: .string)
        do { _ = try access.snapshot(); fatalError("Text clipboard accepted") } catch ClipboardFailure.noImage {}
        for (name, type) in [("example-1.png", NSPasteboard.PasteboardType.png), ("example-1.tiff", .tiff)] {
            let url = URL(fileURLWithPath: "validation/"+name)
            board.clearContents(); board.setData(try Data(contentsOf: url), forType: type)
            let snapshot = try access.snapshot()
            precondition(!snapshot.data.isEmpty)
            precondition(access.copy("$x_i$", ifUnchangedSince: snapshot.changeCount))
            precondition(board.string(forType: .string) == "$x_i$")
            board.clearContents(); board.setData(try Data(contentsOf: url), forType: type)
            let old = try access.snapshot()
            board.clearContents(); board.setString("newer clipboard", forType: .string)
            precondition(!access.copy("must not replace", ifUnchangedSince: old.changeCount))
            precondition(board.string(forType: .string) == "newer clipboard")
        }
        print("PASS: empty, non-image, PNG, TIFF, automatic copy, changed-clipboard preservation")
    }
}
