#if canImport(UIKit)
import MisterOCore
import UIKit

/// Runner'ın kullandığı gerçek sürücü: `ViewResolver` ile bulur, `ActionExecutor` ile uygular.
@MainActor
public final class UIKitDriver: UIDriver {
    public var resolver: ViewResolver
    public var executor: ActionExecutor

    public init(resolver: ViewResolver = ViewResolver(), executor: ActionExecutor = ActionExecutor()) {
        self.resolver = resolver
        self.executor = executor
    }

    public func tap(_ selector: ElementSelector) throws {
        try executor.tap(try element(for: selector))
    }

    public func typeText(_ text: String, into selector: ElementSelector) throws {
        try executor.type(text, into: try element(for: selector))
    }

    public func isVisible(_ selector: ElementSelector) -> Bool {
        resolver.find(selector) != nil
    }

    public func isEnabled(_ selector: ElementSelector) -> Bool? {
        resolver.find(selector).map { ElementAttributes($0.object).isEnabled }
    }

    public func texts(of selector: ElementSelector) -> [String]? {
        resolver.find(selector).map { ElementAttributes($0.object).readableTexts }
    }

    public func scroll(_ direction: ScrollDirection, in selector: ElementSelector?) throws {
        let scroller = Scroller(windows: resolver.windows)
        let scrollView: UIScrollView?
        if let selector {
            scrollView = scroller.scrollView(containing: try element(for: selector), for: direction)
        } else {
            scrollView = scroller.mainScrollView(for: direction)
        }
        guard let scrollView else { throw DriverError.noScrollableArea(selector) }
        // Alan zaten sondaysa testçinin parmağıyla kaydırması gibi bir şey olmaz; hata değil.
        Scroller.page(scrollView, toward: direction)
    }

    public func scrollToFind(_ search: inout ScrollSearch) -> Bool {
        let scroller = Scroller(windows: resolver.windows)
        guard search.steps < ScrollSearch.maxSteps, let scrollView = scroller.mainScrollView(for: search.direction) else {
            return false
        }
        search.steps += 1
        if Scroller.page(scrollView, toward: search.direction) { return true }
        guard !search.hasTurned else { return false }
        search.hasTurned = true
        search.direction = search.direction.opposite
        return Scroller.page(scrollView, toward: search.direction)
    }

    public func goBack() throws {
        guard let top = ScreenAnchor.visibleViewController() else { throw DriverError.nothingToGoBack }
        if let navigation = top.navigationController, navigation.viewControllers.count > 1 {
            navigation.popViewController(animated: true)
            return
        }
        // Sunulan (sheet, tam ekran, uyarı) sayfanın kökü: üst view controller zincirinin başı.
        var presented = top
        while let parent = presented.parent {
            presented = parent
        }
        guard presented.presentingViewController != nil else { throw DriverError.nothingToGoBack }
        presented.dismiss(animated: true)
    }

    private func element(for selector: ElementSelector) throws -> UIElement {
        guard let element = resolver.find(selector) else {
            throw DriverError.elementNotFound(selector)
        }
        return element
    }
}
#endif
