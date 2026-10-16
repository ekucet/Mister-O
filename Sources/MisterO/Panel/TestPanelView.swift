#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Test paneli: senaryo kataloğu, asistan, akış editörü, Çalıştır/Durdur, adım logu ve ekran öğeleri listesi.
/// Kapalıyken sürüklenebilir bir baloncuğa dönüşür; koşu sırasında uygulama görünür kalır.
struct TestPanelView: View {
    private enum Section: Hashable {
        case scenarios
        case assistant
        case log
        case elements
    }

    @ObservedObject var runner: InAppTestRunner
    @ObservedObject var scenarios: ScenarioStore
    @ObservedObject var panel: PanelModel
    let assistant: FlowAssistant?
    let resolver: ViewResolver

    @AppStorage private var script: String
    @FocusState private var isEditorFocused: Bool
    @State private var section: Section
    @State private var elements: [InspectedElement] = []

    init(runner: InAppTestRunner, scenarios: ScenarioStore, panel: PanelModel, assistant: FlowAssistant?,
         resolver: ViewResolver, initialScript: String) {
        self.runner = runner
        self.scenarios = scenarios
        self.panel = panel
        self.assistant = assistant
        self.resolver = resolver
        // Testçinin son yazdığı akış uygulama yeniden açıldığında geri gelir.
        _script = AppStorage(wrappedValue: initialScript, "MisterO.script")
        _section = State(initialValue: scenarios.isConfigured ? .scenarios : .log)
    }

    private var isBusy: Bool { runner.isRunning || scenarios.isRunning }

    var body: some View {
        ZStack {
            if panel.isExpanded {
                // Asistan adım adım çalışırken uygulama daha net görünsün.
                Color.black.opacity(section == .assistant ? 0.08 : 0.25)
                    .ignoresSafeArea()
                    .onTapGesture(perform: collapse)
                    .transition(.opacity)

                card
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                FloatingBubble(runner: runner, scenarios: scenarios, panel: panel)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: panel.isExpanded)
        .onReceive(runner.$state.removeDuplicates()) { state in
            // Suite sırasında her senaryonun sonunda açılmasın; suite bitince açılır.
            // Asistanın çalıştırdığı tek tek adımlar da paneli Log'a çekmesin.
            guard state.isFinished, scenarios.suite?.isRunning != true, section != .assistant else { return }
            section = .log
            panel.expand()
        }
        .onReceive(scenarios.$suite.map { $0?.isRunning }.removeDuplicates()) { isRunning in
            guard isRunning == false else { return }
            section = .scenarios
            panel.expand()
        }
    }

    // MARK: - Kart

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Picker("Bölüm", selection: sectionBinding) {
                if scenarios.isConfigured {
                    Text("Senaryolar").tag(Section.scenarios)
                }
                if assistant != nil {
                    Text("Asistan").tag(Section.assistant)
                }
                Text("Log").tag(Section.log)
                Text("Öğeler").tag(Section.elements)
            }
            .pickerStyle(.segmented)

            switch section {
            case .scenarios:
                ScenarioListView(store: scenarios, isBusy: isBusy, onRun: run, onRunAll: runSuite,
                                 onEdit: edit, onStop: stop)
                    .frame(minHeight: 160, maxHeight: 440)
            case .assistant:
                if let assistant {
                    AssistantView(assistant: assistant) { flow in
                        script = flow
                        section = .log
                    }
                    .frame(minHeight: 180, maxHeight: 360)
                }
            case .log, .elements:
                editorSection
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    @ViewBuilder
    private var editorSection: some View {
        TextEditor(text: $script)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .frame(height: 150)
            .focused($isEditorFocused)
            .disabled(isBusy)

        controls

        Group {
            switch section {
            case .elements:
                ElementListView(elements: elements, onRefresh: refreshElements, onInsert: appendLine)
            case .log, .scenarios, .assistant:
                RunLogView(runner: runner)
            }
        }
        .frame(minHeight: 110, maxHeight: 230)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "testtube.2")
                .foregroundStyle(.indigo)
            Text("Mister-O")
                .font(.headline)
            StatusBadge(state: runner.state)
            Spacer()
            Button {
                UIPasteboard.general.string = reportText
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(reportText.isEmpty)
            .accessibilityLabel("Raporu kopyala")

            Button(action: collapse) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Paneli küçült")
        }
    }

    private var controls: some View {
        HStack {
            if isBusy {
                Button(role: .destructive, action: stop) {
                    Label("Durdur", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: play) {
                    Label("Çalıştır", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
            Text(progressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Eylemler

    private func play() {
        isEditorFocused = false
        section = .log
        // Akış hatalıysa panel açık kalır, hatalar log'da satır numarasıyla görünür.
        guard runner.validate(script) else { return }
        panel.collapse()
        panel.prepareForRun()
        runner.start(script)
    }

    private func run(_ scenario: Scenario) {
        beginRun()
        scenarios.start(scenario)
    }

    private func runSuite(_ list: [Scenario]) {
        beginRun()
        scenarios.startSuite(list)
    }

    private func beginRun() {
        isEditorFocused = false
        panel.collapse()
        panel.prepareForRun()
    }

    private func stop() {
        scenarios.cancel()
        runner.cancel()
    }

    /// Senaryoyu düzenlemek ya da parça parça denemek için editöre alır.
    private func edit(_ scenario: Scenario) {
        script = scenario.script
        section = .log
    }

    private func collapse() {
        isEditorFocused = false
        panel.collapse()
    }

    private func refreshElements() {
        elements = resolver.inspect()
    }

    private func appendLine(_ line: String) {
        let separator = script.isEmpty || script.hasSuffix("\n") ? "" : "\n"
        script += separator + line
    }

    private var sectionBinding: Binding<Section> {
        Binding {
            section
        } set: { newValue in
            section = newValue
            if newValue == .elements { refreshElements() }
        }
    }

    /// Senaryolar sekmesinde son suite'in, diğerlerinde son koşunun raporu.
    private var reportText: String {
        if section == .scenarios, scenarios.suite != nil { return scenarios.suiteReportText }
        return runner.results.isEmpty && runner.parseIssues.isEmpty ? "" : runner.reportText
    }

    private var progressText: String {
        guard !runner.results.isEmpty else { return "" }
        let passed = runner.results.filter { $0.status == .passed }.count
        let elapsed = runner.elapsed.map { " · \($0.secondsText)" } ?? ""
        return "\(passed)/\(runner.results.count) adım\(elapsed)"
    }
}

/// Koşu durumunu renkli kapsül olarak gösterir (Başarılı / Başarısız / Çalışıyor…).
struct StatusBadge: View {
    let state: RunState

    var body: some View {
        Text(state.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(state.tint)
            .background(state.tint.opacity(0.15), in: Capsule())
    }
}

extension RunState {
    var tint: Color {
        switch self {
        case .idle: .indigo
        case .running: .blue
        case .passed: .green
        case .failed, .invalidScript: .red
        case .cancelled: .orange
        }
    }
}
#endif
