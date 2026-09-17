import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

/// The catalog names meshes by string, and a name that does not resolve is an
/// object that silently does not appear — the exact failure mode the type-id
/// checker was written for on the drawing side, now with 381 meshes to get
/// wrong instead of 38 type ids. Caught here rather than by looking at an
/// empty patch of grass and wondering.
struct SceneCatalogTests {
    private func meshes(in look: SceneCatalog.Look) -> [String] {
        var names: [String] = []
        switch look.massing {
        case let .building(meshes, _): names += meshes
        case let .single(model, _): names.append(model)
        case let .scatter(models, _, _): names += models
        case let .rows(model, _, _, _, _, _): names.append(model)
        case .surface, .sunken, .volume: break
        }
        return names + look.props.map(\.model)
    }

    @Test func everyMeshTheCatalogNamesExists() {
        for (typeId, look) in SceneCatalog.table {
            for mesh in meshes(in: look) {
                #expect(ModelMetrics[mesh] != nil, "\(typeId) names missing mesh \(mesh)")
            }
        }
        for mesh in meshes(in: SceneCatalog.fallback) {
            #expect(ModelMetrics[mesh] != nil)
        }
    }

    /// Every type in the object catalog has a look of its own. Falling back is
    /// fine as a safety net and wrong as an answer: a plan where the septic
    /// tank and the greenhouse are the same grey box is the plan this is
    /// replacing.
    @Test func everyCatalogTypeHasALookOfItsOwn() {
        let missing = ObjectLibrary.all
            .map(\.id)
            .filter { SceneCatalog.table[$0] == nil }
        #expect(missing.isEmpty, "no 3D look for: \(missing.joined(separator: ", "))")
    }

    @Test func theCatalogNamesNothingItDoesNotDraw() {
        let known = Set(ObjectLibrary.all.map(\.id))
        let unknown = SceneCatalog.table.keys.filter { !known.contains($0) }
        #expect(unknown.isEmpty, "look for types that are not in the catalog: \(unknown)")
    }

    /// Sizes are in metres and a typo is an order of magnitude. A building
    /// three metres tall is a shed; one thirty metres tall is a mistake.
    @Test func everySizeIsPlausibleInMetres() {
        for (typeId, look) in SceneCatalog.table {
            switch look.massing {
            case let .building(_, height):
                #expect(height > 1.5 && height < 15, "\(typeId) is \(height) m tall")
            case .single:
                break
            case let .scatter(_, density, height):
                #expect(density > 0 && density < 1, "\(typeId) plants \(density) per m²")
                #expect(height > 0.2 && height < 20)
            case let .rows(_, spacing, height, _, _, tilt):
                #expect(abs(tilt) < 1.4, "\(typeId) tilts \(tilt) rad")
                #expect(spacing > 0.3 && spacing < 10, "\(typeId) rows \(spacing) m apart")
                #expect(height > 0.1 && height < 10)
            case let .surface(_, height):
                #expect(height >= 0 && height < 5)
            case let .volume(_, wallHeight, ridgeRise, opacity):
                #expect(wallHeight > 0.3 && wallHeight < 12, "\(typeId) walls are \(wallHeight) m")
                #expect(ridgeRise >= 0 && ridgeRise < 6)
                #expect(opacity > 0 && opacity <= 1)
            case let .sunken(_, depth):
                #expect(depth > 0 && depth < 5)
            }
            for prop in look.props {
                #expect(prop.count > 0 && prop.count < 30)
                #expect(abs(prop.offset.x) <= 1.2 && abs(prop.offset.y) <= 1.2, "\(typeId) prop is off its own plot")
            }
        }
    }
}
