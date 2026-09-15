//
//  PlotEditorView.swift
//  Homestead
//
//  The plot's own shape and site conditions. All three of these drive the
//  engine and none of them had any way in:
//
//  - Shape: the plot was always the rectangle PlanDocument.blank starts with,
//    even though PlotShape has built L-shaped boundaries since stage 2.
//  - Waterfront: without one, Placement drops a requested dock or micro-hydro
//    turbine on the floor (Placement.swift's "nowhere sensible to put it"),
//    so ticking Dock in the infrastructure list produced nothing at all.
//  - Slope: the drainage check that warns about a septic tank uphill of the
//    house needs an elevation to have an opinion about.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct PlotEditorView: View {
    let model: ProjectModel
    let edit: (String, () -> Void) -> Void

    enum Shape: String, CaseIterable, Identifiable {
        case rectangle, lShape
        var id: String { rawValue }
        var label: String { self == .rectangle ? "Rectangle" : "L-shaped" }
    }

    @State private var shape: Shape = .rectangle
    @State private var notchCorner: PlotCorner = .ne
    @State private var notchWidth: Double = 15
    @State private var notchDepth: Double = 12

    // A `Group` of sections, not a bare tuple of them: a custom view that
    // yields several sections into a parent `Form` is flattened reliably this
    // way, and a Form that mis-resolves its content is how the panel collapsed.
    var body: some View {
        Group {
            Section("Plot") {
                // Typed, not just stepped: a 5 m stepper is a slow way to say
                // "37", and there was no way at all to say "eight hundred square
                // metres", which is how plots are actually described and sold.
                LabeledContent("Width") { metreField(plotWidth) }
                LabeledContent("Depth") { metreField(plotDepth) }
                LabeledContent("Area") {
                    HStack(spacing: 6) {
                        TextField("", value: areaBinding, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Text("m²")
                            .foregroundStyle(.secondary)
                        Text(hectareNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Shape", selection: $shape) {
                    ForEach(Shape.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: shape) { applyShape() }

                if shape == .lShape {
                    Picker("Missing corner", selection: $notchCorner) {
                        ForEach(PlotCorner.allCases, id: \.self) { Text(cornerLabel($0)).tag($0) }
                    }
                    .onChange(of: notchCorner) { applyShape() }
                    LabeledContent("Notch width") {
                        Stepper(value: $notchWidth, in: 2...400, step: 1) { Text("\(Int(notchWidth)) m") }
                            .onChange(of: notchWidth) { applyShape() }
                    }
                    LabeledContent("Notch depth") {
                        Stepper(value: $notchDepth, in: 2...400, step: 1) { Text("\(Int(notchDepth)) m") }
                            .onChange(of: notchDepth) { applyShape() }
                    }
                }
            }

            Section("Planning norms") {
                Picker("Region", selection: regulatoryRegion) {
                    ForEach(RegulatoryRegion.allCases, id: \.self) { Text(regionLabel($0)).tag($0) }
                }
                // The engine's own framing, repeated where the choice is made
                // rather than buried in a warning nobody reads until it fires.
                Label(
                    "Planning orientation, not certified compliance — confirm every distance against the current text of the relevant code before building.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Water") {
                Picker("Waterfront", selection: waterfrontType) {
                    Text("None").tag(Optional<WaterfrontType>.none)
                    ForEach(WaterfrontType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(Optional(type))
                    }
                }

                if let waterfront = model.document.plot.waterfront {
                    Picker("Along edge", selection: waterfrontEdge) {
                        ForEach(PlotEdge.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    LabeledContent("Width into plot") {
                        Stepper(value: waterfrontWidth, in: 1...200, step: 1) {
                            Text("\(Int(waterfront.widthM)) m")
                        }
                    }
                    // Micro-hydro needs one of these two to clear its threshold;
                    // without them the turbine gets a "not feasible here" warning
                    // rather than silence.
                    LabeledContent("Flow speed") {
                        Stepper(value: waterfrontFlow, in: 0...6, step: 0.1) {
                            Text("\(waterfront.flowSpeedMps ?? 0, specifier: "%.1f") m/s")
                        }
                    }
                    LabeledContent("Head drop") {
                        Stepper(value: waterfrontDrop, in: 0...50, step: 0.5) {
                            Text("\(waterfront.elevationDropM ?? 0, specifier: "%.1f") m")
                        }
                    }
                }
            }

            Section("Slope") {
                Picker("Highest edge", selection: elevationEdge) {
                    Text("Flat").tag(Optional<PlotEdge>.none)
                    ForEach(PlotEdge.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                if let elevation = model.document.plot.elevation {
                    LabeledContent("Fall across plot") {
                        Stepper(value: elevationDrop, in: 0.5...60, step: 0.5) {
                            Text("\(elevation.dropM, specifier: "%.1f") m")
                        }
                    }
                }
            }
            .onAppear(perform: adoptCurrentShape)
        }
    }

    // MARK: - Shape

    /// The document stores a boundary polygon, not "which shape was chosen",
    /// so the editor recovers the whole setting — shape, corner and notch
    /// size — from the geometry. Reading back only the shape would leave the
    /// notch fields at their defaults, and the next width nudge would rebuild
    /// a saved 20 × 15 notch as 15 × 12.
    private func adoptCurrentShape() {
        switch PlotShape.describe(model.document.plot.boundary) {
        case .rectangle:
            shape = .rectangle
        case let .lShape(notchWidth, notchHeight, corner):
            shape = .lShape
            self.notchWidth = notchWidth
            self.notchDepth = notchHeight
            notchCorner = corner
        case .freeform:
            // Imported or hand-edited geometry: show the controls in their
            // neutral state and touch nothing until the user actually picks
            // a shape, which is the point at which they've asked for it.
            shape = .rectangle
        }
    }

    private func applyShape() {
        let bounds = model.document.plot.bounds
        let boundary = build(width: bounds?.width ?? 60, depth: bounds?.height ?? 45)
        // `adoptCurrentShape` assigns to `shape` on appear, which fires the
        // same `onChange` a real pick does. Comparing the geometry rather than
        // tracking "is this the adoption pass" means the no-op case costs
        // nothing either way: no undo entry, and no variants marked stale for
        // a plot that didn't move.
        guard boundary != model.document.plot.boundary else { return }
        edit("Change Plot Shape") { model.updatePlotBoundary(boundary) }
    }

    /// The shape currently selected, at a given size. Both the shape picker
    /// and the size steppers go through this, so resizing rebuilds whichever
    /// shape the plot actually is — rebuilding a rectangle every time is how
    /// an L-shaped plot would silently square itself off the moment someone
    /// nudged its width.
    private func build(width: Double, depth: Double) -> [Point] {
        switch shape {
        case .rectangle:
            return PlotShape.rectangle(width: width, height: depth)
        case .lShape:
            return PlotShape.lShape(
                width: width,
                height: depth,
                notchWidth: min(notchWidth, width - 1),
                notchHeight: min(notchDepth, depth - 1),
                corner: notchCorner
            )
        }
    }

    private var regulatoryRegion: Binding<RegulatoryRegion> {
        Binding(
            get: { model.document.plot.regulatoryRegion ?? .generic },
            set: { region in
                edit("Change Planning Region") { model.updateRegulatoryRegion(region) }
            }
        )
    }

    private func regionLabel(_ region: RegulatoryRegion) -> String {
        switch region {
        case .generic: return "Generic"
        case .ruSanPiN: return "Russia — SanPiN / SP"
        case .deGeneric: return "Germany — Abstandsflächen"
        case .esGeneric: return "Spain — PGOU"
        }
    }

    private func cornerLabel(_ corner: PlotCorner) -> String {
        switch corner {
        case .nw: return "North-west"
        case .ne: return "North-east"
        case .sw: return "South-west"
        case .se: return "South-east"
        }
    }

    /// Metres, typed or nudged. One control rather than a stepper alone.
    @ViewBuilder
    private func metreField(_ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            Text("m").foregroundStyle(.secondary)
            Stepper("", value: value, in: 5...1000, step: 1).labelsHidden()
        }
    }

    /// Setting the area rescales both sides and keeps the proportions, which
    /// is what someone means by "make it eight hundred square metres" — they
    /// are describing the plot they have, not asking for a particular shape.
    private var areaBinding: Binding<Double> {
        Binding(
            get: {
                let bounds = model.document.plot.bounds
                return (bounds?.width ?? 0) * (bounds?.height ?? 0)
            },
            set: { target in
                guard target > 1, let bounds = model.document.plot.bounds,
                      bounds.width > 0, bounds.height > 0 else { return }
                let factor = (target / (bounds.width * bounds.height)).squareRoot()
                edit("Resize Plot") {
                    resize(
                        width: (bounds.width * factor).rounded(),
                        depth: (bounds.height * factor).rounded()
                    )
                }
            }
        )
    }

    /// Hectares and sotkas alongside the metres, because that is how anyone
    /// buying land talks about it.
    private var hectareNote: String {
        let bounds = model.document.plot.bounds
        let area = (bounds?.width ?? 0) * (bounds?.height ?? 0)
        guard area > 0 else { return "" }
        return String(format: "= %.2f ha · %.1f sotka", area / 10_000, area / 100)
    }

    private var plotWidth: Binding<Double> {
        Binding(
            get: { model.document.plot.bounds?.width ?? 0 },
            set: { width in
                edit("Resize Plot") { resize(width: width, depth: model.document.plot.bounds?.height ?? 30) }
            }
        )
    }

    private var plotDepth: Binding<Double> {
        Binding(
            get: { model.document.plot.bounds?.height ?? 0 },
            set: { depth in
                edit("Resize Plot") { resize(width: model.document.plot.bounds?.width ?? 30, depth: depth) }
            }
        )
    }

    private func resize(width: Double, depth: Double) {
        model.updatePlotBoundary(build(width: width, depth: depth))
    }

    // MARK: - Water and slope

    private var waterfrontType: Binding<WaterfrontType?> {
        Binding(
            get: { model.document.plot.waterfront?.type },
            set: { type in
                edit("Change Waterfront") {
                    guard let type else {
                        model.updateWaterfront(nil)
                        return
                    }
                    let existing = model.document.plot.waterfront
                    model.updateWaterfront(Waterfront(
                        type: type,
                        edge: existing?.edge ?? .north,
                        widthM: existing?.widthM ?? 8,
                        flowSpeedMps: existing?.flowSpeedMps ?? (type == .river ? 1.0 : nil),
                        elevationDropM: existing?.elevationDropM
                    ))
                }
            }
        )
    }

    private func waterfrontBinding<T>(_ keyPath: WritableKeyPath<Waterfront, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { model.document.plot.waterfront?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var waterfront = model.document.plot.waterfront else { return }
                waterfront[keyPath: keyPath] = value
                edit("Change Waterfront") { model.updateWaterfront(waterfront) }
            }
        )
    }

    private var waterfrontEdge: Binding<PlotEdge> { waterfrontBinding(\.edge, default: .north) }
    private var waterfrontWidth: Binding<Double> { waterfrontBinding(\.widthM, default: 8) }

    private var waterfrontFlow: Binding<Double> {
        Binding(
            get: { model.document.plot.waterfront?.flowSpeedMps ?? 0 },
            set: { value in
                guard var waterfront = model.document.plot.waterfront else { return }
                waterfront.flowSpeedMps = value
                edit("Change Waterfront") { model.updateWaterfront(waterfront) }
            }
        )
    }

    private var waterfrontDrop: Binding<Double> {
        Binding(
            get: { model.document.plot.waterfront?.elevationDropM ?? 0 },
            set: { value in
                guard var waterfront = model.document.plot.waterfront else { return }
                waterfront.elevationDropM = value
                edit("Change Waterfront") { model.updateWaterfront(waterfront) }
            }
        )
    }

    private var elevationEdge: Binding<PlotEdge?> {
        Binding(
            get: { model.document.plot.elevation?.highEdge },
            set: { edge in
                edit("Change Slope") {
                    guard let edge else {
                        model.updateElevation(nil)
                        return
                    }
                    model.updateElevation(PlotElevation(
                        highEdge: edge,
                        dropM: model.document.plot.elevation?.dropM ?? 3
                    ))
                }
            }
        )
    }

    private var elevationDrop: Binding<Double> {
        Binding(
            get: { model.document.plot.elevation?.dropM ?? 0 },
            set: { value in
                guard let elevation = model.document.plot.elevation else { return }
                edit("Change Slope") {
                    model.updateElevation(PlotElevation(highEdge: elevation.highEdge, dropM: value))
                }
            }
        )
    }
}
