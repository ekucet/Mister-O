#if canImport(UIKit)
import MisterOCore
import SwiftUI

/// Ekrandaki adlandırılmış öğeler. Testçi id'leri geliştiriciye sormadan görür; bir satıra
/// dokununca seçtiği komut akışın sonuna eklenir.
struct ElementListView: View {
    let elements: [InspectedElement]
    let onRefresh: () -> Void
    let onInsert: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(elements.count) öğe · dokun ve komut ekle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onRefresh) {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(elements) { element in
                        Menu {
                            let query = FlowParser.quote(element.suggestedQuery)
                            Button("tap: \(query)") { onInsert("tap: \(query)") }
                            Button("assertVisible: \(query)") { onInsert("assertVisible: \(query)") }
                            Button("type: \(query) -> \"\"") { onInsert("type: \(query) -> \"\"") }
                        } label: {
                            ElementRow(element: element)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ElementRow: View {
    let element: InspectedElement

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if let identifier = element.identifier {
                    Text(identifier)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                if let name = element.name, name != element.identifier {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(element.kind)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.primary)
    }
}
#endif
