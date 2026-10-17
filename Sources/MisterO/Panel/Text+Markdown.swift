#if canImport(UIKit)
import SwiftUI

extension Text {
    /// Çevrilmiş metindeki `kod` gibi Markdown'ı korur; `String`'den kurulan `Text` Markdown işlemez.
    init(markdown: String) {
        self.init((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
    }
}
#endif
