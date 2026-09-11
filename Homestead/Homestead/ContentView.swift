//
//  ContentView.swift
//  Homestead
//
//  The app's first real screen: generate a plan, switch between variants,
//  see it drawn, see its warnings. Everything here reads from ProjectModel —
//  no new logic in the view layer, per AGENTS.md's three-layer split.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct ContentView: View {
    @State private var model = ProjectModel(document: .blank(name: "My Homestead", widthM: 60, heightM: 45))
    @State private var mode: PlanningMode = .beautyBalanced
    @State private var selectedVariantID: Variant.ID?

    private var selectedVariant: Variant? {
        guard let id = selectedVariantID else { return nil }
        return model.variant(id)
    }

    var body: some View {
        NavigationSplitView {
            List(model.document.variants, selection: $selectedVariantID) { variant in
                VStack(alignment: .leading) {
                    Text(variant.strategyLabel).font(.headline)
                    Text("\(variant.objects.count) objects").font(.caption).foregroundStyle(.secondary)
                }
                .tag(variant.id)
            }
            .navigationTitle("Variants")
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
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
            }
        } detail: {
            if let variant = selectedVariant {
                VSplitView {
                    PlanCanvasView(plot: model.document.plot, variant: variant)
                        .frame(minHeight: 300)
                    WarningsListView(warnings: model.warnings(for: variant.id))
                        .frame(minHeight: 120, idealHeight: 180)
                }
            } else {
                ContentUnavailableView(
                    "No plan yet",
                    systemImage: "sparkles",
                    description: Text("Pick a mode and press Generate.")
                )
            }
        }
        .onAppear {
            selectedVariantID = model.activeVariant?.id
        }
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
