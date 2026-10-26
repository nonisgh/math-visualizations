// ゲームコントローラー（Joy-Con・SNES・PlayStation・Xbox など、Mac の GameController がわかるもの）と、トラックパッドの触覚
//   見回し（頭だけ）と進む向きは別（ウェブ版と同じ）。右スティック 進む向きを変える（矢印キー・Shift＋ドラッグ）、
//   ZL を押しながら右スティック 見回しだけ（ZL を押して離すだけで前を見る。マウスのドラッグ。地図は回らず、水色の円すいが見ている向き）、左スティック 進む向きへ歩く（W・S・A・D。手前に倒すと後ろへ）、
//   倒しきったままだと加速、左スティックを押し込む（L3） 軌跡（道すじ・足あと）を消す、Y・右スティックを押し込む 前を見る（進む向きは変えない。もう一度で水平にも）、ZL を押しながら Y この向きへ進む（Enter）、
//   L・R 上・下、ZR 速く、A 目印を置く、B 歩き続ける、X 縦横無尽、
//   十字 上下 殻の見える距離、メニュー 設定。Joy-Con を 1 本だけ横持ちした時は、十字（スティック）で歩き、A・X が使える
import Foundation
import GameController
import AppKit

final class GameInput {
    private var prev: [String: Bool] = [:]
    var onButton: ((String) -> Void)?
    var names: [String] { GCController.controllers().map { $0.vendorName ?? "コントローラー" } }
    /// 確かめる時のにせの入力（コントローラーの代わり）
    var fake: (move: SIMD3<Double>, look: SIMD2<Double>, fast: Bool, push: Bool, lookOnly: Bool)?

    init() {
        GCController.shouldMonitorBackgroundEvents = false
        GCController.startWirelessControllerDiscovery {}
    }

    /// 毎コマ読む：歩く向き（右・上・前）、向きの変わり（方位・仰角、度／秒）、速く、左スティックを押し込んでいる（L3）、ZL（右スティックで見回しだけ）
    func read() -> (move: SIMD3<Double>, look: SIMD2<Double>, fast: Bool, push: Bool, lookOnly: Bool) {
        if let fake { return fake }
        var mv = SIMD3<Double>(0, 0, 0), lk = SIMD2<Double>(0, 0), fast = false, push = false, lookOnly = false
        func dz(_ v: Float) -> Double { let a = Double(v); return abs(a) < 0.15 ? 0 : (a - (a > 0 ? 0.15 : -0.15)) / 0.85 }   // 遊び
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                mv.x += dz(g.leftThumbstick.xAxis.value); mv.z += dz(g.leftThumbstick.yAxis.value)
                lk.x += dz(g.rightThumbstick.xAxis.value); lk.y += dz(g.rightThumbstick.yAxis.value)
                if g.rightShoulder.isPressed { mv.y += 1 }
                if g.leftShoulder.isPressed { mv.y -= 1 }
                if g.rightTrigger.value > 0.5 { fast = true }
                if g.leftThumbstickButton?.isPressed == true { push = true }
                if g.leftTrigger.value > 0.5 { lookOnly = true }
                edge("A", g.buttonA.isPressed); edge("B", g.buttonB.isPressed); edge("X", g.buttonX.isPressed); edge("Y", g.buttonY.isPressed)
                edge("R3", g.rightThumbstickButton?.isPressed == true)
                edge("up", g.dpad.up.isPressed); edge("down", g.dpad.down.isPressed); edge("menu", g.buttonMenu.isPressed)
            } else if let m = c.microGamepad {
                mv.x += dz(m.dpad.xAxis.value); mv.z += dz(m.dpad.yAxis.value)
                edge("A", m.buttonA.isPressed); edge("B", m.buttonX.isPressed)
            }
        }
        return (mv, lk, fast, push, lookOnly)
    }
    /// 今押しているボタン・倒しているスティック（パネルに出して、どのボタンがどう読めているか確かめる）
    func pressedNames() -> String {
        var out: [String] = []
        for c in GCController.controllers() {
            guard let g = c.extendedGamepad else { continue }
            let pairs: [(String, Bool)] = [("A", g.buttonA.isPressed), ("B", g.buttonB.isPressed), ("X", g.buttonX.isPressed), ("Y", g.buttonY.isPressed),
                ("L", g.leftShoulder.isPressed), ("R", g.rightShoulder.isPressed), ("ZL", g.leftTrigger.value > 0.5), ("ZR", g.rightTrigger.value > 0.5),
                ("左スティック押し込み", g.leftThumbstickButton?.isPressed == true), ("右スティック押し込み", g.rightThumbstickButton?.isPressed == true),
                ("十字↑", g.dpad.up.isPressed), ("十字↓", g.dpad.down.isPressed), ("十字←", g.dpad.left.isPressed), ("十字→", g.dpad.right.isPressed)]
            out += pairs.filter { $0.1 }.map { $0.0 }
            if abs(g.leftThumbstick.xAxis.value) > 0.15 || abs(g.leftThumbstick.yAxis.value) > 0.15 { out.append("左スティック") }
            if abs(g.rightThumbstick.xAxis.value) > 0.15 || abs(g.rightThumbstick.yAxis.value) > 0.15 { out.append("右スティック") }
        }
        return out.isEmpty ? "なし" : out.joined(separator: "・")
    }
    private func edge(_ k: String, _ on: Bool) {
        if on && prev[k] != true { onButton?(k) }
        prev[k] = on
    }
}

/// トラックパッドの触覚（Force Touch のトラックパッドに指を置いている時だけ感じる）
enum Haptic {
    private static var last = 0.0
    /// 赤道・極を通った時：「コツン」
    static func milestone() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    /// 球層の殻を 1 枚通るごとに：かすかな「カチ」（つづけて鳴りすぎないよう 50 ミリ秒あける）
    static func tick() {
        let now = CACurrentMediaTime(); guard now - last > 0.05 else { return }; last = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
