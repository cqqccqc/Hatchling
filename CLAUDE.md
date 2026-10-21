# CLAUDE.md · Hatchling

## 项目是什么

**Hatchling**（曾用名"蛋生/DANSHENG"，已弃用，旧原型文件 UI 文案中残留）——一只住在 Apple Watch 表盘上的赛博电子生命：孵蛋繁育、稀有基因、语音对话。**个人亲子项目**（做给自己和 5-10 岁的儿子共用一块表玩），**不考虑商业化**。单一主人设定：不分用户，就当一个人玩。

## 文档索引

| 文件 | 内容 | 状态 |
|---|---|---|
| `docs/plan/PROJECT.md` | **产品主文档**：定位/玩法/平台方案/待定清单 | v2.2 定稿 |
| `docs/plan/watch-design-spec.md` | 交互视觉设计：2 页 + 3 演出 + 表盘；全图标 + emoji 反馈；聆听界面绿光晕 | v1.2 定稿 |
| `docs/plan/watch-prototype.html` | 可交互网页原型（单文件，浏览器直接打开；`?legend=1` 必出传说蛋） | v2 可玩 |
| `docs/plan/tech-architecture.md` | 技术架构：决策 D1-D6 / 管线 / 降级 / 里程碑 M0-M7 | v0.1 |
| `docs/plan/data-model.md` | 数据模型：SwiftData schema / 三层基因槽 / 结算引擎 | v1.1 |
| `docs/plan/breeding-algorithm.md` | 融合遗传算法：三层池/突变分层/隐藏配方/保底/概率校验 | v1.0 |
| `docs/plan/style-sampler.html` | 像素渲染采样器 v0.2（赛博版）——三物种/动画状态机渲染引擎的**原始蓝本**（原型与烘焙管线的移植源） | 已验证 |
| `docs/archive/style-sampler.html` | v0.1 软萌版采样器 | 留档 |
| `docs/plan/rare-gene-lab.html` | 稀有基因画廊 + 融合仪式动画序列（`?legend=1` 强制传说） | 已验证 |
| `docs/archive/esp32-hardware-plan.md` | 【已归档】ESP32 自研硬件方案（平台转向前旧方案） | 留档 |
| `docs/archive/hardware-render.html` | ESP32 硬件概念渲染页 | 留档 |

## 核心已定决策（勿重新讨论，改动须先过用户）

**产品**
- 孵化即完全体，**无成长阶段**（语言进化/进化分支/版本升级已砍）
- 二分：**天生 = 基因**（三层槽 express/carry/dormant + 性格四参数 + 口味，可遗传）/ **后天 = 记忆**（agent memory，越来越懂你）
- 主线：星空坠落开局 → 零等待破壳 → 语音取名 → 日常（喂豆三口味 / 挂机任务绑真实步数 / 语音对话）→ 融合繁育 → 屋子 3 只**并行挂机** → 放生 = 归档
- **电子宠物不死亡**；放生由宠物先表达远行愿望（🌍 送行叙事，孩子是"目送"不是"抛弃"）
- 繁育：CryptoKitties 式——Gen 代数、繁育疲劳递增（4/8/16/封顶 48h）、异色 1/96（羁绊 ≥90 ×3）、传说 0.08%、血统谱
- 社交原则：**宠物去社交，不是用户去社交**；双星同孵 P0 / 做客 P1 / 相亲 P2；客房不占 3 只上限
- 任务：每日早上自动出发，步数达标（默认 4000）提前收工，10h 倒计时兜底，奖励分档（兜底无蛋）

**技术**
- watchOS 11+ · SwiftUI + SpriteKit · v1 纯手表（数据层按跨端设计）
- **结算制模拟**（D1）：无后台常驻，状态 = f(事件日志， now)，激活时 reconcile
- **烘焙渲染**（D2/D6）：构建期用同一份 Swift 绘制代码烤 PNG 图集，运行时 SpriteKit 图层合成
- **零云化（v2.3 裁决：不申请开发者账号）**：SwiftData 纯本地（App Group 容器，Widget 只读）；无 CloudKit/iCloud/TestFlight/App Store；卸载即数据丢失，「备份导出」列远期
- 云端：**🚧 语音大模型对话整体暂缓（v0.3 裁决，方案待重新讨论）**——v1 对话形态 = 本地意图池 + emoji 反馈；原级联/豆包方案留档于 tech-architecture（D3/D7/§6.2/§7）；Memory 表与晨间记忆一并暂缓
- 零文字交互：图标按钮 + emoji 反馈（意图表驱动）；聆听界面绿光晕 = 录音中
- 对话约束：LLM 输出 ≤14 字 + 儿童内容护栏；失败降级本地意图池，永不卡死

## 当前待办（优先序）

1. ~~M0 工程骨架~~ ✅ 2026-10-21 完成（模拟器全流程通过；**真机安装**：Xcode 选用户自己的免费 Apple ID 签名 → 真机 Run；⚠️ 免费签名 7 天过期，到期连 Mac 重新 Run 即可）
2. ~~M2 游戏循环~~ ✅ 2026-10-21 完成（Reconciler 结算引擎：孵化自动/任务自动出发·步数倒计时兜底·奖励分档/饱食心情增量漂移；UI：摸头❤️/喂豆三 chips/矿洞探险卡/收取礼盒，模拟器全自动生命周期验证）
   ~~M1 烘焙渲染管线~~ ✅ 2026-10-21 核心完成（PixelGrid/CreatureRenderer 移植采样器；Baker 烘 379 帧图集；PetScene SpriteKit 合成：呼吸/眨眼/双帧；模拟器真渲染验证通过。余：真机 30fps、glitch/溶解/teleport 特效、holo 动态流转）→ M2 游戏循环（含 Genetics.fuse + Reconciler 单测）→ M4 表盘 → M5 育种 → M6 节律 → M7 社交（详见 tech-architecture §11）
3. ~~M4 表盘常驻~~ ✅ 2026-10-21 完成（Widget extension：accessoryCircular/Rectangular，timeline 24 条低频帧 + 心情点，App Group 只读，App 事件触发 reload）
4. M3 对话：🚧 暂缓，待与用户重新讨论方案；M5 育种 UI（融合入口）/M6 HealthKit 步数接入/表盘姿态细节

## 工程现状（代码）

```
Hatchling.xcodeproj   ← 由 xcodegen 从 project.yml 生成（改 project.yml 后须 `xcodegen generate`）
project.yml           ← 工程定义（watchOS app + widget extension + HatchlingKit 本地包）
packages/HatchlingKit/  SPM 包：Domain / Engine(Genetics/Reconciler) / Persistence / Render(PixelGrid/CreatureRenderer/PetScene/AtlasComposer) / Baker
WatchApp/             SwiftUI 入口 + RootView（当前宠物大卡/喂豆/矿洞/屋子小卡）
Widget/               表盘 Complication（accessoryCircular/Rectangular，timeline 24 条，读 App Group）
```

- 部署目标 watchOS 11；构建验证：`xcodebuild -project Hatchling.xcodeproj -scheme Hatchling -sdk watchsimulator build CODE_SIGNING_ALLOWED=NO`
- 单测：`swift test --package-path packages/HatchlingKit`（Swift Testing）
- 演示开关：模拟器 `xcrun simctl launch <udid> com.hatchling.watch -demoAutospawn`（空屋自动坠蛋）；蛋 30s 可破壳（demoHatchSeconds，正式版换 config.hatchMinutes）
- App Group：`group.com.hatchling.app`（entitlements 已配，免费 Apple ID 可用；无 iCloud）

## 工作约定

- 全程中文交流；文档与注释中文为主，代码标识符英文
- 改决策必须同步回写对应文档：版本号递增 + 文档头部追加修订记录（现有惯例见各文档头部）
- `docs/plan/*.html` 原型是独立单文件，改完用浏览器直接验证（可借助 Playwright/Chrome MCP 跑 `python3 -m http.server` 测试，file:// 下麦克风等能力受限）
- **xcodegen 用显式文件列表**：WatchApp/ 下**新增或删除源文件后必须 `xcodegen generate`**（改已有文件内容不需要）；改 project.yml 同理
- 演示开关（simctl launch 传参）：`-demoAutospawn` 空屋坠蛋 · `-demoHome` 直接活体 · `-demoFeed` 打开喂豆面板
- git：工作分支 `dev`，`main` 用于 PR；commit 信息中文、结尾按惯例附 Co-Authored-By
