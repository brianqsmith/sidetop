import AppKit
import Combine
import UniformTypeIdentifiers

enum ItemSortMode: String, CaseIterable, Identifiable {
    case name
    case kind
    case dateModified

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .dateModified: return "Date Modified"
        }
    }
}

enum BrowserViewMode: String {
    case list
    case icon
}

struct OpenWithApplication: Identifiable {
    let url: URL
    let name: String
    var id: URL { url }
}

enum DesktopGroup: String, CaseIterable, Identifiable {
    case folders = "Folders"
    case screenshots = "Screenshots"
    case images = "Images"
    case documents = "Documents"
    case archives = "Archives"
    case movies = "Movies"
    case music = "Music"
    case other = "Other"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .archives: return "Archive"
        default: return rawValue
        }
    }

    var iconAssetName: String { rawValue.lowercased() }

    static func group(for url: URL, resourceValues: URLResourceValues? = nil) -> DesktopGroup {
        let values = resourceValues ?? (try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]))
        if values?.isDirectory == true { return .folders }
        let ext = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
        let documentExtensions: Set<String> = ["csv", "doc", "docx", "key", "md", "numbers", "odp", "ods", "odt", "pages", "pdf", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"]
        let archiveExtensions: Set<String> = ["7z", "bz2", "cab", "gz", "rar", "tar", "tgz", "xz", "zip"]
        let movieExtensions: Set<String> = ["3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"]
        let musicExtensions: Set<String> = ["aac", "aif", "aiff", "alac", "flac", "m4a", "mp3", "ogg", "opus", "wav", "wma"]
        if imageExtensions.contains(ext), isScreenshotName(url.deletingPathExtension().lastPathComponent) {
            return .screenshots
        }
        if imageExtensions.contains(ext) { return .images }
        if documentExtensions.contains(ext) { return .documents }
        if archiveExtensions.contains(ext) { return .archives }
        if movieExtensions.contains(ext) { return .movies }
        if musicExtensions.contains(ext) { return .music }
        if let type = values?.contentType {
            if type.conforms(to: .image) { return .images }
            if type.conforms(to: .archive) { return .archives }
            if type.conforms(to: .movie) { return .movies }
            if type.conforms(to: .audio) { return .music }
            if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) {
                return .documents
            }
        }
        return .other
    }

    private static func isScreenshotName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("screenshot") ||
            normalized.hasPrefix("screen shot") ||
            normalized.hasPrefix("cleanshot")
    }
}

@MainActor
final class CategoryOrderManager: ObservableObject {
    static let shared = CategoryOrderManager()
    @Published private(set) var order: [DesktopGroup]
    private let defaultsKey = "desktopCategoryOrder"

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let restored = saved.compactMap(DesktopGroup.init(rawValue:))
        order = restored + DesktopGroup.allCases.filter { !restored.contains($0) }
    }

    func move(_ group: DesktopGroup, before target: DesktopGroup) {
        guard group != target,
              let sourceIndex = order.firstIndex(of: group),
              let targetIndex = order.firstIndex(of: target) else { return }
        var updated = order
        updated.remove(at: sourceIndex)
        updated.insert(group, at: min(targetIndex, updated.count))
        order = updated
        UserDefaults.standard.set(updated.map(\.rawValue), forKey: defaultsKey)
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
