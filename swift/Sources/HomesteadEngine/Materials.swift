import Foundation

/// Ported from `src/engine/materials.ts`. A real bill-of-quantities view of
/// the plan — metres of each fence type, square metres of paved driveway/
/// walkway vs. gravel path, each structure's footprint — as opposed to
/// `Costs`, which turns the same geometry straight into money and never
/// exposes the raw quantities a contractor would actually order against.
public struct FenceQuantity: Equatable, Codable, Sendable {
    public let fenceType: FenceType
    public let lengthM: Double
}

public enum PathGroup: String, Codable, Sendable {
    case driveway, walkway, gardenPath
}

public struct PathQuantity: Equatable, Codable, Sendable {
    public let group: PathGroup
    public let lengthM: Double
    public let widthM: Double
    public let areaM2: Double
}

public struct StructureQuantity: Equatable, Codable, Sendable {
    public let typeId: String
    public let label: String
    public let widthM: Double
    public let heightM: Double
    public let areaM2: Double
}

public struct MaterialsTakeoff: Equatable, Codable, Sendable {
    public let fences: [FenceQuantity]
    public let totalFenceLengthM: Double
    public let paths: [PathQuantity]
    public let totalPavedAreaM2: Double
    public let totalGravelAreaM2: Double
    public let structures: [StructureQuantity]
}

public enum Materials {
    private static func polylineLength(_ points: [Point]) -> Double {
        var length = 0.0
        for i in 0..<max(0, points.count - 1) { length += distance(points[i], points[i + 1]) }
        return length
    }

    public static func takeoff(objects: [PlanObject], paths: [PathEntity], fences: [Fence]) -> MaterialsTakeoff {
        // Both maps accumulate in first-insertion order (the order fences/
        // paths appear in their arrays) and sum floating lengths as they go
        // — same insertion-order sensitivity as Analytics' category totals,
        // for the same reason: (a + b) + c isn't bit-identical to whatever
        // order a JavaScript Map would have summed them in otherwise.
        var fenceOrder: [FenceType] = []
        var fenceLengths: [FenceType: Double] = [:]
        for fence in fences {
            guard let first = fence.points.first else { continue }
            let lengthM = polylineLength(fence.points + [first])
            if fenceLengths[fence.fenceType] == nil { fenceOrder.append(fence.fenceType) }
            fenceLengths[fence.fenceType, default: 0] += lengthM
        }
        let fenceQuantities = fenceOrder.map { FenceQuantity(fenceType: $0, lengthM: fenceLengths[$0]!) }
        let totalFenceLengthM = fenceQuantities.reduce(0.0) { $0 + $1.lengthM }

        var pathOrder: [PathGroup] = []
        var pathLengths: [PathGroup: (lengthM: Double, widthM: Double)] = [:]
        for path in paths {
            let group: PathGroup = path.category == .service ? .driveway : path.surfaceType == .paved ? .walkway : .gardenPath
            let lengthM = polylineLength(path.points)
            if var existing = pathLengths[group] {
                existing.lengthM += lengthM
                pathLengths[group] = existing
            } else {
                pathOrder.append(group)
                pathLengths[group] = (lengthM, path.widthM)
            }
        }
        let pathQuantities = pathOrder.map { group -> PathQuantity in
            let entry = pathLengths[group]!
            return PathQuantity(group: group, lengthM: entry.lengthM, widthM: entry.widthM, areaM2: entry.lengthM * entry.widthM)
        }
        let totalPavedAreaM2 = pathQuantities.filter { $0.group != .gardenPath }.reduce(0.0) { $0 + $1.areaM2 }
        let totalGravelAreaM2 = pathQuantities.filter { $0.group == .gardenPath }.reduce(0.0) { $0 + $1.areaM2 }

        // JavaScript's sort is stable; Swift's is not, and two structures
        // sharing an area — a common coincidence among same-type crops or
        // outbuildings — would otherwise reorder. Explicit index tie-break.
        let structures = objects.enumerated()
            .map { offset, object -> (Int, StructureQuantity) in
                (offset, StructureQuantity(
                    typeId: object.typeId,
                    label: ObjectLibrary[object.typeId]?.label ?? object.typeId,
                    widthM: object.transform.width,
                    heightM: object.transform.height,
                    areaM2: object.transform.width * object.transform.height
                ))
            }
            .sorted { lhs, rhs in
                if lhs.1.areaM2 != rhs.1.areaM2 { return lhs.1.areaM2 > rhs.1.areaM2 }
                return lhs.0 < rhs.0
            }
            .map(\.1)

        return MaterialsTakeoff(
            fences: fenceQuantities,
            totalFenceLengthM: totalFenceLengthM,
            paths: pathQuantities,
            totalPavedAreaM2: totalPavedAreaM2,
            totalGravelAreaM2: totalGravelAreaM2,
            structures: structures
        )
    }
}
