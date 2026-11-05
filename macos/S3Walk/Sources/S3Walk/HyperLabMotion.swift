// 超球の自動の動き：超球デモ・超球を詰める・視点切りかえ・2 重回転（回す・ゆらす）・4D 回転。
//   4 つの角度（前後・左右・面内・Z-W）を動かす係はここにまとめる。同時に動かすと取り合いになる組は claim で切る
import SwiftUI
import MetalKit
import CoreVideo

/// 自動の動きの途中の値（HyperLabState.run）。設定ではないので覚えない
struct HLMotionRun {
    var demoT = 0.0, demoDt = 1.0 / 60, demoKeep: [Double] = [], demoPoles = 0, demoAuto = false, demoSpin = false
    var shotT = 0.0, shotK = 1.0, shotNow = -1, shotFrom: [Double] = [], shotTo: [Double] = [], shotZW = false, shotYaw = false
    var curveK: [[Double]] = [], curveN: [String] = []
    var swingC = SIMD2<Double>(0, 0), swingP = SIMD2<Double>(0, 0)   // ゆらす：真ん中の角度（面内・Z-W）と位相
}

extension HyperLabState {
    /// 4 つの角度を自動で動かす係
    enum AngleDriver { case auto, rot2, follow, followXYZ, shots }
    /// 取り合いになる組：入れた係が、ここに並んだ係を切る（4D 回転と 2 重回転・2 重回転と自分を追う・自分を追う 2 つ・視点切りかえと自分を追う）
    static let angleConflicts: [AngleDriver: [AngleDriver]] = [.auto: [.rot2], .rot2: [.auto, .follow], .follow: [.followXYZ, .rot2], .followXYZ: [.follow], .shots: [.follow]]
    func claim(_ d: AngleDriver) {
        for o in Self.angleConflicts[d] ?? [] {
            switch o {
            case .auto: auto = false
            case .rot2: rot2On = false
            case .follow: followOn = false
            case .followXYZ: followXYZ = false
            case .shots: shotOn = false
            }
        }
    }
    func swingStart() { run.swingC = SIMD2(yaw, zw); run.swingP = .zero }
    /// 書き出しの裏で動かす超球へ、今の傾きと自動の動きを写す（Exporter）
    func copyMotion(from s: HyperLabState) {
        zw = s.zw; pitch = s.pitch; roll = s.roll; yaw = s.yaw; cutPos = s.cutPos
        auto = s.auto; spin3D = s.spin3D; rot2XY = s.rot2XY; rot2ZW = s.rot2ZW; rot2Swing = s.rot2Swing; rot2Amp = s.rot2Amp; rot2On = s.rot2On
        shotEvery = s.shotEvery; shotEase = s.shotEase; shotCam = s.shotCam; shotCurve = s.shotCurve; shotCurveEvery = s.shotCurveEvery; shotOn = s.shotOn
        viewYaw = s.viewYaw; viewPitch = s.viewPitch; followOn = s.followOn; followXYZ = s.followXYZ; followSlack = s.followSlack; followSpeed = s.followSpeed; followHeading = s.followHeading; followDrift = s.followDrift
        cutOn = s.cutOn; cutSweep = s.cutSweep; cutKind = s.cutKind
    }
    // 超球デモ（約 1 分強）：W 消失の真正面で、中に閉じ込められた赤玉を見せ、4D の回転で表へ出す。超球の見る向きをときどき変えて、左の 3D の球と同じ動きに見えないようにする
    /// 時刻（秒）・前後（Y-W）・左右（X-W）・面内・Z-W・3D の左右・3D の上下（度）
    static let demoKeys: [[Double]] = [
        [0, 0, 0, 0, 0, 0, 0],                                         // W 消失の真正面。赤玉は真ん中
        [6, 0, 0, 60, 0, 180, 20], [12, 0, 0, 120, 0, 360, 0],         // くるくる回しても、赤玉は中に閉じ込められたまま
        [14, 0, 0, 0, 0, 360, 0],
        [24, -90, 0, 0, 0, 360, 0],                                    // 真正面のまま、赤玉が表へにょきっと
        [28, -90, 0, 0, 0, 400, 15],                                   // 横からも見る
        [32, -90, 0, 0, 0, 360, 80], [34, -90, 0, 0, 0, 360, 80],      // 赤玉を画面へ向ける
        [48, -90, 0, 720, 0, 360, 80], [50, -90, 0, 720, 0, 360, 80],  // 赤玉を止めたまま 4D で 2 回転：隠れた軸が回るので、形だけが変わり続ける
        [56, 0, 0, 720, 0, 360, 0],                                    // また中へ
        [61, 0, -90, 720, 0, 325, 10], [63, 0, -90, 720, 0, 325, 10],  // 別の向きから、横へ出す
        [68, 0, 0, 720, 0, 360, 0]]
    static let demoLen = 70.0                                          // 最後の 2 秒で、始める前の向きへ戻る
    static func demoGlassK(_ pitch: Double, _ roll: Double) -> Double { let c = cos(pitch) * cos(roll); return 0.3 + 0.7 * (1 - c * c) }
    /// 時刻 t のキーの間をなめらかにつないだ値（度）
    static func demoPose(_ t: Double) -> [Double] {
        let keys = demoKeys
        guard t > 0 else { return Array(keys[0].dropFirst()) }
        for k in 1..<keys.count where t <= keys[k][0] {
            let a = keys[k - 1], b = keys[k], u = max(0, min(1, (t - a[0]) / (b[0] - a[0]))), e = u * u * (3 - 2 * u)
            return (1...6).map { a[$0] + (b[$0] - a[$0]) * e }
        }
        return Array(keys[keys.count - 1].dropFirst())
    }
    func toggleDemo() {
        if demoOn { endDemo(); return }
        run.demoKeep = [pitch, roll, yaw, zw, viewYaw, viewPitch]; run.demoPoles = polesMode; run.demoAuto = auto; run.demoSpin = spin3D
        auto = false; spin3D = false; polesMode = 2; run.demoT = 0; demoOn = true
    }
    private func endDemo() {
        pitch = run.demoKeep[0]; roll = run.demoKeep[1]; yaw = run.demoKeep[2]; zw = run.demoKeep[3]; viewYaw = run.demoKeep[4]; viewPitch = run.demoKeep[5]
        polesMode = run.demoPoles; auto = run.demoAuto; spin3D = run.demoSpin; demoOn = false; demoGlass = 1; version &+= 1; bump()
    }
    func tickDemo(_ dt: Double) {
        run.demoDt += (min(0.05, dt) - run.demoDt) * 0.08                      // コマの間隔は 8〜30 ms でばらつくので、ならした時間で進める（1 コマごとの動きをそろえる）
        run.demoT += run.demoDt
        if run.demoT >= Self.demoLen { endDemo(); return }
        let p = Self.demoPose(run.demoT).map { $0 * .pi / 180 }, last = run.demoT > Self.demoLen - 2 ? (run.demoT - Self.demoLen + 2) / 2 : 0, e = last * last * (3 - 2 * last)
        func put(_ v: Double, _ k: Int) -> Double { let d = Self.norm(run.demoKeep[k] - v); return Self.norm(v + d * e) }
        pitch = put(p[0], 0); roll = put(p[1], 1); yaw = put(p[2], 2); zw = put(p[3], 3); viewYaw = put(p[4], 4); viewPitch = put(p[5], 5)
        demoGlass = Self.demoGlassK(pitch, roll) * (1 - e) + e; version &+= 1
    }
    static let fillLen = 16.0
    /// 半径 a より外側を詰めた時の体積（a ＝ 0 で超球の全体 π²/2）
    static func fillVolume(_ a: Double) -> Double { .pi * .pi / 2 * (1 - pow(a, 4)) }
    /// 描く殻：外から内へ（半径・濃さ）。新しい殻はだんだん現れる
    func fillShells() -> [(r: Double, k: Float)] {
        let n = max(2, min(30, fillCount))
        return (0..<n).compactMap { i in
            let r = 1 - Double(i) / Double(n), k = i == 0 ? 1 : min(1, (r - fillA) * Double(n))
            return k > 0 ? (r, Float(k)) : nil
        }
    }
    func toggleFill() { fillOn.toggle(); fillA = 1; if fillOn { expandOn = false }; version &+= 1 }
    /// 名前・前後・左右・Z-W（度）。左下の地図と同じ向き：Y 消失は w が上、X 消失は w が右、Z 消失は w が手前。反転は w の頭とケツを入れかえる
    static let shotList: [(name: String, pitch: Double, roll: Double, zw: Double)] = [
        ("W 消失", 0, 0, 0), ("W 消失・反転", 180, 0, 0), ("Y 消失", -90, 0, 0), ("Y 消失・反転", 90, 0, 0), ("X 消失", 0, 90, 0), ("X 消失・反転", 0, -90, 0),
        ("Z 消失", 0, 0, -90), ("Z 消失・反転", 0, 0, 90), ("斜め", 37, 13, 0), ("斜めの裏", -50, 40, 0)]
    static let shotCams: [(yaw: Double, pitch: Double)] = [(0, 0), (0, 0), (30, 15), (-30, 12), (20, -20), (-40, 25)]
    /// 次の見え方（今と同じ軸は続けない。Z-W を回している間は Z-W を動かす見え方を除く）
    private func nextShot(_ zwTurning: Bool) -> Int {
        func family(_ i: Int) -> Character { Self.shotList[i].name.first ?? " " }
        let c = Self.shotList.indices.filter { i in i != run.shotNow && !(zwTurning && Self.shotList[i].zw != 0) && (run.shotNow < 0 || family(i) != family(run.shotNow)) }
        return c.randomElement() ?? 0
    }
    /// 次の見え方の目印（前後・左右・Z-W・面内・3D の左右・上下）。角度は前の目印から近い回り方でつなげる
    private func shotKey(after prev: [Double]) -> [Double] {
        run.shotNow = nextShot(rot2On && abs(rot2ZW) >= 0.5)
        let s = Self.shotList[run.shotNow], pick = Self.shotCams.randomElement() ?? (yaw: 0, pitch: 0)
        let raw = [s.pitch * .pi / 180, s.roll * .pi / 180, s.zw * .pi / 180, 0, shotCam ? pick.yaw * .pi / 180 : prev[4], shotCam ? pick.pitch * .pi / 180 : prev[5]]
        run.curveN.append(s.name)
        return (0..<6).map { prev[$0] + Self.norm(raw[$0] - prev[$0]) }
    }
    private func tickShotCurve(_ dt: Double) {
        let every = max(0.4, shotCurveEvery)
        if run.curveK.count != 4 {
            let p = [pitch, roll, zw, yaw, viewYaw, viewPitch]
            run.curveN = ["", ""]; let a = shotKey(after: p); run.curveK = [p, p, a, shotKey(after: a)]; run.shotT = 0
        }
        run.shotT += dt
        while run.shotT >= every { run.shotT -= every; run.curveK.removeFirst(); run.curveN.removeFirst(); run.curveK.append(shotKey(after: run.curveK[2])) }
        let u = run.shotT / every, u2 = u * u, u3 = u2 * u
        func at(_ k: Int) -> Double {
            let p0 = run.curveK[0][k], p1 = run.curveK[1][k], p2 = run.curveK[2][k], p3 = run.curveK[3][k]
            return Self.norm(0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3))
        }
        pitch = at(0); roll = at(1)
        if !(rot2On && abs(rot2ZW) >= 0.5) { zw = at(2) }              // 回している角度は触らない
        if !rot2On { yaw = at(3) }
        if shotCam && !spin3D { viewYaw = at(4); viewPitch = at(5) }   // 3D 回転を入れている間は、3D のカメラは回転にまかせる
        let n = "→ " + run.curveN[2]; if shotName != n { shotName = n }
        version &+= 1
    }
    private func tickShot(_ dt: Double) {
        if shotCurve { tickShotCurve(dt); return }
        run.shotT += dt
        if run.shotT >= shotEvery {
            run.shotT = 0
            let turning = rot2On && abs(rot2ZW) >= 0.5
            run.shotNow = nextShot(turning)
            let s = Self.shotList[run.shotNow], pick = Self.shotCams.randomElement() ?? (yaw: 0, pitch: 0)
            let c = shotCam ? [pick.yaw, pick.pitch] : [viewYaw * 180 / .pi, viewPitch * 180 / .pi]
            run.shotFrom = [pitch, roll, zw, yaw, viewYaw, viewPitch]
            run.shotTo = [s.pitch, s.roll, s.zw, 0, c[0], c[1]].map { $0 * .pi / 180 }
            run.shotZW = !turning; run.shotYaw = !rot2On                            // 回している角度は触らない
            run.shotK = 0; shotName = s.name
        }
        guard run.shotK < 1, run.shotTo.count == 6 else { return }
        run.shotK = shotEase < 0.01 ? 1 : min(1, run.shotK + dt / shotEase)
        let e = run.shotK * run.shotK * (3 - 2 * run.shotK)
        func to(_ k: Int) -> Double { Self.norm(run.shotFrom[k] + Self.norm(run.shotTo[k] - run.shotFrom[k]) * e) }
        pitch = to(0); roll = to(1); viewYaw = to(4); viewPitch = to(5)
        if run.shotZW { zw = to(2) }
        if run.shotYaw { yaw = to(3) }
        version &+= 1
    }
    /// 今の速さの組み合わせの名前
    var rot2Kind: String {
        let a = abs(rot2XY), b = abs(rot2ZW)
        if a < 0.5 && b < 0.5 { return "止まっている" }
        if rot2Swing { return a < 0.5 ? "Z-W だけをゆらす" : b < 0.5 ? "X-Y だけをゆらす" : abs(a - b) < 0.5 ? "クリフォード回転でゆらす" : "2 重回転でゆらす" }
        if a < 0.5 { return "Z-W だけの回転（X-Y の円は動かない）" }
        if b < 0.5 { return "X-Y だけの回転（Z-W の円は動かない）" }
        return abs(a - b) < 0.5 ? "クリフォード回転（全部の点が同じ速さ）" : "2 重回転（動かない点はない）"
    }
    /// Z-W 回転だけ：Z-W を回し続けて、ほかの角度（前後・左右・面内）は手で動かす
    var rot2ZWOnly: Bool {
        get { rot2On && abs(rot2XY) < 0.5 }
        set { if newValue { rot2XY = 0; if abs(rot2ZW) < 0.5 { rot2ZW = 30 } }; rot2On = newValue }
    }
    /// 2 重回転（メニュー）：Z-W だけの後に入れた時は、止めた面の速さを戻す
    var rot2Both: Bool {
        get { rot2On && !rot2ZWOnly }
        set { if newValue { if abs(rot2XY) < 0.5 { rot2XY = 30 }; if abs(rot2ZW) < 0.5 { rot2ZW = 30 } }; rot2On = newValue }
    }
    /// 速さの比を選ぶ：X-Y の速さはそのままで、Z-W を X-Y の k 倍に
    func rot2Ratio(_ k: Double) { if abs(rot2XY) < 0.5 { rot2XY = 30 }; rot2ZW = rot2XY * k }
    /// 毎コマ（受け持ちの画面が呼ぶ）：視点切りかえ・3D 回転・2 重回転・4D 回転（ウェブ版の「複合」：前後と左右を 1 : 0.67 の速さで）の順に角度を進める
    func tick(_ dt: Double) {
        if demoOn { return }                                           // デモは大きな画面の 1 コマごとに進める（tickDive）
        if shotOn { tickShot(dt) }
        if spin3D && !followXYZ { viewYaw = Self.norm(viewYaw + 0.3 * dt); version &+= 1 }   // 3D 回転：3D のカメラだけ回す（1 周 約 21 秒）。xyz のみで追う間はカメラをそちらに任せて休む
        if rot2On {
            let vx = rot2XY * .pi / 180, vz = rot2ZW * .pi / 180
            if rot2Swing {                                             // 止めた面は手で動かせるように触らない（動き出す時に、そこを真ん中にする）
                let a = rot2Amp * .pi / 180
                if abs(rot2XY) < 0.5 { run.swingC.x = yaw; run.swingP.x = 0 } else { run.swingP.x = (run.swingP.x + vx * dt).truncatingRemainder(dividingBy: 2 * .pi); yaw = Self.norm(run.swingC.x + a * sin(run.swingP.x)) }
                if abs(rot2ZW) < 0.5 { run.swingC.y = zw; run.swingP.y = 0 } else { run.swingP.y = (run.swingP.y + vz * dt).truncatingRemainder(dividingBy: 2 * .pi); zw = Self.norm(run.swingC.y + a * sin(run.swingP.y)) }
            } else { yaw = Self.norm(yaw + vx * dt); zw = Self.norm(zw + vz * dt) }
            version &+= 1
        }
        guard auto else { return }
        let d = 0.72 * dt
        pitch = Self.norm(pitch + d); roll = Self.norm(roll + d * 0.67); version &+= 1
    }
}
