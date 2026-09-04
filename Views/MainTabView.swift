//
//  MainTabView.swift
//  DailyVocal
//
//  Root switch between onboarding and the 4-tab main interface.
//  Every tab owns its NavigationStack.
//

import SwiftUI

public struct MainTabView: View {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        if !onboardingCompleted {
            OnboardingView()
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DailyRoutineView()
                }
                .tabItem { Label("일일 루틴", systemImage: "calendar.badge.clock") }
                .tag(0)

                NavigationStack {
                    PitchTrackerView()
                }
                .tabItem { Label("피치 트래커", systemImage: "waveform.path.ecg") }
                .tag(1)

                NavigationStack {
                    VocalLabView()
                }
                .tabItem { Label("발성 연구소", systemImage: "books.vertical.fill") }
                .tag(2)

                NavigationStack {
                    VocalProgressView()
                }
                .tabItem { Label("성장 기록", systemImage: "chart.bar.fill") }
                .tag(3)
            }
            .tint(Color.brandPrimary)
            .preferredColorScheme(.dark)
            .toolbarBackground(.thinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
