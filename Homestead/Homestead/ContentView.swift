//
//  ContentView.swift
//  Homestead
//
//  Brief on the left, plan on the right. Everything reads from ProjectModel
//  — no new logic in the view layer, per AGENTS.md's three-layer split — and
//  every mutation goes through PlanStore.edit, which is what makes undo
//  uniform.
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
    @Bindable var store: PlanStore

    @State private var mode: PlanningMode = .beautyBalanced
    @State private var viewMode: PlanViewMode = .plan
    @State private var showsDimensions = false
    @State private var selectedVariantID: Variant.ID?
    @State private var selectedObjectID: String?
    @State private var selectedWarningID: String?
    @State private var viewport = Viewport()

    private var model: ProjectModel { store.model }

    private var selectedVariant: Variant? {
        guard let id = selectedVariantID else { return nil }
        return model.variant(id)
    }

    private var selectedObject: PlanObject? {
        guard let id = selectedObjectID else { return nil }
        return selectedVariant?.objects.first { $0.id == id }
    }

    /// The objects a selected warning is about. A warning names them by
    /// label; on a plan of fifteen objects that isn't enough to find them.
    private func highlightedObjectIDs(in variant: Variant) -> Set<String> {
        guard let id = selectedWarningID,
              let warning = model.warnings(for: variant.id).first(where: { $0.id == id })
        else { return [] }
        return Set(warning.objectIds)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                BriefEditorView(model: model, edit: store.edit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                generateBar
            }
            // `maxHeight: .infinity` is the load-bearing part. Without it the
            // column sized itself to its content's ideal height and sat
            // centred in the pane, and the form's ideal height resolved to a
            // single row — so the whole brief was one "Width" field with a
            // fifth of the window above and below it, and no scrollbar to
            // suggest there was more.
            .frame(minWidth: 290, idealWidth: 340, maxWidth: 460, maxHeight: .infinity)

            detailPane
                .frame(minWidth: 560, maxHeight: .infinity)
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
        .onChange(of: selectedVariantID) {
            selectedObjectID = nil
            selectedWarningID = nil
        }
        // Opening a file swaps the whole document, so the selection that
        // pointed into the old one has to go with it.
        .onChange(of: model.document.id) {
            selectedVariantID = model.activeVariant?.id
            selectedObjectID = nil
            selectedWarningID = nil
        }
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
                                highlightedObjectIDs: highlightedObjectIDs(in: variant),
                                showsDimensions: showsDimensions,
                                moveObject: { id, delta, committed in
                                    drag(id, by: delta, in: variant.id, committed: committed)
                                }
                            )
                            .transition(.opacity)
                        case .axonometric:
                            SceneViewContainer(
                                plot: model.document.plot,
                                variant: variant,
                                selectedObjectID: $selectedObjectID,
                                highlightedObjectIDs: highlightedObjectIDs(in: variant)
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
                        WarningsListView(
                            warnings: model.warnings(for: variant.id),
                            selectedWarningID: $selectedWarningID,
                            applyFix: { warning in fix(warning, in: variant.id) }
                        )
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

    /// One undo step per fix, labelled with what it did — a plan that moved
    /// on its own is exactly the kind of change you want to be able to take
    /// back in one keystroke.
    private func fix(_ warning: Warning, in variantID: Variant.ID) -> Resolve.Fix? {
        var applied: Resolve.Fix?
        store.edit(warning.suggestedFix?.label ?? "Fix Warning") {
            applied = model.applyFix(for: warning, in: variantID)
        }
        return applied
    }

    /// Live movement applies straight to the model; the undo step is opened
    /// once at the start of the gesture and closed once at its end, so a drag
    /// undoes as one action rather than as sixty.
    private func drag(_ objectID: String, by delta: Point, in variantID: Variant.ID, committed: Bool) {
        if committed {
            store.endInteractiveEdit("Move Object")
            return
        }
        store.beginInteractiveEdit()
        guard let object = model.variant(variantID)?.objects.first(where: { $0.id == objectID }) else { return }
        var transform = object.transform
        transform.x += delta.x
        transform.y += delta.y
        model.moveObject(objectID, in: variantID, to: transform)
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
        var newID: Variant.ID?
        store.edit("Generate Plan") {
            let id = model.generateVariant(mode: mode, seed: Int.random(in: 0..<1_000_000))
            model.setActiveVariant(id)
            newID = id
        }
        if let newID {
            selectedVariantID = newID
            selectedObjectID = nil
        }
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

            Button {
                store.edit("Rotate Object") { model.rotateObject90(object.id, in: variant.id) }
            } label: {
                Label("Rotate", systemImage: "rotate.right")
            }
            Button {
                store.edit(object.locked ? "Unlock Object" : "Lock Object") {
                    model.toggleLock(object.id, in: variant.id)
                }
            } label: {
                Label(object.locked ? "Unlock" : "Lock", systemImage: object.locked ? "lock.open" : "lock")
            }
            Button(role: .destructive) {
                store.edit("Delete Object") { _ = model.deleteObjects([object.id], in: variant.id) }
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
                store.edit("Resize Object") {
                    model.resizeObject(object.id, in: variant.id, to: transform)
                }
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
    ContentView(store: PlanStore())
}
