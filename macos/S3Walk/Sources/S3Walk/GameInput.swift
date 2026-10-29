// ゲームコントローラー（Joy-Con・SNES・PlayStation・Xbox など、Mac の GameController がわかるもの）と、トラックパッドの触覚
//   見回し（頭だけ）と進む向きは別（ウェブ版と同じ）。右スティック 進む向きを変える（矢印キー・Shift＋ドラッグ）、
//   ZL を押しながら右スティック 見回しだけ（ZL を押して離すだけで前を見る。マウスのドラッグ。地図は回らず、水色の円すいが見ている向き）、左スティック 進む向きへ歩く（W・S・A・D。手前に倒すと後ろへ）、
//   倒しきったままだと加速、左スティックを押し込む（L3） 軌跡（道すじ・足あと）を消す、Y・右スティックを押し込む 前を見る（進む向きは変えない。もう一度で水平にも）、ZL を押しながら Y この向きへ進む（Enter）、
//   L・R 上・下、ZR 速く、A アクセル（離すとゆっくり減速＝車のように）、B ブレーキ（押し始めはやわらかく）、X ターボ、Y 自動で走るの開始・停止、
//   十字の上 ターボ・下 ターボを切る・右 ターボの切りかえ、メニュー（＋） 設定、オプション（−） 地図を出す・隠す。Joy-Con を 1 本だけ横持ちした時は、十字（スティック）で歩き、A・X が使える
import Foundation
import GameController
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import QuartzCore

final class GameInput {
    private var prev: [String: Bool] = [:]
    var onButton: ((String) -> Void)?
    var names: [String] { GCController.controllers().map { $0.vendorName ?? "コントローラー" } }
    /// 確かめる時のにせの入力（コントローラーの代わり）
    var fake: (move: SIMD3<Double>, look: SIMD2<Double>, fast: Bool, push: Bool, lookOnly: Bool)?
    /// 左右のスティックを入れかえる（右で歩く・左で向き。押し込みの L3・R3 も入れかわる）。本物のコントローラーも画面のゲームパッドも
    var swapSticks = false

    init() {
        GCController.shouldMonitorBackgroundEvents = false
        GCController.startWirelessControllerDiscovery {}
    }

    /// 画面のゲームパッド（VirtualPad）：スティック（右・上が ＋、−1〜1）と押しているボタン。本物のコントローラーと足し合わせて読む
    var vLeft = SIMD2<Double>(0, 0), vRight = SIMD2<Double>(0, 0), vHeld: Set<String> = []
    /// 画面のゲームパッドのボタン k を押す・離す（押した時、A・B・X・Y・R3・十字・＋・− はコントローラーと同じく onButton へ）
    func vPress(_ k0: String, _ on: Bool) {
        let k = swapSticks ? (k0 == "L3" ? "R3" : k0 == "R3" ? "L3" : k0) : k0   // 入れかえた時は、押し込みも入れかわる
        if on { vHeld.insert(k) } else { vHeld.remove(k) }
        if on && ["A", "B", "X", "Y", "R3", "ZR", "up", "down", "right", "menu", "options"].contains(k) { onButton?(k) }
    }
    func vClear() { vLeft = .zero; vRight = .zero; vHeld = [] }

    /// 十字の上下を押している（上 ＋1・下 −1・なし 0）。決まった道の速さに使う
    var fakeDpad: Double? = nil
    func dpadY() -> Double {
        if let fakeDpad { return fakeDpad }
        var y = (vHeld.contains("up") ? 1.0 : 0) - (vHeld.contains("down") ? 1.0 : 0)
        for c in GCController.controllers() { if let g = c.extendedGamepad { if g.dpad.up.isPressed { y += 1 }; if g.dpad.down.isPressed { y -= 1 } } }
        return max(-1, min(1, y))
    }
    /// 確かめる時のにせのボタン（押している間）
    var fakeHeld: Set<String>? = nil
    /// A（アクセル）・B（ブレーキ）を押している
    func held(_ k: String) -> Bool {
        if let f = fakeHeld { return f.contains(k) }
        if vHeld.contains(k) { return true }
        return GCController.controllers().contains { c in
            guard let g = c.extendedGamepad else { return k == "A" ? c.microGamepad?.buttonA.isPressed == true : k == "B" ? c.microGamepad?.buttonX.isPressed == true : false }
            return k == "A" ? g.buttonA.isPressed : k == "B" ? g.buttonB.isPressed : false
        }
    }
    /// 十字の右を押している（ターボを押している間だけの時）
    func dpadRight() -> Bool { vHeld.contains("right") || GCController.controllers().contains { $0.extendedGamepad?.dpad.right.isPressed == true } }
    /// ターボのボタン（A か十字の右）を押している
    func turboButtonHeld() -> Bool { vHeld.contains("right") || vHeld.contains("A") || GCController.controllers().contains { g in g.extendedGamepad.map { $0.dpad.right.isPressed || $0.buttonA.isPressed } ?? false } }
    /// 毎コマ読む：歩く向き（右・上・前）、向きの変わり（方位・仰角、度／秒）、速く、左スティックを押し込んでいる（L3）、ZL（右スティックで見回しだけ）
    func read() -> (move: SIMD3<Double>, look: SIMD2<Double>, fast: Bool, push: Bool, lookOnly: Bool) {
        if let fake { return fake }
        var mv = SIMD3<Double>(0, 0, 0), lk = SIMD2<Double>(0, 0), fast = false, push = false, lookOnly = false
        func dz(_ v: Float) -> Double { let a = Double(v); return abs(a) < 0.15 ? 0 : (a - (a > 0 ? 0.15 : -0.15)) / 0.85 }   // 遊び
        for c in GCController.controllers() {
            if let g = c.extendedGamepad {
                let ls = swapSticks ? g.rightThumbstick : g.leftThumbstick, rs = swapSticks ? g.leftThumbstick : g.rightThumbstick
                let lb = swapSticks ? g.rightThumbstickButton : g.leftThumbstickButton, rb = swapSticks ? g.leftThumbstickButton : g.rightThumbstickButton
                mv.x += dz(ls.xAxis.value); mv.z += dz(ls.yAxis.value)
                lk.x += dz(rs.xAxis.value); lk.y += dz(rs.yAxis.value)
                if g.rightShoulder.isPressed { mv.y += 1 }
                if g.leftShoulder.isPressed { mv.y -= 1 }
                if g.rightTrigger.value > 0.5 { fast = true }
                if lb?.isPressed == true { push = true }
                if g.leftTrigger.value > 0.5 { lookOnly = true }
                edge("A", g.buttonA.isPressed); edge("B", g.buttonB.isPressed); edge("X", g.buttonX.isPressed); edge("Y", g.buttonY.isPressed)
                edge("R3", rb?.isPressed == true)
                edge("ZR", g.rightTrigger.value > 0.5)                 // ZR（PlayStation の R2）：自動走行の間は前を見る（ふだんは押している間だけ速く＝ fast）
                edge("up", g.dpad.up.isPressed); edge("down", g.dpad.down.isPressed); edge("right", g.dpad.right.isPressed); edge("menu", g.buttonMenu.isPressed)
                edge("options", g.buttonOptions?.isPressed == true)
            } else if let m = c.microGamepad {
                mv.x += dz(m.dpad.xAxis.value); mv.z += dz(m.dpad.yAxis.value)
                edge("A", m.buttonA.isPressed); edge("B", m.buttonX.isPressed)
            }
        }
        // 画面のゲームパッド
        let vl = swapSticks ? vRight : vLeft, vr = swapSticks ? vLeft : vRight
        mv.x += vl.x; mv.z += vl.y; lk += vr
        if vHeld.contains("R") { mv.y += 1 }
        if vHeld.contains("L") { mv.y -= 1 }
        if vHeld.contains("ZR") { fast = true }
        if vHeld.contains("L3") { push = true }
        if vHeld.contains("ZL") { lookOnly = true }
        return (mv, lk, fast, push, lookOnly)
    }
    /// スティックだけを読む（ボタンの押した瞬間の知らせは出さない。左・右は手で持った時の左右＝入れかえの設定によらない）
    func sticks() -> (left: SIMD2<Double>, right: SIMD2<Double>) {
        func dz(_ v: Float) -> Double { let a = Double(v); return abs(a) < 0.15 ? 0 : (a - (a > 0 ? 0.15 : -0.15)) / 0.85 }
        var l = SIMD2<Double>(0, 0), r = SIMD2<Double>(0, 0)
        for c in GCController.controllers() {
            guard let g = c.extendedGamepad else { continue }
            l += SIMD2(dz(g.leftThumbstick.xAxis.value), dz(g.leftThumbstick.yAxis.value)); r += SIMD2(dz(g.rightThumbstick.xAxis.value), dz(g.rightThumbstick.yAxis.value))
        }
        l += vLeft; r += vRight
        return (l, r)
    }
    /// 今押しているボタン・倒しているスティック（パネルに出して、どのボタンがどう読めているか確かめる）
    func pressedNames() -> String {
        var out: [String] = []
        for c in GCController.controllers() {
            guard let g = c.extendedGamepad else { continue }
            let pairs: [(String, Bool)] = [("A", g.buttonA.isPressed), ("B", g.buttonB.isPressed), ("X", g.buttonX.isPressed), ("Y", g.buttonY.isPressed),
                ("L", g.leftShoulder.isPressed), ("R", g.rightShoulder.isPressed), ("ZL", g.leftTrigger.value > 0.5), ("ZR", g.rightTrigger.value > 0.5),
                ("左スティック押し込み", g.leftThumbstickButton?.isPressed == true), ("右スティック押し込み", g.rightThumbstickButton?.isPressed == true),
                ("十字↑", g.dpad.up.isPressed), ("十字↓", g.dpad.down.isPressed), ("十字←", g.dpad.left.isPressed), ("十字→", g.dpad.right.isPressed), ("＋", g.buttonMenu.isPressed), ("−", g.buttonOptions?.isPressed == true)]
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
    static func milestone() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()   // iPhone は本体が震える
        #endif
    }
    /// 球層の殻を 1 枚通るごとに：かすかな「カチ」（つづけて鳴りすぎないよう 50 ミリ秒あける）
    static func tick() {
        let now = CACurrentMediaTime(); guard now - last > 0.05 else { return }; last = now
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
        #endif
    }
}
