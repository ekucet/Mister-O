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
}

public enum DriverError: Error, Equatable, Sendable {
    case elementNotFound(ElementSelector)
    case elementDisabled(ElementSelector)
    case notActionable(ElementSelector)
    case notTextInput(ElementSelector)
    case focusFailed(ElementSelector)

    /// Zaman aşımına kadar yeniden denenebilir mi? (öğe henüz gelmemiş ya da henüz aktif değil)
    public var isRetryable: Bool {
        switch self {
        case .elementNotFound, .elementDisabled: true
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
        }
    }
}
