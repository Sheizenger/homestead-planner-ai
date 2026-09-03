import Foundation
import HomesteadEngine

/// Pan and zoom over the plan, in the sense the web app never had: the canvas
/// draws through this, rather than a scroll view stretching a fixed image.
///
/// `offset` is the world point drawn at the view's origin; `scale` is points
/// per metre. Screen-space furniture — north arrow, scale bar — is positioned
/// by the view directly and deliberately does not pass through here, which is
/// what keeps it on screen at any zoom.
public struct Viewport: Equatable, Sendable {
    public static let minScale: Double = 2
    public static let maxScale: Double = 200

    public var offset: Point
    public var scale: Double

    public init(offset: Point = Point(x: 0, y: 0), scale: Double = 12) {
        self.offset = offset
        self.scale = Self.clampScale(scale)
    }

    static func clampScale(_ scale: Double) -> Double {
        min(max(scale, minScale), maxScale)
    }

    public func toScreen(_ world: Point) -> Point {
        Point(x: (world.x - offset.x) * scale, y: (world.y - offset.y) * scale)
    }

    public func toWorld(_ screen: Point) -> Point {
        Point(x: screen.x / scale + offset.x, y: screen.y / scale + offset.y)
    }

    /// Zooms while holding one screen point still — the anchor stays under the
    /// cursor, instead of the view lurching toward its top-left corner.
    public mutating func zoom(by factor: Double, anchor: Point) {
        let before = toWorld(anchor)
        scale = Self.clampScale(scale * factor)
        let after = toWorld(anchor)
        offset.x += before.x - after.x
        offset.y += before.y - after.y
    }

    public mutating func pan(byScreen delta: Point) {
        offset.x -= delta.x / scale
        offset.y -= delta.y / scale
    }

    /// Frames `bounds` inside a view of `size`, leaving `padding` points of
    /// margin on every side. A degenerate box or view leaves the viewport
    /// untouched rather than producing an infinite or zero scale.
    public mutating func fit(_ bounds: Rect, in size: Size, padding: Double = 24) {
        let usable = Size(
            width: size.width - padding * 2,
            height: size.height - padding * 2
        )
        guard usable.width > 0, usable.height > 0, bounds.width > 0, bounds.height > 0 else { return }

        scale = Self.clampScale(min(usable.width / bounds.width, usable.height / bounds.height))
        offset = Point(
            x: bounds.midX - size.width / (2 * scale),
            y: bounds.midY - size.height / (2 * scale)
        )
    }
}
