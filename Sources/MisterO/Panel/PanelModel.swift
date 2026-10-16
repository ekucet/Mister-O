#if canImport(UIKit)
import SwiftUI

/// Panelin açık/kapalı durumu ve yüzen baloncuğun konumu (pencere koordinatlarında).
@MainActor
final class PanelModel: ObservableObject {
    static let coordinateSpace = "MisterO.panel"
    static let bubbleDiameter: CGFloat = 56
    private static let edgeMargin: CGFloat = 14

    @Published var isExpanded = false
    @Published var bubbleCenter: CGPoint?

    /// Koşu başlamadan hemen önce çağrılır (klavyeyi kapat, odağı uygulamaya ver).
    var prepareForRun: () -> Void = {}

    func expand() { isExpanded = true }
    func collapse() { isExpanded = false }

    func center(in size: CGSize) -> CGPoint {
        let fallback = CGPoint(x: size.width - Self.bubbleDiameter / 2 - Self.edgeMargin, y: size.height * 0.62)
        return clamped(bubbleCenter ?? fallback, in: size)
    }

    /// Bırakılan baloncuğu en yakın yan kenara yapıştırır.
    func snapped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let inset = Self.bubbleDiameter / 2 + Self.edgeMargin
        return clamped(CGPoint(x: point.x < size.width / 2 ? inset : size.width - inset, y: point.y), in: size)
    }

    func acceptsTouch(at point: CGPoint, in size: CGSize) -> Bool {
        if isExpanded { return true }
        let center = center(in: size)
        return hypot(point.x - center.x, point.y - center.y) <= Self.bubbleDiameter / 2 + 8
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let inset = Self.bubbleDiameter / 2 + Self.edgeMargin
        guard size.width > inset * 2, size.height > inset * 2 + 120 else { return point }
        return CGPoint(x: min(max(point.x, inset), size.width - inset),
                       y: min(max(point.y, inset + 60), size.height - inset - 60))
    }
}
#endif
