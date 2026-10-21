import Foundation

/// 渲染用基因规格（express 层快照）
public struct CreatureSpec: Hashable, Sendable {
    public var species: SpeciesGene
    public var color: ColorGene
    public var antenna: AntennaGene
    public var pattern: PatternGene
    public var eye: EyeRenderState
    public var phase: Int      // 动画帧 0/1

    public init(species: SpeciesGene, color: ColorGene, antenna: AntennaGene,
                pattern: PatternGene, eye: EyeRenderState = .dot, phase: Int = 0) {
        self.species = species
        self.color = color
        self.antenna = antenna
        self.pattern = pattern
        self.eye = eye
        self.phase = phase
    }

    public static func from(_ gene: GeneValue, eye: EyeRenderState = .dot, phase: Int = 0) -> CreatureSpec {
        CreatureSpec(species: gene.species.express, color: gene.color.express,
                     antenna: gene.antenna.express, pattern: gene.pattern.express,
                     eye: eye, phase: phase)
    }
}

public enum EyeRenderState: String, Codable, CaseIterable, Sendable {
    case dot, big, sleepy, closed, blink, happy, annoyed, wide
}

/// 采样器 JS draw* 函数家族的 Swift 移植（48×48 网格坐标系）
public enum CreatureRenderer {

    // MARK: 背景（扫描线 + 星尘）

    public static func drawBackground(_ g: inout PixelGrid) {
        for y in 0..<48 {
            g.rect(0, Double(y), 48, 1, Pixel(hex: y % 2 == 0 ? 0x0d1119 : 0x0a0d14))
        }
        for (sx, sy) in [(5.0, 7.0), (38, 4), (12, 15), (42, 20), (7, 28), (35, 33), (17, 3), (27, 8)] {
            g.px(sx, sy, Pixel(hex: 0x1c2432))
        }
    }

    // MARK: 眼睛（单只；分层烘焙时 x 取 ±4，整帧时按物种间距）

    public static func drawEye(_ g: inout PixelGrid, _ x: Int, _ y: Int,
                               _ state: EyeRenderState, _ glow: Pixel) {
        let red = Pixel(hex: 0xe43b44)
        switch state {
        case .closed, .blink:
            g.rect(Double(x - 2), Double(y), 4, 1, Pixel.outline)
        case .happy:
            g.px(Double(x - 2), Double(y + 1), glow)
            g.px(Double(x - 1), Double(y), glow)
            g.px(Double(x), Double(y), glow)
            g.px(Double(x + 1), Double(y + 1), glow)
        case .annoyed:
            for i in -1...1 {
                g.px(Double(x + i), Double(y + i), red)
                g.px(Double(x + i), Double(y - i), red)
            }
        case .dot:
            g.ell(Double(x), Double(y), 2.1, 2.1, .outline)
            g.ell(Double(x), Double(y), 1.3, 1.3, Pixel(hex: 0xeafcff))
            g.px(Double(x - 1), Double(y - 1), Pixel(hex: 0xffffff))
        case .wide:  // 聆听态：放大瞳孔
            g.ell(Double(x), Double(y), 2.6, 2.6, .outline)
            g.ell(Double(x), Double(y), 1.8, 1.8, Pixel(hex: 0xeafcff))
            g.px(Double(x), Double(y), Pixel(hex: 0xffffff))
            g.px(Double(x - 1), Double(y), Pixel(hex: 0xffffff))
        case .big:
            for (dx, dy) in [(0, -2.0), (0, 2.0), (-2.0, 0), (2.0, 0),
                             (-1, -1.0), (1, -1.0), (-1, 1.0), (1, 1.0)] {
                g.px(Double(x) + Double(dx), Double(y) + dy, glow)
            }
            g.px(Double(x), Double(y), Pixel(hex: 0xffffff))
        case .sleepy:
            g.rect(Double(x - 2), Double(y), 4, 1, Pixel.outline)
            g.px(Double(x - 2), Double(y + 1), glow)
        }
    }

    /// 分层眼睛：两只，标准中心 (24, 21)，间距按物种
    public static func drawEyesLayer(_ g: inout PixelGrid, species: SpeciesGene,
                                     eye: EyeRenderState, color: ColorGene) {
        let dx: Double = species == .ghost ? 5 : species == .pod ? 4 : 3.4
        let glow = Palette.forColor(color).base
        drawEye(&g, 24 - Int(dx), 21, eye, glow)
        drawEye(&g, 24 + Int(dx), 21, eye, glow)
    }

    // MARK: 天线（分层：底端统一 y=12.5，中心 x=24）

    public static func drawAntennaLayer(_ g: inout PixelGrid, _ type: AntennaGene,
                                        _ color: ColorGene, erect: Bool = false) {
        let x = 24.0, y = 12.5
        let glow = Palette.forColor(color).base
        if erect {  // 聆听态：天线竖直伸长 + 顶端信号
            g.rect(x, y - 6, 1, 6, .dark)
            g.ell(x, y - 8, 2, 2, glow)
            g.px(x, y - 11, Pixel(hex: 0xeafcff))
            return
        }
        switch type {
        case .round:
            g.rect(x, y - 4, 1, 4, .dark)
            g.ell(x, y - 5.5, 2, 2, glow)
            g.px(x - 1, y - 6.5, Pixel(hex: 0xffffff))
        case .forked:
            g.rect(x - 3, y - 4, 1, 4, .dark)
            g.rect(x + 3, y - 4, 1, 4, .dark)
            g.px(x - 3, y - 5, glow)
            g.px(x + 3, y - 5, glow)
        case .droopy:
            g.ring(x, y - 6, 5, 1.6, glow)
            g.px(x + 5, y - 6, Pixel(hex: 0xffffff))
        case .pointy:
            for i in 0..<4 {
                g.rect(x - Double(i), y - 1 - Double(i), Double(i * 2 + 1), 1, i < 2 ? glow : .dark)
            }
        }
    }

    // MARK: 花纹（裁剪在身体内）

    public static func drawPattern(_ g: inout PixelGrid, _ spec: CreatureSpec,
                                   cx: Double, cy: Double, rx: Double, ry: Double,
                                   pal: Palette) {
        switch spec.pattern {
        case .belly:
            let y0 = cy + ry * 0.45
            var x = (cx - rx * 0.7).rounded(.down)
            while x <= (cx - rx * 0.15).rounded() {
                if g.inEll(cx, cy, rx, ry, x, y0) { g.px(x, y0, pal.light) }
                x += 1
            }
            g.rect((cx - rx * 0.78).rounded(.down), y0 - 1, 2, 2, pal.light)
            x = (cx + rx * 0.2).rounded(.down)
            while x <= (cx + rx * 0.65).rounded() {
                if g.inEll(cx, cy, rx, ry, x, y0 - 2) { g.px(x, y0 - 2, pal.light) }
                x += 1
            }
            g.rect((cx + rx * 0.6).rounded(.down), y0 - 3, 2, 2, pal.light)
        case .stripes:
            let shift = Int(Date().timeIntervalSince1970 * 1000 / 180) % 5  // 烘焙静态取一相位
            for col in [cx - rx * 0.45, cx + rx * 0.3] {
                var y = (cy - ry * 0.6).rounded(.down)
                while y <= (cy + ry * 0.6).rounded(.up) {
                    if (Int(y) + shift) % 5 < 2, g.inEll(cx, cy, rx, ry, col, y) {
                        g.px(col, y, pal.light)
                    }
                    y += 1
                }
            }
        case .spots:
            for (sx, sy) in [(-0.4, -0.3), (0.35, 0.15), (-0.05, 0.5)] {
                let px = cx + sx * rx, py = cy + sy * ry
                if g.inEll(cx, cy, rx, ry, px, py) { g.rect(px - 1, py, 2, 2, pal.light) }
            }
        case .stardust:  // 稀有 · 星尘纹：体内漂浮微粒（烘焙静态一帧）
            for (sx, sy, i) in [(-4.0, -5.0, 0), (3.0, -7.0, 1), (5.0, 0.0, 2), (-2.0, 2.0, 3), (1.0, 6.0, 4)] {
                if g.inEll(cx, cy, rx, ry, cx + sx, cy + sy) {
                    g.px(cx + sx, cy + sy, i % 2 == 0 ? pal.light : Pixel(hex: 0xfee761))
                }
            }
        case .plain:
            break
        }
    }

    // MARK: 三物种身体（光垫 + 身体 + 花纹 + 高光；眼/天线分层另绘）

    /// 整帧绘制（背景 + 身体 + 眼 + 天线）—— 预览/截图用
    public static func drawFullFrame(_ g: inout PixelGrid, spec: CreatureSpec) {
        drawBackground(&g)
        drawBody(&g, spec: spec)
        drawEyesLayer(&g, species: spec.species, eye: spec.eye, color: spec.color)
        drawAntennaLayer(&g, spec.antenna, spec.color)
    }

    public static func drawBody(_ g: inout PixelGrid, spec: CreatureSpec) {
        let pal = Palette.forColor(spec.color)
        let x = 24.0
        let cy = 23.0

        switch spec.species {
        case .ghost:
            let rx = 12.0, ry = 11.0
            g.ell(x, 43, 9, 2, pal.base.with(alpha: 0x2e))   // 悬浮光垫
            // 裙摆两相位
            let bumps: [(Double, Double, Double)] =
                spec.phase == 0 ? [(-9, 0, 9)] : [(-12, -4, 4), (12, -4, 4)]
            let bumpR = spec.phase == 0 ? 4.8 : 3.4
            // 描边 pass（并集轮廓）
            ell(&g, x, cy - 3, rx + 1.2, ry + 1.2, .outline)
            rectCentered(&g, x, cy + 3, rx, 7, .outline)
            for (bx, by, br) in bumps {
                ell(&g, x + bx, cy + 7 + by, bumpR + 1.2, 3.2 + 1.2, .outline)
            }
            // 本体 pass
            ell(&g, x, cy - 3, rx, ry, pal.base)
            rectCentered(&g, x, cy + 3, rx, 7, pal.base)
            for (bx, by, br) in bumps {
                ell(&g, x + bx, cy + 7 + by, bumpR, 3.2, pal.base)
            }
            g.ell(x - 5, cy - 8, 3, 2, pal.light)            // 高光
            drawPattern(&g, spec, cx: x, cy: cy, rx: rx, ry: ry, pal: pal)
            // LED 腮
            g.rect(x - 8, cy + 2, 2, 1, pal.base.with(alpha: 0x88))
            g.rect(x + 6, cy + 2, 2, 1, pal.base.with(alpha: 0x88))

        case .pod:
            let rx = 11.5, ry = 14.0
            g.ell(x, 43, 8, 2, pal.base.with(alpha: 0x2e))
            if spec.phase == 1 {                              // 尾焰（相位帧出现）
                g.px(x - 2, 39, Pixel(hex: 0xfeae34))
                g.px(x + 1, 40, Pixel(hex: 0xfee761))
            }
            g.ring(x, 41, 9, 1.4, pal.base.with(alpha: 0x66))
            g.ell(x, cy, rx + 1.4, ry + 1.4, pal.shade)       // 柔和包边
            g.ell(x, cy, rx, ry, pal.base)
            g.ell(x - 4, cy - 9, 2.5, 1.6, pal.light)         // 高光
            g.ell(x, cy - 3, 9, 6, .outline)                  // 观察窗
            g.ell(x, cy - 3, 8, 5, Pixel(hex: 0x0a0e18))
            drawPattern(&g, spec, cx: x, cy: cy + 3, rx: rx - 2, ry: ry - 7, pal: pal)

        case .crystal:
            // 旋转错觉：两相位互补脉动
            let spin: Double = spec.phase == 0 ? 0 : 1.0
            let a = 8 + 5 * spin, b = 14 - 4 * spin
            g.ell(x, 43, 7, 2, pal.base.with(alpha: 0x2e))
            g.ring(x, cy + b + 3, 6, 1.2, pal.base.with(alpha: 0x55))
            g.diamond(x, cy, a + 1.2, b + 1.2, pal.shade)
            g.diamond(x, cy, a, b, pal.base)
            g.diamond(x - a * 0.28, cy - b * 0.3, a * 0.5, b * 0.42, pal.light)
            g.rect(x - 1, cy - 1, 2, 2, Pixel(hex: 0xffffff)) // 内核
            drawPattern(&g, spec, cx: x, cy: cy + b * 0.35, rx: a * 0.75, ry: b * 0.4, pal: pal)
        }
    }

    /// 中心形式矩形（JS parts 的 rect 语义）
    static func rectCentered(_ g: inout PixelGrid, _ cx: Double, _ cy: Double,
                             _ halfW: Double, _ halfH: Double, _ c: Pixel) {
        g.rect(cx - halfW, cy - halfH, halfW * 2, halfH * 2, c)
    }

    static func ell(_ g: inout PixelGrid, _ cx: Double, _ cy: Double,
                    _ rx: Double, _ ry: Double, _ c: Pixel) {
        g.ell(cx, cy, rx, ry, c)
    }
}

extension Pixel {
    func with(alpha: UInt8) -> Pixel {
        var p = self
        p.a = alpha
        return p
    }
}
