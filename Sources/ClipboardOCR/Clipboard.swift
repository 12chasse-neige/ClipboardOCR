import AppKit

enum ClipboardFailure: LocalizedError {
    case noImage, changed, invalidImage
    var errorDescription: String? {
        switch self {
        case .noImage: return "No image on the clipboard. Copy a PNG or TIFF image and try again."
        case .changed: return "The clipboard changed while reading it. Try again."
        case .invalidImage: return "This clipboard image could not be read. Copy it again and retry."
        }
    }
}
struct ClipboardSnapshot {
    let data: Data
    let changeCount: Int
    let fileExtension: String
}
struct ClipboardAccess {
    let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    func snapshot() throws -> ClipboardSnapshot {
        let count = pasteboard.changeCount
        let type: NSPasteboard.PasteboardType
        if pasteboard.availableType(from: [.png]) != nil { type = .png }
        else if pasteboard.availableType(from: [.tiff]) != nil { type = .tiff }
        else { throw ClipboardFailure.noImage }
        guard let data = pasteboard.data(forType: type), !data.isEmpty,
              NSBitmapImageRep(data: data) != nil else { throw ClipboardFailure.invalidImage }
        guard pasteboard.changeCount == count else { throw ClipboardFailure.changed }
        return ClipboardSnapshot(data: data, changeCount: count, fileExtension: type == .png ? "png" : "tiff")
    }
    @discardableResult func copy(_ text: String, ifUnchangedSince count: Int? = nil) -> Bool {
        if let count, pasteboard.changeCount != count { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
