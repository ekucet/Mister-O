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
    /// UIKit `isEnabled` ya da SwiftUI `.disabled` (erişilebilirlikte `notEnabled`).
    let isEnabled: Bool
    /// Metin alanının içeriği; gizli alanlarda yalnızca dolu olduğu bilgisi.
    let value: String?
    /// Metin alanının beklediği veri ("email", "phone", "password"…); asistan doğru değeri seçsin diye.
    let inputKind: String?

    init(_ object: NSObject) {
        identifier = Self.accessibilityIdentifier(of: object)?.nonEmpty
        label = object.accessibilityLabel?.nonEmpty
        if let view = object as? UIView {
            texts = Self.displayedTexts(of: view)
            isEnabled = Self.isEnabled(view)
            value = Self.inputValue(of: view)
            inputKind = Self.inputKind(of: view)
        } else {
            texts = []
            isEnabled = !object.accessibilityTraits.contains(.notEnabled)
            value = object.accessibilityValue?.nonEmpty
            inputKind = object.accessibilityTraits.contains(.searchField) ? "text" : nil
        }
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

    private static func isEnabled(_ view: UIView) -> Bool {
        if let control = view.firstAncestor(ofType: UIControl.self) { return control.isEnabled }
        if let textView = view as? UITextView { return textView.isEditable }
        return !view.accessibilityTraits.contains(.notEnabled)
    }

    private static func inputKind(of view: UIView) -> String? {
        if view is UITextView { return "text" }
        guard let field = view as? UITextField else { return nil }
        if field.isSecureTextEntry { return "password" }
        if let type = field.textContentType {
            switch type {
            case .emailAddress: return "email"
            case .password, .newPassword: return "password"
            case .oneTimeCode: return "code"
            case .telephoneNumber: return "phone"
            case .name, .givenName, .familyName, .nickname: return "name"
            case .URL: return "url"
            case .username: return "username"
            case .postalCode: return "postal code"
            case .fullStreetAddress, .streetAddressLine1, .addressCity: return "address"
            default: break
            }
        }
        switch field.keyboardType {
        case .emailAddress: return "email"
        case .phonePad, .namePhonePad: return "phone"
        case .numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation: return "number"
        case .URL: return "url"
        default: return "text"
        }
    }

    private static func inputValue(of view: UIView) -> String? {
        switch view {
        case let field as UITextField:
            guard let text = field.text, !text.isEmpty else { return nil }
            // Modele giden değer; istemler İngilizce.
            return field.isSecureTextEntry ? "(hidden, filled)" : text
        case let textView as UITextView:
            return textView.text?.nonEmpty
        default:
            return nil
        }
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
