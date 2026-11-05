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
        print("== 左下のダイブ画面 ==")
        wipeChecks(nil)
        lightChecks(nil)
        wmapChecks(nil)
        do {
            var s = Settings(); s.uniL = 2
            let r0 = s.moveR; s.uniSpeed = true; let r1 = s.moveR; s.uniL = 1; let r2 = s.moveR; s.uniL = 1.24; let r3 = s.moveR
            var t = Settings(); t.shellN = 11; t.uniL = 2; let e0 = t.shellNEff; t.shellUni = true; let e1 = t.shellNEff; t.uniL = 1; let e2 = t.shellNEff; t.uniL = 3; let e3 = t.shellNEff
            check(e0 == 11 && e1 == 61 && e2 == 11 && e3 == 61, "殻を宇宙に合わせる：×100 で 11 × 100 ÷ 17 ≒ 63 → 61 で頭打ち、×10 はそのまま（\(e0)・\(e1)・\(e2)・\(e3)）")
            check(r0 == 100 && abs(r1 - Settings.uniSpeedR) < 1e-9 && r2 == 10 && abs(r3 - Settings.uniSpeedR) < 1e-9, "速さを宇宙に合わせる：×100 でも進む角度は ×17 の時のまま、×10 はそのまま（\(String(format: "%.1f・%.1f・%.1f・%.1f", r0, r1, r2, r3))）")
        }
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
            let wind = s.renderTest(seconds: 1, speed: 0.75, zoom: 1)
            check(bell.peak > wind.rms * 1.2, String(format: "音：チャイムの山が走る音の大きさより上にある（チャイム %.2f・走る音 %.2f）", bell.peak, wind.rms))
            let farFull = s.renderTest(seconds: 1, speed: 0.7, zoom: 1), farSoft = s.renderTest(seconds: 1, speed: 0.7, zoom: 1, fade: 0.2), farOld = s.renderTest(seconds: 1, speed: 0.7, zoom: 0)
            check(farSoft.rms > farOld.rms * 1.5 && farSoft.rms < farFull.rms * 0.6, "ダイブの外の走る音は、ダイブより小さく、今までの外の音より聞こえる（ダイブ \(String(format: "%.3f", farFull.rms))・外 \(String(format: "%.3f", farSoft.rms))・今まで \(String(format: "%.3f", farOld.rms))）")
            s.tune(height: 0, place: 0, bass: 2.5); let boost = s.renderTest(seconds: 1, speed: 1, zoom: 1); s.tune(height: 0, place: 0, bass: 1)
            check(boost.rms > dive.rms * 1.02 && boost.peak <= 1, "音：低音を強くすると大きくなり、割れない（\(dive.rms) → \(boost.rms)）")
            s.tune(height: 0, place: 0, bass: 1, phones: true); let hp = s.renderTest(seconds: 1, speed: 1, zoom: 1), hp7 = s.renderTest(seconds: 1, speed: 0.7, zoom: 1)
            s.tune(height: 0, place: 0, bass: 1, rough: 0, phones: true); let hp0 = s.renderTest(seconds: 1, speed: 0.7, zoom: 1); s.tune(height: 0, place: 0, bass: 1)
            check(abs(hp7.rms - hp0.rms) > 0.001 && hp.peak <= 0.99, "音：ヘッドホン用はガラララが鳴り、割れない（なし \(hp0.rms) → あり \(hp7.rms)、最高速の山 \(hp.peak)）")
            s.tune(height: 0, place: 0, bass: 1, rush: 1); let rs = s.renderTest(seconds: 1, speed: 1, zoom: 1); s.tune(height: 0, place: 0, bass: 1)
            var ru = 0.0; for _ in 0..<420 { ru = HyperSound.rushStep(ru, swing: 0.02, speed: 1, dt: 1.0 / 60) }
            let ruUp = ru; for _ in 0..<90 { ru = HyperSound.rushStep(ru, swing: 0.5, speed: 1, dt: 1.0 / 60) }
            let aimOK = HyperSound.poleAim(SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)) > 0.99 && HyperSound.poleAim(SIMD4(0, 0, 1, 0), SIMD4(1, 0, 0, 0)) < 0.01
            check(aimOK && rs.rms > dive.rms && rs.peak <= 0.99 && ruUp > 0.85 && ru < 0.05, "音：直線で伸びて、曲がると戻る（\(dive.rms) → \(rs.rms)、山 \(rs.peak)、7 秒で \(String(format: "%.2f", ruUp))、カーブ 1.5 秒で \(String(format: "%.2f", ru))）")
            do {   // 空気：ナビエ・ストークスの渦とコースター
                let ar = AirSim(); var ls: [Float] = []
                for i in 0..<600 { ar.tick(speed: 0.6, cross: 0); if i >= 240 { ls.append(ar.lift) } }
                let me = ls.reduce(0, +) / Float(ls.count); var zc = 0
                for i in 1..<ls.count where (ls[i - 1] - me) * (ls[i] - me) < 0 { zc += 1 }
                let al = AirSim(); var lp: Float = 0, ln: Float = 0
                for _ in 0..<420 { al.tick(speed: 0.6, cross: 0.6); lp += al.lift }; for _ in 0..<420 { al.tick(speed: 0.6, cross: -0.6); ln += al.lift }
                var hiM = 0.0, loM = 0.0, peak = 0.0, sum = 0.0, n = 0.0
                if let cr = Renderer(device: MTLCreateSystemDefaultDevice()!) {
                    cr.resetNorth(); cr.walking = true; cr.autoSpeed = 1; cr.coastOn = true
                    for _ in 0..<300 { cr.cam.w.p = SIMD4(0, 0, 0, 1); cr.step(1.0 / 60) }; hiM = cr.coastM
                    for _ in 0..<300 { cr.cam.w.p = SIMD4(0, 0, 0, -1); cr.step(1.0 / 60) }; loM = cr.coastM
                    cr.coastOn = false; cr.meriK = 1; cr.topK = 1.6; cr.resetNorth(); cr.walking = true; cr.autoSpeed = 1; for _ in 0..<60 { cr.step(1.0 / 60) }
                    for i in 0..<21600 { cr.step(1.0 / 60); peak = max(peak, cr.coastM); if i > 7200 { sum += cr.coastM; n += 1 } }   // まっすぐ 6 分
                }
                check(zc >= 6 && lp > 0 && ln < 0 && hiM < 0.6 && loM > 1.1 && peak < 1.6 && abs(sum / max(1, n) - 1) < 0.12, "空気：カルマン渦で揚力がゆれ（\(zc / 2) 往復）、横風の向きで力が変わる。コースターはアナ極で ×\(String(format: "%.2f", hiM))・カタ極で ×\(String(format: "%.2f", loM))。直線の最高は ×\(String(format: "%.2f", peak))で上がり続けず、平均 ×\(String(format: "%.2f", sum / max(1, n)))")
            }
            do {   // らくらく書き出し：周の道のりを測る
                let ex = VideoExport.shared, kp = ex.genPath, set0 = Settings()
                ex.genPath = PathMode.tour.rawValue
                let l1 = MTLCreateSystemDefaultDevice().map { ex.lapDistance($0, set0).0 ?? 0 } ?? 0
                ex.genPath = kp
                let mg = EasyExport.merged([[0.1, 0.3], [0.5, 0.7]], 0.25, 0.55), mg2 = EasyExport.merged([[0.1, 0.3]], 0.6, 1)
                check(mg == [[0.1, 0.7]] && mg2 == [[0.1, 0.3], [0.6, 1]], "らくらく書き出し：ダイブの区間は重なるとまとまり、離れていれば別の区間のまま")
                let rm = EasyExport.removed([[0, 1]], 0.3, 0.5), rm2 = EasyExport.removed(rm, 0.7, 0.8), rm3 = EasyExport.removed([[0.35, 0.45], [0.6, 0.8]], 0.3, 0.5)
                let fl = EasyExport.flipped([[0.1, 0.3], [0.6, 1]], at: 0.2), fl2 = EasyExport.flipped([[0.1, 0.3], [0.6, 1]], at: 0.4), fl3 = EasyExport.flipped([], at: 0.4)
                check(rm == [[0, 0.3], [0.5, 1]] && rm2 == [[0, 0.3], [0.5, 0.7], [0.8, 1]] && rm3 == [[0.6, 0.8]], "らくらく書き出し：ダイブなしを塗ると、ダイブの区間が分かれて何か所でも入る")
                check(fl == [[0.6, 1]] && fl2 == [[0.1, 1]] && fl3 == [[0, 1]], "らくらく書き出し：バーを押すと、その区間の色が反対になる")
                check(l1 > 3, "らくらく書き出し：1 周の道のりを測れる（\(String(format: "%.2f", l1))）。小数の周はこの道のりで止める")
            }
            do {   // R の世界を滑らかに降りる
                let sg = HyperLabState(); sg.noSink = true; sg.worldR = 0.6; sg.glideDir = -1
                var last = 0.6, maxStep = 0.0, up = true, t = 0.0
                while t < 30 { sg.tickGlide(1.0 / 60); maxStep = max(maxStep, last - sg.worldR); if sg.worldR > last + 1e-12 { up = false }; last = sg.worldR; t += 1.0 / 60 }
                let landed = sg.worldR == 0.05 && sg.glideDir == 0
                sg.glideDir = 1; for _ in 0..<120 { sg.tickGlide(1.0 / 60) }; sg.glideDir = 0; for _ in 0..<300 { sg.tickGlide(1.0 / 60) }
                let stopped = sg.worldR > 0.05 && sg.worldR < 0.2 && sg.glideV == 0
                check(landed && up && maxStep <= HyperLabState.glideMax / 60 * 1.01 && stopped, "R の世界：▼ でなめらかに降りて R 0.05 に着地し（1 コマの最大 \(String(format: "%.4f", maxStep))）、▲ で上り、■ ですっと止まる（R \(String(format: "%.3f", sg.worldR))・着地 \(landed)・止まった \(stopped)）")
            }
            check(VideoExport.stopLimit(0) == 1200 && VideoExport.stopLimit(3) == 180, "止めるタイマー：3 分で 180 秒、なしなら 20 分で止める")
            do {   // 道の保存と呼び出し
                var ok = false
                if let cr = Renderer(device: MTLCreateSystemDefaultDevice()!) {
                    cr.startTourFlow(show: true)
                    let rt = cr.savableRoute, one = rt.map { RouteStore.merged([], name: "朝の道", $0) }, two = one.flatMap { o in rt.map { RouteStore.merged(o.routes, name: "朝の道", $0) } }
                    let three = two.flatMap { o in rt.map { RouteStore.merged(o.routes, name: "夜の道", $0) } }
                    let data = (try? JSONEncoder().encode(three?.routes ?? [])) ?? Data(), back = (try? JSONDecoder().decode([CustomRoute].self, from: data)) ?? []
                    if let s = one?.saved { cr.stopWalking(); cr.pickRoute(s); cr.walkFromHere() }
                    ok = rt?.flow == true && two?.routes.count == 1 && two?.saved.id == one?.saved.id && back.count == 2 && back[0].flow == true && cr.pathMode == .custom && cr.cr.title == "朝の道"
                }
                check(ok, "道の保存：今の道を名前で保存（同じ名前は入れかえ、別の名前は足す）。保存の形で戻せて、呼び出して歩ける")
            }
            do {   // さんぽの歩く・停止・最初から
                var ok = false, gap = 9.0
                if let cr = Renderer(device: MTLCreateSystemDefaultDevice()!) {
                    cr.startTourFlow(show: true); for _ in 0..<600 { cr.step(1.0 / 60) }
                    cr.stopWalking(); let stopped = cr.pathMode == .none, here = cr.cam.w.p, lap0 = cr.journey.lap
                    cr.walkFromHere(); cr.step(1.0 / 60); gap = acos(max(-1, min(1, dot4(here, cr.cam.w.p))))
                    let walked = cr.pathMode == .custom && cr.lastRoute?.pts.first?.p == Renderer.tourPoints(show: true).first?.p
                    for _ in 0..<120 { cr.step(1.0 / 60) }
                    cr.restartRoute(); let atStart = cr.cam.w.p.w > 0.999 && cr.pathMode == .custom && cr.journey.lap == 1
                    ok = stopped && walked && gap < 0.05 && atStart && lap0 >= 1
                }
                check(ok, "さんぽ：停止で止まり、歩くでその場から道を作り直し（飛び \(String(format: "%.3f", gap))）、最初からで ① に戻る")
            }
            do {   // 極のドップラー：アナ極へ近づくと高く前から、離れると低く後ろから。カタ星は前後が反対
                let ed = sin(0.3), ec = cos(0.3), R = SIMD4<Double>(1, 0, 0, 0), U = SIMD4<Double>(0, 1, 0, 0)
                let pA = SIMD4<Double>(0, 0, ed, ec), hIn = SIMD4<Double>(0, 0, -ec, ed)
                let inA = HyperSound.flyPass(pA, head: hIn, right: R, up: U, feel: 1), outA = HyperSound.flyPass(pA, head: -hIn, right: R, up: U, feel: 1)
                let pK = SIMD4<Double>(0, 0, ed, -ec), hK = SIMD4<Double>(0, 0, -ec, -ed), inK = HyperSound.flyPass(pK, head: hK, right: R, up: U, feel: 1)
                let far = HyperSound.flyPass(SIMD4(0.70710678, 0, 0, 0.70710678), head: SIMD4(-0.7, 0, 0.7, 0), right: R, up: U, feel: 1)
                let quiet = s.renderTest(seconds: 1, speed: 0.5, zoom: 1), loud = s.renderTest(seconds: 1, speed: 0.5, zoom: 1, fly: 1.5)
                check(inA.hz > outA.hz * 1.5 && inA.at.z < 0 && outA.at.z > 0 && inK.at.z > 0 && inK.amp > 0.5 && far.amp < 0.01 && loud.rms > quiet.rms && loud.peak <= 1.2, "星の音：アナ極へ近づくと高く前から（\(Int(inA.hz)) Hz）、離れると低く後ろから（\(Int(outA.hz)) Hz）、カタ星は近づく時に後ろから、遠いと鳴らず、割れない（山 \(loud.peak)）")
            }
            let spR = s.renderTest(seconds: 1, speed: 1, zoom: 1, at: SIMD3(1.5, 0, 0)), spL = s.renderTest(seconds: 1, speed: 1, zoom: 1, at: SIMD3(-1.5, 0, 0))
            check(spR.rmsR > spR.rms * 1.1 && spL.rms > spL.rmsR * 1.1 && spR.peak < 1,   // 低い音が多いので、左右の差は 1 割ほど（低い音ほど耳の差が小さい。高いパチパチを消したので前より小さい）
                  String(format: "空間オーディオ：右から鳴らすと右の耳 %.3f > 左 %.3f、左から鳴らすと左 %.3f > 右 %.3f（割れない）", spR.rmsR, spR.rms, spL.rms, spL.rmsR))
            if let dir = ProcessInfo.processInfo.environment["S3_SNDWAV"] {     // 聞いて確かめる用：風切り音を wav に
                for (n, sp, z, tr) in [("1_遅い", 0.4, 0.0, 0.0), ("2_速い", 1.0, 0.0, 0.0), ("3_ズーム", 1.0, 1.0, 0.0), ("4_ズーム右へ曲がる", 1.0, 1.0, 1.0), ("5_ズーム中くらい", 0.6, 1.0, 0.0)] {
                    _ = s.renderTest(seconds: 4, speed: sp, zoom: z, turn: tr, wav: dir + "/風切り_\(n).caf")
                }
            }
            let icy = s.renderTest(seconds: 0.5, speed: 0, zoom: 1, iceAt: 0.05), icyNo = s.renderTest(seconds: 0.5, speed: 0, zoom: 1)
            check(icy.rms > 0.005 && icy.rms > icyNo.rms * 10 && icy.peak < 0.95, String(format: "シュパッ：止まっていても聞こえる（%.4f、鳴らさないと %.5f）、割れない（いちばん大きい値 %.2f）", icy.rms, icyNo.rms, icy.peak))
            if let dir = ProcessInfo.processInfo.environment["S3_SNDWAV"] { _ = s.renderTest(seconds: 2, speed: 0.8, zoom: 1, turn: 0.6, iceAt: 0.5, wav: dir + "/シュパッ.caf") }
            check(still.rms < 1e-4 && slow.rms > still.rms && fast.rms > slow.rms && dive.rms > fast.rms * 1.5 && dive.peak < 0.99 && turn.rms > dive.rms && turn.rms < dive.rms * 2.6 && turn.peak < 0.99 && bell.rms > 0.01 && fast.rms < dive.rms * 0.08 && bellFar.rms > bell.rms * 0.8,
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
                let okA: Bool = s0 < 1e-6 && l1 > 0.12 && b1 < b2 * 0.45 && b2 > 0.25
                let okB: Bool = l3 < 0.02 && b3 < b2 * 0.2 && h0 < 1e-6 && h1 > 0.5 && h3 < 0.02
                check(okA && okB,
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
        // 体の右と同じ向きへ進む道（y の − の地極へ）・正反対の点が続く道：体の向きが壊れない（地図・景色・保存がみんな止まる）
        do {
            func idx(_ n: String) -> Int { RouteStore.poles.firstIndex { $0.0 == n } ?? 0 }
            let rt = CustomRoute(name: "確かめ", pts: ["アナ極", "カタ極", "地極"].map { n in RoutePoint(p: RouteStore.poles[idx(n)].1, name: n) })
            var bad = -1, cnt = 0
            func ok(_ v: V4) -> Bool { (v.x + v.y + v.z + v.w).isFinite }
            for flow in [true, false] {
                r.set = .plain; r.set.routeFlow = flow; r.resetNorth(); r.journey = Journey(); r.startCustom(rt)
                for i in 0..<30000 where r.pathMode == .custom {
                    r.crStep(0.02); cnt += 1
                    let w = r.cam.w
                    if !(ok(w.p) && ok(w.f) && ok(w.r) && ok(w.u)) { bad = i; break }
                }
                if bad >= 0 { break }
                r.pathMode = .none
            }
            r.pathMode = .none; r.set = .plain; r.resetNorth(); r.journey = Journey()
            check(bad < 0, "体の右と同じ向きへ進む道・正反対の点が続く道でも、体の向きが壊れない（\(cnt) 歩。壊れた所 \(bad)）")
            // 壊れた向きが保存されていても、読み直した時に作り直す（景色に線も星も出なくなる）
            var fixedOK = true
            for p in [V4(0, 0, 0.987, -0.159), V4(0, 0, 0, 1), V4(0.5, 0.5, 0.5, 0.5), V4(0, 1, 0, 0)] {
                var d = Store.snapshot(r), nan = [Double](repeating: .nan, count: 4)
                d["p"] = Store.arr(nrm(p)); d["r"] = nan; d["u"] = nan; d["f"] = nan; nan = []
                Store.applyPosition(r, d)
                let w = r.cam.w, off = [dot4(w.p, w.f), dot4(w.p, w.r), dot4(w.p, w.u), dot4(w.f, w.r), dot4(w.f, w.u), dot4(w.r, w.u)].map(abs).max() ?? 1
                if !(ok(w.f) && ok(w.r) && ok(w.u)) || off > 1e-9 || simd_double4x4(rows: [w.r, w.u, w.f, w.p]).determinant < 0 { fixedOK = false }
            }
            r.resetNorth()
            check(fixedOK, "壊れた体の向きが保存されていても、読み直す時に今いる所から作り直す")
        }
        // 切りかえの順番：左をすばやく黒くする → 右の画面が変わる → 左の中身を入れかえて出す。ぱっと切りかえる時も左は黒を通る
        do {
            let s0 = HyperLabState(), dt = 1.0 / 60; s0.diveOn = true
            func order() -> Bool {
                let z0 = s0.diveT, p0 = s0.paneDive
                func run(_ n: Int) { for _ in 0..<n { s0.tickDive(dt) } }
                let now = s0.paneBlack                                     // 押した瞬間から黒
                run(5)
                let first = now && s0.paneCover > 0 && s0.diveT == z0
                run(10)
                let black = s0.paneCover == 1, wait = s0.paneDive == p0
                run(30)
                let zoom = s0.diveT != z0, dark = s0.paneCover == 1 && s0.paneDive == p0
                var n = 0
                while s0.diveT != (s0.diveOn ? 1 : 0) && n < 400 { run(1); n += 1 }
                run(3)
                let swapped = s0.paneDive != p0 && s0.paneCover == 1
                run(40)
                return first && black && wait && zoom && dark && swapped && s0.paneCover == 0 && !s0.paneBusy
            }
            let inOK = order()
            s0.diveOn = false
            let outOK = order()
            func cut(_ on: Bool) -> Bool {                                 // ぱっと切りかえる：右はすぐ変わり、左は黒を通って入れかわる
                let c = HyperLabState(); c.diveOn = !on; c.diveT = on ? 0 : 1; c.paneDive = !on
                c.diveOn = on; c.diveT = on ? 1 : 0
                let now = c.paneBlack
                for _ in 0..<5 { c.tickDive(dt) }
                let early = c.paneCover > 0 && c.paneCover < 1 && c.paneDive != on
                var k = 0, black = false
                while c.paneDive != on && k < 60 { c.tickDive(dt); black = c.paneCover == 1; k += 1 }
                for _ in 0..<40 { c.tickDive(dt) }
                return now && early && black && c.paneDive == on && c.paneCover == 0 && !c.paneBusy
            }
            let m = HyperLabState(); m.diveManual = true; m.diveOn = true; m.diveT = 0.6; m.tickDive(dt)   // スライダーを手で動かす間は、黒くしない
            check(inOK && outOK && cut(true) && cut(false) && m.paneDive && m.paneCover == 0, "切りかえの順番：左をすばやく黒くする → 右の画面が変わる → 左の中身を入れかえて出す。入る時も出る時も同じ。ぱっと切りかえる時も左は黒を通る。スライダーを手で動かす時は、すぐ変わる")
            let sz = HyperLabState(); sz.diveManual = true; sz.thirdK = 1; sz.showFrame = SIMD2(0.3, 0.2); sz.showRoll = 0.3
            if let r = HyperLabRenderer(side: .right, state: sz, view: nil) {  // ズームの始まりと終わりで、カメラのずらしと傾きが飛ばない
                sz.diveT = 0; let a = r.camBasis(); sz.diveT = 0.002; let b = r.camBasis()
                check(simd_distance(a.0, b.0) < 0.01 && simd_distance(a.1, b.1) < 0.01, String(format: "ズームの端でカメラが飛ばない：ショーカメラの構図があっても %.4f", simd_distance(a.0, b.0)))
            }
            do {   // 渦の歌：流体の渦で音色が変わり、速いほど大きく、割れない
                let ar = AirSim(); var r0: [Float] = [], r1: [Float] = []
                for i in 0..<420 { ar.tick(speed: 0.7, cross: 0); if i == 360 { r0 = ar.ring() }; if i == 419 { r1 = ar.ring() } }
                let moved = zip(r0, r1).map { abs($0 - $1) }.reduce(0, +) / 64
                let snd = HyperSound.shared; snd.setScan(r1); snd.tune(height: 0, place: 0, bass: 1, song: 1, wind: 0)
                let a = snd.renderTest(seconds: 1, speed: 0.4, zoom: 1), b = snd.renderTest(seconds: 1, speed: 0.8, zoom: 1, wav: ProcessInfo.processInfo.environment["S3_SONG_WAV"])
                snd.tune(height: 0, place: 0, bass: 1, rush: 1, song: 1, wind: 0.5); let c = snd.renderTest(seconds: 1, speed: 0.8, zoom: 1); snd.tune(height: 0, place: 0, bass: 1)
                check(moved > 0.05 && b.rms > a.rms * 1.2 && b.rms > 0.1 && c.peak <= 1, String(format: "渦の歌：渦で波形が動き（%.2f）、速いほど大きい（%.3f → %.3f）、風と直線を足しても山 %.2f で割れない", moved, a.rms, b.rms, c.peak))
            }
            do {   // 線路の音：かすかに鳴る
                let snd = HyperSound.shared; snd.tune(height: 0, place: 0, bass: 1, rail: 1); snd.railTick()
                let r = snd.renderTest(seconds: 0.3, speed: 0, zoom: 1); snd.tune(height: 0, place: 0, bass: 1)
                check(r.peak > 0.02 && r.peak < 0.2, String(format: "線路の音：矢印を通るとかすかに鳴る（山 %.3f）", r.peak))
            }
            do {   // シースルー：左の絵の右端が、右の窓の左端のすぐ隣、反転する時は右の窓の右端のすぐ隣
                let c0 = HyperLabRenderer.seeClipX(rw: 800, lw: 600, gap: 6, flip: false), c1 = HyperLabRenderer.seeClipX(rw: 800, lw: 600, gap: 6, flip: true)
                let e = 1 + 2 * 6.0 / 800, w = 2 * 600.0 / 800
                check(abs(c0.a * -e + c0.b - 1) < 1e-9 && abs(c0.a * (-e - w) + c0.b + 1) < 1e-9 && abs(c1.a * e + c1.b + 1) < 1e-9 && abs(c1.a * (e + w) + c1.b - 1) < 1e-9, "シースルー：左の絵は仕切りをはさんで右の窓の隣につながる（反転の時も）")
                let sq = HyperLabState(); sq.seeThrough = true; sq.diveOn = true
                var seen = false, swappedDark = false
                for _ in 0..<500 { sq.tickDive(1.0 / 60); seen = seen || sq.paneSee; if sq.paneDive && sq.paneCover == 1 { swappedDark = true } }
                check(seen && swappedDark && sq.paneDive && !sq.paneSee && sq.paneSeeA == 0 && !sq.paneBusy, "シースルー：変形の間だけ透かして、終わったら地図へ入れかえる")
            }
            do {   // 向きから作る道：方位・仰角の決まりと、アナの体の向きがそろう
                func near(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }
                var c = Camera(); c.az = 30; c.el = 0
                let l = c.lookFrame().L, d30 = RouteStore.dirPoint(az: 30, el: 0)
                check(near(RouteStore.dirPoint(az: 0, el: 0), [1, 0, 0, 0]) && near(RouteStore.dirPoint(az: 90, el: 0), [0, 1, 0, 0]) && near(RouteStore.dirPoint(az: 45, el: -90), [0, 0, -1, 0]) && near(d30, [l[0], l[1], l[2], l[3]]), "向きから作る道：方位 0 が東、90 が北、仰角 −90 が地。アナの体の向きと同じ決まり")
            }
            do {   // 丸い大円のプリセット：どれも直交する 2 本の軸の面で、反対の点を通る 1 周
                var ok = RouteStore.circles.count == 6
                for c in RouteStore.circles {
                    let p = c.1.map { RouteStore.poles[$0].1 }
                    func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).map { $0 * $1 }.reduce(0, +) }
                    ok = ok && dot(p[0], p[1]) == 0 && dot(p[0], p[2]) == -1 && dot(p[1], p[3]) == -1 && dot(p[2], p[3]) == 0
                }
                check(ok, "丸い大円のプリセット：6 本とも直交する軸の面を 1 周する")
                let fs = RouteStore.fullSet.map { RouteStore.poles[$0].1 }
                var legs = true
                for k in 0..<fs.count {
                    let a = fs[k], b = fs[(k + 1) % fs.count]
                    var d = 0.0
                    for j in 0..<4 { d += a[j] * b[j] }
                    if d != 0 { legs = false }
                }
                check(fs.count == 27 && fs.count <= RouteStore.maxPts && legs, "大円フルセット：6 本を 27 点で 1 周ずつ、どの区間も 90°")
            }
            do {   // 超球デモ：真正面で始まり、赤玉を表へ出して、真正面へ戻る
                let p0 = HyperLabState.demoPose(0), p1 = HyperLabState.demoPose(24), p2 = HyperLabState.demoPose(HyperLabState.demoLen - 2), k = HyperLabState.demoKeys
                var inc = true; for i in 1..<k.count where k[i][0] <= k[i - 1][0] { inc = false }
                check(inc && p0[0] == 0 && p0[1] == 0 && abs(p1[0] + 90) < 1e-9 && p2[0] == 0 && p2[1] == 0 && HyperLabState.demoLen > 55 && HyperLabState.demoLen < 80, "超球デモ：真正面から赤玉を表へ出して、真正面へ戻る（約 1 分強）")
            }
            do {   // 超球（試作）：殻の広がり 2π²r³ を足すと超球の体積 π²/2。殻は 10 枚、最後の 0.1 まで
                var sum = 0.0; let n = 20000
                for i in 0..<n { let r = (Double(i) + 0.5) / Double(n); sum += 2 * .pi * .pi * r * r * r / Double(n) }
                var w = 0.0
                for i in 0..<n { let t = -1 + 2 * (Double(i) + 0.5) / Double(n); w += 4.0 / 3 * .pi * pow(1 - t * t, 1.5) * 2 / Double(n) }
                let s = HyperLabState(); s.fillA = 0; let c = s.fillShells(); s.fillA = 1
                check(abs(sum - HyperLabState.fillVolume(0)) < 1e-6 && abs(w - HyperLabState.fillVolume(0)) < 1e-5 && abs(HyperLabState.fillVolume(0.5) / HyperLabState.fillVolume(0) - 0.9375) < 1e-12 && c.count == 10 && s.fillShells().count == 1, String(format: "超球の積分：超球面の積み重ねも輪切りも π²/2（%.5f・%.5f）", sum, w))
            }
            do {   // 超立方体の 8 部屋：まっすぐ 4 部屋で元の所へ。辺のまわりは 3 部屋で、向きが 90° ずれる。部屋の中心は 8 つの極
                var c = TWFrame.start; let c0 = c, n = TWFrame.move(&c, c.f, 8)
                func near(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> Bool { simd_length(a - b) < 1e-9 }
                let ring = n == 4 && near(c.p, c0.p) && near(c.f, c0.f) && near(c.u, c0.u) && near(c.r, c0.r)
                var e = TWFrame(p: [0.5, 0.5, 0, 1], r: [0, -1, 0, 0], u: [0, 0, 1, 0], f: [1, 0, 0, 0], a: 3, s: 1)
                var seen = [e.room], cross = 0
                for d in [SIMD4<Double>(1, 0, 0, 0), [0, 1, 0, 0], [0, 0, 0, 1]] { cross += TWFrame.move(&e, d, 1); seen.append(e.room) }
                let edge = cross == 3 && near(e.p, [0.5, 0.5, 0, 1]) && near(e.f, [0, 1, 0, 0]) && near(e.u, [0, 0, 1, 0]) && Set(seen).count == 3
                let poles = (0..<4).allSatisfy { a in [1.0, -1.0].allSatisfy { s in FIXED[TWFrame(p: .zero, r: .zero, u: .zero, f: .zero, a: a, s: s).room].c[a] == s } }
                var w = TWFrame.start, sane = true
                for i in 0..<400 { let t = Double(i); w.turn(0.7 + sin(t), 0.4 * cos(t * 0.7)); _ = TWFrame.move(&w, w.f, 0.37); let q = [w.r, w.u, w.f]; for x in q { sane = sane && abs(simd_length(x) - 1) < 1e-9 && abs(x[w.a]) < 1e-9 }; sane = sane && abs(simd_dot(w.r, w.f)) < 1e-9 && abs(w.p[w.a] - w.s) < 1e-12 && max(abs(w.p.x), abs(w.p.y), abs(w.p.z), abs(w.p.w)) <= 1 + 1e-12 }
                check(ring && edge && poles && sane, "超立方体の 8 部屋：まっすぐ 4 部屋で元の所・辺のまわりは 3 部屋で向きが 90° ずれる・部屋の中心は 8 つの極")
            }
            do {   // 設定の保存の表：キーは重ならず、覚えた値を読み直すと同じになる（保存と読み込みが同じ表から作られている）
                let names = HyperLabState.savedKeys.map { k -> String in switch k { case .d(let n, _), .i(let n, _), .b(let n, _): return n } }
                let a = HyperLabState(); a.layers = 23; a.camW = 4.4; a.poleEN = true; a.rot2XY = -12; a.shotCurve = false; a.uiScale = 1.25; a.spinMode = 5; a.order = [2, 0, 1]
                let b = HyperLabState(); b.apply(a.snapshot)
                let sa = a.snapshot, sb = b.snapshot, same = sa.keys.sorted() == sb.keys.sorted() && sa.keys.allSatisfy { "\(sa[$0]!)" == "\(sb[$0]!)" }
                check(Set(names).count == names.count && sa.count == names.count + 1 && same && b.layers == 23 && b.order == [2, 0, 1], "設定の保存：\(names.count + 1) 個のキーが重ならず、覚えた値を読み直すと同じ")
            }
            do {   // 超球面拡張：ステージの半径・ブラックホールは自分のステージの S³ の上、出口は 1 つ下の S³ の上・詰めると拡張はどちらか一方
                let R = HyperLabState.stageR, B = HyperLabState.blackHoles
                let onShell = B.indices.allSatisfy { k in abs(simd_length(B[k] * R[k]) - R[k]) < 1e-12 && (k + 1 >= R.count || abs(simd_length(B[k] * R[k + 1]) - R[k + 1]) < 1e-12) }
                let s = HyperLabState(); s.toggleFill(); s.expandOn = true; s.stageView = 2
                let sh = s.expandShells(), one = !s.fillOn
                s.stageOnly = true; let solo = s.expandShells(); s.stageOnly = false
                s.toggleFill(); let other = s.fillOn && !s.expandOn
                let sf = HyperLabState(); sf.toggleFill(); sf.fillA = 0; let n10 = sf.fillShells().count; sf.fillCount = 20; let n20 = sf.fillShells().map { $0.r }
                check(n10 == 10 && n20.count == 20 && abs(n20[1] - 0.95) < 1e-12 && abs(n20[19] - 0.05) < 1e-12, "詰める数：ふつう 10 枚、20 枚にすると 1, 0.95, … 0.05 の等しい間隔")
                check(R == [1, 0.8, 0.6, 0.4, 0.2] && B.count == R.count && onShell && one && other && sh.map { $0.r } == R && sh[2].k == 1 && sh[0].k < 1 && solo.count == 1 && solo[0].r == 0.6 && solo[0].k == 1, "超球面拡張：5 つのステージ・入口は自分のステージ、出口は 1 つ下のステージの上・詰めるとどちらか一方・ほかのステージを消すと光らせるステージだけ")
            }
            do {   // ナイフ：画面の点から殻の経度を読む（4D で回していても）・引いて広げる・付いてくる・殻の外は読まない
                let st = HyperLabState(); st.pitch = 0.3; st.roll = -0.4; st.viewYaw = 0.5; st.viewPitch = 0.3
                if let r = HyperLabRenderer(side: .right, state: st, view: nil), r.image(400, 300) != nil, let ks = r.knifeShell() {
                    let sz = CGSize(width: 400, height: 300), m = r.knifeMVP, eye = r.camBasis().0, ctr = r.walkPlace(ks.c).0
                    func scr(_ th: Double, _ ph: Double) -> (pt: CGPoint, front: Bool) {   // front：はっきり手前を向いている所（ふちの近くは除く）
                        let p = r.walkPlace(HyperLabRenderer.knifePoint(ks.c, ks.r, th, ph)).0, q = m * SIMD4(SIMD3<Float>(p), 1)
                        return (CGPoint(x: (Double(q.x / q.w) * 0.5 + 0.5) * 400, y: (0.5 - Double(q.y / q.w) * 0.5) * 300), simd_dot(simd_normalize(p - ctr), simd_normalize(eye - p)) > 0.35)
                    }
                    func dang(_ a: Double, _ b: Double) -> Double { var d = a - b; d -= 2 * .pi * floor((d + .pi) / (2 * .pi)); return abs(d) }
                    var errs: [Double] = []
                    for k in 0..<24 { let ph = Double(k) / 24 * 2 * .pi, s = scr(1.3, ph); if s.front, let l = r.knifePick(s.pt, m, sz) { errs.append(dang(l, ph)) } }
                    var a = 0.0
                    for j in 0..<72 { let x = Double(j) / 72 * 2 * .pi; if scr(1.4, x).front && scr(1.4, x + 0.35).front && scr(1.4, x + 0.7).front { a = x; break } }
                    func drag(_ to: Double) { st.knifeStart = scr(1.4, a).pt; st.knifePtr = st.knifeStart; st.knifeDown = true; r.knifeStep(m, sz)
                        for t in 1...10 { st.knifePtr = scr(1.4, a + (to - a) * Double(t) / 10).pt; r.knifeStep(m, sz) }; st.knifeDown = false; r.knifeStep(m, sz) }
                    st.knifeOn = true; drag(a + 0.7)
                    let openOK = st.cutOn && st.cutRef == 2 && dang(st.cutPhi, a + 0.35) < 0.02 && abs(st.cutWDeg - 0.7 * 180 / .pi) < 1.5, w0 = st.cutWDeg
                    st.knifeMove = true; drag(a + 0.7)
                    let moveOK = dang(st.cutPhi, a + 0.7) < 0.02 && st.cutWDeg == w0
                    let outside = r.knifePick(CGPoint(x: 2, y: 2), m, sz) == nil
                    check(errs.count >= 5 && (errs.max() ?? 1) < 0.02 && openOK && moveOK && outside,
                          String(format: "ナイフ：画面の点から殻の経度を読む（%d 点・ずれ最大 %.2f°）・引いて広げる（真ん中 %.1f°・幅 %.1f°）・付いてくる・殻の外は読まない", errs.count, (errs.max() ?? 0) * 180 / .pi, st.cutPhi * 180 / .pi, w0))
                } else { check(false, "ナイフ：確かめの絵が描けない") }
            }
            do {   // R の世界：さんぽの宇宙の大きさに R をかける（速さ・目印の見かけは 1/R）。宇宙の大きさの設定とは別。0.05 より小さくしない・さんぽへ知らせる
                var s = Settings(); s.stageR = 0.2; s.uniL = 1
                let st = HyperLabState(), old = HyperLabState.worldRSink; var got = -1.0
                HyperLabState.worldRSink = { got = $0 }; st.worldR = 0; let low = st.worldR; st.worldR = 0.4; HyperLabState.worldRSink = old
                var pc = PassCaption(); let cap = pc.update(SIMD4(0, 0, 1, 0), 1, r: 0.2).text
                let tags = [MapRenderer.worldTag(1), MapRenderer.worldTag(0.2), MapRenderer.worldTag(0.45), MapRenderer.worldTag(0.453)]
                check(tags == ["", "R0.2", "R0.45", "R0.453"] && cap.contains("R0.2 通過"), "R の世界の札：R ＝ 1 は付けない・R0.2・R0.45・R0.453（1000 分の 1 まで）、通過の知らせ「\(cap)」")
                do {   // 書き出しの記録：詰める数・内側の球層・内核の演出・R の世界・ドリルを、1 コマごとに覚える
                    let sr = HyperLabState(); sr.noSink = true; sr.fillOn = true; sr.fillCount = 20; sr.fillAuto = false; sr.fillLayers = 7; sr.chaosOn = true; sr.worldR = 0.4
                    if let r = HyperLabRenderer(side: .right, state: sr, view: nil) {
                        r.walkOverride = { HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)) }
                        let f = r.recordFrame()?.f ?? []
                        check(f.count == 41 && f[34] == 20 && f[35] == 7 && f[36] == 1 && abs(f[37] - 0.4) < 1e-12, "書き出しの記録：詰める数 20・内側の球層 7・内核の演出・R の世界 0.4 を 1 コマごとに覚える（\(f.count) 個）")
                    } else { check(false, "書き出しの記録：確かめの状態が作れない") }
                }
                do {   // ドリル：R0 → 0.05 → R0、知らせは 掘り始め・中心を抜ける・着いた の順に 1 回ずつ
                    let sd = HyperLabState(), oldD = HyperLabState.drillSink, oldW = HyperLabState.worldRSink
                    var ev: [Int] = [], minR = 9.0, n = 0
                    HyperLabState.drillSink = { ev.append($0) }; HyperLabState.worldRSink = { minR = min(minR, $0); n += 1 }
                    sd.worldR = 0.6; sd.startDrill()
                    for _ in 0..<Int((HyperLabState.drillLen + 1.5) * 60) { sd.tickDrill(1.0 / 60) }
                    HyperLabState.drillSink = oldD; HyperLabState.worldRSink = oldW
                    check(ev == [0, 1, 2] && minR == 0.05 && sd.worldR == 0.6 && !sd.drillOn && sd.drillK == 0 && n > 100,
                          String(format: "ドリル：R 0.6 → いちばん小さく %.2f → 0.6 に戻る・知らせ %@・R が %d 回なめらかに変わる", minR, ev.map(String.init).joined(separator: "→"), n))
                }
                check(abs(s.uniR - 2) < 1e-9 && abs(s.uniBase - 10) < 1e-9 && abs(s.moveR - 2) < 1e-9 && low == 0.05 && got == 0.4,
                      String(format: "R の世界：宇宙 ×10 で R ＝ 0.2 なら半径 %.2f（進む角度 1/R）・R ＝ 0 は %.2f で止める・さんぽへ %.2f を知らせる", s.uniR, low, got))
            }
            check(FIXED.map(MapRenderer.poleAxis) == ["+w", "−w", "+x", "−x", "+y", "−y", "+z", "−z"], "極の札の軸：アナ極 +w・カタ極 −w・東極 +x・西極 −x・北極 +y・南極 −y・天極 +z・地極 −z")
            do {   // 2 重回転：X-Y と Z-W を同時に回す。傾きはそのままで、超球そのものが回る
                func spun(_ a: Double, _ b: Double, _ sec: Double) -> HyperLabState { let s = HyperLabState(); s.pitch = 0.6; s.roll = 0.3; s.rot2On = true; s.rot2XY = a; s.rot2ZW = b; for _ in 0..<Int(sec * 100) { s.tick(0.01) }; return s }
                let c = spun(30, 30, 1), ang = 30.0 * .pi / 180
                let moved = abs(c.yaw - ang) < 1e-9 && abs(c.zw - ang) < 1e-9 && c.pitch == 0.6 && c.roll == 0.3
                let pts: [SIMD4<Double>] = [[1, 0, 0, 0], [0, 0, 1, 0], [0.6, 0, 0.8, 0], [0.5, 0.5, 0.5, 0.5], [0.1, -0.7, 0.7, 0.1]].map { simd_normalize($0) }
                func arc(_ s: HyperLabState, _ p: SIMD4<Double>) -> Double {   // 傾きのない時の、回った前と後の角
                    let z = SIMD4<Double>(s.zw, s.yaw, 0, 0); return acos(max(-1, min(1, simd_dot(p, s.rot4(p, z)))))
                }
                let same = pts.allSatisfy { abs(arc(c, $0) - ang) < 1e-9 }                 // クリフォード回転：全部の点が同じ角
                let g = spun(30, 60, 1), noneFixed = pts.allSatisfy { arc(g, $0) > ang - 1e-9 }   // 動かない点がない（動く角は遅い方以上）
                let f = spun(30, 0, 1), fixed = arc(f, [0, 0, 1, 0]) < 1e-9 && abs(arc(f, [1, 0, 0, 0]) - ang) < 1e-9   // 片方が 0 なら、その面の円は動かない
                var rings = true                                                        // 2 つの円は形が動かず、円の上をすべるだけ
                for t in stride(from: 0.0, to: 6.28, by: 0.7) {
                    let q = HyperLabState(); q.pitch = 0.6; q.roll = 0.3
                    let a0 = c.rot4(SIMD4(cos(t), sin(t), 0, 0)), a1 = q.rot4(SIMD4(cos(t + ang), sin(t + ang), 0, 0))
                    let b0 = c.rot4(SIMD4(0, 0, cos(t), sin(t))), b1 = q.rot4(SIMD4(0, 0, cos(t + ang), sin(t + ang)))
                    rings = rings && simd_length(a0 - a1) < 1e-9 && simd_length(b0 - b1) < 1e-9
                }
                let x = HyperLabState(); x.rot2On = true; x.auto = true; let one = !x.rot2On; x.rot2On = true; let two = !x.auto; x.followOn = true; let three = !x.rot2On
                let o = HyperLabState(); o.pitch = 0.4; o.roll = -0.2; o.yaw = 0.7; o.rot2ZW = 0; o.rot2ZWOnly = true
                for _ in 0..<100 { o.tick(0.01) }
                let zwOnly = o.rot2On && abs(o.zw - ang) < 1e-9 && abs(o.yaw - 0.7) < 1e-9 && o.pitch == 0.4 && o.roll == -0.2
                o.rot2ZWOnly = false; let off = !o.rot2On; o.rot2Both = true; let back = o.rot2On && !o.rot2ZWOnly && o.rot2XY == 30
                let sw = HyperLabState(); sw.yaw = 0.3; sw.zw = 0.2; sw.pitch = 0.5; sw.rot2XY = 30; sw.rot2ZW = 60; sw.rot2Amp = 60; sw.rot2Swing = true; sw.rot2On = true
                var smooth = true, py = sw.yaw, pz = sw.zw
                for _ in 0..<300 { sw.tick(0.01); smooth = smooth && abs(sw.yaw - py) < 0.02 && abs(sw.zw - pz) < 0.02; py = sw.yaw; pz = sw.zw }   // 3 秒：飛ばずに動く
                let peak = abs(sw.yaw - (0.3 + .pi / 3)) < 1e-6 && abs(sw.zw - 0.2) < 1e-6 && sw.pitch == 0.5       // 面内は 1/4 往復で端、Z-W は半往復で真ん中
                for _ in 0..<900 { sw.tick(0.01) }
                let home = abs(sw.yaw - 0.3) < 1e-6 && abs(sw.zw - 0.2) < 1e-6                                   // 12 秒で 1 往復して元へ
                let hz = HyperLabState(); hz.rot2Swing = true; hz.rot2ZWOnly = true; hz.yaw = 0.7; for _ in 0..<50 { hz.tick(0.01) }
                let hand = abs(hz.yaw - 0.7) < 1e-12 && abs(hz.zw) > 0.05                                          // Z-W だけ：面内は手のまま
                check(smooth && peak && home && hand, "ゆらす（単振動）：飛ばずに動く・1/4 往復で端・1 往復で元へ・止めた面は手で動かせる")
                check(zwOnly && off && back, "Z-W 回転だけ：Z-W だけが進み、前後・左右・面内はそのまま・2 重回転へ戻せる")
                check(moved && same && noneFixed && fixed && rings && one && two && three, "2 重回転：傾きはそのまま・同じ速さなら全部の点が同じ角・動かない点なし・片方 0 で円が止まる・2 つの円は形が動かない")
            }
            do {   // 視点切りかえ：左下の地図と同じ向き。Y 消失は w が上、X 消失は w が右、Z 消失は w が手前。回している角度は触らない
                let b = HyperLabState()
                func wAxis(_ n: String) -> SIMD4<Double> { let s = HyperLabState.shotList.first { $0.name == n }!; return b.rot4(SIMD4(0, 0, 0, 1), SIMD4(s.zw * .pi / 180, 0, s.pitch * .pi / 180, s.roll * .pi / 180)) }
                let want: [(String, SIMD4<Double>)] = [("W 消失", [0, 0, 0, 1]), ("W 消失・反転", [0, 0, 0, -1]), ("Y 消失", [0, 1, 0, 0]), ("Y 消失・反転", [0, -1, 0, 0]), ("X 消失", [1, 0, 0, 0]), ("X 消失・反転", [-1, 0, 0, 0]), ("Z 消失", [0, 0, 1, 0]), ("Z 消失・反転", [0, 0, -1, 0])]
                let axes = want.allSatisfy { simd_length(wAxis($0.0) - $0.1) < 1e-9 }
                let s = HyperLabState(); s.shotCurve = false; s.shotEvery = 0.5; s.shotEase = 0; s.shotCam = false; s.viewYaw = 0.2; s.viewPitch = 0.1; s.followOn = true; s.shotOn = true
                var seen: Set<String> = [], last = "", exact = !s.followOn, fam = true
                for _ in 0..<2000 {
                    s.tick(0.05)
                    if s.shotName != last {
                        if let e = HyperLabState.shotList.first(where: { $0.name == s.shotName }) {
                            for (a, b) in [(s.pitch, e.pitch), (s.roll, e.roll), (s.zw, e.zw)] { exact = exact && abs(HyperLabState.norm(a - b * .pi / 180)) < 1e-9 }
                        } else { exact = false }
                        fam = fam && s.shotName.first != last.first; last = s.shotName; seen.insert(last)
                    }
                }
                let camKept = abs(s.viewYaw - 0.2) < 1e-9 && abs(s.viewPitch - 0.1) < 1e-9
                let r = HyperLabState(); r.rot2On = true; r.rot2XY = 30; r.rot2ZW = 30; r.shotCurve = false; r.shotEvery = 0.4; r.shotEase = 0.1; r.shotOn = true
                var noZ = true; for _ in 0..<300 { r.tick(0.01); noZ = noZ && !r.shotName.hasPrefix("Z") }
                let turning = abs(r.yaw - .pi / 2) < 1e-9 && abs(r.zw - .pi / 2) < 1e-9
                // カーブ：飛ばずに流れて、間隔ごとに見え方をちょうど通る。3D 回転を入れている間は 3D のカメラに触らない
                let cv = HyperLabState(); cv.shotCurve = true; cv.shotCurveEvery = 1; cv.shotCam = true; cv.shotOn = true
                var flow = true, through = true, prev = [cv.pitch, cv.roll, cv.zw, cv.viewYaw], lastN = "", hits = 0
                for _ in 0..<1000 {
                    let before = cv.shotName; cv.tick(0.01)
                    let now = [cv.pitch, cv.roll, cv.zw, cv.viewYaw]
                    for k in 0..<4 { flow = flow && abs(HyperLabState.norm(now[k] - prev[k])) < 0.08 }; prev = now
                    if before != cv.shotName && !before.isEmpty, let e = HyperLabState.shotList.first(where: { "→ " + $0.name == before }) {   // 前の行き先をちょうど通った
                        hits += 1
                        for (a, b) in [(cv.pitch, e.pitch), (cv.roll, e.roll), (cv.zw, e.zw)] { through = through && abs(HyperLabState.norm(a - b * .pi / 180)) < 0.05 }
                    }
                    lastN = cv.shotName
                }
                let sp = HyperLabState(); sp.shotCurve = true; sp.spin3D = true; sp.shotOn = true; sp.viewYaw = 0
                for _ in 0..<100 { sp.tick(0.01) }
                let spinKept = abs(sp.viewYaw - 0.3) < 1e-9 && !lastN.isEmpty
                check(flow && through && hits >= 8 && spinKept, "視点切りかえ（カーブ）：飛ばずに流れる・間隔ごとに見え方を通る・3D 回転はそのまま")
                check(axes && exact && fam && seen.count >= 8 && camKept && noZ && turning, "視点切りかえ：地図と同じ向き・同じ軸は続かない・回している X-Y と Z-W はそのまま進む（Z-W 回転中は Z 消失なし）")
            }
            let g1 = HyperLabRenderer.arrowGap(ecd: 1, showK: 1, m0: 1), g2 = HyperLabRenderer.arrowGap(ecd: 3.4, showK: 3.4, m0: 1)
            check(abs(g1 - g2) < 1e-9, "矢印の間隔：ショーカメラが引いても広がらない")
            var z = 0.0, z35 = 0.0
            for i in 0..<42 { z = HyperLabRenderer.soundFollow(z, to: 1, dt); if i == 20 { z35 = z } }
            check(z35 > 0.5 && z35 < 0.9 && z > 0.95 && z < 1, String(format: "音のリゾルブ：ぱっと切りかえても 0.35 秒で %.2f、0.7 秒で %.2f と徐々に変わる", z35, z))
        }
        // 動画の時間のならし：走っている間に 0.2 秒止まっても、動画では止まらない
        do {
            func d(_ t: Double) -> Double { t < 5 ? t : t < 5.2 ? 5 : t - 0.2 }
            func s(_ t: Double) -> Double { d(VideoExport.smoothTime(t, t0: 0, t1: 10, d)) }
            var low = 9.0, raw = 9.0
            for i in 0..<120 { let t = 4.4 + Double(i) / 60; low = min(low, (s(t + 1.0 / 60) - s(t)) * 60); raw = min(raw, (d(t + 1.0 / 60) - d(t)) * 60) }
            check(raw < 0.01 && low > 0.45 && abs(VideoExport.smoothTime(2, t0: 0, t1: 10, d) - 2) < 1e-3, String(format: "動画の時間のならし：0.2 秒止まった所でも、いちばん遅くて %.2f 倍で進む。ふつうの所の時刻は変わらない", low))
        }
        // 地図の窓：ダイブの入り口（ズームがまだ小さい）から地図の見え方。ふつうの超球の絵にならない
        do {
            let s0 = HyperLabState()
            if let ov = HyperLabRenderer(side: .right, state: s0, view: nil) {
                ov.overview = true; ov.clockOverride = 100
                s0.diveOn = true; s0.diveT = 0
                let enter = ov.ovLive
                s0.diveOn = false; s0.diveT = 0.05
                let leave = ov.ovLive
                s0.diveT = 0; ov.clockOverride = 200
                check(enter && leave && !ov.ovLive, "地図の窓：ダイブに入った瞬間から出るまで地図の見え方（全部の窓が同じ絵にならない）")
            }
        }
        // 先に描く道：反対側の 2 点の道は、走り直すたびに大円が変わる。線はいつも今の道に重なり、素通りの入りが終わると入りの切れ端が消える
        do {
            let rt = CustomRoute(name: "確かめ", pts: [0, 1].map { RoutePoint(p: RouteStore.poles[$0].1, name: RouteStore.poles[$0].0) })
            func off(_ rail: [V4]) -> Double {
                var worst = 0.0
                r.planCache = (-1, []); for q in r.plannedPath(ahead: 2.0) { worst = max(worst, rail.map { simd_distance($0, q) }.min() ?? 9) }
                return worst
            }
            r.set = .plain; r.resetNorth(); r.startCustom(rt, flow: true)
            let g0 = r.railGen, r1 = r.railPath()
            r.cam.w.f = V4(0, 1, 0, 0); r.cam.w.r = V4(1, 0, 0, 0); r.cam.w.u = V4(0, 0, 1, 0); r.cam.az = 0; r.cam.el = 0
            r.cam.w.p = nrm(V4(0.6, 0, 0, 0.8)); orthoFrame(&r.cam.w)
            r.startCustom(rt, flow: true)
            let g1 = r.railGen, r2 = r.railPath(), o2 = off(r2), entering = r.cr.flowIn != nil
            var n = 0
            while r.cr.flowIn != nil && n < 2000 { r.crStep(0.02); n += 1 }
            r.crStep(0.02)
            let r3 = r.railPath(), o3 = off(r3)
            let stub = r3.map { acos(max(-1, min(1, dot4($0, r2[0])))) }.min() ?? 0
            let g2 = r.railGen
            _ = r.railPath(); let g3 = r.railGen
            check(r1.count > 100 && g0 + 1 <= g1 && o2 < 0.03 && entering && o3 < 0.03 && stub > 0.2 && g2 > g1 && g3 == g2,
                  String(format: "先に描く道：走り直すと作り直して今の道に重なる（ずれ %.4f）。入りが終わると切れ端が消え（%.2f 離れる）今の道のまま（ずれ %.4f）、毎コマは作らない", o2, stub, o3))
            r.pathMode = .none
        }
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
            // 極めぐり「極を踏む」：8 つの極を全部ちょうど通る（いちばん近い所 0.01 以内）、止まらずにループ（2 周目も同じ）
            do {
                r.set = .plain; r.set.tourFlow = true; r.journey = Journey(); r.startPath(.tour)
                let tf = r.tourActive && r.pathMode == .custom
                var best = [Double](repeating: 9, count: 8)
                for _ in 0..<1800 where r.pathMode == .custom {
                    r.crStep(0.01)
                    for k in 0..<8 { let q = RouteStore.poles[k].1; best[k] = min(best[k], acos(max(-1, min(1, dot4(r.cam.w.p, V4(q[0], q[1], q[2], q[3])))))) }
                }
                let still = r.pathMode == .custom, far2 = best.max() ?? 9, laps = r.journey.lap, ph = r.journey.polesHit.count
                r.pathMode = .none; r.set = .plain
                check(tf && still && far2 < 0.01 && laps >= 2, String(format: "極めぐり・極を踏む：8 つの極を全部通る（いちばん遠い極まで %.4f）、チェックが付いて %d 周目（今の周の極 %d）、止まらずに巡回", far2, laps, ph))
            }
            // 極めぐり「ショー」：寄り道しながら 8 つの極を全部ちょうど通り、極のチェックで周回する（寄り道の点はチェックポイントにしない）
            do {
                r.set = .plain; r.set.tourShow = true; r.journey = Journey(); r.startPath(.tour)
                let n0 = r.cr.pts.count, rp = r.journey.routePts.count
                var best = [Double](repeating: 9, count: 8), maxTurn = 0.0, prevD: V4? = nil, prevP = r.cam.w.p
                for _ in 0..<3200 where r.pathMode == .custom {
                    r.crStep(0.01); let p = r.cam.w.p
                    for k in 0..<8 { let q = RouteStore.poles[k].1; best[k] = min(best[k], acos(max(-1, min(1, dot4(p, V4(q[0], q[1], q[2], q[3])))))) }
                    let d = p - prevP; if simd_length(d) > 1e-9 { let dn = simd_normalize(d); if let pd = prevD { maxTurn = max(maxTurn, acos(max(-1, min(1, dot4(pd, dn))))) }; prevD = dn }; prevP = p
                }
                let far3 = best.max() ?? 9, laps = r.journey.lap
                r.pathMode = .none; r.set = .plain
                check(n0 == 16 && rp == 0 && far3 < 0.01 && laps >= 2, String(format: "極めぐり・ショー：16 点（極 8 ＋ 寄り道 8、寄り道はチェックポイントにしない）、8 つの極を全部通る（いちばん遠い極まで %.4f）、%d 周目へ。1 歩（0.01）の向きの変わり 最大 %.1f°", far3, laps, maxTurn * 180 / .pi))
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
            // セットの道：道の切れ目と最後の場所で周が進み、チャイムが鳴って、跡が消える
            do {
                var rt = route([0, 2, 6, 1, 3, 5]); rt.name = "確かめのセット"; rt.flow = true; rt.breaks = [2, 5]
                r.set = .plain; r.resetNorth(); r.startCustom(rt)
                let keep = Journey.hitPulse; Journey.hitPulse = []
                let lap0 = r.journey.lap
                for _ in 0..<4000 where r.journey.lap < lap0 + 2 { r.crStep(0.01); r.journey.trail.append(r.cam.w.p) }   // 跡は消えた所の 1 点と、ここで足す 1 点
                let bells = Journey.hitPulse.filter { $0.pole == -1 }.count, tn = r.journey.trail.count
                Journey.hitPulse = keep; r.pathMode = .none
                check(r.journey.lap == lap0 + 2 && bells == 2 && tn == 2, "セットの道：切れ目で周が進み、チャイムが鳴って跡が消える（周 \(r.journey.lap - lap0)・チャイム \(bells)・跡 \(tn)）")
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
            _ = r.padDuringAuto("L3"); r.game.fake = (.zero, .zero, false, false, false); for _ in 0..<150 { r.step(1.0 / 120) }
            let back = abs(r.cam.hy)
            let bUsed = r.padDuringAuto("B"), stopped = r.pathMode == .none, msg = said
            let after = r.padDuringAuto("B")
            r.game.fake = nil; r.game.fakeDpad = nil; r.say = say0; r.set.gamepad = false
            check(abs(sp - 2) < 0.03 && still && hy > 10 && still2 && xUsed && !roam && back < 0.05 && bUsed && stopped && msg.contains("中止") && !after,
                  String(format: "自動走行中：左スティックの前で ×%.2f（極めぐりのまま）、右スティックで見回し %.0f°（道のまま）、X は効かない、L3 で前へ戻す、B で中止「%@」", sp, hy, msg))
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
            check(h0 == 0 && h1 == 1 && h2 == 0 && lap == 2 && msg.count == 2 && msg.last!.contains("2 周目へ") && cleared && poles == [0] && poleMsg.isEmpty,   // 周が変わると通った極もリセット（2 周目もチャイムが鳴る）。残るのは今通ったアナ極だけ
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
            st.setLayers(70); let d = (st.layers, walkN)
            st.layersLink = false; st.setLayers(30); let e = (st.layers, walkN)
            HyperLabState.walkShells = keep
            check(a == 11 && b == 15 && c == 7 && d == (61, 61) && e == (30, 61),
                  "球層の数の連動：さんぽ 11 → こちら \(a)、さんぽ 15 → \(b)、こちらで 7 → さんぽ \(c)、70 → どちらも \(d.0)（3〜61）。切ると別々（こちら \(e.0)・さんぽ \(e.1)）")
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
            // 自分を追う（xyz のみ）：4D の角度は動かず、カメラが自分の向きへ回る。遊びの中は動かない。3D 回転は休む。xyzw とは同時に入らない
            do {
                let me = nrm(SIMD4<Double>(0.5, 0.3, -0.6, 0.2)), dir = simd_normalize(SIMD3(me.x, me.y, me.z))
                HyperLabState.walkSource = { .init(trail: [], pos: me) }
                let s = HyperLabState(); s.followXYZ = true; s.followSlack = 0; s.followDrift = 0; s.spin3D = true; s.pitch = 0; s.roll = 0; s.yaw = 0; s.zw = 0
                for _ in 0..<600 { s.tick(1.0 / 60); s.tickFollow(1.0 / 60) }
                let eye = SIMD3(sin(s.viewYaw) * cos(s.viewPitch), sin(s.viewPitch), cos(s.viewYaw) * cos(s.viewPitch)), hit = simd_dot(eye, dir)
                let s2 = HyperLabState(); s2.followXYZ = true; s2.followSlack = 170; s2.followDrift = 0
                for _ in 0..<60 { s2.tickFollow(1.0 / 60) }
                let s3 = HyperLabState(); s3.followOn = true; s3.followXYZ = true; let only = !s3.followOn && s3.followXYZ; s3.followOn = true; let back = s3.followOn && !s3.followXYZ
                check(hit > 0.995 && s.pitch == 0 && s.roll == 0 && s.zw == 0 && s2.viewYaw == 0 && s2.viewPitch == 0 && only && back, "自分を追う（xyz のみ）：カメラが自分の向きへ回り（\(String(format: "%.3f", hit))）、4D の角度は動かず、遊びの中は止まり、xyzw とは同時に入らない")
                HyperLabState.walkSource = keep
            }
            check(c0 > 0.995 && up > best - 0.03 && still && abs(th - 90) < 3 && drift > 0.3 && drift < 15,
                  String(format: "自分を追う：遊び 0° で真ん中へ（正面 %.3f・進む向きの上 %.2f／できる限り %.2f）、遊び 90° は中では動かさず、奥からは %.1f° まで戻す。ゆるく回すと遊びの中でも 1 秒で %.1f° 寄る", c0, up, best, th, drift))
        }
        // 手で走る時（A・B）も、左スティックはいつも進む：前でアクセル、横は横へ（向きは変えない）。自動の時も前で加速
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
            check(manual && abs(turned) < 1e-9 && abs(up) < 1e-9 && s1 > s0 && autoAcc,
                  String(format: "手で走る時も左スティックはいつも進む：向きは変えない（右へ %.0f°・上へ %.0f°）、前でアクセル ×%.2f → ×%.2f、自動の時も前で加速", turned, up, s0, s1))
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
            let a = g.read(); g.vPress("L3", true); g.vPress("L3", false); g.vPress("R3", true); g.vClear()
            g.swapSticks = false; g.vLeft = SIMD2(0, 1); let b = g.read(); g.vClear()
            check(a.look.y == 1 && a.move.z == -1 && got == ["R3", "L3"] && b.move.z == 1 && b.look.y == 0, "左右のスティックの入れかえ：左で向き・右で歩く、L3 は見回しモード（R3 の働き）・R3 は前を見る（L3 の働き）。切ると元どおり")
        }
        // ドリルの極の表記：北極（+y）から掘ると、中心を抜けるまでは北極、抜けたら南極。もう一度掘ると、抜けたら北極へ戻る
        do {
            let oldD = HyperLabState.drillSink, oldW = HyperLabState.worldRSink, say0 = r.say
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false
            r.cam.w = Walker(p: [0, 1, 0, 0], r: [1, 0, 0, 0], u: [0, 0, 1, 0], f: [0, 0, 0, 1])   // 北極（+y）に立つ
            HyperLabState.drillSink = { r.drillEvent($0) }; HyperLabState.worldRSink = { r.set.stageR = $0 }
            var msgs: [String] = []; r.say = { msgs.append($0) }
            func near(_ p: V4) -> String { MapRenderer.poleName(FIXED.min(by: { dot4(p, $0.c) > dot4(p, $1.c) })!) }
            let sd = HyperLabState(); var log: [String] = [], pc = PassCaption(), t = 0.0
            func run(_ sec: Double) {
                for i in 0..<Int(sec * 60) {
                    sd.tickDrill(1.0 / 60); r.step(1.0 / 60); t += 1.0 / 60
                    let c = pc.update(r.cam.w.p, t, r: sd.worldR)
                    if i % 30 == 0 { log.append(String(format: "%.1f秒 y%+.2f R%.2f 近い極 %@ 通過 %@", t, r.cam.w.p.y, sd.worldR, near(r.cam.w.p), c.a > 0.01 ? c.text : "なし")) }
                }
            }
            let before = near(r.cam.w.p); sd.startDrill(); run(1); let early = near(r.cam.w.p); run(HyperLabState.drillLen); let after1 = near(r.cam.w.p)
            sd.startDrill(); run(1); let early2 = near(r.cam.w.p); run(HyperLabState.drillLen); let after2 = near(r.cam.w.p)
            print(log.joined(separator: "\n")); print("知らせ：" + msgs.joined(separator: " / "))
            HyperLabState.drillSink = oldD; HyperLabState.worldRSink = oldW; r.say = say0; r.set = .plain; r.cam = Camera(); r.journey = Journey()
            check(before == "北極" && early == "北極" && after1 == "南極" && early2 == "南極" && after2 == "北極",
                  "ドリルの極：北極から掘ると、掘り始めは\(early)・抜けると\(after1)・もう一度掘ると始めは\(early2)・抜けると\(after2)")
        }
        // ドリルの決まった道：D の字めぐり（ドリルでカタへ → 地表を半周歩いてアナへ → またドリル）・往復ドリル（カタで止まって、またアナへ）
        do {
            let oldD = HyperLabState.drillSink, oldW = HyperLabState.worldRSink, oldT = HyperLabState.tourWalkSink, say0 = r.say
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.say = { _ in }
            let sd = HyperLabState()
            HyperLabState.drillSink = { r.drillEvent($0) }; HyperLabState.worldRSink = { r.set.stageR = $0 }; HyperLabState.tourWalkSink = { r.tourWalk($0) }
            r.onTourArrived = { sd.tourArrived() }
            func run(_ sec: Double) { for _ in 0..<Int(sec * 60) { sd.tickDrill(1.0 / 60); r.step(1.0 / 60) } }
            sd.drillTour = 2
            run(HyperLabState.drillLen + 0.05); let atKata = r.cam.w.p.w < -0.99, walk1 = r.walking   // 着いてすぐ（もう歩き出している）
            var t = 0.0; while r.walking && t < 30 { run(0.1); t += 0.1 }; let atAna = r.cam.w.p.w > 0.99, walkT = t
            run(HyperLabState.tourPause + 0.2); let again = sd.drillOn
            sd.drillTour = 0; run(HyperLabState.drillLen + 1)
            r.cam = Camera(); r.journey = Journey(); sd.drillTour = 1
            run(HyperLabState.drillLen + 0.3); let k1 = r.cam.w.p.w < -0.999, still = !sd.drillOn && !r.walking
            run(HyperLabState.tourPause + HyperLabState.drillLen + 0.3); let back = r.cam.w.p.w > 0.999
            sd.drillTour = 0; run(HyperLabState.drillLen + 1)
            HyperLabState.drillSink = oldD; HyperLabState.worldRSink = oldW; HyperLabState.tourWalkSink = oldT; r.onTourArrived = nil; r.say = say0
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false
            check(atKata && walk1 && atAna && again && k1 && still && back,
                  String(format: "ドリルの道：D の字めぐりはドリルでカタへ・そのまま半周歩いて（%.1f 秒）アナへ・止まってまたドリル。往復ドリルはカタで止まり、またアナへ", walkT))
        }
        // 超球ラン（B トンネル）：表面すれすれ → 殻と殻のすき間を 4 つ → 中心を抜けて → 反対側へ脱出。さんぽの体もいっしょに動く
        do {
            let oldD = HyperLabState.drillSink, oldW = HyperLabState.worldRSink, oldP = HyperLabState.runPoseSink, oldS = HyperLabState.walkSource, say0 = r.say
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false; r.say = { _ in }
            HyperLabState.drillSink = { r.drillEvent($0) }; HyperLabState.worldRSink = { r.set.stageR = $0 }; HyperLabState.runPoseSink = { r.runPose($0, $1) }
            HyperLabState.walkSource = { HyperLabState.Walk(trail: [], pos: r.cam.w.p, fwd: r.cam.w.f, vR: r.cam.w.r, vU: r.cam.w.u, vL: r.cam.w.f) }
            let sd = HyperLabState()
            sd.runOn = true
            let len = sd.hrun.length, holes = sd.hrun.holes.count, n = Int(len * 60)
            var minR = 9.0, follow = true, gapsOK = true, hold = r.drillHold, maxStep = 0.0, prevX: SIMD4<Double>? = nil
            let stage = HyperLabState.stageR
            for i in 0..<(n - 2) {
                sd.tickRun(1.0 / 60); sd.tickDrill(1.0 / 60); r.step(1.0 / 60)
                let s = sd.hrun.at(sd.runT), x = s.p * s.rho
                minR = min(minR, s.rho)
                if simd_length(r.cam.w.p - s.p) > 1e-6 { follow = false }
                if let px = prevX { maxStep = max(maxStep, simd_length(x - px)) }; prevX = x
                // 殻を通る所はいつも穴の中（穴の真ん中から殻にそって 0.13 より近い）
                for rs in stage where abs(s.rho - rs) < 0.004 {
                    if !sd.tunHoles.contains(where: { abs($0.r - rs) < 1e-6 && simd_length($0.dir * rs - x) < 0.13 && $0.open > 0.5 }) { gapsOK = false; print(String(format: "  穴の外で殻を通った：%.2f 秒 R %.3f", Double(i) / 60, rs)) }
                }
            }
            let end = sd.hrun.at(sd.runT), flips = sd.runFlips
            let mir = r.mirrored
            // ダイブ画面で見る（トンネルでない）：自分でダイブして、殻がうっすら出て、金色の線は中心のそばを切れずに通る
            let tp = sd.runPathPoints(), tGap = zip(tp, tp.dropFirst()).map { simd_length($1 - $0) }.max() ?? 9
            let tMin = tp.map { simd_length($0) }.min() ?? 9, dove = sd.diveOn && !sd.tunnelNow && sd.drillK > 0.99 && sd.runLine
            print(String(format: "  ダイブ画面のラン：線の点 %d・点の間のいちばん大きい所 %.3f・中心にいちばん近い所 %.3f", tp.count, tGap, tMin))
            sd.runOn = false; let released = !r.drillHold
            HyperLabState.drillSink = oldD; HyperLabState.worldRSink = oldW; HyperLabState.runPoseSink = oldP; HyperLabState.walkSource = oldS; r.say = say0
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); r.walking = false
            print(String(format: "  ラン 1 回り %.1f 秒・穴 %d・いちばん深い R %.4f・1 コマの最大の動き %.4f・最後の R %.3f", len, holes, minR, maxStep, end.rho))
            check(hold && follow && gapsOK && holes == 2 * stage.count && minR < 0.01 && flips == 1 && !mir && released && end.rho > HyperRun.top - 0.01 && maxStep < 0.03 && dove && tp.count > 50 && tGap < 0.08,
                  String(format: "超球ラン：表面すれすれ → 殻のすき間 4 つ → 中心を抜けて脱出（1 回り %.1f 秒、穴 %d 個、殻は穴の中だけ通る）。さんぽの体もいっしょに動き、止めると歩ける。ダイブ画面で、通った道を金色の線で見られる", len, holes))
        }
        // 鏡の世界：体を回さずに抜けると鏡写し（もう一度で元へ）。ふつうのドリル（宙返り）は鏡写しにならない
        do {
            r.set = .plain; r.cam = Camera(); r.journey = Journey(); let say0 = r.say; r.say = { _ in }
            let m0 = r.mirrored; r.drillEvent(1); let m1 = r.mirrored; r.drillEvent(3); let m2 = r.mirrored, atS = abs(r.cam.w.p.w - 1) < 1e-9
            r.drillEvent(3); let m3 = r.mirrored; r.say = say0; r.cam = Camera()
            check(!m0 && !m1 && m2 && !m3 && atS, "鏡の世界：ふつうのドリルは鏡写しにならず、鏡の世界のドリルで鏡写しに、もう一度抜けると元の向きに")
        }
        // 泳ぐ：ZL（L2）・Page Down で内へ、ZR（R2）・Page Up で外へ。R は 0.05〜1 の間をなめらかに、超球の窓へも知らせる
        do {
            let old = HyperLabState.worldRFromWalk; var sent = -1.0; HyperLabState.worldRFromWalk = { sent = $0 }
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = false
            r.game.fake = (.zero, .zero, false, false, false); r.game.fakeSwim = -1
            for _ in 0..<120 { r.step(1.0 / 120) }; let in1 = r.set.stageK
            for _ in 0..<600 { r.step(1.0 / 120) }; let floorR = r.set.stageK
            r.game.fakeSwim = 0.5; for _ in 0..<120 { r.step(1.0 / 120) }; let out1 = r.set.stageK
            r.game.fakeSwim = 0; r.keys = [116]; for _ in 0..<600 { r.step(1.0 / 120) }; let top = r.set.stageK; r.keys = []
            let sentOK = abs(sent - top) < 1e-12
            r.game.fakeSwim = nil; r.game.fake = nil; r.set.gamepad = false; HyperLabState.worldRFromWalk = old; r.set = .plain
            check(abs(in1 - (1 - Renderer.swimSpeed)) < 1e-6 && floorR == 0.05 && abs(out1 - (0.05 + 0.5 * Renderer.swimSpeed)) < 1e-6 && top == 1 && sentOK,
                  String(format: "泳ぐ：ZL いっぱいで 1 秒に R %.2f → %.2f、0.05 で止まる、ZR を半分で 1 秒 %.3f、Page Up で 1 まで戻り、超球の窓へも知らせる", 1.0, in1, out1))
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
        // 歩き続ける時のボタン：A を 1 秒で約 2.2 倍、ターボ・ターボ切（元の速さへ）、B を押し続けるとブレーキで止まる
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; r.game.fake = (.zero, .zero, false, false, false)
            let sr = r.set.shellRange
            r.game.fakeHeld = []; r.step(1.0 / 120); r.game.fakeHeld = ["A"]; for _ in 0..<120 { r.step(1.0 / 120) }; let up = r.autoSpeed
            r.game.fakeHeld = []; r.turboOn(); r.step(1.0 / 120); let tb = r.autoSpeed; r.turboOff(); r.step(1.0 / 120); let back = r.autoSpeed
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
                  String(format: "歩き続ける時のボタン：A を 1 秒で ×%.2f、ターボ ×%.0f・ターボ切で ×%.2f、B は押し始めやわらか（0.1 秒で %.1f%%）・押し続けると止まる、Y で自動の開始・なめらかに停止、X でターボ。A で走り出すと ×%.2f、離して 1 秒で ×%.2f（急に止まらない）", up, tb, back, soft * 100, carUp, coast))
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
        check(backDot < -0.1 && abs(vHalf / base - 0.6) < 0.02 && abs(vFull / base - 2.5) < 0.05 && abs(vBack / base - 2.5) < 0.05 && nTrail > 10,
              String(format: "コントローラー：手前に倒すと後ろへ（前との内積 %.2f）。速さ 6 割倒し ×%.2f・倒しきり ×%.2f・後ろへ倒しきり ×%.2f（軌跡 %d 点。L3 は前を見るに引っ越したので、軌跡は消さない）", backDot, vHalf / base, vFull / base, vBack / base, nTrail))
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
        for (name, setup) in [("ふつう", { (s: HyperLabState) in }), ("光沢 0・座標軸なし・跡なし", { (s: HyperLabState) in s.gloss = 0; s.axes = false; s.walk = false; s.marksOn = false }), ("宇宙", { (s: HyperLabState) in s.spaceMode = 1 }), ("詰める・内側 4 層", { (s: HyperLabState) in s.fillOn = true; s.fillA = 0; s.fillLayers = 4 }), ("詰める・内側 11 層", { (s: HyperLabState) in s.fillOn = true; s.fillA = 0; s.fillLayers = 11 })] as [(String, (HyperLabState) -> Void)] {
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
        for (name, gloss, glare, mode) in [("ポリゴン・傾き", 1.0, true, 0), ("拡張A", 1.0, true, 0), ("拡張C", 1.0, true, 0), ("拡張C・ほかを消す", 1.0, true, 0), ("ポリゴン・正面", 1.0, true, 0), ("ポリゴン・上から", 1.0, true, 0), ("ポリゴン・4D回転", 1.0, true, 0), ("ナイフ", 1.0, true, 0), ("R0.6の世界・歩いた跡", 1.0, true, 0), ("このRだけ0.4", 1.0, true, 0), ("ダイブ0.50・R0.4", 1.0, true, 0), ("ダイブ1.00・R0.4・三人称", 1.0, true, 0), ("ダイブ0.45・くるくる", 1.0, true, 0), ("ダイブ1.00・くるくる・三人称", 1.0, true, 0), ("ドリル途中・歩いた跡", 1.0, true, 0), ("ダイブ0.45・ドリル途中", 1.0, true, 0), ("内核・R0.3の世界・歩いた跡", 1.0, true, 0), ("内核・ドリル途中・歩いた跡", 1.0, true, 0), ("北極からドリル", 1.0, true, 0), ("北極からドリル・ダイブ0.45", 1.0, true, 0), ("トンネル・すれすれ", 1.0, true, 0), ("トンネル・すき間", 1.0, true, 0), ("トンネル・すき間の奥", 1.0, true, 0), ("トンネル・炉", 1.0, true, 0), ("トンネル・脱出", 1.0, true, 0), ("トンネル・脱出のあと", 1.0, true, 0), ("トンネル・ドリル", 1.0, true, 0), ("ランをダイブで・すき間", 1.0, true, 0), ("ランをダイブで・すき間の奥", 1.0, true, 0), ("ランをダイブで・炉", 1.0, true, 0), ("ランをダイブで・脱出", 1.0, true, 0), ("詰める・内側4層", 1.0, true, 0), ("詰める・内側11層", 1.0, true, 0), ("詰める20枚・自動", 1.0, true, 0), ("視点X", 1.0, true, 0), ("視点Z", 1.0, true, 0), ("2重回転A", 1.0, true, 0), ("2重回転B", 1.0, true, 0), ("光沢なし", 0.0, false, 0), ("光沢", 1.0, false, 0), ("光沢とグレア", 1.0, true, 0), ("光沢とグレア・半透明", 1.0, true, 2),
                                           ("正面・光沢なし", 0.0, false, 0), ("正面・光沢とグレア", 1.0, true, 0), ("光沢とグレア・歩いた跡", 1.0, true, 0), ("彗星・歩いた跡", 1.0, true, 0), ("巨大彗星・歩いた跡", 1.0, true, 0), ("大彗星・歩いた跡", 1.0, true, 0), ("予定の道・歩いた跡", 1.0, true, 0), ("線の彗星・歩いた跡", 1.0, true, 0), ("極・前の丸・歩いた跡", 1.0, true, 0), ("跡・白い光・歩いた跡", 1.0, true, 0), ("極・英語・歩いた跡", 1.0, true, 0), ("同じ道・前方を消す", 1.0, true, 0), ("極・通った札・歩いた跡", 1.0, true, 0), ("光る瞬間", 1.0, true, 0), ("光る瞬間・軸の色", 1.0, true, 0), ("同じ道・消さない", 1.0, true, 0), ("跡・軸の色・宇宙・歩いた跡", 1.0, true, 0), ("極・光・宇宙・歩いた跡", 1.0, true, 0), ("4D遠近・かすみ", 1.0, true, 0), ("4D遠近・ぼかし・ワイヤー", 0.0, false, 1), ("4D遠近・両方", 1.0, true, 0), ("4D遠近・両方・宇宙", 1.0, true, 0), ("彗星・宇宙・歩いた跡", 1.0, true, 0), ("さんぽ印・歩いた跡", 1.0, true, 0), ("ZW影", 1.0, true, 0), ("ZW両方", 1.0, true, 0), ("断面カット・画面", 1.0, true, 0), ("断面カット・物体", 1.0, true, 0), ("ポリゴンカット", 1.0, true, 0), ("座標軸・プラスのみ", 1.0, true, 0), ("座標軸・立体", 1.0, true, 0), ("宇宙", 1.0, true, 0), ("宇宙・正面", 1.0, true, 0), ("宇宙・半透明・星の遠近", 1.0, true, 2), ("平面・手前", 1.0, true, 0), ("平面・x", 1.0, true, 0), ("4D切断", 1.0, true, 0), ("4D切断・宇宙", 1.0, true, 0), ("4D切断x・正面", 1.0, true, 0), ("4D切断x", 1.0, true, 0), ("ワイヤー", 0.0, false, 1), ("ワイヤー・宇宙", 1.0, true, 1), ("ハイブリッド・宇宙", 1.0, true, 0), ("ダイブ0.2", 1.0, true, 0), ("ダイブ0.45", 1.0, true, 0), ("ダイブ0.60", 1.0, true, 0), ("ダイブ0.70", 1.0, true, 0), ("ダイブ0.75", 1.0, true, 0), ("ダイブ0.50・三人称", 1.0, true, 0), ("ダイブ0.65・三人称", 1.0, true, 0), ("ダイブ0.80・三人称", 1.0, true, 0), ("ダイブ0.65", 1.0, true, 0), ("ダイブ0.8", 1.0, true, 0), ("ダイブ0.9", 1.0, true, 0), ("ダイブ0.65・軸なし", 1.0, true, 0), ("ダイブ1.00・三人称", 1.0, true, 0), ("ダイブ1.00・予定の道・三人称", 1.0, true, 0), ("ダイブ1.00・予定の道・急カーブ・三人称", 1.0, true, 0), ("ダイブ0.00・予定の道・急カーブ", 1.0, true, 0), ("ダイブ0.00・予定の道", 1.0, true, 0), ("ダイブ1.00・巨大彗星・三人称", 1.0, true, 0), ("ダイブ1.00・右へカーブ・三人称", 1.0, true, 0), ("ダイブ1.00・上へカーブ・三人称", 1.0, true, 0), ("ダイブ1.00・南へ・三人称", 1.0, true, 0), ("ダイブ0.80・南へ・三人称", 1.0, true, 0), ("ダイブ0.60・三人称", 1.0, true, 0), ("球層・4方向", 1.0, true, 0), ("ダイブ0.60・4方向", 1.0, true, 0), ("ダイブ1.00・4方向・三人称", 1.0, true, 0), ("ダイブ1.00・南へ・4方向・三人称", 1.0, true, 0), ("ダイブ0.60・軸の色", 1.0, true, 0), ("球層・軸の色・宇宙", 1.0, true, 0), ("ダイブ0.60・4方向・深海", 1.0, true, 0), ("球層・4方向・深海", 1.0, true, 0), ("球層・4方向・宇宙", 1.0, true, 0), ("球層・4方向・宇宙・天の川の中心", 1.0, true, 0), ("球層・軸の色", 1.0, true, 0), ("球層・軸の色・ワイヤー", 0.0, false, 1)] {
            if let o = ProcessInfo.processInfo.environment["S3_PNG_ONLY"], !name.contains(o) { continue }   // 名前にこの文字を含む場面だけ
            for side in [HyperLabRenderer.Side.left, .right] {
                let st = HyperLabState(); st.pitch = 0.55; st.roll = -0.35; st.gloss = gloss; st.glare = glare; st.mode = mode
                if (name.hasPrefix("トンネル") || name.hasPrefix("ランをダイブで")) && side == .left { continue }
                st.viewYaw = 0.5; st.viewPitch = 0.3
                if name.hasPrefix("正面") { st.pitch = 0.0203; st.roll = -0.0962; st.viewYaw = 0; st.viewPitch = 0; st.leftDist = 5.56; st.viewDist = 7.5 }   // ウェブ版の今の画面と同じ向き・大きさ
                switch name {
                case "ポリゴン・傾き": st.cutOn = true; st.cutRef = 2; st.polyArm = 1; st.cutWDeg = 104; st.pitch = -1.757; st.roll = -2.647; st.viewYaw = 0.87; st.viewPitch = 1.277
                case "拡張A": st.expandOn = true; st.stageView = 0
                case "拡張C": st.expandOn = true; st.stageView = 2
                case "拡張C・ほかを消す": st.expandOn = true; st.stageView = 2; st.stageOnly = true
                case "ポリゴン・上から":                                    // すいかの 4 分の 1 切り：上から見下ろして押すと、y のまわりの 90° だけ欠けて、ほかの皮ははがれない
                    st.cutOn = true; st.cutRef = 2; st.polyArm = 1; st.cutWDeg = 90; st.pitch = 0; st.roll = 0; st.viewYaw = 0.4; st.viewPitch = 1.3
                case "ポリゴン・正面":                                      // 2026-11-03 のユーザーの画面：W 消失の正面から斜めに見て、ポリゴンカット 100°
                    st.cutOn = true; st.cutRef = 2; st.polyArm = 1; st.cutWDeg = 100; st.pitch = 0; st.roll = 0; st.viewYaw = -1.341656; st.viewPitch = 0.30925
                case "R0.6の世界・歩いた跡": st.worldR = 0.6                      // R の世界：彗星・跡・目印は R ＝ 0.6 の S³ の上、外の超球はうっすら
                case "このRだけ0.4": st.rOnly = true; st.rOnlyR = 0.4
                case "ダイブ0.50・R0.4", "ダイブ1.00・R0.4・三人称": st.worldR = 0.4
                case "ダイブ0.45・くるくる", "ダイブ1.00・くるくる・三人称": st.diveSpin = 1           // くるくる：途中は 4 次元を回っている途中、寄り切るとふつうと同じ
                case "詰める・内側4層": st.fillOn = true; st.fillA = 0; st.fillLayers = 4      // 超球を詰める：10 枚の超球面を全部（内側の球層の数を変えて）
                case "詰める・内側11層": st.fillOn = true; st.fillA = 0; st.fillLayers = 11
                case "詰める20枚・自動": st.fillOn = true; st.fillA = 0; st.fillCount = 20       // 詰める数を 20 枚に（内側の球層はふつうの 4）
                case "北極からドリル", "北極からドリル・ダイブ0.45":             // 北極（+y）から掘って 3 割（R0.6）：彗星は北極の真下、札が北極と南極のどちらの近くに見えるか
                    st.poleEN = true; st.polesMode = 2; st.drillOn = true; st.drillR0 = 1; st.drillU = 0.33; st.drillS = 0.4; st.drillK = 1; st.worldR = 0.6
                    if name.hasSuffix("ダイブ0.45") { st.diveT = 0.45; st.spaceMode = 1 }
                case "内核・R0.3の世界・歩いた跡": st.chaosOn = true; st.worldR = 0.3        // 内核の演出：R ＝ 0.3 の殻は焼けた鉄の色・ゆらぐ網目
                case "内核・ドリル途中・歩いた跡": st.chaosOn = true; st.drillOn = true; st.drillR0 = 0.8; st.drillU = 0.4; st.drillS = 0.704; st.drillK = 1; st.worldR = 0.8 * (1 - 0.704)
                case "ドリル途中・歩いた跡", "ダイブ0.45・ドリル途中":             // ドリル：R 0.8 から中心へ 7 割ほど掘った所（金色の穴の線・ステージの殻がうっすら）
                    st.drillOn = true; st.drillR0 = 0.8; st.drillU = 0.4; st.drillS = 0.704; st.drillK = 1; st.worldR = 0.8 * (1 - 0.704)             // R の世界でダイブ：その S³ の自分の所へ寄る
                case "ポリゴン・4D回転":                                    // 2026-11-04 のユーザーの画面：4D で大きく回したあと（前後 −180°）。殻ごとの経度で切るので、どの殻も同じ 1 切れ
                    st.cutOn = true; st.cutRef = 2; st.polyArm = 1; st.cutWDeg = 90; st.pitch = -.pi; st.roll = 2.81; st.viewYaw = 0.5; st.viewPitch = 0.3
                case "視点X": st.roll = .pi / 2; st.pitch = 0; st.viewYaw = 0; st.viewPitch = 0; st.axes = true
                case "視点Z": st.zw = -.pi / 2; st.pitch = 0; st.roll = 0; st.viewYaw = 0; st.viewPitch = 0; st.axes = true
                case "2重回転A": st.rot2On = true; st.polesMode = 2; st.yaw = 0.3; st.zw = 0.3
                case "2重回転B": st.rot2On = true; st.polesMode = 2; st.yaw = 1.0; st.zw = 1.0
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
                case "球層・4方向・深海": st.shellMode = 1; st.spaceMode = 2
                case "球層・4方向・宇宙": st.shellMode = 1; st.spaceMode = 1
                case "球層・4方向・宇宙・天の川の中心": st.shellMode = 1; st.spaceMode = 1; st.viewYaw = 0.9; st.viewPitch = -0.4
                case "球層・軸の色", "球層・軸の色・ワイヤー": st.shellMode = 2
                case "球層・軸の色・宇宙": st.shellMode = 2; st.spaceMode = 1
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
                    // 予定の道：まっすぐ 0.4 進んでから、右へ大きくカーブ（工事の看板のような光が走る所）
                    var plan: [SIMD4<Double>] = []
                    if name.contains("予定の道") { let turnStep = name.contains("急カーブ") ? 5.0 : 1.6; var c2 = c; for k in 0..<130 { if k > 20 && k < 80 { c2.az += turnStep }; let L = c2.lookFrame().L; c2.w.p = nrm(c2.w.p + L * 0.02); orthoFrame(&c2.w); plan.append(c2.w.p) } }
                    r.walkOverride = { .init(trail: tr, pos: c.w.p, head: c.lookFrame().L, space: true, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70, plan: plan) }
                    st.diveT = Double(name.dropFirst(3).prefix(4)) ?? 0; st.spaceMode = 1; if name.hasSuffix("軸なし") { st.axesDive = false }; if name.contains("巨大彗星") { st.cursor = 3 }; if name.contains("4方向") { st.shellMode = 1 }; if name.contains("軸の色") { st.shellMode = 2 }; if name.hasSuffix("深海") { st.spaceMode = 2 }; if name.hasSuffix("三人称") { st.diveThird = true }; if let c = ProcessInfo.processInfo.environment["S3_CHASE"]?.split(separator: ",").compactMap({ Double($0) }), c.count == 3 { st.chaseDist = c[0]; st.chasePitch = c[1]; st.chaseYaw = c[2] }
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
                if name.hasPrefix("北極からドリル") {                              // 北極に立って、x の向きを見ている
                    r.walkOverride = { HyperLabState.Walk(trail: [], pos: SIMD4(0, 1, 0, 0), head: SIMD4(1, 0, 0, 0), space: true, fwd: SIMD4(1, 0, 0, 0), vR: SIMD4(0, 0, 1, 0), vU: SIMD4(0, 0, 0, 1), vL: SIMD4(1, 0, 0, 0), fov: 70) }
                }
                if name == "ナイフ" && side == .right {                           // ナイフ：左から右へドラッグして切り開いたあと、刃を指したまま
                    let W = Double(iw), H = Double(ih), p0 = CGPoint(x: W * 0.42, y: H * 0.56), p1 = CGPoint(x: W * 0.6, y: H * 0.5)
                    r.knifeSizeOverride = CGSize(width: W, height: H); st.knifeOn = true
                    st.knifeStart = p0; st.knifePtr = p0; st.knifeDown = true; _ = r.image(iw, ih)
                    for t in 1...6 { let k = Double(t) / 6; st.knifePtr = CGPoint(x: p0.x + (p1.x - p0.x) * k, y: p0.y + (p1.y - p0.y) * k); _ = r.image(iw, ih) }
                    st.knifeDown = false; st.knifePtr = nil; st.knifeHover = p1
                }
                if name.contains("予定の道") && name.hasSuffix("三人称") { st.autoCam = true; _ = r.focusForTest(3) }   // オートカメラの見せ場（前のカーブへ向く）
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
                var tunRestore: (() -> Void)? = nil
                if name.hasPrefix("トンネル") || name.hasPrefix("ランをダイブで") {   // 超球ラン：アナ極から x の向きへ出発して、その場面の時刻まで進める（カメラが追いつくよう、最後の 2 秒は描きながら）
                    let w0 = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1), space: true, fwd: SIMD4(1, 0, 0, 0), vR: SIMD4(0, 0, 1, 0), vU: SIMD4(0, 1, 0, 0), vL: SIMD4(1, 0, 0, 0), fov: 70)
                    let oW = HyperLabState.walkSource, oD = HyperLabState.drillSink, oP = HyperLabState.runPoseSink, oR = HyperLabState.worldRSink
                    let dv = name.hasPrefix("ランをダイブで"); var wcur = w0           // ダイブ画面で見るラン：体もランといっしょに動かす
                    HyperLabState.walkSource = { wcur }; HyperLabState.drillSink = { _ in }; HyperLabState.worldRSink = { _ in }
                    HyperLabState.runPoseSink = dv ? { p, f in wcur.pos = p; wcur.fwd = f; wcur.vL = f } : { _, _ in }
                    if dv { r.walkOverride = { wcur }; st.diveOn = true; st.diveT = 0.45; st.diveManual = true; st.spaceMode = 1 }
                    tunRestore = { HyperLabState.walkSource = oW; HyperLabState.drillSink = oD; HyperLabState.runPoseSink = oP; HyperLabState.worldRSink = oR }
                    let ph = HyperRun.phases, tCore = ph.dropLast().map { $0.1 }.reduce(0, +), tGap = ph.prefix(3).map { $0.1 }.reduce(0, +)
                    let drill = name == "トンネル・ドリル", key = dv ? "トンネル" + name.dropFirst(7) : name
                    let tEnd: Double = ["トンネル・すれすれ": 2.5, "トンネル・すき間": tGap + 1.5, "トンネル・すき間の奥": tCore - 3.2, "トンネル・炉": tCore - 0.12, "トンネル・脱出": tCore + 0.7, "トンネル・脱出のあと": tCore + 2.2, "トンネル・ドリル": 2.4][key] ?? 1
                    st.chaosOn = true
                    st.tunnelView = !dv
                    if drill { st.startDrill() } else { st.runOn = true }
                    var t = 0.0
                    while t < tEnd {
                        st.tickRun(1.0 / 60); st.tickDrill(1.0 / 60); t += 1.0 / 60
                        if t > tEnd - 2 { r.clockOverride = 500 + t; _ = r.image(160, 135) }
                    }
                    r.clockOverride = 500 + t
                    print(String(format: "  %@：%.2f 秒 R %.3f 穴 %d（開いた %d）", name, t, st.worldR, st.tunHoles.count, st.tunHoles.filter { $0.open > 0.5 }.count))
                }
                guard let img = r.image(iw, ih) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent("超球_\(name)_\(side == .left ? "左" : "右").png")
                let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d); print(url.path)
                tunRestore?()
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
            ("宇宙の大きさ ×100：深海・殻を宇宙に合わせる（61 殻）", { s, c in s = Settings(); s.uniL = 2; s.shellUni = true; c.walk([0, 0, 1], 0.05) }),
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

    /// 確かめ：疾走の音を、ガラララ（荒さ）の入り切り・空間オーディオの入り切りで音のファイルにする（低音・荒さは保存の設定）
    static func rattleWav(_ dir: String) {
        let v = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: "s3walk.hyperlab.v1") ?? [:]
        let bass = v["soundBass"] as? Double ?? 1, rough = v["soundRough"] as? Double ?? 1
        let s = HyperSound()
        for (name, r) in [("on", rough), ("off", 0.0)] {
            s.tune(height: 0, place: 0, bass: bass, rough: r)
            _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/stereo_\(name).caf")
            _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/spatial_\(name).caf", at: SIMD3(0, 0, -1.5))
        }
        s.tune(height: 0, place: 0, bass: bass, rough: rough, rush: 1.25)
        _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/stereo_rush.caf")
        s.tune(height: 0, place: 0, bass: bass, rough: rough)
        _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, turn: 0.8, wav: dir + "/stereo_curve.caf")
        s.tune(height: 0, place: 0, bass: bass, rough: rough, phones: true)
        _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/stereo_ph.caf")
        _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/spatial_ph.caf", at: SIMD3(0, 0, -1.5))
        s.tune(height: 0, place: 0, bass: bass, rough: 0, phones: true)
        _ = s.renderTest(seconds: 6, speed: 1, zoom: 1, wav: dir + "/stereo_phoff.caf")
        print("低音 \(bass)・荒さ \(rough)")
    }
    /// W 消失地図の切り方：5 通りとも絵が変わる。dir があれば絵を残す
    static func wmapChecks(_ dir: String?) {
        // fx 0 おまかせ：手前をいつも切って中を見せ、later 秒待つと、ほかの地図と同じ見せ場のくさびが 90° 開く
        func shot(_ fx: Int, later: Double = 0) -> [UInt8] {
            let st = HyperLabState(); st.walk = true; st.cursor = 0; st.ovView = 3; st.ovFx = fx; st.ovShow = true; st.diveT = 1; st.diveOn = true; st.diveManual = true
            guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return [] }
            r.overview = true; r.ovMotion = true
            let a = 0.9, p = SIMD4(sin(a), 0, 0, cos(a)), f = SIMD4(cos(a), 0, 0, -sin(a))
            r.walkOverride = { .init(trail: [], pos: p, head: f, space: false, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 1, 0), vL: f, fov: 70) }
            r.domOverride = 1; st.bump()
            var img: CGImage? = nil
            for k in 0..<45 { r.clockOverride = 1000 + later + Double(k) * 0.1; if k == 0 && later > 0 { r.clockOverride = 1000; _ = r.image(420, 420); r.clockOverride = 1000 + later }; img = r.image(420, 420) }
            guard let img else { return [] }
            if let dir, let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent("wmap\(fx)_\(Int(later)).png") as CFURL, UTType.png.identifier as CFString, 1, nil) { CGImageDestinationAddImage(dd, img, nil); CGImageDestinationFinalize(dd) }
            var b = [UInt8](repeating: 0, count: 420 * 420 * 4)
            let ctx = CGContext(data: &b, width: 420, height: 420, bitsPerComponent: 8, bytesPerRow: 420 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: 420, height: 420)); return b
        }
        func diff(_ a: [UInt8], _ b: [UInt8]) -> Double { a.count == b.count && !a.isEmpty ? zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) : 0 }
        let half = shot(1), ds = [2, 3, 4, 5].map { diff(half, shot($0)) }
        check(ds.allSatisfy { $0 > 0.3 }, "W 消失地図の手で選ぶ切り方は 5 通りとも絵が変わる（半分とのちがい \(ds.map { String(format: "%.1f", $0) }.joined(separator: "・"))）")
        let auto0 = shot(0), auto1 = shot(0, later: 46), spin = shot(0, later: 12), cut = diff(auto0, half), open = diff(auto0, auto1), turn = diff(auto0, spin)
        check(cut < 0.3 && open > 0.3, "W 消失地図のおまかせは、はじめから手前を切って中を見せ、上り下りの見せ場でくさびが開く（半分と \(String(format: "%.1f", cut))・開く \(String(format: "%.1f", open))）")
        check(turn > 0.3, "W 消失地図のおまかせは、定まって 6 秒たつとゆっくり回る（ちがい \(String(format: "%.1f", turn))）")
    }
    /// 光の回り込み：アナ極の近くでだけ出る。切っていれば何も変わらない。dir があれば絵を残す
    static func lightChecks(_ dir: String?) {
        func shot(_ name: String, _ on: Bool, _ a: Double) -> [UInt8] {
            let st = HyperLabState(); st.walk = true; st.cursor = 0; st.lightWrap = on; st.pitch = 0.5; st.roll = -0.4; st.viewYaw = 0.4; st.viewPitch = 0.3
            guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return [] }
            let p = SIMD4(sin(a), 0, 0, cos(a)), f = SIMD4(cos(a), 0, 0, -sin(a))
            r.walkOverride = { .init(trail: [], pos: p, head: f, space: false, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 1, 0), vL: f, fov: 70) }
            r.clockOverride = 100; r.domOverride = 1; st.bump()
            guard let img = r.image(800, 600) else { return [] }
            if let dir, let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) { CGImageDestinationAddImage(dd, img, nil); CGImageDestinationFinalize(dd) }
            var b = [UInt8](repeating: 0, count: 800 * 600 * 4)
            let ctx = CGContext(data: &b, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 800 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: 800, height: 600)); return b
        }
        func diff(_ a: [UInt8], _ b: [UInt8]) -> Double { a.count == b.count && !a.isEmpty ? zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) : 999 }
        let nearOn = shot("light_on", true, 0.3), nearOff = shot("light_off", false, 0.3), farOn = shot("light_far_on", true, 1.57), farOff = shot("light_far_off", false, 1.57)
        let dn = diff(nearOn, nearOff), df = diff(farOn, farOff)
        check(dn > 1 && df < 0.01, "光の回り込みは、極の近くでだけ出る（極の近く \(String(format: "%.2f", dn))・赤道 \(String(format: "%.3f", df))）")
    }
    /// 左下のダイブ画面：本体がダイブしていない間も、本体のダイブと同じ絵を描く。dir があれば絵を残す
    static func wipeChecks(_ dir: String?) {
        func shot(_ name: String, dive: Bool, wipe: Bool, first: Bool = false) -> [UInt8] {
            let st = HyperLabState(); st.cursor = 1; st.diveThird = !(first && dive); st.diveBlend = false; st.autoCam = false; st.lowView = wipe ? 1 : 0; st.diveManual = true
            guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return [] }
            var c = Camera(); c.az = 50; var tr: [SIMD4<Double>] = []
            for _ in 0..<120 { let L = c.lookFrame().L; c.w.p = nrm(c.w.p + L * 0.01); orthoFrame(&c.w); tr.append(c.w.p) }
            let F = c.viewFrame()
            r.walkOverride = { .init(trail: tr, pos: c.w.p, head: c.lookFrame().L, space: false, fwd: c.w.f, vR: F.R, vU: F.U, vL: F.L, fov: 70) }
            st.diveT = dive ? 1 : 0; st.tickDive(0); r.diveWipe = wipe; r.wipeFirst = first && wipe; st.bump()
            guard let img = r.image(480, 300) else { return [] }
            if let dir, let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) { CGImageDestinationAddImage(dd, img, nil); CGImageDestinationFinalize(dd) }
            var b = [UInt8](repeating: 0, count: 480 * 300 * 4)
            let ctx = CGContext(data: &b, width: 480, height: 300, bitsPerComponent: 8, bytesPerRow: 480 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: 480, height: 300)); return b
        }
        let main = shot("wipe_main", dive: true, wipe: false), wipe = shot("wipe_wipe", dive: false, wipe: true), plain = shot("wipe_plain", dive: false, wipe: false)
        func diff(_ a: [UInt8], _ b: [UInt8]) -> Double { a.count == b.count && !a.isEmpty ? zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) : 999 }
        let same = diff(main, wipe), other = diff(plain, wipe)
        let main1 = shot("wipe_main1", dive: true, wipe: false, first: true), wipe1 = shot("wipe_first", dive: false, wipe: true, first: true)
        check(diff(main1, wipe1) < 2 && diff(wipe, wipe1) > 3, "一人称のダイブ画面の窓は、三人称の設定によらず本体の一人称と同じ絵になる（ちがい \(String(format: "%.2f", diff(main1, wipe1)))）")
        check(same < 2 && other > same * 3, "左下のダイブ画面は、本体のダイブと同じ絵になる（ちがい \(String(format: "%.2f", same))。ダイブしていない絵とのちがい \(String(format: "%.2f", other))）")
        var nowOK = true
        for v in [1, 2] {
            let st = HyperLabState(); st.lowView = v
            func on() -> Bool { v == 1 ? st.lowDiveNow : st.lowBothNow }
            let idleOK = on() && st.diveLive == 1
            st.diveOn = true
            let diveOK = !on() && st.diveLive == 0
            st.diveOn = false; st.walkView = false
            if !(idleOK && diveOK && !on()) { nowOK = false }
        }
        check(nowOK, "ダイブ画面（1 枚・両方）は、ダイブしていない時だけ出す（ダイブ中は地図かさんぽの景色）")
        // 受け持ち（歩く計算・音）はいつも 1 つの画面だけ。両方の時は 3D の球が消えるので、ダイブ画面が代わる
        var ownOK = true
        let st = HyperLabState(); st.lowView = 2
        if let main = HyperLabRenderer(side: .right, state: st, view: nil), let wipe = HyperLabRenderer(side: .right, state: st, view: nil), let low = HyperLabRenderer(side: .right, state: st, view: nil) {
            wipe.diveWipe = true; wipe.wipeMain = true; low.diveWipe = true
            st.show3D = true; if main.ownerForTest || !wipe.ownerForTest || low.ownerForTest { ownOK = false }
            st.show3D = false; if !main.ownerForTest || wipe.ownerForTest || low.ownerForTest { ownOK = false }
        } else { ownOK = false }
        check(ownOK, "両方の時も、歩く計算と音を受け持つ画面は 1 つだけ")
    }
    /// 確かめ：保存の設定で「アナ極→カタ極→地極」の道を歩き、z が大きく w が負の所（天極を過ぎた所）で絵を残す。立体の殻の入と切で比べる
    static func routePNG(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev), let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) else { return }
        var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:])
        func idx(_ n: String) -> Int { RouteStore.poles.firstIndex { $0.0 == n } ?? 0 }
        let rt = CustomRoute(name: "確かめ", pts: ["アナ極", "カタ極", "地極"].map { n in RoutePoint(p: RouteStore.poles[idx(n)].1, name: n) })
        r.set = us; r.resetNorth(); r.journey = Journey(); r.startCustom(rt)
        var sizeW = 800, sizeH = 500
        func save(_ name: String) {
            let w = sizeW, h = sizeH, px = r.renderOffscreen(width: w, height: h)
            var b = [UInt8](repeating: 255, count: w * h * 4), sum = 0.0
            for i in 0..<(w * h) { for c in 0..<3 { b[i * 4 + c] = UInt8(max(0, min(255, px[i * 4 + c] * 255 + 0.5))); sum += Double(b[i * 4 + c]) } }
            let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
            let dd = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd)
            print(name, String(format: "明るさ %.1f", sum / Double(w * h * 3)))
        }
        func fr(_ v: V4) -> String { String(format: "(%.3f, %.3f, %.3f, %.3f)", v.x, v.y, v.z, v.w) }
        var n = 0, shots = 0
        for i in 0..<200000 where r.pathMode == .custom {
            r.crStep(0.004)
            let w = r.cam.w
            if i % 2500 == 0 { print(i, "p", fr(w.p), "f", fr(w.f), "u", fr(w.u)) }
            if shots == 0 && w.p.z > 0.98 && w.p.w < -0.15 {
                print("着いた", i, "p", fr(w.p), "f", fr(w.f), "r", fr(w.r), "u", fr(w.u))
                let on = r.set.shellSolid
                save("route_as"); r.set.shellSolid = !on; save("route_flip"); r.set.shellSolid = on
                r.set.polePlanet = false; save("route_noplanet"); r.set.polePlanet = us.polePlanet
                r.set.shell = false; save("route_noshell"); r.set.shell = us.shell
                let nan = V4(repeating: .nan)
                r.cam.w.r = nan; r.cam.w.u = nan; save("route_nan_ru")
                r.cam.w.f = nan; save("route_nan_all")
                var x = r.cam.w; orthoFrame(&x); repairFrame(&x); r.cam.w = x
                print("直した枠", "f", fr(x.f), "r", fr(x.r), "u", fr(x.u)); save("route_repaired")
                // S3_SETS="k=v,k=v;k=v"：設定を変えて同じ場所で描く（sc は描く細かさ、big は実際の画面の大きさ）
                for (i, c) in (ProcessInfo.processInfo.environment["S3_SETS"] ?? "").split(separator: ";").enumerated() {
                    var dd: [String: Any] = [:], big = false; let sc0 = r.sceneScale
                    for kv in c.split(separator: ",") {
                        let t = kv.split(separator: "=").map(String.init); guard t.count == 2 else { continue }
                        if t[0] == "sc" { r.sceneScale = Double(t[1]) ?? 1 } else if t[0] == "big" { big = true }
                        else if t[1] == "true" || t[1] == "false" { dd[t[0]] = t[1] == "true" } else { dd[t[0]] = Double(t[1]) ?? 0 }
                    }
                    var s = us; s.load(dd); r.set = s
                    if big { sizeW = 1802; sizeH = 1874 } else { sizeW = 800; sizeH = 500 }
                    save("combo\(i)_" + c.replacingOccurrences(of: "=", with: "").replacingOccurrences(of: ",", with: "_"))
                    r.sceneScale = sc0
                }
                shots = 1; n = i; break
            }
        }
        print("歩いた", n, "shellSolid", us.shellSolid, "polePlanet", us.polePlanet)
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
