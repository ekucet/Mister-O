#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Katalogdaki senaryolar ve asistandan kaydedilen taslaklar: etikete göre filtre, tek tek ya da toplu
/// çalıştırma, son sonuçlar, taslakları QA ekibiyle paylaşma.
struct ScenarioListView: View {
    @ObservedObject var store: ScenarioStore
    let isBusy: Bool
    /// Asistan kullanılabiliyorsa düşen senaryolarda "Asistanla onar" görünür.
    let canRepair: Bool
    /// Verildiyse düşen senaryolarda "Kayıt aç" görünür.
    let issueReporter: (any IssueReporter)?
    let onRun: (Scenario) -> Void
    let onRunAll: ([Scenario]) -> Void
    let onEdit: (Scenario) -> Void
    let onRepair: (Scenario) -> Void
    let onStop: () -> Void

    @State private var selectedTag: String?
    @State private var expandedID: Scenario.ID?

    private var visible: [Scenario] {
        guard let selectedTag else { return store.allScenarios }
        return store.allScenarios.filter { $0.tags.contains(selectedTag) }
    }

    private var runnable: [Scenario] {
        visible.filter { store.validation(for: $0).isValid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isConfigured {
                catalogStatus
            }
            if !store.drafts.isEmpty {
                draftsBar
            }

            if let suite = store.suite {
                SuiteSummaryView(suite: suite, runs: store.runs)
            }

            if !store.tags.isEmpty {
                tagBar
            }

            runAllRow

            ScrollView {
                LazyVStack(spacing: 6) {
                    if store.allScenarios.isEmpty {
                        Text(L("No scenarios yet. Test a screen in the Assistant tab and save the passing checks as drafts."))
                            .font(.footnote)
                            .foregroundStyle(Color.gray)
                    }
                    ForEach(visible) { scenario in
                        ScenarioRow(
                            scenario: scenario,
                            isDraft: store.isDraft(scenario),
                            validation: store.validation(for: scenario),
                            run: store.runs[scenario.id],
                            isActive: store.activeScenarioID == scenario.id,
                            isExpanded: expandedID == scenario.id,
                            canRun: !isBusy,
                            canRepair: canRepair && !isBusy,
                            issue: { ScenarioIssueActions(store: store, scenario: scenario, reporter: issueReporter) },
                            onToggle: { expandedID = expandedID == scenario.id ? nil : scenario.id },
                            onRun: { onRun(scenario) },
                            onEdit: { onEdit(scenario) },
                            onRepair: { onRepair(scenario) },
                            onDelete: { store.deleteDraft(scenario.id) }
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
                    Text(L("Loading scenarios…")).foregroundStyle(Color.gray)
                case .live(let date):
                    Text("\(L(store.scenarios.count, one: "%ld scenario", other: "%ld scenarios")) · \(store.feed?.name ?? "") · \(date.panelFormatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(Color.gray)
                case .cached(let savedAt, let error):
                    Text(L("Offline · cache from %@", savedAt.panelFormatted(date: .abbreviated, time: .shortened)))
                        .foregroundStyle(.orange)
                    Text(error).foregroundStyle(Color.gray)
                case .failed(let error):
                    Text(L("Couldn't load the catalog: %@", error)).foregroundStyle(.red)
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
            .accessibilityLabel(L("Refresh catalog"))
        }
    }

    private var draftsBar: some View {
        HStack(spacing: 6) {
            Label(L(store.drafts.count, one: "%ld draft (from the assistant)", other: "%ld drafts (from the assistant)"), systemImage: "tray.full")
                .font(.caption)
                .foregroundStyle(.indigo)
            Spacer()
            ShareLink(item: store.draftsCatalogJSON) {
                Label(L("Share drafts"), systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
        }
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagChip(title: L("All"), tag: nil)
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
                    Label(L("Stop"), systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    onRunAll(runnable)
                } label: {
                    Label(selectedTag.map { L("Run #%@ (%ld)", $0, runnable.count) } ?? L("Run all (%ld)", runnable.count),
                          systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(runnable.isEmpty)
            }
            Spacer()
            let invalid = visible.count - runnable.count
            if invalid > 0 {
                Text(L(invalid, one: "%ld invalid scenario is skipped", other: "%ld invalid scenarios are skipped"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Suite sırasında ilerleme, bitince "17/20 passed" özeti.
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
                Text(L("Scenario %ld/%ld · %@", index + 1, total, suite.scenarios[index].name))
                    .font(.caption.weight(.semibold))
                ProgressView(value: Double(index), total: Double(max(total, 1)))
                    .tint(.blue)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: failed == 0 && !suite.wasCancelled ? "checkmark.seal.fill" : "xmark.seal.fill")
                    Text(L("%ld/%ld passed", passed, total))
                    if failed > 0 { Text("· " + L("%ld failed", failed)) }
                    if let elapsed = suite.elapsed { Text("· \(elapsed.compactText)") }
                    if suite.wasCancelled { Text("· " + L("stopped")) }
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

private struct ScenarioRow<Issue: View>: View {
    let scenario: Scenario
    let isDraft: Bool
    let validation: ScenarioStore.Validation
    let run: ScenarioStore.Run?
    let isActive: Bool
    let isExpanded: Bool
    let canRun: Bool
    let canRepair: Bool
    /// Düşen senaryonun hata kaydı ve "Kayıt aç" butonu.
    let issue: () -> Issue
    let onToggle: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void
    let onRepair: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(scenario.name)
                            .font(.subheadline.weight(.semibold))
                        if isDraft {
                            Text(L("Draft"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.indigo)
                                .background(Color.indigo.opacity(0.15), in: Capsule())
                        }
                    }
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
                        Text(L(validation.issues.count, one: "%ld line has errors; it can't run until fixed", other: "%ld lines have errors; it can't run until fixed"))
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
                .accessibilityLabel(L("Run scenario %@", scenario.name))
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
        let steps = validation.isValid ? L(validation.stepCount, one: "%ld step", other: "%ld steps") : L("invalid flow")
        let tags = scenario.tags.map { "#\($0)" }.joined(separator: " ")
        let reset = scenario.resetsApp ? "" : " · " + L("no reset")
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
            if let run, run.state == .failed {
                issue()
            }
            if canRepair, let run, run.state != .passed, run.state != .cancelled {
                Button(action: onRepair) {
                    Label(L("Repair with assistant"), systemImage: "wrench.and.screwdriver")
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Label(L("Open in editor"), systemImage: "square.and.pencil")
                }
                if isDraft {
                    ShareLink(item: ScenarioCatalog.entry(for: scenario)) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(L("Delete"), systemImage: "trash")
                    }
                }
            }
            .font(.caption)
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

/// Düşen senaryo: ekran görüntüsü, takip aracında kayıt aç (varsa), hata kaydını kopyala/paylaş.
private struct ScenarioIssueActions: View {
    @ObservedObject var store: ScenarioStore
    let scenario: Scenario
    let reporter: (any IssueReporter)?
    @State private var copied = false

    var body: some View {
        if let report = store.bugReport(for: scenario, environment: DeviceEnvironment.summary) {
            let run = store.runs[scenario.id]
            VStack(alignment: .leading, spacing: 6) {
                if let data = run?.screenshot, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
                        .accessibilityLabel(L("Screenshot of the issue"))
                }
                if let reporter {
                    if let receipt = run?.issueReceipt {
                        let title = receipt.key.map { L("Ticket opened: %@", $0) } ?? L("Ticket opened")
                        if let url = receipt.url {
                            Link(destination: url) { Label(title, systemImage: "arrow.up.right.square") }
                        } else {
                            Label(title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        if let warning = receipt.warning {
                            Text(warning).foregroundStyle(.orange)
                        }
                    } else {
                        Button {
                            Task { await store.openIssue(for: scenario, environment: DeviceEnvironment.summary, using: reporter) }
                        } label: {
                            if store.openingIssues.contains(scenario.id) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Label(L("Open ticket (%@)", reporter.name), systemImage: "ticket")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(store.openingIssues.contains(scenario.id))
                    }
                    if let error = run?.issueError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        UIPasteboard.general.string = report.text
                        copied = true
                    } label: {
                        Label(copied ? L("Copied") : L("Bug report"), systemImage: copied ? "checkmark" : "ladybug")
                    }
                    ShareLink(item: report.text) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
    }
}

private extension Date {
    /// Panelin dilinde ("14:05", "17 Eki 2026 14:05").
    func panelFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: MisterOLanguage.current.locale))
    }
}
#endif
