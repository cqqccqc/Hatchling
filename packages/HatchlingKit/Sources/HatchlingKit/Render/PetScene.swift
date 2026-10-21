import Foundation
import SpriteKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 烘焙图集的命名与加载（bundle: HatchlingKit/Resources/Atlas）
public enum Atlas {
    static func cgImage(_ name: String) -> CGImage {
        guard let url = Bundle.module.url(forResource: name,
                                          withExtension: "png",
                                          subdirectory: "Resources/Atlas") else {
            print("⚠️ Atlas MISSING: \(name).png | bundle: \(Bundle.module.bundleURL.path)")
            let listed = (try? FileManager.default.subpathsOfDirectory(atPath: Bundle.module.bundleURL.path))?.prefix(10) ?? []
            print("⚠️ bundle contents sample: \(listed)")
            return PixelGrid(size: 1).makeCGImage()!
        }
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            print("⚠️ Atlas CORRUPT: \(name).png")
            return PixelGrid(size: 1).makeCGImage()!
        }
        return img
    }

    public static func texture(_ name: String) -> SKTexture {
        let t = SKTexture(cgImage: cgImage(name))
        t.filteringMode = .nearest
        return t
    }

    public static func body(spec: CreatureSpec) -> SKTexture {
        texture("body_\(spec.species.rawValue)_\(spec.color.rawValue)_\(spec.pattern.rawValue)_\(spec.phase)")
    }

    public static func eyes(_ state: EyeRenderState, _ color: ColorGene) -> SKTexture {
        texture("eyes_\(state.rawValue)_\(color.rawValue)")
    }

    public static func antenna(_ type: AntennaGene, _ color: ColorGene) -> SKTexture {
        texture("ant_\(type.rawValue)_\(color.rawValue)")
    }

    public static var background: SKTexture { texture("bg") }
}

/// 宠物舞台：图层合成（背景/身体/眼/天线）+ 呼吸 + 眨眼 + 双帧姿态
public final class PetScene: SKScene {
    private let gene: GeneValue
    private let petNode = SKNode()
    private let bodyNode = SKSpriteNode()
    private let eyeNode = SKSpriteNode()
    private let antNode = SKSpriteNode()

    public var state: EyeRenderState = .dot {
        didSet { eyeNode.texture = Atlas.eyes(state, gene.color.express) }
    }

    public init(gene: GeneValue, phase: Int = 0) {
        self.gene = gene
        super.init(size: CGSize(width: 48, height: 48))
        backgroundColor = .clear
        scaleMode = .aspectFit

        let spec = CreatureSpec.from(gene, eye: .dot, phase: phase)

        let bg = SKSpriteNode(texture: Atlas.background)
        bg.position = CGPoint(x: 24, y: 24)
        addChild(bg)


        bodyNode.texture = Atlas.body(spec: spec)
        bodyNode.size = CGSize(width: 48, height: 48)
        bodyNode.position = CGPoint(x: 24, y: 24)
        petNode.addChild(bodyNode)

        eyeNode.texture = Atlas.eyes(.dot, gene.color.express)
        eyeNode.size = CGSize(width: 48, height: 48)
        eyeNode.position = CGPoint(x: 24, y: 24)
        petNode.addChild(eyeNode)

        antNode.texture = Atlas.antenna(gene.antenna.express, gene.color.express)
        antNode.size = CGSize(width: 48, height: 48)
        antNode.position = CGPoint(x: 24, y: 24)
        petNode.addChild(antNode)

        addChild(petNode)

        // 呼吸（±1.2 网格单位，3s 循环）
        let breath = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 1.2, duration: 1.5),
            .moveBy(x: 0, y: -1.2, duration: 1.5),
        ]))
        petNode.run(breath)

        // 双帧姿态交替（裙摆/尾焰/晶体旋转）
        let t0 = Atlas.body(spec: spec)
        var specB = spec
        specB.phase = 1
        let t1 = Atlas.body(spec: specB)
        let phaseAnim = SKAction.repeatForever(.sequence([
            .wait(forDuration: 0.45), .setTexture(t1),
            .wait(forDuration: 0.45), .setTexture(t0),
        ]))
        bodyNode.run(phaseAnim)

        // 眨眼循环
        let closed = Atlas.eyes(.closed, gene.color.express)
        let open = Atlas.eyes(.dot, gene.color.express)
        let blink = SKAction.repeatForever(.sequence([
            .wait(forDuration: 3.1),
            .setTexture(closed), .wait(forDuration: 0.14), .setTexture(open),
        ]))
        eyeNode.run(blink)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }
}
