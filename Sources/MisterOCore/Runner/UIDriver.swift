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
}

extension UIDriver {
    public func isEnabled(_ selector: ElementSelector) -> Bool? { nil }
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

    /// Zaman aşımına kadar yeniden denenebilir mi? (ekran henüz beklenen duruma gelmemiş olabilir)
    public var isRetryable: Bool {
        switch self {
        case .elementNotFound, .elementDisabled, .stillVisible, .elementEnabled: true
        case .notActionable, .notTextInput, .focusFailed: false
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
        }
    }
}
