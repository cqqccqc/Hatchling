import Foundation
import HatchlingKit

// Baker：构建期烘焙像素图集（同一份绘制代码 → PNG）
// 用法：swift run Baker [输出目录]   （默认 Sources/HatchlingKit/Resources/Atlas）

let outRoot = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/HatchlingKit/Resources/Atlas"

let dir = URL(fileURLWithPath: outRoot, isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

var count = 0
func bake(_ grid: PixelGrid, _ name: String) {
    do {
        try grid.writePNG(to: dir.appendingPathComponent(name + ".png"))
        count += 1
    } catch {
        print("✗ FAILED \(name): \(error)")
        exit(1)
    }
}

// 背景
var bg = PixelGrid()
CreatureRenderer.drawBackground(&bg)
bake(bg, "bg")

// 身体（含光垫/花纹/高光/观察窗）× 物种 × 色 × 花纹 × 双帧
for sp in SpeciesGene.allCases {
    for c in ColorGene.allCases {
        for p in PatternGene.allCases {
            for phase in 0..<2 {
                var g = PixelGrid()
                CreatureRenderer.drawBody(&g, spec: CreatureSpec(
                    species: sp, color: c, antenna: .round, pattern: p,
                    eye: .dot, phase: phase))
                bake(g, "body_\(sp.rawValue)_\(c.rawValue)_\(p.rawValue)_\(phase)")
            }
        }
    }
}

// 眼睛 × 状态 × 色（标准中心 24,21）
for st in EyeRenderState.allCases {
    for c in ColorGene.allCases {
        var g = PixelGrid()
        CreatureRenderer.drawEyesLayer(&g, species: .ghost, eye: st, color: c)
        bake(g, "eyes_\(st.rawValue)_\(c.rawValue)")
    }
}

// 天线 × 型 × 色
for a in AntennaGene.allCases {
    for c in ColorGene.allCases {
        var g = PixelGrid()
        CreatureRenderer.drawAntennaLayer(&g, a, c)
        bake(g, "ant_\(a.rawValue)_\(c.rawValue)")
    }
}

print("✓ Baked \(count) frames → \(dir.path)")
