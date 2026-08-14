import XCTest
@testable import Sidetop

final class DesktopGroupTests: XCTestCase {
    func testGroupingByCommonTypes() {
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/photo.png")), .images)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/Screenshot 2026-08-13 at 4.00.00 AM.png")), .screenshots)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/Screen Shot 2026-08-13.png")), .screenshots)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/notes.txt")), .documents)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/archive.zip")), .archives)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/movie.mp4")), .movies)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/song.mp3")), .music)
    }

    @MainActor
    func testFolderExpansionAndKeyboardOrder() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SidetopTests-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: folder.appendingPathComponent("inside.txt"))
        try Data("two".utf8).write(to: root.appendingPathComponent("outside.txt"))
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["Folder", "outside.txt"])

        let model = DesktopModel(desktopURL: root, skipsHiddenItems: false)
        model.refresh()
        model.toggleFolder(folder)

        XCTAssertTrue(model.isFolderExpanded(folder))
        XCTAssertEqual(model.children(of: folder).map(\.name), ["inside.txt"])
        XCTAssertEqual(model.visibleItems.map(\.name), ["Folder", "inside.txt", "outside.txt"])
        XCTAssertEqual(model.moveSelection(by: 1)?.lastPathComponent, "Folder")
        XCTAssertEqual(model.moveSelection(by: 1)?.lastPathComponent, "inside.txt")
        XCTAssertEqual(model.moveSelection(by: 1)?.lastPathComponent, "outside.txt")
        XCTAssertEqual(model.moveSelection(by: -1)?.lastPathComponent, "inside.txt")
    }

    @MainActor
    func testShiftSelectionUsesVisibleRange() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SidetopSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("a.txt")
        let second = root.appendingPathComponent("b.txt")
        let third = root.appendingPathComponent("c.txt")
        try Data().write(to: first)
        try Data().write(to: second)
        try Data().write(to: third)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = DesktopModel(desktopURL: root, skipsHiddenItems: false)
        model.select(first, extendingRange: false)
        model.select(third, extendingRange: true)

        XCTAssertEqual(model.selectedURL, third)
        XCTAssertEqual(model.selectedURLs, Set([first, second, third]))
        XCTAssertTrue(model.isSelected(second))

        model.select(second, extendingRange: false)
        XCTAssertEqual(model.selectedURLs, [second])
    }

    @MainActor
    func testShiftArrowExtendsAndShrinksSelection() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SidetopKeyboardSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = ["a.txt", "b.txt", "c.txt"].map { root.appendingPathComponent($0) }
        for url in urls { try Data().write(to: url) }
        defer { try? FileManager.default.removeItem(at: root) }

        let model = DesktopModel(desktopURL: root, skipsHiddenItems: false)
        model.select(urls[0], extendingRange: false)

        XCTAssertEqual(model.moveSelection(by: 1, extendingRange: true), urls[1])
        XCTAssertEqual(model.selectedURLs, Set(urls[0...1]))
        XCTAssertEqual(model.moveSelection(by: 1, extendingRange: true), urls[2])
        XCTAssertEqual(model.selectedURLs, Set(urls))
        XCTAssertEqual(model.moveSelection(by: -1, extendingRange: true), urls[1])
        XCTAssertEqual(model.selectedURLs, Set(urls[0...1]))

        XCTAssertEqual(model.moveSelection(by: 1), urls[2])
        XCTAssertEqual(model.selectedURLs, [urls[2]])
    }

    @MainActor
    func testChangingDisplayFolderRefreshesContents() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SidetopDisplayFolderTests-\(UUID().uuidString)", isDirectory: true)
        let firstFolder = base.appendingPathComponent("First", isDirectory: true)
        let secondFolder = base.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try Data().write(to: firstFolder.appendingPathComponent("first.txt"))
        try Data().write(to: secondFolder.appendingPathComponent("second.txt"))
        defer { try? FileManager.default.removeItem(at: base) }

        let model = DesktopModel(desktopURL: firstFolder, skipsHiddenItems: false)
        XCTAssertEqual(model.visibleItems.map(\.name), ["first.txt"])

        model.setDisplayFolder(secondFolder)
        XCTAssertEqual(model.desktopURL, secondFolder.standardizedFileURL)
        XCTAssertEqual(model.visibleItems.map(\.name), ["second.txt"])
        XCTAssertTrue(model.selectedURLs.isEmpty)
    }

    @MainActor
    func testNextItemAfterDeletionPrefersFollowingThenPrevious() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("SidetopDeleteNavigationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = ["a.txt", "b.txt", "c.txt"].map { root.appendingPathComponent($0) }
        for url in urls { try Data().write(to: url) }
        defer { try? FileManager.default.removeItem(at: root) }

        let model = DesktopModel(desktopURL: root, skipsHiddenItems: false)
        XCTAssertEqual(model.item(after: urls[1], excluding: [urls[1]]), urls[2])
        XCTAssertEqual(model.item(after: urls[2], excluding: [urls[2]]), urls[1])
        XCTAssertNil(model.item(after: urls[1], excluding: Set(urls)))
    }
}
