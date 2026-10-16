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
        case .elementNotFound(let selector): "Ekranda bulunamadı: \(selector)"
        case .elementDisabled(let selector): "Öğe pasif (disabled): \(selector)"
        case .notActionable(let selector): "Öğe bulundu ama tıklanabilir değil: \(selector)"
        case .notTextInput(let selector): "Öğe bir metin alanı değil: \(selector)"
        case .focusFailed(let selector): "Metin alanına odaklanılamadı: \(selector)"
        case .stillVisible(let selector): "Hâlâ ekranda: \(selector)"
        case .elementEnabled(let selector): "Öğe aktif, pasif olması bekleniyordu: \(selector)"
        }
    }
}
