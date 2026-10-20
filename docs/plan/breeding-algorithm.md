# Hatchling · 融合遗传算法设计

> v1.0 · 2026-10-20 · 配套：`data-model.md`（GeneValue 三层基因槽）、`PROJECT.md` §3.4
> 定位：`HatchlingKit/Engine/Genetics.swift` 的完整实现蓝本。纯函数、RNG 注入、全部可单测。

---

## 1. 设计目标（按优先级）

1. **惊喜结构化**：稀有/史诗基因的隔代上浮由三层池机制保证（不靠文案）；**传说 = 纯低概率突变（0.08%），不可遗传、不参与上浮、不被保底覆盖**——低概率就是传说的全部
2. **概率可配置**：全部概率集中于 GameConfig，蒙特卡洛单测校验（10 万次 ±5%）
3. **可解释**：图鉴能展示"携带层"——玩家看得见潜力，孩子只看表达
4. **不可刷**：传说不可遗传（仅突变）、繁育疲劳递增、保底计数防非酋

## 2. 基因表示

### 2.1 槽位型基因（7 槽，值域含稀有 case）

```swift
enum SpeciesGene: String, Codable { case ghost, pod, crystal }        // 无稀有度
enum ColorGene:   String, Codable { case cyan, purple, green, orange,
                                     red, blue, yellow, white          // 普通 ×8
                                     case holo }                       // 稀有·全息体色
enum AntennaGene: String, Codable { case pointy, round, droopy, forked }
enum EyeGene:     String, Codable { case dot, big, sleepy
                                     case pulseRing }                  // 稀有·脉冲环眼
enum PatternGene: String, Codable { case plain, belly, stripes, spots
                                     case stardust }                   // 稀有·星尘纹
enum GlitchGene:  String, Codable { case low, mid, high }
enum TasteGene:   String, Codable { case knowledge, play, sleep }

enum Rarity: Int, Comparable { case normal = 0, rare = 1, epic = 2, legendary = 3 }
// 每个值域提供 static rarity(of:) —— 稀有 case 映射 rare/epic，其余 normal
```

### 2.2 全局型稀有基因（不占槽，Pet.rareGenes 逗号分隔）

```swift
enum GlobalGene: String, Codable {
    // 行为类
    case afterimage, randomDance, nocturnal, echoTic       // 残影/乱数舞步/夜行/回声口癖
    // 天赋类
    case deepDig, warmCore, gachaLuck                      // 掘深/温暖核心/欧皇协议
    // 隐藏配方产出
    case glitchBody, deepSpaceMessenger                    // 故障体/深空信使
}
```

### 2.3 传说基因（Pet.legendary: String?，物种限定）

```swift
// 注册表：黑涧核心(pod) / 双生幽灵(ghost) / 双子内核(crystal)
// 规则：仅通过全局突变产生（0.08%）；不可遗传；子代物种与限定不符则突变无效
```

## 3. 融合主算法

```
fuse(parentA, parentB, config, rng) -> FusionResult
│
├─ ① species 槽遗传         42% A / 42% B / 16% 三选一随机（无稀有突变）
├─ ② legendary 全局 roll    rand < 0.08% 且注册表存在匹配 ① 物种的传说 → 表达
│                            （不匹配 → 无效，不保留）
├─ ③ 其余 6 槽逐槽遗传       fuseSlot(a, b)（见 §4，含 rare/epic 突变）
├─ ④ shiny 全局 roll        1/96 × (双亲 bond≥90 ? 3 : 1)；与槽位独立
├─ ⑤ personality 混合       四参数独立：clamp(gauss(mean(A,B), σ=0.15), 0, 1)
├─ ⑥ 全局基因继承            见 §6（隐性递减 + 至多继承 2 条）
├─ ⑦ 隐藏配方检查            见 §7（父母 express 组合 → 概率授予）
├─ ⑧ 保底计数               见 §8
└─ ⑨ gen = max(A.gen, B.gen) + 1
```

## 4. 单槽遗传算法 fuseSlot（核心）

```swift
struct SlotResult { var express, carry, dormant: G; var mutation: MutationKind? }

func fuseSlot<G: GeneVal>(_ a: GeneSlot<G>, _ b: GeneSlot<G>,
                          cfg: GameConfig, rng: inout RNG) -> SlotResult {
    let pool = [a.express, a.carry, a.dormant, b.express, b.carry, b.dormant] // 6 层池

    // ① 稀有突变分层（每槽独立，先高后低）
    if roll(cfg.mutateLegendary) {          // 0.08%
        let v = G.rarePool(.epicPlus)       // 从该槽 epic 池取（槽位无 legendary）
        return build(v, from: pool, mutation: .epic(v))
    }
    if roll(cfg.mutateEpic)  { /* 同上，epic 池 */ }
    if roll(cfg.mutateRare)  { /* 同上，rare 池（排除双亲 express 已表达的同一稀有值） */ }

    // ② 常规遗传：42% A表达 / 42% B表达 / 16% 池内随机（普通值域全域）
    let pick = weighted(0.42, 0.42, 0.16)
    let express = pick == 0 ? a.express : pick == 1 ? b.express : pool.random(rng)

    // ③ 三层池洗牌：剩余 5 项（express 取走一项后）shuffle 取 2
    var rest = pool; rest.removeAll(express 的来源项)
    rest.shuffle(rng)
    return SlotResult(express: express, carry: rest[0], dormant: rest[1])
}
```

**机制要点**：
- **突变即表达**：突变产物直接进 express（传说全屏播报、稀有当代可见）
- **隔代上浮**：carry/dormant 中的稀有/史诗基因（祖辈突变遗留）每次融合都有池抽取机会上浮——全息/星尘/脉冲环等稀有表现会隔代浮现；**传说不参与**（不可遗传，每代独立 0.08% roll）
- **稀有突变排除已表达项**：父母正表达着全息体色时，rare 突变不再吐全息（避免无效重复），但**池中已有的全息照常流动**

### 推演示例（两代）

```
Gen0 父：express=blue, carry=holo,  dormant=stripes     （曾突变全息→已传给下一代表达? 否，holo 在 carry 潜伏）
Gen0 母：express=cyan, carry=belly, dormant=holo

子代(Gen1) color 槽：池 = [blue,holo,stripes, cyan,belly,holo]
  express 抽中 belly；剩余洗牌 → carry=holo, dormant=cyan
  → Gen1 表达普通，但携带全息（图鉴显示：color 携带 ★全息体色）

Gen1 × 另一只融合：池再次含 holo（来自 carry）
  express 抽中 holo → Gen2 表达全息体色！
  → 图鉴故事："爷爷带回来的颜色，隔了一代回来了"
```

## 5. 突变系统汇总

| 层级 | 概率/槽 | 产物 | 表达 | 可遗传 |
|---|---|---|---|---|
| legendary（全局单次） | 0.08% | 物种限定传说 | 当代全屏播报 | **否** |
| epic | 0.6% | 槽位 epic 池随机 | 当代表达 | ✅ 进三层池 |
| rare | 2.5% | 槽位 rare 池随机（排除双亲已表达同值） | 当代表达 | ✅ 进三层池 |
| 普通随机 | 16%/槽 | 槽位普通值域全域 | 当代表达 | ✅ |
| 定向遗传 | 42%+42% | 亲本 express | — | ✅ |

- `gachaLuck`（欧皇协议）持有者参与融合：全部突变概率 ×2（含 legendary）
- 概率全在 GameConfig：`mutateLegendary/mutateEpic/mutateRare`

## 6. 全局基因继承（行为/天赋类）

```
候选池 = 父.rareGenes ∪ 母.rareGenes（去重）
每条按类别继承概率独立 roll：行为类 40% / 天赋类 30%
候选命中 → shuffle 取至多 2 条进入子代（防无限堆叠）
获得/继承 GlobalGene 时 EventLog 记录（图鉴点亮）
```

- 全局基因**不产生于常规突变**：获得途径 = 遗传 + 隐藏配方 + 任务特殊奖励（远期）
- `deepDig`（掘深协议）天赋效果：任务标准档蛋掉率 +15%；`gachaLuck`：突变 ×2；`warmCore`：饥饿速率 -20%——效果引擎读 rareGenes 即可

## 7. 隐藏配方（规则引擎）

```swift
struct HiddenRecipe {
    let id: String
    let match: (GeneValue, GeneValue) -> Bool   // 双亲 express 组合条件
    let probability: Double
    let grant: GlobalGene
}
// 首批 2 条：
glitchBody:      A.glitch == .high && B.glitch == .high           → 5%  → .glitchBody
deepSpace:       双亲并集覆盖 {color==.blue, antenna==.droopy, pattern==.stripes}
                                                                  → 8%  → .deepSpaceMessenger
```

- 融合末尾顺序检查，命中即 grant 并记录 EventLog（隐藏基因首次发现走"图鉴新条目"演出）
- 规则表为代码内静态数组，新增配方 = 加一条（个人项目不发版焦虑，TestFlight 秒发）

## 8. 保底机制（主人级）

```
UserDefaults: fuseCountSinceRare（跨宠物计数）
每次融合后判定"稀有收获"：任一槽 epic/legendary 突变 或 shiny 或 新获全局稀有基因
  稀有收获 → 计数归零
  否则     → 计数 +1；计数 ≥ 10 → 本轮强制一个随机槽注入 rare 突变 → 归零
```

注意：**carry 层继承稀有不算稀有收获**（它还没表达）——保底只看"看得见的惊喜"。

## 8.5 调试后门（传说强制）

```swift
// 仅 DEBUG 编译生效——生产/TestFlight 包物理隔离，无运行时开关
enum LegendDebug {
    static var forceLegendary: Bool {
        #if DEBUG
        // 方式 1：launch argument（Xcode scheme Arguments 加 "-forceLegendary"）
        // 方式 2：Debug 隐藏面板开关（主页长按版本号 10 次唤出）
        return ProcessInfo.processInfo.arguments.contains("-forceLegendary") || debugPanelToggle
        #else
        return false
        #endif
    }
}
// 生效点：fuse() 内 legendary roll —— forceLegendary 为 true 时直接命中
// EventLog.payload 标记 {"debug": true} → 图鉴角标「DEBUG」，与正式收集区分
```

对应关系：网页原型 `?legend=1`（watch-prototype.html / rare-gene-lab.html）= 同一后门的 Web 版。

## 9. 双星同孵（社交 P0 预留）

```
两台设备各出一只 → 各自本地跑 fuse(我的A, 你的B)：
  槽位三层池：结果一致（同输入同算法，但 rng 独立 → 表达组合独立）
  shiny / personality：完全独立 roll
  → 双胞胎 = 基因池同源、表现各异的两个个体
```

## 10. 概率校验（单测要求）

| 用例 | 方法 | 通过标准 |
|---|---|---|
| 槽位突变率 | 蒙特卡洛 10⁵ 次/槽 | 实测频率 vs 配置 ±5% |
| 三层池完整性 | 属性测试 | express/carry/dormant 均来自亲本 6 层池（突变除外）；池大小守恒 |
| 隔代上浮 | 500 次三代模拟 | 祖辈稀有/史诗基因在孙代表达次数 > 0 且随深度衰减 |
| 传说隔离 | 10⁵ 次 | legendary 仅由全局突变产生；遗传路径零产出；保底永不触发 legendary |
| 性格分布 | 10⁴ 次 | 均值 ≈ 亲本均值 ±0.02，σ ≈ 0.15 ±0.02 |
| 保底 | 10³ 次连续融合 | 最长非稀有间隔 ≤ 10 |
| shiny 加成 | 10⁵ 次 | bond≥90 组频率 ≈ 3× 基线 ±10% |

## 11. 遗传可视化（图鉴「基因详情」页）

```
┌ 表达层 ────────────────┐
│ 星际蓝 · 光环 · 星芒眼…  │  ← 现在的样子
├ 携带层 ────────────────┤
│ ★ 全息体色 · 数据流      │  ← 下一代可能上浮（育种家的乐趣）
├ 祖源层 ────────────────┤
│ 警报红 · …              │  ← 更深的可能
└────────────────────────┘
```

手表端只显示表达层；携带/祖源层在 iPhone 图鉴（二期），手表上融合确认页给一行"★ 携带稀有 2"角标。

## 12. 参数汇总（全部进 GameConfig）

| 参数 | 默认 | 说明 |
|---|---|---|
| mutateRare / Epic / Legendary | 2.5% / 0.6% / 0.08% | 每槽独立 / legendary 全局单次 |
| shinyOdds / shinyBondMultiplier | 1/96 / ×3 | bond ≥90 触发 |
| personalitySigma | 0.15 | 性格高斯漂移 |
| inheritBehavior / inheritTalent | 40% / 30% | 全局基因分类继承率 |
| maxInheritedGlobals | 2 | 全局继承上限 |
| pityThreshold | 10 | 保底阈值（主人级） |
| recipeGlitchBody / recipeDeepSpace | 5% / 8% | 隐藏配方概率 |
