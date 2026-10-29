// 正しさの確かめ（`S3Walk --verify`）と計測（`S3Walk --bench`）
//   計算：moveAlong で歩いても体の枠が正規直交のまま・大円を 2π 歩くと元に戻る
//   画面：アプリと同じ配置・同じシェーダーで画面の外に描き、画素から
//     ① 目印の見かけの大きさ α が sin α = sin r / |sin d| になること（近い道と遠回りの像の両方）
//     ② 遠回りの像が 180° 回ること（玉の右上の赤い点が左下に来る。鏡なら左上か右下）
//     ③ 北極（アナ極）では、反対側の南極の玉が空全体をおおうこと
import Foundation
import Metal
import QuartzCore
import simd
import ImageIO
import UniformTypeIdentifiers

enum Verify {
    static var ok = true
    static func check(_ cond: Bool, _ msg: String) { print((cond ? "  ✓ " : "  ✗ ") + msg); if !cond { ok = false } }

    static func run() -> Bool {
        print("== 計算（moveAlong）==")
        cpuChecks()
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { print("Metal が使えない"); return false }
        print("== 画面（\(dev.name)、Metal のシェーダーで描いた画素から）==")
        gpuChecks(r)
        print("== 歩く・知らせ・足あと・保存（画面なしで、アプリと同じ step を 1/60 秒ずつ）==")
        journeyChecks(r)
        print("== パネルのドック（並べかえ・たたみ・保存）==")
        dockChecks()
        print("== スライダー（数字の入力・矢印キー）==")
        check(HLSlider.parse("15", 3, 41) == 15 && HLSlider.parse("９", 0, 1.5) == 1.5 && HLSlider.parse("−30°", -180, 180) == -30 && HLSlider.parse("abc", 0, 1) == nil,
              "数字の入力：15 → 15、全角の ９（範囲 0〜1.5）→ 1.5、−30° → −30、文字だけ → 変えない")
        check(HLSlider.nudged(11, 1, "%.0f", 3, 41) == 12 && abs(HLSlider.nudged(0.82, -1, "%.2f", 0, 1.5) - 0.81) < 1e-9
              && abs(HLSlider.nudged(0.9, 10, "%.1f", 0.6, 4) - 1.9) < 1e-9 && HLSlider.nudged(175, 10, "%+.0f°", -180, 180) == 180,
              "矢印キー：層数 11 → 12、光沢 0.82 → 0.81、線の太さ 0.9 →（Shift）1.9、傾き 175° →（Shift）180°（端で止まる）")
        print("== 周回（目印を全部通ったら 1 周）==")
        do {
            var j = Journey(); j.marks = [nrm(SIMD4(1, 0, 0, 0.2)), nrm(SIMD4(0, 1, 0, 0.2))]
            var said: [String] = []
            func go(_ p: SIMD4<Double>) { j.walked(nrm(p), 0.01, footOn: false) { said.append($0) } }
            // m のすぐ横を通り過ぎる（遠く → 近づく → いちばん近い → 離れる → 遠く）
            func pass(_ m: SIMD4<Double>) { let q = nrm(m), s = nrm(SIMD4(0, 0, 1, 0) - q * simd_dot(SIMD4(0, 0, 1, 0), q)); for t in [-0.5, -0.08, -0.03, 0.0, 0.03, 0.08, 0.5] { go(q * cos(t) + s * sin(t)) } }
            go(SIMD4(0, 0, 0, 1)); pass(SIMD4(1, 0, 0, 0.2)); go(SIMD4(0, 0, 0, 1)); pass(SIMD4(0, 1, 0, 0.2))   // 目印 1 → 2：1 周
            let lap2 = j.lap == 2 && j.marksHit.isEmpty, tr2 = j.trail.count   // 1 周した直後の跡の点の数
            go(SIMD4(0, 0, 0, 1)); pass(SIMD4(1, 0, 0, 0.2))                                                     // 次の周の 1 つ目
            check(lap2 && j.marksHit.count == 1 && said.contains { $0.contains("2 周目へ") } && tr2 <= 3,
                  "目印 2 つを全部通ると 2 周目に（チェックと跡をリセット）。次の周も数える（\(j.lap) 周目・通った \(j.marksHit.count)・1 周した直後の跡 \(tr2) 点）")
        }
        do {                                                             // 目印がない時は、8 つの極を全部通ったら 1 周
            var j = Journey(); var said: [String] = []
            func go(_ p: SIMD4<Double>) { j.walked(nrm(p), 0.01, footOn: false) { said.append($0) } }
            let mid = SIMD4<Double>(0.5, 0.5, 0.5, 0.5)
            func pass(_ q: SIMD4<Double>) { let s = nrm(mid - q * simd_dot(mid, q)); for t in [-0.5, -0.06, 0.0, 0.06, 0.5] { go(q * cos(t) + s * sin(t)) } }
            go(mid); for m in FIXED { pass(m.c); go(mid) }
            check(j.lap == 2 && j.polesHit.isEmpty && said.contains { $0.contains("8 つの極を全部通った") },
                  "目印がない時は 8 つの極を全部通ると 2 周目に（極のチェックをリセット。\(j.lap) 周目・残り \(j.polesHit.count)）")
        }
        do {                                                             // そばに入っただけでは数えず、いちばん近い所を過ぎて数える
            var j = Journey(); let m = nrm(SIMD4<Double>(1, 0, 0, 0.2)); j.marks = [m, nrm(SIMD4<Double>(0, 1, 0, 0.2))]
            let s = nrm(SIMD4<Double>(0, 0, 1, 0)); var said: [String] = []
            func go(_ t: Double) { j.walked(m * cos(t) + s * sin(t), 0.01, footOn: false) { said.append($0) } }
            go(-0.5); go(-0.1); go(-0.05); let early = j.marksHit.count; go(0.0); go(0.05); let after = j.marksHit.count
            check(early == 0 && after == 1, "チェックは、そばに入っただけでは付かず（\(early)）、目印のすぐ横を通り過ぎた所で付く（\(after)）")
        }
        print("== 4D 球アナロジーの音（画面なしで作って大きさを測る）==")
        do {
            let s = HyperSound.shared
            let still = s.renderTest(seconds: 1, speed: 0, zoom: 0), slow = s.renderTest(seconds: 1, speed: 0.3, zoom: 0)
            let fast = s.renderTest(seconds: 1, speed: 1, zoom: 0), dive = s.renderTest(seconds: 1, speed: 1, zoom: 1)
            let bell = s.renderTest(seconds: 1, speed: 0, zoom: 1, chimeAt: 0.2), bellFar = s.renderTest(seconds: 1, speed: 0, zoom: 0, chimeAt: 0.2)
            let turn = s.renderTest(seconds: 1, speed: 1, zoom: 1, turn: 1)
            let spR = s.renderTest(seconds: 1, speed: 1, zoom: 1, at: SIMD3(1.5, 0, 0)), spL = s.renderTest(seconds: 1, speed: 1, zoom: 1, at: SIMD3(-1.5, 0, 0))
            check(spR.rmsR > spR.rms * 1.15 && spL.rms > spL.rmsR * 1.15 && spR.peak < 1,   // 低い音が多いので、左右の差は 2 割ほど（低い音ほど耳の差が小さい）
                  String(format: "空間オーディオ：右から鳴らすと右の耳 %.3f > 左 %.3f、左から鳴らすと左 %.3f > 右 %.3f（割れない）", spR.rmsR, spR.rms, spL.rms, spL.rmsR))
            if let dir = ProcessInfo.processInfo.environment["S3_SNDWAV"] {     // 聞いて確かめる用：風切り音を wav に
                for (n, sp, z, tr) in [("1_遅い", 0.4, 0.0, 0.0), ("2_速い", 1.0, 0.0, 0.0), ("3_ズーム", 1.0, 1.0, 0.0), ("4_ズーム右へ曲がる", 1.0, 1.0, 1.0), ("5_ズーム中くらい", 0.6, 1.0, 0.0)] {
                    _ = s.renderTest(seconds: 4, speed: sp, zoom: z, turn: tr, wav: dir + "/風切り_\(n).caf")
                }
            }
            check(still.rms < 1e-4 && slow.rms > still.rms && fast.rms > slow.rms && dive.rms > fast.rms * 1.5 && dive.peak < 0.95 && turn.rms > dive.rms && turn.rms < dive.rms * 2.6 && turn.peak < 0.95 && bell.rms > 0.01 && fast.rms < dive.rms * 0.08 && bellFar.rms > bell.rms * 0.8,
                  String(format: "風切り音：止まると無音（%.4f）、遅い %.4f < 外から全速 %.4f（かすか）< ズームで寄る %.3f < 曲がる %.3f（いちばん大きい値 %.2f、割れない）。チリン 寄って %.3f・外からも %.3f（いつも聞こえる）",
                         still.rms, slow.rms, fast.rms, dive.rms, turn.rms, max(dive.peak, turn.peak), bell.rms, bellFar.rms))
        }
        do {                                                             // ズーム中に回した分は、離すとゆーっくり戻る
            let st = HyperLabState(); st.diveYawOff = 1.0; st.tickDive(0)
            var at: [Double] = []
            for i in 1...480 { st.tickDive(1.0 / 60); if i == 30 || i == 120 || i == 240 || i == 480 { at.append(st.diveYawOff) } }
            check(at[0] > 0.85 && at[1] > 0.2 && at[1] < 0.75 && at[2] < 0.25 && abs(at[3]) < 0.03 && at.allSatisfy { $0 > -0.02 },
                  String(format: "ズーム中に回した 1.0 は、離すと 0.5 秒で %.2f（静かに動き出す）・2 秒で %.2f・4 秒で %.2f・8 秒で %.3f（行き過ぎない）", at[0], at[1], at[2], at[3]))
        }
        do {                                                             // オートカメラのダイナミック：きついカーブで真上近くへ展開し、まっすぐに戻るとゆっくり戻る
            let st = HyperLabState(); st.autoCam = true; st.diveThird = true; st.diveT = 1; st.diveManual = true
            if let r = HyperLabRenderer(side: .right, state: st, view: nil) {
            var c = Camera(); c.az = 0; var turn = true
            r.walkOverride = {
                let F = c.viewFrame()
                return .init(trail: [c.w.p], pos: c.w.p, head: c.lookFrame().L, space: false, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70)
            }
            func run(_ sec: Double) { for _ in 0..<Int(sec * 60) { if turn { c.az += 90.0 / 60 }; c.walk([0, 0, 1], 0.01); r.autoCamForTest(1.0 / 60) } }
            run(0.2); let p0 = st.autoPitch
            run(2.0); let p1 = st.autoPitch, d1 = st.autoDyn
            turn = false; run(4.0); let p2 = st.autoPitch
            check(d1 > 0.8 && p1 > p0 + 0.6 && p2 < p1 * 0.5,
                  String(format: "オートカメラ：きついカーブ（1 秒に 90°）で見下ろしが %.2f → %.2f rad（ダイナミック %.2f）、まっすぐに戻ると 4 秒で %.2f へ", p0, p1, d1, p2))
            }
            if let r = HyperLabRenderer(side: .right, state: st, view: nil) {    // スター・ウォーズの追いかけ：曲がると彗星が先に流れ、カメラの傾きはあとから
                var c = Camera(); c.az = 0; var turn = false
                r.walkOverride = { let F = c.viewFrame(); return .init(trail: [c.w.p], pos: c.w.p, head: c.lookFrame().L, space: false, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70) }
                var o = (SIMD3<Double>(), 0.0, 0.0)
                func run(_ sec: Double) { for _ in 0..<Int(sec * 60) { if turn { c.az += 90.0 / 60 }; c.walk([0, 0, 1], 0.01); o = r.chaseForTest(1.0 / 60) } }
                run(1); let s0 = simd_length(o.0), h0 = o.2
                turn = true; run(0.3); let l1 = simd_length(o.0), b1 = abs(o.1), h1 = o.2
                run(2.0); let l2 = simd_length(o.0), b2 = abs(o.1)
                turn = false; run(2.5); let l3 = simd_length(o.0), b3 = abs(o.1), h3 = o.2
                check(s0 < 1e-6 && l1 > 0.12 && b1 < b2 * 0.45 && b2 > 0.25 && l3 < 0.02 && b3 < b2 * 0.2 && h0 < 1e-6 && h1 > 0.5 && h3 < 0.02,
                      String(format: "追いかけ：まっすぐは真ん中（%.3f）。曲がると 0.3 秒で彗星が先へ %.2f 流れ（傾きはまだ %.2f rad）、2 秒で傾き %.2f rad、まっすぐに戻ると %.3f・%.3f へ。頭のゆがみ まっすぐ %.3f → 曲がって %.2f → 戻って %.3f", s0, l1, b1, b2, l3, b3, h0, h1, h3))
            }
        }
        print("== 地図の写し方（ウェブ版の mapS3 と）==")
        turnChecks(r); mapChecks(r)
        print("== ウェブ版との比べ（refs/ の画素）==")
        webcmp(r)
        print(ok ? "\nすべて合格" : "\n合わないものがある")
        return ok
    }

    // ---- 計算 ----
    static func randomWalker(_ g: inout SystemRandomNumberGenerator) -> Walker {
        func rv() -> V4 { V4(Double.random(in: -1...1, using: &g), Double.random(in: -1...1, using: &g), Double.random(in: -1...1, using: &g), Double.random(in: -1...1, using: &g)) }
        var w = Walker(p: nrm(rv()), r: rv(), u: rv(), f: rv()); orthoFrame(&w); return w
    }
    static func frameErr(_ w: Walker) -> Double {
        let vs = [w.p, w.r, w.u, w.f]; var e = 0.0
        for i in 0..<4 { for j in 0..<4 { e = max(e, abs(dot4(vs[i], vs[j]) - (i == j ? 1 : 0))) } }
        return e
    }
    static func cpuChecks() {
        var g = SystemRandomNumberGenerator()
        // 1. でたらめに 10 万歩（向きもでたらめ）歩いても、体の枠は正規直交のまま
        var cam = Camera(); cam.w = randomWalker(&g); var worst = 0.0
        for _ in 0..<100_000 {
            cam.az = Double.random(in: -180...180, using: &g); cam.el = Double.random(in: -89...89, using: &g)
            cam.walk([0, 0, 1], Double.random(in: 0...0.05, using: &g)); worst = max(worst, frameErr(cam.w))
        }
        check(worst < 1e-12, String(format: "10 万歩でたらめに歩いた後も、体の枠は正規直交（ずれ最大 %.1e）", worst))
        // 2. 大円を 2π 歩くと、点も体の枠も元に戻る（S³ の大円に沿った平行移動は 1 周で元どおり）
        var back = 0.0, along = 0.0
        for _ in 0..<50 {
            let w0 = randomWalker(&g); var w = w0
            let a = Double.random(in: 0...1, using: &g), b = Double.random(in: 0...1, using: &g), c = Double.random(in: 0...1, using: &g)
            let d = nrm(w0.r * (a - 0.5) + w0.u * (b - 0.5) + w0.f * (c - 0.5))
            let n = 1000
            for k in 1...n {
                moveAlong(&w, w.f * dot4(d, w0.f) + w.r * dot4(d, w0.r) + w.u * dot4(d, w0.u), 2 * Double.pi / Double(n))
                // 途中の点は、大円の式 cos s·p₀ + sin s·d と同じ
                if k == 333 { along = max(along, simd_length(w.p - geo(w0.p, d, 2 * Double.pi * 333 / Double(n)))) }
            }
            back = max(back, simd_length(w.p - w0.p), simd_length(w.r - w0.r), simd_length(w.u - w0.u), simd_length(w.f - w0.f))
        }
        check(along < 1e-9, String(format: "1000 歩に分けて歩いた点は、大円の式どおり（ずれ最大 %.1e）", along))
        check(back < 1e-9, String(format: "大円を 2π 歩くと、点も右・上・前も元に戻る（ずれ最大 %.1e）", back))
    }

    // ---- ターンの道：ウェブ版の fillStep・fqStep を node で動かした点（refs/turn_*.json、refs/turn_ref.js で作る。4000 コマ・ds 0.005・40 コマおき）と比べる ----
    static func turnChecks(_ r: Renderer) {
        // 予定の道：先の道を作っても、今の状態は変わらない（言葉も出ない）。そのあと実際に歩いた道は、予定の道に重なる
        do {
            let rt = CustomRoute(name: "確かめ", pts: [0, 2, 6].map { RoutePoint(p: RouteStore.poles[$0].1, name: RouteStore.poles[$0].0) })
            for (label, start) in [("自分の道（3 点の巡回）", { r.set = .plain; r.resetNorth(); r.startCustom(rt) }), ("螺旋", { r.set = .plain; r.startPath(.spiral) }), ("極めぐり", { r.set = .plain; r.startPath(.tour) })] as [(String, () -> Void)] {
                start()
                func adv(_ h: Double) { if r.pathMode == .custom { r.crStep(h) } else if r.pathMode.isTurn { r.turnStep(h) } else { r.pathStep(h) } }
                for _ in 0..<40 { adv(0.02) }
                let saySaved = r.say; var said = 0; r.say = { _ in said += 1 }
                let p0 = r.cam.w.p, n0 = r.journey.trail.count, m0 = r.pathMode
                r.planCache = (-1, []); let plan = r.plannedPath(ahead: 2.0)
                let same = simd_distance(r.cam.w.p, p0) < 1e-12 && r.journey.trail.count == n0 && r.pathMode == m0 && said == 0
                var worst = 0.0
                for _ in 0..<90 { adv(0.02); let q = r.cam.w.p; worst = max(worst, plan.map { simd_distance($0, q) }.min() ?? 9) }
                r.say = saySaved
                check(same && plan.count > 50 && worst < 0.03,
                      String(format: "予定の道・%@：作っても今の所・跡・道は変わらず言葉も出ない、点 %d 個、そのあと 1.8 歩いた所は予定の道から最大 %.4f", label, plan.count, worst))
            }
            r.pathMode = .none
        }
        // ランダムな点の道：点は長さ 1 で S³ に一様（平均はほぼ 0、各成分の 2 乗の平均はほぼ 1/4）。8 点の巡回で、全部の点のそばを通る
        do {
            let qs = (0..<20000).map { _ in RouteStore.randomPoint() }
            let unit = qs.allSatisfy { abs($0.map { $0 * $0 }.reduce(0, +) - 1) < 1e-9 }
            var mean = [Double](repeating: 0, count: 4), sq = [Double](repeating: 0, count: 4)
            for q in qs { for a in 0..<4 { mean[a] += q[a]; sq[a] += q[a] * q[a] } }
            for a in 0..<4 { mean[a] /= Double(qs.count); sq[a] /= Double(qs.count) }
            let pts = (0..<8).map { _ in RouteStore.randomPoint() }
            let rt = CustomRoute(name: "確かめ", pts: pts.enumerated().map { RoutePoint(p: $1, name: "ランダム \(RouteStore.nums[$0])") })
            r.set = .plain; r.set.routeFlow = true; r.resetNorth(); r.startCustom(rt)   // 素通り：全部の点をちょうど通る（目印のチェックが付く）
            var best = [Double](repeating: 9, count: pts.count)
            let pv = pts.map { V4($0[0], $0[1], $0[2], $0[3]) }
            for _ in 0..<12000 where r.pathMode == .custom {
                r.crStep(0.01)
                for k in pv.indices { let c = max(-1.0, min(1.0, dot4(r.cam.w.p, pv[k]))); best[k] = min(best[k], acos(c)) }
            }
            r.pathMode = .none
            let mMax = mean.map { abs($0) }.max() ?? 9, sMin = sq.min() ?? 0, sMax = sq.max() ?? 9, far = best.max() ?? 9
            let okR = unit && mMax < 0.02 && abs(sMin - 0.25) < 0.01 && abs(sMax - 0.25) < 0.01 && far < 0.02
            // 道の点のチェックポイント：素通りで歩くと、全部の点にチェックが付いて（光とチリンの記録 hitPulse も）、全部通ると 1 周。道をやめるとおしまい
            do {
                r.set = .plain; r.set.routeFlow = true; r.resetNorth(); r.journey = Journey(); Journey.hitPulse = []
                r.startCustom(rt)
                let n0 = r.journey.routePts.count
                var maxHit = 0, pulses = 0, said: [String] = []
                let sv = r.say; r.say = { said.append($0) }
                for _ in 0..<12000 where r.pathMode == .custom && r.journey.lap < 2 {
                    r.crStep(0.01); maxHit = max(maxHit, r.journey.routeHit.count)
                    pulses = max(pulses, Journey.hitPulse.filter { $0.pole == -1 }.count)
                }
                let lapped = r.journey.lap >= 2
                r.pathMode = .none
                let cleared = r.journey.routePts.isEmpty
                r.say = sv
                let okC = n0 == pts.count && lapped && maxHit == pts.count - 1 && pulses >= 1 && cleared && said.contains { $0.contains("周目へ") }
                check(okC, "道の点のチェックポイント：\(n0) 点。素通りで歩くと 1 つずつチェックが付き（光の記録あり）、全部通って 2 周目へ。道をやめるとチェックポイントもおしまい")
            }
            // 出発の速さ：決まった道・自分の道を歩き始めると、その速さから。設定を書き出して読み戻しても同じ
            do {
                r.set = .plain; r.set.routeStart = 3.5; r.resetNorth(); r.startPath(.spiral); let s1 = r.pathSpeed
                r.startCustom(rt); let s2 = r.pathSpeed; r.pathMode = .none
                var st2 = Settings(); st2.load(["routeStart": 3.5]); let s3 = st2.routeStart
                r.set = .plain
                check(abs(s1 - 3.5) < 1e-9 && abs(s2 - 3.5) < 1e-9 && abs(s3 - 3.5) < 1e-9, String(format: "出発の速さ ×3.5：螺旋も自分の道も ×%.1f・×%.1f から歩き出す。設定から読み戻して ×%.1f", s1, s2, s3))
            }
            check(okR, String(format: "ランダムな点：長さ 1・一様（平均 最大 %.3f、2 乗の平均 %.3f〜%.3f）、8 点を素通りで巡回すると全部の点を通る（いちばん遠い点まで %.3f）", mMax, sMin, sMax, far))
        }
        // 自分の道：1 点は行って止まる、2 点は往復、3 点以上は巡回（どの点のそばも通る・ほかの極には寄らない）
        do {
            func route(_ ks: [Int]) -> CustomRoute { CustomRoute(name: "確かめ", pts: ks.map { RoutePoint(p: RouteStore.poles[$0].1, name: RouteStore.poles[$0].0) }) }
            func near(_ p: V4, _ k: Int) -> Bool { let q = RouteStore.poles[k].1; return acos(max(-1, min(1, dot4(p, V4(q[0], q[1], q[2], q[3]))))) < 0.12 }
            r.set = .plain; r.set.routeSmart = false; r.resetNorth(); r.startCustom(route([2]))                         // 東極へ
            var steps = 0; while r.pathMode == .custom && steps < 2000 { r.crStep(0.01); steps += 1 }
            check(r.pathMode == .none && near(r.cam.w.p, 2), "自分の道・1 点：アナ極から東極へ行って止まる（\(steps) 歩、π/2 ＝ 157 歩ほど）")
            for (ks, label) in [([2, 4], "2 点（東極 ⇄ 北極の往復）"), ([0, 2, 6], "3 点（アナ極 → 東極 → 天極 → アナ極）"), ([2, 3, 6, 1], "4 点（東極 → 西極（反対側）→ 天極 → カタ極）")] {
                r.set = .plain; r.set.routeSmart = false; r.resetNorth(); r.startCustom(route(ks))
                var visits: [Int] = [], strayOK = true, maxStep = 0.0, prev = r.cam.w.p
                for _ in 0..<6000 {
                    r.crStep(0.01); let p = r.cam.w.p
                    maxStep = max(maxStep, acos(max(-1, min(1, dot4(p, prev))))); prev = p
                    if let k = ks.first(where: { near(p, $0) }), visits.last != k { visits.append(k) }
                    if (0..<8).contains(where: { !ks.contains($0) && $0 != 0 && near(p, $0) }) { strayOK = false }
                }
                r.pathMode = .none
                // 決まった順に巡っているか（はじめのアナ極は出発点なので数えない）
                let seq = visits.filter { ks.contains($0) }, n = ks.count
                let ordered = seq.count >= n * 2 && zip(seq, seq.dropFirst()).allSatisfy { a, b in ks.firstIndex(of: b) == (ks.firstIndex(of: a)! + 1) % n }
                check(ordered && strayOK && maxStep < 0.05, "自分の道・\(label)：決まった順に何周も、ほかの極には寄らない、とびなし（通った順 \(seq.prefix(8).map { RouteStore.poles[$0].0 }.joined(separator: "→"))…）")
            }
            // おまかせ：天 ⇄ 地はまっすぐ 1 本の大円を回り続ける・東 ⇄ 北は引き返さずにループ（西・南も通る）・引き返す所も止まらずに電球の形で回る
            do {
                r.set = .plain; r.set.routeSmart = true; r.resetNorth(); r.startCustom(route([6, 7]))
                var plane: (V4, V4)? = nil, off = 0.0, seen: [Int] = []
                for _ in 0..<4000 {
                    r.crStep(0.01); let p = r.cam.w.p
                    if let k = [6, 7].first(where: { near(p, $0) }), seen.last != k { seen.append(k) }
                    if plane == nil && seen.count >= 2 { plane = (p, r.cam.w.f) }   // 天に着いて地へ向かい始めた後
                    if let (a, b) = plane { let q = a * dot4(p, a) + b * dot4(p, b); off = max(off, simd_length(p - q)) }
                }
                r.pathMode = .none
                check(seen.count >= 5 && off < 1e-3, "自分の道・おまかせ・天極 ⇄ 地極：まっすぐ 1 本の大円をぐるっと回り続ける（大円からのずれ \(String(format: "%.1e", off))、通った順 \(seen.prefix(6).map { RouteStore.poles[$0].0 }.joined(separator: "→"))…）")
            }
            do {
                r.set = .plain; r.set.routeSmart = true; r.resetNorth(); r.startCustom(route([2, 4]))
                var seen: [Int] = [], still = 0, prev = r.cam.w.p
                for _ in 0..<5000 {
                    r.crStep(0.01); let p = r.cam.w.p
                    if dot4(p, prev) > cos(1e-7) { still += 1 }; prev = p
                    if let k = [2, 3, 4, 5].first(where: { near(p, $0) }), seen.last != k { seen.append(k) }
                }
                r.pathMode = .none
                let loop = seen.drop(while: { $0 != 2 }).prefix(8).elementsEqual([2, 4, 3, 5, 2, 4, 3, 5])
                check(loop && still == 0, "自分の道・おまかせ・東極 ⇄ 北極：引き返さずに、東→北→西→南とループ（止まる歩 \(still)、通った順 \(seen.prefix(8).map { RouteStore.poles[$0].0 }.joined(separator: "→"))…）")
            }
            do {
                let back = nrm(V4(1, 0.3, 0, 0))
                r.set = .plain; r.set.routeSmart = true; r.set.turnSharp = false; r.resetNorth()
                r.startCustom(CustomRoute(name: "確かめ", pts: [RoutePoint(p: [1, 0, 0, 0], name: "東極"), RoutePoint(p: [0, 1, 0, 0], name: "北極"), RoutePoint(p: [back.x, back.y, back.z, back.w], name: "東の近く")]))
                var still = 0, prev = r.cam.w.p, prevF = r.cam.w.f, maxTurn = 0.0, nearBack = 0, nearN = 0, prevNearN = false
                for i in 0..<5000 {
                    r.crStep(0.01); let p = r.cam.w.p, f = r.cam.w.f
                    if dot4(p, prev) > cos(1e-7) { still += 1 }
                    let ft = nrm(prevF - p * dot4(prevF, p)); if i > 0 { maxTurn = max(maxTurn, acos(max(-1, min(1, dot4(ft, f))))) }
                    prev = p; prevF = f
                    if acos(max(-1, min(1, dot4(p, back)))) < 0.01 { nearBack += 1 }
                    let n = near(p, 4); if n && !prevNearN { nearN += 1 }; prevNearN = n
                }
                r.pathMode = .none
                check(still == 0 && maxTurn < 0.12 && nearBack > 0 && nearN >= 2, String(format: "自分の道・おまかせ・スムーズ：北極で引き返す所を、止まらずにぐるっと電球の形で回る（止まる歩 %d、1 歩の向きの変わり 最大 %.3f）", still, maxTurn))
            }
            // パネルで光らせる「今向かっている点」：続けて同じ点（③＝②）があっても、道の番号どおり ②→④→①→… と変わる（① のアナ極から出る）
            do {
                var rt = route([0, 2, 2, 6]); rt.name = "確かめ"
                r.set = .plain; r.set.routeSmart = true; r.resetNorth(); r.startCustom(rt)
                var seq: [Int] = []
                for _ in 0..<3000 { r.crStep(0.01); let h = r.cr.src[r.cr.heading]; if seq.last != h { seq.append(h) } }
                r.pathMode = .none
                check(r.cr.routeID == rt.id && Array(seq.prefix(7)) == [1, 3, 0, 1, 3, 0, 1], "自分の道：パネルで光らせる「今向かっている点」が、道の番号どおりに変わる（① のアナ極から出るので ② から、\(seq.prefix(7).map { RouteStore.nums[$0] }.joined(separator: "→"))…、続けて同じ ③ は飛ばす）")
            }
            // 素通り：全部の点をちょうど通り、止まらず、曲がりは滑らか（きつい角も手前からならす）。天 ⇄ 地は 1 本の大円
            let flowCases: [(String, [[Double]])] = [("3 点（アナ・東・天、どこも 90°）", [RouteStore.poles[0].1, RouteStore.poles[2].1, RouteStore.poles[6].1]),
                                 ("3 点（東・北・東の近く、北で引き返す）", [[1, 0, 0, 0], [0, 1, 0, 0], [1 / 1.044, 0.3 / 1.044, 0, 0]]),
                                 ("5 点（アナ・東・天・(½,½,½,½)・西）", [RouteStore.poles[0].1, RouteStore.poles[2].1, RouteStore.poles[6].1, [0.5, 0.5, 0.5, 0.5], RouteStore.poles[3].1])]
            for (label, pts) in flowCases {
                r.set = .plain; r.set.routeFlow = true; r.resetNorth(); r.cam.az = 40
                r.startCustom(CustomRoute(name: "確かめ", pts: pts.enumerated().map { RoutePoint(p: $0.element, name: "点\($0.offset + 1)") }))
                let V = pts.map { nrm(V4($0[0], $0[1], $0[2], $0[3])) }
                var best = Array(repeating: 9.0, count: V.count), still = 0, prev = r.cam.w.p, prevF = r.cam.w.f, maxTurn = 0.0, order: [Int] = []
                for i in 0..<4000 {
                    r.crStep(0.01); let p = r.cam.w.p, f = r.cam.w.f
                    if dot4(p, prev) > cos(1e-7) { still += 1 }
                    if i > 0 { let ft = nrm(prevF - p * dot4(prevF, p)); maxTurn = max(maxTurn, acos(max(-1, min(1, dot4(ft, f))))) }
                    prev = p; prevF = f
                    for (k, v) in V.enumerated() { let d = acos(max(-1, min(1, dot4(p, v)))); best[k] = min(best[k], d); if d < 0.01, order.last != k { order.append(k) } }
                }
                r.pathMode = .none
                let n = V.count, cyc = order.count >= n * 2 && zip(order, order.dropFirst()).allSatisfy { ($0 + 1) % n == $1 }
                // とがり（1 歩で大きく向きが変わる所）がないこと。引き返す点のある道は、短い間で 180° 回るので少しきつめまで
                check(still == 0 && best.allSatisfy { $0 < 0.006 } && cyc && maxTurn < (label.contains("引き返す") ? 0.3 : 0.08),
                      String(format: "自分の道・素通り・%@：全部の点を通る（いちばん近い所 最大 %.4f）・順に巡回・止まらない・1 歩（0.01）の向きの変わり 最大 %.3f（%.1f°）", label, best.max()!, maxTurn, maxTurn / d2r))
            }
            do {
                r.set = .plain; r.set.routeFlow = true; r.resetNorth(); r.startCustom(route([6, 7]))
                var off = 0.0, plane: (V4, V4)? = nil, seen: [Int] = [], onLoop = 0
                for _ in 0..<3000 {
                    r.crStep(0.01); let p = r.cam.w.p
                    if let k = [6, 7].first(where: { near(p, $0) }), seen.last != k { seen.append(k) }
                    if r.cr.flowIn == nil { onLoop += 1 }
                    if plane == nil && onLoop == 10 { plane = (p, r.cam.w.f) }       // 入りの曲線から大円に乗って少し進んでから、大円の面を決める
                    if let (a, b) = plane { off = max(off, simd_length(p - (a * dot4(p, a) + b * dot4(p, b)))) }
                }
                r.pathMode = .none
                check(seen.count >= 4 && off < 1e-3, "自分の道・素通り・天極 ⇄ 地極：1 本の大円をぐるっと（ずれ \(String(format: "%.1e", off))）")
            }
            // 同期（Supabase）：書き出した状態を当て直すと元どおり・ほかの種類の端末の画面の構成は分けて残す・今いる所も戻る
            do {
                r.set = .plain; r.resetNorth(); r.cam.walk([0, 0, 1], 0.7); r.cam.az = 33
                let core0 = NativeSync.json(NativeSync.commonCore(r)), pos0 = NativeSync.position(r)
                var d = NativeSync.commonCore(r); d["pos"] = pos0
                r.set.fov = 61; r.set.space.toggle(); r.set.shellN = 5; r.resetNorth()            // 変えてから
                NativeSync.applyCommon(r, d, true)                                                 // 当て直す
                let back = NativeSync.json(NativeSync.commonCore(r)) == core0
                let posBack = simd_length(r.cam.w.p - V4((pos0["p"] as! [Double])[0], (pos0["p"] as! [Double])[1], (pos0["p"] as! [Double])[2], (pos0["p"] as! [Double])[3])) < 1e-9
                let (own, fo) = NativeSync.split(["set": [:], "ui_mac": ["a": 1], "ui_ios": ["b": 2], "pos": [:]] as [String: Any])
                let other = NativeSync.platform == "mac" ? "ui_ios" : "ui_mac"
                let splitOK = own.keys.sorted() == ["set", "ui_" + NativeSync.platform].sorted() && fo.keys.sorted() == [other]
                let noScale = (NativeSync.commonCore(r)["set"] as? [String: Any])?["scale"] == nil
                check(back && posBack && splitOK && noScale, "同期：書き出した状態を当て直すと元どおり（設定・道・キー）・今いる所も戻る・ほかの種類の端末の画面の構成は分けて残す・描く細かさはそろえない")
            }
            // 座標の入れ方（ウェブ版と同じ）
            var c = CoordInput(); c.fix(); c.set(3, 0.5)
            let share = c.v[0...2].allSatisfy { abs($0 - 0.5) < 1e-9 }
            c.set(0, 0.8); c.set(1, 0.8)                                                    // 0.8 と 0.8 は入りきらない：新しい y はそのまま、前の x が残りの幅に縮む
            let pri = abs(c.v[1] - 0.8) < 1e-9 && abs(c.v[0] - 0.6) < 1e-9 && abs(c.v.map { $0 * $0 }.reduce(0, +) - 1) < 1e-9
            let parsed = ["1", "5", "34", "-5", "０．３", "0.25", "2", "35", "-999", "-1", "１２３４"].map { CoordInput.parse($0) ?? .nan }
            let literal = ["2", "35", "-999", "0.5"].map { CoordInput.parse($0, simple: false) ?? .nan }
            check(share && pri && parsed == [1, 0.5, 0.34, -0.5, 0.3, 0.25, 0.2, 0.35, -0.999, -1, 0.1234] && literal == [2, 35, -999, 0.5] && CustomRoutePanel.num(-0.999) == "-0.999" && CustomRoutePanel.num(0.5) == "0.5",
                  "座標の入れ方：w ＝ 0.5 なら残りを 0.5 ずつ分け合う・最後に入れた数を優先・簡易入力（n 桁 → 1/10ⁿ）2 → 0.2、35 → 0.35、-999 → −0.999、1・−1 はそのまま、全角も（\(parsed)）・簡易入力オフは書いたとおり（\(literal)）・欄の表示 −0.999")
        }
        // 超立方体・二十四胞体の辺めぐり：となりどうし（60°）だけを進み、全部の辺を 1 回ずつ通って、最初の頂点へ戻る
        for (name, V, T, E) in [("超立方体", TurnGeo.cubeVerts, TurnGeo.cubeTour, 32), ("二十四胞体", TurnGeo.cell24Verts, TurnGeo.cell24Tour, 96)] {
            var edges = Set<String>(), adjOK = true
            for i in 0..<T.count {
                let a = T[i], b = T[(i + 1) % T.count], d = zip(a, b).map(*).reduce(0, +)
                if abs(d - 0.5) > 1e-9 { adjOK = false }
                let ia = V.firstIndex(of: a)!, ib = V.firstIndex(of: b)!; edges.insert("\(min(ia, ib))-\(max(ia, ib))")
            }
            check(adjOK && T.count == E && edges.count == E && V.count == (E == 32 ? 16 : 24), "\(name)の辺めぐり：\(V.count) 頂点・\(T.count) 本の辺を、となりどうし（60°）だけで、どれも 1 回ずつ（ちがう辺 \(edges.count) 本）")
            // 歩いて 1 周したら、全部の頂点のそば（0.15 以内）を通る
            r.set = .plain; r.startPath(E == 32 ? .cube : .cell24)
            var near = Array(repeating: false, count: V.count)
            for _ in 0..<Int(Double(E) * Double.pi / 3 / 0.01 * 1.05) {
                r.turnStep(0.01); let p = r.cam.w.p
                for (k, v) in V.enumerated() where !near[k] { let d: Double = dot4(p, V4(v[0], v[1], v[2], v[3])); if acos(max(-1, min(1, d))) < 0.15 { near[k] = true } }
            }
            r.pathMode = .none
            check(near.allSatisfy { $0 }, "\(name)の辺めぐりを 1 周歩くと、全部の頂点のそば（0.15 以内）を通る（\(near.filter { $0 }.count)／\(V.count)）")
        }
        for (mode, st) in [("tour", "smooth"), ("tour", "sharp"), ("half", "smooth"), ("half", "sharp")] {
            guard let d = try? Data(contentsOf: refsDir().appendingPathComponent("turn_\(mode)_\(st).json")), let web = try? JSONSerialization.jsonObject(with: d) as? [[Double]] else { print("  ？ turn_\(mode)_\(st).json が無い"); continue }
            r.set = .plain; r.set.turnSharp = st == "sharp"; r.startPath(mode == "half" ? .half : .tour)
            var worst = 0.0, k = 0
            for i in 1...4000 {
                r.turnStep(0.005)
                if i % 40 == 0, k < web.count {
                    let p = r.cam.w.p, q = r.journey.w2.p, f = r.cam.w.f, m = [p.x, p.y, p.z, p.w, q.x, q.y, q.z, f.x, f.y, f.z, f.w]
                    worst = max(worst, zip(m, web[k]).map { abs($0 - $1) }.max()!); k += 1
                }
            }
            r.pathMode = .none
            check(k == web.count && worst < 1e-9, String(format: "%@（%@）：ウェブ版と同じ道（20 進む間、S³・S² の点と体の前のずれ最大 %.1e）", mode == "half" ? "半周 180° のターン" : "極めぐり", st == "sharp" ? "直角" : "スムーズ", worst))
        }
        r.set = .plain; r.resetNorth()
        // 網目の傾き・自転：ウェブ版の gridM（傾き 40°・向き 30°・自転 0.5）と同じ行列
        do {
            r.set.gridTilt = 40; r.set.gridAz = 30; r.gridSpinAng = 0.5
            let web: [[Double]] = [[0.3424877429258024, -0.7568488703636205, 0.5566703992264194], [0.7513283181113952, 0.5763781576467558, 0.32139380484326957], [-0.564099197260102, 0.3081687959820773, 0.766044443118978]]
            let M = r.gridM(), dev = (0..<3).flatMap { i in (0..<3).map { j in abs(M[i][j] - web[i][j]) } }.max()!
            r.set = .plain; r.gridSpinAng = 0
            check(dev < 1e-12, String(format: "網目の傾き・自転：ウェブ版の gridM と同じ（ずれ %.1e）", dev))
        }
        // 地図の軸の長さを % で決める：x 50% → X-W 60°、w 30% → 3 つの傾きを同じ割合で
        let m = MapRenderer(world: r)
        r.set.mapXW = 0; r.set.mapYW = 0; r.set.mapZW = 0
        let okX = m.setAxisLength(0, 0.5), lx = m.axisLengths()[0], ax = r.set.mapXW
        r.set.mapYW = 20; r.set.mapZW = -10
        let okW = m.setAxisLength(3, 0.3), lw = m.axisLengths()[3]
        r.set.mapXW = 90; r.set.mapYW = 90; r.set.mapZW = 90
        let sw1 = m.swapTilt(), t1 = [r.set.mapXW, r.set.mapYW, r.set.mapZW], sw2 = m.swapTilt(), t2 = [r.set.mapXW, r.set.mapYW, r.set.mapZW]
        check(sw1 && sw2 && t1 == [0, 90, 0] && t2 == [90, 90, 90], "地図の傾きの ⇄：もう一つの組（初めは 0°・90°・0°）と入れかえ、もう一度で戻る")
        r.set.mapFollow = true; let noF = !m.setAxisLength(0, 0.5); r.set = .plain
        check(okX && abs(lx - 0.5) < 2e-4 && abs(ax - 60) < 0.02 && okW && abs(lw - 0.3) < 2e-3 && noF,
              String(format: "地図の軸の長さを %% で：x 50%% → X-W %.2f°（長さ %.2f%%）、w 30%% → %.2f%%、自分中心では決めない", ax, lx * 100, lw * 100))
    }

    // ---- 地図：ウェブ版の mapS3 で写した点（refs/web_map.txt、3 つの写し方 × 8 点、x y z と奥行き w'）と比べる ----
    static func mapChecks(_ r: Renderer) {
        guard let txt = try? String(contentsOf: refsDir().appendingPathComponent("web_map.txt"), encoding: .utf8) else { print("  ？ web_map.txt が無い"); return }
        let web = txt.split(separator: "\n").map { $0.split(separator: " ").map { Double($0)! } }
        let pts: [V4] = [[0, 0, 0, 1], [0, 0, 0, -1], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0.5, 0.5, 0.5, 0.5], [0.1, -0.7, 0.3, 0.6403124], [-0.48, 0.6, -0.64, 0]].map { nrm($0) }
        let cases: [(Double, Double, Double, Double)] = [(0, 90, 0, 2.5), (20, 70, -35, 2.5), (-120, 15, 60, 4)]
        let m = MapRenderer(world: r); var worst = 0.0, k = 0
        for (xw, yw, zw, D) in cases {
            r.set = .plain; r.set.mapXW = xw; r.set.mapYW = yw; r.set.mapZW = zw; r.set.mapD = D
            let R = m.rot4()
            for p in pts {
                let (a, d) = m.map(p, R)!; let w = web[k]; k += 1
                worst = max(worst, abs(Double(a.x) - w[0]), abs(Double(a.y) - w[1]), abs(Double(a.z) - w[2]), abs(d - w[3]))
            }
        }
        check(worst < 1e-5, String(format: "地図の写し方（4 次元の回転 3 通り × 8 点）がウェブ版と同じ（ずれ最大 %.1e）", worst))
        let c = Cell120.shared
        let onS3 = c.edges.allSatisfy { abs(simd_length($0.0) - 1) < 1e-9 && abs(simd_length($0.1) - 1) < 1e-9 }
        let elen = c.edges.map { acos(max(-1, min(1, dot4($0.0, $0.1)))) }
        var vs = Set<String>(); for (A, B) in c.edges { for P in [A, B] { vs.insert((0..<4).map { String(Int((P[$0] * 1e4).rounded())) }.joined(separator: ",")) } }
        let want = 2 * asin(1 / (Cell120.PHI * Cell120.PHI * 2.0.squareRoot()) / 2)   // 半径 1 の正 120 胞体の辺の弦 1/(φ²√2)
        check(c.cells == 120 && c.edges.count == 1200 && vs.count == 600 && onS3 && (elen.max()! - elen.min()!) < 1e-9 && abs(elen[0] - want) < 1e-9,
              String(format: "120 胞体：部屋 %d 個・辺 %d 本・頂点 %d 個、辺の長さはどれも %.6f（正 120 胞体の辺 %.6f）", c.cells, c.edges.count, vs.count, elen[0], want))
        r.set = .plain
    }

    // ---- パネルのドック ----
    static func dockChecks() {
        let saved = UserDefaults.standard.dictionary(forKey: DockState.key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: DockState.key) } else { UserDefaults.standard.removeObject(forKey: DockState.key) } }
        let d = DockState(); d.reset()
        d.move(.screen, before: .walk)                       // 「画面」をいちばん上へ
        d.move(.walk, before: nil)                           // 「歩く」をいちばん下へ
        d.move(.marks, before: .marks)                       // 自分の前へは動かない
        d.toggle(.shell); d.toggle(.view); d.toggle(.view)
        let ok1 = d.order.first == .screen && d.order.last == .walk && d.order.count == PanelID.allCases.count && Set(d.order) == Set(PanelID.allCases)
        let d2 = DockState()                                  // 保存したものを読み直す
        check(ok1 && d2.order == d.order && d2.collapsed == [.shell], "パネルの並べかえ・たたみ・保存（\(d2.order.map(\.title).joined(separator: "→"))、たたんだ：\(d2.collapsed.map(\.title).joined()))")
        // 浮かせる・タブでまとめる・ドックへ戻す
        d.floatPanel(.shell, frame: CGRect(x: 100, y: 200, width: 330, height: 440))
        let gid = d.floating[0].id
        d.addTab(.view, to: gid)                              // 「見え方」を同じ窓のタブに
        d.addTab(.lines, to: gid, before: .view)              // 「線の見え方と光」を「見え方」の前に
        d.floatPanel(.map)                                    // 「地図」は別の窓
        let ok2 = d.floating.count == 2 && d.floating[0].tabs == [.shell, .lines, .view] && d.floating[0].selected == .lines && !d.docked.contains(.shell) && !d.docked.contains(.map)
        d.addTab(.map, to: gid)                               // 別の窓のパネルをこの窓へ：元の窓は空になって消える
        let ok3 = d.floating.count == 1 && d.floating[0].tabs.count == 4
        let d3 = DockState()                                  // 浮いた窓と場所も保存される
        let ok4 = d3.floating == d.floating && d3.frames[gid] == CGRect(x: 100, y: 200, width: 330, height: 440)
        d.dockPanel(.view, before: .walk)                     // 1 枚だけドックへ戻す
        let ok5 = d.floating[0].tabs == [.shell, .lines, .map] && d.docked.firstIndex(of: .view)! < d.docked.firstIndex(of: .walk)!
        d.dockGroup(gid)                                      // 窓ごとドックへ
        let ok6 = d.floating.isEmpty && d.docked.count == PanelID.allCases.count
        check(ok2 && ok3 && ok4 && ok5 && ok6, "パネルを浮かせる・タブでまとめる・別の窓から移す（空の窓は消える）・保存・ドックへ戻す（\(ok2) \(ok3) \(ok4) \(ok5) \(ok6)）")
    }

    // ---- 歩く・知らせ・足あと・保存 ----
    static func journeyChecks(_ r: Renderer) {
        r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = true
        var msgs: [String] = []; r.say = { msgs.append($0) }
        let dt = 1.0 / 60
        while r.journey.dist < 2 * Double.pi + 0.3 { r.step(dt) }
        let back = acos(max(-1, min(1, r.cam.w.p.w)))
        check(abs(back - (r.journey.dist - 2 * Double.pi)) < 1e-6, String(format: "2π ＋ %.3f 歩くと、アナ極から %.3f の所（1 周して戻る）", r.journey.dist - 2 * Double.pi, back))
        check(abs(r.journey.w2.p.z - r.cam.w.p.w) < 1e-9 && abs(simd_length(r.journey.w2.p) - 1) < 1e-12,
              String(format: "S² の仲間：まっすぐ歩くと、S² の北極からの距離と S³ のアナ極からの距離が同じ（z ＝ %.6f、w ＝ %.6f）", r.journey.w2.p.z, r.cam.w.p.w))
        let kinds = msgs.map { $0.contains("赤道") ? "赤道" : $0.contains("カタ極") ? "カタ極" : $0.contains("アナ極") ? "アナ極" : "?" }
        check(kinds == ["赤道", "カタ極", "赤道", "アナ極"], "1 周歩くと、赤道 → カタ極 → 赤道 → アナ極 の順に知らせが出る（\(msgs.joined(separator: "／"))）")
        let n1 = r.journey.foot.count
        r.walking = true; while r.journey.dist < 30 { r.step(dt) }; r.walking = false   // 30 まで歩くと 50 個ぶん。古いものから消えて 40 個
        check(n1 == Int((2 * Double.pi + 0.3) / Journey.footEvery) && r.journey.foot.count == Journey.footMax, "足あと：1 周で \(n1) 個、30 歩くと最大の \(r.journey.foot.count) 個（古いものから消える）")
        let gaps = zip(r.journey.foot, r.journey.foot.dropFirst()).map { acos(max(-1, min(1, dot4($0, $1)))) }
        check(gaps.allSatisfy { abs($0 - Journey.footEvery) < 0.02 }, String(format: "足あとの間は %.1f（%.3f〜%.3f）", Journey.footEvery, gaps.min() ?? 0, gaps.max() ?? 0))
        // 目印を置いて、目印の数が 64 をこえない
        for _ in 0..<30 { r.addMark() }
        check(r.markers().count <= 64, "目印の玉は 64 個まで（極 8・目印 30・足あと 40・自分 → \(r.markers().count) 個）")
        // 縦横無尽：向きが変わりながら、体の枠は正規直交のまま
        r.roaming = true; for _ in 0..<3000 { r.step(dt) }; r.roaming = false
        check(frameErr(r.cam.w) < 1e-12 && abs(r.cam.el) <= 80, String(format: "縦横無尽で 50 秒歩いても、体の枠は正規直交（ずれ %.1e）・仰角は ±80° の中（%.1f°）", frameErr(r.cam.w), r.cam.el))
        // 保存して読み直すと、同じ場所・向き・目印・設定
        r.set.shellSolid = true; r.set.fog = 0.31; r.set.shellN = 7
        let snap = Store.snapshot(r)
        UserDefaults.standard.set(snap, forKey: "s3walk.verify.tmp")
        let r2 = Renderer(device: r.device)!
        if let d = UserDefaults.standard.dictionary(forKey: "s3walk.verify.tmp") { UserDefaults.standard.set(d, forKey: Store.key + ".verify") }
        let saved = UserDefaults.standard.dictionary(forKey: Store.key)
        UserDefaults.standard.set(snap, forKey: Store.key); Store.restore(r2)
        if let saved { UserDefaults.standard.set(saved, forKey: Store.key) } else { UserDefaults.standard.removeObject(forKey: Store.key) }
        UserDefaults.standard.removeObject(forKey: "s3walk.verify.tmp"); UserDefaults.standard.removeObject(forKey: Store.key + ".verify")
        let same = simd_length(r2.cam.w.p - r.cam.w.p) < 1e-12 && simd_length(r2.cam.w.f - r.cam.w.f) < 1e-9 && r2.cam.az == r.cam.az && r2.cam.el == r.cam.el
            && r2.journey.marks.count == r.journey.marks.count && r2.set.shellSolid && r2.set.fog == 0.31 && r2.set.shellN == 7
        check(same, "保存して読み直すと、同じ場所・向き・目印（\(r2.journey.marks.count) 個）・設定")
        // 決まった道：螺旋は道の式の上を進み（S² の仲間は S² の螺旋の上）、回る輪は 1 周（2π）でアナ極に戻る
        r.set = .plain; r.startPath(.spiral); var dev = 0.0
        for _ in 0..<2000 { r.step(dt); let (q, q2) = PathWalk.spiralPoint(r.path.th, r.path.lap, r.set); dev = max(dev, simd_length(q - r.cam.w.p), simd_length(q2 - r.journey.w2.p), frameErr(r.cam.w)) }
        check(dev < 1e-9 && r.pathMode == .spiral, String(format: "螺旋：2000 コマ歩いても道の式の上（ずれ %.1e）・体の枠は正規直交", dev))
        r.set = .plain; r.startPath(.ring); let d0 = r.journey.dist
        while r.path.T < 2 * Double.pi + 0.002 { r.step(dt) }
        let backR = acos(max(-1, min(1, r.cam.w.p.w)))
        check(backR < 0.01 && abs((r.journey.dist - d0) - 2 * Double.pi) < 0.02, String(format: "回る輪：大円を 1 周（道のり %.4f ≈ 2π）するとアナ極のそば（%.4f）に戻る", r.journey.dist - d0, backR))
        r.pathMode = .none
        // 上下も 360° 回す（宙返り）：仰角 85° から 10° 上げると 95°（止まらない）。進む向きは真上を越えて、なめらかに後ろ向きへ
        do {
            var c = Camera(); c.el = 85; let L0 = c.lookFrame().L
            c.el += 10; c.clampAngles(free: true); let L1 = c.lookFrame().L
            var c2 = Camera(); c2.el = 95; c2.clampAngles(free: false)
            c.el = 350; c.clampAngles(free: true)
            check(abs(Camera().el) < 1e-9 && abs(acos(max(-1, min(1, dot4(L0, L1)))) - 10 * d2r) < 1e-9 && c2.el == 89 && abs(c.el + 10) < 1e-9,
                  "上下も 360° 回す：85° → 95°（向きは 10° なめらかに）、350° は −10°。オフの時はウェブ版と同じく 89° で止まる")
        }
        // 宙返りしても左右（と反転）は画面どおり：右スティックの上で 200° 上へ回してから右へ倒すと、景色は画面の右へ回る。反転オンなら左へ
        do {
            func turnRight(_ inv: Bool) -> Double {
                r.set = .plain; r.set.gamepad = true; r.set.padGame = false; r.set.free360 = true; r.set.padInvX = inv; r.cam = Camera(); r.journey = Journey()
                for _ in 0..<400 { r.game.fake = (.zero, [0, 1], false, false, false); r.step(1.0 / 120) }   // 上へ 60°／秒 × 3.3 秒 ≈ 200°
                let F = r.cam.lookFrame()
                for _ in 0..<30 { r.game.fake = (.zero, [1, 0], false, false, false); r.step(1.0 / 120) }
                r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
                return dot4(r.cam.lookFrame().L, F.R)
            }
            let a = turnRight(false), b = turnRight(true)
            check(a > 0.05 && b < -0.05, String(format: "宙返り（上へ約 200°）のあと右へ倒すと右へ回る（%.2f）、左右反転なら左へ（%.2f）", a, b))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // ショートカットキー：初めは今までのキー、変えるとほかの操作からは外れる、初めに戻せる。説明も今のキーで
        do {
            let km = Keymap(persist: false)
            let d0 = km.action(for: "l") == .shell && km.action(for: "+") == .rangeUp && km.action(for: "\r") == .headGo && km.action(for: "w") == nil
            let lost = km.assign("l", to: .space)
            let moved = km.action(for: "l") == .space && lost == .shell && km.label(.shell).isEmpty && km.action(for: "n") == nil && km.helpText().contains("L 背景")
            km.reset()
            let back = km.isDefault && km.action(for: "n") == .space && km.hint(.rangeUp) == "（= / +）"
            let dup = Set(KeyAction.allCases.flatMap(\.defaults)).count == KeyAction.allCases.flatMap(\.defaults).count && !KeyAction.allCases.flatMap(\.defaults).contains(where: Keymap.fixed.contains)
            check(d0 && moved && back && dup, "ショートカットキー：初めは今までのキー（重なりなし）、L を背景にすると球層から外れる、初めに戻せる")
        }
        // 自走（歩き続ける）：左スティックを前へ倒し続けると速く、離すとそのまま、手前でブレーキ、止まっても倒していると軌跡を巻き戻す
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = true
            func run(_ n: Int, _ z: Double) { for _ in 0..<n { r.game.fake = ([0, 0, z], .zero, false, false, false); r.step(1.0 / 120) } }
            run(120, 0); let d1 = r.journey.dist
            run(60, 1); let fwd = r.autoSpeed                                  // 左スティックの前：ゆっくりアクセル（0.5 秒で 1.5 倍より小さい）
            r.game.fakeHeld = ["A"]; run(240, 0); r.game.fakeHeld = nil; run(30, 0); let fast = r.autoSpeed   // 離して A が抜けきるまで（0.2 秒）待つ   // A（アクセル）を押して速く
            run(120, 0); let cruise = r.autoSpeed, nTr = r.journey.trail.count, far = r.journey.dist
            run(450, -1); let back = r.journey.dist, nTr2 = r.journey.trail.count, rew = r.rewinding
            run(10, 0)
            r.walking = false; r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
            check(d1 > 0 && fwd > 1.3 && fwd < 2.2 && fast > 2 && abs(cruise - fast) < 1e-9 && rew && back < far - 0.3 && nTr2 < nTr && !r.rewinding,
                  String(format: "自走：左スティックの前で加速、A で ×%.1f（離してもそのまま）、手前でブレーキ→巻き戻し（道のり %.2f → %.2f、軌跡 %d → %d 点）", fast, far, back, nTr, nTr2))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 決まった道の速さ：A を 1 秒押すと 2 倍、スティックを手前へ 2 秒で 1/2（極めぐりの道のままで）
        do {
            r.set = .plain; r.set.gamepad = true; r.startPath(.tour); r.game.fake = (.zero, .zero, false, false, false)
            func run(_ n: Int, _ y: Double) { r.game.fakeHeld = y > 0 ? ["A"] : []; r.game.fake = ([0, 0, y < 0 ? y : 0], .zero, false, false, false); for _ in 0..<n { r.step(1.0 / 120) } }
            run(60, 0); let d0 = r.journey.dist; run(120, 1); let up = r.pathSpeed; run(240, -1); let dn = r.pathSpeed
            run(60, 0); let d1 = r.journey.dist, still = r.pathMode == .tour
            r.game.fake = nil; r.game.fakeHeld = nil; r.pathMode = .none; r.set.gamepad = false
            check(abs(up - 2) < 0.02 && abs(dn - 0.5) < 0.01 && still && d1 > d0, String(format: "決まった道の速さ：A を 1 秒で ×%.2f、スティックを手前へ 2 秒で ×%.2f（極めぐりのまま）", up, dn))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 自動走行中のコントローラー：左スティックは歩かずに速さ（前 1 秒で 2 倍）、右スティックは見回し（道はそのまま）、X は効かない、B で中止（知らせが出る）
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.startPath(.tour)
            var said = ""; let say0 = r.say; r.say = { said = $0 }
            r.game.fake = (SIMD3(0, 0, 1), .zero, false, false, false); r.game.fakeDpad = 0
            for _ in 0..<120 { r.step(1.0 / 120) }
            let sp = r.pathSpeed, still = r.pathMode == .tour
            r.game.fake = (SIMD3(0.8, 0, 0), SIMD2(1, 0), false, false, false); for _ in 0..<30 { r.step(1.0 / 120) }
            let hy = r.cam.hy, still2 = r.pathMode == .tour
            let xUsed = r.padDuringAuto("X"), roam = r.roaming
            _ = r.padDuringAuto("ZR"); r.game.fake = (.zero, .zero, false, false, false); for _ in 0..<150 { r.step(1.0 / 120) }
            let back = abs(r.cam.hy)
            let bUsed = r.padDuringAuto("B"), stopped = r.pathMode == .none, msg = said
            let after = r.padDuringAuto("B")
            r.game.fake = nil; r.game.fakeDpad = nil; r.say = say0; r.set.gamepad = false
            check(abs(sp - 2) < 0.03 && still && hy > 10 && still2 && xUsed && !roam && back < 0.05 && bUsed && stopped && msg.contains("中止") && !after,
                  String(format: "自動走行中：左スティックの前で ×%.2f（極めぐりのまま）、右スティックで見回し %.0f°（道のまま）、X は効かない、Y で前へ戻す、B で中止「%@」", sp, hy, msg))
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false
        }
        // 目印ごとの模型：選んだ模型で置ける・ランダムは前の目印と違う種類・1 つずつ消すと並びがそろったまま・保存して戻すと同じ・地図の小さな絵ができる
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
            r.set.markModel = 5; r.addMark(); r.set.markModel = 7; r.cam.walk([0, 0, 1], 0.3); r.addMark()
            r.set.markModel = -1; var diff = true
            for _ in 0..<20 { r.cam.walk([0, 0, 1], 0.05); r.addMark(); let n = r.journey.markKinds.count; if r.journey.markKinds[n - 1] == r.journey.markKinds[n - 2] { diff = false } }
            let k0 = Array(r.journey.markKinds.prefix(2))
            r.removeMark(0, routes: false); let aligned = r.journey.marks.count == r.journey.markKinds.count && r.journey.marks2.count == r.journey.marks.count && r.journey.markKinds[0] == 7
            let snap = Store.snapshot(r), kinds = r.journey.markKinds; r.journey = Journey(); Store.applyPosition(r, snap)
            r.setMarkKind(0, 2)
            let thumb = r.modelThumb(3, size: 48)
            check(k0 == [5, 7] && diff && aligned && Array(r.journey.markKinds.dropFirst()) == Array(kinds.dropFirst()) && r.markKind(0) == 2 && thumb?.width == 48,
                  "目印ごとの模型：たぬき・たこを選んで置けた、ランダムはとなりと別の種類、1 つ消しても並びがそろう、保存して戻せる、あとから変えられる、地図の小さな絵ができる")
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 次元おりがみ（ネイティブ版）の分解：中心の胞は動かず、ほかは離れる・くっつけると 0 に戻る・数えるは 1 個ずつ（まだの胞はうっすら）
        do {
            let o = OrigamiState(); o.reset(); o.progress = 1
            func cv(_ n: Int) -> [[SIMD3<Double>]] { OrigamiState.cells(n).map { c in [o.place(o.fold(c, [Double](repeating: 1, count: n).enumerated().map { $0.offset == OrigamiState.fixed(c, n).0 ? OrigamiState.fixed(c, n).1 : $0.element }, n), n).0] } }
            o.startXp(1); for _ in 0..<200 { o.tick(1.0 / 60) }
            let off4 = o.explodeOffsets(cv(4), 4), off3 = o.explodeOffsets(cv(3), 3)
            let apart = o.explodeRaw == 1 && off4[0] == .zero && off3[0] == .zero && off4.dropFirst().allSatisfy { simd_length($0) > 1.5 } && off3.dropFirst().allSatisfy { simd_length($0) > 1.5 }
            o.startXp(0); var flashed = false; for _ in 0..<200 { o.tick(1.0 / 60); if o.cellFocus(3, 8).edge > 1.5 { flashed = true } }
            let back = o.explodeRaw == 0 && o.explodeOffsets(cv(4), 4).allSatisfy { $0 == .zero }
            o.startCount(); for _ in 0..<150 { o.tick(1.0 / 60) }
            let dim = o.countIdx >= 0 && o.cellFocus(7, 8).face < 0.2 && o.cellFocus(o.countIdx, 8).face > 1.5
            o.progress = 0; o.endCount(); o.explodeRaw = 1
            let net = o.explodeOffsets(cv(4), 4), netOK = net[0] == .zero && net.dropFirst().allSatisfy { simd_length($0) > 0.3 }
            check(apart && flashed && back && dim && netOK, "次元おりがみ・分解：中心の胞は動かず、ほかの胞は離れる（組み上がり・展開図）、くっつく瞬間に辺が光り 0 に戻る、数える時は今の胞が濃く・まだの胞はうっすら")
        }
        // 記録した自走の速さ：十字の上で ×2 にして止め、また歩き始めると ×2 から。ターボで歩き始めて、ターボをやめると ×2 に。自走の左右は横歩きしない
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.set.cruise = 1
            r.walking = true; r.game.fake = (.zero, .zero, false, false, false); r.game.fakeDpad = 0; r.step(1.0 / 120)
            r.game.fakeHeld = ["A"]; for _ in 0..<120 { r.step(1.0 / 120) }; r.game.fakeHeld = []
            let rec = r.set.cruise
            r.walking = false; r.step(1.0 / 120); r.walking = true; r.step(1.0 / 120); let again = r.autoSpeed
            r.walking = false; r.step(1.0 / 120); r.turbo(); r.step(1.0 / 120); r.turbo(); let afterTurbo = r.autoSpeed
            let p0 = r.cam.w.p; r.game.fake = (SIMD3(1, 0, 0), .zero, false, false, false); for _ in 0..<60 { r.step(1.0 / 120) }
            r.game.fake = (.zero, .zero, false, false, false); r.cam.w.p = p0
            r.game.fake = nil; r.game.fakeDpad = nil; r.game.fakeHeld = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(abs(rec - 1.71) < 0.05 && abs(again - rec) < 1e-9 && abs(afterTurbo - rec) < 1e-9, String(format: "記録した自走の速さ：×%.2f を覚えて、止めて歩き始めても ×%.2f、ターボのあとも ×%.2f", rec, again, afterTurbo))
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.cruise = 1
        }
        // 自動（Y）の間は、アクセルを離しても減速しない。B で遅くしても自動のまま、その速さを保つ
        do {
            r.set = .plain; r.set.gamepad = true; r.set.autoMax = 4; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.step(1.0 / 120)
            r.game.fake = (.zero, .zero, false, false, false); r.game.fakeHeld = []; _ = r.padWalk("Y"); r.step(1.0 / 120)
            r.game.fakeHeld = ["A"]; for _ in 0..<120 { r.step(1.0 / 120) }; let a1 = r.autoSpeed
            r.game.fakeHeld = []; for _ in 0..<30 { r.step(1.0 / 120) }; let a1b = r.autoSpeed; for _ in 0..<360 { r.step(1.0 / 120) }; let a2 = r.autoSpeed
            r.game.fakeHeld = ["B"]; for _ in 0..<48 { r.step(1.0 / 120) }; r.game.fakeHeld = []; for _ in 0..<30 { r.step(1.0 / 120) }; let b1 = r.autoSpeed
            for _ in 0..<360 { r.step(1.0 / 120) }; let b2 = r.autoSpeed, still = r.walking && r.autoCruise, rec = r.set.cruise
            r.game.fakeHeld = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(a1 > 1.5 && abs(a2 - a1b) < 1e-9 && b1 < a1b * 0.9 && abs(b2 - b1) < 1e-9 && still && abs(rec - b1) < 0.01,
                  String(format: "自動の間：A で ×%.2f、離して 3 秒も ×%.2f（減速しない）。B で ×%.2f にしても自動のまま、3 秒後も ×%.2f", a1, a2, b1, b2))
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.cruise = 1
        }
        // A・B はスティックのように：押した瞬間の速さの変わり方はほぼ 0 から、だんだん強く（一瞬カクつかない）。離した時も急に抜けない
        do {
            r.set = .plain; r.set.gamepad = true; r.set.autoMax = 4; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.step(1.0 / 120)
            r.game.fake = (.zero, .zero, false, false, false); r.game.fakeHeld = []; _ = r.padWalk("Y"); r.step(1.0 / 120)
            func rate(_ held: Set<String>) -> Double { r.game.fakeHeld = held; let s = r.autoSpeed; r.step(1.0 / 120); return (r.autoSpeed - s) * 120 }
            let a0 = rate(["A"]); for _ in 0..<60 { _ = rate(["A"]) }; let aFull = rate(["A"]); let aOff = rate([])
            for _ in 0..<60 { _ = rate([]) }
            let b0 = rate(["B"]); for _ in 0..<90 { _ = rate(["B"]) }; let bFull = rate(["B"]); let bOff = rate([])
            r.game.fakeHeld = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(a0 < aFull * 0.05 && aOff > aFull * 0.9 && b0 > bFull * 0.05 && bOff < bFull * 0.9,
                  String(format: "A・B はなめらかに効く：A の加速 押した瞬間 %.3f → いっぱい %.2f/秒（離した瞬間 %.2f）、B の減速 押した瞬間 %.3f → いっぱい %.2f/秒（離した瞬間 %.2f）", a0, aFull, aOff, b0, bFull, bOff))
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.cruise = 1
        }
        // チェックポイント：置いた所に立っている間は数えず、前に置いた目印を通ると 1、ぐるっと 1 周して最初の目印に戻ると全部通ったので 1 周（チェックは 0 に戻って 2 周目）
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.step(1.0 / 60)
            var said: [String] = []; let keep = r.say; r.say = { said.append($0) }
            r.addMark()
            var c2 = r.cam; c2.walk([0, 0, 1], 1.0); r.journey.marks.append(c2.w.p); r.journey.marks2.append(r.journey.w2.p); r.journey.markKinds.append(0)
            r.walking = true
            while r.journey.dist < 0.5 { r.step(1.0 / 60) }; let h0 = r.journey.marksHit.count
            while r.journey.dist < 1.3 { r.step(1.0 / 60) }; let h1 = r.journey.marksHit.count
            while r.journey.dist < 2 * .pi + 0.3 { r.step(1.0 / 60) }; let h2 = r.journey.marksHit.count, lap = r.journey.lap
            r.walking = false; r.step(1.0 / 60); r.say = keep
            let msg = said.filter { $0.hasPrefix("チェック") && $0.contains("目印") }, poles = r.journey.polesHit, poleMsg = said.filter { $0.contains("（極 ") }
            r.clearMarks(); let cleared = r.journey.marksHit.isEmpty && r.journey.lap == 1
            check(h0 == 0 && h1 == 1 && h2 == 0 && lap == 2 && msg.count == 2 && msg.last!.contains("2 周目へ") && cleared && poles.contains(0) && poles.contains(1) && poleMsg.count == poles.count - 2,
                  "チェックポイント：置いた所では数えず（\(h0)）、前の目印を通って \(h1)、1 周して最初の目印で全部通って \(lap) 周目へ（チェックは \(h2) に戻る。\(msg.last ?? "")）。目印を消すと記録と周回も消える。極も 1 周で \(poles.count) つ（\(poles.map { MapRenderer.poleName(FIXED[$0]) }.joined(separator: "・"))）")
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 4D 球アナロジーの球層の数をさんぽと連動：さんぽで変えるとこちらへ、こちらで変えるとさんぽへ（3〜21 に収める）
        do {
            let keep = HyperLabState.walkShells
            var walkN = 11
            HyperLabState.walkShells = (get: { walkN }, set: { walkN = $0 })
            let st = HyperLabState(); st.layers = 5; st.layersLink = true
            st.pullLayers(); let a = st.layers
            walkN = 15; st.pullLayers(); let b = st.layers
            st.setLayers(7); let c = walkN
            st.setLayers(30); let d = (st.layers, walkN)
            st.layersLink = false; st.setLayers(30); let e = (st.layers, walkN)
            HyperLabState.walkShells = keep
            check(a == 11 && b == 15 && c == 7 && d == (21, 21) && e == (30, 21),
                  "球層の数の連動：さんぽ 11 → こちら \(a)、さんぽ 15 → \(b)、こちらで 7 → さんぽ \(c)、30 → どちらも \(d.0)（3〜21）。切ると別々（こちら \(e.0)・さんぽ \(e.1)）")
        }
        // 4D 球アナロジーの「自分を追う」：遊び 0° は真ん中へ（進む向きも上へ）、遊び 90° は遊びの中では動かさず、外（奥）へ行くと 90° まで連れ戻す
        do {
            let keep = HyperLabState.walkSource
            let back = nrm(SIMD4<Double>(0.3, -0.5, 0.4, -0.7)), fw = nrm(SIMD4<Double>(0.6, 0.2, -0.7, 0.1) - back * dot4(SIMD4<Double>(0.6, 0.2, -0.7, 0.1), back))
            HyperLabState.walkSource = { .init(trail: [], pos: back, fwd: fw) }
            let st = HyperLabState(); st.followOn = true; st.followSlack = 0; st.followHeading = true
            for _ in 0..<600 { st.tickFollow(1.0 / 60) }
            let c0 = st.rot4(back).w, up = st.rot4(fw).y
            let st2 = HyperLabState(); st2.followOn = true; st2.followSlack = 90; st2.followDrift = 0
            let near = nrm(SIMD4<Double>(0.6, 0, 0, 0.8)); HyperLabState.walkSource = { .init(trail: [], pos: near) }
            for _ in 0..<60 { st2.tickFollow(1.0 / 60) }; let still = st2.pitch == 0 && st2.roll == 0 && st2.zw == 0
            HyperLabState.walkSource = { .init(trail: [], pos: back) }
            for _ in 0..<600 { st2.tickFollow(1.0 / 60) }; let th = acos(max(-1, min(1, st2.rot4(back).w))) * 180 / .pi
            // ゆるく回す：遊びの中でも少しずつ回る（1 秒で数度ほど。止まらないが、ゆっくり）
            let st3 = HyperLabState(); st3.followOn = true; st3.followSlack = 90; st3.followDrift = 0.3
            HyperLabState.walkSource = { .init(trail: [], pos: near) }
            let th0 = acos(st3.rot4(near).w); for _ in 0..<60 { st3.tickFollow(1.0 / 60) }; let drift = (th0 - acos(st3.rot4(near).w)) * 180 / .pi
            HyperLabState.walkSource = keep
            // 進む向きを上へ向けるのは面内（X-Y）の回転だけなので、画面の奥行きの成分を除いた分まで（いちばん上を向いた時の値と比べる）
            let fv = st.rot4(fw), best = (fv.x * fv.x + fv.y * fv.y).squareRoot()
            check(c0 > 0.995 && up > best - 0.03 && still && abs(th - 90) < 3 && drift > 0.3 && drift < 15,
                  String(format: "自分を追う：遊び 0° で真ん中へ（正面 %.3f・進む向きの上 %.2f／できる限り %.2f）、遊び 90° は中では動かさず、奥からは %.1f° まで戻す。ゆるく回すと遊びの中でも 1 秒で %.1f° 寄る", c0, up, best, th, drift))
        }
        // 手で走る時（A・B）は、左スティックが向きの操作（右へ倒すと右へ曲がり、前へ倒すと上を向く。速さは変えない）。自動の時は今までどおりアクセル
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.step(1.0 / 120)
            r.game.fake = (.zero, .zero, false, false, false); r.game.fakeHeld = []; _ = r.padWalk("A"); r.game.fakeHeld = ["A"]
            for _ in 0..<120 { r.step(1.0 / 120) }; r.game.fakeHeld = []; for _ in 0..<30 { r.step(1.0 / 120) }
            let az0 = r.cam.az, el0 = r.cam.el, s0 = r.autoSpeed
            r.game.fake = (SIMD3(1, 0, 1), .zero, false, false, false); for _ in 0..<60 { r.step(1.0 / 120) }
            let turned = r.cam.az - az0, up = r.cam.el - el0, s1 = r.autoSpeed, manual = r.walking && !r.autoCruise
            r.game.fake = (.zero, .zero, false, false, false); _ = r.padWalk("Y"); r.step(1.0 / 120)
            let az1 = r.cam.az; r.game.fake = (SIMD3(0, 0, 1), .zero, false, false, false); let s2 = r.autoSpeed; for _ in 0..<60 { r.step(1.0 / 120) }
            let autoAcc = r.autoSpeed > s2 + 0.05 && abs(r.cam.az - az1) < 1e-9
            r.game.fakeHeld = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(manual && turned > 10 && up > 5 && s1 < s0 && autoAcc,
                  String(format: "手で走る時は左スティックで向き：右へ %.0f°・上へ %.0f°（速さは ×%.2f → ×%.2f、ゆるやかに減るだけ）、自動の時は前で加速", turned, up, s0, s1))
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.cruise = 1
        }
        // 手で走る（A）時の最高速は、自動（Y）の半分
        do {
            r.set = .plain; r.set.gamepad = true; r.set.autoMax = 4; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.step(1.0 / 120)
            r.game.fake = (.zero, .zero, false, false, false); _ = r.padWalk("A"); r.game.fakeHeld = ["A"]; for _ in 0..<2400 { r.step(1.0 / 120) }; let man = r.autoSpeed
            r.game.fakeHeld = []; _ = r.padWalk("Y"); r.game.fakeHeld = ["A"]; for _ in 0..<2400 { r.step(1.0 / 120) }; let auto = r.autoSpeed
            r.game.fakeHeld = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(abs(man - 2) < 1e-9 && abs(auto - 4) < 1e-9, String(format: "最高速：手で走る時 ×%.1f、自動の時 ×%.1f（最高 4）", man, auto))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 左右のスティックの入れかえ（画面のゲームパッド）：左を倒すと向き、右を倒すと歩く。押し込みも入れかわる
        do {
            let g = GameInput(); var got: [String] = []; g.onButton = { got.append($0) }
            g.swapSticks = true; g.vLeft = SIMD2(0, 1); g.vRight = SIMD2(0, -1)
            let a = g.read(); g.vPress("L3", true); g.vPress("L3", false); g.vPress("R3", true); let push = g.read().push; g.vClear()
            g.swapSticks = false; g.vLeft = SIMD2(0, 1); let b = g.read(); g.vClear()
            check(a.look.y == 1 && a.move.z == -1 && got == ["R3"] && push && b.move.z == 1 && b.look.y == 0, "左右のスティックの入れかえ：左で向き・右で歩く、L3 は前を見る（R3 の働き）・R3 は跡を消す（L3）。切ると元どおり")
        }
        // 同期：静かモード・コントローラーで歩くは種類の端末ごと（共通には入れない）、今いる所は上げない、地図の向きは行って戻る
        do {
            let c = NativeSync.commonCore(r)["set"] as? [String: Any] ?? [:], k = NativeSync.kindSettings(r)
            let ms = [MapRenderer(world: r, slot: 0), MapRenderer(world: r, slot: 1)]
            ms[0].yaw = 1.1; ms[0].pitch = 0.3; ms[0].dist = 7; ms[0].target = [0.1, 0.2, 0.3]
            let v = NativeSync.mapViews(ms); ms[0].home(); NativeSync.applyMapViews(ms, v)
            check(c["quiet"] == nil && c["gamepad"] == nil && c["scale"] == nil && k["quiet"] != nil && k["gamepad"] != nil && k["scale"] == nil
                  && abs(ms[0].yaw - 1.1) < 1e-12 && abs(ms[0].dist - 7) < 1e-12 && ms[0].target == [0.1, 0.2, 0.3] && NativeSync.uiKey == "ui_mac",
                  "同期：静かモード・コントローラーで歩くは Mac どうしだけ、描く細かさはそろえない、地図の向きは書き出して戻せる")
        }
        // 歩き続ける時のボタン：A を 1 秒で約 2.2 倍、十字の上 ターボ・下 ターボ切（元の速さへ）、B を押し続けるとブレーキで止まる
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; r.game.fake = (.zero, .zero, false, false, false)
            let sr = r.set.shellRange
            r.game.fakeHeld = []; r.step(1.0 / 120); r.game.fakeHeld = ["A"]; for _ in 0..<120 { r.step(1.0 / 120) }; let up = r.autoSpeed
            r.game.fakeHeld = []; _ = r.padWalk("up"); r.step(1.0 / 120); let tb = r.autoSpeed; _ = r.padWalk("down"); r.step(1.0 / 120); let back = r.autoSpeed
            let s0 = r.autoSpeed; r.game.fakeHeld = ["B"]; for _ in 0..<12 { r.step(1.0 / 120) }; let soft = (s0 - r.autoSpeed) / s0   // 押し始め 0.1 秒はやわらかく
            for _ in 0..<600 { r.step(1.0 / 120) }; let stopped = !r.walking
            r.game.fakeHeld = []; _ = r.padWalk("Y"); r.step(1.0 / 120); let yAuto = r.walking && r.autoCruise
            _ = r.padWalk("X"); r.step(1.0 / 120); let xT = r.autoSpeed; _ = r.padWalk("X"); r.step(1.0 / 120)
            _ = r.padWalk("Y"); r.step(1.0 / 120); let ySoft = r.walking; for _ in 0..<480 { r.step(1.0 / 120) }; let ystop = !r.walking && !r.roaming
            // 車のように：A で走り出すとゆっくりから、離すと急に止まらずに減速して、やがて止まる
            _ = r.padWalk("A"); r.game.fakeHeld = ["A"]; for _ in 0..<120 { r.step(1.0 / 120) }; let carUp = r.autoSpeed
            r.game.fakeHeld = []; for _ in 0..<120 { r.step(1.0 / 120) }; let coast = r.autoSpeed; for _ in 0..<1800 { r.step(1.0 / 120) }; let coastStop = !r.walking
            r.game.fakeHeld = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(abs(up - 1.71) < 0.05 && abs(tb - r.set.autoMax) < 1e-9 && abs(back - up) < 0.01 && stopped && soft < 0.12 && yAuto && abs(xT - r.set.autoMax) < 1e-9 && ySoft && ystop
                  && carUp > 0.45 && coast < carUp && coast > carUp * 0.8 && coastStop && r.set.shellRange == sr,
                  String(format: "歩き続ける時のボタン：A を 1 秒で ×%.2f、十字の上でターボ ×%.0f・下で ×%.2f、B は押し始めやわらか（0.1 秒で %.1f%%）・押し続けると止まる、Y で自動の開始・なめらかに停止、X でターボ。A で走り出すと ×%.2f、離して 1 秒で ×%.2f（急に止まらない）", up, tb, back, soft * 100, carUp, coast))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // ターボ：止まっていたら最高速で歩き始め、もう一度で元の速さに。決まった道では道の速さを最高速に
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false
            r.turbo(); r.step(1.0 / 120); let a1 = r.autoSpeed, w1 = r.walking
            r.turbo(); r.step(1.0 / 120); let a2 = r.autoSpeed
            r.walking = false; r.step(1.0 / 120); r.startPath(.tour); r.turbo(); let p1 = r.pathSpeed; r.turbo(); let p2 = r.pathSpeed; r.pathMode = .none
            check(w1 && abs(a1 - r.set.autoMax) < 1e-9 && abs(a2 - 1) < 1e-9 && abs(p1 - r.set.autoMax) < 1e-9 && abs(p2 - 1) < 1e-9,
                  String(format: "ターボ：歩き始めて ×%.0f → もう一度で ×%.0f、決まった道 ×%.0f → ×%.0f", a1, a2, p1, p2))
            // 押している間だけ：Z を押している間は最高速、離すと元の速さ
            r.set = .plain; r.set.turboHold = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; r.step(1.0 / 120)
            r.keys.insert(6); r.turboPress(key: 6); r.step(1.0 / 120); r.step(1.0 / 120); let h1 = r.autoSpeed
            r.keys.remove(6); r.step(1.0 / 120); let h2 = r.autoSpeed; r.walking = false
            check(abs(h1 - r.set.autoMax) < 1e-9 && abs(h2 - 1) < 1e-9, String(format: "ターボ（押している間だけ）：押している間 ×%.0f、離すと ×%.0f", h1, h2))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 残す軌跡：1.5π にすると、それより古い跡は消える
        do {
            r.set = .plain; r.set.trailKeep = 1.5; r.cam = Camera(); r.journey = Journey(); r.walking = true
            for _ in 0..<1200 { r.step(1.0 / 60) }
            r.walking = false; r.step(1.0 / 60)
            let n = r.journey.trail.count, lim = Int(1.5 * Double.pi / 0.02)
            check(n <= lim && n >= lim - 2 && r.journey.trail2.count == n && r.journey.dist > 1.5 * Double.pi, "残す軌跡 1.5π：跡の点 \(n)（上限 \(lim)）、S² の仲間も同じ数")
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 設定の検索：「もや」「fps」「目印 線」で項目が見つかり、押すとそのパネルへ
        do {
            let ss = SettingSearch.shared, keep = ss.query
            ss.query = "もや"; let h1 = ss.hits(); ss.query = "fps"; let h2 = ss.hits(); ss.query = "目印 線"; let h3 = ss.hits(); ss.query = "ターボ"; let h4 = ss.hits(); ss.query = "ｆｐｓ"; let h5 = ss.hits(); ss.query = keep
            check(h1.contains { $0.panel == .view && $0.text.contains("もや") } && h2.contains { $0.panel == .screen } && h3.contains { $0.panel == .shell && $0.text == "目印の線" } && h4.contains { $0.panel == .keys } && !h5.isEmpty,
                  "設定の検索：もや \(h1.count) 件・fps \(h2.count) 件・「目印 線」\(h3.count) 件・ターボ \(h4.count) 件（索引 \(searchIndex.count) 項目）")
        }
        // 自走の最高・最低：前へ倒し続けても最高速まで、手前へ倒し続けても最低速まで（最低速が 0 より大きいと巻き戻さない）
        do {
            r.set = .plain; r.set.gamepad = true; r.set.autoMax = 3; r.set.autoMin = 0.5; r.cam = Camera(); r.journey = Journey(); r.walking = true
            func run(_ n: Int, _ z: Double) { for _ in 0..<n { r.game.fake = ([0, 0, z], .zero, false, false, false); r.step(1.0 / 120) } }
            run(10, 0); r.game.fakeHeld = ["A"]; run(1200, 0); r.game.fakeHeld = nil; let hi = r.autoSpeed
            run(1200, -1); let lo = r.autoSpeed, rew = r.rewinding
            r.walking = false; r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
            check(abs(hi - 3) < 1e-9 && abs(lo - 0.5) < 1e-9 && !rew, String(format: "自走の最高・最低：A を押し続けて ×%.1f（最高 3）、手前で ×%.1f（最低 0.5、巻き戻さない）", hi, lo))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 宇宙の大きさ R：同じ速さで歩くと、進む角度は 1/R（1 秒で 0.9／R）。目印の見かけも 1/R
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.uniL = 2; r.walking = true
            for _ in 0..<120 { r.step(1.0 / 120) }
            r.walking = false
            let ang = r.journey.dist, mk = r.markers().first.map { Double($0.col.w) } ?? 0
            check(abs(ang - 0.9 * r.set.spd / 100) < 1e-6 && abs(mk - FIXED[0].r / 100) < 1e-6,
                  String(format: "宇宙の大きさ R ＝ 100：1 秒で進む角度 %.4f（＝ 0.9×速さ／R、道のりは %.2f＝R が 1 の時と同じ）、アナ極の玉の角度 %.4f（＝ 0.13／R）", ang, ang * 100, mk))
            r.set = .plain
        }
        // 中の景色の極の札（ウェブ版の poleLabels）：アナ極から方位 30° を見ると、東極（+x、左前 30°）が 1.57 の所に。北極（+y、右前 60°）は横の視野の外
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
            let ls = r.poleLabels(aspect: 1.6), names = ls.map(\.name)
            let east = ls.first { $0.name.hasPrefix("東極") }, north = ls.first { $0.name.hasPrefix("北極") }
            let wide = r.poleLabels(aspect: 2.6).first { $0.name.hasPrefix("北極") }
            check(names == ["東極 1.57"] && (east?.x ?? 0) < -0.2 && north == nil && (wide?.x ?? 0) > 0.9,
                  "中の景色の極の札：\(names.joined(separator: "・"))（左前に）。横に広い画面なら北極が右のはしに")
            r.set.shAxis = true
            check(r.poleCol(2) == AXIS_RGB[0] && r.poleCol(0) == AXIS_RGB[3], "軸色の球層の時、極の点もその軸の色（東極＝x の赤・アナ極＝w の紫）")
            r.set = .plain
        }
        // 地図の軸の長さ：自分中心では √(1 − p_i²)（歩くと変わる）、ふつう（yw 90°）では x・z・w 100%・y 0%（ウェブ版と同じ値）
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.set.mapFollow = true
            let m = MapRenderer(world: r), a0 = m.axisLengths()
            r.cam.walk([0, 0, 1], 1.0); let a1 = m.axisLengths(), p = r.cam.w.p
            let want = (0..<4).map { i in (1 - p[i] * p[i]).squareRoot() }
            r.set.mapFollow = false; let an = m.axisLengths()
            let pct = { (a: [Double]) in a.map { String(Int(($0 * 100).rounded())) + "%" }.joined(separator: " ") }
            check(zip(a1, want).allSatisfy { abs($0 - $1) < 1e-9 } && a0 != a1 && abs(an[0] - 1) < 1e-9 && an[1] < 1e-9 && abs(an[3] - 1) < 1e-9,
                  "地図の軸の長さ：自分中心でアナ極 \(pct(a0)) → 1 歩いて \(pct(a1))（√(1 − p²) どおり、ウェブ版も 68% 91% 100% 84%）、ふつう \(pct(an))")
        }
        // 見回しと進む向きは別（ウェブ版と同じ）：ZL＋右スティックは見回し（方位はそのまま）、左スティックは進む向きへ（見回していても）、
        //   右スティックだけなら進む向き、ZL を押して離すだけで前を見る、ZL＋Y で見ている向きを進む向きに（景色はそのまま）、Y・右スティックの押し込みで前を見る（進む向きは変えない）
        do {
            r.set = .plain; r.set.gamepad = true; r.set.padGame = true; r.cam = Camera(); r.journey = Journey()
            func run(_ n: Int, _ mv: SIMD3<Double>, _ lk: SIMD2<Double>, lookOnly: Bool = false) { for _ in 0..<n { r.game.fake = (mv, lk, false, false, lookOnly); r.step(1.0 / 120) } }
            func moved() -> V4 { let p1 = r.cam.w.p; r.game.fake = ([0, 0, 1], .zero, false, false, false); r.step(1.0 / 120); return nrm(r.cam.w.p - p1 - r.cam.w.p * dot4(r.cam.w.p - p1, r.cam.w.p)) }
            run(60, .zero, [1, 0.5], lookOnly: true)
            let az0 = r.cam.az, hy0 = r.cam.hy, hp0 = r.cam.hp
            run(60, [0, 0, 1], .zero)
            let alongHead = dot4(moved(), r.cam.lookFrame().L), hyW = r.cam.hy
            run(60, .zero, .zero); run(30, .zero, [1, 0])
            let az1 = r.cam.az, hy1 = r.cam.hy
            var n = 0
            // ZL を押して離すだけ：前を見る（方位はそのまま）
            let azT = r.cam.az, hyT = r.cam.hy
            run(6, .zero, .zero, lookOnly: true); run(1, .zero, .zero); n = 0
            while r.leveling && n < 600 { r.step(1.0 / 120); n += 1 }
            let tapFront = hyT > 10 && r.cam.az == azT && r.cam.hy == 0 && r.cam.hp == 0
            r.cam.hy = hyT
            // Y だけ：前を見る（進む向き・景色の前はそのまま、見回しが 0 へ）
            let azY = r.cam.az, hyY = r.cam.hy; r.game.fake = (.zero, .zero, false, false, false); r.step(1.0 / 120); r.padY(); n = 0
            while r.leveling && n < 600 { r.step(1.0 / 120); n += 1 }
            let yFront = hyY > 10 && r.cam.az == azY && r.cam.hy == 0 && r.cam.hp == 0
            r.cam.hy = hy1; r.cam.hp = 0
            // ZL を押しながら Y：この向きへ進む
            let look = r.cam.viewFrame().L; r.game.fake = (.zero, .zero, false, false, true); r.step(1.0 / 120); r.padY(); r.game.fake = (.zero, .zero, false, false, false); n = 0
            while r.headGoing && n < 600 { r.step(1.0 / 120); n += 1 }
            let goOK = r.cam.hy == 0 && r.cam.hp == 0 && simd_length(r.cam.lookFrame().L - look) < 1e-6
            r.cam.hy = 25; r.cam.hp = 12; r.cam.el = -20; r.levelView(); n = 0
            while r.leveling && n < 600 { r.step(1.0 / 120); n += 1 }
            let front = r.cam.hy == 0 && r.cam.hp == 0 && r.cam.el == -20
            r.levelView(); n = 0
            while r.leveling && n < 600 { r.step(1.0 / 120); n += 1 }
            let level = r.cam.el == 0
            check(az0 == 30 && hy0 > 10 && hp0 > 5 && alongHead > 0.999 && abs(hyW - hy0) < 1e-9 && az1 > 50 && abs(hy1 - hy0) < 1e-9 && goOK && front && level && yFront && tapFront,
                  String(format: "コントローラー：ZL＋右スティックで見回し（方位 %.0f° のまま、横 %.0f°）、歩くのは進む向きへ、右スティックだけで方位 %.0f°、ZL を押して離す・Y で前を見る（方位そのまま）、ZL＋Y で見ている向きへ（%d コマ、景色そのまま）、押し込みで前を見る→もう一度で水平", az0, hy0, az1, n))
            r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
        }
        // 「ゲームのような操作」がオフでも、ZL＋右スティックは見回し、右スティックだけなら進む向き
        do {
            r.set = .plain; r.set.gamepad = true; r.set.padGame = false; r.cam = Camera(); r.journey = Journey()
            for _ in 0..<60 { r.game.fake = (.zero, [1, 0], false, false, true); r.step(1.0 / 120) }
            let az0 = r.cam.az, hy0 = r.cam.hy
            for _ in 0..<60 { r.game.fake = (.zero, [1, 0], false, false, false); r.step(1.0 / 120) }
            check(az0 == 30 && hy0 > 20 && r.cam.az > 60 && r.cam.hy == hy0,
                  String(format: "ゲームのような操作がオフでも：ZL＋右スティックで見回し（横 %.0f°、方位 %.0f° のまま）、右スティックだけで方位 %.0f°", hy0, az0, r.cam.az))
            r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
        }
        // 歩き続けている時（B）に ZL＋右スティックで見回しても、マウスと同じく進む向きは変わらない
        do {
            r.set = .plain; r.set.gamepad = true; r.set.padGame = true; r.cam = Camera(); r.journey = Journey(); r.walking = true
            for _ in 0..<120 { r.game.fake = (.zero, [1, 0], false, false, true); r.step(1.0 / 120) }
            let p1 = r.cam.w.p; r.step(1.0 / 120); let dv = nrm(r.cam.w.p - p1 - r.cam.w.p * dot4(r.cam.w.p - p1, r.cam.w.p))
            check(r.cam.az == 30 && r.cam.hy > 30 && dot4(dv, r.cam.lookFrame().L) > 0.999,
                  String(format: "歩き続けている時に ZL＋右スティックで見回しても（横 %.0f°）、進む向きは方位 %.0f° のまま", r.cam.hy, r.cam.az))
            r.walking = false; r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
        }
        // コントローラー：左スティックを手前に倒すと後ろへ。倒しきったままだと加速。押し込む（L3）と軌跡を消す
        func padRun(_ mv: SIMD3<Double>, _ sec: Double, push: Bool = false) -> Double {
            r.cam = Camera(); r.journey = Journey(); var last = r.cam.w.p, v = 0.0
            for i in 0..<Int(sec * 120) {
                r.game.fake = (mv, .zero, false, push && i == 20, false)
                last = r.cam.w.p; r.step(1.0 / 120); v = acos(max(-1, min(1, dot4(last, r.cam.w.p)))) * 120
            }
            return v
        }
        r.set = .plain; r.set.gamepad = true; r.set.padGame = true
        let L0 = Camera().lookFrame().L
        _ = padRun([0, 0, -0.6], 1)
        let backDot = dot4(r.cam.w.p, L0), base = 0.9 * r.set.spd
        let vHalf = padRun([0, 0, 0.6], 3), vFull = padRun([0, 0, 1], 3), vBack = padRun([0, 0, -1], 3), nTrail = r.journey.trail.count
        for i in 0..<3 { r.game.fake = (.zero, .zero, false, i == 1, false); r.step(1.0 / 120) }
        let cleared = nTrail > 10 && r.journey.trail.count <= 1 && r.journey.foot.isEmpty && r.journey.trail2.count <= 1
        check(backDot < -0.1 && abs(vHalf / base - 0.6) < 0.02 && abs(vFull / base - 2.5) < 0.05 && abs(vBack / base - 2.5) < 0.05 && cleared,
              String(format: "コントローラー：手前に倒すと後ろへ（前との内積 %.2f）。速さ 6 割倒し ×%.2f・倒しきり ×%.2f・後ろへ倒しきり ×%.2f。L3 で軌跡を消す（%d 点 → %d 点）", backDot, vHalf / base, vFull / base, vBack / base, nTrail, r.journey.trail.count))
        // 歩き続けている時に手前へ倒す（少し横に傾いていても）：ブレーキのあと、横へ流れず後ろへ（軌跡の巻き戻し）
        r.cam = Camera(); r.journey = Journey(); r.walking = true
        for i in 0..<210 { r.game.fake = (i < 120 ? .zero : [0.04, 0, -1], .zero, false, false, false); r.step(1.0 / 120) }   // 0.4 秒ほどでブレーキが効いて止まり、そのあと巻き戻し
        let p1 = r.cam.w.p, F1 = r.cam.lookFrame()
        for _ in 0..<12 { r.step(1.0 / 120) }
        let dv = r.cam.w.p - p1, side = abs(dot4(dv, F1.R)) / max(1e-12, simd_length(dv))
        check(dot4(dv, F1.L) < 0 && side < 0.1, String(format: "歩き続けている時に手前へ倒すと後ろへ（進んだ向きの横の割合 %.3f）", side))
        r.walking = false
        r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
        r.say = nil; r.set = .plain; r.cam = Camera(); r.journey = Journey()
    }

    // ---- 画面 ----
    struct Img {
        let w: Int, h: Int, px: [Float]
        func at(_ x: Int, _ y: Int) -> SIMD3<Float> { let i = (y * w + x) * 4; return SIMD3(px[i], px[i + 1], px[i + 2]) }
    }
    static let W = 2001, H = 2001
    static func shot(_ r: Renderer) -> Img { Img(w: W, h: H, px: r.renderOffscreen(width: W, height: H)) }
    static func diffMask(_ a: Img, _ b: Img) -> [Bool] {
        var m = [Bool](repeating: false, count: a.w * a.h)
        for i in 0..<(a.w * a.h) { let k = i * 4; m[i] = abs(a.px[k] - b.px[k]) + abs(a.px[k + 1] - b.px[k + 1]) + abs(a.px[k + 2] - b.px[k + 2]) > 1e-5 }
        return m
    }
    /// 画素（x：左から、y：上から）の中心が向く角度（画面の真ん中から、横・縦）
    static func ang(_ i: Int, _ n: Int, _ tanF: Double) -> Double { atan(((Double(i) + 0.5) / Double(n) * 2 - 1) * tanF) }
    /// 真ん中の行・列で、真ん中からつながっておおわれている所のふちの角度（4 方向の平均）
    static func radius(_ m: [Bool], _ tanF: Double) -> (Double, Double) {
        let cx = W / 2, cy = H / 2
        guard m[cy * W + cx] else { return (-1, 0) }
        var x1 = cx; while x1 + 1 < W && m[cy * W + x1 + 1] { x1 += 1 }
        var x0 = cx; while x0 > 0 && m[cy * W + x0 - 1] { x0 -= 1 }
        var y1 = cy; while y1 + 1 < H && m[(y1 + 1) * W + cx] { y1 += 1 }
        var y0 = cy; while y0 > 0 && m[(y0 - 1) * W + cx] { y0 -= 1 }
        func edge(_ a: Int, _ b: Int, _ n: Int) -> Double { abs((ang(a, n, tanF) + ang(b, n, tanF)) / 2) }
        let rs = [edge(x1, x1 + 1, W), edge(x0, x0 - 1, W), edge(y1, y1 + 1, H), edge(y0, y0 - 1, H)]
        let mean = rs.reduce(0, +) / 4
        return (mean, rs.map { abs($0 - mean) }.max()!)
    }
    /// おおわれた所の重心（画面の真ん中から、右・上が＋。単位は画素）
    static func centroid(_ m: [Bool]) -> (Double, Double, Int) {
        var sx = 0.0, sy = 0.0, n = 0
        for y in 0..<H { for x in 0..<W where m[y * W + x] { sx += Double(x - W / 2); sy += Double(H / 2 - y); n += 1 } }
        return n > 0 ? (sx / Double(n), sy / Double(n), n) : (0, 0, 0)
    }

    static func gpuChecks(_ r: Renderer) {
        r.set = .plain
        r.set.shell = false; r.set.eq = false            // 玉のふちを画素で測るため、殻と膜は消す（もや・透けはそのまま）
        r.set.hidePair = true                            // 反対側の相棒（−x など）を隠す：遠回りの像が、相棒の玉に隠れないように
        let tanF = tan(r.set.fov * d2r / 2), pix = 2 * tanF / Double(W)
        let target = FIXED[2]                            // 東 +x（半径 0.09）
        print(String(format: "  配置：アナ極から方位 30° へ s 歩き、東 +x の玉（半径 %.2f）の方を向く。視野 %.0f°、%d×%d 画素（真ん中で 1 画素 ≈ %.5f rad）", target.r, r.set.fov, W, H, pix))
        print("     s     距離 d   向き       α（式）   α（画素）  ずれ     赤い点の重心（右, 上）   上の玉 / 右の玉の重心")
        for s in [0.3, 0.7, 1.0] {
            var cam = Camera(); cam.walk([0, 0, 1], s)       // 方位 30° のまま、大円に沿って s 歩く（Swift の moveAlong）
            let P = cam.w.p, c = target.c
            let d = acos(dot4(P, c)), w = nrm(c - P * dot4(P, c))
            for ghost in [false, true] {
                var cm = cam; cm.face(ghost ? -w : w)        // 遠回りの像は、後ろ（−w）に見える
                r.cam = cm
                let alphaF = asin(min(1, sin(target.r) / abs(sin(d))))
                // ① 大きさ：玉ありと玉なしの差
                r.set.extra = []; r.set.orient = false; r.set.hideLabels = []
                let A = shot(r); r.set.hideLabels = [target.label]; let B = shot(r); r.set.hideLabels = []
                let mT = diffMask(A, B)
                let (alphaM, spread) = radius(mT, tanF)
                // ② 向き：赤い点ありと赤い点なしの差
                r.set.orient = true; let C = shot(r); r.set.orient = false
                let (rx, ry, rn) = centroid(zip(diffMask(C, A), mT).map { $0 && $1 })   // 東 +x の玉の中の赤い点だけ（ほかの玉の点は数えない）
                // ③ 立体の配置：玉の上（U）と右（R）に小さい玉を置き、像の中でどこに来るか（向きの印の貼り方によらない確かめ）
                let F0 = { var t = cam; t.face(w); return t.viewFrame() }()
                let eps = alphaF * 2.4
                let up = Marker(c: geo(P, nrm(w * cos(eps) + F0.U * sin(eps)), d), col: [1, 1, 1], r: 0.03, label: "上")
                let rt = Marker(c: geo(P, nrm(w * cos(eps) + F0.R * sin(eps)), d), col: [1, 1, 1], r: 0.03, label: "右")
                r.set.extra = [up, rt]
                let D = shot(r)
                r.set.hideLabels = ["上"]; let E1 = shot(r); r.set.hideLabels = ["右"]; let E2 = shot(r); r.set.hideLabels = []; r.set.extra = []
                let (ux, uy, _) = centroid(diffMask(D, E1)), (qx, qy, _) = centroid(diffMask(D, E2))
                let err = abs(alphaM - alphaF)
                print(String(format: "  %5.2f   %5.3f   %@  %8.5f  %8.5f  %.1e   (%+6.1f, %+6.1f) %5d 画素   上(%+5.0f,%+5.0f) 右(%+5.0f,%+5.0f)",
                             s, ghost ? 2 * Double.pi - d : d, ghost ? "遠回り" : "近い道", alphaF, alphaM, err, rx, ry, rn, ux, uy, qx, qy))
                check(alphaM > 0 && err < 1.0 * pix, String(format: "見かけの大きさ sin α = sin r／|sin d|（ずれ %.5f rad ＜ 1 画素、ふちの 4 方向のちらばり %.5f）", err, spread))
                if ghost {
                    check(rn > 0 && rx < 0 && ry < 0, "遠回りの像の赤い点は左下（右上の点が 180° 回った所。鏡なら左上か右下）")
                    check(uy < 0 && abs(ux) < 2 && qx > 0 && abs(qy) < 2, "立体の配置：上の玉は下に、右の玉は右のまま（＝裏側から見た形を 180° 回した像）")
                } else {
                    check(rn > 0 && rx > 0 && ry > 0, "近い道の像の赤い点は右上（正立）")
                    check(uy > 0 && abs(ux) < 2 && qx > 0 && abs(qy) < 2, "立体の配置：上の玉は上に、右の玉は右に")
                }
            }
        }
        // ③ 北極では空全体が南極の玉（距離 π、|sin π| = 0 で見かけの大きさは無限）
        r.set = .plain; r.set.shell = false; r.set.eq = false
        r.cam = Camera()
        let A = shot(r); r.set.hideLabels = ["S"]; let B = shot(r)
        let m = diffMask(A, B); let cover = Double(m.filter { $0 }.count) / Double(m.count)
        check(cover > 0.999, String(format: "北極（アナ極）に立つと、南極の玉が空全体をおおう（画面の %.2f%%）", cover * 100))
    }

    // ---- 描き方を速くした時に、絵が変わっていないかを比べる（`--ref save 保存先` で保存、`--ref check 保存先` で比べる）----
    static func refScenes() -> [(String, (inout Settings, inout Camera) -> Void)] { [
        ("球層の海", { _, c in c.walk([0, 0, 1], 0.4) }),
        ("球層・立体・壮大", { s, c in s.shellSolid = true; s.grand = true; c.az = -50; c.el = 25; c.walk([0, 0, 1], 1.3) }),
        ("殻の見える距離 1・見回し", { s, c in s.shellRange = 1; c.hy = 70; c.hp = -20; c.walk([0, 0, 1], 2.2) }),
        ("南極の近く", { s, c in s.shellRange = 6; c.el = -40; c.walk([0, 0, 1], 2.9) }),
    ] }
    static func ref(_ mode: String, _ path: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let w = 960, h = 600; var all: [Float] = []
        for (_, f) in refScenes() { r.set = .plain; r.cam = Camera(); f(&r.set, &r.cam); all += r.renderOffscreen(width: w, height: h) }
        if mode == "save" { all.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: path)) }; print("保存：\(path)"); return }
        let old = try! Data(contentsOf: URL(fileURLWithPath: path)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let n = w * h * 4
        for (k, (name, _)) in refScenes().enumerated() {
            var mx: Float = 0, sum: Float = 0, big = 0
            for i in (k * n)..<((k + 1) * n) { let d = abs(all[i] - old[i]); mx = max(mx, d); sum += d; if d > 1.0 / 255 { big += 1 } }
            print(String(format: "  %@：色のちがい 最大 %.2e・平均 %.2e（0〜1 の色で）、1/255 をこえる値 %d 個（%d 画素の中）", name, mx, sum / Float(n), big, w * h))
        }
    }

    /// ウェブ版の画素との比べ：refs/ に、ウェブ版（s3walk.html、内蔵ブラウザ）で同じ場面を 429×537 で描いた画素（32 画素おき、8 ビット）を置いてある。
    ///   軽い線だけの場面は、ウェブ版が「同じ道のりの層（赤道の膜と赤道の軽い線）」の片方を丸めしだいで落とすので（web_lite.txt）、
    ///   ウェブ版の式を Python で一から計算した色（py_lite.txt、両方重ねる）と比べる
    ///   ファイル名 → 場面（アナ極から方位 az・仰角 el へ s 歩く。自分の玉だけ、極の目印は点なので無し）
    static let webScenes: [(String, String, (inout Settings, inout Camera) -> Void)] = [
        ("web_shell.txt", "球層（方位 30° へ 0.4）", { _, c in c.walk([0, 0, 1], 0.4) }),
        ("web_fish.txt", "魚眼レンズ・視野 220°（球層、方位 30° へ 0.4）", { s, c in s.lens = 1; s.fov = 220; c.walk([0, 0, 1], 0.4) }),
        ("web_pano.txt", "360° レンズ（球層、方位 30° へ 0.4）", { s, c in s.lens = 2; c.walk([0, 0, 1], 0.4) }),
        ("web_circ.txt", "経線・赤道の輪＋赤道の膜（球層なし、方位 30°・仰角 10° へ 0.7）", { s, c in s.shell = false; s.eq = true; s.circ = true; c.el = 10; c.walk([0, 0, 1], 0.7) }),
        ("web_room.txt", "120 胞体の部屋の辺（球層なし、方位 45°・仰角 −15° へ 0.5）", { s, c in s.shell = false; s.eq = false; s.room = true; c.az = 45; c.el = -15; c.walk([0, 0, 1], 0.5) }),
        ("web_crisp_shell.txt", "くっきり（線 1.8 画素）・球層（方位 30° へ 0.4）", { s, c in s.lineCrisp = true; s.lineW = 1.8; c.walk([0, 0, 1], 0.4) }),
        ("web_crisp_lite.txt", "くっきり（線 1.8 画素）・軽い線と赤道の膜（方位 30°・仰角 10° へ 1.0）", { s, c in s.lineCrisp = true; s.lineW = 1.8; s.shell = false; s.lite = true; s.webTies = true; c.el = 10; c.walk([0, 0, 1], 1.0) }),
        ("web_shell_lite.txt", "球層＋軽い線（方位 30° へ 0.4。同じ道のりの層の落とし方もウェブ版に合わせて）", { s, c in s.lite = true; s.webTies = true; c.walk([0, 0, 1], 0.4) }),
        ("py_lite.txt", "軽い線だけ（方位 30°・仰角 20° へ 1.2。refs/lite_ref.py で一から計算した色と）", { s, c in s.shell = false; s.lite = true; c.el = 20; c.walk([0, 0, 1], 1.2) }),
    ]
    /// 合わない時の手がかり探し（`--webprobe`）：軽い線だけの場面を、条件を変えて比べる
    static func webprobe(_ r: Renderer) {
        let web = try! String(contentsOf: refsDir().appendingPathComponent("web_lite.txt"), encoding: .utf8).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines))! }
        let vars: [(String, (inout Settings, inout Camera) -> Void)] = [
            ("そのまま", { s, c in s.shell = false; s.lite = true; c.el = 20; c.walk([0, 0, 1], 1.2) }),
            ("水平に歩いてから仰角", { s, c in s.shell = false; s.lite = true; c.walk([0, 0, 1], 1.2); c.el = 20 }),
            ("遠近なし", { s, c in s.shell = false; s.lite = true; s.depth = 0; c.el = 20; c.walk([0, 0, 1], 1.2) }),
            ("膜なし", { s, c in s.shell = false; s.lite = true; s.eq = false; c.el = 20; c.walk([0, 0, 1], 1.2) }),
            ("仰角 0", { s, c in s.shell = false; s.lite = true; c.walk([0, 0, 1], 1.2) }),
        ]
        for (name, f) in vars {
            r.set = .plain; r.set.poles = false; r.cam = Camera(); f(&r.set, &r.cam)
            let w = 429, h = 537, px = r.renderOffscreen(width: w, height: h)
            var k = 0, over = 0
            for y in stride(from: 10, to: h, by: 32) { for x in stride(from: 10, to: w, by: 32) { for c in 0..<3 { if abs(Int((px[(y * w + x) * 4 + c] * 255).rounded()) - web[k]) > 3 { over += 1 }; k += 1 } } }
            print("  \(name)：3 をこえる値 \(over) 個")
        }
    }
    static func refsDir() -> URL {
        // 実行ファイルの場所から、パッケージのフォルダ（refs/ がある所）を探す
        var u = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 { if FileManager.default.fileExists(atPath: u.appendingPathComponent("refs").path) { return u.appendingPathComponent("refs") }; u.deleteLastPathComponent() }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("refs")
    }
    /// 戻り値：すべての場面で、ちがいが 3 をこえる値が無いか
    @discardableResult static func webcmp(_ r: Renderer) -> Bool {
        var allOK = true
        for (file, name, f) in webScenes {
            guard let txt = try? String(contentsOf: refsDir().appendingPathComponent(file), encoding: .utf8) else { print("  ？ \(file) が無い"); continue }
            let web = txt.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines))! }
            let w = 429, h = 537
            r.set = .plain; r.set.poles = false; r.cam = Camera(); f(&r.set, &r.cam)
            let px = r.renderOffscreen(width: w, height: h)
            var k = 0, mx = 0, sum = 0, n = 0, over = 0
            for y in stride(from: 10, to: h, by: 32) { for x in stride(from: 10, to: w, by: 32) {
                var line = ""
                for c in 0..<3 { let v = Int((max(0, min(1, px[(y * w + x) * 4 + c])) * 255).rounded()); let d = abs(v - web[k]); mx = max(mx, d); sum += d; n += 1; if d > 3 { over += 1; line = "(\(x),\(y))" }; k += 1 }
                if !line.isEmpty && CommandLine.arguments.contains("--detail") { let i = (y * w + x) * 4; print("     ちがう画素 \(line)：ネイティブ \(Int(px[i] * 255)),\(Int(px[i + 1] * 255)),\(Int(px[i + 2] * 255))　ウェブ \(web[k - 3]),\(web[k - 2]),\(web[k - 1])") }
            } }
            let ok = mx <= 4; if !ok { allOK = false }   // 4 までは丸めのちがい（float の計算順）
            check(ok, String(format: "%@：%@（%d 画素 × RGB、ちがい 最大 %d・平均 %.2f、0〜255）", file.hasPrefix("py") ? "一から計算した色と同じ" : "ウェブ版と同じ色", name, n / 3, mx, Double(sum) / Double(n)))
        }
        return allOK
    }

    /// 絵のモードの確かめ（`--picstats`）：アナ極から東 +x へ 0.5 歩いて +x（🐰）を見る。玉のまわり（半径 60）の四つの角の平均の色・赤い点
    static func picStats() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        r.set = .plain; r.set.shell = false; r.set.lite = true; r.set.foot = false; r.set.mk = 1
        r.cam = Camera(); r.cam.az = 0; r.cam.walk([0, 0, 1], 0.5)
        let w = 429, h = 537, px = r.renderOffscreen(width: w, height: h)
        var q = [[Double]](repeating: [0, 0, 0, 0], count: 4); var rx = 0.0, ry = 0.0, rn = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4, R = Double(px[i]) * 255, G = Double(px[i + 1]) * 255, B = Double(px[i + 2]) * 255
            let dx = x - 214, dy = y - 268
            if dx * dx + dy * dy < 3600 { let k = (dx >= 0 ? 1 : 0) + (dy >= 0 ? 2 : 0); q[k][0] += R; q[k][1] += G; q[k][2] += B; q[k][3] += 1 }
            if R - max(G, B) > 60 && dx * dx + dy * dy < 8100 { rx += Double(dx); ry += Double(dy); rn += 1 }
        } }
        print("四つの角：", q.map { String(format: "(%.1f, %.1f, %.1f)", $0[0] / $0[3], $0[1] / $0[3], $0[2] / $0[3]) }.joined(separator: " "))
        print(rn > 0 ? String(format: "赤い点：(%.1f, %.1f) %d 画素", rx / Double(rn), ry / Double(rn), rn) : "赤い点：なし")
    }

    /// 地図の 1 コマの時間（CPU で線を作る＋GPU）（`--mapbench`）
    /// 地図の重さ：前の描き方（画面の大きさ・4 倍マルチサンプル）と、今の描き方（縦横 2 倍に描いて縮める）の GPU の時間を比べる
    /// 超球の試作の重さ：左（2 倍に描いて縮める）・右を、窓の半分くらいの大きさ（1600×2000 画素）で
    static func hyperBench() {
        // 大きさを変えて測る時：S3_BENCH="幅,高さ"（画素）
        let bsz = (ProcessInfo.processInfo.environment["S3_BENCH"] ?? "").split(separator: ",").compactMap { Int($0) }
        let bw = bsz.count == 2 ? bsz[0] : 1600, bh = bsz.count == 2 ? bsz[1] : 2000
        for (name, setup) in [("ふつう", { (s: HyperLabState) in }), ("光沢 0・座標軸なし・跡なし", { (s: HyperLabState) in s.gloss = 0; s.axes = false; s.walk = false; s.marksOn = false }), ("宇宙", { (s: HyperLabState) in s.spaceMode = 1 })] as [(String, (HyperLabState) -> Void)] {
            for side in [HyperLabRenderer.Side.left, .right] {
                let st = HyperLabState(); setup(st)
                guard let r = HyperLabRenderer(side: side, state: st, view: nil) else { continue }
                let (g, c) = r.bench(bw, bh)
                print(String(format: "%@・%@：GPU %.2f ms・CPU %.2f ms / コマ", name, side == .left ? "左" : "右", g, c))
            }
        }
        // 今いる所の印の重さ（歩いた跡つき。三人称のダイブで寄り切った所＝彗星が画面の上でいちばん大きい所も）
        for (name, cur, third) in [("印：さんぽ", 0, false), ("印：光の彗星", 1, false), ("印：線の彗星", 2, false), ("印：光の彗星・三人称", 1, true), ("印：線の彗星・三人称", 2, true)] {
            let st = HyperLabState(); st.cursor = cur
            guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { continue }
            var c = Camera(); c.az = 50; var tr: [SIMD4<Double>] = []
            for _ in 0..<120 { let L = c.lookFrame().L; c.w.p = nrm(c.w.p + L * 0.01); orthoFrame(&c.w); tr.append(c.w.p) }
            let F = c.viewFrame()
            r.walkOverride = { .init(trail: tr, pos: c.w.p, head: c.lookFrame().L, space: false, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70) }
            if third { st.diveThird = true; st.diveT = 1; st.diveManual = true; st.tickDive(0) }
            st.bump()
            let (g, cp) = r.bench(bw, bh)
            print(String(format: "%@・右：GPU %.2f ms・CPU %.2f ms / コマ", name, g, cp))
        }
        let st = HyperLabState(); if let r = HyperLabRenderer(side: .left, state: st, view: nil) {
            let t0 = CACurrentMediaTime(); for k in 0..<10 { st.zw = Double(k) * 0.05; r.buildLeftForBench() }
            print(String(format: "左の輪を作り直す（Z-W を変えた時）：%.1f ms / 回", (CACurrentMediaTime() - t0) * 100))
        }
    }
    /// 地図の色：前の描き方（画面の大きさ・4 倍マルチサンプル）と今（縦横 2 倍に描いて縮める）で同じ絵を描き、色の鮮やかさを比べる
    static func mapColorCompare(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev), let q = dev.makeCommandQueue() else { return }
        r.set = Settings(); r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 3 { r.step(1.0 / 60) }; r.walking = false
        let W = 1000, H = 1100, fmt = MTLPixelFormat.rgba16Float
        func tex(_ ms: Bool, _ f: MTLPixelFormat = fmt) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: W, height: H, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = ms ? .private : .shared
            if ms { d.textureType = .type2DMultisample; d.sampleCount = 4 }
            return dev.makeTexture(descriptor: d)!
        }
        func read(_ t: MTLTexture) -> [Float] {
            var h = [Float16](repeating: 0, count: W * H * 4)
            t.getBytes(&h, bytesPerRow: W * 8, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
            return h.map { Float($0) }
        }
        func stat(_ px: [Float]) -> String {
            var n = 0, sat = 0.0, lum = 0.0, rn = 0, rsat = 0.0, rpk = 0.0
            for i in stride(from: 0, to: px.count, by: 4) {
                let rr = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2]), mx = max(rr, g, b), mn = min(rr, g, b)
                if mx > 0.25 { n += 1; sat += (mx - mn) / mx; lum += mx }
                if rr > 0.25 && rr > g * 1.6 && rr > b * 1.6 { rn += 1; rsat += (mx - mn) / mx; rpk += rr }
            }
            return String(format: "明るい画素 %d 鮮やかさ %.3f 明るさ %.3f ／ 赤い画素 %d 鮮やかさ %.3f 明るさ %.3f", n, sat / Double(max(1, n)), lum / Double(max(1, n)), rn, rsat / Double(max(1, rn)), rpk / Double(max(1, rn)))
        }
        for slot in [0, 1] {
            let m = MapRenderer(world: r, slot: slot); m.backingScale = 2
            let out = tex(false), ms = tex(true), dep = tex(true, .depth32Float)
            var cb = q.makeCommandBuffer()!
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = out; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0x03 / 255.0, green: 0x07 / 255.0, blue: 0x12 / 255.0, alpha: 1)
            rp.depthAttachment.texture = dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
            _ = m.encode(cb, rp, fmt, 4, Double(W), Double(H)); cb.commit(); cb.waitUntilCompleted()
            let a = read(out)
            let out2 = tex(false); cb = q.makeCommandBuffer()!; m.superSample = 2; _ = m.encodeSS(cb, into: out2, fmt: fmt); cb.commit(); cb.waitUntilCompleted()
            let b = read(out2)
            print("地図 \(slot + 1) 前（そのまま＋4 倍）：" + stat(a)); print("地図 \(slot + 1) 今（2 倍に描いて縮める）：" + stat(b))
        }
    }
    static func mapSSBench() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev), let q = dev.makeCommandQueue() else { return }
        r.set = Settings(); r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 20 { r.step(1.0 / 60) }; r.walking = false
        let W = 1000, H = 1300, fmt = MTLPixelFormat.rgba16Float                        // Mac の地図の窓くらい（画素）・EDR の形式
        func tex(_ f: MTLPixelFormat, _ ms: Bool) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: W, height: H, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            if ms { d.textureType = .type2DMultisample; d.sampleCount = 4 }
            return dev.makeTexture(descriptor: d)!
        }
        let out = tex(fmt, false), msC = tex(fmt, true), msD = tex(.depth32Float, true)
        for slot in [0, 1] {
            let m = MapRenderer(world: r, slot: slot); m.backingScale = 2
            func run(_ ss: Bool) -> Double {
                var g = 0.0
                for i in 0..<40 {
                    r.cam.walk([0, 0, 1], 0.01)
                    let cb = q.makeCommandBuffer()!
                    if ss { m.superSample = 2; _ = m.encodeSS(cb, into: out, fmt: fmt) }
                    else {
                        let rp = MTLRenderPassDescriptor()
                        rp.colorAttachments[0].texture = msC; rp.colorAttachments[0].resolveTexture = out; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
                        rp.depthAttachment.texture = msD; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
                        _ = m.encode(cb, rp, fmt, 4, Double(W), Double(H))
                    }
                    cb.commit(); cb.waitUntilCompleted()
                    if i >= 10 { g += (cb.gpuEndTime - cb.gpuStartTime) * 1000 }
                }
                return g / 30
            }
            let a = run(false), b = run(true)
            print(String(format: "地図 %d：前（画面の大きさ・4 倍マルチサンプル）GPU %.2f ms/コマ、今（2 倍に描いて縮める）GPU %.2f ms/コマ（%.1f 倍）", slot + 1, a, b, b / max(0.001, a)))
        }
    }
    static func mapBench() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        r.set = Settings(); r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 20 { r.step(1.0 / 60) }; r.walking = false
        for r4 in [false, true] {
        r.set.rainbow4 = r4; r.set.mapFollow = false; r.set.map2Follow = true
        print(r4 ? "4 方向レインボー" : "レインボー")
        for (name, slot) in [("地図 1（ふつう・全体）", 0), ("地図 2（自分中心・全体）", 1)] {
            let m = MapRenderer(world: r, slot: slot); m.backingScale = 2
            _ = m.renderOffscreen(width: 1600, height: 1300)
            var cpu = 0.0, gpu = 0.0
            for _ in 0..<30 { r.cam.walk([0, 0, 1], 0.01); _ = m.renderOffscreen(width: 1600, height: 1300); cpu += m.lastCPU; gpu += m.lastGPU }
            print(String(format: "%@：CPU %.2f ms・GPU %.2f ms/コマ（1600×1300）", name, cpu / 30, gpu / 30))
        }
        }
    }

    /// 静かモードの見積もり（`--quietbench`）：あなたの設定のまま、景色の 1 コマの GPU の時間と、1 秒あたりの GPU の使用の割合（時間 × fps）
    static func quietBench() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        var us = Settings()
        if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key)?["set"] as? [String: Any] { us.load(d) }
        let (W, H) = (2800, 2000)                                 // 地図とパネルを並べた時の景色（Retina の画素）
        print("GPU：\(dev.name)　景色 \(W)×\(H)・あなたの設定")
        for (name, fps, sc, f) in [("今（60 fps・細かさ 0.9）", 60.0, 0.9, { (_: inout Settings) in }),
                                   ("60 fps・細かさ 0.5", 60.0, 0.5, { (_: inout Settings) in }),
                                   ("30 fps・細かさ 0.5", 30.0, 0.5, { (_: inout Settings) in }),
                                   ("30 fps・細かさ 0.4", 30.0, 0.4, { (_: inout Settings) in }),
                                   ("30 fps・細かさ 0.5・殻 12 まで", 30.0, 0.5, { (s: inout Settings) in s.shCap = min(s.shCap, 12) }),
                                   ("24 fps・細かさ 0.45", 24.0, 0.45, { (_: inout Settings) in }),
                                   ("4 方向レインボー・今（60 fps・0.9）", 60.0, 0.9, { (s: inout Settings) in s.shAxis = false; s.rainbow4 = true }),
                                   ("4 方向レインボー・静か（30 fps・0.4）", 30.0, 0.4, { (s: inout Settings) in s.shAxis = false; s.rainbow4 = true }),
                                   ("4 方向レインボー・静か・重ねる殻 12", 30.0, 0.4, { (s: inout Settings) in s.shAxis = false; s.rainbow4 = true; s.shCap = 12 }),
                                   ("4 方向レインボー・静か（30 fps・0.3）", 30.0, 0.3, { (s: inout Settings) in s.shAxis = false; s.rainbow4 = true }),
                                   ("4 方向レインボー・静かモードの自動（画質 0.4 × 0.78）", 30.0, 0.312, { (s: inout Settings) in s.shAxis = false; s.rainbow4 = true })] as [(String, Double, Double, (inout Settings) -> Void)] {
            r.set = us; f(&r.set); r.set.autoQ = false; r.cam = Camera(); r.cam.walk([0, 0, 1], 0.4)
            r.sceneScale = r.set.cine ? sc : 1
            let w = r.set.cine ? W : Int(Double(W) * sc), h = r.set.cine ? H : Int(Double(H) * sc)
            let ms = r.benchmark(width: w, height: h, frames: 60)
            print(String(format: "  %@：%.2f ms/コマ → GPU %.0f%%（%.0f fps）", name, ms, ms * fps / 10, fps))
        }
        // 1440p まで：画面全体（仕上げ・星を含む）を高さ 1440 相当に縮め、景色の画素の数は同じに（4K の画面 4096×2254 の景色 2800×2000 なら 0.64 倍）
        for q in [0.4, 0.5] {
            let k = 1440.0 / 2254.0, w = Int(Double(W) * k), h = Int(Double(H) * k)
            r.set = us; r.set.autoQ = false; r.cam = Camera(); r.cam.walk([0, 0, 1], 0.4)
            r.sceneScale = r.set.cine ? min(1, q / k) : 1
            let ms = r.benchmark(width: r.set.cine ? w : Int(Double(w) * q / k), height: r.set.cine ? h : Int(Double(h) * q / k), frames: 60)
            print(String(format: "  1440p まで・30 fps・画質 %.1f（景色の画素は同じ）：%.2f ms/コマ → GPU %.0f%%", q, ms, ms * 3))
        }
        r.sceneScale = 1
        r.set = us; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 8 { r.step(1.0 / 60) }; r.walking = false
        for r4 in [false, true] {
            r.set.shAxis = false; r.set.rainbow4 = r4
            let m = MapRenderer(world: r, slot: 0); m.backingScale = 2
            _ = m.renderOffscreen(width: 1000, height: 1300)
            var gpu = 0.0, cpu = 0.0
            for _ in 0..<20 { r.cam.walk([0, 0, 1], 0.01); _ = m.renderOffscreen(width: 1000, height: 1300); gpu += m.lastGPU; cpu += m.lastCPU }
            print(String(format: "  地図 1 枚（1000×1300）%@：GPU %.2f ms・CPU %.2f ms/コマ → 60 fps で GPU %.0f%%・CPU %.0f%%、20 fps で GPU %.0f%%・CPU %.0f%%", r4 ? "・4 方向レインボー" : "・レインボー", gpu / 20, cpu / 20, gpu / 20 * 6, cpu / 20 * 6, gpu / 20 * 2, cpu / 20 * 2))
        }
    }

    /// 地図の明るさ（`--mapstats`）：ウェブ版と同じ 600×500・元の向き・殻と赤道の膜だけで、平均の色・明るい画素の数・明るさの中央値
    static func mapStats() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        for glow in [0.0, 0.4] {
            r.set = Settings(); r.set.glow = glow; r.set.mapTrail = false; r.set.foot = false; r.set.mapAxes = false; r.set.poles = false; r.set.selfBall = false
            r.cam = Camera(); r.journey = Journey()
            let m = MapRenderer(world: r, slot: 0); m.backingScale = 1; m.home()
            let (px, _) = m.renderOffscreen(width: 600, height: 500)
            var sum = [0.0, 0, 0], mx = 0; var lit: [Double] = []
            for i in 0..<(600 * 500) { for c in 0..<3 { sum[c] += Double(px[i * 4 + c]); mx = max(mx, Int(px[i * 4 + c])) }
                let l = 0.3 * Double(px[i * 4]) + 0.59 * Double(px[i * 4 + 1]) + 0.11 * Double(px[i * 4 + 2]); if l > 40 { lit.append(l) } }
            lit.sort()
            print(String(format: "にじみ %.1f：平均 (%.2f, %.2f, %.2f)・最大 %d・明るい画素 %d・中央値 %.1f・90%% %.1f", glow, sum[0] / 3e5, sum[1] / 3e5, sum[2] / 3e5, mx, lit.count, lit[lit.count / 2], lit[Int(Double(lit.count) * 0.9)]))
        }
    }

    /// アプリのアイコン（`--icon 保存先.png`、1024×1024）：アプリ自身の S³ の地図（軸色の殻を重ねたもの・光る軌跡）を、宇宙の背景の角丸の板に
    static func icon(_ path: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let m = MapRenderer(world: r); m.backingScale = 1
        r.set = .plain; r.set.shellN = 6; r.set.mapAxes = false; r.set.poles = false; r.set.trailLight = true; r.set.selfBall = true
        r.startPath(.spiral); for _ in 0..<520 { r.step(1.0 / 60) }; r.pathMode = .none
        m.home()
        let S = 1024, mapS = 1200
        let (px0, _) = m.renderOffscreen(width: mapS, height: mapS)
        var px = px0
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let mapCtx = CGContext(data: &px, width: mapS, height: mapS, bitsPerComponent: 8, bytesPerRow: mapS * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        guard let mapImg = mapCtx.makeImage(), let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let inset = CGFloat(S) * 0.09, rect = CGRect(x: inset, y: inset, width: CGFloat(S) - 2 * inset, height: CGFloat(S) - 2 * inset)
        let shape = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
        ctx.addPath(shape); ctx.clip()
        let grad = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.12, green: 0.08, blue: 0.30, alpha: 1), CGColor(srgbRed: 0.01, green: 0.02, blue: 0.07, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.12), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.75, options: [.drawsAfterEndLocation])
        var x: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return CGFloat(x % 100_000) / 100_000 }
        for _ in 0..<260 { let p = CGPoint(x: rect.minX + rnd() * rect.width, y: rect.minY + rnd() * rect.height), b = rnd(), rr = b > 0.95 ? 3.0 : b > 0.8 ? 1.8 : 1.1
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25 + 0.6 * b * b)); ctx.fillEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)) }
        ctx.setBlendMode(.screen)                                          // 地図の暗い背景は、宇宙の板に溶けこませる
        let ms = rect.width * 1.12
        ctx.draw(mapImg, in: CGRect(x: rect.midX - ms / 2, y: rect.midY - ms / 2, width: ms, height: ms))
        ctx.draw(mapImg, in: CGRect(x: rect.midX - ms / 2, y: rect.midY - ms / 2, width: ms, height: ms))
        ctx.setBlendMode(.normal)
        ctx.resetClip(); ctx.addPath(shape); ctx.setStrokeColor(CGColor(srgbRed: 0.65, green: 0.55, blue: 0.98, alpha: 0.55)); ctx.setLineWidth(6); ctx.strokePath()
        guard let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
        print("アイコン：\(path)")
    }
    /// ターンの道の点を JSON で（`--turndump half|tour smooth|sharp コマ数 ds 何コマおき`）。ウェブ版の同じ道と比べる用（S³ の点・S² の点・体の前）
    static func turnDump(_ mode: String, _ sharp: Bool, _ n: Int, _ ds: Double, _ every: Int) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        r.set = .plain; r.set.turnSharp = sharp; r.startPath(mode == "half" ? .half : .tour)
        var out: [[Double]] = []
        for i in 1...n {
            r.turnStep(ds)
            if i % every == 0 { let p = r.cam.w.p, q = r.journey.w2.p, f = r.cam.w.f; out.append([p.x, p.y, p.z, p.w, q.x, q.y, q.z, f.x, f.y, f.z, f.w]) }
        }
        print("[" + out.map { "[" + $0.map { String($0) }.joined(separator: ",") + "]" }.joined(separator: ",") + "]")
    }
    /// 地図を PNG に（`--mappng 保存先のフォルダ`）。名前の札は点で印
    /// 確かめ：あなたの設定と今いる所で、地図だけを PNG に（色の見比べ用）。name：ファイル名
    static func mapUserPNG(_ path: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let m = MapRenderer(world: r); m.backingScale = 2
        if let d = UserDefaults.standard.dictionary(forKey: Store.key) {
            var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); r.set = us
            if ProcessInfo.processInfo.environment["S3_SPACE"] != nil { r.set.space = true }   // 確かめ用：宇宙の背景の時の地図
            func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
            if let p = v4("p"), let rr = v4("r"), let u = v4("u"), let f = v4("f") { r.cam.w = Walker(p: p, r: rr, u: u, f: f); orthoFrame(&r.cam.w) }
        }
        if let a = UserDefaults.standard.array(forKey: NativeSync.mapViewsKey) { NativeSync.applyMapViews([m], a) } else { m.home() }
        let w = 900, h = 900
        var (px, _) = m.renderOffscreen(width: w, height: h)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd)
        print(path, "space", r.set.space, "shAxis", r.set.shAxis, "uniL", r.set.uniL, "mapBright", r.set.mapBright, "range", r.set.mapRange)
    }
    /// 超球（Metal 版の試作）の絵：光沢なし・あり、左（リングの球）と右（球殻の超球）
    static func hyperPNG(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, gloss, glare, mode) in [("光沢なし", 0.0, false, 0), ("光沢", 1.0, false, 0), ("光沢とグレア", 1.0, true, 0), ("光沢とグレア・半透明", 1.0, true, 2),
                                           ("正面・光沢なし", 0.0, false, 0), ("正面・光沢とグレア", 1.0, true, 0), ("光沢とグレア・歩いた跡", 1.0, true, 0), ("彗星・歩いた跡", 1.0, true, 0), ("巨大彗星・歩いた跡", 1.0, true, 0), ("大彗星・歩いた跡", 1.0, true, 0), ("予定の道・歩いた跡", 1.0, true, 0), ("線の彗星・歩いた跡", 1.0, true, 0), ("極・前の丸・歩いた跡", 1.0, true, 0), ("跡・白い光・歩いた跡", 1.0, true, 0), ("極・英語・歩いた跡", 1.0, true, 0), ("同じ道・前方を消す", 1.0, true, 0), ("極・通った札・歩いた跡", 1.0, true, 0), ("光る瞬間", 1.0, true, 0), ("光る瞬間・軸の色", 1.0, true, 0), ("同じ道・消さない", 1.0, true, 0), ("跡・軸の色・宇宙・歩いた跡", 1.0, true, 0), ("極・光・宇宙・歩いた跡", 1.0, true, 0), ("4D遠近・かすみ", 1.0, true, 0), ("4D遠近・ぼかし・ワイヤー", 0.0, false, 1), ("4D遠近・両方", 1.0, true, 0), ("4D遠近・両方・宇宙", 1.0, true, 0), ("彗星・宇宙・歩いた跡", 1.0, true, 0), ("さんぽ印・歩いた跡", 1.0, true, 0), ("ZW影", 1.0, true, 0), ("ZW両方", 1.0, true, 0), ("断面カット・画面", 1.0, true, 0), ("断面カット・物体", 1.0, true, 0), ("ポリゴンカット", 1.0, true, 0), ("座標軸・プラスのみ", 1.0, true, 0), ("座標軸・立体", 1.0, true, 0), ("宇宙", 1.0, true, 0), ("宇宙・正面", 1.0, true, 0), ("宇宙・半透明・星の遠近", 1.0, true, 2), ("平面・手前", 1.0, true, 0), ("平面・x", 1.0, true, 0), ("4D切断", 1.0, true, 0), ("4D切断・宇宙", 1.0, true, 0), ("4D切断x・正面", 1.0, true, 0), ("4D切断x", 1.0, true, 0), ("ワイヤー", 0.0, false, 1), ("ワイヤー・宇宙", 1.0, true, 1), ("ハイブリッド・宇宙", 1.0, true, 0), ("ダイブ0.2", 1.0, true, 0), ("ダイブ0.45", 1.0, true, 0), ("ダイブ0.60", 1.0, true, 0), ("ダイブ0.70", 1.0, true, 0), ("ダイブ0.75", 1.0, true, 0), ("ダイブ0.50・三人称", 1.0, true, 0), ("ダイブ0.65・三人称", 1.0, true, 0), ("ダイブ0.80・三人称", 1.0, true, 0), ("ダイブ0.65", 1.0, true, 0), ("ダイブ0.8", 1.0, true, 0), ("ダイブ0.9", 1.0, true, 0), ("ダイブ0.65・軸なし", 1.0, true, 0), ("ダイブ1.00・三人称", 1.0, true, 0), ("ダイブ1.00・巨大彗星・三人称", 1.0, true, 0), ("ダイブ1.00・右へカーブ・三人称", 1.0, true, 0), ("ダイブ1.00・上へカーブ・三人称", 1.0, true, 0), ("ダイブ1.00・南へ・三人称", 1.0, true, 0), ("ダイブ0.80・南へ・三人称", 1.0, true, 0), ("ダイブ0.60・三人称", 1.0, true, 0), ("球層・4方向", 1.0, true, 0), ("球層・軸の色", 1.0, true, 0), ("球層・軸の色・ワイヤー", 0.0, false, 1)] {
            for side in [HyperLabRenderer.Side.left, .right] {
                let st = HyperLabState(); st.pitch = 0.55; st.roll = -0.35; st.gloss = gloss; st.glare = glare; st.mode = mode
                st.viewYaw = 0.5; st.viewPitch = 0.3
                if name.hasPrefix("正面") { st.pitch = 0.0203; st.roll = -0.0962; st.viewYaw = 0; st.viewPitch = 0; st.leftDist = 5.56; st.viewDist = 7.5 }   // ウェブ版の今の画面と同じ向き・大きさ
                switch name {
                case "ZW影": st.zw = 0.7; st.lzw = 1
                case "ZW両方": st.zw = 0.7; st.lzw = 2
                case "断面カット・画面": st.cutOn = true; st.cutRef = 0; st.cutAngDeg = 0; st.cutWDeg = 120
                case "断面カット・物体": st.cutOn = true; st.cutRef = 1; st.cutAngDeg = 90; st.cutWDeg = 120
                case "ポリゴンカット": st.cutOn = true; st.cutRef = 2; st.polyArm = 1; st.cutWDeg = 200
                case "彗星・歩いた跡": st.cursor = 1
                case "巨大彗星・歩いた跡": st.cursor = 3
                case "大彗星・歩いた跡": st.cursor = 4
                case "予定の道・歩いた跡": st.cursor = 1
                case "線の彗星・歩いた跡": st.cursor = 2
                case "極・前の丸・歩いた跡": st.symGlow = false; st.polesMode = 2
                case "跡・白い光・歩いた跡": st.trailCol = 1
                case "極・通った札・歩いた跡": st.polesMode = 2
                case "極・英語・歩いた跡": st.poleEN = true; st.polesMode = 2
                case "跡・軸の色・宇宙・歩いた跡": st.trailCol = 2; st.spaceMode = 1
                case "極・光・宇宙・歩いた跡": st.polesMode = 2; st.spaceMode = 1
                case "4D遠近・かすみ": st.depth4On = true; st.depth4 = 1
                case "4D遠近・ぼかし・ワイヤー": st.depth4On = true; st.depth4 = 2
                case "4D遠近・両方": st.depth4On = true; st.depth4 = 3
                case "4D遠近・両方・宇宙": st.depth4On = true; st.depth4 = 3; st.spaceMode = 1
                case "彗星・宇宙・歩いた跡": st.cursor = 1; st.spaceMode = 1
                case "球層・4方向": st.shellMode = 1
                case "球層・軸の色", "球層・軸の色・ワイヤー": st.shellMode = 2
                case "さんぽ印・歩いた跡": st.cursor = 0
                case "座標軸・プラスのみ": st.axPlus = true
                case "座標軸・立体": st.axThin = false
                case "宇宙": st.spaceMode = 1
                case "ワイヤー・宇宙", "ハイブリッド・宇宙": st.spaceMode = 1
                case "平面・手前": st.cutOn = true; st.cutKind = 1; st.planeDir = 0; st.cutPos = 0
                case "平面・x": st.cutOn = true; st.cutKind = 1; st.planeDir = 3; st.cutPos = -0.2
                case "4D切断": st.cutOn = true; st.cutKind = 2; st.cutPos = 0.3
                case "4D切断x・正面": st.cutOn = true; st.cutKind = 2; st.cut4Axis = 0; st.cutPos = 0.2; st.pitch = 0; st.roll = 0; st.viewYaw = 0.35; st.viewPitch = 0.25
                case "4D切断x": st.cutOn = true; st.cutKind = 2; st.cut4Axis = 0; st.cutPos = 0.2
                case "4D切断・宇宙": st.cutOn = true; st.cutKind = 2; st.cutPos = 0.1; st.spaceMode = 1
                case "宇宙・半透明・星の遠近": st.spaceMode = 1; st.starDepth = 0.8
                case "宇宙・正面": st.spaceMode = 1; st.pitch = 0.0203; st.roll = -0.0962; st.viewYaw = 0; st.viewPitch = 0
                default: break
                }
                st.bump()
                let (iw, ih) = name.hasPrefix("正面") ? (1024, 1536) : (900, 760)   // 正面はウェブ版の右の枠（1024×1536）と同じ形
                guard let r = HyperLabRenderer(side: side, state: st, view: nil) else { continue }
                if name.hasPrefix("ダイブ") {                                    // 少し歩いた所から、景色の向きでダイブ（宇宙モード）
                    var c = Camera(); c.az = 50; var tr: [SIMD4<Double>] = []
                    if name.contains("南へ") { c.az = 0; c.el = 0; c.w = Walker(p: SIMD4(0, 0, 0, 1), r: SIMD4(1, 0, 0, 0), u: SIMD4(0, 0, 1, 0), f: SIMD4(0, -1, 0, 0)) }   // アナ極から南極（−y）へ向かう＝天の川の中を見る
                    for _ in 0..<120 { let L = c.lookFrame().L; c.w.p = nrm(c.w.p + L * 0.01); orthoFrame(&c.w); tr.append(c.w.p) }   // 見ている向きへ 1.2 歩いた跡
                    let F = c.viewFrame()
                    r.walkOverride = { .init(trail: tr, pos: c.w.p, head: c.lookFrame().L, space: true, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70) }
                    st.diveT = Double(name.dropFirst(3).prefix(4)) ?? 0; st.spaceMode = 1; if name.hasSuffix("軸なし") { st.axesDive = false }; if name.contains("巨大彗星") { st.cursor = 3 }; if name.hasSuffix("三人称") { st.diveThird = true }; if let c = ProcessInfo.processInfo.environment["S3_CHASE"]?.split(separator: ",").compactMap({ Double($0) }), c.count == 3 { st.chaseDist = c[0]; st.chasePitch = c[1]; st.chaseYaw = c[2] }
                }
                if name.hasPrefix("同じ道") {                                     // 大きな円を 1 周半：今いる所の前に、前の周の跡が重なる
                    var tr: [SIMD4<Double>] = []
                    for k in 0...900 { let a = Double(k) / 900 * 3 * .pi; tr.append(nrm(SIMD4(sin(a) * 0.8, 0.3, cos(a) * 0.5, sin(a + 0.4) * 0.3))) }
                    let p = tr.last!, f = nrm(tr[tr.count - 1] - tr[tr.count - 2])
                    r.walkOverride = { .init(trail: tr, pos: p, fwd: f) }
                    st.clearAhead = !name.hasSuffix("消さない")
                }
                if name.hasSuffix("歩いた跡") {                                    // 螺旋の道（極めぐりの螺旋のように）を 9 歩
                    var tr: [SIMD4<Double>] = []
                    for k in 0...900 { let s = Double(k) / 100, a = s * 0.9, b = s * 0.23; tr.append(nrm(SIMD4(cos(a) * sin(b + 0.2), sin(a) * sin(b + 0.2), sin(s * 0.5) * 0.35, cos(b + 0.2)))) }
                    let mk = [tr[150], tr[420], tr[700], nrm(SIMD4<Double>(0.3, -0.6, 0.5, 0.55))]   // 目印 4 つ（はじめの 3 つは通った）
                    // 予定の道：同じ螺旋のこれから先（4 歩ぶん）
                    let plan: [SIMD4<Double>] = name.hasPrefix("予定の道") ? (900...1300).map { k in let s = Double(k) / 100, a = s * 0.9, b = s * 0.23; return nrm(SIMD4(cos(a) * sin(b + 0.2), sin(a) * sin(b + 0.2), sin(s * 0.5) * 0.35, cos(b + 0.2))) } : []
                    r.walkOverride = { .init(trail: tr, pos: tr.last!, marks: mk, hit: [true, true, true, false], poles: [0, 2], plan: plan) }   // 極はアナ極と東極を通った
                }
                st.tickDive(0)                                                   // なめらかに追う値（三人称の割合など）を、今の設定に合わせる
                if name.contains("へカーブ") {                                    // 追いかけ：まっすぐ 1 秒のあと、0.4 秒きつく曲がった所（彗星が先へ流れ、カメラはまだ傾ききらない）
                    var c = Camera(); c.az = 50; var tr: [SIMD4<Double>] = [], turn = false
                    let up = name.contains("上へ")
                    r.walkOverride = { let F = c.viewFrame(); return .init(trail: tr, pos: c.w.p, head: c.lookFrame().L, space: true, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70) }
                    st.autoCam = true
                    for i in 0..<84 {
                        turn = i >= 60
                        if turn { if up { c.el += 90.0 / 60 } else { c.az += 90.0 / 60 } }
                        let L = c.lookFrame().L; c.w.p = nrm(c.w.p + L * 0.01); orthoFrame(&c.w); tr.append(c.w.p)
                        _ = r.chaseForTest(1.0 / 60)
                    }
                }
                if name.hasPrefix("光る瞬間") {                                   // 1 枚目は「まだ」、2 枚目で「通った」に変わる（当たった瞬間の光）
                    var tr: [SIMD4<Double>] = []
                    for k in 0...600 { let s = Double(k) / 100, a = s * 0.9, b = s * 0.23; tr.append(nrm(SIMD4(cos(a) * sin(b + 0.2), sin(a) * sin(b + 0.2), sin(s * 0.5) * 0.35, cos(b + 0.2)))) }
                    let mk = [tr[150], tr[420]]
                    r.walkOverride = { .init(trail: tr, pos: tr.last!, marks: mk, hit: [true, true], poles: [0, 2]) }
                    st.polesMode = 2; if name.hasSuffix("軸の色") { st.shellMode = 2 }; st.bump()
                    let now = ProcessInfo.processInfo.systemUptime                  // 目印 2 と東極に、たった今当たった
                    Journey.hitPulse = [(mk[1], now - 0.08, -1), (FIXED[2].c, now - 0.08, 2)]
                }
                guard let img = r.image(iw, ih) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent("超球_\(name)_\(side == .left ? "左" : "右").png")
                let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d); print(url.path)
            }
        }
    }
    static func mapPNG(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let m = MapRenderer(world: r); m.backingScale = 1
        let scenes: [(String, (Renderer) -> Void)] = [
            ("地図・球層（既定、方位 30° へ 2 歩いた跡）", { r in r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 2 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・赤道の網目と軽い線（球層なし）", { r in r.set = .plain; r.set.shell = false; r.set.lite = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 4 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・軸色の球層（x・y・z・w を重ねる）", { r in r.set = .plain; r.set.shAxis = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 1 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・今いる所（宇宙の大きさ ×1）", { r in r.set = .plain; r.set.mapRange = 1; r.cam = Camera(); r.cam.walk([0, 0, 1], 1); r.journey = Journey() }),
            ("地図・今いる所（宇宙の大きさ ×30：照らす範囲が小さい）", { r in r.set = .plain; r.set.mapRange = 1; r.set.uniL = log10(30); r.cam = Camera(); r.cam.walk([0, 0, 1], 1); r.journey = Journey() }),
            ("地図・写る所（宇宙の大きさ ×30）", { r in r.set = .plain; r.set.mapRange = 2; r.set.uniL = log10(30); r.cam = Camera(); r.cam.walk([0, 0, 1], 1); r.journey = Journey() }),
            ("地図・宇宙の大きさ ×10（少し広がる・細い線）", { r in r.set = .plain; r.set.uniL = 1; r.set.mapExpand = 0.1; r.cam = Camera(); r.cam.walk([0, 0, 1], 1); r.journey = Journey() }),
            ("地図・宇宙の大きさ ×1000（1.3 倍に広がる・いちばん細い線）", { r in r.set = .plain; r.set.uniL = 3; r.set.mapExpand = 0.1; r.cam = Camera(); r.cam.walk([0, 0, 1], 1); r.journey = Journey() }),
            ("地図・光の線の軌跡（螺旋で 6 歩）", { r in r.set = .plain; r.set.trailLight = true; r.startPath(.spiral); for _ in 0..<700 { r.step(1.0 / 60) }; r.pathMode = .none }),
            ("地図・深海（もやの明るさ 0.3：殻を暗く）", { r in r.set = .plain; r.set.hazeK = 0.3; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 2 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・深海・自分中心（もやの明るさ 0.3、層 10・宇宙 ×6.5）", { r in r.set = .plain; r.set.hazeK = 0.3; r.set.mapFollow = true; r.set.shellN = 10; r.set.uniL = 0.81; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 0.4 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・深海・軸色（もやの明るさ 0.3）", { r in r.set = .plain; r.set.hazeK = 0.3; r.set.shAxis = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 1 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・あなたの設定と今いる所", { r in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); r.set = us
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let rr = v4("r"), let u = v4("u"), let f = v4("f") { r.cam.w = Walker(p: p, r: rr, u: u, f: f); orthoFrame(&r.cam.w) }
                    r.cam.az = d["az"] as? Double ?? 0; r.cam.el = d["el"] as? Double ?? 0
                    print("  p", r.cam.w.p, "uniL", r.set.uniL, "follow", r.set.mapFollow, "shAxis", r.set.shAxis, "shellN", r.set.shellN, "mapD", r.set.mapD, "expand", r.set.mapExpand, "trail", r.journey.trail.count)
                }
            }),
            ("地図・デモ：怪獣の背中（アナ極から 1.0 進んだ所）", { r in r.set = .plain; r.backDemo(0, "怪獣"); r.walking = false; r.cam.walk([0, 0, 1], 0.65) }),
            ("地図・デモ：怪獣の背中（2.6 進んだ所）", { r in r.set = .plain; r.backDemo(0, "怪獣"); r.walking = false; r.cam.walk([0, 0, 1], 2.25) }),
            ("地図・ロケットと見ている向きの矢印", { r in r.set = .plain; r.set.shell = false; r.cam = Camera(); r.journey = Journey(); r.cam.walk([0, 0, 1], 0.6); r.cam.hy = 50; r.cam.hp = 20 }),
            ("地図・光の跡を何周も（螺旋で 12 歩、残す 2π）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = true; r.set.trailKeep = 2; r.startPath(.spiral); for _ in 0..<5000 { r.step(1.0 / 60) }; r.pathMode = .none }),
            ("地図・光の跡を何周も（螺旋で 12 歩、全部）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = true; r.startPath(.spiral); for _ in 0..<5000 { r.step(1.0 / 60) }; r.pathMode = .none }),
            ("地図・超立方体の辺めぐり（32 本を全部）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = false; r.set.trailKeep = 0; r.startPath(.cube); for _ in 0..<1900 { r.turnStep(0.02) }; r.pathMode = .none }),
            ("地図・超立方体の辺めぐり・直角・傾き 0（正面の箱の中の箱）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = false; r.set.trailKeep = 0; r.set.turnSharp = true; r.set.mapXW = 0; r.set.mapYW = 0; r.set.mapZW = 0; r.startPath(.cube); for _ in 0..<2600 { r.turnStep(0.02) }; r.pathMode = .none }),
            ("地図・自分の道（アナ・東・天・(½,½,½,½)・西 を巡回、直角）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = false; r.set.trailKeep = 0; r.set.turnSharp = true; r.journey = Journey(); r.resetNorth()
                let P = RouteStore.poles; r.startCustom(CustomRoute(name: "確かめ", pts: [RoutePoint(p: P[0].1, name: P[0].0), RoutePoint(p: P[2].1, name: P[2].0), RoutePoint(p: P[6].1, name: P[6].0), RoutePoint(p: [0.5, 0.5, 0.5, 0.5], name: "(½,½,½,½)"), RoutePoint(p: P[3].1, name: P[3].0)]))
                for _ in 0..<1500 { r.crStep(0.01) }; r.pathMode = .none }),
            ("地図・自分の道・おまかせ（東・北・東の近く：北でぐるっと電球の U ターン）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = false; r.set.trailKeep = 0; r.set.turnSharp = false; r.set.routeSmart = true; r.journey = Journey(); r.resetNorth()
                let b = nrm(V4(1, 0.3, 0, 0)); r.startCustom(CustomRoute(name: "確かめ", pts: [RoutePoint(p: [1, 0, 0, 0], name: "東極"), RoutePoint(p: [0, 1, 0, 0], name: "北極"), RoutePoint(p: [b.x, b.y, b.z, b.w], name: "東の近く")]))
                for _ in 0..<700 { r.crStep(0.01) }; r.pathMode = .none }),
            ("地図・自分の道・素通り（アナ・東・天・(½,½,½,½)・西 を、止まらずに滑らかに）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = false; r.set.trailKeep = 0; r.set.routeFlow = true; r.journey = Journey(); r.resetNorth()
                let P = RouteStore.poles; r.startCustom(CustomRoute(name: "確かめ", pts: [RoutePoint(p: P[0].1, name: P[0].0), RoutePoint(p: P[2].1, name: P[2].0), RoutePoint(p: P[6].1, name: P[6].0), RoutePoint(p: [0.5, 0.5, 0.5, 0.5], name: "(½,½,½,½)"), RoutePoint(p: P[3].1, name: P[3].0)]))
                for _ in 0..<1200 { r.crStep(0.01) }; r.pathMode = .none }),
            ("地図・二十四胞体の辺めぐり（96 本を全部）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = true; r.set.trailKeep = 0; r.startPath(.cell24); for _ in 0..<5600 { r.turnStep(0.02) }; r.pathMode = .none }),
            ("地図・光の跡を近くで横から（カーブが丸い管に見えるか）", { r in r.set = .plain; r.set.shell = false; r.set.trailLight = true; r.startPath(.spiral); for _ in 0..<2500 { r.step(1.0 / 60) }; r.pathMode = .none }),
            ("地図・4 方向レインボー", { r in r.set = .plain; r.set.rainbow4 = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 1 { r.step(1.0 / 60) }; r.walking = false }),
            ("地図・自分を真ん中に", { r in r.set = .plain; r.set.mapFollow = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; while r.journey.dist < 1 { r.step(1.0 / 60) }; r.walking = false }),
        ]
        let w = 1200, h = 900
        let m2 = MapRenderer(world: r, slot: 2); m2.backingScale = 1
        let all = scenes + [("S² の仲間（螺旋で 8 歩いた跡・目印 2 つ）", { (r: Renderer) in r.set = .plain; r.startPath(.spiral); for i in 0..<900 { r.step(1.0 / 60); if i == 300 || i == 600 { r.addMark() } }; r.pathMode = .none })]
        for (k, (name, f)) in all.enumerated() {
            r.demo = nil; f(r); m.home(); m2.home()
            if name.contains("近くで横から") { m.dist = 4.2; m.pitch = 0.02 }
            let m = k == all.count - 1 ? m2 : m
            var (px, labels) = m.renderOffscreen(width: w, height: h)
            for (p, _, ok) in labels where ok { let x = Int(p.x), y = Int(p.y); for dy in -2...2 { for dx in -2...2 { let xx = x + dx, yy = y + dy; if xx >= 0 && xx < w && yy >= 0 && yy < h { let i = (yy * w + xx) * 4; px[i] = 255; px[i + 1] = 255; px[i + 2] = 255 } } } }
            let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let url = URL(fileURLWithPath: dir).appendingPathComponent("map\(k).png")
            let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
            print("\(url.path)（\(name)、名前の札 \(labels.filter { $0.2 }.map { $0.1.text }.joined(separator: " "))）")
        }
    }

    /// 東極から距離 d、(w ＋ y)／√2 の向きにずれた所で、東極の方を向いて立つ（上は z）
    static func nearEast(_ d: Double) -> Walker { Renderer.nearEast(d) }
    /// 地図に出す模型の小さな絵を、PNG に書き出す（見て確かめる用）
    static func thumbs(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        for k in 0..<9 {
            guard let img = r.modelThumb(k, size: 192) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("thumb\(k).png")
            let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
        }
    }
    /// 星雲のかたまり k の方を向く
    static func aimNeb(_ c: inout Camera, _ k: Int) {
        let b = Renderer.nebBlobs[2 * k], X = V4(Double(b.x), Double(b.y), Double(b.z), Double(b.w))
        c.face(nrm(X - c.w.p * dot4(X, c.w.p)))
    }
    /// 星雲のかたまり k から距離 d の所まで歩いて、そちらを向く
    static func nearNeb(_ c: inout Camera, _ k: Int, _ d: Double) {
        aimNeb(&c, k)
        let b = Renderer.nebBlobs[2 * k], X = V4(Double(b.x), Double(b.y), Double(b.z), Double(b.w))
        let dist = acos(max(-1, min(1, dot4(X, c.w.p))))
        if dist > d { c.walk([0, 0, 1], dist - d) }
        aimNeb(&c, k)
    }
    /// 確かめの場面を PNG に（`--png 保存先のフォルダ`）
    static func png(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let w = 1600, h = 1000
        let extra: [(String, (inout Settings, inout Camera) -> Void)] = [
            ("軽い線だけ（ウェブ版の既定の見え方）", { s, c in s.shell = false; s.lite = true; c.el = 10; c.walk([0, 0, 1], 1.0) }),
            ("4 方向レインボー（極に近い殻ほど濃く）", { s, c in s.rainbow4 = true; c.el = 10; c.az = 35; c.walk([0, 0, 1], 0.8) }),
            ("模型・怪獣（東極を 0.5 手前から）", { s, c in s.mk = 4; s.modelKind = 0; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.07) }),
            ("模型・竜（東極を 0.5 手前から）", { s, c in s.mk = 4; s.modelKind = 1; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.07) }),
            ("模型・うんこ（東極を 0.5 手前から）", { s, c in s.mk = 4; s.modelKind = 2; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.07) }),
            ("模型・怪獣を斜め前から（東極から 0.5、w と y の間）", { s, c in s.mk = 4; s.modelKind = 0; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・怪獣の遠回りの像（同じ所で後ろを向く＝向こう側の面が、180° 回って見える）", { s, c in s.mk = 4; s.modelKind = 0; s.shell = false; s.hidePair = true; s.maxD = 6.4; s.fog = 0.08; c.w = nearEast(0.5); c.az = 180 }),
            ("模型・いぬを斜め前から", { s, c in s.mk = 4; s.modelKind = 4; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・ねこを斜め前から", { s, c in s.mk = 4; s.modelKind = 5; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・たぬきを斜め前から", { s, c in s.mk = 4; s.modelKind = 6; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・きつねを斜め前から", { s, c in s.mk = 4; s.modelKind = 7; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・たこを斜め前から", { s, c in s.mk = 4; s.modelKind = 8; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・いかを斜め前から", { s, c in s.mk = 4; s.modelKind = 9; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・惑星の上のたこ（極の惑星と模型をいっしょに）", { s, c in s = Settings(); s.mk = 4; s.modelKind = 8; s.space = true; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.0) }),
            ("体験：ついてくる仲間の後ろ姿（前を見る）", { s, c in s.modelKind = 8; c.az = 25; c.el = 10; c.walk([0, 0, 1], 0.7) }),
            ("体験：ついてくる仲間の顔（振り返る）", { s, c in s.modelKind = 8; c.az = 25; c.el = 10; c.walk([0, 0, 1], 0.7) }),
            ("体験：上下反転の像（前を見る）", { s, c in s.modelKind = 9; c.az = 25; c.el = 10; c.walk([0, 0, 1], 0.7) }),
            ("体験：上下反転の像（振り返る＝ふつうの向き）", { s, c in s.modelKind = 9; c.az = 25; c.el = 10; c.walk([0, 0, 1], 0.7) }),
            ("デモ：怪獣の背中が迫ってくる・0・0.8", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：怪獣の背中が迫ってくる・0・1.8", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：怪獣の背中が迫ってくる・0・2.7", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：怪獣の背中が迫ってくる・0・1.8・振り返る", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：たこの背中が迫ってくる・7・0.8", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：たこの背中が迫ってくる・7・1.8", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：たこの背中が迫ってくる・7・2.7", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：たこの背中が迫ってくる・7・1.8・振り返る", { s, c in s = Settings(); c.az = 20 }),
            ("デモ：怪獣の背中が迫ってくる・0・2.7・宇宙 ×13", { s, c in s = Settings(); s.uniL = 1.12; c.az = 20 }),
            ("体験：ついてくる仲間の後ろ姿（前を見る）・宇宙 ×13", { s, c in s.modelKind = 8; s.uniL = 1.12; c.az = 25; c.el = 10; c.walk([0, 0, 1], 0.7) }),
            ("星：真ん中の星にたこを置く・置いた所", { s, c in s = Settings(); s.mk = 4; s.modelKind = 8; s.shell = false; s.eq = false; c.az = 60; c.el = 10 }),
            ("星：真ん中の星にたこを置く・後ろへ下がって反対側の近く", { s, c in s = Settings(); s.mk = 4; s.modelKind = 8; s.shell = false; s.eq = false; c.az = 60; c.el = 10 }),
            ("模型・竜を斜め前から", { s, c in s.mk = 4; s.modelKind = 1; s.shell = false; s.hidePair = true; c.w = nearEast(0.5); c.az = 0 }),
            ("模型・いろいろ（球層の海・映画の光、東極を 0.5 手前から）", { s, c in s = Settings(); s.mk = 4; s.modelKind = 3; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.07) }),
            ("4 方向レインボー", { s, c in s.rainbow4 = true; c.walk([0, 0, 1], 0.5) }),
            ("4 方向レインボー・立体・宇宙", { s, c in s = Settings(); s.rainbow4 = true; s.space = true; c.walk([0, 0, 1], 0.5) }),
            ("軸色の球層（x・y・z・w）", { s, c in s.shAxis = true; c.walk([0, 0, 1], 0.5) }),
            ("軸色の球層（w だけ）", { s, c in s.shAxis = true; s.shAxX = false; s.shAxY = false; s.shAxZ = false; c.walk([0, 0, 1], 0.5) }),
            ("軸色の球層・立体（x・y・z・w）", { s, c in s.shAxis = true; s.shellSolid = true; c.walk([0, 0, 1], 0.5) }),
            ("宇宙の大きさ ×10：深海・球層", { s, c in s = Settings(); s.uniL = 1; c.walk([0, 0, 1], 0.05) }),
            ("宇宙の大きさ ×100：宇宙・球層・星雲", { s, c in s = Settings(); s.space = true; s.uniL = 2; aimNeb(&c, 0) }),
            ("宇宙の大きさ ×100：深海・目印の線", { s, c in s = Settings(); s.uniL = 2; c.walk([0, 0, 1], 0.3) }),
            ("宇宙の大きさ ×100：宇宙・目印の線", { s, c in s = Settings(); s.space = true; s.uniL = 2; s.nebula = false; c.walk([0, 0, 1], 0.3) }),
            ("宇宙の大きさ ×1000：宇宙・星雲", { s, c in s = Settings(); s.space = true; s.uniL = 3; s.shell = false; aimNeb(&c, 0) }),
            ("あなたの設定・軸色（今いる所から）", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us; s.shAxis = true
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("あなたの設定・網目を 90° 倒す（今いる所から）", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us; s.gridTilt = 90
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("あなたの設定（網目そのまま、比べる）", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("比べ4：4 方向・殻 24", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us; s.shAxis = false; s.rainbow4 = true; s.shCap = 24; s.cine = false
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("比べ4：4 方向・殻 16", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us; s.shAxis = false; s.rainbow4 = true; s.shCap = 16; s.cine = false
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("比べ4：4 方向・殻 12", { s, c in
                if let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
                    var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); s = us; s.shAxis = false; s.rainbow4 = true; s.shCap = 12; s.cine = false
                    func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
                    if let p = v4("p"), let r = v4("r"), let u = v4("u"), let f = v4("f") { c.w = Walker(p: p, r: r, u: u, f: f); orthoFrame(&c.w) }
                    c.az = d["az"] as? Double ?? 30; c.el = d["el"] as? Double ?? 0
                }
            }),
            ("網目の鮮やかさ 0（前）・宇宙・球層（立体）", { s, c in s = Settings(); s.space = true; s.shellSolid = true; s.solidWire = 0.46; s.lineViv = 0; c.az = 20; c.el = 8; c.walk([0, 0, 1], 0.25) }),
            ("網目の鮮やかさ 0（前）・深海・球層", { s, c in s = Settings(); s.lineViv = 0; c.az = 20; c.el = 8; c.walk([0, 0, 1], 0.25) }),
            ("網目の鮮やかさ 0.6（新しい既定）・宇宙・球層（立体）", { s, c in s = Settings(); s.space = true; s.shellSolid = true; s.solidWire = 0.46; s.lineViv = 0.6; c.az = 20; c.el = 8; c.walk([0, 0, 1], 0.25) }),
            ("網目の鮮やかさ 0.6（新しい既定）・深海・球層", { s, c in s = Settings(); s.lineViv = 0.6; c.az = 20; c.el = 8; c.walk([0, 0, 1], 0.25) }),
            ("極の惑星：東極を見る（宇宙・映画の光）", { s, c in s = Settings(); s.space = true; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.1) }),
            ("極の惑星：軸色・球層（東極へ向かう）", { s, c in s = Settings(); s.shAxis = true; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.2) }),
            ("極の惑星：すぐそば（近いほど透ける）", { s, c in s = Settings(); s.space = true; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.57 - 0.3) }),
            ("極の惑星：画面のふち（ふちほど透ける）", { s, c in s = Settings(); s.space = true; s.shell = false; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.0); c.az += 38 }),
            ("極の惑星：宇宙の大きさ ×100（東極のそば）", { s, c in s = Settings(); s.space = true; s.uniL = 2; c.face(V4(1, 0, 0, 0)); c.walk([0, 0, 1], 1.25) }),
            ("映画の光：宇宙・星雲を見る", { s, c in s = Settings(); s.space = true; s.shell = false; s.eq = false; s.poles = false; s.hidePair = true; aimNeb(&c, 0) }),
            ("映画の光：星雲のそば（距離 0.35）", { s, c in s = Settings(); s.space = true; s.shell = false; s.eq = false; s.poles = false; s.hidePair = true; nearNeb(&c, 1, 0.35) }),
            ("映画の光：球層＋星雲", { s, c in s = Settings(); s.space = true; s.shellRange = 1.5; s.poles = false; s.hidePair = true; aimNeb(&c, 2) }),
            ("映画の光なし（比べる）：宇宙・星雲を見る", { s, c in s = Settings(); s.space = true; s.cine = false; s.shell = false; s.eq = false; s.poles = false; s.hidePair = true; aimNeb(&c, 0) }),
            ("映画の光：球層の海（深海）", { s, c in s = Settings(); c.walk([0, 0, 1], 0.9) }),
            ("映画の光なし（比べる）：球層の海（深海）", { s, c in s = Settings(); s.cine = false; c.walk([0, 0, 1], 0.9) }),
            ("宇宙：球層＋星・天の川", { s, c in s.space = true; c.walk([0, 0, 1], 0.9) }),
            ("宇宙：星だけ（天の川の方を向く）", { s, c in s.space = true; s.shell = false; s.eq = false; s.poles = false; s.hidePair = true; c.az = 90; c.el = 10 }),
            ("宇宙：星だけ（天の川を横から）", { s, c in s.space = true; s.shell = false; s.eq = false; s.poles = false; s.hidePair = true; c.az = 0; c.el = 0; c.walk([0, 0, 1], 0.6) }),
            ("宇宙：軽い線＋星", { s, c in s.space = true; s.shell = false; s.lite = true; c.el = 10; c.walk([0, 0, 1], 1.0) }),
            ("球層＋軽い線・赤い点・相棒を隠して後ろ向き", { s, c in s.lite = true; s.orient = true; s.hidePair = true; c.walk([0, 0, 1], 0.9); c.az += 180 }),
            ("光る線（にじみ 0.5）・球層の海", { s, c in s.glow = 0.5; c.walk([0, 0, 1], 0.4) }),
            ("光る線（にじみ 0.8）・球層＋軽い線", { s, c in s.glow = 0.8; s.lite = true; c.el = 10; c.walk([0, 0, 1], 1.0) }),
            ("立体の殻・網目の明るさ 0.7（新しい既定）", { s, c in s.shellSolid = true; s.solidWire = 0.7; s.glow = 0.4; c.walk([0, 0, 1], 0.4) }),
            ("立体の殻・網目の明るさ 0.35（前）", { s, c in s.shellSolid = true; s.glow = 0.4; c.walk([0, 0, 1], 0.4) }),
            ("くっきり（線 1.8 画素）・球層の海", { s, c in s.lineCrisp = true; s.lineW = 1.8; c.walk([0, 0, 1], 0.4) }),
            ("くっきり（線 1.8 画素）・球層・壮大", { s, c in s.lineCrisp = true; s.lineW = 1.8; s.grand = true; s.shellSolid = true; c.az = -50; c.el = 25; c.walk([0, 0, 1], 1.3) }),
            ("くっきり（線 1.8 画素）・軽い線と赤道の膜（球層なし）", { s, c in s.lineCrisp = true; s.lineW = 1.8; s.shell = false; s.lite = true; c.el = 10; c.walk([0, 0, 1], 1.0) }),
            ("くっきり・にじみ 0.4（新しい既定）・球層の海", { s, c in s.lineCrisp = true; s.lineW = 1.8; s.glow = 0.4; c.walk([0, 0, 1], 0.4) }),
        ]
        let only = ProcessInfo.processInfo.environment["S3_PNG_ONLY"]   // 名前にこの文字を含む場面だけ
        for (k, (name, f)) in (refScenes() + extra).enumerated() {
            if let only, !name.contains(only) { continue }
            r.demo = nil; r.set = .plain; r.cam = Camera(); r.journey = Journey(); f(&r.set, &r.cam)
            if name.hasPrefix("星：") {
                r.markAtStar()
                if name.contains("後ろへ"), let q = r.journey.marks.last { let d = acos(max(-1, min(1, dot4(q, r.cam.w.p)))); r.cam.walk([0, 0, -1], Double.pi - d - 0.35) }
                print("  星の目印", r.journey.marks.count, r.journey.marks.last.map { acos(max(-1, min(1, dot4($0, r.cam.w.p)))) } ?? -1)
            }
            if name.hasPrefix("デモ：") {
                let parts = name.components(separatedBy: "・"), k = Int(parts[1])!, d = Double(parts[2])!
                r.backDemo(k, "模型"); r.walking = false
                r.cam.walk([0, 0, 1], d - 0.35)
                if name.contains("振り返る") { r.cam.hy = 180 }
            }
            if name.hasPrefix("体験：") {
                r.experience(name.contains("仲間") ? "self" : "flip")
                if name.contains("振り返る") { r.cam.hy = 180 }
            }
            if k == 4 { var c = Camera(); for _ in 0..<5 { c.walk([0, 0, 1], 0.6); r.journey.foot.append(c.w.p) } }   // 足あとも少し
            let px = r.renderOffscreen(width: w, height: h)
            var b = [UInt8](repeating: 255, count: w * h * 4)
            for i in 0..<(w * h) { for c in 0..<3 { b[i * 4 + c] = UInt8(max(0, min(255, px[i * 4 + c] * 255 + 0.5))) } }
            let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let url = URL(fileURLWithPath: dir).appendingPathComponent("scene\(k).png")
            let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
            print("\(url.path)（\(name)）")
        }
    }

    /// あなたの設定・今いる所から、今の進む向きへまっすぐ歩きながら、何枚か描く（走り続けた時の見え方を確かめる）
    /// 確かめ：広い宇宙（×R）で、模型の目印から少し離れて前（反対側を回ってきた光の像）と後ろ（そのままの姿）を見る。もやを入れた時・入れない時
    static func bigFlip(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        let w = 640, h = 400
        for (uniL, fog, d, grow) in [(0.0, 0.0, 0.6, false), (2.0, 0.0, 0.006, false), (2.0, 0.22, 0.006, false), (2.0, 0.0, Double.pi - 0.02, false), (3.0, 0.0, 0.0006, false),
                                     (2.0, 0.22, 1.2, false), (2.0, 0.22, 1.2, true), (2.0, 0.22, 2.6, true)] {
            var s = Settings(); s.mk = 4; s.uniL = uniL; s.fog = fog; s.fade = fog > 0 ? 0.25 : 0; s.maxD = grow ? 5.9 : 2 * Double.pi; s.shell = false; s.eq = false; s.poles = false; s.selfBall = false; s.foot = false; s.markGrow = grow
            r.set = s; r.cam = Camera(); r.journey = Journey(); r.journey.marks = [r.cam.w.p]; r.journey.markKinds = [7]; r.journey.marks2 = [r.journey.w2.p]
            r.cam.walk([0, 0, 1], d)
            for (name, az) in [("前", 0.0), ("後ろ", 180.0)] {
                r.cam.az = az
                let px = r.renderOffscreen(width: w, height: h)
                var b = [UInt8](repeating: 255, count: w * h * 4)
                for i in 0..<(w * h) { for c in 0..<3 { b[i * 4 + c] = UInt8(max(0, min(255, px[i * 4 + c] * 255 + 0.5))) } }
                let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "big_L%.0f_fog%.2f_d%.4f%@_%@.png", uniL, fog, d, grow ? "_grow" : "", name))
                let dd = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd)
                print(url.lastPathComponent)
            }
        }
    }
    static func walkPNG(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev), let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) else { return }
        var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:])
        if ProcessInfo.processInfo.environment["S3_R4"] != nil { us.rainbow4 = true; us.shAxis = false; us.shell = true }   // 4 方向レインボーで見る
        r.set = us
        func v4(_ k: String) -> V4? { (d[k] as? [Double]).flatMap { $0.count == 4 ? V4($0[0], $0[1], $0[2], $0[3]) : nil } }
        if let p = v4("p"), let rr = v4("r"), let u = v4("u"), let f = v4("f") { r.cam.w = Walker(p: p, r: rr, u: u, f: f); orthoFrame(&r.cam.w) }
        r.cam.az = d["az"] as? Double ?? 30; r.cam.el = d["el"] as? Double ?? 0
        let w = 800, h = 500, step = 0.35
        for k in 0..<9 {
            let px = r.renderOffscreen(width: w, height: h)
            var b = [UInt8](repeating: 255, count: w * h * 4)
            for i in 0..<(w * h) { for c in 0..<3 { b[i * 4 + c] = UInt8(max(0, min(255, px[i * 4 + c] * 255 + 0.5))) } }
            let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let url = URL(fileURLWithPath: dir).appendingPathComponent("walk\(k).png")
            let dd = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd)
            let p = r.cam.w.p
            print(String(format: "%@　歩いた %.2f　アナ極から %.2f　p = (%.2f, %.2f, %.2f, %.2f)", url.path, Double(k) * step, acos(max(-1, min(1, p.w))), p.x, p.y, p.z, p.w))
            r.cam.walk([0, 0, 1], step)
        }
    }

    // ---- 計測：画面の外に描いて GPU の時間 ----
    static func bench(only4K: Bool = false) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { return }
        print("GPU：\(dev.name)　1 コマの GPU の時間（ミリ秒）")
        let sizes = only4K ? [(3840, 2160), (4096, 2304)] : [(1280, 800), (1920, 1080), (2560, 1600), (3456, 2234), (4096, 2304)]
        let sizes2 = ProcessInfo.processInfo.environment["S3_BENCH_NAT"] != nil ? [(1728, 1117), (3456, 2234)] : ProcessInfo.processInfo.environment["S3_BENCH_AX"] != nil || ProcessInfo.processInfo.environment["S3_BENCH_USER"] != nil ? [(1728, 1117)] : sizes
        var cases: [(String, (inout Settings) -> Void)] = [
            ("球層（殻の見える距離 3、球層の海）", { _ in }),
            ("球層（殻の見える距離 1、ウェブ版の既定）", { $0.shellRange = 1 }),
            ("球層・立体", { $0.shellSolid = true }),
            ("球層なし（玉・赤道の膜・もや）", { $0.shell = false }),
        ]
        if only4K { cases.append(("経線・赤道の輪（管）", { $0.shell = false; $0.circ = true })); cases.append(("120 胞体の部屋の辺（管）", { $0.shell = false; $0.room = true })); cases.insert(("球層 6 枚", { $0.shellN = 6 }), at: 1); cases.insert(("球層・網目なし", { $0.shellBare = true }), at: 1); cases.insert(("球層・軽い線あり", { $0.lite = true }), at: 1); cases.append(("軽い線だけ（ウェブ版の既定の見え方）", { $0.shell = false; $0.lite = true })); cases.append(("宇宙：球層＋星・天の川", { $0.space = true })); cases.append(("宇宙：星だけ", { $0.space = true; $0.shell = false })); cases.append(("宇宙＋星雲＋映画の光（星雲を見る）", { $0.space = true; $0.shell = false; $0.nebula = true; $0.cine = true; $0.glow = 0.4 })); cases.append(("宇宙＋球層＋星雲＋映画の光", { $0.space = true; $0.nebula = true; $0.cine = true; $0.glow = 0.4 })); cases.append(("深海＋映画の光", { $0.cine = true; $0.glow = 0.4 })) }
        if ProcessInfo.processInfo.environment["S3_BENCH_USER"] != nil,    // アプリに保存してある設定のままで、レインボーと軸色
           let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key)?["set"] as? [String: Any] ?? UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) {
            var us = Settings(); us.load(d); us.autoQ = false
            cases = [("あなたの設定・レインボー", { $0 = us; $0.shAxis = false; $0.rainbow4 = false }), ("あなたの設定・4 方向レインボー", { $0 = us; $0.shAxis = false; $0.rainbow4 = true }), ("4 方向・重ねる殻 12", { $0 = us; $0.shAxis = false; $0.rainbow4 = true; $0.shCap = 12 }), ("4 方向・目印の線なし", { $0 = us; $0.shAxis = false; $0.rainbow4 = true; $0.wireFloor = 0 }), ("4 方向・殻の見える距離 4", { $0 = us; $0.shAxis = false; $0.rainbow4 = true; $0.shellRange = 4 }), ("あなたの設定・軸色", { $0 = us; $0.shAxis = true }), ("あなたの設定・軸色 w だけ", { $0 = us; $0.shAxis = true; $0.shAxX = false; $0.shAxY = false; $0.shAxZ = false }), ("あなたの設定・軸色 x と w", { $0 = us; $0.shAxis = true; $0.shAxY = false; $0.shAxZ = false }), ("あなたの設定・軸色・立体でない", { $0 = us; $0.shAxis = true; $0.shellSolid = false })]
        }
        if ProcessInfo.processInfo.environment["S3_BENCH_AX"] != nil {     // 軸色の球層だけ
            cases = [("ふつうに起動（レインボー）", { $0 = Settings() }), ("軸色（x・y・z・w）", { $0 = Settings(); $0.shAxis = true }),
                     ("軸色（x・y・z・w）・殻の見える距離 11", { $0 = Settings(); $0.shAxis = true; $0.shellRange = 11 }), ("宇宙・軸色（x・y・z・w）", { $0 = Settings(); $0.shAxis = true; $0.space = true; $0.nebula = false })]
        }
        if ProcessInfo.processInfo.environment["S3_BENCH_NAT"] != nil {    // ふつうに起動した時（アプリの既定の設定）と、前の見え方
            cases = [("前の見え方（映画の光・惑星なし）", { _ in }),
                     ("ふつうに起動（深海・球層・映画の光・惑星・光る線）", { $0 = Settings() }),
                     ("宇宙（星・天の川・星雲・球層）", { $0 = Settings(); $0.space = true }),
                     ("宇宙・球層なし（星・星雲）", { $0 = Settings(); $0.space = true; $0.shell = false }),
                     ("軸色の球層（ふつうに起動＋軸の色）", { $0 = Settings(); $0.shAxis = true })]
        }
        if ProcessInfo.processInfo.environment["S3_BENCH_CINE"] != nil {   // 映画の光・星雲だけ測る
            cases = [("球層（殻の見える距離 3、球層の海）", { _ in }), ("宇宙：星だけ", { $0.space = true; $0.shell = false }),
                     ("宇宙＋星雲（映画の光なし）", { $0.space = true; $0.shell = false; $0.nebula = true }),
                     ("宇宙＋星雲＋映画の光", { $0.space = true; $0.shell = false; $0.nebula = true; $0.cine = true }),
                     ("宇宙＋球層＋星雲＋映画の光", { $0.space = true; $0.nebula = true; $0.cine = true }),
                     ("深海＋映画の光（にじみなし）", { $0.cine = true })]
        }
        print("場面".padding(toLength: 22, withPad: "　", startingAt: 0) + sizes2.map { "\($0.0)×\($0.1)" }.joined(separator: "  "))
        for (name, f) in cases {
            var line = name.padding(toLength: 22, withPad: "　", startingAt: 0)
            for (w, h) in sizes2 {
                // 3 回測って、いちばん速い値（ほかの仕事や GPU の速さの切りかえでぶれるので）
                let ms = (0..<3).map { _ -> Double in r.set = .plain; f(&r.set); r.cam = Camera(); r.cam.walk([0, 0, 1], 0.4); if r.set.nebula { aimNeb(&r.cam, 0) }; return r.benchmark(width: w, height: h) }.min()!
                line += String(format: "%9.2f  ", ms)
            }
            print(line)
        }
    }
}
