import Foundation

/// Pet 的值快照（Engine 纯函数输入，避免耦合 @Model）
public struct PetSnapshot: Sendable {
    public var id: UUID
    public var state: PetState
    public var hatchAt: Date?
    public var hunger: Double          // 0 饱 → 100 饿
    public var mood: Double
    public var exploringSince: Date?
    public var lastTaskDate: Date?
    public var lastTickAt: Date?

    public init(id: UUID, state: PetState, hatchAt: Date?, hunger: Double,
                mood: Double, exploringSince: Date?, lastTaskDate: Date?, lastTickAt: Date?) {
        self.id = id
        self.state = state
        self.hatchAt = hatchAt
        self.hunger = hunger
        self.mood = mood
        self.exploringSince = exploringSince
        self.lastTaskDate = lastTaskDate
        self.lastTickAt = lastTickAt
    }
}

public enum TaskTier: String, Sendable {
    case standard   // 步数达标（深层矿区 · 有蛋机会）
    case fallback   // 倒计时兜底（仅基础资源）
}

public enum ReconcileCommand: Equatable, Sendable {
    case hatchEgg(id: UUID)
    case updateVitals(id: UUID, hunger: Double, mood: Double, tickAt: Date)
    case leaveForTask(id: UUID, at: Date)
    case finishExplore(id: UUID, tier: TaskTier)
}

/// 结算引擎（D1）：状态 = f(快照, now)。纯函数，输出命令由调用方落库。
public enum Reconciler {

    /// - Parameters:
    ///   - stepsToday: 今日步数（HealthKit；无授权传 0 → 任务走倒计时兜底）
    ///   - taskMaxInterval: 任务最晚时长（秒；正式 10h，演示可缩短）
    public static func run(now: Date, stepsToday: Int,
                           config: GameConfig, taskMaxInterval: TimeInterval,
                           pets: [PetSnapshot]) -> [ReconcileCommand] {
        var cmds: [ReconcileCommand] = []
        let cal = Calendar.current

        for p in pets {
            switch p.state {
            case .egg:
                if let due = p.hatchAt, now >= due {
                    cmds.append(.hatchEgg(id: p.id))
                }

            case .home:
                // 每日任务：到达出发时段且今天未出发 → 出发
                let didTaskToday = p.lastTaskDate.map { cal.isDate($0, inSameDayAs: now) } ?? false
                if !didTaskToday, cal.component(.hour, from: now) >= config.taskStartHour {
                    cmds.append(.leaveForTask(id: p.id, at: now))
                }
                vitals(p, now: now, config: config, cmds: &cmds)

            case .exploring:
                vitals(p, now: now, config: config, cmds: &cmds)
                let since = p.exploringSince ?? now
                let hours = now.timeIntervalSince(since) / 3600
                // 步数达标提前收工；倒计时兜底（不出门也必结束）
                if Double(stepsToday) >= Double(config.taskGoalSteps) {
                    cmds.append(.finishExplore(id: p.id, tier: .standard))
                } else if now.timeIntervalSince(since) >= taskMaxInterval {
                    cmds.append(.finishExplore(id: p.id, tier: .fallback))
                }

            case .arrived:
                break  // 等待 tap 收取（UI 层命令）
            }
        }
        return cmds
    }

    /// 饱食度/心情随时间漂移（增量结算：lastTickAt → now）
    private static func vitals(_ p: PetSnapshot, now: Date, config: GameConfig,
                               cmds: inout [ReconcileCommand]) {
        let last = p.lastTickAt ?? now
        let hours = max(0, now.timeIntervalSince(last) / 3600)
        guard hours > 1.0 / 3600 else { return }   // 忽略亚秒级
        let hunger = min(100, p.hunger + config.hungerRatePerHour * hours)
        // 心情：自然缓降 + 饥饿惩罚（饿越多掉越快）
        let moodDecay = config.moodDecayPerDay / 24 * hours
            + max(0, hunger - 60) / 40 * config.moodDecayPerDay / 24 * hours
        let mood = max(0, p.mood - moodDecay)
        cmds.append(.updateVitals(id: p.id, hunger: hunger, mood: mood, tickAt: now))
    }
}
