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

    private func element(for selector: ElementSelector) throws -> UIElement {
        guard let element = resolver.find(selector) else {
            throw DriverError.elementNotFound(selector)
        }
        return element
    }
}
#endif
