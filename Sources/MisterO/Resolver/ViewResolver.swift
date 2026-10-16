#if canImport(UIKit)
import MisterOCore
import UIKit

/// Ekranda bulunan ve bir sorguyla eşleşen öğe.
@MainActor
public struct UIElement {
    public enum Backing {
        case view(UIView)
        /// UIView olmayan erişilebilirlik öğesi (SwiftUI düğümleri, `UIAccessibilityElement`…).
        /// `host`, düğümü yayınlayan view'dır (SwiftUI'da hosting view).
        case accessibilityNode(NSObject, host: UIView)
    }

    public let backing: Backing
    public let selector: ElementSelector
    public let match: MatchKind
    /// Pencere koordinatlarında, üst view'ların kırpması uygulanmış görünen çerçeve.
    public let visibleFrame: CGRect
    public let window: UIWindow
    /// Çizim sırası; büyük olan öndedir.
    let zOrder: Int

    public var center: CGPoint { CGPoint(x: visibleFrame.midX, y: visibleFrame.midY) }
}

/// Panelin "Öğeler" sekmesinde listelenen, ekrandaki adlandırılmış öğe.
public struct InspectedElement: Identifiable, Sendable {
    public let id: Int
    public let identifier: String?
    public let name: String?
    public let kind: String

    /// Akışa yazılacak en sağlam sorgu: önce identifier, yoksa görünen ad.
    public var suggestedQuery: String { identifier ?? name ?? "" }
}

/// UI Helper: `UIWindow` hiyerarşisini yukarıdan aşağıya özyinelemeli (recursive) tarar ve
/// sorguyu `accessibilityIdentifier`, `accessibilityLabel` ya da görünen metinle eşleştirir.
///
/// UIKit view'larının yanında, UIView olmayan erişilebilirlik düğümlerini de gezer; SwiftUI
/// `Button`, `Text`, `NavigationLink` gibi öğeler ekranda bu düğümler olarak bulunur.
/// Yalnızca **görünür** öğeler döner: gizli, saydam ya da kırpılarak ekran dışında kalanlar elenir.
@MainActor
public struct ViewResolver {
    /// Taranacak pencereler, arkadan öne sıralı. Testlerde sahte hiyerarşi vermek için değiştirilebilir.
    public var windows: @MainActor () -> [UIWindow]

    public init(windows: @escaping @MainActor () -> [UIWindow] = ViewResolver.applicationWindows) {
        self.windows = windows
    }

    /// Uygulamanın görünür pencereleri (Mister-O paneli hariç), `windowLevel`'a göre arkadan öne.
    public static func applicationWindows() -> [UIWindow] {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .background && $0.activationState != .unattached }
            .flatMap(\.windows)
            .filter { !($0 is OverlayWindow) && !$0.isHidden && $0.alpha > 0.01 }
        return windows.enumerated()
            .sorted { ($0.element.windowLevel.rawValue, $0.offset) < ($1.element.windowLevel.rawValue, $1.offset) }
            .map(\.element)
    }

    /// En iyi görünür eşleşme: önce eşleşme gücü, eşitse en öndeki.
    public func find(_ selector: ElementSelector) -> UIElement? {
        findAll(selector).first
    }

    /// Tüm görünür eşleşmeler, en iyiden kötüye.
    public func findAll(_ selector: ElementSelector) -> [UIElement] {
        var matches: [UIElement] = []
        traverse { candidate in
            guard let kind = ElementAttributes(candidate.object).match(selector.query) else { return }
            matches.append(UIElement(
                backing: candidate.backing,
                selector: selector,
                match: kind,
                visibleFrame: candidate.visibleFrame,
                window: candidate.window,
                zOrder: candidate.order
            ))
        }
        return matches.sorted { ($0.match, $0.zOrder) > ($1.match, $1.zOrder) }
    }

    /// Ekrandaki adlandırılmış (identifier ya da metni olan) görünür öğeler, yukarıdan aşağıya.
    public func inspect(limit: Int = 300) -> [InspectedElement] {
        var found: [(frame: CGRect, attributes: ElementAttributes, kind: String)] = []
        traverse { candidate in
            // Buton içindeki title label'ı ayrıca listeleme; buton zaten listede.
            if case .view(let view) = candidate.backing, view.superview?.firstAncestor(ofType: UIControl.self) != nil {
                return
            }
            let attributes = ElementAttributes(candidate.object)
            guard attributes.identifier != nil || attributes.displayName != nil else { return }
            found.append((candidate.visibleFrame, attributes, Self.kindName(of: candidate.backing)))
        }
        return found
            .sorted { ($0.frame.minY.rounded(), $0.frame.minX) < ($1.frame.minY.rounded(), $1.frame.minX) }
            .prefix(limit)
            .enumerated()
            .map { InspectedElement(id: $0.offset, identifier: $0.element.attributes.identifier,
                                    name: $0.element.attributes.displayName, kind: $0.element.kind) }
    }

    // MARK: - Tarama

    struct Candidate {
        let backing: UIElement.Backing
        let visibleFrame: CGRect
        let window: UIWindow
        let order: Int

        var object: NSObject {
            switch backing {
            case .view(let view): view
            case .accessibilityNode(let node, _): node
            }
        }
    }

    /// Görünür tüm öğeleri pre-order DFS ile gezer. Bu sıra çizim sırasıdır: sonra gelen öndedir.
    func traverse(_ visit: (Candidate) -> Void) {
        var order = 0
        var seen = Set<ObjectIdentifier>()

        func walk(_ view: UIView, window: UIWindow, clip: CGRect) {
            guard !view.isHidden, view.alpha > 0.01, seen.insert(ObjectIdentifier(view)).inserted else { return }
            order += 1

            let visible = view.convert(view.bounds, to: window).intersection(clip)
            if !visible.isEmpty {
                visit(Candidate(backing: .view(view), visibleFrame: visible, window: window, order: order))
            }

            // clipsToBounds olan view (ör. scroll view) çocuklarını kendi sınırına kırpar.
            let childClip = view.clipsToBounds ? visible : clip
            guard !childClip.isEmpty else { return }

            walkAccessibilityNodes(of: view, host: view, window: window, clip: childClip, depth: 0)
            for subview in view.subviews {
                walk(subview, window: window, clip: childClip)
            }
        }

        func walkAccessibilityNodes(of container: NSObject, host: UIView, window: UIWindow, clip: CGRect, depth: Int) {
            guard depth < 32 else { return }
            for case let node as NSObject in Self.accessibilityChildren(of: container) where !(node is UIView) {
                guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
                order += 1

                let frame = window.convert(node.accessibilityFrame, from: Self.screenSpace(of: window))
                let visible = frame.intersection(clip)
                if !visible.isEmpty, !node.accessibilityElementsHidden {
                    visit(Candidate(backing: .accessibilityNode(node, host: host), visibleFrame: visible,
                                    window: window, order: order))
                }
                walkAccessibilityNodes(of: node, host: host, window: window, clip: clip, depth: depth + 1)
            }
        }

        for window in windows() {
            walk(window, window: window, clip: window.bounds)
        }
    }

    /// `UIAccessibilityContainer` gayri resmi protokolünün iki biçimini de okur.
    private static func accessibilityChildren(of container: NSObject) -> [Any] {
        if let elements = container.accessibilityElements {
            return elements
        }
        let count = container.accessibilityElementCount()
        guard count > 0, count != NSNotFound else { return [] }
        return (0..<count).compactMap { container.accessibilityElement(at: $0) }
    }

    /// `accessibilityFrame` ekran koordinatlarındadır.
    private static func screenSpace(of window: UIWindow) -> UICoordinateSpace {
        (window.windowScene?.screen ?? window.screen).coordinateSpace
    }

    private static func kindName(of backing: UIElement.Backing) -> String {
        switch backing {
        case .view(let view):
            return String(describing: type(of: view))
        case .accessibilityNode(let node, _):
            let traits = node.accessibilityTraits
            let role = if traits.contains(.button) { "Button" }
                else if traits.contains(.link) { "Link" }
                else if traits.contains(.header) { "Header" }
                else if traits.contains(.searchField) { "SearchField" }
                else if traits.contains(.image) { "Image" }
                else if traits.contains(.staticText) { "Text" }
                else if traits.contains(.adjustable) { "Adjustable" }
                else { "Element" }
            return "\(role) · AX"
        }
    }
}

extension UIView {
    /// Kendisi dahil, üst zincirdeki ilk `T`.
    func firstAncestor<T: UIView>(ofType type: T.Type) -> T? {
        sequence(first: self, next: { $0.superview }).lazy.compactMap { $0 as? T }.first
    }
}
#endif
