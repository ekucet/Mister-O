#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Test paneli: akış editörü, Çalıştır/Durdur, adım logu ve ekran öğeleri listesi.
/// Kapalıyken sürüklenebilir bir baloncuğa dönüşür; koşu sırasında uygulama görünür kalır.
struct TestPanelView: View {
    private enum Section: Hashable {
        case log
        case elements
    }

    @ObservedObject var runner: InAppTestRunner
    @ObservedObject var panel: PanelModel
    let resolver: ViewResolver

    @AppStorage private var script: String
    @FocusState private var isEditorFocused: Bool
    @State private var section = Section.log
    @State private var elements: [InspectedElement] = []

    init(runner: InAppTestRunner, panel: PanelModel, resolver: ViewResolver, initialScript: String) {
        self.runner = runner
        self.panel = panel
        self.resolver = resolver
        // Testçinin son yazdığı akış uygulama yeniden açıldığında geri gelir.
        _script = AppStorage(wrappedValue: initialScript, "MisterO.script")
    }

    var body: some View {
        ZStack {
            if panel.isExpanded {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture(perform: collapse)
                    .transition(.opacity)

                card
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                FloatingBubble(runner: runner, panel: panel)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: panel.isExpanded)
        .onReceive(runner.$state.removeDuplicates()) { state in
            if state.isFinished {
                section = .log
                panel.expand()
            }
        }
    }

    // MARK: - Kart

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TextEditor(text: $script)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .frame(height: 150)
                .focused($isEditorFocused)
                .disabled(runner.isRunning)

            controls

            Picker("Bölüm", selection: sectionBinding) {
                Text("Log").tag(Section.log)
                Text("Öğeler").tag(Section.elements)
            }
            .pickerStyle(.segmented)

            Group {
                switch section {
                case .log:
                    RunLogView(runner: runner)
                case .elements:
                    ElementListView(elements: elements, onRefresh: refreshElements, onInsert: appendLine)
                }
            }
            .frame(minHeight: 110, maxHeight: 230)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
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
                UIPasteboard.general.string = runner.reportText
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(runner.results.isEmpty && runner.parseIssues.isEmpty)
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
            if runner.isRunning {
                Button(role: .destructive) {
                    runner.cancel()
                } label: {
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
