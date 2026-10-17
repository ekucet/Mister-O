#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Adım adım koşu logu: her satırın durumu (Başarılı/Başarısız/Atlandı), süresi ve hata mesajı.
struct RunLogView: View {
    @ObservedObject var runner: InAppTestRunner

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if runner.results.isEmpty, runner.parseIssues.isEmpty {
                        // Not: material üstündeki ScrollView'da yarı saydam `.secondary` kayboluyor; opak gri kullan.
                        Text(L("Write a flow and tap ▶︎ Run. To see the ids on the screen, open the “Elements” tab."))
                            .font(.footnote)
                            .foregroundStyle(Color.gray)
                    }

                    ForEach(Array(runner.parseIssues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    ForEach(runner.results) { result in
                        StepRow(result: result)
                            .id(result.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onReceive(runner.$results) { results in
                // Koşu sırasında çalışan adımı, bitince ilk başarısız adımı göster.
                let focus = results.first { $0.status == .running }
                    ?? results.first { if case .failed = $0.status { true } else { false } }
                guard let focus else { return }
                withAnimation { proxy.scrollTo(focus.id, anchor: .center) }
            }
        }
    }
}

struct StepRow: View {
    let result: StepResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.step.source)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                if case .failed(let message) = result.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(L("line %ld", result.step.line))
                if let duration = result.duration {
                    Text(duration.secondsText)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.gray)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch result.status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(Color.gray)
        case .running:
            ProgressView().controlSize(.mini)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(Color.gray)
        }
    }
}
#endif
