import SwiftUI
import SwiftData
import HatchlingKit

/// M2 主页：当前宠物大卡（摸头/喂养/探险）+ 屋子小卡（切换）· 零文字
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Pet.createdAt) private var pets: [Pet]
    @State private var config = GameConfig.load()
    @State private var now = Date()
    @State private var currentID: UUID?
    @State private var feedOpen = false
    @State private var feedback: [String]?
    @State private var pendingTier: [UUID: TaskTier] = [:]   // arrived 待收取的档位

    /// M0 演示加速（正式版：config.hatchMinutes / taskMaxHours）
    private let demoHatchSeconds: TimeInterval = 30
    private let demoTaskInterval: TimeInterval = 90
    private var taskInterval: TimeInterval { demoTaskInterval }

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
                    if let pet = currentPet {
                        CurrentPetCard(pet: pet, now: now,
                                       taskInterval: taskInterval,
                                       pendingTier: pendingTier[pet.id],
                                       onHatch: { hatch(pet) },
                                       onCollect: { collect(pet) })
                            .onTapGesture { tapPet(pet) }
                    } else {
                        emptyState
                    }
                    actionRow
                    if feedOpen, currentPet != nil { feedPanel }
                    if !others.isEmpty { othersRow }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            feedbackOverlay
        }
        .task {
            now = Date()
            if pets.isEmpty, ProcessInfo.processInfo.arguments.contains("-demoAutospawn") {
                spawnEgg()
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

    // MARK: - 动作行（全图标）

    private var actionRow: some View {
        HStack(spacing: 14) {
            iconButton("🫘", active: feedOpen) { withAnimation { feedOpen.toggle() } }
            exploreButton
            iconButton("🧬", enabled: false) {}
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
                    currentID = p.id
                    withAnimation { }
                } label: {
                    VStack(spacing: 4) {
                        PetSpriteView(gene: p.gene ?? .random())
                            .frame(width: 46, height: 46)
                        Text(p.stateKind == .egg ? "🥚" : stateIcon(p.stateKind))
                            .font(.caption2)
                    }
                    .frame(width: 74, height: 84)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.1)))
                }
                .buttonStyle(.plain)
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
                          hatchAt: Date().addingTimeInterval(demoHatchSeconds))
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

    // MARK: - 结算（D1：抬腕/timer 驱动 Reconciler）

    private func reconcile(at now: Date) {
        guard !pets.isEmpty else { return }
        var steps = 0   // M2 无 HealthKit → 任务走倒计时兜底（M6 接入）
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
        if changed { try? ctx.save() }
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
                      hatchAt: Date().addingTimeInterval(demoHatchSeconds))
        ctx.insert(pet)
        ctx.insert(EventLog(type: .born, petID: pet.id, payload: #"{"source":"star"}"#))
        try? ctx.save()
    }

    private func beep(_ f: Double, _ d: Double) {}
    private func hapticPulse() {}
}

// MARK: - 当前宠物大卡

struct CurrentPetCard: View {
    let pet: Pet
    let now: Date
    let taskInterval: TimeInterval
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
        let progress = 1 - remain / max(0.001, demoHatchSeconds())
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

    private func demoHatchSeconds() -> TimeInterval { 30 }

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

extension Color {
    init(hex: UInt) {
        self.init(Color.RGBColorSpace.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

#Preview {
    RootView()
        .modelContainer(for: Pet.self, inMemory: true)
}
