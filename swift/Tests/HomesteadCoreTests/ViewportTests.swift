import Testing
import HomesteadEngine
@testable import HomesteadCore

@Test func screenAndWorldRoundTrip() {
    let viewport = Viewport(offset: Point(x: 12, y: -4), scale: 18)
    let world = Point(x: 31.5, y: 7.25)
    let back = viewport.toWorld(viewport.toScreen(world))
    #expect(abs(back.x - world.x) < 1e-9)
    #expect(abs(back.y - world.y) < 1e-9)
}

/// The behaviour the web app lacked: zooming pulls the view toward the
/// cursor rather than toward the top-left corner.
@Test func zoomHoldsTheAnchorPointStill() {
    var viewport = Viewport(offset: Point(x: 0, y: 0), scale: 10)
    let anchor = Point(x: 320, y: 180)
    let worldUnderCursor = viewport.toWorld(anchor)

    viewport.zoom(by: 2.5, anchor: anchor)

    let stillThere = viewport.toWorld(anchor)
    #expect(abs(stillThere.x - worldUnderCursor.x) < 1e-9)
    #expect(abs(stillThere.y - worldUnderCursor.y) < 1e-9)
    #expect(viewport.scale == 25)
}

@Test func zoomClampsWithoutLosingTheAnchor() {
    var viewport = Viewport(offset: Point(x: 0, y: 0), scale: 10)
    let anchor = Point(x: 100, y: 100)
    let worldUnderCursor = viewport.toWorld(anchor)

    viewport.zoom(by: 1_000, anchor: anchor)

    #expect(viewport.scale == Viewport.maxScale)
    #expect(abs(viewport.toWorld(anchor).x - worldUnderCursor.x) < 1e-9)
}

@Test func panMovesTheWorldWithTheCursor() {
    var viewport = Viewport(offset: Point(x: 0, y: 0), scale: 20)
    viewport.pan(byScreen: Point(x: 40, y: -20))
    #expect(viewport.offset == Point(x: -2, y: 1))
}

@Test func fitCentresThePlotAndLeavesMargin() {
    var viewport = Viewport()
    let plot = Rect(minX: 0, minY: 0, width: 50, height: 42)
    let size = Size(width: 800, height: 600)

    viewport.fit(plot, in: size, padding: 24)

    // The tighter axis decides the scale: (600 - 48) / 42 is smaller than
    // (800 - 48) / 50.
    #expect(abs(viewport.scale - 552.0 / 42.0) < 1e-9)

    let centre = viewport.toWorld(Point(x: size.width / 2, y: size.height / 2))
    #expect(abs(centre.x - plot.midX) < 1e-9)
    #expect(abs(centre.y - plot.midY) < 1e-9)
}

@Test func fitLeavesADegenerateViewAlone() {
    var viewport = Viewport(offset: Point(x: 3, y: 4), scale: 15)
    let before = viewport

    viewport.fit(Rect(minX: 0, minY: 0, width: 0, height: 0), in: Size(width: 800, height: 600))
    #expect(viewport == before)

    viewport.fit(Rect(minX: 0, minY: 0, width: 50, height: 42), in: Size(width: 10, height: 10))
    #expect(viewport == before)
}

@Test func boundingBoxOfAPolygon() {
    let lShape = [
        Point(x: 0, y: 0), Point(x: 60, y: 0), Point(x: 60, y: 30),
        Point(x: 40, y: 30), Point(x: 40, y: 45), Point(x: 0, y: 45),
    ]
    let bounds = Rect(bounding: lShape)
    #expect(bounds == Rect(minX: 0, minY: 0, width: 60, height: 45))
    #expect(Rect(bounding: []) == nil)
}

/// Rounding is a silent porting trap: these two disagree only on negative
/// halves, which is exactly where a plan places objects left of the origin.
@Test func jsRoundBreaksHalvesUpwardsLikeJavaScript() {
    #expect(jsRound(2.5) == 3)
    #expect(jsRound(-2.5) == -2)
    #expect((-2.5).rounded() == -3)
    #expect(jsRound(-2.6) == -3)
    #expect(jsRound(0.5) == 1)
    #expect(jsRound(-0.5) == 0)
}
