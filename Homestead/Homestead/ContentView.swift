//
//  ContentView.swift
//  Homestead
//
//  Brief on the left, plan on the right. Everything reads from ProjectModel
//  — no new logic in the view layer, per AGENTS.md's three-layer split.
//
//  Laid out with HSplitView rather than NavigationSplitView: on macOS the
//  latter's default style floats the sidebar over the detail column, which
//  put the brief on top of the plan.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

enum PlanViewMode: String, CaseIterable, Identifiable {
    case plan, axonometric
    var id: String { rawValue }

    var label: String { self == .plan ? "Plan" : "3D" }
    var symbol: String { self == .plan ? "square.grid.2x2" : "cube" }
}

struct ContentView: View {
    @State private var model = ProjectModel(document: .blank(name: "My Homestead", widthM: 60, heightM: 45))
    @State private var mode: PlanningMode = .beautyBalanced
    @State private var viewMode: PlanViewMode = .plan
    @State private var showsDimensions = false
    @State private var selectedVariantID: Variant.ID?
    @State private var selectedObjectID: String?
    @State private var viewport = Viewport()

    private var selectedVariant: Variant? {
        guard let id = selectedVariantID else { return nil }
        return model.variant(id)
    }

    private var selectedObject: PlanObject? {
        guard let id = selectedObjectID else { return nil }
        return selectedVariant?.objects.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                BriefEditorView(model: model)
                Divider()
                generateBar
            }
            .frame(minWidth: 290, idealWidth: 320, maxWidth: 420)

            detailPane
                .frame(minWidth: 560)
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode.animation(.easeInOut(duration: 0.25))) {
                    ForEach(PlanViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Toggle(isOn: $showsDimensions) {
                    Label("Dimensions", systemImage: "ruler")
                }
                .toggleStyle(.button)
            }
            if !model.document.variants.isEmpty {
                ToolbarItem {
                    Picker("Variant", selection: $selectedVariantID) {
                        ForEach(model.document.variants) { variant in
                            Text(variant.strategyLabel).tag(variant.id as Variant.ID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .onAppear { selectedVariantID = model.activeVariant?.id }
        .onChange(of: selectedVariantID) { selectedObjectID = nil }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let variant = selectedVariant {
            VStack(spacing: 0) {
                if model.isStale(variant.id) { staleBanner }
                VSplitView {
                    ZStack {
                        switch viewMode {
                        case .plan:
                            PlanCanvasView(
                                plot: model.document.plot,
                                variant: variant,
                                viewport: $viewport,
                                selectedObjectID: $selectedObjectID,
                                showsDimensions: showsDimensions
                            )
                            .transition(.opacity)
                        case .axonometric:
                            AxonometricPlanView(
                                plot: model.document.plot,
                                variant: variant,
                                viewport: $viewport,
                                selectedObjectID: $selectedObjectID,
                                showsDimensions: showsDimensions
                            )
                            .transition(.opacity)
                        }
                    }
                    .frame(minHeight: 320)

                    VStack(spacing: 0) {
                        if let object = selectedObject {
                            selectionBar(for: object, in: variant)
                            Divider()
                        }
                        WarningsListView(warnings: model.warnings(for: variant.id))
                    }
                    .frame(minHeight: 150, idealHeight: 210)
                }
            }
        } else {
            ContentUnavailableView(
                "No plan yet",
                systemImage: "sparkles",
                description: Text("Describe the homestead on the left, then press Generate.")
            )
        }
    }

    private var generateBar: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(PlanningMode.allCases, id: \.self) { mode in
                    Text(label(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                generate()
            } label: {
                Label("Generate", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .keyboardShortcut("g", modifiers: .command)
            .controlSize(.large)
        }
        .padding(12)
        .background(.bar)
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("The brief changed since this plan was generated.")
            Spacer()
            Button("Regenerate") { generate() }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func generate() {
        let id = model.generateVariant(mode: mode, seed: Int.random(in: 0..<1_000_000))
        model.setActiveVariant(id)
        selectedVariantID = id
        selectedObjectID = nil
    }

    @ViewBuilder
    private func selectionBar(for object: PlanObject, in variant: Variant) -> some View {
        HStack(spacing: 14) {
            Label(object.label, systemImage: ObjectSymbols.name(for: object))
                .font(.headline)

            HStack(spacing: 4) {
                Text("W").font(.caption).foregroundStyle(.secondary)
                Stepper(value: dimension(of: object, in: variant, axis: .width), in: 1...120, step: 0.5) {
                    Text("\(object.transform.width, specifier: "%.1f") m").monospacedDigit()
                }
                Text("D").font(.caption).foregroundStyle(.secondary)
                Stepper(value: dimension(of: object, in: variant, axis: .height), in: 1...120, step: 0.5) {
                    Text("\(object.transform.height, specifier: "%.1f") m").monospacedDigit()
                }
            }
            .font(.callout)

            Spacer()

            Button { model.rotateObject90(object.id, in: variant.id) } label: {
                Label("Rotate", systemImage: "rotate.right")
            }
            Button { model.toggleLock(object.id, in: variant.id) } label: {
                Label(object.locked ? "Unlock" : "Lock", systemImage: object.locked ? "lock.open" : "lock")
            }
            Button(role: .destructive) {
                _ = model.deleteObjects([object.id], in: variant.id)
                selectedObjectID = nil
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private enum Axis { case width, height }

    /// Resizing goes through ProjectModel.resizeObject like every other edit,
    /// clamped to the catalog's own minimum for that type so a stepper can't
    /// shrink a well below the size the engine considers buildable.
    private func dimension(of object: PlanObject, in variant: Variant, axis: Axis) -> Binding<Double> {
        Binding(
            get: { axis == .width ? object.transform.width : object.transform.height },
            set: { newValue in
                let minimum = ObjectLibrary[object.typeId]?.minimumSize
                let floorValue = axis == .width ? (minimum?.width ?? 1) : (minimum?.height ?? 1)
                let clamped = max(floorValue, newValue)
                var transform = object.transform
                if axis == .width { transform.width = clamped } else { transform.height = clamped }
                model.resizeObject(object.id, in: variant.id, to: transform)
            }
        )
    }

    private func label(for mode: PlanningMode) -> String {
        switch mode {
        case .productionMax: return "Production"
        case .minimumMaintenance: return "Low-upkeep"
        case .beautyBalanced: return "Balanced"
        case .safetyFirst: return "Safety"
        }
    }
}

#Preview {
    ContentView()
}
