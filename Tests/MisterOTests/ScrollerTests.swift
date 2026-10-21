#if canImport(UIKit)
import Testing
import UIKit
@testable import MisterO

@MainActor
struct ScrollerTests {
    private let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }()

    /// Ekranı dolduran, 3000 pt içerikli bir liste; en altta "Hesabı sil" butonu.
    private func makeList() -> (UIScrollView, UIButton) {
        let list = UIScrollView(frame: window.bounds)
        list.contentInsetAdjustmentBehavior = .never
        list.contentSize = CGSize(width: 390, height: 3000)
        let button = UIButton(type: .system)
        button.setTitle("Hesabı sil", for: .normal)
        button.frame = CGRect(x: 0, y: 2900, width: 390, height: 44)
        list.addSubview(button)
        window.addSubview(list)
        return (list, button)
    }

    private var driver: UIKitDriver {
        UIKitDriver(resolver: ViewResolver(windows: { [window] in [window] }))
    }

    @Test func pagesThroughTheListUntilTheElementShowsUp() {
        let (list, _) = makeList()
        let driver = driver
        #expect(!driver.isVisible("Hesabı sil"))

        var search = ScrollSearch()
        while !driver.isVisible("Hesabı sil"), driver.scrollToFind(&search) {}

        #expect(driver.isVisible("Hesabı sil"))
        #expect(abs(list.contentOffset.y - (3000 - 844)) < 0.5)
        #expect(search.steps == 4)
    }

    @Test func turnsAroundAtTheEndAndStopsAtTheOtherEnd() {
        let (list, _) = makeList()
        list.contentOffset = CGPoint(x: 0, y: 3000 - 844)
        let driver = driver

        var search = ScrollSearch()
        #expect(driver.scrollToFind(&search))
        #expect(search.hasTurned && search.direction == .up)
        while driver.scrollToFind(&search) {}
        #expect(abs(list.contentOffset.y) < 0.5)
    }

    @Test func scrollCommandMovesOnePageAndIsQuietAtTheEnd() throws {
        let (list, _) = makeList()
        let driver = driver

        try driver.scroll(.down, in: nil)
        #expect(abs(list.contentOffset.y - 844 * Scroller.pageFraction) < 1)
        try driver.scroll(.up, in: nil)
        try driver.scroll(.up, in: nil)
        #expect(abs(list.contentOffset.y) < 0.5)
    }

    @Test func coveredListsAndTextViewsAreNotScrolled() {
        let (list, _) = makeList()
        let sheet = UIView(frame: window.bounds)
        sheet.backgroundColor = .white
        window.addSubview(sheet)
        let driver = driver

        var search = ScrollSearch()
        #expect(!driver.scrollToFind(&search))
        #expect(throws: DriverError.noScrollableArea(nil)) { try driver.scroll(.down, in: nil) }
        #expect(list.contentOffset.y == 0)

        sheet.removeFromSuperview()
        list.removeFromSuperview()
        let notes = UITextView(frame: window.bounds)
        notes.text = String(repeating: "satır\n", count: 300)
        window.addSubview(notes)
        #expect(throws: DriverError.noScrollableArea(nil)) { try driver.scroll(.down, in: nil) }
    }
}
#endif
