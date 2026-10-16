#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Katalogdaki senaryolar: etikete göre filtre, tek tek ya da toplu çalıştırma, son sonuçlar.
struct ScenarioListView: View {
    @ObservedObject var store: ScenarioStore
    let isBusy: Bool
    let onRun: (Scenario) -> Void
    let onRunAll: ([Scenario]) -> Void
    let onEdit: (Scenario) -> Void
    let onStop: () -> Void

    @State private var selectedTag: String?
    @State private var expandedID: Scenario.ID?

    private var visible: [Scenario] {
        guard let selectedTag else { return store.scenarios }
        return store.scenarios.filter { $0.tags.contains(selectedTag) }
    }

    private var runnable: [Scenario] {
        visible.filter { store.validation(for: $0).isValid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            catalogStatus

            if let suite = store.suite {
                SuiteSummaryView(suite: suite, runs: store.runs)
            }

            if !store.tags.isEmpty {
                tagBar
            }

            runAllRow

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visible) { scenario in
                        ScenarioRow(
                            scenario: scenario,
                            validation: store.validation(for: scenario),
                            run: store.runs[scenario.id],
                            isActive: store.activeScenarioID == scenario.id,
                            isExpanded: expandedID == scenario.id,
                            canRun: !isBusy,
                            onToggle: { expandedID = expandedID == scenario.id ? nil : scenario.id },
                            onRun: { onRun(scenario) },
                            onEdit: { onEdit(scenario) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Parçalar

    private var catalogStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                switch store.status {
                case .idle, .loading:
                    Text("Senaryolar yükleniyor…").foregroundStyle(Color.gray)
                case .live(let date):
                    Text("\(store.scenarios.count) senaryo · \(store.feed?.name ?? "") · \(date.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(Color.gray)
                case .cached(let savedAt, let error):
                    Text("Çevrimdışı · \(savedAt.formatted(date: .abbreviated, time: .shortened)) önbelleği")
                        .foregroundStyle(.orange)
                    Text(error).foregroundStyle(Color.gray)
                case .failed(let error):
                    Text("Katalog yüklenemedi: \(error)").foregroundStyle(.red)
                }
            }
            .font(.caption)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.status == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.status == .loading || isBusy)
            .accessibilityLabel("Kataloğu yenile")
        }
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagChip(title: "Tümü", tag: nil)
                ForEach(store.tags, id: \.self) { tag in
                    tagChip(title: "#\(tag)", tag: tag)
                }
            }
        }
    }

    private func tagChip(title: String, tag: String?) -> some View {
        let isSelected = selectedTag == tag
        return Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.indigo : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .onTapGesture { selectedTag = tag }
    }

    private var runAllRow: some View {
        HStack {
            if isBusy {
                Button(role: .destructive, action: onStop) {
                    Label("Durdur", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    onRunAll(runnable)
                } label: {
                    Label(selectedTag.map { "#\($0) çalıştır (\(runnable.count))" } ?? "Tümünü çalıştır (\(runnable.count))",
                          systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(runnable.isEmpty)
            }
            Spacer()
            let invalid = visible.count - runnable.count
            if invalid > 0 {
                Text("\(invalid) hatalı senaryo atlanır")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Suite sırasında ilerleme, bitince "17/20 başarılı" özeti.
private struct SuiteSummaryView: View {
    let suite: ScenarioStore.Suite
    let runs: [Scenario.ID: ScenarioStore.Run]

    var body: some View {
        let total = suite.scenarios.count
        let passed = suite.scenarioIDs.filter { runs[$0]?.state == .passed }.count
        let failed = suite.scenarioIDs.filter { runs[$0].map { $0.state != .passed && $0.state != .cancelled } ?? false }.count

        VStack(alignment: .leading, spacing: 4) {
            if suite.isRunning {
                let index = suite.currentIndex ?? 0
                Text("Senaryo \(index + 1)/\(total) · \(suite.scenarios[index].name)")
                    .font(.caption.weight(.semibold))
                ProgressView(value: Double(index), total: Double(max(total, 1)))
                    .tint(.blue)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: failed == 0 && !suite.wasCancelled ? "checkmark.seal.fill" : "xmark.seal.fill")
                    Text("\(passed)/\(total) başarılı")
                    if failed > 0 { Text("· \(failed) başarısız") }
                    if let elapsed = suite.elapsed { Text("· \(elapsed.compactText)") }
                    if suite.wasCancelled { Text("· durduruldu") }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(failed == 0 && !suite.wasCancelled ? Color.green : Color.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ScenarioRow: View {
    let scenario: Scenario
    let validation: ScenarioStore.Validation
    let run: ScenarioStore.Run?
    let isActive: Bool
    let isExpanded: Bool
    let canRun: Bool
    let onToggle: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.name)
                        .font(.subheadline.weight(.semibold))
                    if let summary = scenario.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Color.gray)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(Color.gray)
                    if !validation.isValid {
                        Text("\(validation.issues.count) satır hatalı; düzeltilene kadar çalıştırılamaz")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if let run, run.state != .passed, let failure = run.failureMessage {
                        Text(failure)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                }
                Spacer(minLength: 4)
                Button(action: onRun) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canRun && validation.isValid ? Color.indigo : Color.gray)
                .disabled(!canRun || !validation.isValid)
                .accessibilityLabel("\(scenario.name) senaryosunu çalıştır")
            }

            if isExpanded {
                details
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private var meta: String {
        let steps = validation.isValid ? "\(validation.stepCount) adım" : "akış hatalı"
        let tags = scenario.tags.map { "#\($0)" }.joined(separator: " ")
        let reset = scenario.resetsApp ? "" : " · reset yok"
        return [steps, tags].filter { !$0.isEmpty }.joined(separator: " · ") + reset
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(validation.issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let run {
                ForEach(run.steps) { result in
                    StepRow(result: result)
                }
            }
            Button(action: onEdit) {
                Label("Editöre al", systemImage: "square.and.pencil")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.leading, 26)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isActive {
            ProgressView().controlSize(.mini)
        } else {
            switch run?.state {
            case .passed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed, .invalidScript:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle").foregroundStyle(Color.gray)
            default:
                Image(systemName: "circle").foregroundStyle(Color.gray)
            }
        }
    }
}
#endif
