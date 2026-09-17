//
//  SceneViewContainer.swift
//  Homestead
//
//  The 3D tab: a SceneKit view, the gestures that drive it, and the chrome
//  around it.
//
//  Drag orbits. That is a change from the old view, where drag panned and
//  rotation was hidden behind a modifier — reasonable when the view barely
//  turned, wrong now that turning it is the point. Panning moves to ⌥-drag,
//  where it is the rarer gesture.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct SceneViewContainer: View {
    let plot: Plot
    let variant: Variant
    @Binding var selectedObjectID: String?
    var highlightedObjectIDs: Set<String> = []

    @State private var camera = Camera3D()
    @State private var zoom: Double = 1
    @State private var pan = Point(x: 0, y: 0)

    @State private var cameraAnchor = Camera3D()
    @State private var panAnchor = Point(x: 0, y: 0)
    @State private var dragKind: DragKind?
    @State private var magnifyAnchor: CGFloat = 1
    @State private var panModifierHeld = false

    private enum DragKind { case orbit, pan }

    /// Radians per point of drag: a full turn in a little over half a canvas
    /// width, the whole usable range of elevation in about a third of its
    /// height.
    private static let yawPerPoint = 2 * Double.pi / 640
    private static let pitchPerPoint = (Camera3D.maxPitch - Camera3D.minPitch) / 340
    private static let compassRadius: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            ScenePlanView(
                plot: plot,
                variant: variant,
                camera: $camera,
                zoom: $zoom,
                pan: $pan,
                selectedObjectID: $selectedObjectID,
                highlightedObjectIDs: highlightedObjectIDs
            )
            .overlay(alignment: .topTrailing) { compass }
            .overlay(alignment: .bottomTrailing) { controls }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let kind = dragKind ?? begin(at: value.startLocation, in: geometry.size)
                        switch kind {
                        case .orbit:
                            camera = cameraAnchor.turned(
                                byYaw: Double(value.translation.width) * Self.yawPerPoint,
                                pitch: Double(value.translation.height) * Self.pitchPerPoint
                            )
                        case .pan:
                            // Screen right is the camera's own right on the
                            // ground; screen down is further into the scene.
                            let metresPerPoint = 0.06 * zoom * 40
                            let right = Point(x: cos(camera.yaw), y: sin(camera.yaw))
                            let away = Point(x: -sin(camera.yaw), y: cos(camera.yaw))
                            let dx = -Double(value.translation.width) / 400 * metresPerPoint
                            let dy = -Double(value.translation.height) / 400 * metresPerPoint
                                / max(0.2, sin(camera.pitch))
                            pan = Point(
                                x: panAnchor.x + right.x * dx + away.x * dy,
                                y: panAnchor.y + right.y * dx + away.y * dy
                            )
                        }
                    }
                    .onEnded { _ in dragKind = nil }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let factor = value.magnification / magnifyAnchor
                        magnifyAnchor = value.magnification
                        zoom = min(2.5, max(0.08, zoom / Double(factor)))
                    }
                    .onEnded { _ in magnifyAnchor = 1 }
            )
            .onModifierKeysChanged(mask: .option) { _, held in
                panModifierHeld = held.contains(.option)
            }
        }
    }

    private func begin(at start: CGPoint, in size: CGSize) -> DragKind {
        let kind: DragKind = panModifierHeld ? .pan : .orbit
        dragKind = kind
        cameraAnchor = camera
        panAnchor = pan
        return kind
    }

    // MARK: - Chrome

    /// The compass is also the reset: every map app puts the bearing there and
    /// puts it back when you click it.
    private var compass: some View {
        Button {
            camera = Camera3D()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(camera.isIsometric ? 0.25 : 0.5), lineWidth: 1)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.radians(-camera.yaw - .pi / 4))
                Text("N")
                    .font(.system(size: 9, weight: .semibold))
                    .offset(y: -Self.compassRadius - 3)
                    .rotationEffect(.radians(-camera.yaw - .pi / 4))
            }
            .frame(width: Self.compassRadius * 2, height: Self.compassRadius * 2)
        }
        .buttonStyle(.plain)
        .help(camera.isIsometric ? "North" : "Click to face north again")
        .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Button { zoom = max(0.08, zoom / 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
            Button { zoom = min(2.5, zoom * 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { zoom = 1; pan = Point(x: 0, y: 0) } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Fit the plot to the window")

            Divider().frame(width: 26)

            Button { camera = camera.turned(byYaw: -.pi / 4) } label: { Image(systemName: "rotate.left") }
                .help("Turn the view 45° anticlockwise")
            Button { camera = camera.turned(byYaw: .pi / 4) } label: { Image(systemName: "rotate.right") }
                .help("Turn the view 45° clockwise")
        }
        .buttonStyle(.bordered)
        .padding(12)
    }
}
