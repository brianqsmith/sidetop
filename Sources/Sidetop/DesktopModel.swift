import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

@MainActor
final class DesktopModel: ObservableObject {
    @Published private(set) var groups: [DesktopGroup: [DesktopItem]] = [:]
    @Published var selectedURL: URL?
    @Published var expandedGroups = Set(DesktopGroup.allCases)

    let desktopURL: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1

    init(desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]) {
        self.desktopURL = desktopURL
        refresh()
    }

    func startMonitoring() {
        stopMonitoring()
        directoryDescriptor = Darwin.open(desktopURL.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryDescriptor,
                                                               eventMask: [.write, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { [descriptor = directoryDescriptor] in close(descriptor) }
        directorySource = source
        source.resume()
    }

    func stopMonitoring() {
        directorySource?.cancel()
        directorySource = nil
        directoryDescriptor = -1
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .contentTypeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: desktopURL,
                                                                 includingPropertiesForKeys: Array(keys),
                                                                 options: [.skipsHiddenFiles])) ?? []
        let items = urls.compactMap { url -> DesktopItem? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true else { return nil }
            return DesktopItem(url: url,
                               group: DesktopGroup.group(for: url, resourceValues: values),
                               isDirectory: values.isDirectory == true)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        groups = Dictionary(grouping: items, by: \DesktopItem.group)
        if let selectedURL, !items.contains(where: { $0.url == selectedURL }) { self.selectedURL = nil }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func rename(_ url: URL, to proposedName: String? = nil) {
        let newName: String
        if let proposedName {
            newName = proposedName
        } else {
            let alert = NSAlert()
            alert.messageText = "Rename “\(url.lastPathComponent)”"
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(string: url.deletingPathExtension().lastPathComponent)
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let ext = url.pathExtension
            newName = ext.isEmpty ? field.stringValue : "\(field.stringValue).\(ext)"
        }
        guard !newName.isEmpty, newName != url.lastPathComponent else { return }
        perform { try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(newName)) }
    }

    func delete(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.show(error) }
                self?.refresh()
            }
        }
    }

    func duplicate(_ url: URL) {
        let destination = uniqueDestination(for: url, suffix: " copy")
        perform { try FileManager.default.copyItem(at: url, to: destination) }
    }

    func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    func paste() {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else { return }
        urls.filter { $0.deletingLastPathComponent() != desktopURL }.forEach { source in
            let destination = uniqueDestination(for: source, suffix: " copy")
            perform { try FileManager.default.copyItem(at: source, to: destination) }
        }
    }

    func importProviders(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        matching.forEach { provider in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let source: URL?
                if let data = item as? Data { source = URL(dataRepresentation: data, relativeTo: nil) }
                else { source = item as? URL }
                guard let self, let source else { return }
                Task { @MainActor in
                    guard source.deletingLastPathComponent() != self.desktopURL else { return }
                    let destination = self.uniqueDestination(for: source, suffix: " copy")
                    self.perform { try FileManager.default.copyItem(at: source, to: destination) }
                }
            }
        }
        return !matching.isEmpty
    }

    private func uniqueDestination(for source: URL, suffix: String) -> URL {
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var candidate = desktopURL.appendingPathComponent("\(stem)\(suffix)").appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = desktopURL.appendingPathComponent("\(stem)\(suffix) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    private func perform(_ work: () throws -> Void) {
        do { try work(); refresh() } catch { show(error) }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
