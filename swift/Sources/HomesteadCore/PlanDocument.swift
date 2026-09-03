import Foundation
import HomesteadEngine

/// A named object type and its user-adjustable footprint, the offered
/// starting sizes for a new plot. Ported concept from `StylePreset`'s id in
/// `src/domain/types.ts` — the palette mapping itself is a view concern
/// (colours), so only the identifier lives here.
public enum StylePresetID: String, Codable, CaseIterable, Sendable {
    case architecturalLight = "architectural-light"
    case architecturalDark = "architectural-dark"
}

/// One generated-or-edited layout. `Layout` (the engine's pure output) has
/// no identity or history — those belong here, at the document layer, per
/// AGENTS.md.
public struct Variant: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var strategyLabel: String
    public var mode: PlanningMode
    public var seed: Int
    public var zones: [Zone]
    public var objects: [PlanObject]
    public var paths: [PathEntity]
    public var fences: [Fence]
    public var utilityNodes: [UtilityNode]
    public var createdAt: Date

    /// True once the user has moved, resized, deleted, or added anything —
    /// distinguishing "what the generator proposed" from "what the user
    /// actually wants," per the "AI proposes, user stays in control"
    /// principle. Re-generating never clears it and never touches this
    /// variant at all: see `ProjectModel.generateVariant`.
    public var manuallyEdited: Bool

    /// The brief and plot boundary this variant was generated from, kept so
    /// staleness ("the brief changed since this was generated") can be
    /// detected later without threading a comparison through every edit
    /// path. Compared by `ProjectModel.isStale`.
    public var generatedFromBrief: Brief
    public var generatedFromPlotBoundary: [Point]

    /// A point-in-time snapshot, written only so an exported file reads
    /// standalone in something that isn't this app. Never read back: the
    /// running app always recomputes from `objects`/`zones` and the
    /// document's current plot/brief, which is what "derived, never stored"
    /// means in practice — even the copy sitting right here in the struct
    /// is treated as untrusted the moment the file is opened.
    public var analyticsSnapshot: AnalyticsSnapshot
    public var warningsSnapshot: [Warning]

    public init(
        id: UUID = UUID(),
        strategyLabel: String,
        mode: PlanningMode,
        seed: Int,
        zones: [Zone],
        objects: [PlanObject],
        paths: [PathEntity],
        fences: [Fence],
        utilityNodes: [UtilityNode],
        createdAt: Date = Date(),
        manuallyEdited: Bool = false,
        generatedFromBrief: Brief,
        generatedFromPlotBoundary: [Point],
        analyticsSnapshot: AnalyticsSnapshot,
        warningsSnapshot: [Warning]
    ) {
        self.id = id
        self.strategyLabel = strategyLabel
        self.mode = mode
        self.seed = seed
        self.zones = zones
        self.objects = objects
        self.paths = paths
        self.fences = fences
        self.utilityNodes = utilityNodes
        self.createdAt = createdAt
        self.manuallyEdited = manuallyEdited
        self.generatedFromBrief = generatedFromBrief
        self.generatedFromPlotBoundary = generatedFromPlotBoundary
        self.analyticsSnapshot = analyticsSnapshot
        self.warningsSnapshot = warningsSnapshot
    }

    /// Builds the variant a fresh `Generate.variant` call produces, stamping
    /// it with a new identity and today's brief/plot as the "generated from"
    /// baseline.
    public init(generated layout: Layout, plot: Plot, brief: Brief) {
        self.init(
            strategyLabel: layout.strategyLabel,
            mode: layout.mode,
            seed: layout.seed,
            zones: layout.zones,
            objects: layout.objects,
            paths: layout.paths,
            fences: layout.fences,
            utilityNodes: layout.utilityNodes,
            generatedFromBrief: brief,
            generatedFromPlotBoundary: plot.boundary,
            analyticsSnapshot: layout.analytics,
            warningsSnapshot: layout.warnings
        )
    }
}

/// The saved/exported shape of a project — one JSON format for both, per
/// AGENTS.md. `schemaVersion` exists so a future format change can migrate
/// or reject an old file explicitly instead of failing decode with no
/// explanation.
public struct PlanDocument: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var brief: Brief
    public var plot: Plot
    public var variants: [Variant]
    public var activeVariantID: Variant.ID?
    public var stylePresetID: StylePresetID

    public init(
        schemaVersion: Int = PlanDocument.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        brief: Brief,
        plot: Plot,
        variants: [Variant] = [],
        activeVariantID: Variant.ID? = nil,
        stylePresetID: StylePresetID = .architecturalLight
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.brief = brief
        self.plot = plot
        self.variants = variants
        self.activeVariantID = activeVariantID
        self.stylePresetID = stylePresetID
    }

    /// A new, empty project: a bare rectangular plot and a default brief,
    /// nothing generated yet.
    public static func blank(name: String, widthM: Double, heightM: Double) -> PlanDocument {
        PlanDocument(
            name: name,
            brief: Brief(structuredInputs: StructuredInputs()),
            plot: Plot(boundary: PlotShape.rectangle(width: widthM, height: heightM))
        )
    }
}

/// The codec for both saving and export — one format, per AGENTS.md. Dates
/// as ISO 8601 and pretty-printed output keep an exported file readable
/// outside this app, which is the entire point of writing the snapshot
/// fields at all.
public enum PlanDocumentCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ document: PlanDocument) throws -> Data {
        try encoder().encode(document)
    }

    public static func decode(_ data: Data) throws -> PlanDocument {
        try decoder().decode(PlanDocument.self, from: data)
    }
}
