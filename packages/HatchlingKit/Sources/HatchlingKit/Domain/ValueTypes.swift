import Foundation

// MARK: - 槽位值域（含稀有 case · 定义见 breeding-algorithm.md §2.1）

public enum SpeciesGene: String, Codable, Hashable, CaseIterable, Sendable {
    case ghost, pod, crystal
}

public enum ColorGene: String, Codable, Hashable, CaseIterable, Sendable {
    case cyan, purple, green, orange, red, blue, yellow, white
    case holo        // 稀有 · 全息体色
}

public enum AntennaGene: String, Codable, Hashable, CaseIterable, Sendable {
    case pointy, round, droopy, forked
}

public enum EyeGene: String, Codable, Hashable, CaseIterable, Sendable {
    case dot, big, sleepy
    case pulseRing   // 稀有 · 脉冲环眼
}

public enum PatternGene: String, Codable, Hashable, CaseIterable, Sendable {
    case plain, belly, stripes, spots
    case stardust    // 稀有 · 星尘纹
}

public enum GlitchGene: String, Codable, Hashable, CaseIterable, Sendable {
    case low, mid, high
}

public enum TasteGene: String, Codable, Hashable, CaseIterable, Sendable {
    case knowledge, play, sleep
}

public enum Rarity: Int, Codable, Comparable, Sendable {
    case normal = 0, rare = 1, epic = 2, legendary = 3

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - 三层基因槽（表达 / 携带 / 祖源）

public struct GeneSlot<V: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var express: V
    public var carry: V
    public var dormant: V

    public init(express: V, carry: V, dormant: V) {
        self.express = express
        self.carry = carry
        self.dormant = dormant
    }
}

// MARK: - 性格四参数（0-1，遗传 = 亲本均值 + 高斯漂移）

public struct Personality: Codable, Hashable, Sendable {
    public var cling: Double      // 粘人
    public var snark: Double      // 毒舌
    public var curiosity: Double  // 好奇
    public var brave: Double      // 勇气

    public init(cling: Double = 0.5, snark: Double = 0.5,
                curiosity: Double = 0.5, brave: Double = 0.5) {
        self.cling = cling
        self.snark = snark
        self.curiosity = curiosity
        self.brave = brave
    }
}

// MARK: - 基因组

public struct GeneValue: Codable, Hashable, Sendable {
    public var species: GeneSlot<SpeciesGene>
    public var color: GeneSlot<ColorGene>
    public var antenna: GeneSlot<AntennaGene>
    public var eyes: GeneSlot<EyeGene>
    public var pattern: GeneSlot<PatternGene>
    public var glitch: GeneSlot<GlitchGene>
    public var taste: GeneSlot<TasteGene>
    public var shiny: Bool            // 异色（独立 roll，不遗传）
    public var legendary: Legendary?  // 传说基因（物种限定，仅突变产生）
    public var personality: Personality

    public init(species: GeneSlot<SpeciesGene>, color: GeneSlot<ColorGene>,
                antenna: GeneSlot<AntennaGene>, eyes: GeneSlot<EyeGene>,
                pattern: GeneSlot<PatternGene>, glitch: GeneSlot<GlitchGene>,
                taste: GeneSlot<TasteGene>, shiny: Bool = false,
                legendary: Legendary? = nil,
                personality: Personality = Personality()) {
        self.species = species
        self.color = color
        self.antenna = antenna
        self.eyes = eyes
        self.pattern = pattern
        self.glitch = glitch
        self.taste = taste
        self.shiny = shiny
        self.legendary = legendary
        self.personality = personality
    }
}

// MARK: - 全局型稀有基因（不占槽 · Pet.rareGenes 逗号分隔）

public enum GlobalGene: String, Codable, CaseIterable, Sendable {
    // 行为类（继承率 40%）
    case afterimage, randomDance, nocturnal, echoTic
    // 天赋类（继承率 30%）
    case deepDig, warmCore, gachaLuck
    // 隐藏配方产出
    case glitchBody, deepSpaceMessenger

    public var inheritChance: Double {
        switch self {
        case .afterimage, .randomDance, .nocturnal, .echoTic: return 0.40
        case .deepDig, .warmCore, .gachaLuck: return 0.30
        case .glitchBody, .deepSpaceMessenger: return 0.0   // 仅配方授予
        }
    }
}

// MARK: - 随机基因生成（开局星空蛋 / 任务野生蛋）

extension GeneValue {
    /// 全普通值域随机（三层独立随机；稀有只能来自突变/遗传）
    public static func random<G: RandomNumberGenerator>(rng: inout G) -> GeneValue {
        func slot<V>(_ all: [V]) -> GeneSlot<V> where V: Hashable & Codable & Sendable {
            GeneSlot(express: all.randomElement(using: &rng)!,
                     carry: all.randomElement(using: &rng)!,
                     dormant: all.randomElement(using: &rng)!)
        }
        func normalColor() -> ColorGene {
            let normal: [ColorGene] = [.cyan, .purple, .green, .orange, .red, .blue, .yellow, .white]
            return normal.randomElement(using: &rng)!
        }
        func normalEye() -> EyeGene {
            [EyeGene.dot, .big, .sleepy].randomElement(using: &rng)!
        }
        func normalPattern() -> PatternGene {
            [PatternGene.plain, .belly, .stripes, .spots].randomElement(using: &rng)!
        }
        func gauss() -> Double {
            // Box-Muller 简化版：两个均匀随机均值近似
            (Double.random(in: 0...1, using: &rng) + Double.random(in: 0...1, using: &rng)) / 2
        }
        return GeneValue(
            species: slot(SpeciesGene.allCases),
            color: slot([ColorGene.cyan, .purple, .green, .orange, .red, .blue, .yellow, .white]),
            antenna: slot(AntennaGene.allCases),
            eyes: slot([EyeGene.dot, .big, .sleepy]),
            pattern: slot([PatternGene.plain, .belly, .stripes, .spots]),
            glitch: slot(GlitchGene.allCases),
            taste: slot(TasteGene.allCases),
            shiny: false,
            legendary: nil,
            personality: Personality(
                cling: gauss(), snark: gauss(),
                curiosity: gauss(), brave: gauss())
        )
    }

    public static func random() -> GeneValue {
        var rng = SystemRandomNumberGenerator()
        return random(rng: &rng)
    }
}
