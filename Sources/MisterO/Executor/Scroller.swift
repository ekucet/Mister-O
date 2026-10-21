#if canImport(UIKit)
import MisterOCore
import UIKit

/// Kaydırılabilir alanları (UIKit `UIScrollView`, `UITableView`, `UICollectionView`; SwiftUI `ScrollView`
/// ve `List`) bulur ve `setContentOffset` ile sayfa sayfa kaydırır. Sentetik dokunuş üretmez.
@MainActor
struct Scroller {
    /// Bir sayfa, görünen yüksekliğin bu kadarı: önceki sayfanın son satırı yeni sayfada da görünür.
    static let pageFraction: CGFloat = 0.8

    let windows: @MainActor () -> [UIWindow]

    /// Ekranın ana listesi: önde duran penceredeki, üstü kapalı olmayan, bu yönde kaydırılabilen en büyük alan.
    func mainScrollView(for direction: ScrollDirection) -> UIScrollView? {
        for window in windows().reversed() {
            let candidates = scrollViews(in: window, scrollableToward: direction).filter { isUncovered($0, in: window) }
            if let largest = candidates.max(by: { area($0, in: window) < area($1, in: window) }) {
                return largest
            }
        }
        return nil
    }

    /// Öğeyi içeren en içteki kaydırılabilir alan: UIKit'te öğenin üst view'ları, SwiftUI'da öğenin
    /// ortasını kapsayan scroll view.
    func scrollView(containing element: UIElement, for direction: ScrollDirection) -> UIScrollView? {
        if case .view(let view) = element.backing,
           let own = sequence(first: view, next: { $0.superview }).lazy.compactMap({ $0 as? UIScrollView })
               .first(where: { Self.isCandidate($0) }) {
            return own
        }
        return scrollViews(in: element.window, scrollableToward: nil)
            .filter { visibleFrame(of: $0, in: element.window).contains(element.center) }
            .min { area($0, in: element.window) < area($1, in: element.window) }
    }

    /// Bir sayfa kaydırır. Alan o yönde sondaysa (kayacak yer yoksa) `false`.
    @discardableResult
    static func page(_ scrollView: UIScrollView, toward direction: ScrollDirection) -> Bool {
        let inset = scrollView.adjustedContentInset
        let bounds = scrollView.bounds.size
        let current = scrollView.contentOffset
        var target = current
        switch direction {
        case .down, .up:
            let minY = -inset.top
            let maxY = max(minY, scrollView.contentSize.height - bounds.height + inset.bottom)
            let page = max(1, (bounds.height - inset.top - inset.bottom) * pageFraction)
            target.y = direction == .down ? min(current.y + page, maxY) : max(current.y - page, minY)
        case .left, .right:
            let minX = -inset.left
            let maxX = max(minX, scrollView.contentSize.width - bounds.width + inset.right)
            let page = max(1, (bounds.width - inset.left - inset.right) * pageFraction)
            target.x = direction == .right ? min(current.x + page, maxX) : max(current.x - page, minX)
        }
        guard abs(target.x - current.x) > 0.5 || abs(target.y - current.y) > 0.5 else { return false }
        scrollView.setContentOffset(target, animated: false)
        scrollView.layoutIfNeeded()
        return true
    }

    // MARK: - Yardımcılar

    /// Penceredeki görünür, kaydırmaya açık alanlar (metin görünümleri hariç), arkadan öne.
    private func scrollViews(in window: UIWindow, scrollableToward direction: ScrollDirection?) -> [UIScrollView] {
        var found: [UIScrollView] = []
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let scrollView = view as? UIScrollView, Self.isCandidate(scrollView),
               !visibleFrame(of: scrollView, in: window).isEmpty,
               direction.map({ Self.canScroll(scrollView, along: $0) }) ?? true {
                found.append(scrollView)
            }
            view.subviews.forEach(walk)
        }
        walk(window)
        return found
    }

    private static func isCandidate(_ scrollView: UIScrollView) -> Bool {
        scrollView.isScrollEnabled && !(scrollView is UITextView)
    }

    /// İçerik bu eksende alandan büyük mü? (Sondaysa da `true`; o zaman ters yöne kaydırılır.)
    private static func canScroll(_ scrollView: UIScrollView, along direction: ScrollDirection) -> Bool {
        let inset = scrollView.adjustedContentInset
        if direction.isVertical {
            return scrollView.contentSize.height + inset.top + inset.bottom > scrollView.bounds.height + 1
        }
        return scrollView.contentSize.width + inset.left + inset.right > scrollView.bounds.width + 1
    }

    /// Üstünde başka bir ekran (sheet, uyarı) yok: alanın ortasına dokunulsa ona ulaşılır.
    private func isUncovered(_ scrollView: UIScrollView, in window: UIWindow) -> Bool {
        let frame = visibleFrame(of: scrollView, in: window)
        guard let hit = window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil) else { return false }
        return hit.isDescendant(of: scrollView)
    }

    private func visibleFrame(of view: UIView, in window: UIWindow) -> CGRect {
        var frame = view.convert(view.bounds, to: window).intersection(window.bounds)
        for ancestor in sequence(first: view.superview, next: { $0?.superview }).compactMap({ $0 }) where ancestor.clipsToBounds {
            frame = frame.intersection(ancestor.convert(ancestor.bounds, to: window))
        }
        return frame.isNull ? .zero : frame
    }

    private func area(_ view: UIView, in window: UIWindow) -> CGFloat {
        let frame = visibleFrame(of: view, in: window)
        return frame.width * frame.height
    }
}
#endif
