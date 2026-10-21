import Foundation
import SwiftUI

/// 方波音效 + 触觉（全局；M1.5 换 SquareWave 引擎真合成）
func beep(_ f: Double, _ d: Double = 0.08) {
    // TODO M1.5: AVAudioEngine 方波合成（采样器音色基因）
}

func chirp() {
    beep(520, 0.06)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { beep(780, 0.07) }
}

func hapticPulse() {
    // TODO: WKInterfaceDevice.current().play(.click)——真机触觉
}
