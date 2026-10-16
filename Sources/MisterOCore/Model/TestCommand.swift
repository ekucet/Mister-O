/// Ekrandaki bir öğeyi tarif eden sorgu.
///
/// Sürücü sorguyu sırasıyla `accessibilityIdentifier`, `accessibilityLabel`, görünen metin
/// ve son olarak büyük/küçük harf duyarsız metinle eşleştirir.
public struct ElementSelector: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let query: String

    public init(_ query: String) {
        self.query = query
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { "\"\(query)\"" }
}

/// Akıştaki tek bir satırın anlamı.
public enum TestCommand: Equatable, Sendable {
    /// `tap: "login_button"`
    case tap(ElementSelector)
    /// `type: "email_field" -> "test@example.com"`
    case typeText(ElementSelector, text: String)
    /// `wait: 1.5`
    case wait(seconds: Double)
    /// `assertVisible: "welcome_label"`
    case assertVisible(ElementSelector)
    /// `assertNotVisible: "error_label"`
    case assertNotVisible(ElementSelector)
    /// `assertEnabled: "login_button"`
    case assertEnabled(ElementSelector)
    /// `assertDisabled: "login_button"`
    case assertDisabled(ElementSelector)
}

/// Parser çıktısı: komut + testçiye geri gösterilecek kaynak satır bilgisi.
public struct TestStep: Identifiable, Equatable, Sendable {
    /// Akış içindeki 0 tabanlı sıra.
    public let id: Int
    /// Metin editöründeki 1 tabanlı satır numarası.
    public let line: Int
    /// Testçinin yazdığı satır (boşlukları kırpılmış).
    public let source: String
    public let command: TestCommand

    public init(id: Int, line: Int, source: String, command: TestCommand) {
        self.id = id
        self.line = line
        self.source = source
        self.command = command
    }
}
