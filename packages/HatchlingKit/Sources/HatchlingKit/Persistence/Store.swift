import Foundation
import SwiftData

public enum AppGroup {
    public static let identifier = "group.com.hatchling.app"
}

public struct HatchlingStore {
    public let container: ModelContainer
    /// 零云化后恒为 false（保留字段兼容 UI 层"本地"徽标展示）
    public let synced: Bool

    /// v0.4 零云化：App Group 本地存储，无 CloudKit（不申请开发者账号）
    /// 回退链：App Group 本地 → 默认位置本地（无 entitlement 环境）
    public static func make() -> HatchlingStore {
        let schema = Schema([Pet.self, EventLog.self, Memory.self, Archive.self])

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            let storeURL = groupURL.appending(path: "Hatchling.store")
            let cfg = ModelConfiguration(
                schema: schema, url: storeURL, cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: schema, configurations: [cfg]) {
                return HatchlingStore(container: c, synced: false)
            }
        }

        let fallbackCfg = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        let c = try! ModelContainer(for: schema, configurations: [fallbackCfg])
        return HatchlingStore(container: c, synced: false)
    }
}
