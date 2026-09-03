import Foundation

/// The top-level assembly, ported from `src/engine/generate.ts`. Takes a
/// plot and a brief rather than a full `Project` — identity (a variant's id,
/// its undo history) belongs to the document layer, not to this pure
/// function; see AGENTS.md.
public enum Generate {
    private static let strategyLabels: [PlanningMode: String] = [
        .minimumMaintenance: "Compact & Efficient",
        .productionMax: "Production-Maximizing",
        .beautyBalanced: "Beauty-Balanced",
        .safetyFirst: "Safety-First",
    ]

    public static func variant(plot: Plot, brief: Brief, mode: PlanningMode, seed: Int) -> Layout {
        let extraction = TextParser.parse(brief.freeText)
        let mergedInputs = TextParser.merge(brief.structuredInputs, with: extraction)
        let program = Sizing.buildProgram(mergedInputs, mode: mode)
        let placed = Placement.placeObjects(plot: plot, program: program, mode: mode, seed: seed)
        let paths = PathsAndFences.synthesizePaths(objects: placed.objects, plot: plot)
        let fences = PathsAndFences.synthesizeFences(objects: placed.objects, plot: plot)
        let zones = FutureExpansionZone.build(plot: plot, objects: placed.objects, mode: mode)
        let analytics = Analytics.compute(objects: placed.objects, zones: zones, plot: plot)
        var warnings = Warnings.compute(
            objects: placed.objects,
            fences: fences,
            analytics: analytics,
            plot: plot,
            householdSize: mergedInputs.householdSize,
            climateZone: mergedInputs.climateZone,
            crops: mergedInputs.crops
        )

        // `unshift`, once per unplaced item in array order: each prepend
        // pushes the *previous* prepends one step further back, so after all
        // of them the item unshifted *last* sits at the very front — i.e.
        // inserting at index 0 in `unplaced`'s own order (not reversed)
        // reproduces the sequence of prepends exactly. The random id suffix
        // TypeScript appends (a fresh uuid, not seeded) is dropped rather
        // than reproduced: it carries no information, and the golden
        // fixtures were normalized to omit it for exactly that reason.
        for item in placed.unplaced {
            warnings.insert(
                Warning(
                    id: "warn-unplaced-\(item.typeId)",
                    severity: .critical,
                    message: "Could not fit \"\(item.typeId.replacingOccurrences(of: "-", with: " "))\" anywhere on the plot without violating hard constraints or overlapping existing zones. Consider a larger plot or a smaller program.",
                    messageKey: "warning.unplaced",
                    messageParams: ["itemType": .string(item.typeId)],
                    ruleId: "capacity-overflow",
                    objectIds: []
                ),
                at: 0
            )
        }

        return Layout(
            strategyLabel: strategyLabels[mode]!,
            mode: mode,
            seed: seed,
            zones: zones,
            objects: placed.objects,
            paths: paths,
            fences: fences,
            utilityNodes: UtilityConnections.computeNodes(placed.objects),
            analytics: analytics,
            warnings: warnings
        )
    }
}
