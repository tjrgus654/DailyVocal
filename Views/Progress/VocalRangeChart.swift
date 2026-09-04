//
//  VocalRangeChart.swift
//  DailyVocal
//
//  Vocal range growth chart. All values are real data passed in from the
//  profile: the onboarding baseline vs the current measured range, with the
//  expansion computed in semitones. Bars are drawn to scale inside a fixed
//  C2...C5 display window.
//

import SwiftUI

public struct VocalRangeChart: View {
    let hasMeasuredRange: Bool
    let baselineRangeText: String
    let currentRangeText: String
    let expansionSemitones: Int

    /// Display window in MIDI numbers (C2 = 36 ... C5 = 72).
    private let windowLow = 36.0
    private let windowHigh = 72.0

    public init(
        hasMeasuredRange: Bool,
        baselineRangeText: String,
        currentRangeText: String,
        expansionSemitones: Int
    ) {
        self.hasMeasuredRange = hasMeasuredRange
        self.baselineRangeText = baselineRangeText
        self.currentRangeText = currentRangeText
        self.expansionSemitones = expansionSemitones
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("음역대 변화")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if hasMeasuredRange {
                    Text(expansionLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(expansionColor)
                }
            }

            if hasMeasuredRange {
                rangeRow(
                    title: "시작 (측정 당시)",
                    rangeText: baselineRangeText,
                    accent: false
                )
                rangeRow(
                    title: "현재",
                    rangeText: currentRangeText,
                    accent: true
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.title3)
                        .foregroundColor(.textSecondary)
                    Text("아직 기준 측정이 없습니다.\n피치 트래커로 측정을 시작하면 음역대 성장이 기록됩니다.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            HStack {
                Text("C2")
                Spacer()
                Text("C3")
                Spacer()
                Text("C4")
                Spacer()
                Text("C5")
            }
            .font(.system(size: 9))
            .foregroundColor(.textSecondary)
        }
        .glassCard(cornerRadius: 18, padding: 16)
    }

    private var expansionLabel: String {
        switch expansionSemitones {
        case ..<0:
            return "\(expansionSemitones) 반음"
        case 0:
            return "변화 없음"
        default:
            return "+\(expansionSemitones) 반음 확장"
        }
    }

    private var expansionColor: Color {
        expansionSemitones > 0 ? .vocalSuccess : .textSecondary
    }

    /// Bar width is proportional to the semitone span of the range text
    /// (e.g. "C3 ~ A4" = 19 semitones) inside the 36-semitone window.
    private func rangeRow(
        title: String,
        rangeText: String,
        accent: Bool
    ) -> some View {
        let span = semitoneSpan(of: rangeText)
        let fraction = min(1, max(0.08, span / (windowHigh - windowLow)))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(accent ? .brandSecondary : .textSecondary)
                Spacer()
                Text(rangeText)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(accent ? .brandSecondary : .white)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            accent
                                ? LinearGradient(colors: [Color.brandPrimary, Color.brandSecondary],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.brandPrimary.opacity(0.6), Color.brandPrimary],
                                                 startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 16)
        }
    }

    /// Parses "C3 ~ A4"-style text into a semitone count.
    private func semitoneSpan(of text: String) -> Double {
        let parts = text.split(separator: "~").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let low = VocalAudioEngine.midiNumber(forNoteName: parts[0]),
              let high = VocalAudioEngine.midiNumber(forNoteName: parts[1]) else {
            return 0
        }
        return Double(high - low)
    }
}
