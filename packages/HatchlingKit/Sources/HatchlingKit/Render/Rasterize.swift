import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public extension PixelGrid {
    /// 栅格化为 CGImage（RGBA 预乘）
    func makeCGImage() -> CGImage? {
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            if let p = pixels[i] {
                buf[i * 4] = p.r
                buf[i * 4 + 1] = p.g
                buf[i * 4 + 2] = p.b
                buf[i * 4 + 3] = p.a
            }
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &buf, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        return ctx.makeImage()
    }

    func pngData() -> Data? {
        guard let img = makeCGImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// 最近邻放大（像素风图标/大图用，插值关闭保锐利）
    func upscaledCGImage(factor: Int) -> CGImage? {
        guard let base = makeCGImage() else { return nil }
        let w = size * factor, h = size * factor
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func writePNG(to url: URL) throws {
        guard let data = pngData() else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        try data.write(to: url)
    }
}
