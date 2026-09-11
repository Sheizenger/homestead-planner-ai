//
//  PlanCanvasView.swift
//  Homestead
//
//  Draws one variant's plot boundary, placed objects, paths and fences in a
//  single Canvas — the whole scene in one call, per AGENTS.md's settled
//  decision, not ~300 individual views. World coordinates (Double, metres)
//  are converted to screen coordinates (CGFloat) via a uniform scale-to-fit
//  with the plot centred; no axis flip, since the engine's own +Y (south)
//  convention already matches SwiftUI's downward-growing Y.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct PlanCanvasView: View {
    let plot: Plot
    let variant: Variant

    var body: some View {
        Canvas { context, size in
            guard let bounds = plot.bounds, bounds.width > 0, bounds.height > 0 else { return }
            let boundsWidth = CGFloat(bounds.width)
            let boundsHeight = CGFloat(bounds.height)
            let boundsMinX = CGFloat(bounds.minX)
            let boundsMinY = CGFloat(bounds.minY)
            let padding: CGFloat = 24
            let scale = min(
                (size.width - padding * 2) / boundsWidth,
                (size.height - padding * 2) / boundsHeight
            )
            let offsetX = (size.width - boundsWidth * scale) / 2
            let offsetY = (size.height - boundsHeight * scale) / 2

            func project(_ point: Point) -> CGPoint {
                CGPoint(
                    x: (CGFloat(point.x) - boundsMinX) * scale + offsetX,
                    y: (CGFloat(point.y) - boundsMinY) * scale + offsetY
                )
            }

            var boundaryPath = Path()
            boundaryPath.addLines(plot.boundary.map(project))
            boundaryPath.closeSubpath()
            context.fill(boundaryPath, with: .color(Color(white: 0.97)))
            context.stroke(boundaryPath, with: .color(.secondary), lineWidth: 1.5)

            for fence in variant.fences {
                var path = Path()
                path.addLines(fence.points.map(project))
                context.stroke(path, with: .color(.brown), style: StrokeStyle(lineWidth: 1.5, dash: fence.gated ? [4, 3] : []))
            }

            for pathEntity in variant.paths {
                var path = Path()
                path.addLines(pathEntity.points.map(project))
                context.stroke(path, with: .color(Color(white: 0.6)), lineWidth: max(1, CGFloat(pathEntity.widthM) * scale))
            }

            for object in variant.objects {
                var shape = Path()
                let corners = object.transform.corners.map(project)
                shape.addLines(corners)
                shape.closeSubpath()
                context.fill(shape, with: .color(color(for: object.category).opacity(object.locked ? 0.4 : 0.75)))
                context.stroke(shape, with: .color(object.locked ? .secondary : color(for: object.category)), lineWidth: object.locked ? 1 : 1.5)

                let center = project(object.transform.center)
                context.draw(
                    Text(object.label).font(.system(size: 9)).foregroundColor(.black),
                    at: center
                )
            }
        }
        .background(Color(white: 0.99))
    }

    private func color(for category: ObjectCategory) -> Color {
        switch category {
        case .residential: return .orange
        case .access: return .gray
        case .foodAnnual: return .green
        case .foodPerennial: return Color(red: 0.1, green: 0.4, blue: 0.1)
        case .greenhouse: return .mint
        case .animal: return .brown
        case .utility: return .blue
        case .water: return .cyan
        case .energy: return .yellow
        case .storage: return Color(white: 0.5)
        case .leisure: return .purple
        case .futureExpansion: return Color(white: 0.85)
        case .fence, .path: return .secondary
        }
    }
}
