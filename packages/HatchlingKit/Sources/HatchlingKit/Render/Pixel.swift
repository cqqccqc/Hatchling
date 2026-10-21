import Foundation

/// 不透明像素颜色（RGBA 8bit/通道）
public struct Pixel: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(hex: UInt32, alpha: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xff)
        g = UInt8((hex >> 8) & 0xff)
        b = UInt8(hex & 0xff)
        a = alpha
    }

    public static let outline = Pixel(hex: 0x181425)
    public static let dark = Pixel(hex: 0x262b44)
}

/// 色板（移植采样器 COLS：base / shade / light 三色）
public struct Palette: Hashable, Sendable {
    public let base: Pixel
    public let shade: Pixel
    public let light: Pixel

    public init(base: Pixel, shade: Pixel, light: Pixel) {
        self.base = base
        self.shade = shade
        self.light = light
    }

    /// ColorGene → 色板（holo 用彩虹中段近似，动态流转 M1.5 做）
    public static func forColor(_ c: ColorGene) -> Palette {
        switch c {
        case .cyan:   return .init(base: Pixel(hex: 0x2ce8f5), shade: Pixel(hex: 0x0099db), light: Pixel(hex: 0xffffff))
        case .purple: return .init(base: Pixel(hex: 0xb55088), shade: Pixel(hex: 0x68386c), light: Pixel(hex: 0xf6757a))
        case .green:  return .init(base: Pixel(hex: 0x63c74d), shade: Pixel(hex: 0x265c42), light: Pixel(hex: 0xfee761))
        case .orange: return .init(base: Pixel(hex: 0xf77622), shade: Pixel(hex: 0xb86f50), light: Pixel(hex: 0xfeae34))
        case .red:    return .init(base: Pixel(hex: 0xe43b44), shade: Pixel(hex: 0xa22633), light: Pixel(hex: 0xf6757a))
        case .blue:   return .init(base: Pixel(hex: 0x124e89), shade: Pixel(hex: 0x193c3e), light: Pixel(hex: 0x2ce8f5))
        case .yellow: return .init(base: Pixel(hex: 0xfee761), shade: Pixel(hex: 0xfeae34), light: Pixel(hex: 0xffffff))
        case .white:  return .init(base: Pixel(hex: 0xc0cbdc), shade: Pixel(hex: 0x8b9bb4), light: Pixel(hex: 0xffffff))
        case .holo:   return .init(base: Pixel(hex: 0x9b5de5), shade: Pixel(hex: 0x5c3a8e), light: Pixel(hex: 0xffd6ff))
        }
    }
}

/// 48×48 像素画布 —— 采样器 JS Grid 类的 Swift 移植
public struct PixelGrid: Sendable {
    public let size: Int
    public var pixels: [Pixel?]

    public init(size: Int = 48) {
        self.size = size
        self.pixels = .init(repeating: nil, count: size * size)
    }

    public mutating func clear() {
        pixels = .init(repeating: nil, count: size * size)
    }

    public subscript(x: Int, y: Int) -> Pixel? {
        get {
            guard x >= 0, y >= 0, x < size, y < size else { return nil }
            return pixels[y * size + x]
        }
        set {
            guard x >= 0, y >= 0, x < size, y < size else { return }
            pixels[y * size + x] = newValue
        }
    }

    public mutating func px(_ x: Double, _ y: Double, _ c: Pixel) {
        self[Int(x.rounded()), Int(y.rounded())] = c
    }

    public mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Pixel) {
        for j in 0..<Int(h) {
            for i in 0..<Int(w) {
                self[Int(x) + i, Int(y) + j] = c
            }
        }
    }

    public mutating func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Pixel) {
        guard rx > 0, ry > 0 else { return }
        let y0 = Int((cy - ry).rounded(.down)), y1 = Int((cy + ry).rounded(.up))
        let x0 = Int((cx - rx).rounded(.down)), x1 = Int((cx + rx).rounded(.up))
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = (Double(x) - cx) / rx
                let dy = (Double(y) - cy) / ry
                if dx * dx + dy * dy <= 1 { self[x, y] = c }
            }
        }
    }

    public func inEll(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ x: Double, _ y: Double) -> Bool {
        let dx = (x - cx) / rx, dy = (y - cy) / ry
        return dx * dx + dy * dy <= 1
    }

    public mutating func diamond(_ cx: Double, _ cy: Double, _ a: Double, _ b: Double, _ c: Pixel) {
        let y0 = Int((cy - b).rounded(.down)), y1 = Int((cy + b).rounded(.up))
        let x0 = Int((cx - a).rounded(.down)), x1 = Int((cx + a).rounded(.up))
        for y in y0...y1 {
            for x in x0...x1 {
                if abs(Double(x) - cx) * b + abs(Double(y) - cy) * a <= a * b {
                    self[x, y] = c
                }
            }
        }
    }

    public func inDiamond(_ cx: Double, _ cy: Double, _ a: Double, _ b: Double, _ x: Double, _ y: Double) -> Bool {
        abs(x - cx) * b + abs(y - cy) * a <= a * b
    }

    public mutating func ring(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Pixel) {
        let n = max(24, Int((rx + ry) * 3))
        for i in 0..<n {
            let t = Double(i) / Double(n) * .pi * 2
            px(cx + cos(t) * rx, cy + sin(t) * ry, c)
        }
    }

    public mutating func stamp(_ rows: [String], _ x: Int, _ y: Int, _ c: Pixel) {
        for j in 0..<rows.count {
            let row = Array(rows[j])
            for i in 0..<row.count where row[i] == "1" {
                rect(Double(x + i), Double(y + j), 1, 1, c)
            }
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension Color {
    /// 项目色板 hex 快捷构造（0xRRGGBB）
    init(hex: UInt) {
        self.init(Color.RGBColorSpace.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
#endif
