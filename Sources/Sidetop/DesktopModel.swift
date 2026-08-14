import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

@MainActor
final class DesktopModel: ObservableObject {
    @Published private(set) var groups: [DesktopGroup: [DesktopItem]] = [:]
    @Published var selectedURL: URL?
    @Published private(set) var selectedURLs = Set<URL>()
    @Published var expandedGroups = Set(DesktopGroup.allCases)
    @Published var expandedFolders = Set<URL>()
    @Published private(set) var folderContents: [URL: [DesktopItem]] = [:]

    @Published private(set) var desktopURL: URL
    private let skipsHiddenItems: Bool
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private var defaultsObserver: NSObjectProtocol?
    private var selectionAnchorURL: URL?
    private var selectionScope: [DesktopItem]?

    init(desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0],
         skipsHiddenItems: Bool = true) {
        self.desktopURL = desktopURL
        self.skipsHiddenItems = skipsHiddenItems
        refresh()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
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

    func setDisplayFolder(_ url: URL) {
        let folder = url.standardizedFileURL
        guard folder != desktopURL.standardizedFileURL else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        let wasMonitoring = directorySource != nil
        stopMonitoring()
        desktopURL = folder
        expandedFolders.removeAll()
        folderContents.removeAll()
        clearSelection()
        refresh()
        if wasMonitoring { startMonitoring() }
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .contentTypeKey]
        let options: FileManager.DirectoryEnumerationOptions = skipsHiddenItems ? [.skipsHiddenFiles] : []
        let urls = (try? FileManager.default.contentsOfDirectory(at: desktopURL,
                                                                 includingPropertiesForKeys: Array(keys),
                                                                 options: options)) ?? []
        let items = urls.compactMap(makeItem)
        groups = Dictionary(grouping: items, by: \DesktopItem.group)
        let existingURLs = Set(visibleItems.map(\.url))
        selectedURLs.formIntersection(existingURLs)
        if let selectedURL, !existingURLs.contains(selectedURL) {
            self.selectedURL = selectedURLs.first
        }
        if let selectionAnchorURL, !existingURLs.contains(selectionAnchorURL) {
            self.selectionAnchorURL = self.selectedURL
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func openWithApplications(for url: URL) -> [OpenWithApplication] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
            .map { OpenWithApplication(url: $0,
                                       name: FileManager.default.displayName(atPath: $0.path)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func open(_ url: URL, with applicationURL: URL) {
        NSWorkspace.shared.open([url],
                                withApplicationAt: applicationURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func toggleFolder(_ url: URL) {
        let key = folderKey(url)
        if expandedFolders.contains(key) {
            expandedFolders.remove(key)
        } else {
            folderContents[key] = contents(of: url)
            expandedFolders.insert(key)
        }
    }

    func children(of url: URL) -> [DesktopItem] {
        sorted(folderContents[folderKey(url)] ?? [])
    }

    func items(in directory: URL) -> [DesktopItem] {
        contents(of: directory)
    }

    func isFolderExpanded(_ url: URL) -> Bool { expandedFolders.contains(folderKey(url)) }

    var visibleItems: [DesktopItem] {
        CategoryOrderManager.shared.order.flatMap { group -> [DesktopItem] in
            guard expandedGroups.contains(group) else { return [] }
            return sorted(groups[group] ?? []).flatMap(flattenedItem)
        }
    }

    func setSelectionScope(_ items: [DesktopItem]?) {
        selectionScope = items
        let validURLs = Set((items ?? visibleItems).map(\.url))
        selectedURLs.formIntersection(validURLs)
        if let selectedURL, !validURLs.contains(selectedURL) { clearSelection() }
    }

    private var selectableItems: [DesktopItem] { selectionScope ?? visibleItems }

    @discardableResult
    func moveSelection(by offset: Int, extendingRange: Bool = false) -> URL? {
        let items = selectableItems
        guard !items.isEmpty else { clearSelection(); return nil }
        let current = selectedURL.flatMap { selected in items.firstIndex { $0.url == selected } }
        let next = min(max((current ?? (offset > 0 ? -1 : items.count)) + offset, 0), items.count - 1)
        if extendingRange, selectedURL != nil {
            extendSelection(to: items[next].url, in: items)
        } else {
            selectOnly(items[next].url)
        }
        return selectedURL
    }

    func select(_ url: URL, extendingRange: Bool) {
        guard extendingRange, selectedURL != nil else {
            selectOnly(url)
            return
        }
        extendSelection(to: url, in: selectableItems)
    }

    private func extendSelection(to url: URL, in items: [DesktopItem]) {
        let anchor = selectionAnchorURL ?? selectedURL ?? url
        guard let anchorIndex = items.firstIndex(where: { $0.url == anchor }),
              let clickedIndex = items.firstIndex(where: { $0.url == url }) else {
            selectOnly(url)
            return
        }
        let bounds = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
        selectedURLs = Set(bounds.map { items[$0].url })
        selectedURL = url
        selectionAnchorURL = anchor
    }

    func isSelected(_ url: URL) -> Bool { selectedURLs.contains(url) }
    func dragURLs(for url: URL) -> [URL] {
        selectedURLs.contains(url) ? Array(selectedURLs) : [url]
    }

    var selectionCount: Int { selectedURLs.count }

    func item(after url: URL, excluding excludedURLs: Set<URL>) -> URL? {
        let items = selectableItems
        guard let index = items.firstIndex(where: { $0.url == url }) else { return nil }
        let following = items.dropFirst(index + 1).first { !excludedURLs.contains($0.url) }
        let preceding = items[..<index].reversed().first { !excludedURLs.contains($0.url) }
        return following?.url ?? preceding?.url
    }

    private func selectOnly(_ url: URL) {
        selectedURL = url
        selectedURLs = [url]
        selectionAnchorURL = url
    }

    private func clearSelection() {
        selectedURL = nil
        selectedURLs.removeAll()
        selectionAnchorURL = nil
    }

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
        let urls = selectedURLs.contains(url) ? Array(selectedURLs) : [url]
        delete(urls)
    }

    func deleteSelection(selecting nextURL: URL? = nil) {
        guard !selectedURLs.isEmpty else { return }
        delete(Array(selectedURLs), selecting: nextURL)
    }

    private func delete(_ urls: [URL], selecting nextURL: URL? = nil) {
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.show(error) }
                self?.clearSelection()
                self?.refresh()
                if let nextURL,
                   FileManager.default.fileExists(atPath: nextURL.path) {
                    self?.selectOnly(nextURL)
                }
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

    private func contents(of directory: URL) -> [DesktopItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .contentTypeKey]
        let options: FileManager.DirectoryEnumerationOptions = skipsHiddenItems ? [.skipsHiddenFiles] : []
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: Array(keys),
                                                                 options: options)) ?? []
        return sorted(urls.compactMap(makeItem))
    }

    private func makeItem(_ url: URL) -> DesktopItem? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .contentTypeKey]
        let values = try? url.resourceValues(forKeys: keys)
        if skipsHiddenItems, values?.isHidden == true || url.lastPathComponent.hasPrefix(".") { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let directory = isDirectory.boolValue
        return DesktopItem(url: url,
                           group: directory ? .folders : DesktopGroup.group(for: url, resourceValues: values),
                           isDirectory: directory)
    }

    private func flattenedItem(_ item: DesktopItem) -> [DesktopItem] {
        guard item.isDirectory, isFolderExpanded(item.url) else { return [item] }
        return [item] + children(of: item.url).flatMap(flattenedItem)
    }

    func sorted(_ items: [DesktopItem]) -> [DesktopItem] {
        let rawMode = UserDefaults.standard.string(forKey: "itemSortMode") ?? ItemSortMode.name.rawValue
        let mode = ItemSortMode(rawValue: rawMode) ?? .name
        return items.sorted { lhs, rhs in
            switch mode {
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .kind:
                let leftKind = kindName(for: lhs)
                let rightKind = kindName(for: rhs)
                let comparison = leftKind.localizedStandardCompare(rightKind)
                return comparison == .orderedSame
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : comparison == .orderedAscending
            case .dateModified:
                let leftDate = (try? lhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate == rightDate
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : leftDate > rightDate
            }
        }
    }

    private func kindName(for item: DesktopItem) -> String {
        if item.isDirectory { return "Folder" }
        return (try? item.url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription)
            ?? item.url.pathExtension.lowercased()
    }

    private func folderKey(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    private func perform(_ work: () throws -> Void) {
        do { try work(); refresh() } catch { show(error) }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
