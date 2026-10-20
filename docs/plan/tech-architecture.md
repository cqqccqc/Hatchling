# Hatchling · 技术架构设计

> v0.2 · 2026-10-20 · 配套：`PROJECT.md`（v2.2）、`watch-design-spec.md`（v1.2）、`data-model.md`（v1.0）
> 平台：watchOS 11+ · SwiftUI · 基准 46mm · v1 纯手表（数据层按跨端设计）
>
> v0.2：从"选型文档"升级为工程蓝图——新增代码架构（§3）、核心协议与接口（§4）、关键流程时序（§6）、云端协议要点（§7）

---

## 1. 架构总览

```
┌─ watchOS 设备 ──────────────────────────────────────────────┐
│  ┌─ Watch App ──────────┐   ┌─ Widget Extension ──────────┐ │
│  │ SwiftUI 场景层        │   │ WidgetKit TimelineProvider   │ │
│  │ (主页/屋子/聆听/演出)  │   │ (表盘 Complication, 只读)     │ │
│  └──────────┬────────────┘   └──────────────┬──────────────┘ │
│             │        App Group 共享 store    │                │
│  ┌──────────┴───────────────────────────────┴────────────┐ │
│  │ HatchlingKit (SPM)                                     │ │
│  │  Domain(纯值) ← Engine(纯函数) ← App层组合              │ │
│  │  Persistence(SwiftData+CloudKit) · Render(SpriteKit)   │ │
│  │  Audio(方波) · Gateway(豆包直连) · AgentMemory           │ │
│  └──────────────────────────┬────────────────────────────┘ │
└─────────────────────────────┼───────────────────────────────┘
                              │ HTTPS / WebSocket（直连，单 key）
┌─────────────────────────────┴───────────────────────────────┐
│ 云端智能：火山引擎/豆包系三件套（讯飞为 ASR 备选，见 D3/D7）      │
│  流式 ASR · doubao LLM(OpenAI 兼容) · 流式 TTS                 │
└──────────────────────────────────────────────────────────────┘
数据面（不经云端厂商）：CloudKit 私有库自动同步 · HealthKit 本地 · WatchConnectivity(二期)
```

## 2. 核心架构决策

| # | 决策 | 要点 |
|---|---|---|
| D1 | **结算制模拟** | 无后台常驻。状态 = f(事件日志， now)：激活/刷新时 `Reconciler.run()` 输出 `[Command]`，由调用方落库。零后台、零心跳、抗重启 |
| D2 | **程序化烘焙 + 图层合成** | 逐像素实时绘制不可行。构建期 Baker target 用同一份 Swift 绘制代码烤 PNG 图集（分层：身体/配饰/特效），运行时 SpriteKit GPU 合成，30fps |
| D3 | **云端直连，无网关（🚧 暂缓——v0.3 裁决：对话云端方案待重新讨论，v1 先用本地意图池）** | 留档：豆包全家桶起步（流式 ASR + doubao LLM + TTS 单 key），讯飞为 ASR 备选；prompt 组装在端上；轻代理网关降为远期可选 |
| D4 | **晨间记忆结算（🚧 暂缓：依赖 LLM，随对话方案一并重议；Memory 表保留）** | 留档：当日首次激活把昨日 EventLog 压成一次 LLM 调用 → Memory 落库 → 触发讲梦演出 |
| D5 | **本地优先 + CloudKit 兜底** | SwiftData store 在 App Group；未登录/无网纯本地照玩；`quotaExceeded` 显式提示 |
| D7 | **对话走级联（🚧 暂缓：级联/E2E 整体方案待重新讨论，本节仅留档）** | 留档：结构化信号是交互刚需，文本 LLM 最可靠；半双工聆听界面废掉 E2E 全双工优势；E2E 为演进方向，只动 Gateway 层 |

## 3. 代码架构

### 3.1 包结构（HatchlingKit 单 SPM 包内分层 + 3 个 App Target）

```
Hatchling/
├── packages/HatchlingKit/           # SPM 包，全部业务核心
│   ├── Sources/Domain/              # 纯值类型，零依赖（可跨端共享）
│   │   ├── Entities.swift           #   Pet(含蛋期状态)/EventLog/Memory/Archive @Model
│   │   ├── ValueTypes.swift         #   GeneValue/GeneSlot/Personality/Species…
│   │   ├── Events.swift             #   EventType + payload 定义
│   │   ├── Snapshots.swift          #   PetSnapshot（@Model→值快照，进引擎）
│   │   └── GameConfig.swift         #   可配置参数（UserDefaults 持久）
│   ├── Sources/Engine/              # 纯函数，只依赖 Domain——全部可单测
│   │   ├── Reconciler.swift         #   run(now,steps,config,snapshots) → [Command]
│   │   ├── Commands.swift           #   Command 枚举 + CommandApplier
│   │   ├── Genetics.swift           #   三层基因槽融合 + 突变 roll
│   │   ├── TaskPlanner.swift        #   任务状态机（步数/倒计时/奖励分档）
│   │   ├── RhythmPlanner.swift      #   节律：早安梦/晚安/闹钟/主动开口预算
│   │   └── BreedingRules.swift      #   融合校验（冷却/24h门槛/数量上限）
│   ├── Sources/Persistence/
│   │   ├── Store.swift              #   ModelContainer 装配（App Group + CloudKit）
│   │   ├── Repositories.swift       #   Pet/Event/Memory/Archive 读写
│   │   └── ModelActor.swift         #   后台 @ModelActor（reconcile 落库/批处理）
│   ├── Sources/Render/
│   │   ├── PixelLayers.swift        #   图层描述（身体帧索引/天线/眼/花纹/特效）
│   │   ├── AnimationStates.swift    #   姿态状态机 → (帧序列, 偏移, eyeState)
│   │   ├── PetScene.swift           #   SpriteKit 场景：图层合成 + 帧驱动
│   │   └── AtlasLoader.swift        #   烘焙图集加载（按物种×色板检索）
│   ├── Sources/Audio/
│   │   ├── SquareWave.swift         #   AVAudioEngine 方波合成
│   │   └── VoiceMood.swift          #   性格参数 → 音高/音色调制
│   ├── Sources/Gateway/             # 云端大脑（厂商隔离层）
│   │   ├── Protocols.swift          #   SpeechRecognizing/SpeechSynthesizing/BrainClient
│   │   ├── DoubaoASR.swift          #   火山流式语音识别 WebSocket 客户端
│   │   ├── DoubaoLLM.swift          #   OpenAI 兼容 chat/completions 流式
│   │   ├── DoubaoTTS.swift          #   火山 TTS 流式客户端
│   │   ├── PromptBuilder.swift      #   人设+性格+Memory+今日事件 → system prompt
│   │   ├── ChatModels.swift         #   ChatPrompt/BrainDelta/ChatAction
│   │   └── LocalFallback.swift      #   本地意图池（chips 同源，降级用）
│   ├── Sources/AgentMemory/
│   │   ├── MemorySummarizer.swift   #   昨日事件 → 一次 LLM → Memory
│   │   └── DreamComposer.swift      #   dreamSeed → 讲梦演出内容
│   └── Sources/Support/
│       ├── Haptics.swift · Clock.swift · AppGroup.swift
├── WatchApp/                        # SwiftUI 场景层（薄，组合 HatchlingKit）
│   ├── RootView · HomeScene(三态) · HouseScene · ListenScene
│   ├── Ceremonies/                  #   开局/融合/放生 演出视图
│   ├── AppViewModel.swift           #   activate() 触发 reconcile → 状态分发
│   └── NotificationService.swift    #   毒舌闹钟（本地通知）
├── Widget/                          # ComplicationProvider（TimelineProvider，只读）
└── Baker/                           # macOS 命令行 target（构建期跑烘焙）
    └── bake.swift                   #   同一份绘制代码 → PNG 图集输出到 bundle
```

**依赖方向**（编译器强制）：`Domain ← Engine/Persistence/Render/Audio/Gateway/AgentMemory ← App Targets`。Engine 不 import 任何 IO 框架。

### 3.2 渲染烘焙流水线（D2 展开）

```
绘制代码（Render/PixelLayers 逻辑）
   ├─ 运行时：SpriteKit 合成烘焙帧（GPU）
   └─ 构建期：Baker target 跑同一逻辑 → 图集 PNG
        身体帧：3 物种 × 8 色 × ~12 姿态 ≈ 288 张（48×48，<1KB/张）
        配饰层：天线 4 + 眼 5(dot/big/sleepy/closed/happy/wide) + 花纹 4
        特效：glitch 用 shader/运行时像素扰动，溶解=alpha 抖动
       总计 < 1MB，App bundle 内置
动画 = 姿态帧序列（idle 呼吸 2 帧 ±1.5px、happy 4 帧、eat 含豆子飞入帧）
```

## 4. 核心协议与接口

```swift
// ── Gateway 协议（厂商可替换：豆包起步，讯飞 ASR 备选只换实现） ──
// BrainClient = "对话大脑(LLM)"的抽象插座：
//   · 可替换：换厂商/E2E 演进(D7) = 新增实现文件，场景层零改动
//   · 可测试：MockBrainClient 返回固定脚本，M2 无云端也能跑通全部 UI
//   · 流式统一：HTTP SSE / WebSocket 差异封装在实现内，UI 只消费 BrainDelta
//   · 降级注入：超时可无感切到 LocalFallback（本地意图池，同一协议）
protocol SpeechRecognizing {
    func startStream() throws -> ASRStream           // 流式：边说边转写
    func transcribe(pcm: Data) async throws -> String // 一次性兜底
}
protocol SpeechSynthesizing {
    /// 流式合成，返回音频分片（mp3/pcm），首包到达即可播
    func synthesize(_ text: String, voice: VoiceConfig) async throws -> AsyncStream<Data>
}
protocol BrainClient {
    func chat(_ prompt: ChatPrompt) -> AsyncThrowingStream<BrainDelta, Error>
}

struct ChatPrompt {
    let system: String            // PromptBuilder 产物：人设+性格参数+儿童护栏
    let memoryInjects: [String]   // 近 7 天 Memory.summary
    let todayEvents: [String]     // 今日事件摘要（事件溯源的对话侧注入）
    let userText: String          // ASR 转写
}
enum BrainDelta {
    case text(String)             // 增量文本（首句触发 TTS，≤14 字由网关侧校验截断）
    case action(ChatAction)       // 终帧结构化动作 —— 交互链枢纽
}
struct ChatAction: Codable {
    let intent: String            // greet/food/dance/dream/mine/night/love/unknown
    let anim: String              // happy/eat/sleep/teleport/annoyed/idle
    let moodDelta: Double
    let say: String               // ≤14 字
}

// ── Engine（纯函数，输入值快照输出命令；无 IO、无 @Model 依赖） ──
enum Command: Equatable {
    case updateVitals(petID: UUID, hunger: Double, mood: Double)
    case leaveForTask(petID: UUID)
    case finishExplore(petID: UUID, tier: TaskTier, rewards: [Reward])
    case hatchEgg(petID: UUID)      // state: egg → home
    case clearCooldown(petID: UUID)
    case promptDream(day: String)
}
enum Reconciler {
    static func run(now: Date, stepsToday: Int, config: GameConfig,
                    pets: [PetSnapshot],
                    todayEvents: [EventRecord]) -> [Command]
}
// PetSnapshot 等为 Domain 值快照；Repository 负责 @Model ⇄ Snapshot 转换
// 调用方（AppViewModel.activate / Widget timeline）执行 CommandApplier 落库
```

**设计规则**：Engine/Gateway 协议只认值类型 → 单测无需数据库/网络（协议 mock）；厂商替换只新增 `XxxASR.swift` 等实现文件。

## 5. 数据模型

完整 schema 见 **`data-model.md`**（v1.1）：4 个 @Model（Pet 含蛋期状态机/EventLog/Memory/Archive）+ 三层基因槽 GeneValue + GameConfig；UUID 弱引用、无关系、CloudKit 约束 checklist、EventLog 90 天滚动裁剪、遗传算法与蒙特卡洛单测要求。此处不重复。

## 6. 关键流程时序

### 6.1 激活结算（每次抬腕/切前台）
```
scenePhase=.active / Complication tap
 → AppViewModel.activate()
     snapshots = PetRepository.snapshots()              // @Model → 值快照
     steps     = await HealthKit.stepsToday()
     commands  = Reconciler.run(now, steps, config, snapshots, todayEvents)
     ModelActor.apply(commands)                          // 写库
     → 状态分发：主页三态切换 / 讲梦演出 / 开箱提示 / 表盘 reload
```

### 6.2 对话（🚧 暂缓——整体方案待重新讨论；v1 对话形态 = 本地意图池 + emoji 反馈，无云端。以下留档）
```
用户        WatchApp            Gateway 层              豆包云端
 │ tap 🎤    │                   │                       │
 │──────────▶│ openListen()      │                       │
 │  说话      │ AVAudioEngine ═══│══ ASR 流式(WS) ═══════▶│
 │           │  (静音检测停止)     │◀─ 转写增量 ────────────│
 │ tap ✓     │                   │                       │
 │──────────▶│ PromptBuilder.build(人设+性格+Memory+今日事件)
 │           │── BrainClient.chat(stream) ───────────────▶│
 │           │◀─ .text(增量) ──│  首句到达 → 触发 TTS      │
 │           │── SpeechSynthesizing.synthesize ──────────▶│
 │           │◀─ audio chunks ─│                       │
 │ 听到声音   │ .action 落 EventLog + emoji + anim + mood │
 ✗ 任一环 >6s → LocalFallback：chips 同源意图池 + 随机 emoji
```

### 6.3 表盘 timeline
```
WidgetKit 请求 → Provider.getTimeline()
  读 App Group store（只读快照）→ 姿态序列 = 状态机 + 稳定随机种子
  → 16-24 entry（20-30min/条）→ AOD 静态休眠帧 → completion(timeline)
App 内关键事件（出发/到家/孵化/融合）→ WidgetCenter.reloadAllTimelines()
```

### 6.4 任务生命周期（结算式）
```
[当日首次激活 且 now.hour ≥ taskStartHour 且 lastTaskDate ≠ today]
  → Command.leaveForTask → exploringSince=now → 主页/表盘探险态
[每次激活]
  steps = HealthKit.stepsToday()
  steps ≥ S(goal)      → finishExplore(.standard)   提前收工
  时长 ≥ T(maxHours)   → finishExplore(.fallback)   倒计时兜底
[完成] 奖励结算（标准档含蛋 roll）→ state=arrived → tap 开箱 → EventLog
```

### 6.5 融合
```
选两只 → BreedingRules.validate（冷却/24h 门槛/≤3 只）
→ Genetics.fuse(a.gene, b.gene, cfg, bond)   // 三层槽 + 突变分层 roll
→ 新 Pet(state: .egg, hatchAt=now+30min) → 仪式动画 → 双亲 fuseCount+1
→ cooldownUntil = now + fatigue[min(fuseCount, 3)]
```

### 6.6 晨间记忆（D4）
```
当日首次激活 → 昨日有 EventLog？
→ PromptBuilder.memory(昨日事件) → BrainClient.chat() 单次调用
→ 解析 JSON {summary, emotion, tags, anniversary, dreamSeed}
→ Memory 落库 → DreamComposer 演出（💤✨ + 内容性 emoji）
无网：跳过顺延，下次激活补结算
```

## 7. 云端协议要点（🚧 暂缓——随对话方案重议时恢复；以下仅留档）

| 能力 | 接入 | 要点 |
|---|---|---|
| ASR | 火山流式语音识别 WebSocket（openspeech.bytedance.com） | 16k mono PCM 分片 + JSON 控制帧；X-Api-Resource-Id；返回增量转写 |
| LLM | OpenAI 兼容 `POST /api/v3/chat/completions`（ark.cn-beijing.volces.com） | `stream=true`；`response_format: json_object` 约束 ChatAction；model=doubao-lite 系 |
| TTS | 火山语音合成 WebSocket/HTTP 流式 | mp3/pcm 分片；音色实测选型（萌系/童声向）；SSML 调语速 |
| 备选 | 讯飞流式 ASR（WebSocket） | 仅实现 `SpeechRecognizing` 协议新实现，其余不动 |

**儿童护栏**：写入 system prompt（角色锁定/话题边界/拒绝清单）+ LLM 输出后端上二次校验（关键词表 + say 长度截断）。

## 8. 降级策略

| 故障 | 行为 |
|---|---|
| 无网 | 纯本地：chips 意图池 + emoji 反馈；任务/结算全本地 |
| 未登录 iCloud | 纯本地模式常驻，HUD 小图标提示 |
| ASR 失败/空结果 | unknown 意图（本地随机 emoji）+ chips 兜底 |
| LLM 超时 6s | 同上；云端重试 1 次由客户端控制 |
| TTS 失败 | 静音 + emoji 照常（体验降级不中断） |
| CloudKit quota | 像素风提示「⚠ 云端仓库满了」；本地照玩 |
| HealthKit 拒绝 | 任务退化：按时长结算，步数进度隐藏 |

## 9. 性能与功耗

前台 30fps（SpriteKit GPU 合成），离开前台停渲染；AOD 静态帧；timeline 16-24 entry/天；零后台常驻；方波合成无文件 IO；TTS 流播完即释放。目标：日常互动对表电无感。

## 10. 风险清单

| 风险 | 等级 | 对策 |
|---|---|---|
| 童声 ASR 识别率 | **高** | 真机实测先行；豆包/讯飞/Whisper 三候选；chips 永远兜底 |
| SwiftData watchOS 成熟度 | 中 | 已锁 watchOS 11；数据层隔离于 Persistence，降级 Core Data 只动一层 |
| WidgetKit 刷新预算 | 中 | entry 保守（16-24）；事件驱动 reload 优先 |
| LLM 结构化输出漂移 | 中 | json_object + 端上 schema 校验 + 截断；失败走本地意图池 |
| SpriteKit 表现 | 低 | 图层 <10、图集 <1MB；兜底 UIImage 合成 |

## 11. 里程碑

| 阶段 | 内容 | 验收 |
|---|---|---|
| M0 | 工程骨架：Xcode + HatchlingKit + App Group + CloudKit | 空 app 真机同步通 |
| M1 | 渲染：Baker 烘焙 + SpriteKit 姿态动画 | 真机 30fps 三物种 |
| M2 | 游戏循环：Reconciler + 主页三态 + 喂养 + 屋子 + 蛋 | 完整养一只（无对话） |
| M3 | 对话：🚧 暂缓（方案待重新讨论）；v1 用本地意图池 + emoji 反馈替代 | 本地对话体验成立 |
| M4 | 表盘：complication timeline + 心情点 | 抬腕见它，预算内 |
| M5 | 育种：三层基因 + 融合 + 血统谱 + 放生归档 | 三代血脉树成立 |
| M6 | 节律：HealthKit 睡眠/步数 + 早安梦话 + 闹钟 | 它知道你几点睡 |
| M7 | 社交 P0 双星同孵 + 打磨 | 两块表孵出双胞胎 |
