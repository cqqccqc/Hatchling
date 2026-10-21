import Testing
import Foundation
@testable import HatchlingKit

struct DomainSmokeTests {
    @Test func geneSlotCodableRoundtrip() throws {
        let slot = GeneSlot(express: ColorGene.blue, carry: ColorGene.holo, dormant: ColorGene.red)
        let data = try JSONEncoder().encode(slot)
        let back = try JSONDecoder().decode(GeneSlot<ColorGene>.self, from: data)
        #expect(back == slot)
    }

    @Test func randomGeneAllSlotsValid() {
        let gene = GeneValue.random()
        #expect(SpeciesGene.allCases.contains(gene.species.express))
        #expect(ColorGene.allCases.contains(gene.color.express))
        #expect(GlitchGene.allCases.contains(gene.glitch.express))
        // 开局随机蛋不携带稀有（稀有只能来自突变/遗传）
        #expect(gene.color.express != .holo)
        #expect(gene.eyes.express != .pulseRing)
        #expect(gene.pattern.express != .stardust)
    }

    @Test func petStateMachineDefaults() {
        let pet = Pet(name: "零波", gene: .random(), state: .egg,
                      hatchAt: Date().addingTimeInterval(30))
        #expect(pet.stateKind == .egg)
        #expect(pet.mood == 70)
        #expect(pet.legend == false)
    }

    @Test func eventTypeRawValuesStable() {
        // CloudKit 落库的是 raw 字符串，改名会破坏历史数据
        #expect(EventType.feed.rawValue == "feed")
        #expect(EventType.hatchDone.rawValue == "hatchDone")
    }
}
