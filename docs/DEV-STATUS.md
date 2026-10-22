# Hatchling · 开发状态文档

> 更新：2026-10-22 · 里程碑进度：M0 ✅ M1 ✅ M1.5 ✅ M2 ✅ M4 ✅ M5 ✅ M6.1 ✅（M3/M6.2/M7 见 §6 暂缓区）
> 本文档是开发接续点：已完成清单 / 代码实况 / 调试指南 / 踩坑记录 / 剩余路线。
> 产品定义看 `docs/plan/PROJECT.md`（v2.3），技术设计看 `docs/plan/tech-architecture.md`（v0.4），会话入口看根目录 `CLAUDE.md`。

---

## 1. 当前可玩状态

模拟器安装后（`-demoFast -demoHome` 启动）即可体验的完整闭环：

```
星空坠蛋 → 30s 孵化 → 在家互动（摸头❤️ / 喂三豆 / 看它呼吸眨眼卡信号）
→ 次日自动出门挖矿（演示 90s）→ 回家带礼物 → 收取开箱（可能出蛋）
→ 屋内两只可融合（仪式演出 → 新基因蛋）→ 满 3 只长按放生（🕊 送行 → Archive 归档）
→ 表盘/智能叠放常驻（宠物帧 + 心情点）
```

正式节奏（真机默认）：孵化 30 分钟 · 任务 10 小时 · 融合门槛 24 小时 · 冷却首档 4 小时。

## 2. 已实现功能（按里程碑）

| 里程碑 | 内容 | 验证状态 |
|---|---|---|
| M0 骨架 | xcodegen 工程、HatchlingKit SPM 包、SwiftData store 三级降级链（AppGroup+Cloud→AppGroup 本地→默认本地）、Swift Testing 框架 | 模拟器构建/运行/单测 ✅ |
| M1 渲染 | 采样器 JS → Swift 移植（PixelGrid + 三物种 + 眼 8 态 + 天线 4 型 + 花纹 5 种 + 星空）；Baker 烘焙 379 帧图集；PetScene SpriteKit 图层合成（呼吸/眨眼/双帧） | 烘焙帧人工检 + 模拟器显示 ✅ |
| M1.5 生命感 | glitch 基因抖动（low 9s/mid 5.5s/high 2.5s）、playHappy（happy 眼+蹦跳+像素心粒子）、playAnnoyed（X 眼+摇头）、moodPulse/annoyPulse 脉冲接线 | 构建 ✅ 动画实机手感待反馈 |
| M2 循环 | Genetics.fuse（三层池/突变分层/传说隔离/shiny/性格高斯/全局继承/隐藏配方/保底）+ 12 单测；Reconciler 结算引擎（孵化/任务双条件/增量漂移）；主页：当前宠物大卡 + 摸头 + 喂豆 chips + 矿洞探险卡 + 收取 + 屋子小卡切换 | 模拟器全自动生命周期 ✅（坠蛋→孵化→出发→兜底收取）|
| M4 表盘 | Widget extension（accessoryCircular/Rectangular）；App Group 只读；AtlasComposer 实时合成帧；timeline 24 条 ×25min；心情点；App 事件触发 reload | 构建/安装 ✅ 表盘槽位添加待真机 |
| M4.5 伪表盘 | 智能叠放大卡：星空铺满 + 宠物 84×84 居中 + 名字/心情条/异色✨ | 构建 ✅ 叠放显示待真机 |
| M5 育种 | 🧬 融合模式（选两只→校验→fuse→仪式 fullScreenCover 四相→蛋入屋→双亲冷却翻倍→保底计数）；放生（🌍 愿望→🕊 确认→Archive 归档落库）；-demoFuse 自动验证 | 模拟器全流程 ✅（占用 2→3）|
| M6.1 步数闹钟 | HealthKitClient（授权+今日步数）；任务双条件（步数主/倒计时兜底）；探险卡 👣 步数；毒舌闹钟（性格调制语气，每日 8:00 本地通知） | -demoSteps=4500 标准档 ✅ 授权弹窗/真机闹钟待真机 |
| 发布打包 | App 图标（Baker 烘制 1024 + AssetCatalog）；AOD 常亮静态帧（scenePhase）；正式/演示节奏双轨（-demoFast） | 构建/截图 ✅ |

## 3. 代码架构实况

```
Hatchling/
├── project.yml                 # xcodegen 定义（改后或增删文件后须 xcodegen generate）
├── Hatchling.xcodeproj/        # 生成物（入库）
├── packages/HatchlingKit/      # 核心逻辑 SPM 包（watchOS 11 + macOS 15）
│   ├── Package.swift           # targets: HatchlingKit(库) / Baker(macOS 可执行) / Tests
│   ├── Sources/HatchlingKit/
│   │   ├── Domain/             # ValueTypes(三层基因槽 enums/GeneSlot/GeneValue)
│   │   │                       # Entities(@Model: Pet 状态机/EventLog/Memory/Archive)
│   │   │                       # GameConfig(UserDefaults 持久)
│   │   ├── Engine/             # Genetics.fuse(三层池/突变/保底) · Reconciler(结算命令)
│   │   │                       # BreedingPity(主人级保底计数)
│   │   ├── Persistence/        # Store.make() 三级降级（AppGroup 容器）
│   │   ├── Render/             # Pixel.swift(Pixel/Palette/PixelGrid)
│   │   │                       # CreatureRenderer(三物种绘制) · Rasterize(CGImage/PNG/放大)
│   │   │                       # PetScene(SpriteKit 动画) · AtlasComposer(实时合成)
│   │   ├── Health/             # HealthKitClient（canImport 守卫，macOS 空实现）
│   │   └── Resources/Atlas/    # Baker 产物 379 帧（.copy 进 bundle）
│   ├── Baker/main.swift        # swift run Baker [atlas目录] [icon输出路径]
│   └── Tests/HatchlingKitTests/# Domain 冒烟 + Genetics 蒙特卡洛（12 项）
├── WatchApp/                   # 手表 app（SwiftUI）
│   ├── HatchlingApp.swift      # 入口，装配 store
│   ├── RootView.swift          # 主页：HUD/大卡/动作行/喂豆面板/小卡/结算接线
│   ├── CurrentPetCard(在 RootView.swift 内)  # 大卡：蛋/活体/探险/收取四态
│   ├── PetSpriteView.swift     # SpriteKit 包装（moodPulse/annoyPulse/aod）
│   ├── NotificationService.swift  # 毒舌闹钟（本地通知）
│   ├── AudioFeedback.swift     # beep/chirp/hapticPulse（音效占位）
│   └── Hatchling.entitlements  # App Group
├── Widget/HatchlingWidget.swift + Widget.entitlements
└── WatchApp/Assets.xcassets/AppIcon.appiconset/  # Baker 烘制的 1024 图标
```

**依赖方向**：Domain ← Engine/Persistence/Render/Health ← WatchApp/Widget。Engine 纯函数（值快照输入、命令输出），全部可单测。

## 4. 构建 / 运行 / 调试速查

```bash
# 工程再生成（增删源文件或改 project.yml 后必须）
xcodegen generate

# 构建（模拟器，免签名）
xcodebuild -project Hatchling.xcodeproj -scheme Hatchling -sdk watchsimulator \
  -configuration Debug -derivedDataPath ./build build CODE_SIGNING_ALLOWED=NO

# 单测（12 项：Domain 冒烟 + Genetics 蒙特卡洛）
swift test --package-path packages/HatchlingKit

# 烘焙图集 + App 图标（绘制代码改动后必须重跑）
cd packages/HatchlingKit
swift run Baker Sources/HatchlingKit/Resources/Atlas ../../WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png

# 安装到模拟器 + 启动
xcrun simctl install <UDID> build/Build/Products/Debug-watchsimulator/Hatchling.app
xcrun simctl launch <UDID> com.hatchling.watch [参数…]
```

**演示参数**（可组合）：

| 参数 | 作用 |
|---|---|
| `-demoFast` | 演示节奏：孵化 30s / 任务 90s / 融合门槛 10s / 冷却 30s（默认正式：30min/10h/24h/4h） |
| `-demoAutospawn` | 空屋自动坠一颗蛋 |
| `-demoHome` | 直接一只活体宠物（当日已出勤，不被自动派工） |
| `-demoTwo` | 直接两只活体（测融合前置） |
| `-demoFuse` | 两只 + 3 秒后自动融合（看仪式演出） |
| `-demoFeed` | 启动即打开喂豆面板 |
| `-demoSteps=N` | 注入步数（≥4000 验证任务标准档提前收工） |
| `-noNotifications` | 跳过闹钟授权弹窗 |

**模拟器手动验证完整循环**：`-demoFast` 启动 → 点 ✨ 坠蛋 → 30s 后点破壳 → 摸头/喂豆 → 点 ⛏ 出发 → 90s 后点它收礼物 → 🧬 选两只融合 → 长按小卡放生。

## 5. 踩坑记录（重要——新会话必读）

1. **xcodegen 显式文件列表**：WatchApp/、Widget/ 下**增删源文件必须 `xcodegen generate`**；只改文件内容不需要
2. **SKSpriteNode() 无参后赋 texture 不会自动设 size**（保持 0×0 不可见）——必须显式 `size = 48×48`
3. **SwiftData @Model 默认值必须全限定类型名**：`var x: Date = .distantPast` 会报错（@Model 宏限制），写 `= Date.distantPast`
4. **HealthKit 缺用途声明即 abort**：Info.plist 必须有 NSHealthShareUsageDescription（已配于 project.yml INFOPLIST_KEY）
5. **Widget Info.plist 与 GENERATE_INFOPLIST_FILE 冲突**：widget target 用 xcodegen `info:` 生成 plist 保 NSExtension 键，勿开 GENERATE
6. **模拟器通知授权弹窗**：`#if !targetEnvironment(simulator)` 编译排除（系统会重放 pending 请求，TCC reset 也清不掉）
7. **demo 注入优先级**：-demoSteps 必须同步先于 HealthKit await 设置，且 reconcile 节流刷新在 demo 注入时跳过
8. **宠物孵化/诞生当日免任务**（lastTaskDate=now）：否则刚出生即被自动派工，互动窗口消失
9. **pixel 坐标系**：PixelGrid y 向下（图像语义），SpriteKit 显示 PNG 时系统处理翻转，节点坐标 y 向上——同帧内视觉一致
10. **编辑脚本教训**：python 批量替换必须 assert 锚点 + 失败即中止（曾静默失败造成分支丢失）；多轮编辑后 grep 复核关键分支存在性

## 6. 暂缓区（须用户决策后恢复）

| 项 | 状态 | 恢复条件 |
|---|---|---|
| M3 对话（语音/云端大脑） | 🚧 级联/E2E 方案均留档于 tech-architecture D3/D7/§6.2/§7；聆听界面 UI（绿光晕）未实现 | 用户重议方案；Memory 表与晨间批处理 schema 已就绪 |
| M6.2 睡眠分期 | HealthKit 授权已含 sleepAnalysis；读取代码未写 | 真机睡眠数据验证 |
| M7 社交（双星同孵/做客/相亲） | 零云化后 CloudKit 通道移除；双机传输方案待重议（WatchConnectivity 需配套 iPhone） | 传输方案决策 |
| 早安梦话 | 依赖 agent memory 晨间批处理（LLM），随对话方案一并 | 同 M3 |

## 7. 已知技术债与打磨清单

- [ ] 真机 30fps 验证（SpriteKit 图层合成表现）
- [ ] 溶解/瞬移转场（切换宠物/页面，采样器 teleport 三段动画上屏）
- [ ] holo 体色动态流转（当前静态近似帧）
- [ ] 方波音效真合成（AudioFeedback 为占位空实现；采样器 WebAudio 逻辑移植 AVAudioEngine）
- [ ] 基因详情 sheet（三层基因可视化 + 血统信息——育种核心 UI）
- [ ] 冷却中宠物列表视觉标识（⏳ 角标）
- [ ] 放生归档查看页（「曾陪伴」）
- [ ] 备份导出（存档 JSON，零云化后数据安全兜底）
- [ ] 表盘姿态集丰富（翻身/glitch 触发条件与心情联动）
- [ ] 蛋孵化时长等参数的正式/演示切换已做（-demoFast）；任务目标步数 UI 化设置（远期）
- [ ] archiveGen 血统回溯（Pet → Archive 跨表 Gen 查询，当前 parentGen 只查活体表）

## 8. 剩余里程碑

| 阶段 | 内容 | 前置 |
|---|---|---|
| M6.2 | 睡眠分期读取 + 作息联动（你睡它睡/熬夜记仇） | 真机 |
| M5+ | 基因详情 sheet + 放生归档查看 + 血统谱（iPhone 大屏二期） | — |
| M3 重议 | 对话方案（级联/E2E/纯本地深化）+ 聆听界面 + agent memory 接线 | 用户决策 |
| M7 | 社交 P0 双星同孵（双机传输方案） | 传输方案决策 |
| 打磨轮 | 特效/手感/性能（真机 30fps） | 真机反馈 |
