//
//  RoutineStep.swift
//  5VocalMaster
//
//  5-step daily routine definition with week-specific presets.
//  Every training week has a different emphasis following the 4-week roadmap
//  (W1 relaxation/breathing, W2 falsetto switch, W3 mix/passaggio, W4 vowel
//  tuning & song application). All weeks total exactly 15 minutes.
//
//  Presets follow vocal-science evidence: SOVT exercises (lip trill, straw,
//  humming) open every session; each week ends with a short cool-down —
//  Ragan 2016 (J. Voice) found SOVT/humming the most effective cool-down and
//  singers felt better 12–24h post-practice; Ragsdale 2022 (J. Voice) found
//  5–10 min warm-ups sufficient, so no session ever exceeds 15 minutes.
//

import SwiftUI

public struct RoutineStep: Identifiable, Hashable {

    public let stepNumber: Int            // 1...5
    public let title: String
    public let subtitle: String
    public let durationSeconds: Int
    public let soundKeyword: String
    public let analogyEmoji: String
    public let analogyTitle: String
    public let analogyDescription: String
    public let actionGuide: [String]
    public let category: VocalCategory
    public let recommendedToneType: TonePatternType

    public var id: Int { stepNumber }

    public var formattedDuration: String {
        String(format: "%02d:%02d", durationSeconds / 60, durationSeconds % 60)
    }
}

public enum TonePatternType: String, Codable {
    case sirenSlide        // continuous low-high siren (guided by arpeggio)
    case octaveJump        // 1-8-1
    case fiveToneScale     // 1-2-3-4-5-4-3-2-1
    case arpeggio          // 1-3-5-8-5-3-1
    case sustainedNote     // single held tone
}

public enum RoutinePresets {

    /// Week-specific routine. `week` is clamped to 1...4.
    public static func defaultRoutine(forWeek week: Int) -> [RoutineStep] {
        switch week.clamped(to: 1...4) {
        case 1: return week1
        case 2: return week2
        case 3: return week3
        default: return week4
        }
    }

    /// Busy-day shortcut: one 2-minute step that still touches breath,
    /// resonance and range so the streak never has to die on a packed day.
    public static func quickRoutine() -> [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "퀵 2분: 목 깨우기",
                subtitle: "립트릴 → 허밍 → 사이렌 압축 세트",
                durationSeconds: 120,
                soundKeyword: "부르르 → 음- → 우에에엥",
                analogyEmoji: "⚡",
                analogyTitle: "엔진 예열 비유",
                analogyDescription: "노래방 가기 전 2분. 차가운 엔진으로 출발하면 목이 금방 지칠 수 있습니다. 세 동작만 빠르게 돌리면 성대가 깨어납니다.",
                actionGuide: [
                    "40초: 입술을 '부르르' 떨며 편안한 음역을 왕복합니다. 안 되면 빨대를 물고 '우---'로 대체합니다.",
                    "40초: '음---' 허밍으로 콧대 울림을 깨웁니다.",
                    "40초: '우-' 사이렌으로 저음에서 고음까지 한 번 미끄러뜨립니다."
                ],
                category: .breathing,
                recommendedToneType: .sirenSlide
            )
        ]
    }

    /// Sore-voice day: volume-minimal SOVT only. Pain means the mucosa needs
    /// recovery, not training (Iowa voice-rest protocol: relative rest, no
    /// whispering, no high-effort phonation).
    public static func restRoutine() -> [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "쉬는 날 2분: 소리 줄이기",
                subtitle: "아주 작은 빨대 발성과 저음 허밍만",
                durationSeconds: 120,
                soundKeyword: "빨대 우--- (아주 작게) → 음- → 하---",
                analogyEmoji: "🩹",
                analogyTitle: "딱지 비유",
                analogyDescription: "아픈 성대는 무릎의 딱지와 같아서, 큰 소리는 딱지를 뜯는 행위입니다. 오늘은 아주 작은 소리로 혈류만 돌려줍니다.",
                actionGuide: [
                    "40초: 빨대를 물고 들릴락 말락한 크기로 '우---'를 붑니다. 높이는 편한 한 음만 유지합니다.",
                    "40초: 아주 낮고 작은 '음---' 허밍으로 콧대에 온기만 느껴지게 합니다.",
                    "40초: 하품하듯 입을 열고 조용한 한숨 '하---'로 마무리합니다. 절대 속삭이지 않습니다 — 속삭임이 조용한 말보다 성대에 부담입니다."
                ],
                category: .breathing,
                recommendedToneType: .sustainedNote
            )
        ]
    }

    // MARK: - Week 1: 목 힘 0% & 호흡 길 뚫기 (240/180/180/150/150)

    private static var week1: [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "1단계: 웜업 & 호흡",
                subtitle: "립트릴로 목 힘 완전히 풀기",
                durationSeconds: 240,
                soundKeyword: "부르르- (Lip Bubble)",
                analogyEmoji: "🎈",
                analogyTitle: "풍선 주둥이 비유",
                analogyDescription: "배에 무식하게 힘을 주면 목이 조입니다. 풍선 주둥이를 얇게 열어 바람이 고르게 빠지듯 호흡을 흘려보냅니다.",
                actionGuide: [
                    "시작 전 물을 한 모금 마셔 성대 점막을 촉촉하게 만듭니다.",
                    "턱을 양손으로 가볍게 받치고 볼을 모아줍니다.",
                    "입술을 '부르르' 편안하게 떨며 저음부터 고음까지 사이렌을 오릅니다.",
                    "립트릴이 안 되면 가는 빨대를 물고 '우---'로 대체합니다. 역압(SOVT) 효과는 비슷합니다.",
                    "목이나 어깨에 힘이 들어가면 즉시 멈추고 하품하듯 숨을 다시 쉽니다."
                ],
                category: .breathing,
                recommendedToneType: .sirenSlide
            ),
            RoutineStep(
                stepNumber: 2,
                title: "2단계: 성대 깨우기",
                subtitle: "허밍으로 공명 통로 열기",
                durationSeconds: 180,
                soundKeyword: "음- (Humming)",
                analogyEmoji: "👃",
                analogyTitle: "마스크 공명 비유",
                analogyDescription: "소리를 목에서 만들지 말고, 콧대에 선글라스가 얹히는 위치의 '마스크'에 울리게 합니다.",
                actionGuide: [
                    "입을 다물고 '음---'을 길게 내며 콧대와 입술 끝이 찌릿한지 확인합니다.",
                    "허밍 그대로 입을 열어 '음→아'로 넘겨 울림 위치를 유지합니다.",
                    "고음으로 갈수록 힘이 아닌 울림의 위치만 위로 옮깁니다."
                ],
                category: .nasalResonance,
                recommendedToneType: .fiveToneScale
            ),
            RoutineStep(
                stepNumber: 3,
                title: "3단계: 호흡 압력 훈련",
                subtitle: "치찰음으로 일정한 바람 만들기",
                durationSeconds: 180,
                soundKeyword: "스--- (20초 유지)",
                analogyEmoji: "🥤",
                analogyTitle: "빨대 불기 비유",
                analogyDescription: "얇은 빨대로 바람을 불듯 세기가 변하지 않는 일정한 호흡을 만듭니다. 노래의 이어지는 호흡이 이 감각입니다.",
                actionGuide: [
                    "윗니 사이로 '스---'를 20초간 일정한 세기로 뱉습니다.",
                    "마지막 3초까지 세기가 유지되지 않으면 배를 더 쥐지 말고 옆구리 팽창을 유지합니다.",
                    "3회 반복하며 그대로 소리('수---')로 바꿔 같은 압력을 느껴봅니다.",
                    "'우---'를 8초에 걸쳐 작게→보통→작게로 조절해봅니다(messa di voce). 압력 관리와 안정된 시작·끝을 함께 훈련합니다."
                ],
                category: .breathing,
                recommendedToneType: .sustainedNote
            ),
            RoutineStep(
                stepNumber: 4,
                title: "4단계: 턱 & 목 릴랙스",
                subtitle: "하품 자세로 후두 내리기",
                durationSeconds: 150,
                soundKeyword: "하품 → 우- (Yawn Sigh)",
                analogyEmoji: "🛗",
                analogyTitle: "엘리베이터 비유",
                analogyDescription: "고음이라고 목젖이 턱 밑으로 올라가면 안 됩니다. 하품할 때처럼 목젖이 지하 1층에 머물러 둡니다.",
                actionGuide: [
                    "하품을 살짝 참으며 입안 공간을 넓힙니다.",
                    "그 공간 그대로 '우-'를 낮은 음에서 높은 음으로 부드럽게 미끄러뜨립니다.",
                    "거울로 턱밑이 딱딱해지지 않았는지 수시로 확인합니다."
                ],
                category: .jawLarynx,
                recommendedToneType: .sirenSlide
            ),
            RoutineStep(
                stepNumber: 5,
                title: "5단계: 마무리 사이렌",
                subtitle: "편안한 범위 왕복으로 정리",
                durationSeconds: 150,
                soundKeyword: "우에에엥- (Siren)",
                analogyEmoji: "🚨",
                analogyTitle: "소방차 사이렌 비유",
                analogyDescription: "오늘 연 낮은 길과 높은 길을 끊김 없이 왕복하며 몸에 오늘의 감각을 각인시킵니다.",
                actionGuide: [
                    "립트릴 또는 '우-'로 가장 편한 음역을 끊김 없이 오르내립니다.",
                    "중간에 목이 잠기면 볼륨을 반으로 줄이고 다시 시도합니다.",
                    "마지막에 가장 편안한 중음을 10초간 유지하며 마무리합니다."
                ],
                category: .soundDirection,
                recommendedToneType: .arpeggio
            )
        ]
    }

    // MARK: - Week 2: 가성 스위치 & 접지 (180/240/180/150/150)

    private static var week2: [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "1단계: 웜업",
                subtitle: "립트릴로 목 힘 0% 만들기",
                durationSeconds: 180,
                soundKeyword: "부르르- (Lip Bubble)",
                analogyEmoji: "🎈",
                analogyTitle: "풍선 주둥이 비유",
                analogyDescription: "배를 쥐어짜지 않고 풍선 주둥이만 얇게 열어 고른 호흡을 만듭니다.",
                actionGuide: [
                    "턱을 받치고 입술을 '부르르' 떨며 편안한 음역을 왕복합니다.",
                    "호흡이 흔들리면 옆구리 팽창을 다시 확인합니다.",
                    "1분간 반복해 몸을 발성 준비 상태로 만듭니다."
                ],
                category: .breathing,
                recommendedToneType: .sirenSlide
            ),
            RoutineStep(
                stepNumber: 2,
                title: "2단계: 가성 스위치",
                subtitle: "부엉이 소리로 가성 먼저 켜기",
                durationSeconds: 240,
                soundKeyword: "후- (Owl)",
                analogyEmoji: "🦉",
                analogyTitle: "부엉이 비유",
                analogyDescription: "고음을 진성으로 밀지 말고, 힘 뺀 가성부터 먼저 켭니다. 전등을 켜듯 가성 스위치를 먼저 올리는 것입니다.",
                actionGuide: [
                    "목에 힘을 완전히 빼고 작게 '후-' 높은 가성을 냅니다.",
                    "바람 소리만 나도 괜찮습니다. 크기는 신경 쓰지 않습니다.",
                    "낮은음→높은음 순서로 스위치가 켜지는 감각을 5회 익힙니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .octaveJump
            ),
            RoutineStep(
                stepNumber: 3,
                title: "3단계: 성대 접지",
                subtitle: "'응'을 붙여 흩어진 소리 모으기",
                durationSeconds: 180,
                soundKeyword: "응-후 / 밍- (Ming)",
                analogyEmoji: "👏",
                analogyTitle: "손바닥 포개기 비유",
                analogyDescription: "뜬 가성은 두 손바닥을 마주 대듯 성대를 부드럽게 붙여 알맹이를 만듭니다. 부딪히면 안 되고 스치듯 닿아야 합니다.",
                actionGuide: [
                    "부엉이 '후-' 앞에 '응-'을 붙여 '응-후-'로 연결합니다.",
                    "'밍-'으로 입을 다문 채 같은 접지 감각을 반복합니다.",
                    "앞니 뒤나 콧대에 찌릿한 진동이 느껴지면 성공입니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .fiveToneScale
            ),
            RoutineStep(
                stepNumber: 4,
                title: "4단계: 가벼운 어택",
                subtitle: "'읏-아'로 성대 착지 감각",
                durationSeconds: 150,
                soundKeyword: "읏-아 (Light Onset)",
                analogyEmoji: "🪶",
                analogyTitle: "깃털 착지 비유",
                analogyDescription: "소리의 첫 순간 성대가 '톡' 가볍게 맞닿아야 합니다. 깃털이 내려앉듯 부드러운 어택을 만듭니다.",
                actionGuide: [
                    "숨을 살짝 머금고 '읏' 준비 후 '아'를 아주 가볍게 시작합니다.",
                    "첫 소리가 터지거나 숨이 새면 볼륨을 줄여 다시 합니다.",
                    "5회 반복해 매번 같은 착지 감각을 만듭니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .sustainedNote
            ),
            RoutineStep(
                stepNumber: 5,
                title: "5단계: 접지 가창",
                subtitle: "가벼운 노래 1소절 적용",
                durationSeconds: 150,
                soundKeyword: "응→가사",
                analogyEmoji: "🎯",
                analogyTitle: "밑그림 위에 입히기",
                analogyDescription: "오늘 만든 접지 감각을 실제 노래에 얹습니다. 처음엔 볼륨 50%로 충분합니다.",
                actionGuide: [
                    "노래 직전 20초: 빨대 '우---' 또는 허밍으로 성대를 다시 예열한 뒤 바로 노래에 들어갑니다.",
                    "편안한 애창곡 1소절을 '응-응-'으로 먼저 부릅니다.",
                    "같은 소절을 모음으로만 부릅니다.",
                    "접지 감각을 유지한 채 본 가사를 가볍게 얹어 완성합니다.",
                    "마무리 쿨다운: '음---' 허밍이나 립트릴 20초로 성대를 식힙니다."
                ],
                category: .practicalTips,
                recommendedToneType: .fiveToneScale
            )
        ]
    }

    // MARK: - Week 3: 믹스보이스 & 파사지오 돌파 (180/180/300/120/120)

    private static var week3: [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "1단계: 웜업",
                subtitle: "립트릴 사이렌",
                durationSeconds: 180,
                soundKeyword: "부르르- (Lip Bubble)",
                analogyEmoji: "🎈",
                analogyTitle: "풍선 주둥이 비유",
                analogyDescription: "고른 호흡 위에서만 믹스가 만들어집니다. 웜업으로 몸의 바탕을 고르게 합니다.",
                actionGuide: [
                    "립트릴로 편안한 음역을 왕복합니다.",
                    "파사지오 구간을 지날 때 특별히 힘을 더하지 않습니다.",
                    "숨이 부족해지면 호흡부터 다시 세팅합니다."
                ],
                category: .breathing,
                recommendedToneType: .sirenSlide
            ),
            RoutineStep(
                stepNumber: 2,
                title: "2단계: 가성→접지 리마인드",
                subtitle: "'응-후' 빠른 복습",
                durationSeconds: 180,
                soundKeyword: "응-후 / 밍- (Ming)",
                analogyEmoji: "👏",
                analogyTitle: "손바닥 포개기 비유",
                analogyDescription: "오리 소리 전에 접지 감각을 다시 확인합니다. 흩어진 가성 위에는 믹스가 세워지지 않습니다.",
                actionGuide: [
                    "'응-후'를 3회, '밍-'을 3회 반복합니다.",
                    "진동 위치가 앞(콧대·앞니 뒤)에 있는지 확인합니다.",
                    "뒤에서 소리가 나면 다시 1단계 호흡으로 돌아갑니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .octaveJump
            ),
            RoutineStep(
                stepNumber: 3,
                title: "3단계: 오리 소리 Nay",
                subtitle: "파사지오(2옥 솔/라) 돌파",
                durationSeconds: 300,
                soundKeyword: "네이 네이 (Nay)",
                analogyEmoji: "🦆",
                analogyTitle: "마녀 웃음 & 오리 소리 비유",
                analogyDescription: "과장된 코맹맹이 '네이'로 성대를 얇게 유지하면, 힘을 쓰지 않고도 2옥타브 후반을 통과할 수 있습니다.",
                actionGuide: [
                    "디즈니 마녀처럼 얄미운 톤으로 '네이!'를 외칩니다.",
                    "가이드 5도 스케일에 맞춰 반음씩 올라가며 반복합니다.",
                    "파사지오 구간(남자 2옥타브 미~솔·여자 3옥타브 레~파, 바리톤은 2~3반음 낮게)에서 목이 조이면 볼륨을 30% 줄이고 코맹맹이를 더 과장합니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .fiveToneScale
            ),
            RoutineStep(
                stepNumber: 4,
                title: "4단계: 소리 방향 OUT",
                subtitle: "앞니 30cm 앞으로 던지기",
                durationSeconds: 120,
                soundKeyword: "아→앞으로 (Direction)",
                analogyEmoji: "🎯",
                analogyTitle: "물총 쏘기 비유",
                analogyDescription: "소리를 목으로 삼키면(IN) 조입니다. 앞니 30cm 앞 허공의 과녁으로 포물선을 그리며 던집니다.",
                actionGuide: [
                    "앞에 과녁을 상상하고 '아'를 그 지점으로 던집니다.",
                    "삼키는 발성(울림이 목에 꽂히는 느낌)과 던지는 발성을 비교합니다.",
                    "Nay에서 얻은 높은 길을 '아' 모음으로 유지해 던져봅니다."
                ],
                category: .soundDirection,
                recommendedToneType: .arpeggio
            ),
            RoutineStep(
                stepNumber: 5,
                title: "5단계: Nay→가사 조립",
                subtitle: "고음 소절 3단계 완성",
                durationSeconds: 120,
                soundKeyword: "네이 → 모음 → 가사",
                analogyEmoji: "🎨",
                analogyTitle: "밑그림→채색→디테일",
                analogyDescription: "1) 네이로 스케치 2) 모음으로 채색 3) 가사로 디테일. 이 순서를 지키면 고음 소절이 무너지지 않습니다.",
                actionGuide: [
                    "노래 직전 20초: 빨대 '우---'로 성대를 다시 예열합니다. 웜업 감각은 오래가지 않으므로 노래에 바로 붙입니다.",
                    "애창곡 최고음 소절을 '네이 네이'로 부릅니다.",
                    "같은 소절을 모음만으로 부릅니다 ('사랑해'→'아-아-에').",
                    "본 가사를 얹되, 절대 지르지 않고 Nay 볼륨 그대로 완성합니다.",
                    "마무리 쿨다운: 빨대 발성이나 립트릴로 높은 음→낮은 음 내리막을 3회 미끄러뜨립니다."
                ],
                category: .practicalTips,
                recommendedToneType: .sustainedNote
            )
        ]
    }

    // MARK: - Week 4: 모음 튜닝 & 실전 완성 (180/180/180/210/150)

    private static var week4: [RoutineStep] {
        [
            RoutineStep(
                stepNumber: 1,
                title: "1단계: 웜업",
                subtitle: "노래방 1분 웜업 루틴",
                durationSeconds: 180,
                soundKeyword: "부르르 + 음- (Lip+Hum)",
                analogyEmoji: "🏎️",
                analogyTitle: "F1 피트스탑 비유",
                analogyDescription: "차가운 엔진으로 레이스를 시작하면 목이 금방 지칠 수 있습니다. 웜업은 엔진 예열입니다.",
                actionGuide: [
                    "립트릴 1분, 허밍 1분, 가벼운 사이렌 1분을 순서대로 진행합니다.",
                    "목이 당기는 동작은 즉시 중단하고 하품으로 풉니다.",
                    "몸이 가벼워지면 다음 단계로 넘어갑니다."
                ],
                category: .breathing,
                recommendedToneType: .sirenSlide
            ),
            RoutineStep(
                stepNumber: 2,
                title: "2단계: 접지 유지",
                subtitle: "'멈 멈'으로 후두 안정",
                durationSeconds: 180,
                soundKeyword: "멈 멈 (Mum)",
                analogyEmoji: "🗜️",
                analogyTitle: "성대 클램프 풀기",
                analogyDescription: "'멈'은 입술 저항으로 성대를 스스로 진동하게 두는 발성입니다. 목이 아닌 입술이 일하도록 합니다.",
                actionGuide: [
                    "'멈-멈-멈'을 가이드 톤에 맞춰 부릅니다.",
                    "목 주변에 손을 대고 딱딱해지지 않는지 확인합니다.",
                    "고음에서도 입술 마찰감이 유지되면 접지가 살아있는 것입니다."
                ],
                category: .falsettoSwitch,
                recommendedToneType: .fiveToneScale
            ),
            RoutineStep(
                stepNumber: 3,
                title: "3단계: 모음 튜닝",
                subtitle: "'아'를 '어'로 좁혀 통과하기",
                durationSeconds: 180,
                soundKeyword: "아→어 / 좁은 문 (Vowel)",
                analogyEmoji: "🚪",
                analogyTitle: "좁은 문 통과 비유",
                analogyDescription: "고음에서 입을 크게 벌리면 후두가 치솟습니다. 모음의 문을 살짝 좁혀('아'→'어') 통과시킵니다.",
                actionGuide: [
                    "가이드 톤 위에서 '아'를 점점 올리다 목이 조이는 지점을 찾습니다.",
                    "같은 음을 '어'로 바꿔 좁혀 통과하고, 더 위는 '오'→'우'로 이어 좁힙니다. 좁은 모음이 파사지오를 여는 핵심입니다.",
                    "'사랑해'를 '사렁해'→'소롱해'→'수룽해' 느낌으로 불러, 모음 좁히기 사다리를 연습합니다."
                ],
                category: .jawLarynx,
                recommendedToneType: .fiveToneScale
            ),
            RoutineStep(
                stepNumber: 4,
                title: "4단계: 애창곡 완곡 훈련",
                subtitle: "3단계 조립법으로 곡 완성",
                durationSeconds: 210,
                soundKeyword: "네이 → 모음 → 가사",
                analogyEmoji: "📐",
                analogyTitle: "레고 블록 조립 비유",
                analogyDescription: "어려운 곡을 통째로 하지 말고, 안 되는 소절만 분해해 조립합니다. 한 블록씩 완성이 전체를 바꿉니다.",
                actionGuide: [
                    "애창곡에서 가장 어려운 1소절을 고릅니다.",
                    "네이→모음→가사 순서로 3회씩 조립합니다.",
                    "완성된 소절을 앞뒤 소절과 이어 끊김 없이 부릅니다."
                ],
                category: .practicalTips,
                recommendedToneType: .arpeggio
            ),
            RoutineStep(
                stepNumber: 5,
                title: "5단계: 실전 시뮬레이션",
                subtitle: "녹음하며 한 곡 완창",
                durationSeconds: 150,
                soundKeyword: "완창 + 녹음 (Record)",
                analogyEmoji: "🪞",
                analogyTitle: "거울 보기 비유",
                analogyDescription: "소리는 보이지 않지만 녹음은 보입니다. 녹음으로 오늘의 상태를 객관적으로 확인합니다.",
                actionGuide: [
                    "폰 녹음을 켜고 애창곡을 처음부터 끝까지 부릅니다.",
                    "듣고 가장 아쉬운 소절 하나만 골라 다시 조립 연습합니다.",
                    "마지막에 성대 쿨다운 '부르르' 30초로 마무리합니다."
                ],
                category: .soundDirection,
                recommendedToneType: .sustainedNote
            )
        ]
    }
}
