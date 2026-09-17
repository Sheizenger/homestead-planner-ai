//
//  SceneAssembly.swift
//  Homestead
//
//  `Scene3D` to SceneKit nodes. Mechanical on purpose: this is the layer that
//  cannot be compiled or tested anywhere but on a Mac, so it gets as few
//  decisions as possible. Everything about *what* the scene contains is
//  decided in `SceneBuilder`, under test.
//

import SwiftUI
import SceneKit
import HomesteadEngine
import HomesteadCore

enum SceneAssembly {
    /// A node's `name` is the plan object it belongs to, or nil for scenery.
    ///
    /// Stashing it under a custom KVC key would read better and relies on
    /// SCNNode accepting keys it does not declare — an idiom rather than a
    /// guarantee, and this is the one layer that cannot be compiled or run
    /// anywhere but on a Mac. The mesh's own id is never read back, so `name`
    /// is free to carry the thing that is.

    // MARK: - Meshes

    /// Loaded meshes, by `kit/name`.
    ///
    /// A plan is a hundred and thirty meshes drawn from maybe thirty distinct
    /// files, and a scene is rebuilt whenever the plan changes. Reading an OBJ
    /// off disk for every copy of every tree would make editing unusable, so
    /// each file is read once and cloned after that — SceneKit clones share
    /// geometry, so a hundred fence panels cost one mesh.
    private static var cache: [String: SCNNode] = [:]

    static func node(for mesh: SceneNode) -> SCNNode? {
        guard let prototype = geometry(named: mesh.model) else { return nil }
        let node = prototype.clone()
        node.name = mesh.objectId
        node.position = SCNVector3(
            CGFloat(mesh.position.x), CGFloat(mesh.position.y), CGFloat(mesh.position.z)
        )
        node.scale = SCNVector3(CGFloat(mesh.scale.x), CGFloat(mesh.scale.y), CGFloat(mesh.scale.z))
        // Tilt first, then turn: the order `SceneBuilder` assumes, and the
        // only thing that tilts is a solar panel.
        node.eulerAngles = SCNVector3(CGFloat(mesh.pitch), CGFloat(mesh.yaw), 0)
        if let tint = mesh.tint {
            apply(tint: tint, to: node)
        }
        node.castsShadow = true
        return node
    }

    /// One kit's meshes share one atlas and one material, which is what makes
    /// a scene this size cheap. Cloning preserves that.
    private static func geometry(named model: String) -> SCNNode? {
        if let cached = cache[model] { return cached }
        // `kit/name` is the logical key, but the file is `kit_name.obj` and it
        // sits at the top of the resource directory: Xcode copies a resource to
        // `Contents/Resources/<basename>`, so the directory it occupies in the
        // repository is not a directory in the bundle.
        guard let url = Bundle.main.url(
            forResource: model.replacingOccurrences(of: "/", with: "_"),
            withExtension: "obj"
        ),
            let scene = try? SCNScene(url: url, options: [
                .createNormalsIfAbsent: true,
                .convertToYUp: false,
            ])
        else {
            return nil
        }
        // The OBJ arrives as a scene with the mesh somewhere under its root.
        // Flattening gives one node with one geometry, which is what the
        // clone-per-copy scheme wants.
        let node = scene.rootNode.flattenedClone()
        for material in node.geometry?.materials ?? [] {
            // Flat, unlit-looking shading: these kits are modelled to read as
            // colour, not as plastic. A specular highlight on a low-poly roof
            // is what makes a stylised scene look like a botched realistic one.
            material.lightingModel = .lambert
            material.specular.contents = NSColor.black
            material.isDoubleSided = false
            material.diffuse.mipFilter = .linear
            // These atlases are 12 KB of flat colour swatches; interpolating
            // between them bleeds one swatch into the next along every seam.
            material.diffuse.magnificationFilter = .nearest
        }
        cache[model] = node
        return node
    }

    private static func apply(tint: Int, to node: SCNNode) {
        let colour = NSColor(
            calibratedRed: CGFloat((tint >> 16) & 255) / 255,
            green: CGFloat((tint >> 8) & 255) / 255,
            blue: CGFloat(tint & 255) / 255,
            alpha: 1
        )
        // The mesh has to stop sharing the kit's material, or tinting one barn
        // tints every building in the plan.
        node.geometry = node.geometry?.copy() as? SCNGeometry
        node.geometry?.materials = (node.geometry?.materials ?? []).map { shared in
            guard let material = shared.copy() as? SCNMaterial else { return shared }
            // Multiply rather than replace: the atlas keeps its own light and
            // shade and the tint recolours it, so windows and doors survive.
            material.multiply.contents = colour
            return material
        }
    }

    // MARK: - Built geometry

    /// A flat polygon — ground, paving, a path, the surface of water.
    static func node(for slab: SceneSlab) -> SCNNode {
        let shape = SCNShape(path: bezier(slab.polygon), extrusionDepth: max(0.01, CGFloat(slab.thickness)))
        shape.chamferRadius = 0
        let material = SCNMaterial()
        material.diffuse.contents = colour(slab.colour)
        material.lightingModel = .lambert
        material.specular.contents = NSColor.black
        shape.materials = [material]

        let node = SCNNode(geometry: shape)
        // `SCNShape` extrudes a path in the XY plane along +Z; a slab lies in
        // the ground plane, so it is laid down and pushed to its own top.
        node.eulerAngles = SCNVector3(CGFloat(GroundPlane.pitch), 0, 0)
        node.position = SCNVector3(0, CGFloat(slab.top), 0)
        node.castsShadow = slab.thickness > 0.05
        node.name = slab.objectId
        return node
    }

    /// A built volume: walls up from the footprint, then a lid or a ridge.
    static func node(for solid: SceneSolid) -> SCNNode {
        let group = SCNNode()
        group.name = solid.objectId

        let walls = SCNShape(path: bezier(solid.polygon), extrusionDepth: max(0.05, CGFloat(solid.wallHeight)))
        walls.chamferRadius = 0
        walls.materials = [material(solid.colour, opacity: solid.opacity)]
        let wallNode = SCNNode(geometry: walls)
        wallNode.eulerAngles = SCNVector3(CGFloat(GroundPlane.pitch), 0, 0)
        wallNode.position = SCNVector3(0, CGFloat(solid.base + solid.wallHeight), 0)
        wallNode.castsShadow = true
        group.addChildNode(wallNode)

        guard solid.ridgeRise > 0.01, let box = Rect(bounding: solid.polygon) else {
            let lid = SCNShape(path: bezier(solid.polygon), extrusionDepth: 0.05)
            lid.materials = [material(solid.colour, opacity: solid.opacity)]
            let lidNode = SCNNode(geometry: lid)
            lidNode.eulerAngles = SCNVector3(CGFloat(GroundPlane.pitch), 0, 0)
            lidNode.position = SCNVector3(0, CGFloat(solid.base + solid.wallHeight + 0.05), 0)
            group.addChildNode(lidNode)
            return group
        }

        // A ridged top, as four triangles over the footprint's bounding box.
        let eaves = solid.base + solid.wallHeight
        let apex = eaves + solid.ridgeRise
        let alongX = box.width >= box.height
        let corners = [
            SCNVector3(CGFloat(box.minX), CGFloat(eaves), CGFloat(box.minY)),
            SCNVector3(CGFloat(box.maxX), CGFloat(eaves), CGFloat(box.minY)),
            SCNVector3(CGFloat(box.maxX), CGFloat(eaves), CGFloat(box.maxY)),
            SCNVector3(CGFloat(box.minX), CGFloat(eaves), CGFloat(box.maxY)),
        ]
        let ridgeA: SCNVector3
        let ridgeB: SCNVector3
        if alongX {
            ridgeA = SCNVector3(CGFloat(box.minX), CGFloat(apex), CGFloat(box.midY))
            ridgeB = SCNVector3(CGFloat(box.maxX), CGFloat(apex), CGFloat(box.midY))
        } else {
            ridgeA = SCNVector3(CGFloat(box.midX), CGFloat(apex), CGFloat(box.minY))
            ridgeB = SCNVector3(CGFloat(box.midX), CGFloat(apex), CGFloat(box.maxY))
        }
        let vertices: [SCNVector3]
        if alongX {
            vertices = [
                corners[0], corners[1], ridgeB, corners[0], ridgeB, ridgeA,
                corners[3], ridgeA, ridgeB, corners[3], ridgeB, corners[2],
                corners[0], ridgeA, corners[3],
                corners[1], corners[2], ridgeB,
            ]
        } else {
            vertices = [
                corners[0], ridgeA, ridgeB, corners[0], ridgeB, corners[3],
                corners[1], corners[2], ridgeB, corners[1], ridgeB, ridgeA,
                corners[0], corners[1], ridgeA,
                corners[3], ridgeB, corners[2],
            ]
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: Array(Int32(0)..<Int32(vertices.count)), primitiveType: .triangles
        )
        let roof = SCNGeometry(sources: [source], elements: [element])
        roof.materials = [material(solid.colour, opacity: solid.opacity)]
        let roofNode = SCNNode(geometry: roof)
        roofNode.castsShadow = true
        group.addChildNode(roofNode)
        return group
    }

    // MARK: - Selection

    static func setHighlighted(_ node: SCNNode, _ isLit: Bool) {
        let colour = isLit ? NSColor.systemOrange : NSColor.clear
        node.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                material.emission.contents = colour
                material.emission.intensity = isLit ? 0.32 : 0
            }
        }
    }

    // MARK: -

    /// The path a slab is built from, in the coordinates the quarter turn in
    /// `node(for:)` expects — see `GroundPlane`, which owns that arithmetic
    /// and is tested on it. Taken straight across, a path comes out laid down
    /// on the far side of the origin from every mesh.
    private static func bezier(_ polygon: [Point]) -> NSBezierPath {
        let path = NSBezierPath()
        let points = GroundPlane.path(polygon)
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.line(to: CGPoint(x: point.x, y: point.y))
        }
        path.close()
        return path
    }

    private static func colour(_ hex: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: 1
        )
    }

    private static func material(_ hex: Int, opacity: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = colour(hex)
        material.lightingModel = .lambert
        material.specular.contents = NSColor.black
        material.isDoubleSided = true
        if opacity < 1 {
            material.transparency = CGFloat(opacity)
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
        }
        return material
    }
}
