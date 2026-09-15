import AppKit
let board = NSPasteboard.general
let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
    Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
}
let png = try Data(contentsOf: URL(fileURLWithPath: "validation/example-1.png"))
let tiff = try Data(contentsOf: URL(fileURLWithPath: "validation/example-1.tiff"))
let marker = "ClipboardOCR test: newer clipboard"
func isOurs() -> Bool {
    let text = board.string(forType: .string) ?? ""
    return text == marker || text.hasPrefix("## Energy and linear algebra") || board.data(forType: .png) == png || board.data(forType: .tiff) == tiff
}
print("Clipboard fixture ready; original contents retained in memory.")
while let line = readLine() {
    switch line {
    case "png": board.clearContents(); board.setData(png, forType: .png); print("PNG ready")
    case "tiff": board.clearContents(); board.setData(tiff, forType: .tiff); print("TIFF ready")
    case "newer": board.clearContents(); board.setString(marker, forType: .string); print("Newer text ready")
    case "check":
        let text = board.string(forType: .string) ?? ""
        print("markdown=\(text.hasPrefix("## Energy and linear algebra")) numbered=\(text.contains("\\tag*{(1)}")) matrix=\(text.contains("\\begin{pmatrix}")) newer=\(text == marker) image=\(board.availableType(from:[.png,.tiff]) != nil)")
    case "restore":
        if isOurs() {
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item
            }
            board.clearContents(); board.writeObjects(items)
            print("Original clipboard restored")
        } else { print("Clipboard changed independently; preserved") }
        exit(0)
    default: print("Unknown test command")
    }
}
