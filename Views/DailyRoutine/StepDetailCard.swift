//
//  StepDetailCard.swift
//  DailyVocal
//
//  Current step explanation card: category badge, analogy, expandable action
//  guide, and the live mic waveform. While the guide tone is playing, the
//  waveform visualizes the played notes instead of the microphone — the synth
//  output would otherwise dominate the mic signal (speaker->mic feedback).
//

import SwiftUI

public struct StepDetailCard: View {
    let step: RoutineStep
    @State private var isExpanded = false

    public init(step: RoutineStep) {
        self.step = step
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Text(step.category.emoji)
                    Text(step.category.title)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(step.category.themeColor.opacity(0.2))
                .foregroundColor(step.category.themeColor)
                .clipShape(Capsule())

                Spacer()

                LiveFeedbackIndicator()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.subtitle)
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text("소리 형태:")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(step.soundKeyword)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.brandSecondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Text(step.analogyEmoji)
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceDark)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.analogyTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.brandPrimary)

                    Text(step.analogyDescription)
                        .font(.tipBody)
                        .foregroundColor(.textSecondary)
                        .lineSpacing(4)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(Color.borderGlass)
                        .padding(.vertical, 4)

                    Text("초보자 실천 요령")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    ForEach(Array(step.actionGuide.enumerated()), id: \.offset) { index, guide in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.brandSecondary)
                            Text(guide)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .lineSpacing(3)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.buttonTap()
            }) {
                HStack {
                    Spacer()
                    Text(isExpanded ? "간단히 보기" : "실천 요령 더보기")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.brandSecondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.brandSecondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .glassCard(cornerRadius: DesignLayout.cornerRadiusCard, padding: 18)
    }
}

/// Live waveform, isolated so its ~23 Hz amplitude updates only redraw itself.
/// Guide tones take precedence over mic input while a sequence plays.
private struct LiveFeedbackIndicator: View {
    let audio = VocalAudioEngine.shared
    let sequencer = ScaleSequencer.shared

    var body: some View {
        HStack(spacing: 3) {
            if sequencer.isPlaying {
                // Guided: pulse with each played note instead of mic noise.
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundColor(.brandAccent)
                Text(sequencer.currentNoteName)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.brandAccent)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            } else {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(audio.isVoiceDetected ? Color.brandSecondary : Color.white.opacity(0.2))
                        .frame(width: 3, height: barHeight(for: index))
                }
            }
        }
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.12), value: audio.amplitude)
        .animation(.easeInOut(duration: 0.15), value: sequencer.isPlaying)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Abs of a sine profile so all bars react; mic off -> floor height.
        let profile: [Double] = [0.55, 0.85, 1.0, 0.8, 0.5]
        let level = min(1.0, audio.amplitude / 0.12)
        return max(5, 24 * profile[index] * level)
    }
}
