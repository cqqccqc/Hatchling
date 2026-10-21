import Testing
import Foundation
@testable import HatchlingKit

/// 可种子化 RNG（蒙特卡洛可复现）
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite("Genetics 遗传算法")
struct GeneticsTests {

    let cfg = GameConfig.default

    func fuseOnce(seed: UInt64, sinceRare: Int = 0,
                  a: GeneValue? = nil, b: GeneValue? = nil,
                  bondA: Double = 0, bondB: Double = 0) -> FusionOutput {
        var rng = SeededRNG(seed: seed)
        return Genetics.fuse(a: a ?? .random(), b: b ?? .random(),
                             bondA: bondA, bondB: bondB,
                             aRareGenes: [], bRareGenes: [],
                             sinceRare: sinceRare, config: cfg, rng: &rng)
    }

    // MARK: 三层池完整性

    @Test("未突变时三层均来自亲本 6 层池")
    func poolIntegrity() {
        let a = GeneSlot(express: ColorGene.blue, carry: .holo, dormant: .red)
        let b = GeneSlot(express: ColorGene.cyan, carry: .cyan, dormant: .white)
        let pool: Set<ColorGene> = [.blue, .holo, .red, .cyan, .white]
        for seed in 0..<500 {
            var rng = SeededRNG(seed: UInt64(seed))
            var muts: [String] = []
            let out = Genetics.fuseSlot(a, b, config: cfg, luck: 1.0,
                                        mutations: &muts, rng: &rng)
            #expect(pool.contains(out.express))
            #expect(pool.contains(out.carry))
            #expect(pool.contains(out.dormant))
        }
    }

    // MARK: 稀有突变率（蒙特卡洛）

    @Test("rare 突变率 ≈ 配置值 ±15%", arguments: [13, 77, 1024])
    func mutationRate(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let a = GeneSlot(express: ColorGene.blue, carry: .cyan, dormant: .red)
        let b = GeneSlot(express: ColorGene.cyan, carry: .white, dormant: .green)
        let n = 50_000
        var muts: [String] = []
        var holo = 0
        for _ in 0..<n {
            let out = Genetics.fuseSlot(a, b, config: cfg, luck: 1.0,
                                        mutations: &muts, rng: &rng)
            if out.express == .holo { holo += 1 }
        }
        let rate = Double(holo) / Double(n)
        #expect(abs(rate - cfg.mutateRare) < cfg.mutateRare * 0.15,
                "rare 突变率 \(rate) vs 配置 \(cfg.mutateRare)")
    }

    // MARK: 性格

    @Test("性格经 fuse 后落在 0-1 且偏向亲本均值")
    func personalityViaFuse() {
        var rng = SeededRNG(seed: 9)
        let high = Personality(cling: 0.9, snark: 0.9, curiosity: 0.9, brave: 0.9)
        var clingSum = 0.0
        let n = 3_000
        for _ in 0..<n {
            let out = Genetics.fuse(a: GeneValue.random(), b: GeneValue.random(),
                                    bondA: 0, bondB: 0, aRareGenes: [], bRareGenes: [],
                                    sinceRare: 0, config: cfg, rng: &rng)
            #expect(out.gene.personality.cling >= 0 && out.gene.personality.cling <= 1)
            clingSum += out.gene.personality.cling
        }
        // 双亲基因 random（均值≈0.5），子代均值应接近 0.5
        let avg = clingSum / Double(n)
        #expect(abs(avg - 0.5) < 0.05, "随机亲本子代 cling 均值应≈0.5，实测 \(avg)")
        _ = high
    }

    // MARK: 传说隔离（v1.0 裁决：纯低概率突变，不可遗传）

    @Test("传说仅由突变产生且物种匹配", arguments: [31, 555])
    func legendaryIsolation(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var legendaryCount = 0
        let n = 30_000
        for _ in 0..<n {
            let out = fuseOnce(seed: seed &+ UInt64(n) &+ UInt64(rng.next()),
                               a: .random(), b: .random())
            if let leg = out.legendary {
                legendaryCount += 1
                #expect(leg.species == out.gene.species.express, "传说必须与子代物种匹配")
                #expect(out.mutations.contains { $0.hasPrefix("legendary:") })
            }
        }
        let rate = Double(legendaryCount) / Double(n)
        #expect(abs(rate - cfg.mutateLegendary) < cfg.mutateLegendary * 0.5,
                "传说率 \(rate) vs 配置 \(cfg.mutateLegendary)")
    }

    // MARK: 保底

    @Test("保底：计数达标后本轮必有稀有收获（兜底或自然命中）")
    func pityTrigger() {
        var pity = 0
        var guaranteed = 0
        let n = 300
        for i in 0..<n {
            let out = fuseOnce(seed: UInt64(500 + i), sinceRare: 9)
            if out.isPityTriggered { pity += 1 }
            // 核心断言：要么保底触发，要么自然出了稀有——总之必有收获
            if out.isPityTriggered || Genetics.hasRareGain(out) { guaranteed += 1 }
        }
        #expect(guaranteed == n, "保底兜底保证 100% 有收获，实测 \(guaranteed)/\(n)")
        #expect(pity > n * 60 / 100, "多数轮次由保底兜底（自然稀有抢占约 10-20%），pity=\(pity)")
    }

    @Test("保底：sinceRare=0 时绝不触发")
    func pityNotTriggeredWhenLow() {
        var pity = 0
        for i in 0..<500 {
            let out = fuseOnce(seed: UInt64(1000 + i), sinceRare: 0)
            if out.isPityTriggered { pity += 1 }
        }
        #expect(pity == 0, "sinceRare=0 绝不应触发保底")
    }

    // MARK: 隐藏配方（蒙特卡洛）

    @Test("故障体配方：双亲 glitch high ≈ 5% 产出")
    func glitchBodyRecipe() {
        func highGlitchPet() -> GeneValue {
            var g = GeneValue.random()
            g.glitch = GeneSlot(express: .high, carry: .mid, dormant: .low)
            return g
        }
        let n = 4_000
        var granted = 0
        for i in 0..<n {
            let out = fuseOnce(seed: UInt64(7000 + i),
                               a: highGlitchPet(), b: highGlitchPet())
            if out.rareGenes.contains(.glitchBody) { granted += 1 }
        }
        let rate = Double(granted) / Double(n)
        #expect(abs(rate - 0.05) < 0.02, "故障体配方率 \(rate) vs 5%")
    }

    // MARK: 稀有收获

    @Test("稀有收获判定：holo 表达 / 全局基因 / 传说 均算收获")
    func rareGainDetection() {
        var out = FusionOutput(gene: GeneValue.random(), legendary: nil,
                               rareGenes: [], mutations: [], isPityTriggered: false)
        #expect(!Genetics.hasRareGain(out))
        out.gene.color.express = .holo
        #expect(Genetics.hasRareGain(out))
        out.gene.color.express = .blue
        out.rareGenes = [.deepDig]
        #expect(Genetics.hasRareGain(out))
        out.rareGenes = []
        out.legendary = .blackHoleCore
        #expect(Genetics.hasRareGain(out))
    }
}
