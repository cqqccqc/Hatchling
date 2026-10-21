import SwiftUI
import HatchlingKit

// MARK: - 融合仪式（rare-gene-lab 序列的 SwiftUI 版：汇聚 → 成蛋 → 抖动 → 登场）

struct FusionCeremonyData: Identifiable {
    var id = UUID()
    var parentA: GeneValue
    var parentB: GeneValue
    var childGene: GeneValue
    var childName: String
    var mutations: [String]
}

struct FusionCeremonyView: View {
    let data: FusionCeremonyData
    let onDone: () -> Void

    @State private var phase = 0   // 0 汇聚 · 1 成蛋 · 2 抖动 · 3 登场
    @State private var appeared = false

    private var hasLegendary: Bool { data.childGene.legendary != nil }
    private var hasRare: Bool { data.mutations.contains { $0.hasPrefix("rare:") || $0.hasPrefix("epic:") } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            stage
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            runPhases()
        }
    }

    @ViewBuilder private var stage: some View {
        switch phase {
        case 0:
            HStack(spacing: 40) {
                frame(data.parentA).opacity(0.75)
                frame(data.parentB).opacity(0.75)
            }
            .scaleEffect(0.9)
        case 1:
            Text("🥚").font(.system(size: 56))
                .transition(.scale)
        case 2:
            Text("🥚").font(.system(size: 56))
                .rotationEffect(.degrees(Double(Int.random(in: -12...12))))
                .animation(.linear(duration: 0.08).repeatForever(autoreverses: true), value: phase)
        default:
            VStack(spacing: 10) {
                if hasLegendary {
                    Text("⚠️").font(.system(size: 40))
                } else if hasRare {
                    Text("🌟").font(.system(size: 36))
                } else {
                    Text("🎉").font(.system(size: 36))
                }
                frame(data.childGene, eye: .happy)
                    .frame(width: 96, height: 96)
                HStack(spacing: 4) {
                    ForEach(data.mutations.prefix(3), id: \.self) { m in
                        Text(badge(for: m)).font(.system(size: 15))
                    }
                }
            }
        }
    }

    private func badge(for mutation: String) -> String {
        if mutation.hasPrefix("legendary") { return "⚠️" }
        if mutation.hasPrefix("rare") { return "🌟" }
        if mutation.hasPrefix("epic") { return "💜" }
        if mutation.hasPrefix("pity") { return "🍀" }
        if mutation.hasPrefix("recipe") { return "📜" }
        return "✨"
    }

    private func frame(_ gene: GeneValue, eye: EyeRenderState = .dot) -> some View {
        let img = AtlasComposer.composite(gene: gene, eye: eye)
        return Image(uiImage: UIImage(cgImage: img))
            .resizable()
            .interpolation(.none)
            .scaledToFit()
    }

    private func runPhases() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut) { phase = 1 }
            beep(440, 0.1)
            try? await Task.sleep(for: .seconds(0.8))
            phase = 2
            try? await Task.sleep(for: .seconds(0.9))
            phase = 3
            if hasLegendary {
                beep(1200, 0.06); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { beep(1200, 0.06) }
                hapticPulse()
            } else {
                chirp(); hapticPulse()
            }
            try? await Task.sleep(for: .seconds(1.8))
            onDone()
        }
    }
}

// MARK: - 放生确认（宠物先表达远行愿望 · 送行叙事）

struct ReleaseConfirmView: View {
    let pet: Pet
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var wishShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 14) {
                frame(pet.gene)
                    .frame(width: 84, height: 84)
                Text("🌍✈️").font(.system(size: 30))
                // ✓ 送行 / ✕ 留下（零文字：手势图标语义）
                HStack(spacing: 20) {
                    Button {
                        onConfirm()
                    } label: {
                        Text("🕊️").font(.system(size: 26))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        onCancel()
                    } label: {
                        Text("🏠").font(.system(size: 26))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wishShown = true
            }
        }
    }

    private func frame(_ gene: GeneValue?) -> some View {
        let img = AtlasComposer.composite(gene: gene ?? .random(), eye: .sleepy)
        return Image(uiImage: UIImage(cgImage: img))
            .resizable()
            .interpolation(.none)
            .scaledToFit()
    }
}
