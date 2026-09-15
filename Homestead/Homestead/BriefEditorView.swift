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
    /// Brief changes are edits like any other, so they go through the same
    /// undo-registering wrapper the canvas uses.
    let edit: (String, () -> Void) -> Void

    var body: some View {
        Form {
            PlotEditorView(model: model, edit: edit)

            Section("Site") {
                Picker("Climate", selection: input(\.climateZone)) {
                    ForEach(ClimateZone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Soil", selection: input(\.soilType)) {
                    ForEach(SoilType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Terrain", selection: input(\.terrainSlope)) {
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

            Section {
                ForEach(Sizing.cropVocabulary) { term in
                    Toggle(term.label, isOn: membership(term.key, in: \.crops))
                }
            } header: {
                sectionHeader("Crops", isFull: isEverythingOn(Sizing.cropVocabulary, in: \.crops)) {
                    setAll(Sizing.cropVocabulary, in: \.crops, on: !isEverythingOn(Sizing.cropVocabulary, in: \.crops))
                }
            }

            Section {
                ForEach(Sizing.animalVocabulary) { term in
                    LabeledContent(term.label) {
                        Stepper(value: animalCount(term.key), in: 0...200, step: 2) {
                            Text("\(animalCount(term.key).wrappedValue)")
                        }
                    }
                }
            } header: {
                sectionHeader("Animals", isFull: isEveryAnimalKept()) {
                    setAllAnimals(kept: !isEveryAnimalKept())
                }
            }

            Section {
                ForEach(Sizing.infrastructureVocabulary) { term in
                    Toggle(term.label, isOn: membership(term.key, in: \.infrastructure))
                }
                if needsWaterfront {
                    // The engine drops these when there's no water to put them
                    // on, and warns with its generic "couldn't fit it, try a
                    // bigger plot" text — which is the wrong advice, since the
                    // plot size has nothing to do with it.
                    Label(
                        "A dock or micro-hydro turbine needs a waterfront — set one under Plot ▸ Water, or they'll be left out.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                sectionHeader("Infrastructure", isFull: isEverythingOn(Sizing.infrastructureVocabulary, in: \.infrastructure)) {
                    setAll(
                        Sizing.infrastructureVocabulary,
                        in: \.infrastructure,
                        on: !isEverythingOn(Sizing.infrastructureVocabulary, in: \.infrastructure)
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Select all

    /// A section title with one control that flips the whole list. One button
    /// rather than an All/None pair: which of the two it offers is already
    /// decided by whether the list is full, so a second button would always
    /// be the no-op one.
    private func sectionHeader(_ title: String, isFull: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(isFull ? "Clear all" : "Select all", action: action)
                .buttonStyle(.link)
                .font(.caption)
                .textCase(nil)
        }
    }

    private func isEverythingOn(_ terms: [Sizing.VocabularyTerm], in keyPath: WritableKeyPath<StructuredInputs, [String]>) -> Bool {
        let selected = Set(model.document.brief.structuredInputs[keyPath: keyPath])
        return !terms.isEmpty && terms.allSatisfy { selected.contains($0.key) }
    }

    /// One undo step for the whole list, not one per term — the point of the
    /// button is that it is a single decision.
    private func setAll(_ terms: [Sizing.VocabularyTerm], in keyPath: WritableKeyPath<StructuredInputs, [String]>, on: Bool) {
        edit(on ? "Select All" : "Clear All") {
            model.updateStructuredInputs { inputs in
                if on {
                    // Keep anything already there that this list doesn't know
                    // about, so a term typed into the free-text brief isn't
                    // quietly dropped by a button labelled "select all".
                    let known = Set(terms.map(\.key))
                    let unknown = inputs[keyPath: keyPath].filter { !known.contains($0) }
                    inputs[keyPath: keyPath] = unknown + terms.map(\.key)
                } else {
                    let known = Set(terms.map(\.key))
                    inputs[keyPath: keyPath].removeAll { known.contains($0) }
                }
            }
        }
    }

    private func isEveryAnimalKept() -> Bool {
        let animals = model.document.brief.structuredInputs.animals
        return Sizing.animalVocabulary.allSatisfy { term in
            animals.contains { $0.type == term.key && $0.count > 0 }
        }
    }

    /// Animals are counts, not switches, so "select all" has to pick a number.
    /// A small starter flock: enough for the engine to size a shelter and a
    /// paddock, low enough that nobody gets a plan for a commercial herd they
    /// never asked for.
    private static let starterFlock = 6

    private func setAllAnimals(kept: Bool) {
        edit(kept ? "Select All" : "Clear All") {
            model.updateStructuredInputs { inputs in
                guard kept else {
                    let known = Set(Sizing.animalVocabulary.map(\.key))
                    inputs.animals.removeAll { known.contains($0.type) }
                    return
                }
                for term in Sizing.animalVocabulary where !inputs.animals.contains(where: { $0.type == term.key && $0.count > 0 }) {
                    inputs.animals.removeAll { $0.type == term.key }
                    inputs.animals.append(AnimalRequest(type: term.key, count: Self.starterFlock))
                }
            }
        }
    }

    /// Placement drops a dock or a turbine outright when the plot has no water
    /// (Placement.swift's "nowhere sensible to put it"), so ticking one here on
    /// a dry plot produces nothing and an unrelated-sounding warning. The list
    /// of types that care comes from the engine rather than a copy kept here,
    /// so it cannot drift out of step with the rule it is describing.
    private var needsWaterfront: Bool {
        guard model.document.plot.waterfront == nil else { return false }
        return model.document.brief.structuredInputs.infrastructure.contains { key in
            guard let term = Sizing.infrastructureVocabulary.first(where: { $0.key == key }) else { return false }
            return term.typeIds.contains { Placement.waterLovingTypes.contains($0) }
        }
    }

    // MARK: - Bindings into the model

    /// ProjectModel's document is `private(set)` on purpose — everything goes
    /// through its mutators, so each control gets a binding that reads the
    /// document and writes through `updateStructuredInputs`.
    private func input<T>(_ keyPath: WritableKeyPath<StructuredInputs, T>) -> Binding<T> {
        Binding(
            get: { model.document.brief.structuredInputs[keyPath: keyPath] },
            set: { value in
                edit("Change Brief") {
                    model.updateStructuredInputs { $0[keyPath: keyPath] = value }
                }
            }
        )
    }

    private func membership(_ key: String, in keyPath: WritableKeyPath<StructuredInputs, [String]>) -> Binding<Bool> {
        Binding(
            get: { model.document.brief.structuredInputs[keyPath: keyPath].contains(key) },
            set: { isOn in
                edit("Change Brief") {
                model.updateStructuredInputs { inputs in
                    if isOn {
                        guard !inputs[keyPath: keyPath].contains(key) else { return }
                        inputs[keyPath: keyPath].append(key)
                    } else {
                        inputs[keyPath: keyPath].removeAll { $0 == key }
                    }
                }
                }
            }
        )
    }

    private func animalCount(_ key: String) -> Binding<Int> {
        Binding(
            get: { model.document.brief.structuredInputs.animals.first { $0.type == key }?.count ?? 0 },
            set: { count in
                edit("Change Animals") {
                    model.updateStructuredInputs { inputs in
                        inputs.animals.removeAll { $0.type == key }
                        if count > 0 { inputs.animals.append(AnimalRequest(type: key, count: count)) }
                    }
                }
            }
        )
    }

}
