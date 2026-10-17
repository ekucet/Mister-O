#if canImport(UIKit)
import Testing
import UIKit
@testable import MisterO

@MainActor
struct ScreenCaptureTests {
    @available(iOS 17.0, *)   // traitOverrides
    @Test func capturesTheWindowAsPNGAtMostAt2x() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.traitOverrides.displayScale = 3
        window.updateTraitsIfNeeded()
        window.backgroundColor = .white
        window.isHidden = false

        let data = try #require(ScreenCapture.png(of: window))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let image = try #require(UIImage(data: data))
        #expect(image.size.width * image.scale == 780)
        #expect(image.size.height * image.scale == 1688)
    }

    @Test func skipsAnEmptyWindow() {
        #expect(ScreenCapture.png(of: UIWindow(frame: .zero)) == nil)
    }
}
#endif
