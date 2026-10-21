import Foundation

// MARK: - 槽位基因协议（稀有度表 + 突变候选池）

public protocol SlotGene: Codable, Hashable, CaseIterable, Sendable, RawRepresentable where RawValue == String {
    static func rarity(of value: Self) -> Rarity
    /// 突变候选池（rare+epic；亲本已表达的同一值由算法排除）
    static func mutationPool() -> [Self]
}

extension SpeciesGene: SlotGene {
    public static func rarity(of value: SpeciesGene) -> Rarity { .normal }
    public static func mutationPool() -> [SpeciesGene] { [] }   // 物种无稀有度
}
extension ColorGene: SlotGene {
    public static func rarity(of value: ColorGene) -> Rarity { value == .holo ? .rare : .normal }
    public static func mutationPool() -> [ColorGene] { [.holo] }
}
extension AntennaGene: SlotGene {
    public static func rarity(of value: AntennaGene) -> Rarity { .normal }
    public static func mutationPool() -> [AntennaGene] { [] }
}
extension EyeGene: SlotGene {
    public static func rarity(of value: EyeGene) -> Rarity { value == .pulseRing ? .rare : .normal }
    public static func mutationPool() -> [EyeGene] { [.pulseRing] }
}
extension PatternGene: SlotGene {
    public static func rarity(of value: PatternGene) -> Rarity { value == .stardust ? .rare : .normal }
    public static func mutationPool() -> [PatternGene] { [.stardust] }
}
extension GlitchGene: SlotGene {
    public static func rarity(of value: GlitchGene) -> Rarity { .normal }
    public static func mutationPool() -> [GlitchGene] { [] }
}
extension TasteGene: SlotGene {
    public static func rarity(of value: TasteGene) -> Rarity { .normal }
    public static func mutationPool() -> [TasteGene] { [] }
}

// MARK: - 传说注册表（物种限定 · 仅突变 · 不可遗传 · v1.0 裁决）

public enum Legendary: String, Codable, CaseIterable, Sendable {
    case blackHoleCore   // 黑洞核心 · pod
    case twinGhost       // 双生幽灵 · ghost
    case twinCore        // 双子内核 · crystal

    public var species: SpeciesGene {
        switch self {
        case .blackHoleCore: return .pod
        case .twinGhost: return .ghost
        case .twinCore: return .crystal
        }
    }
}

// MARK: - 融合输出

public struct FusionOutput: Sendable {
    public var gene: GeneValue
    public var legendary: Legendary?
    public var rareGenes: [GlobalGene]
    public var mutations: [String]     // "epic:xxx" / "rare:xxx" / "legendary:xxx" / "pity" / "recipe:xxx"
    public var isPityTriggered: Bool   // 保底命中
}

// MARK: - 融合主算法（breeding-algorithm.md §3-§8 落码）

public enum Genetics {

    /// 融合两只宠物的基因（纯函数）
    /// - Parameters:
    ///   - sinceRare: 主人级保底计数（≥9 时本轮触发保底）
    ///   - rng: 注入随机源（单测用种子 RNG）
    public static func fuse<G: RandomNumberGenerator>(a: GeneValue, b: GeneValue,
                            bondA: Double, bondB: Double,
                            aRareGenes: [GlobalGene], bRareGenes: [GlobalGene],
                            sinceRare: Int,
                            config: GameConfig,
                            rng: inout G) -> FusionOutput {
        var out = FusionOutput(gene: a, legendary: nil, rareGenes: [], mutations: [], isPityTriggered: false)
        let luck = (aRareGenes.contains(.gachaLuck) || bRareGenes.contains(.gachaLuck)) ? 2.0 : 1.0

        // ① 物种槽（42/42/16，无稀有突变）
        out.gene.species = fuseSlot(a.species, b.species, config: config,
                                    luck: 1.0, mutations: &out.mutations, rng: &rng)

        // ② 传说全局 roll（物种限定 · 不可遗传 · 欧皇 ×2）
        if Double.random(in: 0..<1, using: &rng) < config.mutateLegendary * luck,
           let leg = Legendary.allCases.first(where: { $0.species == out.gene.species.express }) {
            out.legendary = leg
            out.gene.legendary = leg
            out.mutations.append("legendary:\(leg.rawValue)")
        }

        // ③ 其余 6 槽逐槽遗传（稀有槽位突变 ×欧皇 luck）
        out.gene.color = fuseSlot(a.color, b.color, config: config, luck: luck, mutations: &out.mutations, rng: &rng)
        out.gene.antenna = fuseSlot(a.antenna, b.antenna, config: config, luck: 1.0, mutations: &out.mutations, rng: &rng)
        out.gene.eyes = fuseSlot(a.eyes, b.eyes, config: config, luck: luck, mutations: &out.mutations, rng: &rng)
        out.gene.pattern = fuseSlot(a.pattern, b.pattern, config: config, luck: luck, mutations: &out.mutations, rng: &rng)
        out.gene.glitch = fuseSlot(a.glitch, b.glitch, config: config, luck: 1.0, mutations: &out.mutations, rng: &rng)
        out.gene.taste = fuseSlot(a.taste, b.taste, config: config, luck: 1.0, mutations: &out.mutations, rng: &rng)

        // ④ shiny（独立 roll；双亲羁绊 ≥90 ×3）
        let bondMax = max(bondA, bondB)
        let shinyOdds = config.shinyOdds * (bondMax >= 90 ? config.shinyBondMultiplier : 1.0)
        out.gene.shiny = Double.random(in: 0..<1, using: &rng) < shinyOdds

        // ⑤ 性格（亲本均值 + 近高斯 σ≈0.15，四参数独立）
        out.gene.personality = blendPersonality(a.personality, b.personality, rng: &rng)

        // ⑥ 全局基因继承（行为 40% / 天赋 30%，至多 2 条）
        out.rareGenes = inheritGlobals(aRareGenes: aRareGenes, bRareGenes: bRareGenes, rng: &rng)

        // ⑦ 隐藏配方（双亲 express 组合）
        applyRecipes(a: a, b: b, output: &out, rng: &rng)

        // ⑧ 保底（无稀有收获且计数达标 → 强制注入一个稀有）
        if !hasRareGain(out), sinceRare + 1 >= 10 {
            let injections: [(inout GeneValue) -> Void] = [
                { $0.color.express = .holo },
                { $0.eyes.express = .pulseRing },
                { $0.pattern.express = .stardust },
            ]
            if let inject = injections.randomElement(using: &rng) {
                inject(&out.gene)
            }
            out.isPityTriggered = true
            out.mutations.append("pity")
        }

        out.gene.personality.clampAll()
        return out
    }

    /// 稀有收获判定（carry 层继承不算——保底只看"看得见的惊喜"）
    public static func hasRareGain(_ out: FusionOutput) -> Bool {
        out.legendary != nil
            || out.gene.shiny
            || !out.rareGenes.isEmpty
            || out.gene.color.express == .holo
            || out.gene.eyes.express == .pulseRing
            || out.gene.pattern.express == .stardust
            || out.mutations.contains { $0.hasPrefix("rare:") || $0.hasPrefix("epic:") }
    }

    /// 稀有收获后应重置保底计数
    public static func shouldResetPity(_ out: FusionOutput) -> Bool {
        hasRareGain(out)
    }

    // MARK: 单槽遗传（返回槽 + 突变记录）

    static func fuseSlot<V: SlotGene, G: RandomNumberGenerator>(
                                      _ a: GeneSlot<V>, _ b: GeneSlot<V>,
                                      config: GameConfig, luck: Double,
                                      mutations: inout [String],
                                      rng: inout G) -> GeneSlot<V> {
        var pool = [a.express, a.carry, a.dormant, b.express, b.carry, b.dormant]  // 6 层池
        var express: V
        var mutatedBy: V? = nil

        // 突变分层：epic → rare（legendary 不走槽位）
        let epicRoll = Double.random(in: 0..<1, using: &rng)
        if epicRoll < config.mutateEpic * luck,
           let v = V.mutationPool().filter({ V.rarity(of: $0) == .epic }).randomElement() {
            express = v
            mutatedBy = v
            mutations.append("epic:\(v.rawValue)")
        } else if Double.random(in: 0..<1, using: &rng) < config.mutateRare * luck {
            // 排除双亲正在表达的同一稀有值（避免无效重复）
            let candidates = V.mutationPool().filter {
                V.rarity(of: $0) == .rare && $0 != a.express && $0 != b.express
            }
            if let v = candidates.randomElement() {
                express = v
                mutatedBy = v
                mutations.append("rare:\(v.rawValue)")
            }
        }

        if let v = mutatedBy {
            express = v
        } else {
            // 常规：42% A表达 / 42% B表达 / 16% 池内随机
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.42 {
                express = a.express
            } else if roll < 0.84 {
                express = b.express
            } else if let v = pool.randomElement(using: &rng) {
                express = v
            } else {
                express = a.express
            }
        }
        // 从池移除一个 express 实例，剩余洗牌 → carry / dormant
        if let idx = pool.firstIndex(of: express) { pool.remove(at: idx) }
        pool.shuffle(using: &rng)
        let carry = pool.first ?? express
        let dormant = pool.count > 1 ? pool[1] : carry
        return GeneSlot(express: express, carry: carry, dormant: dormant)
    }

    // MARK: 性格（亲本均值 + 近高斯）

    static func blendPersonality<G: RandomNumberGenerator>(_ a: Personality, _ b: Personality,
                                 rng: inout G) -> Personality {
        func blend(_ x: Double, _ y: Double) -> Double {
            let mean = (x + y) / 2
            // 4 个均匀随机之和 ≈ 高斯：σ_uniform=0.289×2=0.577，×0.26≈0.15
            let g = (Double.random(in: 0..<1, using: &rng)
                   + Double.random(in: 0..<1, using: &rng)
                   + Double.random(in: 0..<1, using: &rng)
                   + Double.random(in: 0..<1, using: &rng) - 2) * 0.26
            return min(1, max(0, mean + g))
        }
        return Personality(cling: blend(a.cling, b.cling),
                           snark: blend(a.snark, b.snark),
                           curiosity: blend(a.curiosity, b.curiosity),
                           brave: blend(a.brave, b.brave))
    }

    // MARK: 全局基因继承（行为 40% / 天赋 30%，至多 2 条）

    static func inheritGlobals<G: RandomNumberGenerator>(aRareGenes: [GlobalGene], bRareGenes: [GlobalGene],
                               rng: inout G) -> [GlobalGene] {
        var candidates: [GlobalGene] = []
        for g in Set(aRareGenes + bRareGenes) where g.inheritChance > 0 {
            if Double.random(in: 0..<1, using: &rng) < g.inheritChance {
                candidates.append(g)
            }
        }
        candidates.shuffle(using: &rng)
        return Array(candidates.prefix(2))
    }

    // MARK: 隐藏配方（双亲 express 组合）

    static func applyRecipes<G: RandomNumberGenerator>(a: GeneValue, b: GeneValue, output: inout FusionOutput,
                             rng: inout G) {
        // 故障体：双亲 glitch 表达层都是 high → 5%
        if a.glitch.express == .high && b.glitch.express == .high,
           Double.random(in: 0..<1, using: &rng) < 0.05,
           !output.rareGenes.contains(.glitchBody) {
            output.rareGenes.append(.glitchBody)
            output.mutations.append("recipe:glitchBody")
        }
        // 深空信使：双亲并集覆盖 {星际蓝 · 光环天线 · 数据流花纹} → 8%
        let traits = Set([
            "c:\(a.color.express.rawValue)", "c:\(b.color.express.rawValue)",
            "a:\(a.antenna.express.rawValue)", "a:\(b.antenna.express.rawValue)",
            "p:\(a.pattern.express.rawValue)", "p:\(b.pattern.express.rawValue)",
        ])
        if traits.contains("c:blue"), traits.contains("a:droopy"), traits.contains("p:stripes"),
           Double.random(in: 0..<1, using: &rng) < 0.08,
           !output.rareGenes.contains(.deepSpaceMessenger) {
            output.rareGenes.append(.deepSpaceMessenger)
            output.mutations.append("recipe:deepSpace")
        }
    }
}

extension Personality {
    mutating func clampAll() {
        cling = min(1, max(0, cling))
        snark = min(1, max(0, snark))
        curiosity = min(1, max(0, curiosity))
        brave = min(1, max(0, brave))
    }
}
