import Foundation
#if canImport(HealthKit)
import HealthKit

/// HealthKit 客户端（M6 节律）：步数查询 + 授权
/// macOS（Baker）无 HealthKit——canImport 守卫，仅 watchOS/iOS 生效
public final class HealthKitClient: ObservableObject {
    public static let shared = HealthKitClient()
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 请求读取授权（步数/睡眠）。已授权时幂等。
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            return false
        }
    }

    /// 今日累计步数（HealthKit 无数据/未授权 → 0，任务走倒计时兜底）
    public func stepsToday() async -> Int {
        guard isAvailable else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stat, _ in
                let steps = stat?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                cont.resume(returning: Int(steps))
            }
            store.execute(query)
        }
    }
}

#else

/// macOS（Baker）占位：无 HealthKit
public final class HealthKitClient: ObservableObject {
    public static let shared = HealthKitClient()
    public init() {}
    public var isAvailable: Bool { false }
    @discardableResult
    public func requestAuthorization() async -> Bool { false }
    public func stepsToday() async -> Int { 0 }
}

#endif
