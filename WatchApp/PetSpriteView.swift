import SwiftUI
import SpriteKit
import HatchlingKit

/// 真渲染宠物视图：SpriteKit 图层合成（呼吸/眨眼/双帧姿态）
struct PetSpriteView: View {
    let gene: GeneValue
    var moodPulse: Int = 0    // 递增触发 happy 反应
    var annoyPulse: Int = 0   // 递增触发 annoyed 反应
    @State private var scene: PetScene

    init(gene: GeneValue) {
        self.gene = gene
        _scene = State(initialValue: PetScene(gene: gene))
    }

    var body: some View {
        SpriteView(scene: scene)
            .frame(width: 96, height: 96)
            .onChange(of: moodPulse) { _, _ in scene.playHappy() }
            .onChange(of: annoyPulse) { _, _ in scene.playAnnoyed() }
    }
}
