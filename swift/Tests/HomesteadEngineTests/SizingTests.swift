import Testing
@testable import HomesteadEngine

/// Expected widths/heights below are values the real `buildProgram` in
/// TypeScript actually produced for these inputs (captured via Node), not
/// values reasoned out from the formula — the sqrt-scaling composes in a way
/// that's easy to get subtly wrong by inspection alone.
struct SizingTests {
    private func item(_ typeId: String, _ width: Double, _ height: Double, metadata: [String: JSONValue] = [:]) -> Sizing.ProgramItem {
        Sizing.ProgramItem(typeId: typeId, size: Size(width: width, height: height), count: 1, metadata: metadata)
    }

    private func base(
        householdSize: Int = 3,
        aestheticPreference: Double = 20,
        crops: [String] = [],
        animals: [AnimalRequest] = [],
        infrastructure: [String] = [],
        houseShape: HouseShape = .rect,
        houseSizePreset: HouseSizePreset = .medium
    ) -> StructuredInputs {
        StructuredInputs(
            householdSize: householdSize,
            animals: animals,
            crops: crops,
            infrastructure: infrastructure,
            aestheticPreference: aestheticPreference,
            houseSizePreset: houseSizePreset,
            houseShape: houseShape
        )
    }

    @Test func bareHouseHasNoPatioBelowTheAestheticThreshold() {
        let program = Sizing.buildProgram(base(), mode: .beautyBalanced)
        #expect(program == [item("house", 12, 10), item("shed", 4, 3)])
    }

    @Test func aestheticPreferenceAtThirtyFiveAddsAPatio() {
        let program = Sizing.buildProgram(base(aestheticPreference: 50), mode: .beautyBalanced)
        #expect(program == [item("house", 12, 10), item("patio", 6, 5), item("shed", 4, 3)])
    }

    @Test func lShapedLargeHouseScalesBySqrtOfTheSizePreset() {
        let program = Sizing.buildProgram(base(houseShape: .lshape, houseSizePreset: .large), mode: .beautyBalanced)
        #expect(program.first == item("house-l", 17.983325610131182, 14.129755836531642))
    }

    /// Staple crops scale with household size and ignore the mode; surplus
    /// crops scale with the mode and ignore household size. Compost is added
    /// automatically once any crop is requested.
    @Test func productionMaxGrowsSurplusCropsNotStaples() {
        let program = Sizing.buildProgram(
            base(crops: ["potato", "orchard", "berries"]),
            mode: .productionMax
        )
        #expect(program == [
            item("house", 12, 10),
            item("shed", 4, 3),
            item("potato-area", 15, 10),
            item("orchard-trees", 20.523157651784484, 15.962455951387932),
            item("berry-rows", 11.401754250991381, 6.841052550594828),
            item("compost", 4, 3),
        ])
    }

    @Test func staplesScaleWithHouseholdSizeAcrossAnyMode() {
        let program = Sizing.buildProgram(
            base(householdSize: 6, crops: ["potato", "vegetable"]),
            mode: .minimumMaintenance
        )
        #expect(program == [
            item("house", 12, 10),
            item("shed", 4, 3),
            item("potato-area", 20.12461179749811, 13.416407864998739),
            item("vegetable-area", 16.099689437998485, 13.416407864998739),
            item("compost", 4, 3),
        ])
    }

    @Test func animalCountsScaleShelterAndPaddockIndependently() {
        let program = Sizing.buildProgram(
            base(animals: [
                AnimalRequest(type: "goats", count: 8),
                AnimalRequest(type: "poultry", count: 20),
            ]),
            mode: .safetyFirst
        )
        #expect(program == [
            item("house", 12, 10),
            item("shed", 4, 3),
            item("goat-shelter", 6.708203932499369, 5.366563145999495),
            item("goat-paddock", 22.627416997969522, 16.970562748477143, metadata: [
                "animalCount": .number(8), "animalType": "goats",
            ]),
            item("poultry-coop", 9.486832980505138, 7.905694150420949, metadata: [
                "animalCount": .number(20), "animalType": "poultry",
            ]),
        ])
    }

    @Test func infrastructureExpandsToEveryLinkedType() {
        let program = Sizing.buildProgram(
            base(infrastructure: ["solar", "well"]),
            mode: .beautyBalanced
        )
        #expect(program == [
            item("house", 12, 10),
            item("shed", 4, 3),
            item("solar-array", 8, 5),
            item("battery-room", 3, 3),
            item("inverter-room", 2, 2),
            item("well", 2, 2),
            item("pump", 2, 2),
        ])
    }

    @Test func explicitCompostIsNotDuplicated() {
        let program = Sizing.buildProgram(
            base(crops: ["potato"], infrastructure: ["compost"]),
            mode: .beautyBalanced
        )
        #expect(program.filter { $0.typeId == "compost" }.count == 1)
    }

    /// An unresolvable crop name still counts as "requesting food production"
    /// for the auto-compost rule: that check is `crops.length > 0` on the raw
    /// list, not on how many items actually resolved to a catalog type.
    @Test func unknownCropsAndInfrastructureAreIgnoredButStillCountAsFoodProduction() {
        let program = Sizing.buildProgram(
            base(crops: ["not-a-real-crop"], infrastructure: ["not-a-real-infra"]),
            mode: .beautyBalanced
        )
        #expect(program == [item("house", 12, 10), item("shed", 4, 3), item("compost", 4, 3)])
    }
}
