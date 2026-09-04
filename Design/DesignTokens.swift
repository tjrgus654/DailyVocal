//
//  DesignTokens.swift
//  DailyVocal
//
//  Design system: colors, typography (SF Pro Rounded display stack),
//  gradients, layout constants, and the shared app background.
//

import SwiftUI

// MARK: - Color System
extension Color {
    /// 메인 브랜드 인디고 (#6366F1)
    static let brandPrimary = Color(red: 0.388, green: 0.400, blue: 0.945)

    /// 세컨더리 시안 (#06B6D4) - 피치 시각화 및 액센트
    static let brandSecondary = Color(red: 0.024, green: 0.714, blue: 0.831)

    /// 액센트 퍼플 (#A855F7) - 그라데이션 및 뱃지
    static let brandAccent = Color(red: 0.659, green: 0.333, blue: 0.969)

    /// 배경 상단 딥 네이비 (#0A0E27)
    static let backgroundTop = Color(red: 0.039, green: 0.055, blue: 0.153)

    /// 배경 하단 리얼 블랙 (#000000)
    static let backgroundBottom = Color.black

    /// 카드 서피스 다크 (#121633)
    static let surfaceDark = Color(red: 0.071, green: 0.086, blue: 0.200)

    /// 보더용 반투명 인디고
    static let borderGlass = Color.white.opacity(0.10)

    /// 텍스트 프라이머리
    static let textPrimary = Color.white

    /// 텍스트 세컨더리 (#94A3B8)
    static let textSecondary = Color(red: 0.580, green: 0.639, blue: 0.722)

    /// 피치 성공/온피치 에메랄드 (#10B981)
    static let vocalSuccess = Color(red: 0.063, green: 0.725, blue: 0.506)

    /// 피치 플랫/경고 앰버 (#F59E0B)
    static let vocalWarning = Color(red: 0.961, green: 0.620, blue: 0.043)

    /// 피치 샤프/에러 레드 (#EF4444)
    static let vocalAlert = Color(red: 0.937, green: 0.267, blue: 0.267)
}

// MARK: - Gradient Presets
extension LinearGradient {
    /// 메인 배경 딥 네이비 그라데이션
    static let mainBackground = LinearGradient(
        colors: [Color.backgroundTop, Color.backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 타이머 프로그레스 링 그라데이션
    static let timerRing = LinearGradient(
        colors: [Color.brandSecondary, Color.brandPrimary, Color.brandAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 메인 액션 버튼 그라데이션
    static let primaryButton = LinearGradient(
        colors: [Color.brandPrimary, Color.brandAccent],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 서브 뱃지 그라데이션
    static let accentBadge = LinearGradient(
        colors: [Color.brandAccent.opacity(0.8), Color.brandPrimary.opacity(0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 글래스 카드 상단 광택 라인 (깔쌈한 유리 느낌의 핵심)
    static let cardSheen = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.0), location: 0.4)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Shared background (gradient + aurora glow)
/// 앱 전체 공통 배경: 딥 네이비 수직 그라데이션 위에 브랜드 컬러의
/// 은은한 방사형 글로우를 겹쳐 입체감을 만든다.
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient.mainBackground
            RadialGradient(
                colors: [Color.brandPrimary.opacity(0.18), Color.brandPrimary.opacity(0.0)],
                center: UnitPoint(x: 0.5, y: -0.25),
                startRadius: 50,
                endRadius: 900
            )
            RadialGradient(
                colors: [Color.brandSecondary.opacity(0.10), Color.brandSecondary.opacity(0.0)],
                center: UnitPoint(x: 0.9, y: 1.1),
                startRadius: 50,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Typography Presets (SF Pro Rounded display stack)
extension Font {
    /// 메인 타이머 대형 숫자 디스플레이 (60pt Rounded, 타이트 트래킹)
    static let timerDisplay = Font.system(size: 60, weight: .bold, design: .rounded)
        .monospacedDigit()

    /// 화면 메인 타이틀 (24pt Rounded Heavy, 타이트)
    static let screenTitle = Font.system(size: 24, weight: .heavy, design: .rounded)

    /// 상단 eyebrow 라벨 (12pt Rounded Bold)
    static let eyebrow = Font.system(size: 12, weight: .bold, design: .rounded)

    /// 스텝/섹션 타이틀 (17pt Rounded Bold)
    static let sectionTitle = Font.system(size: 17, weight: .bold, design: .rounded)

    /// 카드 내부 서브헤드 (15pt Rounded Semibold)
    static let cardSubhead = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// 본문 (14pt Regular)
    static let tipBody = Font.system(size: 14, weight: .regular, design: .default)

    /// 캡션 (12pt Rounded Medium)
    static let smallCaption = Font.system(size: 12, weight: .medium, design: .rounded)

    /// 감지 음표 대형 디스플레이 (52pt Rounded Black)
    static let noteDisplay = Font.system(size: 52, weight: .black, design: .rounded)
}

// MARK: - Layout Constants
struct DesignLayout {
    static let cornerRadiusCard: CGFloat = 22
    static let cornerRadiusButton: CGFloat = 16
    static let cornerRadiusBadge: CGFloat = 10
    static let paddingStandard: CGFloat = 20
    static let paddingSmall: CGFloat = 12
    static let paddingLarge: CGFloat = 28
}
