// 角度を動かす遊び（ウェブ版 hypercube.html の「回転アニメ」「角度のプリセット」「角度の往復（A〜D）」と同じ決まり）
//   回転アニメ：X-W・Y-W・Z-W に入れた角度まで 1.2 秒で（空欄は今のまま。どの面も短いほうへ回る）
//   角度のプリセット：今の 6 つの角度に名前を付けて保存（このアプリに覚える）。押すとその角度へなめらかに
//   往復：停留点（A・B・C・D…）を、往復（A→B→C→D→C→B→A…）か ぐるっと（A→B→C→D→A…）でめぐる。最初に今の角度から A へ 0.8 秒で寄せる。
//     動き方：ばね（前の区間の終わりの位置と速さを続ける減衰振動）・ターン・単振動・ゆりかご・バウンド。片道 1 回だけ（A→B と B→A が交互）も
import Foundation
import simd

/// 保存した角度（度）
struct AnglePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var deg: [Double]                         // X-W・Y-W・Z-W・X-Y・X-Z・Y-Z
    var lock: Bool? = nil                     // 消せないようにする（前に保存したものには無いので省略できる形）
    var locked: Bool { lock ?? false }
    static let key = "origami.anglePresets"
    static func load() -> [AnglePreset] {
        guard let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode([AnglePreset].self, from: d) else { return [] }
        return a
    }
    static func save(_ a: [AnglePreset]) { if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) } }
}

/// 保存した角度の往復（停留点・1 区間の秒数・往復かぐるっとか・動き方）
struct PingPongPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var stops: [[Double]]                     // 停留点（度。それぞれ X-W・Y-W・Z-W・X-Y・X-Z・Y-Z）
    var sec: Double
    var cycle: Bool
    var ease: String
    var spring: Double, turn: Double, sine: Double
    var lock: Bool? = nil
    var locked: Bool { lock ?? false }
    static let key = "origami.ppPresets"
    static func load() -> [PingPongPreset] {
        guard let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode([PingPongPreset].self, from: d) else { return [] }
        return a
    }
    static func save(_ a: [PingPongPreset]) { if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) } }
    var summary: String { String(format: "%d 点・%.1f 秒・", stops.count, sec) + (cycle ? "ぐるっと" : "往復") + "・" + (OrigamiState.ppEases.first { $0.0 == ease }?.1 ?? ease) }
}

/// 往復の途中のようす
struct PingPong {
    var from: [Double], A: [Double], pts: [[Double]], seq: [Int]
    var legSec: Double, t = 0.0, intro: Double, pj0: Double, pj1: Double, off0: Double, once: Bool
    var sp: (k: Int, x0: Double, v0: Double, zeta: Double)? = nil
}

extension OrigamiState {
    static let ppNames = ["A", "B", "C", "D", "E", "F", "G", "H"]
    static let ppEases: [(String, String)] = [("spring", "ばね"), ("turn", "ターン"), ("sine", "単振動"), ("cradle", "ゆりかご"), ("bounce", "バウンド")]
    var angles6: [Double] { [ax, ay, zw, xy, xz, yz] }
    var angles6Deg: [Double] { angles6.map { Self.wrapPi($0) * 180 / .pi } }
    /// 行き先の角度：なめらかに回っている途中なら、その行き先（途中の角度から次を決めると、前の回転が途中で止まって中途半端な角度が残る）
    var targetAngles6: [Double] { tween?.to ?? angles6 }
    var targetAngles6Deg: [Double] { targetAngles6.map { Self.wrapPi($0) * 180 / .pi } }
    func setAngles6(_ a: [Double]) { ax = a[0]; ay = a[1]; zw = a[2]; xy = a[3]; xz = a[4]; yz = a[5]; updateMats() }
    static func degText(_ d: [Double]) -> String { String(format: "%.0f・%.0f・%.0f｜%.0f・%.0f・%.0f", d[0], d[1], d[2], d[3], d[4], d[5]) }

    // ---- 回転アニメ ----
    func playRotAnim() {
        func target(_ s: String, _ cur: Double) -> Double {
            guard let n = Double(s.trimmingCharacters(in: .whitespaces)) else { return cur }   // 空欄・数でない時は今のまま
            return cur + Self.wrapPi(n * .pi / 180 - cur)
        }
        stopSpins(); stopPP(); cycling = false; presetPar = nil
        // 空欄の面は、回っている途中ならその行き先のまま（途中の角度で止めない）
        let g = targetAngles6
        let to = [target(animXW, g[0]), target(animYW, g[1]), target(animZW, g[2]), g[3], g[4], g[5]]
        tween = (angles6, to, 0, 1.2, projBlend, 0)                       // 手で決めた回転は遠近へ（ウェブ版と同じ）
    }
    /// 保存した角度（度）へなめらかに（投影：平行投影の時は W の角度が付いていれば平行）
    func animToAngles(_ deg: [Double]) {
        stopSpins(); stopPP(); cycling = false; presetPar = nil; xyManualOff = 0
        let to = deg.map { $0 * .pi / 180 }
        let turned = to[0..<3].contains { abs(Self.wrapPi($0)) > 0.02 }
        tween = (angles6, to, 0, 1.2, projBlend, !perspMode && turned ? 1 : 0)
    }

    // ---- 角度のプリセット ----
    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        presets.append(AnglePreset(name: name.isEmpty ? "角度 \(presets.count + 1)" : name, deg: angles6Deg)); presetName = ""
        AnglePreset.save(presets)
    }
    func deletePreset(_ p: AnglePreset) { if p.locked { return }; presets.removeAll { $0.id == p.id }; AnglePreset.save(presets) }
    // ---- 角度のプリセットの編集（名前・6 つの角度・今の角度で上書き・ロック・並べかえ）----
    func savePresets() { AnglePreset.save(presets) }
    func overwritePreset(_ i: Int) { guard presets.indices.contains(i) else { return }; presets[i].deg = angles6Deg; savePresets() }
    func toggleLockPreset(_ i: Int) { guard presets.indices.contains(i) else { return }; presets[i].lock = !presets[i].locked; savePresets() }
    func movePreset(_ i: Int, _ d: Int) { let j = i + d; guard presets.indices.contains(i), presets.indices.contains(j) else { return }; presets.swapAt(i, j); savePresets() }

    // ---- 往復のプリセット（ウェブ版の「往復を保存」）：今の停留点・秒数・往復／ぐるっと・動き方に名前を付けて保存。押すとそれで往復を始める ----
    func currentPP(_ name: String) -> PingPongPreset {
        PingPongPreset(name: name, stops: ppStops, sec: ppSec, cycle: ppCycle, ease: ppEase, spring: ppSpring, turn: ppTurn, sine: ppSine)
    }
    func savePPPreset() {
        let name = ppPresetName.trimmingCharacters(in: .whitespaces)
        ppPresets.append(currentPP(name.isEmpty ? "往復 \(ppPresets.count + 1)" : name)); ppPresetName = ""
        PingPongPreset.save(ppPresets)
    }
    func savePPPresets() { PingPongPreset.save(ppPresets) }
    /// プリセットを今の往復に入れる（start なら往復を始める）
    func loadPPPreset(_ p: PingPongPreset, start: Bool) {
        guard p.stops.count >= 2 else { return }
        ppStops = p.stops; ppSec = p.sec; ppCycle = p.cycle; ppEase = p.ease; ppSpring = p.spring; ppTurn = p.turn; ppSine = p.sine
        if start { startPP(ppStops, once: false) }
    }
    func overwritePPPreset(_ i: Int) {
        guard ppPresets.indices.contains(i) else { return }
        var p = currentPP(ppPresets[i].name); p.id = ppPresets[i].id; p.lock = ppPresets[i].lock; ppPresets[i] = p; savePPPresets()
    }
    func deletePPPreset(_ p: PingPongPreset) { if p.locked { return }; ppPresets.removeAll { $0.id == p.id }; savePPPresets() }
    func toggleLockPP(_ i: Int) { guard ppPresets.indices.contains(i) else { return }; ppPresets[i].lock = !ppPresets[i].locked; savePPPresets() }
    func movePP(_ i: Int, _ d: Int) { let j = i + d; guard ppPresets.indices.contains(i), ppPresets.indices.contains(j) else { return }; ppPresets.swapAt(i, j); savePPPresets() }

    // ---- 往復 ----
    func ppSetStop(_ i: Int) { ppStops[i] = angles6Deg }
    func ppAddStop() { if ppStops.count < Self.ppNames.count { ppStops.append(angles6Deg) } }
    func ppRemoveStop(_ i: Int) { if ppStops.count > 2 { ppStops.remove(at: i) } }
    func ppReverse() { ppStops.reverse() }
    /// A〜D に超立方体の 4 つの見方（胞から・面から・辺から・頂点から）を入れる
    func ppFillViews() { ppStops = Self.views.map { [$0.a * 180 / .pi, $0.b * 180 / .pi, $0.c * 180 / .pi, 0, 0, 0] } }
    func ppToggle() { if pp != nil && !(pp!.once) { stopPP() } else { startPP(ppStops, once: false) } }
    /// 片道を 1 回だけ（押すたびに A→B と B→A が交互）
    func ppOnce() {
        guard ppStops.count >= 2 else { return }
        startPP(ppOnceFwd ? [ppStops[0], ppStops[1]] : [ppStops[1], ppStops[0]], once: true); ppOnceFwd.toggle()
    }
    func startPP(_ stops: [[Double]], once: Bool) {
        spinX = false; spinY = false; spinZW = false; cycling = false; tween = nil; playing = false; loop = false   // 3D の回し続けるはそのまま（見る向きを回す）
        let pts = stops.map { $0.map { $0 * .pi / 180 } }, cur = angles6, a = pts[0], n = pts.count
        let turned = pts.contains { q in q[0..<3].contains { abs(Self.wrapPi($0)) > 0.02 } }
        let atStart = zip(a, cur).allSatisfy { abs(Self.wrapPi($0 - $1)) < 0.003 } && abs(xyManualOff) < 0.003
        var seq = Array(0..<n)
        if !(ppCycle && n > 2) { for i in stride(from: n - 2, through: 1, by: -1) { seq.append(i) } }   // 往復：端で折り返す（2 つなら A→B→A）
        pp = PingPong(from: cur, A: zip(a, cur).map { $1 + Self.wrapPi($0 - $1) }, pts: pts, seq: seq, legSec: max(0.1, ppSec),
                      intro: atStart ? 0 : 0.8, pj0: projBlend, pj1: !perspMode && turned ? 1 : 0, off0: xyManualOff, once: once)
        ppRunning = true
    }
    func stopPP() {
        guard let P = pp else { return }
        pp = nil; ppRunning = false
        presetPar = P.pj1; presetHold = SIMD3(ax, ay, zw)                // 投影は、W を動かすまでそのまま
        // 往復の間に回した見る向き（view3）を X-Y・X-Z・Y-Z に入れて、見た目を変えずに元にもどす
        if view3 != matrix_identity_double4x4 {
            let prev = [xy, xz, yz], r = Self.decompose(view3 * Self.R(1, 2, yz) * Self.R(0, 2, xz) * Self.R(0, 1, xy), prev)
            xy = r[0]; xz = r[1]; yz = r[2]; xyManualOff = Self.wrapPi(xyManualOff + Self.wrapPi(xy - prev[0]))
            view3 = matrix_identity_double4x4; updateMats()
        }
    }
    /// 区間の進み u（0→1）を位置（0→1）へ。ばねは別（前の区間から続ける）
    func ppEaseF(_ u: Double) -> Double {
        switch ppEase {
        case "turn":
            let k = 1 - pow(10, -(0.5 + 2.5 * ppTurn))
            return 0.5 - asin(k * cos(.pi * u)) / (2 * asin(k))
        case "cradle": return u - sin(2 * .pi * u) / (2 * .pi)
        case "bounce":
            let n1 = 7.5625, d1 = 2.75
            if u < 1 / d1 { return n1 * u * u }
            if u < 2 / d1 { let v = u - 1.5 / d1; return n1 * v * v + 0.75 }
            if u < 2.5 / d1 { let v = u - 2.25 / d1; return n1 * v * v + 0.9375 }
            let v = u - 2.625 / d1; return n1 * v * v + 0.984375
        default:                                                          // 単振動（緩やかさで、端で加速も 0 の形と混ぜる）
            let a = (1 - cos(.pi * u)) / 2, b = u - sin(2 * .pi * u) / (2 * .pi)
            return a + (b - a) * (1 - ppSine)
        }
    }
    /// 目標 T へ向かう減衰ばねの、時間 tau 後の位置と速さ
    static func springLeg(_ x0: Double, _ v0: Double, _ T: Double, _ tau: Double, _ zeta: Double, _ omega: Double) -> (Double, Double) {
        let wd = omega * sqrt(1 - zeta * zeta), a = zeta * omega, e0 = x0 - T, B = (v0 + a * e0) / wd
        let ex = exp(-a * tau), c = cos(wd * tau), sn = sin(wd * tau)
        return (T + ex * (e0 * c + B * sn), ex * (-a * (e0 * c + B * sn) + (-e0 * wd * sn + B * wd * c)))
    }
    func tickPP(_ dt: Double) {
        guard var P = pp else { return }
        // 4D の回し続ける・周回が入ったら往復を止める（3D の回し続けるは、往復の上から見る向きを回すので止めない）
        if spinX || spinY || spinZW || cycling { stopPP(); return }
        P.t += dt
        if P.t < P.intro {                                                // 今の角度から A へ
            let f = Self.smoother(P.t / P.intro)
            setAngles6(zip(P.from, P.A).map { $0 + ($1 - $0) * f })
            projBlend = P.pj0 + (P.pj1 - P.pj0) * f; xyManualOff = P.off0 * (1 - f)
            pp = P; return
        }
        projBlend = P.pj1; xyManualOff = 0
        let u = (P.t - P.intro) / P.legSec, L = P.seq.count
        func leg(_ k: Int) -> ([Double], [Double]) { (P.pts[P.seq[((k % L) + L) % L]], P.pts[P.seq[(((k + 1) % L) + L) % L]]) }
        func place(_ k: Int, _ f: Double) { let (p0, p1) = leg(k); setAngles6(zip(p0, p1).map { Self.wrapPi($0 + Self.wrapPi($1 - $0) * f) }) }
        func endAt(_ k: Int) { setAngles6(leg(k).1.map { Self.wrapPi($0) }) }
        if ppEase == "spring" {                                           // ばね：区間が短いほど減衰を弱めて、よく弾む
            let zeta = max(0.12, (0.85 - 0.55 * ppSpring) * min(1, sqrt(P.legSec / 3))), omega = 4 / (0.85 * P.legSec * zeta)
            if P.once {
                let (f, v) = Self.springLeg(0, 0, 1, max(0, u) * P.legSec, zeta, omega)
                if u >= 1 && ((abs(f - 1) < 0.002 && abs(v) < 0.02) || u >= 1.6) { endAt(0); pp = P; stopPP(); return }
                place(0, f); pp = P; return
            }
            let k = max(0, Int(floor(u)))
            if P.sp == nil || P.sp!.k > k || P.sp!.zeta != zeta { P.sp = (0, 0, 0, zeta) }
            while P.sp!.k < k {                                           // 前の区間の終わり（行き過ぎと速さ）を次へ。折り返す区間は向きを反対に
                let r = Self.springLeg(P.sp!.x0, P.sp!.v0, 1, P.legSec, zeta, omega), kk = P.sp!.k + 1
                let turn = P.seq[((kk + 1) % L + L) % L] == P.seq[((kk - 1) % L + L) % L]
                P.sp = (kk, turn ? 1 - r.0 : r.0 - 1, turn ? -r.1 : r.1, zeta)
            }
            let (f, _) = Self.springLeg(P.sp!.x0, P.sp!.v0, 1, (u - Double(k)) * P.legSec, zeta, omega)
            place(k, f); pp = P; return
        }
        if P.once && u >= 1 { endAt(0); pp = P; stopPP(); return }
        let k = Int(floor(u))
        place(k, ppEaseF(u - Double(k))); pp = P
    }
}
