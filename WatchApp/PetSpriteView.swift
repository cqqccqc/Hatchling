import SwiftUI
import SpriteKit
import HatchlingKit

/// 真渲染宠物视图：SpriteKit 图层合成（呼吸/眨眼/双帧姿态）
struct PetSpriteView: View {
    @State private var scene: PetScene

    init(gene: GeneValue) {
        _scene = State(initialValue: PetScene(gene: gene))
    }

    var body: some View {
        SpriteView(scene: scene)
            .frame(width: 96, height: 96)
    }
}
