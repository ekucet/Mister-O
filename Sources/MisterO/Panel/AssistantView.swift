#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Asistan sekmesi.
///
/// - "Bu ekranı test et": asistan kontrolleri planlar ve kendisi koşar.
/// - "Şunu test et": testçinin cümlesi ("alanları doldur, Kaydet'e bas; sonraki ekran açılmalı") tek kontrol olarak koşar.
/// - Rapor: sorunlar hata kaydı ya da takip aracında kayıt olur, geçenler taslak senaryo olur,
///   bilgi bekleyenler testçiye sorulur, onarılan senaryolar güncellenir.
struct AssistantView: View {
    @ObservedObject var assistant: FlowAssistant
    @ObservedObject var scenarios: ScenarioStore
    let issueReporter: (any IssueReporter)?
    /// Asistan uygulamayı sürmeye başlamadan hemen önce (paneli küçült, klavyeyi kapat).
    let onRun: () -> Void
    let onEdit: (String) -> Void

    @State private var request = ""
    @State private var answers: [FlowAssistant.Check.ID: String] = [:]
    @State private var expanded: Set<FlowAssistant.Check.ID> = []
    @State private var copied: FlowAssistant.Check.ID?
    @State private var reportCopied = false

    var body: some View {
        Group {
            if case .unavailable(let reason) = assistant.availability {
                unavailable(reason)
            } else {
                switch assistant.stage {
                case .idle:
                    ScrollView { intro }
                case .planning:
                    busyRow(L("Looking at the screen, planning checks…"))
                case .running, .finished, .failed:
                    report
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Başlangıç

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("The assistant tests this screen by itself: it plans a few checks, runs them and gives a short report. It asks if it needs something."))
                .font(.footnote)
                .foregroundStyle(Color.gray)

            Button {
                start()
            } label: {
                Label(L("Test this screen"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)

            requestField(placeholder: L("or describe one: fill in the fields, tap Save; the next screen should open"),
                         button: L("Test"))

            facts
        }
    }

    /// Asistanın bildiği test bilgileri: uygulamanın verdikleri (kilitli) ve testçinin verdikleri (silinebilir).
    @ViewBuilder
    private var facts: some View {
        if !assistant.knownFacts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("What I know")).font(.caption.weight(.semibold))
                    Spacer()
                    if !assistant.answers.isEmpty {
                        Button(L("Forget all"), role: .destructive) { assistant.forgetAll() }
                            .font(.caption)
                    }
                }
                ForEach(Array(assistant.appFacts.enumerated()), id: \.offset) { _, fact in
                    Label("\(fact.question): \(fact.answer)", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.gray)
                }
                ForEach(Array(assistant.answers.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline) {
                        Text("• \(fact.answer)")
                            .font(.caption)
                            .foregroundStyle(Color.gray)
                        Spacer()
                        Button {
                            assistant.forget(fact)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gray)
                        }
                        .accessibilityLabel(L("Forget"))
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func requestField(placeholder: String, button: String) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(placeholder, text: $request, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
            Button(button) {
                let text = request
                request = ""
                onRun()
                assistant.addCheck(text)
            }
            .buttonStyle(.bordered)
            .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Rapor

    private var report: some View {
        VStack(alignment: .leading, spacing: 8) {
            reportHeader

            if case .failed(let message) = assistant.stage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(assistant.checks) { check in
                        checkCard(check)
                    }
                }
            }

            if !assistant.isWorking {
                footer
            }
        }
    }

    private var reportHeader: some View {
        let summary = assistant.summary
        let done = assistant.checks.filter(\.status.isFinished).count
        return HStack(spacing: 8) {
            if assistant.isWorking {
                ProgressView().controlSize(.small)
                Text(L("Testing · %ld/%ld", done, assistant.checks.count))
            } else {
                Image(systemName: summary.issues > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(summary.issues > 0 ? Color.red : Color.green)
                Text(assistant.summaryText)
            }
            Spacer()
            if assistant.isWorking {
                Button(L("Stop"), role: .destructive) { assistant.stop() }
            } else {
                Button {
                    UIPasteboard.general.string = assistant.reportText
                    reportCopied = true
                } label: {
                    Image(systemName: reportCopied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel(L("Copy report"))
                Button {
                    start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L("Test the screen again"))
                Button {
                    assistant.reset()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Close report"))
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            requestField(placeholder: L("Also try: e.g. a wrong password should show an error"), button: L("Add"))
            let saveable = assistant.checks.filter { isSaveable($0) && $0.repairs == nil && !$0.isSaved }
            if saveable.count > 1 {
                Button {
                    saveable.forEach(saveDraft)
                } label: {
                    Label(L("Save all passed checks as drafts (%ld)", saveable.count), systemImage: "tray.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Kontrol kartı

    private func checkCard(_ check: FlowAssistant.Check) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon(check.status)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                        .font(.subheadline.weight(.semibold))
                    Text(statusText(check))
                        .font(.caption)
                        .foregroundStyle(statusColor(check.status))
                    if let line = check.currentLine {
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.gray)
                    }
                }
                Spacer(minLength: 4)
                if !check.attempts.isEmpty {
                    Image(systemName: expanded.contains(check.id) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.gray)
                }
            }

            if case .needsInput = check.status, !assistant.isWorking {
                HStack(spacing: 6) {
                    TextField(L("Your answer (remembered)"), text: answerBinding(check.id))
                        .textFieldStyle(.roundedBorder)
                        .font(.footnote)
                    Button(L("Send")) {
                        let text = answers[check.id] ?? ""
                        answers[check.id] = nil
                        onRun()
                        assistant.answer(text, for: check.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }

            if expanded.contains(check.id) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(L("Expected")): \(check.plan.expectation)")
                        .font(.caption)
                        .foregroundStyle(Color.gray)
                    ForEach(Array(check.attempts.enumerated()), id: \.offset) { _, attempt in
                        Label {
                            Text(attempt.line + (attempt.note.map { " — \($0)" } ?? ""))
                                .font(.system(.caption2, design: .monospaced))
                        } icon: {
                            Image(systemName: attempt.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(attempt.passed ? Color.green : Color.red)
                        }
                    }
                }
            }

            if check.status.isFinished, !assistant.isWorking {
                actions(for: check)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !check.attempts.isEmpty else { return }
            if expanded.contains(check.id) { expanded.remove(check.id) } else { expanded.insert(check.id) }
        }
    }

    @ViewBuilder
    private func actions(for check: FlowAssistant.Check) -> some View {
        switch check.status {
        case .passed:
            if let original = check.repairs, !check.steps.isEmpty {
                Button {
                    scenarios.saveRepair(of: original, steps: check.steps)
                    assistant.markSaved(check.id)
                } label: {
                    Label(check.isSaved ? L("Scenario updated") : L("Update scenario"),
                          systemImage: check.isSaved ? "checkmark" : "wrench.and.screwdriver")
                }
                .disabled(check.isSaved)
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            } else if isSaveable(check) {
                HStack(spacing: 6) {
                    Button {
                        saveDraft(check)
                    } label: {
                        Label(check.isSaved ? L("Saved") : L("Save as draft"),
                              systemImage: check.isSaved ? "checkmark" : "tray.and.arrow.down")
                    }
                    .disabled(check.isSaved)
                    Button(L("Open in editor")) { onEdit(check.steps.joined(separator: "\n")) }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        case .issue:
            issueActions(for: check)
        case .blocked, .skipped:
            Button(L("Try again")) { rerun(check) }
                .font(.caption)
                .buttonStyle(.bordered)
        case .needsInput, .pending, .running:
            EmptyView()
        }
    }

    /// Sorun: ekran görüntüsü, takip aracında kayıt aç (varsa), hata kaydını kopyala/paylaş, tekrar dene.
    private func issueActions(for check: FlowAssistant.Check) -> some View {
        let report = assistant.bugReport(for: check, environment: DeviceEnvironment.summary)
        return VStack(alignment: .leading, spacing: 6) {
            if let data = check.screenshot, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
                    .accessibilityLabel(L("Screenshot of the issue"))
            }
            if let issueReporter {
                if let receipt = check.issueReceipt {
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
                        Task {
                            await assistant.openIssue(for: check.id, environment: DeviceEnvironment.summary,
                                                      using: issueReporter)
                        }
                    } label: {
                        if assistant.openingIssues.contains(check.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label(L("Open ticket (%@)", issueReporter.name), systemImage: "ticket")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(assistant.openingIssues.contains(check.id))
                }
                if let error = check.issueError {
                    Text(error).foregroundStyle(.red)
                }
            }
            HStack(spacing: 6) {
                Button {
                    UIPasteboard.general.string = report.text
                    copied = check.id
                } label: {
                    Label(copied == check.id ? L("Copied") : L("Bug report"),
                          systemImage: copied == check.id ? "checkmark" : "ladybug")
                }
                ShareLink(item: report.text) {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
                Button(L("Try again")) { rerun(check) }
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
    }

    // MARK: - Yardımcılar

    private func start() {
        request = ""
        expanded = []
        reportCopied = false
        onRun()
        assistant.explore()
    }

    private func rerun(_ check: FlowAssistant.Check) {
        onRun()
        assistant.retry(check.id)
    }

    private func isSaveable(_ check: FlowAssistant.Check) -> Bool {
        if case .passed = check.status { return !check.steps.isEmpty }
        return false
    }

    private func saveDraft(_ check: FlowAssistant.Check) {
        guard let scenario = assistant.scenario(for: check) else { return }
        scenarios.saveDraft(scenario)
        assistant.markSaved(check.id)
    }

    private func answerBinding(_ id: FlowAssistant.Check.ID) -> Binding<String> {
        Binding { answers[id] ?? "" } set: { answers[id] = $0 }
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).lineLimit(2)
            Spacer()
            Button(L("Stop"), role: .destructive) { assistant.stop() }
        }
        .font(.footnote)
    }

    private func statusText(_ check: FlowAssistant.Check) -> String {
        switch check.status {
        case .pending: L("Queued · %@", check.plan.expectation)
        case .running: L("Running · %@", check.plan.expectation)
        case .passed(let message), .issue(let message), .blocked(let message), .skipped(let message): message
        case .needsInput(let question): question
        }
    }

    private func statusColor(_ status: FlowAssistant.Check.Status) -> Color {
        switch status {
        case .passed: .green
        case .issue: .red
        case .needsInput: .indigo
        case .blocked: .orange
        case .pending, .running, .skipped: .gray
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: FlowAssistant.Check.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(Color.gray)
        case .running:
            ProgressView().controlSize(.mini)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .issue:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .needsInput:
            Image(systemName: "questionmark.bubble.fill").foregroundStyle(.indigo)
        case .blocked:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(Color.gray)
        }
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Assistant unavailable"), systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            Text(reason)
                .font(.footnote)
            Text(markdown: L("The assistant uses Apple's on-device model: it needs iOS 26+, a device that supports Apple Intelligence and Apple Intelligence turned on. You can pass your own model with `assistantModel:`."))
                .font(.caption)
                .foregroundStyle(Color.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ViewResolver {
    /// Asistana verilen ekran özeti: Öğeler sekmesindeki listenin aynısı, durumlarıyla.
    func screenElements() -> [ScreenElement] {
        inspect().map {
            ScreenElement(query: $0.suggestedQuery, identifier: $0.identifier, name: $0.name, kind: $0.kind,
                          isEnabled: $0.isEnabled, value: $0.value, inputKind: $0.inputKind)
        }
    }
}

/// iOS 26 öncesinde ya da model verilmediğinde: sekme nedenini gösterir.
struct UnavailableAssistantModel: FlowAssistantModel {
    let reason: String

    var availability: AssistantAvailability { .unavailable(reason) }

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        throw AssistantModelError(reason)
    }
}
#endif
