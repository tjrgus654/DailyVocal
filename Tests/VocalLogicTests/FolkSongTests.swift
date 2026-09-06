import XCTest
@testable import VocalLogic

final class FolkSongTests: XCTestCase {

    func testLibraryShipsNineSongs() {
        XCTAssertEqual(VocalLogic.folkSongs.count, 9)
        XCTAssertEqual(VocalLogic.folkSongs.map(\.title),
                       ["아리랑", "강강술래", "한오백년", "정선아리랑", "둥당기타령", "도라지타령", "난봉가", "매화타령", "신고산타령"])
        // Every song documents its traditional origin (the PD basis).
        for song in VocalLogic.folkSongs {
            XCTAssertTrue(song.origin.contains("전통"), "\(song.title)")
            XCTAssertFalse(song.firstLyric.isEmpty, "\(song.title) needs its opening line")
            XCTAssertGreaterThanOrEqual(song.notes.count, 8, "\(song.title) needs a real phrase")
        }
    }

    func testNotesAreMusical() {
        for song in VocalLogic.folkSongs {
            for note in song.notes {
                // Pentatonic offsets on the la-based scale: 0,3,5,7,10(,12).
                XCTAssertTrue([0, 3, 5, 7, 10, 12].contains(note.offset),
                              "\(song.title) offset \(note.offset) breaks the pentatonic frame")
                XCTAssertTrue(note.beats > 0 && note.beats <= 4, "\(song.title) beats \(note.beats)")
            }
            // A phrase needs a grounded ending (long final note).
            XCTAssertTrue((3...4).contains(song.notes.last!.beats),
                          "\(song.title) must resolve on a 3-4 beat note")
        }
    }

    func testSongSequenceFromBase() {
        let arirang = VocalLogic.folkSongs[0]
        let seq = VocalLogic.songSequence(song: arirang, baseMidi: 55)
        XCTAssertEqual(seq.count, arirang.notes.count)
        XCTAssertEqual(seq.first, 55 + 7)  // mi above la
        XCTAssertEqual(seq.last, 55 + 3)   // resolves on do
    }

    func testSongSequenceClampedToBand() {
        let high = VocalLogic.songSequence(song: VocalLogic.folkSongs[2], baseMidi: 69)
        XCTAssertTrue(high.allSatisfy { (43...72).contains($0) })
        // 한오백년 ends on its base note (offset 0) — stays at 69, top note clamps at 72.
        XCTAssertEqual(high.last, 69)
        XCTAssertEqual(high.max(), 72)
        let low = VocalLogic.songSequence(song: VocalLogic.folkSongs[0], baseMidi: 44)
        XCTAssertTrue(low.allSatisfy { (43...72).contains($0) })
    }

    func testNoteDurationsFollowBeatsAndBpm() {
        let song = VocalLogic.folkSongs[1]
        // 60 BPM -> 1 beat = 1s.
        let at60 = VocalLogic.songNoteDurations(song: song, bpm: 60)
        XCTAssertEqual(at60.first!, 1.0, accuracy: 0.001)
        XCTAssertEqual(at60.last!, 3.0, accuracy: 0.001, "강강술래 ends on a 3-beat note")
        // Faster BPM (within the 40-80 clamp) shortens durations proportionally:
        // 80 BPM is 3/4 the beat of 60 BPM.
        let at80 = VocalLogic.songNoteDurations(song: song, bpm: 80)
        XCTAssertEqual(at80.first! / at60.first!, 0.75, accuracy: 0.001)
    }

    func testSongPreviewLine() {
        // Mid-rotation: 아리랑 -> 강강술래.
        XCTAssertTrue(VocalLogic.songPreviewLine(after: VocalLogic.folkSongs[0])
            .hasPrefix("다음 곡: 강강술래 '강강술래 강강술래'"))
        // Wrap-around: last song previews the first.
        XCTAssertTrue(VocalLogic.songPreviewLine(after: VocalLogic.folkSongs.last!)
            .hasPrefix("다음 곡: 아리랑 '아리랑 아리랑 아라리요'"))
        // Format invariant: title + quoted first lyric.
        for song in VocalLogic.folkSongs {
            let line = VocalLogic.songPreviewLine(after: song)
            XCTAssertTrue(line.contains("'"), line)
            XCTAssertTrue(line.hasPrefix("다음 곡: "), line)
        }
    }

    func testRegionTagsAndFilter() {
        // Every song derives a real region from its origin line.
        for song in VocalLogic.folkSongs {
            XCTAssertFalse(song.region.isEmpty, song.title)
            XCTAssertNotEqual(song.region, "기타", "\(song.title) origin should name a region: \(song.origin)")
        }
        // 강원 has exactly 정선아리랑; 전라 has 한오백년.
        XCTAssertEqual(VocalLogic.songs(inRegion: "강원").map(\.title), ["정선아리랑"])
        XCTAssertEqual(VocalLogic.songs(inRegion: "전라").map(\.title), ["한오백년"])
        // Region list is ordered, distinct, and covers every song.
        XCTAssertEqual(Set(VocalLogic.songRegions).count, VocalLogic.songRegions.count)
        XCTAssertEqual(VocalLogic.songRegions.count, Set(VocalLogic.folkSongs.map(\.region)).count)
    }

    /// The song book must work for MALE singers out of the box: from a
    /// comfortable male base the whole phrase stays inside the singing band
    /// without the top note clamping (clamped notes lose the melody).
    func testSongsSitInMaleComfortableRange() {
        // Male comfortable bases: E3(52)...G4(67). Everything must stay in
        // the band; the 55...62 core must be clamp-free.
        for base in 52...67 {
            for song in VocalLogic.folkSongs {
                let seq = VocalLogic.songSequence(song: song, baseMidi: base)
                XCTAssertTrue(seq.allSatisfy { (43...72).contains($0) },
                              "\(song.title) from \(base) left the band")
                if base >= 55 && base <= 62 {
                    let clamped = zip(seq, song.notes).filter { $0.0 != base + $0.1.offset }.count
                    XCTAssertEqual(clamped, 0,
                                   "\(song.title) from \(base) clamps \(clamped) notes — the melody breaks for male voices")
                }
            }
        }
    }
}
