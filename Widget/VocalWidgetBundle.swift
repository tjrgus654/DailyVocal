//
//  VocalWidgetBundle.swift
//  5VocalMaster
//
//  Widget extension target ONLY (do not add this file to the app target —
//  it declares @main, which would collide with FiveVocalMasterApp).
//  Core/LiveActivity/VocalActivityAttributes.swift must be a member of BOTH
//  the app and the widget target.
//

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct VocalWidgetBundle: WidgetBundle {
    var body: some Widget {
        VocalLiveActivityWidget()
    }
}

struct VocalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VocalActivityAttributes.self) { context in
            lockScreenBanner(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(context.state.currentStepIndex)/5")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                        Text(context.state.stepTitle)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.isPaused ? "일시정지" : "남은 시간")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Group {
                            if context.state.isPaused {
                                // timerInterval cannot freeze; show static text.
                                Text(context.state.pausedRemainingText)
                            } else {
                                Text(
                                    timerInterval: context.state.stepStartTime...context.state.stepEndTime,
                                    countsDown: true
                                )
                            }
                        }
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: 72)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack {
                            Text(context.state.soundKeyword)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(context.state.totalProgress * 100))% 완료")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                Capsule()
                                    .fill(Color.cyan)
                                    .frame(width: geo.size.width * CGFloat(context.state.totalProgress))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    Text("S\(context.state.currentStepIndex)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                Group {
                    if context.state.isPaused {
                        Text(context.state.pausedRemainingText)
                    } else {
                        Text(
                            timerInterval: context.state.stepStartTime...context.state.stepEndTime,
                            countsDown: true
                        )
                    }
                }
                .font(.caption2.monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(.cyan)
                .frame(maxWidth: 42)
            } minimal: {
                Image(systemName: "mic.fill")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
        }
    }

    @ViewBuilder
    private func lockScreenBanner(context: ActivityViewContext<VocalActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.stepTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(context.state.soundKeyword)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Group {
                    if context.state.isPaused {
                        Text(context.state.pausedRemainingText)
                    } else {
                        Text(
                            timerInterval: context.state.stepStartTime...context.state.stepEndTime,
                            countsDown: true
                        )
                    }
                }
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(.cyan)
                Text("\(Int(context.state.totalProgress * 100))% 완료")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(Color(red: 0.05, green: 0.07, blue: 0.18))
    }
}
