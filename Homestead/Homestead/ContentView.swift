//
//  ContentView.swift
//  Homestead
//
//  Generate a plan, switch between variants, pan/zoom it, select an object,
//  read its warnings. Everything here reads from ProjectModel — no new logic
//  in the view layer, per AGENTS.md's three-layer split.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct ContentView: View {
    @State private var model = ProjectModel(document: .blank(name: "My Homestead", widthM: 60, heightM: 45))
    @State private var mode: PlanningMode = .beautyBalanced
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
        NavigationSplitView {
            List(model.document.variants, selection: $selectedVariantID) { variant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.strategyLabel).font(.headline)
                    Text("\(variant.objects.count) objects").font(.caption).foregroundStyle(.secondary)
                }
                .tag(variant.id)
            }
            .navigationTitle("Variants")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            Group {
                if let variant = selectedVariant {
                    VSplitView {
                        PlanCanvasView(
                            plot: model.document.plot,
                            variant: variant,
                            viewport: $viewport,
                            selectedObjectID: $selectedObjectID
                        )
                        .frame(minHeight: 320)

                        VStack(spacing: 0) {
                            if let object = selectedObject {
                                selectionBar(for: object, in: variant)
                                Divider()
                            }
                            WarningsListView(warnings: model.warnings(for: variant.id))
                        }
                        .frame(minHeight: 140, idealHeight: 200)
                    }
                } else {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "sparkles",
                        description: Text("Pick a mode and press Generate.")
                    )
                }
            }
            .toolbar {
                ToolbarItem {
                    Picker("Mode", selection: $mode) {
                        ForEach(PlanningMode.allCases, id: \.self) { mode in
                            Text(label(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem {
                    Button {
                        let id = model.generateVariant(mode: mode, seed: Int.random(in: 0..<1_000_000))
                        model.setActiveVariant(id)
                        selectedVariantID = id
                        selectedObjectID = nil
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
            }
        }
        .onAppear { selectedVariantID = model.activeVariant?.id }
        .onChange(of: selectedVariantID) { selectedObjectID = nil }
    }

    @ViewBuilder
    private func selectionBar(for object: PlanObject, in variant: Variant) -> some View {
        HStack(spacing: 12) {
            Text(object.label).font(.headline)
            Text("\(Int(object.transform.width.rounded())) × \(Int(object.transform.height.rounded())) m")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.rotateObject90(object.id, in: variant.id)
            } label: {
                Label("Rotate", systemImage: "rotate.right")
            }

            Button {
                model.toggleLock(object.id, in: variant.id)
            } label: {
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

    private func label(for mode: PlanningMode) -> String {
        switch mode {
        case .productionMax: return "Production"
        case .minimumMaintenance: return "Low-maintenance"
        case .beautyBalanced: return "Balanced"
        case .safetyFirst: return "Safety-first"
        }
    }
}

#Preview {
    ContentView()
}
