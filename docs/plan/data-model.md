# Hatchling · 数据模型详细设计（SwiftData Schema）

> v1.0 · 2026-10-20 · 配套：`tech-architecture.md`（D1 结算制 / D5 本地优先 + CloudKit）
> 目标：可直接作为 M0 编码蓝本。~~CloudKit 同步约束~~（v1.2 零云化：无 CloudKit；以下约束仍保留——无 unique 约束、属性全默认值/optional、关系最小化，作为长期数据纪律）

---

## 0. 容器与存储布局

```swift
// App Group 共享（主 App + 表盘 Widget 同一 store）· 零云（v1.2：无 CloudKit）
let config = ModelConfiguration(
    groupContainer: .identifier("group.com.hatchling.app"),
    cloudKitDatabase: .none             // 不申请开发者账号，数据 100% 本地
)
let container = try ModelContainer(
    for: Pet.self, EventLog.self, Memory.self, Archive.self,
    configurations: config
)
```

- **GameConfig 不入库**：Codable struct 存 UserDefaults（单一设备、全局一份，无需同步）
- 并发：`@ModelActor` 后台上下文执行 `reconcile` / 记忆批处理；主上下文只读喂 UI
- 弱引用策略：跨实体引用一律 UUID 字段（不用 SwiftData 关系）——父母可能已归档、事件要滚动裁剪，弱引用 + 内存合并视图最稳，也规避 CloudKit 关系同步的坑

## 1. 值类型（Codable 复合属性）

```swift
enum Species:  String, Codable, Hashable { case ghost, pod, crystal }
enum Antenna:  String, Codable, Hashable { case pointy, round, droopy, antenna }
enum EyeStyle: String, Codable, Hashable { case dot, big, sleepy }
enum Pattern:  String, Codable, Hashable { case plain, belly, stripes, spots } // plain 避开 none
enum Taste:    String, Codable, Hashable { case knowledge, play, sleep }

/// 三层基因槽：表达 / 携带 / 祖源（CryptoKitties 式）
struct GeneSlot<V: Codable & Hashable>: Codable, Hashable {
    var express: V
    var carry:   V
    var dormant: V
}

/// 性格四参数（连续值 0-1；遗传 = 均值 + 高斯漂移，不走三层槽）
struct Personality: Codable, Hashable {
    var cling: Double = 0.5       // 粘人
    var snark: Double = 0.5       // 毒舌
    var curiosity: Double = 0.5   // 好奇
    var brave: Double = 0.5       // 勇气
}

struct GeneValue: Codable, Hashable {
    // 槽位值域为含稀有 case 的 enum（定义见 breeding-algorithm.md §2.1）
    var species : GeneSlot<SpeciesGene>
    var color   : GeneSlot<ColorGene>     // 普通 ×8 + 稀有 .holo（全息体色）
    var antenna : GeneSlot<AntennaGene>
    var eyes    : GeneSlot<EyeGene>       // + 稀有 .pulseRing（脉冲环眼）
    var pattern : GeneSlot<PatternGene>   // + 稀有 .stardust（星尘纹）
    var glitch  : GeneSlot<GlitchGene>
    var taste   : GeneSlot<TasteGene>     // 口味偏好
    var shiny   : Bool = false            // 异色（1/96，羁绊加成；不遗传独立 roll）
    var personality = Personality()
}
// 传说基因（物种限定，仅突变产生、不可遗传）→ Pet.legendary
// 全局型稀有基因（行为/天赋/隐藏配方）→ Pet.rareGenes（逗号分隔）
// 完整遗传算法见 breeding-algorithm.md
```

## 2. @Model 实体

### 2.0 实体关系图（全部 UUID 弱引用，查询时内存 join）

**Pet 单实体 + 状态机**（蛋 = 尚未破壳的宠物，v1.1 简化：不单独建模）：

```
                     state 状态机（单表内流转）
    ┌─────┐ hatchAt 到期  ┌──────┐ 出发    ┌───────────┐ 到家  ┌─────────┐
    │ egg │ ════════════▶ │ home │ ──────▶ │ exploring │ ────▶ │ arrived │
    └─────┘ (state→home)   └──────┘         └───────────┘       └────┬────┘
        │                      │          （收取后回 home）           │ tap开箱
        │ parentA/B → Pet      │                                    ▼
        │ (融合时双亲必在屋)      │  release（宠物先表愿望）      回 home
        ▼                      ▼
   ┌─────────┐  release   ┌─────────┐          ┌─────────┐
   │ Archive │ ◀════════  │   Pet   │  1:N     │ EventLog│
   └─────────┘  (克隆+摘要) └─────────┘ ────────▶ └─────────┘
                                  │
                             ┌────┴─────┐
                             │  Memory  │  （独立，按天，主人/家维度；不遗传）
                             └──────────┘
```

- **孵化 = 状态转换**（`state: egg → home`），不再删表建表；蛋期字段（hatchAt/source/legend）与宠物期字段（mood/hunger/bond…）共存于 Pet，蛋期后者保持默认值
- **放生 = Pet 删、Archive 建**（克隆 + eventDigest），仅适用于非 egg 状态
- **血统查询**：Pet.parentA/B → 先查 Pet 表（本表）、未命中查 Archive 表，递归向上——Archive 的存在使谱系永不丢
- **Memory 独立于宠物**：单一主人 + 屋子共享"家的记忆"；融合只传基因，不传 Memory（v1.1 已否决记忆传承）
- **屋子占用 = `count(Pet)`**，蛋和宠物同占卡位，不再跨表计数



```swift
@Model final class Pet {
    var id: UUID = UUID()
    var name: String = ""             // 蛋期已有名字（融合时确定/任务蛋随机名）
    var gene: GeneValue?              // optional = CloudKit 约束
    var gen: Int = 0                  // 0 = 星生代
    var parentA: UUID?                // 弱引用（可能已归档）
    var parentB: UUID?
    // --- 生命周期状态机（蛋 = 尚未破壳的宠物，不单独建模） ---
    var state: String = "egg"         // egg | home | exploring | arrived
    var hatchAt: Date?                // 蛋期：孵化到期（非蛋 = nil）
    var source: String = "star"       // star | task | fuse | twin（蛋来源）
    var legend: Bool = false          // 传说蛋（破壳演出规格）
    var rareGenes: String = ""        // 全局型稀有基因，逗号分隔（GlobalGene raw）
    var birthAt: Date = Date.distantPast  // 蛋 = 产出时刻；破壳后 = 破壳时刻
    // --- 宠物期动态状态（reconcile 可变；蛋期保持默认值） ---
    var mood: Double = 70             // 0-100
    var hunger: Double = 20           // 0 饱 → 100 饿；每小时 +hungerRate
    var bond: Double = 0              // 亲密度 0-100（≥90 → 后代异色 ×3）
    var exploringSince: Date?         // state=exploring 时非 nil（结算制核心字段）
    var lastTaskDate: Date?           // 每日一次任务的判重
    var cooldownUntil: Date?          // 繁育疲劳到期
    var fuseCount: Int = 0            // 疲劳曲线索引
    var createdAt: Date = Date()
}

@Model final class EventLog {
    var id: UUID = UUID()
    var ts: Date = Date()
    var type: String = ""             // EventType raw（见下）
    var petID: UUID?
    var payload: String?              // JSON（意图/豆种/奖励明细…）
    var day: String = ""              // "2026-10-20" 冗余，按天取免日历运算
}

@Model final class Memory {           // agent memory 产物（晨间结算写入）
    var id: UUID = UUID()
    var day: String = ""              // "2026-10-20"
    var summary: String = ""          // 当天摘要（≤100 字）
    var emotion: String = ""          // 主导情绪
    var tags: String = ""             // 逗号分隔
    var isAnniversary: Bool = false   // 纪念日（周年提醒）
    var dreamSeed: String?            // 讲梦素材（早安演出用）
}

@Model final class Archive {          // 放生归档（只增不删）
    var id: UUID = UUID()
    var name: String = ""
    var gene: GeneValue?
    var gen: Int = 0
    var parentA: UUID?
    var parentB: UUID?
    var birthAt: Date?
    var releasedAt: Date = Date()
    var eventDigest: String = ""      // 一生事件摘要（放生时压缩）
}
```

### EventType 枚举（payload JSON schema 随类型定义）

```swift
enum EventType: String {
    case born                    // {source: star/task/fuse/twin}
    case feed                    // {bean: knowledge/play/sleep, liked: Bool}
    case petted                  // {duringTalk: Bool}  打断+摸头
    case talk                    // {intent, matched: Bool}
    case exploreStart            // {goalSteps, maxHours}
    case exploreDone             // {steps, tier: standard/fallback, rewards[]}
    case hatchDone               // {name}
    case fuse                    // {partnerID, childEggID, legendary}
    case release                 // {digest}
    case sleepWake               // {at}
    case alarm                   // {snoozed: Bool}  赖床→记仇素材
    case dream                   // {memoryDay}
    case moodMilestone           // {kind}  首颗异色蛋等成就
}
```

## 3. GameConfig（UserDefaults · 不入库）

```swift
struct GameConfig: Codable {
    // 孵化与繁育
    var hatchMinutes: Int = 30
    var fuseGateHours: Int = 24              // 破壳后可融合门槛
    var fatigueHours: [Int] = [4, 8, 16, 48] // 繁育疲劳递增（末位封顶）
    // 任务
    var taskGoalSteps: Int = 4000
    var taskMaxHours: Int = 10
    var taskStartHour: Int = 8               // 早上自动出发
    // 掉落
    var eggChanceStandard: Double = 0.30     // 调参目标：自然游玩周 1-2 颗
    var partChance: Double = 0.25
    // 基因
    var mutateRare: Double = 0.025
    var mutateEpic: Double = 0.006
    var mutateLegendary: Double = 0.0008
    var shinyOdds: Double = 1.0 / 96.0
    var shinyBondMultiplier: Double = 3.0    // bond ≥90 时
    // 生活
    var maxPets: Int = 3
    var hungerRatePerHour: Double = 2.0      // 满 100 约 2 天
    var moodDecayPerDay: Double = 10.0       // 不互动自然变差
    var dailyTalkLimit: Int = 2
    var eventRetentionDays: Int = 90
}
```

## 4. 遗传算法（Engine 纯函数 · 可单测）

```swift
enum Genetics {
    /// 三层基因槽融合：每个槽从亲本 6 层池中构建子代 3 层
    static func fuse(_ a: GeneValue, _ b: GeneValue,
                     cfg: GameConfig, bond: Double,
                     rng: inout RandomNumberGenerator) -> GeneValue {
        // 对每个性状槽：
        // 1) express：roll 突变？
        //    legendary(cfg.mutateLegendary) > epic(0.006) > rare(0.025)
        //    未突变 → 42% a.express / 42% b.express / 16% 从池随机
        // 2) pool = [a.express, a.carry, a.dormant, b.express, b.carry, b.dormant]
        //    移除已上浮项 → shuffle 取 2 → carry / dormant
        // 3) shiny：shinyOdds ×（bond ≥ 90 ? shinyBondMultiplier : 1）
        // 性格：clamp(((a+b)/2 均值) + 高斯(σ=0.15), 0, 1)（四参数独立）
        // gen = max(a.gen?, b.gen?) + 1（在调用方处理，gene 不含 gen）
    }
}
```

> 设计要点：**显性稀有基因被 16% 突变通道压制**，携带层/祖源层让祖辈稀有/史诗基因可隔代上浮；**传说例外——纯 0.08% 突变，不可遗传、不上浮、无保底**。单测覆盖：突变分层概率（10 万次蒙特卡洛 vs 配置值 ±5%）、三层池不重复、性格边界、传说隔离性。

## 5. 结算引擎（Reconcile · 纯函数）

```swift
enum Reconciler {
    static func run(now: Date, steps: Int, config: GameConfig,
                    pets: [Pet]) -> [Command]
    // 返回命令列表由调用方执行（保持引擎无副作用、可测试）：
    // .updateVitals(petID, hunger, mood)  饱食度/心情随时间漂移
    // .hatchEgg(petID)      now ≥ hatchAt → state: egg → home、EventLog(born)
    // .finishExplore(petID, tier)  步数 ≥ S 提前 / 时长 ≥ T 兜底 → 奖励结算
    // .clearCooldown(petID) 疲劳到期
    // .promptDream(memoryDay)      当日首次激活 → 触发讲梦流程
    // .leaveForTask(petID)         taskStartHour 后首次激活 → 出发
}```

## 6. 数据生命周期

| 数据 | 生命周期 | 裁剪策略 |
|---|---|---|
| EventLog | 滚动 90 天 | 每日 reconcile 顺手删 `day < today-90`；放生时把该宠事件压缩进 Archive.eventDigest |
| Memory | 永久（纪念价值） | 不裁剪；量级 = 1 条/天 |
| Pet/Egg | 活体 | 放生 → Pet 删、Archive 建 |
| Archive | 永久 | 只增不删（血脉与"归档回归"伏笔的载体） |

## 7. CloudKit 同步注意事项（编码期 checklist）

- [x] 所有 `@Model` 属性带默认值或 optional（保持数据纪律）
- [x] 不使用 `@Attribute(.unique)`——唯一性由业务层 UUID 保证
- [x] 不使用 SwiftData 关系——全部 UUID 弱引用
- [ ] 复合属性（GeneValue）为 Data blob 存储，改其 Swift 定义 = 数据迁移，**发布 v1 前锁定字段**
- [ ] Widget 读同一 App Group store：只读，写入仅主 App（避免双写冲突）
- [ ] （v1.2 零云化）数据 100% 本地：卸载即丢失，备份导出功能远期兜底
- [ ] 大字段审视：EventLog.payload 控制在 <1KB；Memory.summary ≤100 字

## 8. 待办衔接

- [x] schema 定义（本文档）
- [ ] M0 落码：模型 + 容器 + App Group + CloudKit 打通真机
- [ ] Genetics.fuse 蒙特卡洛单测
- [ ] Tick.reconcile 场景单测（离家/到家/孵化/饥饿）
