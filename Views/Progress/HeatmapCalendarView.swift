//
//  HeatmapCalendarView.swift
//  DailyVocal
//
//  GitHub-style contribution heatmap over the last 12 weeks. The day list is
//  built Monday-aligned (see ProgressViewModel), so the 7 columns line up
//  with the weekday header.
//

import SwiftUI

public struct HeatmapCalendarView: View {
    let days: [HeatmapDay]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    public init(days: [HeatmapDay]) {
        self.days = days
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("연습 활동 (최근 12주)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("총 \(activeDayCount)일 실천")
                    .font(.caption2)
                    .foregroundColor(.brandSecondary)
            }

            HStack(spacing: 4) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cellColor(for: day))
                        .frame(height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(
                                    day.count > 0 ? Color.brandSecondary.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
            }

            HStack(spacing: 6) {
                Spacer()
                Text("적음")
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("많음")
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
            }
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: 18, padding: 16)
    }

    private var activeDayCount: Int {
        days.filter { $0.count > 0 }.count
    }

    private func cellColor(for day: HeatmapDay) -> Color {
        switch day.count {
        case 0: return Color.white.opacity(0.06)
        case 1: return Color.brandPrimary.opacity(0.55)
        case 2: return Color.brandPrimary
        default: return Color.brandSecondary
        }
    }

    private func levelColor(for level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.06)
        case 1: return Color.brandPrimary.opacity(0.55)
        case 2: return Color.brandPrimary
        default: return Color.brandSecondary
        }
    }
}
