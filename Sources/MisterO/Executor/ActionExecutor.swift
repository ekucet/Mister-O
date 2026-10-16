#if canImport(UIKit)
import MisterOCore
import UIKit

/// Bulunan öğe üzerinde eylemi programatik olarak gerçekleştirir. Sentetik dokunuş (private API)
/// üretmez; yalnızca UIKit'in açık API'lerini kullanır:
///
/// - `UIControl` → `sendActions(for:)` (`UISwitch` için değer değişimi)
/// - `UITableViewCell` / `UICollectionViewCell` → seçim + delegate `didSelect`
/// - SwiftUI ve diğer erişilebilirlik düğümleri → `accessibilityActivate()`
/// - Metin → `becomeFirstResponder()` + `UIKeyInput.insertText(_:)`; böylece delegate'ler,
///   `.editingChanged` ve SwiftUI binding'leri gerçek klavye girişindeki gibi güncellenir.
@MainActor
public struct ActionExecutor {
    /// `type` yazmadan önce alanın mevcut içeriğini siler.
    public var clearsTextBeforeTyping: Bool

    public init(clearsTextBeforeTyping: Bool = true) {
        self.clearsTextBeforeTyping = clearsTextBeforeTyping
    }

    // MARK: - Tap

    public func tap(_ element: UIElement) throws {
        let anchor: UIView
        switch element.backing {
        case .view(let view):
            if try activateNearestActionable(from: view, element) { return }
            anchor = view
        case .accessibilityNode(let node, let host):
            // `.disabled(true)` olan SwiftUI butonu: form geçerli olana kadar runner yeniden dener.
            if node.accessibilityTraits.contains(.notEnabled) {
                throw DriverError.elementDisabled(element.selector)
            }
            // SwiftUI Button / NavigationLink / Toggle vb. varsayılan eylemi.
            if node.accessibilityActivate() { return }
            anchor = host
        }

        // Yedek: öğenin merkezindeki gerçek view'ı bul. Yalnızca öğenin kendi alt ağacındaysa kabul
        // edilir; aksi hâlde üstte duran başka bir ekranın (sheet, alert) butonuna basılabilirdi.
        if let hit = element.window.hitTest(element.center, with: nil), hit.isDescendant(of: anchor),
           try activateNearestActionable(from: hit, element) {
            return
        }
        // Son çare: view'ın kendi `accessibilityActivate()` override'ı.
        if case .view(let view) = element.backing, view.accessibilityActivate() { return }

        throw DriverError.notActionable(element.selector)
    }

    private func activateNearestActionable(from start: UIView, _ element: UIElement) throws -> Bool {
        for view in sequence(first: start, next: { $0.superview }) where !(view is UIWindow) {
            if try trigger(view, element) { return true }
        }
        return false
    }

    private func trigger(_ view: UIView, _ element: UIElement) throws -> Bool {
        switch view {
        case is UITextField, is UITextView:
            element.window.makeKey()
            return view.becomeFirstResponder()

        case let toggle as UISwitch:
            guard toggle.isEnabled else { throw DriverError.elementDisabled(element.selector) }
            toggle.setOn(!toggle.isOn, animated: true)
            toggle.sendActions(for: .valueChanged)
            return true

        case let control as UIControl:
            guard control.isEnabled else { throw DriverError.elementDisabled(element.selector) }
            control.sendActions(for: .touchUpInside)
            // UIButton .touchUpInside'tan .primaryActionTriggered'ı (UIAction / primaryAction) kendisi
            // üretir; ikisini birden göndermek çift tetikler. Diğer kontrollerde ayrıca gönder.
            if !(control is UIButton), control.allControlEvents.contains(.primaryActionTriggered) {
                control.sendActions(for: .primaryActionTriggered)
            }
            return true

        case let cell as UITableViewCell:
            guard let table = cell.firstAncestor(ofType: UITableView.self),
                  let indexPath = table.indexPath(for: cell) else { return false }
            table.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            table.delegate?.tableView?(table, didSelectRowAt: indexPath)
            return true

        case let cell as UICollectionViewCell:
            guard let collection = cell.firstAncestor(ofType: UICollectionView.self),
                  let indexPath = collection.indexPath(for: cell) else { return false }
            collection.selectItem(at: indexPath, animated: true, scrollPosition: [])
            collection.delegate?.collectionView?(collection, didSelectItemAt: indexPath)
            return true

        default:
            return false
        }
    }

    // MARK: - Type

    public func type(_ text: String, into element: UIElement) throws {
        guard let input = textInput(for: element) else {
            throw DriverError.notTextInput(element.selector)
        }
        if let field = input as? UITextField, !field.isEnabled {
            throw DriverError.elementDisabled(element.selector)
        }
        if let textView = input as? UITextView, !textView.isEditable {
            throw DriverError.notTextInput(element.selector)
        }

        // Klavye odağı test panelinin penceresinde kalmış olabilir.
        element.window.makeKey()
        guard input.isFirstResponder || input.becomeFirstResponder() else {
            throw DriverError.focusFailed(element.selector)
        }

        if clearsTextBeforeTyping,
           let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument), !all.isEmpty {
            input.selectedTextRange = all
            input.deleteBackward()
        }
        input.insertText(text)
    }

    private func textInput(for element: UIElement) -> (UIView & UITextInput)? {
        switch element.backing {
        case .view(let view):
            // Eşleşen view'ın kendisi, alt ağacı (ör. id'li container) ya da yakın atası (ör. placeholder label).
            return Self.firstTextInput(in: view)
                ?? sequence(first: view, next: { $0.superview }).prefix(4).lazy.compactMap(Self.asTextInput).first
        case .accessibilityNode(_, let host):
            // SwiftUI TextField/SecureField/TextEditor alttaki UITextField/UITextView'dır: düğümün
            // merkezine denk gelen en derindeki metin alanını seç.
            return Self.lastTextInput(in: host, containing: element.center, window: element.window)
        }
    }

    private static func asTextInput(_ view: UIView) -> (UIView & UITextInput)? {
        guard view is UITextField || view is UITextView else { return nil }
        return view as? (UIView & UITextInput)
    }

    private static func firstTextInput(in root: UIView) -> (UIView & UITextInput)? {
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let input = asTextInput(view), !view.isHidden { return input }
            queue += view.subviews
        }
        return nil
    }

    private static func lastTextInput(in root: UIView, containing point: CGPoint, window: UIWindow) -> (UIView & UITextInput)? {
        var match: (UIView & UITextInput)?
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if !view.isHidden, let input = asTextInput(view), view.convert(view.bounds, to: window).contains(point) {
                match = input
            }
            queue += view.subviews
        }
        return match
    }
}
#endif
