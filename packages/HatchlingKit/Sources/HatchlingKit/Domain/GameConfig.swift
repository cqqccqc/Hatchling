import Foundation

/// 全部可配置玩法参数（data-model.md §3）
/// M0-M2：打包默认值 + UserDefaults 覆盖；后续可远端下发
public struct GameConfig: Codable, Sendable {
    // 孵化与繁育
    public var hatchMinutes: Int = 30
    public var fuseGateHours: Int = 24
    public var fatigueHours: [Int] = [4, 8, 16, 48]
    // 任务
    public var taskGoalSteps: Int = 4000
    public var taskMaxHours: Int = 10
    public var taskStartHour: Int = 8
    // 掉落
    public var eggChanceStandard: Double = 0.30
    public var partChance: Double = 0.25
    // 基因
    public var mutateRare: Double = 0.025
    public var mutateEpic: Double = 0.006
    public var mutateLegendary: Double = 0.0008
    public var shinyOdds: Double = 1.0 / 96.0
    public var shinyBondMultiplier: Double = 3.0
    // 生活
    public var maxPets: Int = 3
    public var hungerRatePerHour: Double = 2.0
    public var moodDecayPerDay: Double = 10.0
    public var dailyTalkLimit: Int = 2
    public var eventRetentionDays: Int = 90

    public static let `default` = GameConfig()

    private static let key = "hatchling.gameconfig.v1"

    public static func load() -> GameConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(GameConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
