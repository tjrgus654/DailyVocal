//
//  HaruVocalApp.swift
//  DailyVocal
//
//  App entry point: SwiftData container + default profile bootstrap.
//  Audio session configuration is owned by VocalAudioEngine and applied
//  lazily when audio actually starts (so launching the app never interrupts
//  background music).
//

import SwiftUI
import SwiftData

@main
struct HaruVocalApp: App {

    private let container: ModelContainer
    #if DEBUG
    @State private var showAudioDiagnostics = false
    #endif

    init() {
        do {
            let schema = Schema([
                PracticeSession.self,
                PitchRecord.self,
                UserProfile.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("SwiftData ModelContainer 초기화 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
                .onAppear(perform: ensureDefaultProfileExists)
                .onAppear(perform: applyDebugLaunchArgs)
                #if DEBUG
                .fullScreenCover(isPresented: $showAudioDiagnostics) {
                    AudioDiagnosticsView()
                }
                #endif
        }
        .modelContainer(container)
    }

    // MARK: - Debug launch arguments (CI store-screenshot capture)
    //
    // `--open-tab N` skips onboarding and opens tab N directly;
    // `--demo-seed` inserts representative records so the growth dashboard
    // and lab render rich content in captures. `--audio-diag` opens the
    // §6.1 on-device audio self-check. Debug builds only — never
    // active in a shipped app.

    @MainActor
    private func applyDebugLaunchArgs() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--open-tab") || args.contains("--demo-seed")
                || args.contains("--audio-diag") else { return }
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        if args.contains("--audio-diag") {
            showAudioDiagnostics = true
        }
        if args.contains("--demo-seed") {
            seedDemoContent()
        }
        if let flag = args.firstIndex(of: "--open-tab"), flag + 1 < args.count,
           let tab = Int(args[flag + 1]), (0...3).contains(tab) {
            AppRouter.shared.selectedTab = tab
        }
        #endif
    }

    /// One deterministic demo dataset: a profile with measured range +
    /// technique fingerprints, 6 pitch records, 5 practice days.
    @MainActor
    private func seedDemoContent() {
        let context = container.mainContext
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        if let profile {
            profile.hasMeasuredRange = true
            profile.prefersHigherKeyGuide = false
            profile.baselineHighestFrequency = 349.23   // F4
            profile.lowestFrequency = 98.0               // G2
            profile.lowestNoteName = "G2"
            profile.highestFrequency = 349.23
            profile.highestNoteName = "F4"
            profile.lastVibratoRateHz = 5.6
            profile.lastVibratoExtentCents = 74
            profile.lastDynamicsRangeDb = 11.8
            profile.bestSustainSeconds = 17.2
        }
        let targets: [(String, Double, Double)] = [
            ("모음 게임", 82, 0), ("비브라토 체크", 76, 5.6), ("다이내믹스 아치", 71, 11.8),
            ("스케일 시퀀스", 68, 0.8), ("멜로디 프레이즈", 74, 1.1), ("E4", 88, 0),
        ]
        for (index, entry) in targets.enumerated() {
            let record = PitchRecord(
                timestamp: Date().addingTimeInterval(-Double(index) * 3_600),
                durationSeconds: 60,
                targetNoteName: entry.0,
                targetFrequency: 329.6,
                averageCentsDeviation: 14,
                accuracyPercentage: entry.1,
                voicedFrameCount: 120,
                lowestNoteName: "G2", lowestFrequency: 98,
                highestNoteName: "F4", highestFrequency: 349.2,
                techniqueValue: entry.2)
            context.insert(record)
        }
        let calendar = Calendar.current
        for day in 0..<5 {
            let date = calendar.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            let session = PracticeSession(
                date: date,
                durationSeconds: 900,
                completedStepIndices: [0, 1, 2, 3, 4],
                isFullCompletion: true,
                weekNumber: 1,
                notes: "")
            context.insert(session)
        }
        try? context.save()
    }

    @MainActor
    private func ensureDefaultProfileExists() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserProfile>()
        let count: Int
        do {
            count = try context.fetchCount(descriptor)
        } catch {
            print("UserProfile fetchCount 실패 — 기본 프로필 생성 생략: \(error)")
            return
        }
        guard count == 0 else { return }
        context.insert(UserProfile())
        do {
            try context.save()
        } catch {
            print("기본 UserProfile 저장 실패: \(error)")
        }
    }
}
