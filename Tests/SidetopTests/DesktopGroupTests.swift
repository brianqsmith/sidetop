import XCTest
@testable import Sidetop

final class DesktopGroupTests: XCTestCase {
    func testGroupingByCommonTypes() {
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/photo.png")), .images)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/notes.txt")), .documents)
        XCTAssertEqual(DesktopGroup.group(for: URL(fileURLWithPath: "/tmp/archive.zip")), .other)
    }
}
