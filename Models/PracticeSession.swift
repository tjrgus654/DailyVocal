//
//  PracticeSession.swift
//  5VocalMaster
//
//  SwiftData model for one completed (or partially completed) routine run.
//

import Foundation
import SwiftData

@Model
public final class PracticeSession {

    public var id: UUID
    public var date: Date
    public var durationSeconds: Int
    /// 0-based indices of steps that were practiced for at least 70% of their duration.
    public var completedStepIndices: [Int]
    public var isFullCompletion: Bool
    public var weekNumber: Int
    public var notes: String

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        durationSeconds: Int = 0,
        completedStepIndices: [Int] = [],
        isFullCompletion: Bool = false,
        weekNumber: Int = 1,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.completedStepIndices = completedStepIndices
        self.isFullCompletion = isFullCompletion
        self.weekNumber = weekNumber
        self.notes = notes
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    /// Local-time "yyyy-MM-dd" key used by the heatmap.
    public var dayKey: String {
        Self.dayFormatter.string(from: date)
    }

    public var formattedDuration: String {
        VocalLogic.durationLabel(seconds: durationSeconds)
    }
}
