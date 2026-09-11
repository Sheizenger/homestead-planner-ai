//
//  BriefEditorView.swift
//  Homestead
//
//  The input side of the product, which the first pass simply didn't have:
//  the app generated from StructuredInputs() defaults — no crops, no
//  animals, no infrastructure — so every plan was house + shed + patio, and
//  all four planning modes produced byte-identical output because three
//  objects leave nothing to trade off. Measured, not guessed: see the
//  commit that added this.
//
//  Every list of terms comes from Sizing's published vocabulary rather than
//  a hardcoded copy here, because the engine silently ignores a term it
//  doesn't know ("chicken" instead of "poultry" yields a plan with no
//  chickens and no error).
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct BriefEditorView: View {
    let model: ProjectModel

    var body: some View {
        Form {
            Section("Plot") {
                LabeledContent("Width") {
                    Stepper(value: plotWidth, in: 10...500, step: 5) {
                        Text("\(Int(plotWidth.wrappedValue)) m")
                    }
                }
                LabeledContent("Depth") {
                    Stepper(value: plotHeight, in: 10...500, step: 5) {
                        Text("\(Int(plotHeight.wrappedValue)) m")
                    }
                }
                Picker("Climate", selection: input(\.climateZone)) {
                    ForEach(ClimateZone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Soil", selection: input(\.soilType)) {
                    ForEach(SoilType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Slope", selection: input(\.terrainSlope)) {
                    ForEach(TerrainSlope.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }

            Section("Household") {
                LabeledContent("People") {
                    Stepper(value: input(\.householdSize), in: 1...20) {
                        Text("\(input(\.householdSize).wrappedValue)")
                    }
                }
                Picker("House size", selection: input(\.houseSizePreset)) {
                    ForEach(HouseSizePreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("House shape", selection: input(\.houseShape)) {
                    ForEach(HouseShape.allCases, id: \.self) { Text($0 == .lshape ? "L-shaped" : "Rectangular").tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Utilitarian ↔ ornamental")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: input(\.aestheticPreference), in: 0...100, step: 5)
                }
            }

            Section("Crops") {
                ForEach(Sizing.cropVocabulary) { term in
                    Toggle(term.label, isOn: membership(term.key, in: \.crops))
                }
            }

            Section("Animals") {
                ForEach(Sizing.animalVocabulary) { term in
                    LabeledContent(term.label) {
                        Stepper(value: animalCount(term.key), in: 0...200, step: 2) {
                            Text("\(animalCount(term.key).wrappedValue)")
                        }
                    }
                }
            }

            Section("Infrastructure") {
                ForEach(Sizing.infrastructureVocabulary) { term in
                    Toggle(term.label, isOn: membership(term.key, in: \.infrastructure))
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings into the model

    /// ProjectModel's document is `private(set)` on purpose — everything goes
    /// through its mutators, so each control gets a binding that reads the
    /// document and writes through `updateStructuredInputs`.
    private func input<T>(_ keyPath: WritableKeyPath<StructuredInputs, T>) -> Binding<T> {
        Binding(
            get: { model.document.brief.structuredInputs[keyPath: keyPath] },
            set: { value in model.updateStructuredInputs { $0[keyPath: keyPath] = value } }
        )
    }

    private func membership(_ key: String, in keyPath: WritableKeyPath<StructuredInputs, [String]>) -> Binding<Bool> {
        Binding(
            get: { model.document.brief.structuredInputs[keyPath: keyPath].contains(key) },
            set: { isOn in
                model.updateStructuredInputs { inputs in
                    if isOn {
                        guard !inputs[keyPath: keyPath].contains(key) else { return }
                        inputs[keyPath: keyPath].append(key)
                    } else {
                        inputs[keyPath: keyPath].removeAll { $0 == key }
                    }
                }
            }
        )
    }

    private func animalCount(_ key: String) -> Binding<Int> {
        Binding(
            get: { model.document.brief.structuredInputs.animals.first { $0.type == key }?.count ?? 0 },
            set: { count in
                model.updateStructuredInputs { inputs in
                    inputs.animals.removeAll { $0.type == key }
                    if count > 0 { inputs.animals.append(AnimalRequest(type: key, count: count)) }
                }
            }
        )
    }

    private var plotWidth: Binding<Double> {
        Binding(
            get: { model.document.plot.bounds?.width ?? 0 },
            set: { width in
                model.updatePlotBoundary(PlotShape.rectangle(width: width, height: model.document.plot.bounds?.height ?? 30))
            }
        )
    }

    private var plotHeight: Binding<Double> {
        Binding(
            get: { model.document.plot.bounds?.height ?? 0 },
            set: { height in
                model.updatePlotBoundary(PlotShape.rectangle(width: model.document.plot.bounds?.width ?? 30, height: height))
            }
        )
    }
}
