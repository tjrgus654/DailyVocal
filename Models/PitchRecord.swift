//
//  PitchRecord.swift
//  5VocalMaster
//
//  SwiftData model summarizing one pitch-tracking measurement session
//  (created when the user stops tracking), used for range growth statistics.
//

import Foundation
import SwiftData

@Model
public final class PitchRecord {

    public var id: UUID
    public var timestamp: Date
    public var durationSeconds: Int

    public var targetNoteName: String
    public var targetFrequency: Double

    /// Average absolute cents deviation over voiced frames.
    public var averageCentsDeviation: Double
    /// Share of voiced frames that matched the target within ±25 cents (0...100).
    public var accuracyPercentage: Double
    public var voicedFrameCount: Int

    public var lowestNoteName: String
    public var lowestFrequency: Double
    public var highestNoteName: String
    public var highestFrequency: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        durationSeconds: Int = 0,
        targetNoteName: String = "",
        targetFrequency: Double = 0,
        averageCentsDeviation: Double = 0,
        accuracyPercentage: Double = 0,
        voicedFrameCount: Int = 0,
        lowestNoteName: String = "",
        lowestFrequency: Double = 0,
        highestNoteName: String = "",
        highestFrequency: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.targetNoteName = targetNoteName
        self.targetFrequency = targetFrequency
        self.averageCentsDeviation = averageCentsDeviation
        self.accuracyPercentage = accuracyPercentage
        self.voicedFrameCount = voicedFrameCount
        self.lowestNoteName = lowestNoteName
        self.lowestFrequency = lowestFrequency
        self.highestNoteName = highestNoteName
        self.highestFrequency = highestFrequency
    }
}
