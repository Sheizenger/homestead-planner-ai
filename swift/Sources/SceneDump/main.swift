//  Dumps a generated plan's 3D scene as JSON.
//
//  The app target cannot be built on Linux, so the only way to see whether a
//  scene is right is to build it here and rasterise it here. This hands the
//  scene to `scripts/preview_scene.py`, which reads the same OBJ files the
//  renderer will and draws them through the same camera.
//
//      swift run scene-dump > scene.json

import Foundation
import HomesteadEngine
import HomesteadCore

func encode(_ value: Any) -> String {
    switch value {
    case let number as Double:
        return number.isFinite ? String(format: "%.5f", number) : "0"
    case let number as Int:
        return String(number)
    case let text as String:
        return "\"" + text.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    // An array of pairs is also an array of Any, so it has to be tried first
    // or every object encodes as a list of nulls.
    case let object as [(String, Any)]:
        return "{" + object.map { "\"\($0.0)\":" + encode($0.1) }.joined(separator: ",") + "}"
    case let list as [Any]:
        return "[" + list.map(encode).joined(separator: ",") + "]"
    case Optional<Any>.none:
        return "null"
    default:
        return "null"
    }
}

let arguments = CommandLine.arguments
let width = Double(arguments.dropFirst().first ?? "") ?? 52
let depth = Double(arguments.dropFirst(2).first ?? "") ?? 40

var inputs = StructuredInputs()
inputs.householdSize = 4
inputs.crops = ["potato", "vegetable", "grain", "berries", "orchard", "vineyard", "greenhouse", "raised-beds"]
inputs.animals = [AnimalRequest(type: "goats", count: 6), AnimalRequest(type: "poultry", count: 12)]
inputs.infrastructure = [
    "solar", "well", "septic", "water-tank", "compost", "cellar", "woodshed",
    "garage", "barn", "pool", "gazebo", "apiary", "banya", "smokehouse", "workshop",
]

let plot = Plot(
    boundary: [
        Point(x: 0, y: 0), Point(x: width, y: 0),
        Point(x: width, y: depth), Point(x: 0, y: depth),
    ],
    waterfront: Waterfront(type: .river, edge: .north, widthM: 11)
)
let brief = Brief(structuredInputs: inputs)
let layout = Generate.variant(plot: plot, brief: brief, mode: .beautyBalanced, seed: 7)
let variant = Variant(generated: layout, plot: plot, brief: brief)

let scene = SceneBuilder.build(plot: plot, variant: variant)

let meshes: [Any] = scene.meshes.map { node in
    [
        ("id", node.id), ("model", node.model),
        ("p", [node.position.x, node.position.y, node.position.z] as [Any]),
        ("s", [node.scale.x, node.scale.y, node.scale.z] as [Any]),
        ("yaw", node.yaw), ("pitch", node.pitch),
        ("tint", node.tint ?? -1),
        ("object", node.objectId ?? ""),
    ] as [(String, Any)]
}
let slabs: [Any] = scene.slabs.map { slab in
    [
        ("id", slab.id),
        ("polygon", slab.polygon.flatMap { [$0.x, $0.y] } as [Any]),
        ("top", slab.top), ("thickness", slab.thickness), ("colour", slab.colour),
    ] as [(String, Any)]
}
let objects: [Any] = variant.objects.map { object in
    [
        ("id", object.id), ("type", object.typeId),
        ("x", object.transform.x), ("y", object.transform.y),
        ("w", object.transform.width), ("d", object.transform.height),
        ("rot", object.transform.rotationDeg),
    ] as [(String, Any)]
}
let solids: [Any] = scene.solids.map { solid in
    [
        ("id", solid.id),
        ("polygon", solid.polygon.flatMap { [$0.x, $0.y] } as [Any]),
        ("base", solid.base), ("wall", solid.wallHeight), ("ridge", solid.ridgeRise),
        ("colour", solid.colour), ("opacity", solid.opacity),
    ] as [(String, Any)]
}
print(encode([
    ("meshes", meshes), ("slabs", slabs), ("solids", solids), ("objects", objects),
] as [(String, Any)]))
