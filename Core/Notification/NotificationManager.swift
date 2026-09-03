//
//  NotificationManager.swift
//  5VocalMaster
//
//  Local daily reminder (default 20:00) and streak-protection alert (22:30).
//  Local notifications need no Push Notifications capability — only the
//  user's permission.
//

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
public final class NotificationManager {

    public static let shared = NotificationManager()

    public private(set) var isAuthorized = false

    private static let dailyReminderID = "dailyVocalReminder"
    private static let streakAlertID = "streakProtectionAlert"

    private init() {
        refreshAuthorizationStatus()
    }

    public func refreshAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Requests permission (if needed) and schedules both reminders.
    /// Returns false when the user denied permission.
    @discardableResult
    public func enableDailyReminders(hour: Int = 20, minute: Int = 0) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                granted = true
            case .notDetermined:
                granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            default:
                granted = false
            }
        } catch {
            print("알림 권한 요청 실패: \(error.localizedDescription)")
            granted = false
        }
        isAuthorized = granted
        guard granted else { return false }

        scheduleDailyReminder(hour: hour, minute: minute)
        scheduleStreakAlert()
        return true
    }

    public func disableDailyReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.dailyReminderID, Self.streakAlertID]
        )
    }

    private func scheduleDailyReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderID])

        let content = UNMutableNotificationContent()
        content.title = "🎙️ 오늘의 15분 보컬 타임!"
        content.body = "목 풀 준비 되셨나요? 가벼운 립트릴부터 5단계 루틴으로 목소리를 깨워보세요."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: Self.dailyReminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.add(request)
    }

    private func scheduleStreakAlert() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.streakAlertID])

        let content = UNMutableNotificationContent()
        content.title = "🔥 스트릭이 끊어질 수 있어요!"
        content.body = "오늘 아직 보컬 연습을 하지 않았습니다. 자기 전 5분만 가벼운 웜업이라도 해볼까요?"
        content.sound = .default

        var components = DateComponents()
        components.hour = 22
        components.minute = 30

        let request = UNNotificationRequest(
            identifier: Self.streakAlertID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.add(request)
    }
}
