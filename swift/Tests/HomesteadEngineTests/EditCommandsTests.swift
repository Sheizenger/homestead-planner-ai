import Testing
@testable import HomesteadEngine

/// Every expectation below is a real `parseEditCommand`/`resizeTransform`/
/// `findRepositionTarget` value captured from Node, not inferred by reading
/// the TypeScript.
struct EditCommandsTests {
    private func object(_ typeId: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> PlanObject {
        PlanObject(id: "obj-\(typeId)", typeId: typeId, category: .residential, transform: Transform(x: x, y: y, width: w, height: h), label: typeId, layerId: .residential)
    }

    private var scene: [PlanObject] {
        [object("greenhouse", 10, 10, 8, 5), object("well", 30, 30, 2, 2), object("house", 5, 5, 12, 10)]
    }

    @Test func parsesEveryVerbAgainstTheObjectsPresent() {
        let cases: [(String, ParsedEditCommand?)] = [
            ("move the greenhouse near the well", ParsedEditCommand(verb: .moveNear, subjectTypeId: "greenhouse", referenceTypeId: "well")),
            ("move greenhouse away from the well", ParsedEditCommand(verb: .moveAway, subjectTypeId: "greenhouse", referenceTypeId: "well")),
            ("delete the well", ParsedEditCommand(verb: .delete, subjectTypeId: "well", referenceTypeId: nil)),
            ("duplicate the House", ParsedEditCommand(verb: .duplicate, subjectTypeId: "house", referenceTypeId: nil)),
            ("lock the greenhouse", ParsedEditCommand(verb: .lock, subjectTypeId: "greenhouse", referenceTypeId: nil)),
            ("unlock house", ParsedEditCommand(verb: .unlock, subjectTypeId: "house", referenceTypeId: nil)),
            ("make the greenhouse bigger", ParsedEditCommand(verb: .enlarge, subjectTypeId: "greenhouse", referenceTypeId: nil)),
            ("shrink the House", ParsedEditCommand(verb: .shrink, subjectTypeId: "house", referenceTypeId: nil)),
            ("move something near nothing", nil),
            ("", nil),
            ("rotate the well and the house", ParsedEditCommand(verb: .rotate, subjectTypeId: "well", referenceTypeId: "house")),
        ]
        for (text, expected) in cases {
            #expect(EditCommands.parse(text, objectsPresent: scene) == expected, Comment(rawValue: text))
        }
    }

    @Test func moveVerbsRequireAReferenceObject() {
        // "near"/"away" name only one object present in the scene — no
        // second mention to move relative to, so parsing must fail rather
        // than guess a reference.
        #expect(EditCommands.parse("move the greenhouse nearby", objectsPresent: scene) == nil)
    }

    @Test func resizeGrowsAndShrinksBySameFactorTypeScriptUses() {
        let current = Transform(x: 0, y: 0, width: 8, height: 5)
        let greenhouse = ObjectLibrary["greenhouse"]!
        #expect(EditCommands.resizeTransform(entry: greenhouse, current: current, grow: true) == Size(width: 9.6, height: 6))
        #expect(EditCommands.resizeTransform(entry: greenhouse, current: current, grow: false) == Size(width: 6.4, height: 4))
    }

    @Test func resizeClampsToTheCatalogMinimum() {
        let well = ObjectLibrary["well"]!
        let shrunk = EditCommands.resizeTransform(entry: well, current: Transform(x: 0, y: 0, width: 1, height: 1), grow: false)
        #expect(shrunk == Size(width: 1, height: 1))
    }

    @Test func repositionsNearAndAwayFromTheReference() {
        let plot = Plot(boundary: PlotShape.rectangle(width: 40, height: 30))
        let subject = object("shed", 5, 5, 4, 3)
        let reference = object("well", 35, 25, 2, 2)
        let objects = [subject, reference, object("house", 20, 15, 10, 8)]

        let near = EditCommands.findRepositionTarget(objects: objects, plot: plot, subject: subject, reference: reference, mode: .near)
        #expect(near == Transform(x: 35, y: 21.75, width: 4, height: 3, rotationDeg: 0))

        let away = EditCommands.findRepositionTarget(objects: objects, plot: plot, subject: subject, reference: reference, mode: .away)
        #expect(away == Transform(x: 2, y: 1.5, width: 4, height: 3, rotationDeg: 0))
    }

    @Test func repositionFailsWhenThereIsNowhereToPutIt() {
        // A subject far too large for the plot to hold anywhere.
        let plot = Plot(boundary: PlotShape.rectangle(width: 10, height: 10))
        let subject = object("barn", 5, 5, 20, 20)
        let reference = object("well", 5, 5, 1, 1)
        let result = EditCommands.findRepositionTarget(objects: [subject, reference], plot: plot, subject: subject, reference: reference, mode: .near)
        #expect(result == nil)
    }
}
