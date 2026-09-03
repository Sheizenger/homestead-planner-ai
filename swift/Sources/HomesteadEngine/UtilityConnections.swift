import Foundation

/// Real hookup topology, ported from `src/engine/utilityConnections.ts` — not
/// the full adjacency-constraint matrix used for warnings, but the physical
/// cable/pipe runs a homesteader would actually wire up, so the plan can show
/// *why* a battery room or pump sits where it does, not just leave the user
/// to infer it from proximity alone.
public enum UtilityConnections {
    public static func computeNodes(_ objects: [PlanObject]) -> [UtilityNode] {
        func find(_ typeId: String) -> PlanObject? {
            objects.first { $0.typeId == typeId }
        }

        var nodesByObjectID: [String: UtilityNode] = [:]
        var order: [String] = []

        @discardableResult
        func ensure(_ object: PlanObject, kind: UtilityKind) -> UtilityNode {
            if let existing = nodesByObjectID[object.id] { return existing }
            let node = UtilityNode(id: "util-\(object.id)", objectId: object.id, type: object.typeId, kind: kind, connections: [])
            nodesByObjectID[object.id] = node
            order.append(object.id)
            return node
        }

        func link(_ a: PlanObject, _ b: PlanObject, kind: UtilityKind) {
            let nodeA = ensure(a, kind: kind)
            ensure(b, kind: kind)
            let nodeBID = "util-\(b.id)"
            if !nodeA.connections.contains(nodeBID) {
                nodesByObjectID[a.id]!.connections.append(nodeBID)
            }
        }

        // Power chain: any generation source feeds the battery room if
        // present, else straight into the inverter; battery and inverter
        // link to each other when both exist.
        let battery = find("battery-room")
        let inverter = find("inverter-room")
        if let sink = battery ?? inverter {
            for typeId in ["solar-array", "micro-hydro", "generator"] {
                if let source = find(typeId), source.id != sink.id {
                    link(source, sink, kind: .power)
                }
            }
        }
        if let battery, let inverter { link(battery, inverter, kind: .power) }

        // Water chain: well feeds the pump, which feeds a tank/cistern; a
        // tank with no pump (gravity- or rain-fed) links straight to the well.
        let well = find("well")
        let pump = find("pump")
        let tank = find("water-tank") ?? find("rainwater-cistern")
        if let well, let pump { link(well, pump, kind: .water) }
        if let pump, let tank {
            link(pump, tank, kind: .water)
        } else if let well, let tank, pump == nil {
            link(well, tank, kind: .water)
        }

        return order.map { nodesByObjectID[$0]! }
    }
}
