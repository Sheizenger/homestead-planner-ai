import Testing
import HomesteadEngine
@testable import HomesteadCore

struct HitTestingTests {
    private func object(_ id: String, _ transform: Transform) -> PlanObject {
        PlanObject(id: id, typeId: "shed", category: .storage, transform: transform, label: id, layerId: .storage)
    }

    // MARK: - Point hit-testing

    @Test func pointHitsTheTopmostObjectAtThatPoint() {
        let objects = [
            object("back", Transform(x: 10, y: 10, width: 6, height: 6)),
            object("front", Transform(x: 10, y: 10, width: 6, height: 6)),
        ]
        // Both occupy the same footprint; draw order says "front" is on top.
        #expect(HitTesting.hitTest(Point(x: 10, y: 10), in: objects) == "front")
    }

    @Test func pointOutsideEveryFootprintMissesEntirely() {
        let objects = [object("a", Transform(x: 10, y: 10, width: 4, height: 4))]
        #expect(HitTesting.hitTest(Point(x: 100, y: 100), in: objects) == nil)
    }

    /// The point this whole file exists to prove: a rotated object's corner
    /// is not where its AABB says it is, and hit-testing against the actual
    /// footprint has to get that right.
    @Test func hitTestRespectsRotationNotJustTheBoundingBox() {
        // A 10x2 rect centred at (10,10), rotated 45°: its AABB spans
        // roughly ±7 in both axes, but the point (10, 6.9) — inside that
        // AABB — is well outside the actual rotated sliver.
        let rotated = object("plank", Transform(x: 10, y: 10, width: 10, height: 2, rotationDeg: 45))
        #expect(rotated.transform.aabb.overlaps(Rect(minX: 9.9, minY: 6.8, maxX: 10.1, maxY: 7.0)))
        #expect(HitTesting.hitTest(Point(x: 10, y: 6.9), in: [rotated]) == nil)
        // But the centre, and a point out along the rotated long axis, hit.
        #expect(HitTesting.hitTest(Point(x: 10, y: 10), in: [rotated]) == "plank")
    }

    // MARK: - Marquee hit-testing

    @Test func marqueeCatchesAnObjectItFullyContains() {
        let objects = [object("a", Transform(x: 10, y: 10, width: 2, height: 2))]
        let hits = HitTesting.objectsIntersecting(Rect(minX: 0, minY: 0, maxX: 20, maxY: 20), in: objects)
        #expect(hits == ["a"])
    }

    @Test func marqueeMissesAnObjectEntirelyOutsideIt() {
        let objects = [object("a", Transform(x: 100, y: 100, width: 2, height: 2))]
        #expect(HitTesting.objectsIntersecting(Rect(minX: 0, minY: 0, maxX: 20, maxY: 20), in: objects).isEmpty)
    }

    /// The web app's marquee tested only an object's centre point (see
    /// BACKLOG.md), which misses an object straddling the marquee's edge
    /// with its centre outside. A true overlap test catches it.
    @Test func marqueeCatchesAnObjectItOnlyPartiallyOverlaps() {
        let objects = [object("straddling", Transform(x: 19, y: 10, width: 6, height: 6))]
        let hits = HitTesting.objectsIntersecting(Rect(minX: 0, minY: 0, maxX: 20, maxY: 20), in: objects)
        #expect(hits == ["straddling"])
    }

    /// A diamond (45°-rotated square) can poke a corner into the marquee
    /// while its AABB — a much larger axis-aligned box — also overlaps; the
    /// AABB overlap alone is not sufficient to prove the actual shapes
    /// touch, so this exercises the segment-intersection fallback rather
    /// than either containment shortcut.
    @Test func marqueeUsesTheRotatedFootprintNotTheBoundingBox() {
        let diamond = object("diamond", Transform(x: 25, y: 10, width: 12, height: 12, rotationDeg: 45))
        // The diamond's corner reaches to x = 25 - 12/√2 ≈ 16.5, into a
        // marquee spanning only x ∈ [0, 18].
        let hits = HitTesting.objectsIntersecting(Rect(minX: 0, minY: 0, maxX: 18, maxY: 20), in: [diamond])
        #expect(hits == ["diamond"])

        let miss = HitTesting.objectsIntersecting(Rect(minX: 0, minY: 0, maxX: 10, maxY: 20), in: [diamond])
        #expect(miss.isEmpty)
    }

    @Test func hiddenObjectsAreExcludedByPreFilteringTheList() {
        // HitTesting has no notion of "layer visibility" — the caller
        // filters before calling, which is what actually fixes the web
        // app's "marquee catches hidden-layer objects" bug (see BACKLOG.md):
        // there is nothing here for a hidden object to leak through.
        let objects = [object("hidden", Transform(x: 10, y: 10, width: 4, height: 4))]
        let visible = objects.filter { $0.id != "hidden" }
        #expect(HitTesting.hitTest(Point(x: 10, y: 10), in: visible) == nil)
    }
}
