import Foundation

/// 主人级保底计数（跨宠物，UserDefaults 持久）
public enum BreedingPity {
    static let key = "hatchling.pity.sinceRare"

    public static func load() -> Int { UserDefaults.standard.integer(forKey: key) }
    public static func reset() { UserDefaults.standard.set(0, forKey: key) }
    public static func increment() { UserDefaults.standard.set(load() + 1, forKey: key) }
}
