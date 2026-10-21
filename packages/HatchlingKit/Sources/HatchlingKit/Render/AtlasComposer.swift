import Foundation
import CoreGraphics

/// 运行时合成完整宠物帧（背景+身体+眼+天线）——Widget timeline / 任意静态场景用
/// 与 Baker 烘焙、PetScene 动画同一份 CreatureRenderer 绘制代码（D2 同源原则）
public enum AtlasComposer {
    public static func composite(spec: CreatureSpec) -> CGImage {
        var g = PixelGrid()
        CreatureRenderer.drawBackground(&g)
        CreatureRenderer.drawBody(&g, spec: spec)
        CreatureRenderer.drawEyesLayer(&g, species: spec.species,
                                       eye: spec.eye, color: spec.color)
        CreatureRenderer.drawAntennaLayer(&g, spec.antenna, spec.color)
        return g.makeCGImage()!
    }

    /// 便捷：从 GeneValue 合成（express 层）
    public static func composite(gene: GeneValue, eye: EyeRenderState = .dot, phase: Int = 0) -> CGImage {
        composite(spec: .from(gene, eye: eye, phase: phase))
    }
}
