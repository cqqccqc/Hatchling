import Foundation
import SwiftData

// MARK: - 宠物（单实体状态机：egg → home → exploring → arrived；放生 → Archive）
// schema 详见 docs/plan/data-model.md v1.1

public enum PetState: String, Sendable {
    case egg, home, exploring, arrived
}

@Model
public final class Pet {
    public var id: UUID = UUID()
    public var name: String = ""
    public var gene: GeneValue?
    public var gen: Int = 0
    public var parentA: UUID?
    public var parentB: UUID?
    // --- 生命周期状态机 ---
    public var state: String = PetState.egg.rawValue
    public var hatchAt: Date?
    public var source: String = "star"        // star | task | fuse | twin
    public var legend: Bool = false
    public var rareGenes: String = ""         // GlobalGene raw 逗号分隔
    public var birthAt: Date = Date.distantPast
    // --- 宠物期动态状态（结算制可变） ---
    public var mood: Double = 70
    public var hunger: Double = 20
    public var bond: Double = 0
    public var exploringSince: Date?
    public var lastTaskDate: Date?
    public var cooldownUntil: Date?
    public var fuseCount: Int = 0
    public var createdAt: Date = Date()

    public init(name: String,
                gene: GeneValue?,
                gen: Int = 0,
                state: PetState = .egg,
                source: String = "star",
                legend: Bool = false,
                hatchAt: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.gene = gene
        self.gen = gen
        self.state = state.rawValue
        self.source = source
        self.legend = legend
        self.hatchAt = hatchAt
        self.birthAt = Date()
        self.createdAt = Date()
    }

    public var stateKind: PetState {
        get { PetState(rawValue: state) ?? .home }
        set { state = newValue.rawValue }
    }
}

// MARK: - 事件溯源（90 天滚动裁剪，day 冗余便于按天查询）

public enum EventType: String, Sendable {
    case born, feed, petted, talk
    case exploreStart, exploreDone
    case hatchDone, fuse, release
    case sleepWake, alarm, dream, moodMilestone
}

@Model
public final class EventLog {
    public var id: UUID = UUID()
    public var ts: Date = Date()
    public var type: String = ""
    public var petID: UUID?
    public var payload: String?
    public var day: String = ""               // "2026-10-20"

    public init(type: EventType, petID: UUID? = nil, payload: String? = nil, ts: Date = Date()) {
        self.id = UUID()
        self.ts = ts
        self.type = type.rawValue
        self.petID = petID
        self.payload = payload
        self.day = Self.dayString(from: ts)
    }

    public static func dayString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

// MARK: - agent memory 产物（晨间批处理写入 · 暂缓对接 LLM，schema 先立）

@Model
public final class Memory {
    public var id: UUID = UUID()
    public var day: String = ""
    public var summary: String = ""
    public var emotion: String = ""
    public var tags: String = ""
    public var isAnniversary: Bool = false
    public var dreamSeed: String?

    public init(day: String, summary: String, emotion: String = "",
                tags: String = "", isAnniversary: Bool = false, dreamSeed: String? = nil) {
        self.id = UUID()
        self.day = day
        self.summary = summary
        self.emotion = emotion
        self.tags = tags
        self.isAnniversary = isAnniversary
        self.dreamSeed = dreamSeed
    }
}

// MARK: - 放生归档（只增不删 · 血脉与"归档回归"伏笔的载体）

@Model
public final class Archive {
    public var id: UUID = UUID()
    public var name: String = ""
    public var gene: GeneValue?
    public var gen: Int = 0
    public var parentA: UUID?
    public var parentB: UUID?
    public var birthAt: Date?
    public var releasedAt: Date = Date()
    public var eventDigest: String = ""

    public init(name: String, gene: GeneValue?, gen: Int,
                parentA: UUID?, parentB: UUID?, birthAt: Date?, eventDigest: String) {
        self.id = UUID()
        self.name = name
        self.gene = gene
        self.gen = gen
        self.parentA = parentA
        self.parentB = parentB
        self.birthAt = birthAt
        self.releasedAt = Date()
        self.eventDigest = eventDigest
    }
}
