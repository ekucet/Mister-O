#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Panel kapalıyken ekranda kalan, sürüklenebilir baloncuk. Koşu sırasında ilerlemeyi,
/// bitince sonucu renkle gösterir. Dokununca paneli açar.
struct FloatingBubble: View {
    @ObservedObject var runner: InAppTestRunner
    @ObservedObject var panel: PanelModel

    var body: some View {
        // Güvenli alanı yok sayan GeometryReader'ın koordinatları = pencere koordinatları;
        // OverlayWindow da dokunuş bölgesini aynı koordinatlarla hesaplar.
        GeometryReader { proxy in
            bubble
                .position(panel.center(in: proxy.size))
                .onTapGesture(perform: panel.expand)
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(PanelModel.coordinateSpace))
                        .onChanged { panel.bubbleCenter = $0.location }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                panel.bubbleCenter = panel.snapped(value.location, in: proxy.size)
                            }
                        }
                )
        }
        .coordinateSpace(name: PanelModel.coordinateSpace)
        .ignoresSafeArea()
    }

    private var bubble: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
            Circle()
                .strokeBorder(runner.state.tint.opacity(0.35), lineWidth: 4)
            if runner.isRunning {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(runner.state.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                    .animation(.easeInOut, value: progress)
                Text(stepText)
                    .font(.caption2.weight(.bold).monospacedDigit())
            } else {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(runner.state.tint)
            }
        }
        .frame(width: PanelModel.bubbleDiameter, height: PanelModel.bubbleDiameter)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .contentShape(Circle())
        .accessibilityLabel("Mister-O test paneli")
    }

    private var finishedCount: Int {
        runner.results.filter { $0.status != .pending && $0.status != .running }.count
    }

    private var progress: CGFloat {
        runner.results.isEmpty ? 0 : CGFloat(finishedCount) / CGFloat(runner.results.count)
    }

    private var stepText: String {
        "\(min(finishedCount + 1, runner.results.count))/\(runner.results.count)"
    }

    private var icon: String {
        switch runner.state {
        case .passed: "checkmark"
        case .failed, .invalidScript: "xmark"
        case .cancelled: "stop.fill"
        case .idle, .running: "testtube.2"
        }
    }
}
#endif
