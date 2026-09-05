//
//  AppRouter.swift
//  DailyVocal
//
//  Cross-tab navigation state. The growth dashboard's recommendation card
//  switches to the tracker tab AND pre-selects the recommended mode, so the
//  user lands one tap away from singing.
//

import SwiftUI
import Observation

@MainActor
@Observable
public final class AppRouter {
    public static let shared = AppRouter()

    /// Selected main tab (0 루틴 · 1 트래커 · 2 연구소 · 3 성장).
    public var selectedTab = 0
    /// Tracker mode to apply when the tracker tab next appears, then clears
    /// (one-shot deep link payload).
    public var pendingTrackerMode: PitchTrackerViewModel.TrackerMode?

    private init() {}
}
