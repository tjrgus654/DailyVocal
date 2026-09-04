//
//  HapticManager.swift
//  DailyVocal
//
//  Centralized UIKit haptic feedback. All engines are prepared up front so
//  the first event has no latency.
//

import UIKit

@MainActor
public final class HapticManager {

    public static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private init() {
        prepare()
    }

    public func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        notificationFeedback.prepare()
        selectionFeedback.prepare()
    }

    /// Routine step transition.
    public func stepTransition() {
        mediumImpact.impactOccurred()
    }

    /// Timer tick / countdown.
    public func tick() {
        lightImpact.impactOccurred(intensity: 0.6)
    }

    /// Entering the on-pitch zone (fire only on rising edge, not per frame).
    public func onPitchHit() {
        selectionFeedback.selectionChanged()
    }

    /// Full routine completion.
    public func routineCompleted() {
        notificationFeedback.notificationOccurred(.success)
    }

    public func warning() {
        notificationFeedback.notificationOccurred(.warning)
    }

    /// Generic button tap.
    public func buttonTap() {
        selectionFeedback.selectionChanged()
    }
}
