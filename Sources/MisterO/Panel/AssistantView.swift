#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Asistan sekmesi: testçi hedefi yazar, asistan ekrana bakıp adım önerir ya da soru sorar.
/// Çıkan doğrulanmış akış editöre alınabilir ya da katalog kaydı olarak kopyalanabilir.
struct AssistantView: View {
    @ObservedObject var assistant: FlowAssistant
    let onEdit: (String) -> Void

    @State private var input = ""
    @State private var isNaming = false
    @State private var entryName = ""
    @State private var entryTags = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .unavailable(let reason) = assistant.availability {
                unavailable(reason)
            } else {
                transcript
                controls
                if !assistant.steps.isEmpty, !assistant.isWorking {
                    exportRow
                }
            }
        }
        .alert("Katalog kaydı", isPresented: $isNaming) {
            TextField("Senaryo adı", text: $entryName)
            TextField("Etiketler (virgülle)", text: $entryTags)
            Button("Kopyala", action: copyEntry)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("JSON kaydı panoya kopyalanır; kataloğun scenarios dizisine yapıştırın.")
        }
    }

    // MARK: - Konuşma

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if assistant.messages.isEmpty {
                        Text("Ne test etmek istediğinizi yazın. Asistan ekrana bakıp bir sonraki adımı önerir, eksik bilgiyi sorar; her adım çalıştırılarak doğrulanır.")
                            .font(.footnote)
                            .foregroundStyle(Color.gray)
                    }
                    ForEach(assistant.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onReceive(assistant.$messages) { messages in
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: - Duruma göre kontroller

    @ViewBuilder
    private var controls: some View {
        switch assistant.phase {
        case .idle, .finished, .failed:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    inputField(assistant.steps.isEmpty
                               ? "Ne test edilsin? ör. Yanlış şifreyle girişte hata çıkmalı"
                               : "Devam ettir ya da yeni bir hedef yaz")
                    if !assistant.steps.isEmpty {
                        Button("Devam") { submit { assistant.continueWith($0) } }
                            .buttonStyle(.bordered)
                    }
                    Button(assistant.steps.isEmpty ? "Başlat" : "Yeni") { submit { assistant.start(goal: $0) } }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }
                Toggle("Otomatik ilerle (her adımda onay sorma)", isOn: $assistant.autoAdvance)
                    .font(.caption)
                    .tint(.indigo)
            }

        case .thinking:
            busyRow(Text("Düşünüyor…"))

        case .running(let line):
            busyRow(Text(line).font(.system(.caption, design: .monospaced)))

        case .awaitingApproval(let line, _):
            VStack(alignment: .leading, spacing: 6) {
                Text(line)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 6) {
                    Button {
                        assistant.approve()
                    } label: {
                        Label("Çalıştır", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    Button("Başka öner") { submit(allowEmpty: true) { assistant.reject($0) } }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Durdur", role: .destructive) { assistant.stop() }
                }
                inputField("İsteğe bağlı: neden bu adım olmasın?")
            }

        case .awaitingAnswer:
            HStack(alignment: .bottom, spacing: 6) {
                inputField("Cevabınız")
                Button("Gönder") { submit { assistant.answer($0) } }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
        }
    }

    private func inputField(_ placeholder: String) -> some View {
        TextField(placeholder, text: $input, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .font(.footnote)
    }

    private func busyRow(_ label: Text) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            label.lineLimit(1)
            Spacer()
            Button("Durdur", role: .destructive) { assistant.stop() }
        }
        .font(.footnote)
    }

    private var exportRow: some View {
        HStack(spacing: 6) {
            Text("\(assistant.steps.count) doğrulanmış adım")
                .font(.caption)
                .foregroundStyle(Color.gray)
            Spacer()
            Button("Editöre al") { onEdit(assistant.script) }
                .buttonStyle(.bordered)
            Button {
                entryName = String(assistant.goal.split(separator: "\n").first?.prefix(48) ?? "")
                isNaming = true
            } label: {
                Label(copied ? "Kopyalandı" : "Katalog kaydı", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Asistan kullanılamıyor", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            Text(reason)
                .font(.footnote)
            Text("Asistan Apple'ın cihaz içi modelini kullanır: iOS 26+, Apple Intelligence destekleyen bir cihaz ve açık Apple Intelligence gerekir.")
                .font(.caption)
                .foregroundStyle(Color.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Eylemler

    private func submit(allowEmpty: Bool = false, _ action: (String) -> Void) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowEmpty || !text.isEmpty else { return }
        copied = false
        action(text)
        input = ""
    }

    private func copyEntry() {
        let tags = entryTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !entryName.trimmingCharacters(in: .whitespaces).isEmpty,
              let json = try? assistant.catalogEntry(name: entryName, tags: tags) else { return }
        UIPasteboard.general.string = json
        copied = true
    }
}

private struct MessageRow: View {
    let message: FlowAssistant.Message

    var body: some View {
        switch message.role {
        case .tester:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.footnote)
                    .foregroundStyle(Color.white)
                    .padding(8)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.indigo)
                Text(message.text)
                    .font(.footnote)
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 40)
            }
        case .step(let passed):
            Label {
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
            } icon: {
                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(passed ? Color.green : Color.red)
            }
        case .note:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(Color.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

extension ViewResolver {
    /// Asistana verilen ekran özeti: Öğeler sekmesindeki listenin aynısı.
    func screenElements() -> [ScreenElement] {
        inspect().map {
            ScreenElement(query: $0.suggestedQuery, identifier: $0.identifier, name: $0.name, kind: $0.kind)
        }
    }
}
#endif
