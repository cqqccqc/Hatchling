import SwiftUI
import SwiftData
import WidgetKit
import HatchlingKit

/// M2 主页：当前宠物大卡（摸头/喂养/探险）+ 屋子小卡（切换）· 零文字
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Pet.createdAt) private var pets: [Pet]
    @State private var config = GameConfig.load()
    @State private var now = Date()
    @State private var stepsToday = 0
    @State private var demoStepsOverride: Int? = nil
    @State private var lastStepsFetch = Date.distantPast
    @State private var currentID: UUID?
    @State private var feedOpen = ProcessInfo.processInfo.arguments.contains("-demoFeed")
    @State private var feedback: [String]?
    @State private var pendingTier: [UUID: TaskTier] = [:]   // arrived 待收取的档位
    @State private var fuseMode = false
    @State private var fuseSelected: [UUID] = []
    @State private var ceremony: FusionCeremonyData?
    @State private var pendingFusion: PendingFusion?
    @State private var releaseCandidate: Pet?
    @State private var moodPulse = 0
    @State private var annoyPulse = 0
    // M5 演示加速（正式版：config.fuseGateHours / fatigueHours）

    /// 节奏双轨：正式（config）/ 演示加速（-demoFast）
    private var demoFast: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoFast")
    }
    /// 孵化时长：正式 30min（config）/ 演示 30s
    private var hatchInterval: TimeInterval {
        demoFast ? 30 : TimeInterval(config.hatchMinutes * 60)
    }
    /// 任务最晚时长：正式 10h（config）/ 演示 90s
    private var taskInterval: TimeInterval {
        demoFast ? 90 : TimeInterval(config.taskMaxHours * 3600)
    }
    /// 融合门槛：正式 24h（config）/ 演示 10s
    private var fuseGateInterval: TimeInterval {
        demoFast ? 10 : TimeInterval(config.fuseGateHours * 3600)
    }
    /// 繁育冷却：正式首档 4h（config）/ 演示 30s
    private var cooldownInterval: TimeInterval {
        demoFast ? 30 : TimeInterval((config.fatigueHours.first ?? 4) * 3600)
    }

    private var currentPet: Pet? {
        pets.first { $0.id == currentID } ?? pets.first
    }
    private var others: [Pet] {
        pets.filter { $0.id != currentPet?.id }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(hex: 0x0a0d14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    hud
                    if fuseMode {
                        HStack(spacing: 10) {
                            ForEach(0..<2, id: \.self) { i in
                                Circle()
                                    .fill(i < fuseSelected.count ? Color(hex: 0xfee761) : Color.white.opacity(0.15))
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    if let pet = currentPet {
                        CurrentPetCard(pet: pet, now: now,
                                       taskInterval: taskInterval,
                                       hatchInterval: hatchInterval,
                                       stepsToday: stepsToday,
                                       moodPulse: moodPulse,
                                       annoyPulse: annoyPulse,
                                       aod: scenePhase != .active,
                                       pendingTier: pendingTier[pet.id],
                                       onHatch: { hatch(pet) },
                                       onCollect: { collect(pet) })
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(fuseSelected.contains(pet.id) ? Color(hex: 0xfee761) : .clear, lineWidth: 2))
                            .onTapGesture { fuseMode ? tapFuseCandidate(pet) : tapPet(pet) }
                    } else {
                        emptyState
                    }
                    actionRow
                    if !others.isEmpty { othersRow }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            feedbackOverlay
            // 喂豆面板打开时：点击面板外任意处收起
            if feedOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { feedOpen = false } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if feedOpen {
                feedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.09))
            } else {
                spawnButton
            }
        }
        .fullScreenCover(item: $ceremony) { data in
            FusionCeremonyView(data: data) { finishFusion() }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $releaseCandidate) { pet in
            ReleaseConfirmView(pet: pet,
                               onConfirm: { confirmRelease(pet) },
                               onCancel: { releaseCandidate = nil })
                .ignoresSafeArea()
        }
        .task {
            now = Date()
            let args = ProcessInfo.processInfo.arguments
            // -demoSteps=N 注入优先（模拟器测标准档；真实拉取只在无注入时）
            if let arg = args.first(where: { $0.hasPrefix("-demoSteps=") }),
               let v = Int(arg.dropFirst("-demoSteps=".count)) {
                demoStepsOverride = v
                stepsToday = v
            } else if await HealthKitClient.shared.requestAuthorization() {
                stepsToday = await HealthKitClient.shared.stepsToday()
            }
            // 模拟器不弹通知授权（干扰自动化）；真机首次启动请求（毒舌闹钟）
            #if !targetEnvironment(simulator)
            if !args.contains("-noNotifications") {
                NotificationService.scheduleMorningAlarm(personality: currentPet?.gene?.personality)
            }
            #endif
            if pets.isEmpty, args.contains("-demoAutospawn") {
                spawnEgg()
            }
            // -demoHome：直接一只活体宠物（测试/截图用；今日已出发防自动派工）
            if pets.isEmpty, args.contains("-demoHome") {
                let pet = Pet(name: ["零波", "咕噜", "噗啾"].randomElement()!,
                              gene: .random(), state: .home)
                pet.birthAt = Date()
                pet.lastTaskDate = Date()
                ctx.insert(pet)
                try? ctx.save()
            }
            // -demoTwo：两只活体；-demoFuse：两只 + 3 秒后自动融合（仪式验证）
            if pets.isEmpty, args.contains("-demoTwo") || args.contains("-demoFuse") {
                for name in ["零波", "咕噜"] {
                    let p = Pet(name: name, gene: .random(), state: .home)
                    p.birthAt = Date().addingTimeInterval(-86400 * 2)   // 两天前出生 → 满足融合门槛
                    p.lastTaskDate = Date()                             // 今日已出发（防 Reconciler 打断 demo）
                    ctx.insert(p)
                }
                try? ctx.save()
            }
            if args.contains("-demoFuse") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    startFuseMode()
                    fuseSelected = pets.filter { $0.stateKind == .home }.prefix(2).map(\.id)
                    if fuseSelected.count == 2 { runFusion() }
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { t in
            now = t
            reconcile(at: t)
        }
    }

    // MARK: - HUD

    private var hud: some View {
        HStack {
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<config.maxPets, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < pets.count ? Color(hex: 0x2ce8f5) : Color.white.opacity(0.15))
                        .frame(width: 9, height: 11)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🌌").font(.system(size: 44))
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color(hex: 0x1c2432)).frame(width: 4, height: 4)
                }
            }
        }
        .padding(.top, 30)
    }

    private var spawnButton: some View {
        Button {
            spawnEgg()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 62, height: 48)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: 0x2ce8f5)))
        }
        .buttonStyle(.plain)
        .disabled(pets.count >= config.maxPets)
        .opacity(pets.count >= config.maxPets ? 0.3 : 1)
    }

    // MARK: - 动作行（全图标）

    private var actionRow: some View {
        HStack(spacing: 14) {
            iconButton("🫘", active: feedOpen,
                       enabled: currentPet?.stateKind == .home) { withAnimation { feedOpen.toggle() } }
            exploreButton
            iconButton("🧬", active: fuseMode) { startFuseMode() }
        }
    }

    private var exploreButton: some View {
        Button {
            startExplore()
        } label: {
            Text("⛏").font(.system(size: 22, weight: .bold))
                .frame(width: 62, height: 48)
        }
        .buttonStyle(.plain)
        .opacity(currentPet?.stateKind == .home ? 1 : 0.3)
    }

    private func iconButton(_ symbol: String, active: Bool = false, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 22))
                .frame(width: 62, height: 48)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(active ? Color(hex: 0x1a3a44) : Color(white: 0.1)))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? Color(hex: 0x2ce8f5) : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
    }

    // MARK: - 喂豆面板（三豆 chips）

    private var feedPanel: some View {
        HStack(spacing: 12) {
            // 关闭：点面板外即收（另有全屏遮罩）
            ForEach(TasteGene.allCases, id: \.rawValue) { t in
                Button {
                    feed(t)
                } label: {
                    Text(beanSymbol(t)).font(.system(size: 24))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color(white: 0.12)))
                        .overlay(Circle().stroke(
                            currentPet?.gene?.taste.express == t ? Color(hex: 0xfee761) : Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func beanSymbol(_ t: TasteGene) -> String {
        switch t {
        case .knowledge: return "🔸"
        case .play: return "🟡"
        case .sleep: return "🌙"
        }
    }

    // MARK: - 其他宠物小卡（切换）

    private var othersRow: some View {
        HStack(spacing: 10) {
            ForEach(others) { p in
                Button {
                    fuseMode ? tapFuseCandidate(p) : (currentID = p.id)
                } label: {
                    VStack(spacing: 4) {
                        PetSpriteView(gene: p.gene ?? .random())
                            .frame(width: 46, height: 46)
                        Text(p.stateKind == .egg ? "🥚" : stateIcon(p.stateKind))
                            .font(.caption2)
                    }
                    .frame(width: 74, height: 84)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(fuseSelected.contains(p.id) ? Color(hex: 0xfee761) : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { releaseCandidate = p } label: {
                        Image(systemName: "arrow.up.circle.dotted")
                    }
                }
            }
        }
    }

    private func stateIcon(_ s: PetState) -> String {
        switch s {
        case .egg: return "🥚"
        case .home: return "🏠"
        case .exploring: return "⛏"
        case .arrived: return "🎁"
        }
    }

    // MARK: - 反馈 overlay（emoji 浮现）

    private var feedbackOverlay: some View {
        Group {
            if let emojis = feedback {
                HStack(spacing: 8) {
                    ForEach(Array(emojis.enumerated()), id: \.offset) { _, e in
                        Text(e).font(.system(size: 42))
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: feedback)
    }

    private func showFeedback(_ emojis: [String], hold: Double = 1.6) {
        withAnimation { feedback = emojis }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            withAnimation { if feedback == emojis { feedback = nil } }
        }
    }

    // MARK: - 交互

    /// 摸头（home 态）
    private func tapPet(_ pet: Pet) {
        guard pet.stateKind == .home else { return }
        pet.mood = min(100, pet.mood + 5)
        moodPulse += 1
        ctx.insert(EventLog(type: .petted, petID: pet.id))
        try? ctx.save()
        showFeedback(["❤️"])
        beep(660, 0.06)
    }

    /// 喂豆：爱豆 😋💛 / 普通 😋 / 讨厌 🤢
    private func feed(_ t: TasteGene) {
        guard let pet = currentPet, pet.stateKind == .home else { return }
        let liked = pet.gene?.taste.express == t
        pet.hunger = max(0, pet.hunger - 30)
        pet.mood = min(100, pet.mood + (liked ? 12 : t == .sleep ? 4 : 7))
        ctx.insert(EventLog(type: .feed, petID: pet.id,
                            payload: #"{"bean":"\#(t.rawValue)"}"#))
        try? ctx.save()
        withAnimation { feedOpen = false }
        let dislike = !liked && Double.random(in: 0..<1) < 0.25
        if dislike { annoyPulse += 1 }
        showFeedback(dislike ? ["🤢"] : ["😋", liked ? "💛" : ""])
        beep(880, 0.07)
        hapticPulse()
    }

    /// 探险出发
    private func startExplore() {
        guard let pet = currentPet, pet.stateKind == .home else { return }
        pet.stateKind = .exploring
        pet.exploringSince = Date()
        pet.lastTaskDate = Date()
        ctx.insert(EventLog(type: .exploreStart, petID: pet.id))
        try? ctx.save()
        showFeedback([["⛏"], ["💪"]].randomElement()!)
        beep(520, 0.07)
    }

    /// 收取（arrived → 奖励 roll → 回 home）
    private func collect(_ pet: Pet) {
        guard pet.stateKind == .arrived else { return }
        let tier = pendingTier[pet.id] ?? .fallback
        pet.stateKind = .home
        pet.exploringSince = nil
        // 奖励：标准档蛋 roll（周 1-2 颗稀缺性由任务频次控制）
        if tier == .standard, Double.random(in: 0..<1) < 0.30,
           pets.count < config.maxPets {
            let egg = Pet(name: ["蛋蛋", "小星", "豆蛋"].randomElement()!,
                          gene: .random(), state: .egg, source: "task",
                          hatchAt: Date().addingTimeInterval(hatchInterval))
            ctx.insert(egg)
            showFeedback(["🥚", "🎉"], hold: 2.2)
        } else {
            showFeedback(["🫘", "✨"])
        }
        ctx.insert(EventLog(type: .exploreDone, petID: pet.id,
                            payload: #"{"tier":"\#(tier.rawValue)"}"#))
        pendingTier[pet.id] = nil
        try? ctx.save()
        beep(920, 0.09)
        hapticPulse()
    }

    // MARK: - M5 育种：融合模式

    private func startFuseMode() {
        guard pets.filter({ $0.stateKind == .home }).count >= 2 else {
            showFeedback(["❌"]); return
        }
        fuseMode = true
        fuseSelected = []
        showFeedback(["🧬"])
        beep(600, 0.05)
    }

    private func tapFuseCandidate(_ pet: Pet) {
        guard pet.stateKind == .home else { showFeedback(["⏳"]); return }
        guard Date().timeIntervalSince(pet.birthAt) >= fuseGateInterval else {
            showFeedback(["🐣"]); return
        }
        if let cd = pet.cooldownUntil, Date() < cd { showFeedback(["⏳"]); return }
        if let idx = fuseSelected.firstIndex(of: pet.id) {
            fuseSelected.remove(at: idx)
        } else if fuseSelected.count < 2 {
            fuseSelected.append(pet.id)
        }
        beep(600, 0.04)
        if fuseSelected.count == 2 { runFusion() }
    }

    private func runFusion() {
        let pair = fuseSelected.compactMap { id in pets.first { $0.id == id } }
        guard pair.count == 2,
              let pa = pair.first, let pb = pair.last,
              let ga = pa.gene, let gb = pb.gene else { fuseMode = false; return }
        fuseMode = false
        fuseSelected = []
        var rng = SystemRandomNumberGenerator()
        let out = Genetics.fuse(a: ga, b: gb, bondA: pa.bond, bondB: pb.bond,
                                aRareGenes: parseGlobalGenes(pa.rareGenes),
                                bRareGenes: parseGlobalGenes(pb.rareGenes),
                                sinceRare: BreedingPity.load(),
                                config: config, rng: &rng)
        let childName = ["波啾", "咖豆", "咪零", "泡崽", "啾咪"].randomElement()!
        ceremony = FusionCeremonyData(parentA: ga, parentB: gb,
                                      childGene: out.gene, childName: childName,
                                      mutations: out.mutations)
        pendingFusion = PendingFusion(output: out, parentIDs: [pa.id, pb.id],
                                      childName: childName)
    }

    /// 仪式完成后落库：蛋入屋 + 双亲疲劳冷却 + 保底计数
    private func finishFusion() {
        guard let pf = pendingFusion else { ceremony = nil; return }
        let egg = Pet(name: pf.childName, gene: pf.output.gene, state: .egg,
                      source: "fuse", hatchAt: Date().addingTimeInterval(hatchInterval))
        egg.gen = max(parentGen(pf.parentIDs[0]), parentGen(pf.parentIDs[1])) + 1
        egg.parentA = pf.parentIDs[0]
        egg.parentB = pf.parentIDs[1]
        egg.rareGenes = pf.output.rareGenes.map(\.rawValue).joined(separator: ",")
        ctx.insert(egg)
        ctx.insert(EventLog(type: .fuse, petID: egg.id,
                            payload: pf.output.mutations.joined(separator: ",")))
        for pid in pf.parentIDs {
            if let p = pets.first(where: { $0.id == pid }) {
                p.fuseCount += 1
                p.cooldownUntil = Date().addingTimeInterval(cooldownInterval)
            }
        }
        if Genetics.shouldResetPity(pf.output) { BreedingPity.reset() } else { BreedingPity.increment() }
        try? ctx.save()
        pendingFusion = nil
        ceremony = nil
        currentID = nil
        showFeedback(["🧬"])
    }

    private func parentGen(_ id: UUID) -> Int {
        pets.first { $0.id == id }?.gen ?? 0
    }
    private func parseGlobalGenes(_ s: String) -> [GlobalGene] {
        s.split(separator: ",").compactMap { GlobalGene(rawValue: String($0)) }
    }

    // MARK: - M5 放生归档（用户感受 = 送行；实现 = Archive 落库）

    private func confirmRelease(_ pet: Pet) {
        let digest = "Gen\(pet.gen) · \(pet.name)"
        let arch = Archive(name: pet.name, gene: pet.gene, gen: pet.gen,
                           parentA: pet.parentA, parentB: pet.parentB,
                           birthAt: pet.birthAt, eventDigest: digest)
        ctx.insert(arch)
        ctx.insert(EventLog(type: .release, petID: pet.id, payload: digest))
        if currentID == pet.id { currentID = nil }
        ctx.delete(pet)
        try? ctx.save()
        releaseCandidate = nil
        showFeedback(["🕊️"])
    }

    // MARK: - 结算（D1：抬腕/timer 驱动 Reconciler）

    private func reconcile(at now: Date) {
        guard !pets.isEmpty else { return }
        // 步数节流刷新（60s）：真机走路时任务可提前达标收工；demo 注入时不拉取
        if demoStepsOverride == nil, now.timeIntervalSince(lastStepsFetch) > 60 {
            lastStepsFetch = now
            Task {
                let s = await HealthKitClient.shared.stepsToday()
                await MainActor.run { stepsToday = s }
            }
        }
        let steps = stepsToday
        let snapshots = pets.map { p in
            PetSnapshot(id: p.id, state: p.stateKind, hatchAt: p.hatchAt,
                        hunger: p.hunger, mood: p.mood,
                        exploringSince: p.exploringSince,
                        lastTaskDate: p.lastTaskDate, lastTickAt: p.lastTickAt)
        }
        let cmds = Reconciler.run(now: now, stepsToday: steps,
                                  config: config, taskMaxInterval: taskInterval,
                                  pets: snapshots)
        var changed = false
        for cmd in cmds {
            switch cmd {
            case .hatchEgg(let id):
                if let p = pets.first(where: { $0.id == id }) {
                    p.stateKind = .home
                    p.birthAt = now
                    p.hatchAt = nil
                    ctx.insert(EventLog(type: .hatchDone, petID: id))
                    showFeedback(["✨"])
                }
            case .updateVitals(let id, let hunger, let mood, let tick):
                if let p = pets.first(where: { $0.id == id }) {
                    p.hunger = hunger
                    p.mood = mood
                    p.lastTickAt = tick
                }
            case .leaveForTask(let id, let at):
                if let p = pets.first(where: { $0.id == id }) {
                    p.stateKind = .exploring
                    p.exploringSince = at
                    p.lastTaskDate = at
                    ctx.insert(EventLog(type: .exploreStart, petID: id))
                    showFeedback(["⛏"])
                }
            case .finishExplore(let id, let tier):
                if let p = pets.first(where: { $0.id == id }) {
                    p.stateKind = .arrived
                    pendingTier[id] = tier
                    ctx.insert(EventLog(type: .exploreDone, petID: id,
                                        payload: #"{"tier":"\#(tier.rawValue)"}"#))
                    showFeedback(["🏠", "🎁"], hold: 2.2)
                }
            }
            changed = true
        }
        if changed {
            try? ctx.save()
            WidgetCenter.shared.reloadAllTimelines()   // 表盘同步宠物状态
        }
    }

    private func hatch(_ pet: Pet) {
        guard pet.stateKind == .egg, let due = pet.hatchAt, now >= due else { return }
        pet.stateKind = .home
        pet.birthAt = now
        pet.hatchAt = nil
        ctx.insert(EventLog(type: .hatchDone, petID: pet.id))
        try? ctx.save()
        showFeedback(["✨"])
    }

    private func spawnEgg() {
        let names = ["零波", "咕噜", "噗啾", "豆崽", "咪团", "泡球"]
        let pet = Pet(name: names.randomElement()!, gene: .random(),
                      state: .egg, source: "star",
                      hatchAt: Date().addingTimeInterval(hatchInterval))
        ctx.insert(pet)
        ctx.insert(EventLog(type: .born, petID: pet.id, payload: #"{"source":"star"}"#))
        try? ctx.save()
    }

}

// MARK: - 当前宠物大卡

/// 仪式期间挂起的融合结果（演出完成后落库）
struct PendingFusion {
    let output: FusionOutput
    let parentIDs: [UUID]
    let childName: String
}

struct CurrentPetCard: View {
    let pet: Pet
    let now: Date
    let taskInterval: TimeInterval
    let hatchInterval: TimeInterval
    var stepsToday: Int = 0
    var moodPulse: Int = 0
    var annoyPulse: Int = 0
    var aod: Bool = false
    let pendingTier: TaskTier?
    let onHatch: () -> Void
    let onCollect: () -> Void

    var body: some View {
        Group {
            switch pet.stateKind {
            case .egg: eggBody
            case .exploring: exploreBody
            case .arrived: collectBody
            default: petBody
            }
        }
        .cardStyle()
    }

    // 蛋
    @ViewBuilder private var eggBody: some View {
        let due = pet.hatchAt ?? now
        let remain = max(0, due.timeIntervalSince(now))
        let progress = 1 - remain / max(0.001, hatchInterval)
        HStack(spacing: 12) {
            Text("🥚").font(.system(size: 38))
            VStack(alignment: .leading, spacing: 5) {
                Text(remain > 0 ? String(format: "%ds", Int(ceil(remain))) : "✨")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x2ce8f5))
                Capsule()
                    .fill(Color(hex: 0x2ce8f5))
                    .frame(width: max(4, 120 * progress), height: 7)
                    .frame(maxWidth: 130, alignment: .leading)
            }
            Spacer()
        }
    }

    // 活体（home）：渲染 + 名字 + 心情条 + 饱食条
    @ViewBuilder private var petBody: some View {
        HStack(spacing: 8) {
            PetSpriteView(gene: pet.gene ?? .random())
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(pet.name).font(.headline)
                    if pet.gene?.shiny == true { Text("✨").font(.caption2) }
                }
                moodBar
                hungerBar
            }
            Spacer()
            Text("G\(pet.gen)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // 探险：矿洞进度
    @ViewBuilder private var exploreBody: some View {
        let since = pet.exploringSince ?? now
        let progress = min(1, now.timeIntervalSince(since) / max(0.001, taskInterval))
        HStack(spacing: 12) {
            Text("⛏").font(.system(size: 34))
            VStack(alignment: .leading, spacing: 6) {
                Text(pet.name).font(.headline)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color(hex: 0xfeae34))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 4) {
                    Text("👣").font(.caption2)
                    Text("\(stepsToday)").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x2ce8f5))
                }
            }
            Spacer()
        }
    }

    // 到家待收取
    @ViewBuilder private var collectBody: some View {
        HStack {
            Text("🎁").font(.system(size: 40))
            Spacer()
            Button(action: onCollect) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color(hex: 0xfee761)))
            }
            .buttonStyle(.plain)
        }
    }

    // 条形图组件
    private var moodBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < moodLv ? moodColor : Color.white.opacity(0.14))
                    .frame(width: 14, height: 9)
            }
        }
    }

    private var hungerBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color(hex: 0x63c74d))
                    .frame(width: geo.size.width * max(0.02, 1 - pet.hunger / 100))
            }
        }
        .frame(width: 56, height: 5)
    }

    private var moodLv: Int { pet.mood >= 66 ? 3 : pet.mood >= 33 ? 2 : 1 }
    private var moodColor: Color {
        [Color(hex: 0xe43b44), Color(hex: 0xfeae34), Color(hex: 0x63c74d)][moodLv - 1]
    }
}

// MARK: - 样式辅助

extension View {
    func cardStyle() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.07, green: 0.07, blue: 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

#Preview {
    RootView()
        .modelContainer(for: Pet.self, inMemory: true)
}
