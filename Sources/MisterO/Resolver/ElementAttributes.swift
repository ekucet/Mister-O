#if canImport(UIKit)
import UIKit

/// Sorgunun ne kadar güçlü eşleştiği. Büyük olan kazanır.
public enum MatchKind: Int, Comparable, Sendable {
    case caseInsensitiveText
    case text
    case label
    case identifier

    public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Bir view'dan ya da erişilebilirlik düğümünden okunan, eşleştirmede kullanılan değerler.
@MainActor
struct ElementAttributes {
    let identifier: String?
    let label: String?
    /// Ekranda görünen metinler (buton başlığı, label metni, text field içeriği/placeholder…).
    let texts: [String]

    init(_ object: NSObject) {
        identifier = Self.accessibilityIdentifier(of: object)?.nonEmpty
        label = object.accessibilityLabel?.nonEmpty
        texts = (object as? UIView).map(Self.displayedTexts(of:)) ?? []
    }

    /// Kullanıcıya gösterilecek en iyi ad (inspector ve sorgu önerisi için).
    var displayName: String? { label ?? texts.first }

    func match(_ query: String) -> MatchKind? {
        if identifier == query { return .identifier }

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if label?.trimmed == query { return .label }
        if texts.contains(where: { $0.trimmed == query }) { return .text }

        let candidates = [label].compactMap { $0 } + texts
        if candidates.contains(where: { $0.trimmed.localizedCaseInsensitiveCompare(query) == .orderedSame }) {
            return .caseInsensitiveText
        }
        return nil
    }

    // MARK: - Okuma

    private static func accessibilityIdentifier(of object: NSObject) -> String? {
        if let view = object as? UIView { return view.accessibilityIdentifier }
        if let identifiable = object as? UIAccessibilityIdentification { return identifiable.accessibilityIdentifier }
        // SwiftUI düğümleri protokole resmi olarak uymadan da cevap verebiliyor.
        let selector = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    private static func displayedTexts(of view: UIView) -> [String] {
        let texts: [String?] = switch view {
        case let button as UIButton:
            [button.currentTitle, button.configuration?.title, button.currentAttributedTitle?.string]
        case let label as UILabel:
            [label.text]
        case let field as UITextField:
            [field.text, field.placeholder]
        case let textView as UITextView:
            [textView.text]
        default:
            []
        }
        return texts.compactMap { $0?.nonEmpty }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
