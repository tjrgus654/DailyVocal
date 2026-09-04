//
//  TipDetailView.swift
//  DailyVocal
//
//  Tip detail sheet: diagnosis, analogy, 3-step practice guide, related tips,
//  and the original YouTube shorts link (reference only — the app works
//  standalone via the practice guide).
//

import SwiftUI

public struct TipDetailView: View {
    let tip: VocalTip
    let relatedTips: [VocalTip]
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelectRelated: (VocalTip) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        tip: VocalTip,
        relatedTips: [VocalTip],
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void,
        onSelectRelated: @escaping (VocalTip) -> Void
    ) {
        self.tip = tip
        self.relatedTips = relatedTips
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onSelectRelated = onSelectRelated
    }

    public var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundColor(isFavorite ? .vocalWarning : .textSecondary)
                        }
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    HStack {
                        HStack(spacing: 6) {
                            Text(tip.category.emoji)
                            Text(tip.category.title)
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tip.category.themeColor.opacity(0.2))
                        .foregroundColor(tip.category.themeColor)
                        .clipShape(Capsule())

                        Spacer()

                        if tip.viewCount > 0 {
                            Text("쇼츠 조회수 \(tip.formattedViewCount)")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        } else {
                            // Research-derived tips (no source short) are labeled
                            // instead of showing a meaningless "0회".
                            Label("연구 기반 팁", systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.brandSecondary)
                        }
                    }

                    Text(tip.title)
                        .font(.screenTitle)
                        .foregroundColor(.white)
                        .lineSpacing(4)

                    sectionCard(
                        icon: "sparkles",
                        iconColor: .brandSecondary,
                        title: tip.viewCount > 0 ? "핵심 진단" : "핵심 원리"
                    ) {
                        Text(tip.shortsSummary)
                            .font(.tipBody)
                            .foregroundColor(.white)
                            .lineSpacing(5)
                    }

                    sectionCard(
                        icon: "lightbulb.fill",
                        iconColor: .vocalWarning,
                        title: "초보자 찰떡 비유"
                    ) {
                        Text(tip.beginnerAnalogy)
                            .font(.tipBody)
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(5)
                    }

                    sectionCard(
                        icon: "figure.walk",
                        iconColor: .vocalSuccess,
                        title: "이렇게 연습합니다"
                    ) {
                        Text(tip.howTo)
                            .font(.tipBody)
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(6)
                    }

                    if !relatedTips.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("관련 팁")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(relatedTips) { related in
                                Button(action: { onSelectRelated(related) }) {
                                    HStack(spacing: 12) {
                                        Text(related.category.emoji)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(related.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text(related.keyActionWord)
                                                .font(.caption2)
                                                .foregroundColor(.brandSecondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(12)
                                    .background(Color.surfaceDark.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .glassCard(cornerRadius: 16, padding: 16)
                    }

                    if let url = tip.youtubeURL {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("출처 영상 보기")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .glassCard(cornerRadius: 14, padding: 16)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func sectionCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            content()
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }
}
