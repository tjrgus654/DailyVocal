//
//  VocalCategoryTheme.swift
//  DailyVocal
//
//  SwiftUI presentation layer of the category enum defined in Core/Logic.
//

import SwiftUI

extension VocalCategory {
    /// 카테고리 테마 색상
    public var themeColor: Color {
        switch self {
        case .breathing:
            return Color(red: 0.235, green: 0.584, blue: 0.965) // 파랑
        case .falsettoSwitch:
            return Color(red: 0.133, green: 0.773, blue: 0.533) // 에메랄드
        case .soundDirection:
            return Color(red: 0.957, green: 0.447, blue: 0.447) // 코랄 레드
        case .jawLarynx:
            return Color(red: 0.659, green: 0.333, blue: 0.969) // 퍼플
        case .nasalResonance:
            return Color(red: 0.961, green: 0.773, blue: 0.188) // 앰버 옐로우
        case .practicalTips:
            return Color(red: 0.024, green: 0.714, blue: 0.831) // 시안
        }
    }
    
    /// 초보자 친화적 한 줄 설명
    public var summaryDescription: String {
        switch self {
        case .breathing:
            return "배에 무작정 힘주지 않고 풍선 주둥이처럼 호흡의 길 열기"
        case .falsettoSwitch:
            return "진성으로만 버티지 않고 가성을 켠 뒤 손바닥처럼 부드럽게 붙이기"
        case .soundDirection:
            return "목으로 소리를 삼키지 않고 앞니 30cm 앞 과녁으로 쏘아보내기"
        case .jawLarynx:
            return "고음 갈 때 턱 내밀지 않고 엘리베이터처럼 목젖을 안정시키기"
        case .nasalResonance:
            return "코를 쥐어짜는 생목 콧소리가 아닌 마스크 공명 통로 만들기"
        case .practicalTips:
            return "노래방 1분 웜업, 삑사리 즉시 교정, 모음 좁히기 비법"
        }
    }
}
