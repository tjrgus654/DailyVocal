import XCTest
@testable import VocalLogic

final class TipRecommendationTests: XCTestCase {

    func testWeaknessFirstPriority() {
        // Sustain wins over everything when breath support is the wall.
        let r = VocalLogic.recommendedTip(
            vibratoRateHz: 3.8, dynamicsRangeDb: 4.0,
            bestSustainSeconds: 9, isMaleVoice: true)
        XCTAssertEqual(r?.id, 60)
        XCTAssertTrue(r?.reason.contains("호흡 지지") == true)
        // Vibrato next once sustain is healthy.
        let v = VocalLogic.recommendedTip(
            vibratoRateHz: 7.2, dynamicsRangeDb: 4.0,
            bestSustainSeconds: 16, isMaleVoice: false)
        XCTAssertEqual(v?.id, 55)
        // Dynamics next.
        let d = VocalLogic.recommendedTip(
            vibratoRateHz: 5.5, dynamicsRangeDb: 4.2,
            bestSustainSeconds: 16, isMaleVoice: false)
        XCTAssertEqual(d?.id, 56)
    }

    func testFallbacks() {
        let male = VocalLogic.recommendedTip(
            vibratoRateHz: 5.5, dynamicsRangeDb: 8, bestSustainSeconds: 16, isMaleVoice: true)
        XCTAssertEqual(male?.id, 58)
        let general = VocalLogic.recommendedTip(
            vibratoRateHz: 0, dynamicsRangeDb: 0, bestSustainSeconds: 0, isMaleVoice: false)
        XCTAssertEqual(general?.id, 57)
    }
}
