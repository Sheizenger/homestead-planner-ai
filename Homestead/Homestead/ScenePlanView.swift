//
//  ScenePlanView.swift
//  Homestead
//
//  The 3D view, on a real renderer.
//
//  What was here before drew the plan as paths in a `Canvas`: a projection
//  written out by hand, a painter's algorithm, and every roof, wall and tree
//  built from `Path` primitives. It went a long way — further than it had any
//  right to — and it was never going to look like the references, because the
//  references are lit, shadowed, textured meshes and that is not a thing you
//  can approximate with filled polygons.
//
//  So: SceneKit, an orthographic camera, and 381 CC0 meshes. This file is
//  deliberately the smallest part of the change. Everything decidable without
//  a GPU — which mesh, how big, facing where, standing on what — is decided in
//  `SceneBuilder`, in HomesteadCore, under test on Linux. What is left here is
//  walking a list and handing it to SceneKit, because this is the one layer
//  that cannot be compiled, run or checked anywhere but on a Mac.
//

import SwiftUI
import SceneKit
import HomesteadEngine
import HomesteadCore

struct ScenePlanView: NSViewRepresentable {
    let plot: Plot
    let variant: Variant
    @Binding var camera: Camera3D
    /// Multiplies the framed extent: 1 fits the plot, smaller is closer in.
    @Binding var zoom: Double
    /// Where the camera is looking, as metres from the middle of the plot.
    @Binding var pan: Point
    @Binding var selectedObjectID: String?
    var highlightedObjectIDs: Set<String> = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        // The camera is driven by the app's own orbit gesture, which already
        // knows how to hold the site still while it turns. SceneKit's built-in
        // control would fight it and would also give a perspective camera.
        view.allowsCameraControl = false
        view.rendersContinuously = false

        let root = view.scene!.rootNode
        root.addChildNode(context.coordinator.contentNode)
        root.addChildNode(context.coordinator.cameraNode)
        root.addChildNode(context.coordinator.sunNode)
        root.addChildNode(context.coordinator.fillNode)
        view.pointOfView = context.coordinator.cameraNode

        let click = NSClickGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleClick(_:))
        )
        view.addGestureRecognizer(click)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuildIfNeeded(plot: plot, variant: variant)
        context.coordinator.apply(camera: camera, zoom: zoom, pan: pan)
        context.coordinator.highlight(selectedObjectID, others: highlightedObjectIDs)
        view.setNeedsDisplay(view.bounds)
    }

    // MARK: -

    final class Coordinator: NSObject {
        var parent: ScenePlanView
        weak var view: SCNView?

        let contentNode = SCNNode()
        let cameraNode = SCNNode()
        let sunNode = SCNNode()
        let fillNode = SCNNode()

        /// The middle of the plot. `apply` orbits around this plus the pan.
        /// What the scene was last built from. Rebuilding on every frame would
        /// reload every mesh on every redraw of a view that redraws whenever
        /// the camera moves.
        private var builtFrom: (objects: [PlanObject], boundary: [Point], waterfront: Waterfront?)?
        private var radius: Double = 30
        private var pivot = Vector3.zero
        private var highlighted: Set<String> = []

        init(_ parent: ScenePlanView) {
            self.parent = parent
            super.init()

            let camera = SCNCamera()
            // Orthographic, because this is a plan. A perspective camera makes
            // the far end of a plot smaller than the near end, which is the
            // one thing a site drawing may not do.
            camera.usesOrthographicProjection = true
            camera.zNear = 1
            camera.zFar = 4000
            cameraNode.camera = camera

            let sun = SCNLight()
            sun.type = .directional
            sun.castsShadow = true
            sun.shadowMode = .deferred
            sun.shadowSampleCount = 8
            sun.shadowRadius = 4
            sun.shadowColor = NSColor(white: 0, alpha: 0.38)
            sun.color = NSColor(calibratedWhite: 1.0, alpha: 1)
            sun.intensity = 1100
            // The shadow map covers the site rather than the frustum, so the
            // far end of a large plot is not left unshadowed.
            sun.automaticallyAdjustsShadowProjection = true
            sunNode.light = sun

            let fill = SCNLight()
            fill.type = .ambient
            fill.intensity = 620
            fill.color = NSColor(calibratedRed: 0.86, green: 0.90, blue: 1.0, alpha: 1)
            fillNode.light = fill
        }

        // MARK: Building

        func rebuildIfNeeded(plot: Plot, variant: Variant) {
            let signature = (variant.objects, plot.boundary, plot.waterfront)
            if let built = builtFrom,
               built.objects == signature.0,
               built.boundary == signature.1,
               built.waterfront == signature.2 {
                return
            }
            builtFrom = signature

            contentNode.childNodes.forEach { $0.removeFromParentNode() }
            let scene = SceneBuilder.build(plot: plot, variant: variant)
            for slab in scene.slabs { contentNode.addChildNode(SceneAssembly.node(for: slab)) }
            for solid in scene.solids { contentNode.addChildNode(SceneAssembly.node(for: solid)) }
            for mesh in scene.meshes {
                if let node = SceneAssembly.node(for: mesh) { contentNode.addChildNode(node) }
            }

            // What the camera orbits and how much of the world it has to fit.
            if let bounds = plot.bounds {
                pivot = Vector3(x: bounds.midX, y: 2, z: bounds.midY)
                radius = max(bounds.width, bounds.height)
            }
        }

        // MARK: Camera and light

        func apply(camera: Camera3D, zoom: Double, pan: Point) {
            let pivot = Vector3(x: self.pivot.x + pan.x, y: self.pivot.y, z: self.pivot.z + pan.y)
            let toCamera = camera.toCamera
            // The engine's Z is the scene's Y; see `Vector3`.
            let direction = SCNVector3(toCamera.x, toCamera.z, toCamera.y)
            let distance = CGFloat(radius * 2.5 + 40)
            cameraNode.position = SCNVector3(
                CGFloat(pivot.x) + direction.x * distance,
                CGFloat(pivot.y) + direction.y * distance,
                CGFloat(pivot.z) + direction.z * distance
            )
            cameraNode.look(
                at: SCNVector3(CGFloat(pivot.x), CGFloat(pivot.y), CGFloat(pivot.z)),
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
            // Orthographic scale is half the vertical extent in world units.
            // Padded, because buildings stand up out of the plot's footprint.
            cameraNode.camera?.orthographicScale = (radius * 0.62 + 6) * max(0.05, zoom)

            // The sun travels with the camera — see `SceneLight`, and the
            // measurement behind it: a fixed sun leaves half of an orbit with
            // both visible walls at ambient.
            let light = SceneLight.following(camera)
            let toSun = SCNVector3(light.toSun.x, light.toSun.z, light.toSun.y)
            let far = CGFloat(radius * 2 + 60)
            sunNode.position = SCNVector3(
                CGFloat(pivot.x) + toSun.x * far,
                CGFloat(pivot.y) + toSun.y * far,
                CGFloat(pivot.z) + toSun.z * far
            )
            sunNode.look(
                at: SCNVector3(CGFloat(pivot.x), 0, CGFloat(pivot.z)),
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
        }

        // MARK: Selection

        func highlight(_ selected: String?, others: Set<String>) {
            let wanted = Set([selected].compactMap { $0 }).union(others)
            guard wanted != highlighted else { return }
            highlighted = wanted
            for node in contentNode.childNodes {
                let isLit = node.value(forKey: SceneAssembly.objectKey)
                    .flatMap { $0 as? String }
                    .map { wanted.contains($0) } ?? false
                SceneAssembly.setHighlighted(node, isLit)
            }
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let view else { return }
            let point = recognizer.location(in: view)
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
            ])
            // The id is on the node the assembler made; a hit lands on a
            // child geometry node somewhere under it.
            var found: String?
            var node = hits.first?.node
            while let current = node, found == nil {
                found = current.value(forKey: SceneAssembly.objectKey) as? String
                node = current.parent
            }
            parent.selectedObjectID = found
        }
    }
}
