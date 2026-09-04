//
//  VocalCategory.swift
//  DailyVocal
//
//  6 Core Vocal Training Categories mapped from OhVocal 48 Shorts.
//  Foundation-pure core (enum/titles/emoji) so preset contract tests run
//  on any toolchain; the SwiftUI theme color lives in Models/.
//

import Foundation

public enum VocalCategory: String, CaseIterable, Codable, Identifiable {
    case breathing = "breathing"
    case falsettoSwitch = "falsetto_switch"
    case soundDirection = "sound_direction"
    case jawLarynx = "jaw_larynx"
    case nasalResonance = "nasal_resonance"
    case practicalTips = "practical_tips"
    
    public var id: String { rawValue }
    
    /// 한글 카테고리 명칭
    public var title: String {
        switch self {
        case .breathing:
            return "호흡 & 복압"
        case .falsettoSwitch:
            return "가성 스위치 & 접지"
        case .soundDirection:
            return "소리 방향 OUT"
        case .jawLarynx:
            return "턱 & 후두 릴랙스"
        case .nasalResonance:
            return "비강공명 vs 생목"
        case .practicalTips:
            return "실전 팁 & 코노 치트키"
        }
    }
    
    /// 대표 이모지
    public var emoji: String {
        switch self {
        case .breathing: return "🫁"
        case .falsettoSwitch: return "🔊"
        case .soundDirection: return "🎯"
        case .jawLarynx: return "🦴"
        case .nasalResonance: return "👃"
        case .practicalTips: return "🎤"
        }
    }
}
