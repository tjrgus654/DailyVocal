//
//  GlassCard.swift
//  5VocalMaster
//
//  Frosted glassmorphism modifier + container. The "깔쌈" recipe:
//  ultra-thin material + dark tint, a 0.8pt top sheen stroke (cardSheen),
//  a soft outer shadow, and continuous-corner rounding.
//

import SwiftUI

// MARK: - GlassCard Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var strokeColor: Color
    var strokeWidth: CGFloat

    init(
        cornerRadius: CGFloat = DesignLayout.cornerRadiusCard,
        strokeColor: Color = Color.borderGlass,
        strokeWidth: CGFloat = 1
    ) {
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.surfaceDark.opacity(0.40))
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // Top-edge highlight: catches the light like real glass.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient.cardSheen, lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

// MARK: - View Extension
extension View {
    /// 글래스모피즘 카드 스타일 적용 (padding 포함)
    func glassCard(
        cornerRadius: CGFloat = DesignLayout.cornerRadiusCard,
        padding: CGFloat = 0,
        strokeColor: Color = Color.borderGlass,
        strokeWidth: CGFloat = 1
    ) -> some View {
        self
            .padding(padding)
            .modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeColor: strokeColor, strokeWidth: strokeWidth))
    }
}

// MARK: - Reusable GlassCard Container
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    var padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = DesignLayout.cornerRadiusCard,
        padding: CGFloat = DesignLayout.paddingStandard,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassCard(cornerRadius: cornerRadius)
    }
}
