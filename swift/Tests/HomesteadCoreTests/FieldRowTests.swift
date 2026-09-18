import Foundation
import Testing
import HomesteadEngine
@testable import HomesteadCore

struct FieldRowTests {
    private func bed(_ w: Double, _ d: Double, rotation: Double = 0) -> PlanObject {
        PlanObject(
            id: "bed-1",
            typeId: "vineyard",
            category: .foodPerennial,
            transform: Transform(x: 20, y: 20, width: w, height: d, rotationDeg: rotation),
            label: "vineyard",
            layerId: .foodPerennial
        )
    }

    /// A field plants inside its own bed. Plants are placed by their centres
    /// and scaled uniformly, so a row laid out to the edge hangs half a plant
    /// over it — which put a vine row inside the smokehouse next door and
    /// turned the overlap check red.
    @Test func plantsStayOnTheirOwnBed() {
        for (w, d, height) in [(6.0, 9.0, 1.5), (4.0, 4.0, 1.0), (12.0, 5.0, 1.6), (3.0, 3.0, 1.8)] {
            let object = bed(w, d)
            let nodes = SceneBuilder.rows(
                object, model: "survival/grass-large", spacing: 3.0, height: height,
                alongLongAxis: true, stretched: false, tilt: 0, base: 0, tint: nil,
                metrics: ModelMetrics.all
            )
            guard !nodes.isEmpty else {
                Issue.record("no plants for a \(w)x\(d) bed")
                continue
            }
            guard let mesh = ModelMetrics["survival/grass-large"] else {
                Issue.record("no metrics for the test mesh")
                return
            }
            let box = object.transform
            for node in nodes {
                let halfX = mesh.width * node.scale.x / 2
                let halfZ = mesh.depth * node.scale.z / 2
                // A hand's breadth of slack: the jitter along a row is
                // deliberate and a plant is not a box.
                #expect(node.position.x - halfX > box.x - box.width / 2 - 0.25)
                #expect(node.position.x + halfX < box.x + box.width / 2 + 0.25)
                #expect(node.position.z - halfZ > box.y - box.height / 2 - 0.25)
                #expect(node.position.z + halfZ < box.y + box.height / 2 + 0.25)
            }
        }
    }

    /// Rows you can see rows in. Set the spacing under the plant's own width
    /// and the bed closes into one green mass — which is how the vines, the
    /// berries and the grain all came to look like the same thing.
    @Test func aRowHasGapsAlongIt() {
        let object = bed(8, 12)
        let nodes = SceneBuilder.rows(
            object, model: "survival/grass-large", spacing: 3.0, height: 1.5,
            alongLongAxis: true, stretched: false, tilt: 0, base: 0, tint: nil,
            metrics: ModelMetrics.all
        )
        guard let mesh = ModelMetrics["survival/grass-large"], nodes.count > 2 else {
            Issue.record("expected a planted bed")
            return
        }
        let widest = nodes.map { mesh.width * $0.scale.x }.max() ?? 0
        var apart = Double.infinity
        for (a, b) in zip(nodes, nodes.dropFirst()) {
            let dx: Double = a.position.x - b.position.x
            let dz: Double = a.position.z - b.position.z
            let gap: Double = (dx * dx + dz * dz).squareRoot()
            if gap > 0.01 { apart = min(apart, gap) }
        }
        #expect(apart > widest * 0.8, "plants \(apart)m apart are \(widest)m wide")
    }
}
