import WidgetKit
import SwiftUI
import SwiftData
import HatchlingKit

// MARK: - Widget 入口

@main
struct HatchlingWidgetBundle: WidgetBundle {
    var body: some Widget {
        PetComplication()
    }
}

// MARK: - 展示模型（从共享 store 读取后的值快照）

struct PetDisplay: Sendable {
    var name: String
    var species: SpeciesGene
    var color: ColorGene
    var pattern: PatternGene
    var antenna: AntennaGene
    var mood: Double
    var isEgg: Bool
    var geneShiny: Bool = false
}

// MARK: - 数据读取（App Group 共享 store · 只读）

enum StoreReader {
    static func loadPets() -> [PetDisplay] {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier) else { return [] }
        let schema = Schema([Pet.self, EventLog.self, Memory.self, Archive.self])
        let cfg = ModelConfiguration(schema: schema,
                                     url: groupURL.appending(path: "Hatchling.store"),
                                     cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [cfg]) else { return [] }
        let ctx = ModelContext(container)
        let pets = (try? ctx.fetch(FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return pets.map { p in
            PetDisplay(name: p.name,
                       species: p.gene?.species.express ?? .ghost,
                       color: p.gene?.color.express ?? .cyan,
                       pattern: p.gene?.pattern.express ?? .plain,
                       antenna: p.gene?.antenna.express ?? .round,
                       mood: p.mood,
                       isEgg: p.stateKind == .egg,
                       geneShiny: p.gene?.shiny ?? false)
        }
    }
}

// MARK: - Timeline

struct PetEntry: TimelineEntry {
    let date: Date
    let pet: PetDisplay?
    let phase: Int        // 身体双帧
    let eyesClosed: Bool  // 低频眨眼
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: Date(), pet: samplePet, phase: 0, eyesClosed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(getEntry(date: Date(), index: 0))
    }

    /// 24 条 × 25 分钟 ≈ 全天覆盖（预算内：每 entry 一帧静态）
    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        var entries: [PetEntry] = []
        var date = Date()
        for i in 0..<24 {
            entries.append(getEntry(date: date, index: i))
            date = Calendar.current.date(byAdding: .minute, value: 25, to: date) ?? date
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func getEntry(date: Date, index: Int) -> PetEntry {
        let pets = StoreReader.loadPets()
        let pet = pets.first
        // 低频生命感：双帧交替 + 偶尔闭眼
        let phase = index % 2
        let eyesClosed = index % 7 == 3
        return PetEntry(date: date, pet: pet, phase: phase, eyesClosed: eyesClosed)
    }

    private var samplePet: PetDisplay {
        PetDisplay(name: "零波", species: .ghost, color: .cyan,
                   pattern: .plain, antenna: .round, mood: 80, isEgg: false)
    }
}

// MARK: - Complication

struct PetComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HatchlingPet", provider: Provider()) { entry in
            PetComplicationView(entry: entry)
        }
        .configurationDisplayName("Hatchling")
        .description(Text(""))  // 零文字：无描述文案
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 视图

struct PetComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        default: rectangular
        }
    }

    /// 圆形：宠物合成帧 + 心情色点
    private var circular: some View {
        ZStack {
            switch entry.pet {
            case .some(let pet) where !pet.isEgg:
                frameImage(pet: pet, eyesClosed: entry.eyesClosed)
                    .overlay(alignment: .bottomTrailing) { moodDot(pet.mood).padding(5) }
            case .some(let pet):
                Text("🥚").font(.system(size: 26))
                    .overlay(alignment: .bottom) { moodDot(pet.mood).padding(2) }
            case .none:
                Text("🌌").font(.system(size: 26))
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    /// 矩形（智能叠放 = 伪表盘）：星空铺满 + 宠物居中大图 + 底部状态行
    private var rectangular: some View {
        ZStack {
            starfield
            switch entry.pet {
            case .some(let pet) where !pet.isEgg:
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    frameImage(pet: pet, eyesClosed: entry.eyesClosed)
                        .frame(width: 84, height: 84)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        moodBar(pet.mood)
                        Text(pet.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if pet.geneShiny { Text("✨").font(.caption2) }
                    }
                    .padding(.bottom, 4)
                }
            case .some:
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text("🥚").font(.system(size: 40))
                    Spacer(minLength: 0)
                    Text("· · ·").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            case .none:
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("🌌").font(.system(size: 34))
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color.white.opacity(0.15)).frame(width: 4, height: 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    /// 伪表盘星空（静态点阵，烘焙星空的低配近似）
    private var starfield: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let stars: [(Double, Double)] = [(0.1, 0.12), (0.3, 0.06), (0.55, 0.1), (0.8, 0.08),
                                             (0.15, 0.3), (0.9, 0.28), (0.45, 0.22), (0.7, 0.4),
                                             (0.2, 0.55), (0.85, 0.6), (0.05, 0.45), (0.6, 0.62),
                                             (0.35, 0.5), (0.95, 0.5), (0.5, 0.35)]
            for (fx, fy) in stars {
                let r = Double.random(in: 0.8...1.6)
                ctx.fill(Path(CGRect(x: size.width * fx, y: size.height * fy,
                                     width: r, height: r)),
                         with: .color(.white.opacity(0.35)))
            }
        }
        .ignoresSafeArea()
    }

    private func moodBar(_ mood: Double) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < moodLv(mood) ? Color(hex: 0x63c74d) : Color.white.opacity(0.18))
                    .frame(width: 9, height: 11)
            }
        }
    }

    private func nameColumn(_ pet: PetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pet.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < moodLv(pet.mood) ? Color(hex: 0x63c74d) : Color.white.opacity(0.2))
                        .frame(width: 6, height: 7)
                }
            }
        }
    }

    private func frameImage(pet: PetDisplay, eyesClosed: Bool) -> some View {
        let spec = CreatureSpec(species: pet.species, color: pet.color,
                                antenna: pet.antenna, pattern: pet.pattern,
                                eye: eyesClosed ? .closed : .dot, phase: entry.phase)
        return Image(uiImage: UIImage(cgImage: AtlasComposer.composite(spec: spec)))
            .resizable()
            .interpolation(.none)
            .scaledToFit()
    }

    private func moodDot(_ mood: Double) -> some View {
        Circle()
            .fill(moodColor(mood))
            .frame(width: 7, height: 7)
    }

    private func moodLv(_ m: Double) -> Int { m >= 66 ? 3 : m >= 33 ? 2 : 1 }
    private func moodColor(_ m: Double) -> Color {
        [Color(hex: 0xe43b44), Color(hex: 0xfeae34), Color(hex: 0x63c74d)][moodLv(m) - 1]
    }
}
