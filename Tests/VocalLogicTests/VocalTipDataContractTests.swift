import XCTest
import Foundation
@testable import VocalLogic

/// Swift-executable contract over the SHIPPED Resources/vocal_tips.json —
/// previously only the Python static script verified this. Loads the real
/// file via #filePath (repo layout is fixed for both Windows dev and the
/// macOS CI checkout) and decodes it with the production Codable model.
final class VocalTipDataContractTests: XCTestCase {

    static let tips: [VocalTip] = load()

    /// Failure reason kept for the setUp message so all seven tests don't
    /// fail with an identical opaque "failed to load".
    static var loadError: String?

    static func load() -> [VocalTip] {
        // Tests/VocalLogicTests/<file> -> repo root is three levels up.
        let testFile = URL(fileURLWithPath: #filePath)
        let jsonURL = testFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/vocal_tips.json")
        do {
            let data = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([VocalTip].self, from: data)
        } catch {
            loadError = "\(jsonURL.path): \(error)"
            return []
        }
    }

    override func setUp() {
        XCTAssertNil(Self.loadError, "vocal_tips.json failed to load/decode: \(Self.loadError ?? "?")")
    }

    func testAllFiftyTwoTipsDecode() {
        XCTAssertEqual(Self.tips.count, 54)
    }

    func testIdsAreContiguousAndUnique() {
        let ids = Self.tips.map(\.id)
        XCTAssertEqual(ids, Array(1...54))
    }

    func testEveryCategoryPresentAndValid() {
        let used = Set(Self.tips.map(\.category))
        let valid = Set(VocalCategory.allCases)
        XCTAssertTrue(used.isSubset(of: valid))
        XCTAssertEqual(used, valid, "all 6 categories must ship content")
    }

    func testRelatedShortsResolveWithoutSelfReferenceOrDuplicates() {
        let ids = Set(Self.tips.map(\.id))
        for tip in Self.tips {
            XCTAssertEqual(Set(tip.relatedShorts).count, tip.relatedShorts.count,
                           "tip \(tip.id) has duplicate references")
            for related in tip.relatedShorts {
                XCTAssertTrue(ids.contains(related), "tip \(tip.id) references missing id \(related)")
                XCTAssertNotEqual(related, tip.id, "tip \(tip.id) self-references")
            }
            XCTAssertLessThanOrEqual(tip.relatedShorts.count, 3)
        }
    }

    /// The UI branches on viewCount > 0 (조회수 vs 연구 기반 팁 badge) and on
    /// youtubeURL != nil (link row): the two must agree for every tip.
    func testResearchTipMarkerConsistency() {
        for tip in Self.tips {
            if tip.viewCount == 0 {
                XCTAssertEqual(tip.youtubeId, "", "tip \(tip.id) has no views but a video id")
                XCTAssertNil(tip.youtubeURL)
            } else {
                XCTAssertFalse(tip.youtubeId.isEmpty, "tip \(tip.id) has views but no video id")
                XCTAssertNotNil(tip.youtubeURL)
            }
        }
        // Exactly the 4 research tips added in ROUND5.
        XCTAssertEqual(Self.tips.filter { $0.viewCount == 0 }.map(\.id), [49, 50, 51, 52, 53, 54])
    }

    func testContentFieldsNonEmpty() {
        for tip in Self.tips {
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.shortsSummary.isEmpty)
            XCTAssertFalse(tip.beginnerAnalogy.isEmpty)
            XCTAssertFalse(tip.howTo.isEmpty)
            XCTAssertFalse(tip.keyActionWord.isEmpty)
            XCTAssertTrue(tip.howTo.contains("\n"), "tip \(tip.id) howTo should have numbered steps")
            XCTAssertGreaterThanOrEqual(tip.viewCount, 0)
        }
    }

    func testFormattedViewCountFormatting() {
        func make(_ views: Int) -> VocalTip {
            VocalTip(id: 0, category: .breathing, title: "t", shortsSummary: "s",
                     beginnerAnalogy: "a", howTo: "1. x", youtubeId: "x",
                     viewCount: views, relatedShorts: [], keyActionWord: "k")
        }
        XCTAssertEqual(make(999).formattedViewCount, "999회")
        XCTAssertEqual(make(1_500).formattedViewCount, "1.5천회")
        XCTAssertEqual(make(23_400).formattedViewCount, "2.3만회")
    }
}
