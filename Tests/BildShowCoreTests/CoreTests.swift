import XCTest
@testable import BildShowCore

final class CoreTests: XCTestCase {
    func testFolderTreeSelectionCanExcludeAndReincludeSubtrees() {
        let root = FolderReference(path: "/Pictures")
        var folders = [root]
        XCTAssertTrue(FolderSelection.isIncluded("/Pictures/Birds/Owl", in: folders))

        folders = FolderSelection.toggled("/Pictures/Birds", bookmark: nil, in: folders)
        XCTAssertFalse(FolderSelection.isIncluded("/Pictures/Birds", in: folders))
        XCTAssertFalse(FolderSelection.isIncluded("/Pictures/Birds/Owl", in: folders))
        XCTAssertTrue(FolderSelection.isIncluded("/Pictures/Cars", in: folders))

        folders = FolderSelection.toggled("/Pictures/Birds/Owl", bookmark: nil, in: folders)
        XCTAssertTrue(FolderSelection.isIncluded("/Pictures/Birds/Owl", in: folders))
        XCTAssertFalse(FolderSelection.isIncluded("/Pictures/Birds/Eagle", in: folders))
    }

    func testNonRecursiveFolderDoesNotSelectChildren() {
        let root = FolderReference(path: "/Pictures", recursive: false)
        XCTAssertTrue(FolderSelection.isIncluded("/Pictures", in: [root]))
        XCTAssertFalse(FolderSelection.isIncluded("/Pictures/Birds", in: [root]))
    }

    func testLegacyFolderReferenceDecodesWithoutExclusions() throws {
        let json = #"{"id":"5EB5CC40-5C61-4AD7-9D49-09DC2FA8409C","path":"/Pictures","recursive":true}"#.data(using: .utf8)!
        let folder = try JSONDecoder().decode(FolderReference.self, from: json)
        XCTAssertEqual(folder.path, "/Pictures")
        XCTAssertNil(folder.excludedRelativePaths)
    }

    func testPresetInheritsOnlyUnchangedSettings() {
        var defaults = Preferences(); defaults.values[Setting.interval.rawValue] = .number(3)
        var preset = Preset(name: "Birds"); preset.overrides[Setting.transition.rawValue] = .text("fade")
        XCTAssertEqual(defaults.resolved(for: preset)[.interval].number, 3)
        XCTAssertEqual(defaults.resolved(for: preset)[.transition].text, "fade")
        defaults.values[Setting.interval.rawValue] = .number(6)
        XCTAssertEqual(defaults.resolved(for: preset)[.interval].number, 6)
        preset.overrides[Setting.interval.rawValue] = .number(2)
        XCTAssertEqual(defaults.resolved(for: preset)[.interval].number, 2)
    }
    func testSmartFillCropsWithoutDistorting() {
        let layout = ImageLayout.calculate(width: 1000, height: 800, screenWidth: 900, screenHeight: 800, settings: Preferences())
        XCTAssertEqual(layout.scale, 1, accuracy: 0.001)
        XCTAssertEqual(layout.x, -50, accuracy: 0.001)
        XCTAssertEqual(layout.width / layout.height, 1.25, accuracy: 0.001)
    }
    func testSmallPortraitUsesThreeTimesCapAt4K() {
        let layout = ImageLayout.calculate(width: 240, height: 360, screenWidth: 3840, screenHeight: 2160, settings: Preferences())
        XCTAssertEqual(layout.scale, 3)
        XCTAssertEqual(layout.width, 720)
        XCTAssertEqual(layout.height, 1080)
        XCTAssertEqual(layout.rule.featherPercent, 0.5)
    }
    func testPortraitIsNotAggressivelyCroppedBySmartDefault() {
        let layout = ImageLayout.calculate(width: 2400, height: 3600, screenWidth: 3840, screenHeight: 2160, settings: Preferences())
        XCTAssertEqual(layout.height, 2160, accuracy: 0.01)
        XCTAssertEqual(layout.width, 1440, accuracy: 0.01)
    }
    func testNearDisplaySizeChoosesBicubic() {
        let layout = ImageLayout.calculate(width: 2688, height: 1512, screenWidth: 3840, screenHeight: 2160, settings: Preferences())
        XCTAssertEqual(layout.rule.method, "bicubic")
        XCTAssertEqual(layout.width, 3840, accuracy: 0.01)
    }
    func testMinimumDimensionsAreOrientationIndependent() {
        var settings = Preferences(); settings.values[Setting.minShort.rawValue] = .number(240); settings.values[Setting.minLong.rawValue] = .number(360)
        let id = UUID()
        let first = ImageItem(path: "a.jpg", folderID: id, width: 240, height: 360, modified: .now, bytes: 1, type: "jpg")
        let second = ImageItem(path: "b.jpg", folderID: id, width: 360, height: 240, modified: .now, bytes: 1, type: "jpg")
        XCTAssertTrue(first.included(in: settings)); XCTAssertTrue(second.included(in: settings))
    }
    func testReconcilePreservesShuffleAndRemovesDuplicates() {
        let result = PlaybackOrder.reconcile(saved: ["b", "a", "b", "missing"], available: ["a", "b", "c", "c"], random: true)
        XCTAssertEqual(result, ["b", "a", "c"])
    }
    func testLoopAvoidsImmediateRepeatAndUsesEveryImage() {
        for _ in 0..<20 {
            let result = PlaybackOrder.nextRound(["a", "b", "c"], random: true, previous: "c")
            XCTAssertNotEqual(result.first, "c"); XCTAssertEqual(Set(result), Set(["a", "b", "c"]))
        }
    }
    func testPresetRoundTripRetainsBookmarkAndOverrides() throws {
        var preset = Preset(name: "Products")
        preset.folders = [FolderReference(path: "/Volumes/Pictures", bookmark: Data([1, 2, 3]), recursive: false)]
        preset.overrides[Setting.ending.rawValue] = .text("loop"); preset.markedPaths = ["/Volumes/Pictures/a.png"]
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
    }
}
