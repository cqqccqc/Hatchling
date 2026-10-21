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
                       isEgg: p.stateKind == .egg)
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

    /// 矩形：宠物帧 + 名字 + 心情条
    private var rectangular: some View {
        Group {
            switch entry.pet {
            case .some(let pet):
                HStack(spacing: 6) {
                    if pet.isEgg {
                        Text("🥚").font(.system(size: 24))
                    } else {
                        frameImage(pet: pet, eyesClosed: entry.eyesClosed)
                            .frame(width: 34, height: 34)
                        nameColumn(pet)
                    }
                    Spacer(minLength: 0)
                }
            case .none:
                Text("🌌").font(.system(size: 22))
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color.black }
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
