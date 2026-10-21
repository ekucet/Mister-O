import Foundation

/// Runner'ın ekranla konuştuğu tek kapı.
///
/// Uygulamadaki gerçek sürücü `MisterO` modülündeki `UIKitDriver`'dır. Metotlar senkron ve
/// "anlık"tır: öğe o an ekranda yoksa `DriverError.elementNotFound` fırlatırlar; bekleme ve
/// yeniden deneme mantığı runner'dadır. Bu sayede runner sahte bir sürücüyle test edilebilir.
@MainActor
public protocol UIDriver {
    func tap(_ selector: ElementSelector) throws
    func typeText(_ text: String, into selector: ElementSelector) throws
    func isVisible(_ selector: ElementSelector) -> Bool
    /// Öğe aktif mi? Ekranda yoksa `nil`.
    func isEnabled(_ selector: ElementSelector) -> Bool?
    /// Öğenin okunabilen metinleri (değer, etiket, görünen metin). Ekranda yoksa `nil`.
    func texts(of selector: ElementSelector) -> [String]?
    /// `scroll` komutu: `selector` verilirse o öğenin bulunduğu kaydırılabilir alanı, verilmezse ekranın
    /// ana listesini bir sayfa kaydırır. Alan zaten sondaysa hata değildir.
    func scroll(_ direction: ScrollDirection, in selector: ElementSelector?) throws
    /// Aranan öğe ekranda yokken ana listeyi bir adım kaydırır. Kaydıracak yer kalmadıysa `false`.
    func scrollToFind(_ search: inout ScrollSearch) -> Bool
    /// Navigasyonda bir geri gider ya da en üstteki sayfayı kapatır.
    func goBack() throws
}

extension UIDriver {
    public func isEnabled(_ selector: ElementSelector) -> Bool? { nil }
    public func texts(of selector: ElementSelector) -> [String]? { nil }
    public func scroll(_ direction: ScrollDirection, in selector: ElementSelector?) throws {
        throw DriverError.noScrollableArea(selector)
    }
    public func scrollToFind(_ search: inout ScrollSearch) -> Bool { false }
    public func goBack() throws { throw DriverError.nothingToGoBack }
}

/// Ekranda olmayan bir öğeyi ararken listenin nereye kadar kaydırıldığı. Önce aşağı, sona gelince yukarı.
public struct ScrollSearch: Equatable, Sendable {
    /// Bir arama en fazla bu kadar sayfa kaydırır.
    public static let maxSteps = 40

    public var direction: ScrollDirection = .down
    /// Bir uca varıp yön değiştirdi; öbür uca da varınca arama biter.
    public var hasTurned = false
    public var steps = 0

    public init() {}
}

public enum DriverError: Error, Equatable, Sendable {
    case elementNotFound(ElementSelector)
    case elementDisabled(ElementSelector)
    case notActionable(ElementSelector)
    case notTextInput(ElementSelector)
    case focusFailed(ElementSelector)
    /// `assertNotVisible`: öğe hâlâ ekranda.
    case stillVisible(ElementSelector)
    /// `assertDisabled`: öğe pasif olmalıydı ama aktif.
    case elementEnabled(ElementSelector)
    /// `assertText`: öğe ekranda ama metni beklenen metni içermiyor.
    case textMismatch(ElementSelector, expected: String, actual: String)
    /// `scroll`: kaydırılabilir bir alan yok.
    case noScrollableArea(ElementSelector?)
    /// `back`: geri gidilecek ya da kapatılacak bir sayfa yok.
    case nothingToGoBack

    /// Zaman aşımına kadar yeniden denenebilir mi? (ekran henüz beklenen duruma gelmemiş olabilir)
    public var isRetryable: Bool {
        switch self {
        case .elementNotFound, .elementDisabled, .stillVisible, .elementEnabled, .textMismatch, .noScrollableArea: true
        case .notActionable, .notTextInput, .focusFailed, .nothingToGoBack: false
        }
    }
}

extension DriverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let selector): L("Not on screen: %@", "\(selector)")
        case .elementDisabled(let selector): L("Element is disabled: %@", "\(selector)")
        case .notActionable(let selector): L("Element found but it can't be tapped: %@", "\(selector)")
        case .notTextInput(let selector): L("Element isn't a text field: %@", "\(selector)")
        case .focusFailed(let selector): L("Couldn't focus the text field: %@", "\(selector)")
        case .stillVisible(let selector): L("Still on screen: %@", "\(selector)")
        case .elementEnabled(let selector): L("Element is enabled, it should be disabled: %@", "\(selector)")
        case .textMismatch(let selector, let expected, let actual):
            L("%@ shows \"%@\", expected \"%@\"", "\(selector)", actual, expected)
        case .noScrollableArea(let selector):
            selector.map { L("No scrollable area around %@", "\($0)") } ?? L("No scrollable area on screen")
        case .nothingToGoBack: L("Nothing to go back from: no previous screen or open sheet")
        }
    }
}
