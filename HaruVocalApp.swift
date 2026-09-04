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
        }
        .modelContainer(container)
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
