import AppKit
import UniformTypeIdentifiers

enum DesktopGroup: String, CaseIterable, Identifiable {
    case folders = "Folders"
    case documents = "Documents"
    case images = "Images"
    case other = "Other"

    var id: String { rawValue }

    static func group(for url: URL, resourceValues: URLResourceValues? = nil) -> DesktopGroup {
        let values = resourceValues ?? (try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]))
        if values?.isDirectory == true { return .folders }
        let ext = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
        let documentExtensions: Set<String> = ["csv", "doc", "docx", "key", "md", "numbers", "odp", "ods", "odt", "pages", "pdf", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"]
        if imageExtensions.contains(ext) { return .images }
        if documentExtensions.contains(ext) { return .documents }
        if let type = values?.contentType {
            if type.conforms(to: .image) { return .images }
            if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) {
                return .documents
            }
        }
        return .other
    }
}

struct DesktopItem: Identifiable, Hashable {
    let url: URL
    let group: DesktopGroup
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}
