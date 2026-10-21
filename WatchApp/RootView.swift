import SwiftUI
import SwiftData
import HatchlingKit

/// M0 零文字界面：形状 / emoji / 数字表达一切（对齐 watch-design-spec §7.2）
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Pet.createdAt) private var pets: [Pet]
    @State private var config = GameConfig.load()
    @State private var now = Date()
    /// M0 演示加速：蛋 30 秒可破壳（正式为 config.hatchMinutes）
    private let demoHatchSeconds: TimeInterval = 30

    var body: some View {
        ZStack {
            // 深空背景（像素星空的低成本近似，M1 换烘焙星空）
            LinearGradient(colors: [.black, Color(hex: 0x0a0d14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    hud
                    ForEach(pets) { pet in
                        PetCard(pet: pet, now: now,
                                demoHatchSeconds: demoHatchSeconds,
                                onHatch: { hatch(pet) })
                            .contextMenu {
                                Button(role: .destructive) {
                                    release(pet)
                                } label: { Label("", systemImage: "arrow.up.circle") }
                            }
                    }
                    if pets.isEmpty { emptyState }
                    spawnButton
                        .padding(.top, 6)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .task {
            now = Date()
            // 自动化演示开关（测试/截图用）：
            // "-demoAutospawn" → 空屋坠一颗蛋；"-demoHome" → 直接一只活体宠物
            let args = ProcessInfo.processInfo.arguments
            if pets.isEmpty, args.contains("-demoAutospawn") {
                spawnEgg()
            }
            if pets.isEmpty, args.contains("-demoHome") {
                let pet = Pet(name: ["零波", "咕噜", "噗啾"].randomElement()!,
                              gene: .random(), state: .home)
                pet.birthAt = Date()
                ctx.insert(pet)
                try? ctx.save()
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) {
            now = $0      // 周期刷新驱动结算显示（抬腕结算的最小对应物）
        }
    }

    // MARK: - HUD：时间 + 屋子占用方块

    private var hud: some View {
        HStack {
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<config.maxPets, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < pets.count ? Color(hex: 0x2ce8f5)
                                             : Color.white.opacity(0.15))
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
        .padding(.bottom, 6)
    }

    // MARK: - 动作

    private func spawnEgg() {
        let names = ["零波", "咕噜", "噗啾", "豆崽", "咪团", "泡球"]
        let pet = Pet(
            name: names.randomElement()!,
            gene: .random(),
            state: .egg,
            source: "star",
            hatchAt: Date().addingTimeInterval(demoHatchSeconds)
        )
        ctx.insert(pet)
        ctx.insert(EventLog(type: .born, petID: pet.id,
                            payload: #"{"source":"star"}"#))
        try? ctx.save()
        now = Date()
    }

    /// 孵化结算：now ≥ hatchAt → state: egg → home（正式版在 Reconciler）
    private func hatch(_ pet: Pet) {
        guard pet.stateKind == .egg, let due = pet.hatchAt, now >= due else { return }
        pet.stateKind = .home
        pet.birthAt = now
        pet.hatchAt = nil
        ctx.insert(EventLog(type: .hatchDone, petID: pet.id))
        try? ctx.save()
    }

    /// M0 直接删除（正式版为放生仪式 + Archive 归档）
    private func release(_ pet: Pet) {
        ctx.delete(pet)
        try? ctx.save()
    }

}

// MARK: - 宠物卡（蛋 / 活体 两种形态）

struct PetCard: View {
    let pet: Pet
    let now: Date
    let demoHatchSeconds: TimeInterval
    let onHatch: () -> Void

    var body: some View {
        Group {
            if pet.stateKind == .egg { eggBody } else { petBody }
        }
        .cardStyle()
    }

    // 蛋：🥚 + 倒计时数字 + 像素进度条 + ✨破壳按钮
    @ViewBuilder private var eggBody: some View {
        let due = pet.hatchAt ?? now
        let remain = max(0, due.timeIntervalSince(now))
        let progress = 1 - remain / demoHatchSeconds
        HStack(spacing: 12) {
            Text("🥚").font(.system(size: 38))
            VStack(alignment: .leading, spacing: 5) {
                Text(remain > 0 ? String(format: "%ds", Int(ceil(remain))) : "✨")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x2ce8f5))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color(hex: 0x2ce8f5))
                            .frame(width: geo.size.width * max(0, min(1, progress)))
                    }
                }
                .frame(height: 7)
            }
            Spacer()
            if remain <= 0 {
                Button(action: onHatch) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color(hex: 0xfee761)))
                }
            }
        }
    }

    // 活体：像素渲染宠物 + 名字 + 心情条 + Gen 徽标 + 异色角标
    @ViewBuilder private var petBody: some View {
        HStack(spacing: 8) {
        PetSpriteView(gene: pet.gene ?? .random())
            .frame(width: 62, height: 62)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(pet.name).font(.headline)
                if pet.gene?.shiny == true { Text("✨").font(.caption2) }
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < moodLv ? moodColor : Color.white.opacity(0.14))
                        .frame(width: 13, height: 15)
                }
            }
        }
        Spacer()
        Text("G\(pet.gen)")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 表现层映射（emoji/颜色 = 形状化语言）

private extension PetCard {
    var moodLv: Int { pet.mood >= 66 ? 3 : pet.mood >= 33 ? 2 : 1 }
    var moodColor: Color {
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
