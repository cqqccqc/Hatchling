import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

// App 图标：星空 + 居中豆荚大使（48 网格 ×21 nearest = 1008，画布居中到 1024）
if CommandLine.arguments.count > 2 {
    let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
    var g = PixelGrid()
    CreatureRenderer.drawBackground(&g)
    // 加密星点（图标氛围）
    for (sx, sy) in [(3.0, 3.0), (12.0, 5.0), (44.0, 4.0), (7.0, 40.0), (41.0, 43.0),
                     (20.0, 44.0), (35.0, 20.0), (4.0, 22.0), (30.0, 2.0), (46.0, 30.0)] {
        g.px(sx, sy, Pixel(hex: 0xeafcff))
    }
    let spec = CreatureSpec(species: .pod, color: .cyan, antenna: .round,
                            pattern: .belly, eye: .dot, phase: 0)
    CreatureRenderer.drawBody(&g, spec: spec)
    CreatureRenderer.drawEyesLayer(&g, species: spec.species, eye: .dot, color: spec.color)
    CreatureRenderer.drawAntennaLayer(&g, spec.antenna, spec.color)
    if let icon = g.upscaledCGImage(factor: 21) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                            bytesPerRow: 1024 * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0x08/255.0, green: 0x09/255.0, blue: 0x0d/255.0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.interpolationQuality = .none
        ctx.draw(icon, in: CGRect(x: 8, y: 8, width: 1008, height: 1008))
        if let final = ctx.makeImage() {
            let out = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, final, nil)
                CGImageDestinationFinalize(dest)
                try? (out as Data).write(to: iconURL)
                print("✓ Icon → \(iconURL.path)")
            }
        }
    }
}
