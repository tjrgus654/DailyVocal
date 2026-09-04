//
//  PitchLineCanvas.swift
//  DailyVocal
//
//  Canvas renderer for the live pitch trajectory. Log-frequency vertical axis,
//  dashed target line, and segment breaks at unvoiced gaps.
//

import SwiftUI

public struct PitchLineCanvas: View {
    let history: [PitchPoint]
    let targetNoteName: String
    let targetFrequency: Double
    /// Echo mode: all sequence targets; the dashed lines render dimmed except
    /// `activeEchoIndex`, which gets the full-strength single-target style.
    var echoTargetFrequencies: [Double] = []
    var activeEchoIndex: Int = 0

    private let minFrequency = 98.0    // G2
    private let maxFrequency = 587.0   // D5

    public init(
        history: [PitchPoint],
        targetNoteName: String,
        targetFrequency: Double,
        echoTargetFrequencies: [Double] = [],
        activeEchoIndex: Int = 0
    ) {
        self.history = history
        self.targetNoteName = targetNoteName
        self.targetFrequency = targetFrequency
        self.echoTargetFrequencies = echoTargetFrequencies
        self.activeEchoIndex = activeEchoIndex
    }

    public var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            drawOctaveGuides(context: context, size: size)
            drawTargetLine(context: context, size: size)
            drawTrajectory(context: context, size: size)
        }
    }

    private var logSpan: Double { log2(maxFrequency / minFrequency) }

    private func yPosition(for frequency: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(frequency, minFrequency), maxFrequency)
        let normalized = (log2(clamped) - log2(minFrequency)) / logSpan
        return height * (1.0 - CGFloat(normalized))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        for line in 1..<5 {
            let y = size.height * CGFloat(line) / 5
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        }
    }

    /// Faint octave anchor lines (C3/C4/C5) so the vertical axis is readable.
    private func drawOctaveGuides(context: GraphicsContext, size: CGSize) {
        let anchors: [(name: String, midi: Double)] = [("C3", 48), ("C4", 60), ("C5", 72)]
        for anchor in anchors {
            let frequency = VocalAudioEngine.frequency(forMidi: anchor.midi)
            guard frequency > minFrequency, frequency < maxFrequency else { continue }
            let y = yPosition(for: frequency, height: size.height)

            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 1)

            context.draw(
                Text(anchor.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.35)),
                at: CGPoint(x: size.width - 10, y: y - 7)
            )
        }
    }

    private func drawTargetLine(context: GraphicsContext, size: CGSize) {
        guard targetFrequency > minFrequency, targetFrequency < maxFrequency else { return }

        // Echo mode: dimmed guide lines for the not-yet-active targets.
        for (index, frequency) in echoTargetFrequencies.enumerated() where index != activeEchoIndex {
            guard frequency > minFrequency, frequency < maxFrequency else { continue }
            let y = yPosition(for: frequency, height: size.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(Color.brandSecondary.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 5])
            )
        }

        let y = yPosition(for: targetFrequency, height: size.height)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            path,
            with: .color(Color.brandSecondary.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )

        context.draw(
            Text(targetNoteName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.brandSecondary),
            at: CGPoint(x: 8, y: y - 8)
        )
    }

    private func drawTrajectory(context: GraphicsContext, size: CGSize) {
        guard history.count >= 2 else { return }

        let capacity = 120.0
        let stepX = size.width / CGFloat(capacity - 1)
        // Right-aligned: newest point sits at the right edge.
        let startIndex = Swift.max(0, Double(history.count) - capacity)

        var currentPath = Path()
        var previousVoiced = false
        var previousPoint: CGPoint?
        var lastVoiced: (position: CGPoint, isOnPitch: Bool)?

        for (index, entry) in history.enumerated() where Double(index) >= startIndex {
            let x = size.width - CGFloat(Double(history.count - 1 - index)) * stepX
            let y = yPosition(for: max(entry.frequency, minFrequency), height: size.height)
            let point = CGPoint(x: x, y: y)

            if entry.isVoiced && previousVoiced, let previous = previousPoint {
                currentPath.move(to: previous)
                currentPath.addLine(to: point)
            }
            previousPoint = entry.isVoiced ? point : nil
            previousVoiced = entry.isVoiced
            if entry.isVoiced {
                lastVoiced = (point, entry.isOnPitch)
            }
        }

        let gradient = Gradient(colors: [Color.brandSecondary, Color.brandAccent])
        context.stroke(
            currentPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: size.height),
                endPoint: CGPoint(x: size.width, y: 0)
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )

        // Glow dot on the newest voiced point
        if let last = lastVoiced {
            let color: Color = last.isOnPitch ? .vocalSuccess : .brandSecondary
            context.fill(
                Path(ellipseIn: CGRect(x: last.position.x - 6, y: last.position.y - 6, width: 12, height: 12)),
                with: .color(color.opacity(0.35))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: last.position.x - 3.5, y: last.position.y - 3.5, width: 7, height: 7)),
                with: .color(color)
            )
        }
    }
}
