import XCTest
@testable import VocalLogic

/// Preset integrity contracts — the routine content ships as static data, so
/// a bad edit would otherwise only surface as a mistimed session on device.
final class RoutinePresetContractTests: XCTestCase {

    private let weeks: [[RoutineStep]] = [
        RoutinePresets.defaultRoutine(forWeek: 1),
        RoutinePresets.defaultRoutine(forWeek: 2),
        RoutinePresets.defaultRoutine(forWeek: 3),
        RoutinePresets.defaultRoutine(forWeek: 4),
    ]

    func testEveryWeekTotalsExactlyFifteenMinutes() {
        // Header contract: "All weeks total exactly 15 minutes."
        for (index, week) in weeks.enumerated() {
            let total = week.reduce(0) { $0 + $1.durationSeconds }
            XCTAssertEqual(total, 900, "week \(index + 1) totals \(total)s")
        }
    }

    func testWeekClampingOutOfRangeInput() {
        XCTAssertEqual(RoutinePresets.defaultRoutine(forWeek: 0).map(\.title), weeks[0].map(\.title))
        XCTAssertEqual(RoutinePresets.defaultRoutine(forWeek: 99).map(\.title), weeks[3].map(\.title))
    }

    func testStepNumbersAreSequential() {
        for week in weeks {
            XCTAssertEqual(week.map(\.stepNumber), Array(1...week.count))
            XCTAssertEqual(week.count, 5)
        }
    }

    func testEveryStepHasCompleteContent() {
        let allSteps = (weeks.flatMap { $0 } + RoutinePresets.quickRoutine() + RoutinePresets.restRoutine())
        for step in allSteps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.subtitle.isEmpty)
            XCTAssertFalse(step.soundKeyword.isEmpty)
            XCTAssertFalse(step.analogyTitle.isEmpty)
            XCTAssertFalse(step.analogyDescription.isEmpty)
            XCTAssertGreaterThanOrEqual(step.actionGuide.count, 3, step.title)
            XCTAssertTrue(step.actionGuide.allSatisfy { !$0.isEmpty }, step.title)
        }
    }

    func testShortcutsAreTwoMinuteSingleSteps() {
        for steps in [RoutinePresets.quickRoutine(), RoutinePresets.restRoutine()] {
            XCTAssertEqual(steps.count, 1)
            XCTAssertEqual(steps[0].durationSeconds, 120)
        }
    }

    /// Safety: a sore voice must never be handed a high-load drill. The rest
    /// routine contains minimal-SOVT shapes only and the no-whisper warning.
    func testRestRoutineIsMinimalLoadAndWarnsAboutWhispering() {
        let rest = RoutinePresets.restRoutine()[0]
        let fullText = ([rest.title, rest.subtitle, rest.soundKeyword] + rest.actionGuide).joined(separator: " ")
        XCTAssertFalse(fullText.contains("네이"), "rest routine must not include the bratty nay drill")
        XCTAssertFalse(fullText.contains("사이렌"), "rest routine must not include sirens")
        XCTAssertTrue(fullText.contains("속삭"), "rest routine must carry the no-whisper warning")
        XCTAssertEqual(rest.recommendedToneType, .sustainedNote, "guide tone must be a single held note")
    }

    func testCategoriesAreValidRawValues() {
        let allSteps = weeks.flatMap { $0 } + RoutinePresets.quickRoutine() + RoutinePresets.restRoutine()
        let valid = Set(VocalCategory.allCases.map(\.rawValue))
        for step in allSteps {
            XCTAssertTrue(valid.contains(step.category.rawValue), step.title)
        }
    }

    /// Duration formatting used by the timer UI.
    func testFormattedDuration() {
        XCTAssertEqual(RoutineStep(stepNumber: 1, title: "t", subtitle: "s", durationSeconds: 754,
                                   soundKeyword: "k", analogyEmoji: "e", analogyTitle: "a",
                                   analogyDescription: "d", actionGuide: ["1", "2", "3"],
                                   category: .breathing, recommendedToneType: .sustainedNote).formattedDuration,
                       "12:34")
    }

    // MARK: - Guide pattern contract

    func testGuidePatterns() {
        XCTAssertEqual(VocalLogic.guidePattern(for: .fiveToneScale), [0, 2, 4, 5, 7, 5, 4, 2, 0])
        XCTAssertEqual(VocalLogic.guidePattern(for: .octaveJump), [0, 12, 0])
        XCTAssertEqual(VocalLogic.guidePattern(for: .arpeggio), [0, 4, 7, 12, 7, 4, 0])
        XCTAssertEqual(VocalLogic.guidePattern(for: .sirenSlide), [0, 4, 7, 12, 7, 4, 0])
        XCTAssertEqual(VocalLogic.guidePattern(for: .sustainedNote), [0])
        // Every pattern starts and ends on the base note.
        for tone in TonePatternType.allCases {
            let pattern = VocalLogic.guidePattern(for: tone)
            XCTAssertFalse(pattern.isEmpty)
            XCTAssertEqual(pattern.first, 0, "\(tone)")
            XCTAssertEqual(pattern.last, 0, "\(tone)")
            XCTAssertTrue(pattern.allSatisfy { abs($0) <= 12 }, "\(tone) exceeds an octave")
        }
    }

    // MARK: - A4 clamp boundaries

    func testClampedA4Boundaries() {
        XCTAssertEqual(VocalLogic.clampedA4(0), 440)          // unset sentinel
        XCTAssertEqual(VocalLogic.clampedA4(-5), 435)         // negative -> floor
        XCTAssertEqual(VocalLogic.clampedA4(434.9), 435)
        XCTAssertEqual(VocalLogic.clampedA4(435), 435)
        XCTAssertEqual(VocalLogic.clampedA4(440), 440)
        XCTAssertEqual(VocalLogic.clampedA4(445), 445)
        XCTAssertEqual(VocalLogic.clampedA4(445.1), 445)
        XCTAssertEqual(VocalLogic.clampedA4(999), 445)
    }

    // MARK: - Stored-record label contract

    func testEchoLabelFormat() {
        XCTAssertEqual(VocalLogic.echoLabel(midis: [60, 64, 67]), "C4-E4-G4")
        XCTAssertEqual(VocalLogic.echoLabel(midis: [64, 61, 64]), "E4-C#4-E4")  // 61 = C#4
        // Empty for anything that is not a real 3-note sequence.
        XCTAssertEqual(VocalLogic.echoLabel(midis: []), "")
        XCTAssertEqual(VocalLogic.echoLabel(midis: [60]), "")
        XCTAssertEqual(VocalLogic.echoLabel(midis: [60, 64]), "")
    }

    func testEchoLabelPartsAreValidNoteNames() {
        let label = VocalLogic.echoLabel(midis: [43, 57, 72])
        XCTAssertFalse(label.isEmpty)
        let parts = label.split(separator: "-").map(String.init)
        XCTAssertEqual(parts.count, 3)
        for part in parts {
            XCTAssertNotNil(VocalLogic.midiNumber(forNoteName: part), part)
        }
    }
}
