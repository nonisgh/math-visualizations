// 超球の窓のカメラ：彗星の速さ・空気・ゲームパッドのカメラ・オートカメラ・ショーカメラ・ダイブの寄り方と見せ場
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    func tickCometSpeed(_ dt: Double) {
        guard let w = wsrc?() else { return }
        var v = 0.0
        if let p0 = csPos, dt > 0 { let d = simd_length(w.pos - p0); v = d > 0.5 ? 0 : d / dt }
        csPos = w.pos
        let target = min(1, (v / 1.4).squareRoot() * st.feelK)
        st.cometSpd += (target - st.cometSpd) * (1 - exp(-dt * 3))
    }
    func tickAir(_ dt: Double) {
        let wr = HyperLabState.walkRendererGet?()
        wr?.coastOn = st.coaster; wr?.meriK = st.meriK; wr?.topK = st.topK
        st.meterM = wr?.coastM ?? 1
        if lastT - meterT >= 1.0 / 30 {                                    // 速度メーターは 1 秒に 30 回だけ（ここの表示だけ描き直す）
            meterT = lastT
            let show = st.meterOn && st.walk && (st.coaster || st.meriK > 0)
            if st.live.meterShow != show { st.live.meterShow = show }
            if show { st.live.meter = st.meterM; st.live.meterA = st.coastG; st.live.meterTop = st.topK }
        }
        st.coastG += ((wr?.coastA ?? 0) - st.coastG) * (1 - exp(-dt * 4))
        guard st.airOn else { st.airLift = 0; HyperSound.shared.setAir(1); return }
        if !st.soundOn { st.flyA = 0 }
        air.tick(speed: Float(min(1, st.cometSpd + 0.5 * st.flyA)), cross: Float(max(-1, min(1, sndTurn / 1.2 + 0.8 * st.flyA * st.flySide))))   // 極のそばでは空気が乱れる
        st.airLift += (Double(air.lift) - st.airLift) * (1 - exp(-dt * 20))
        HyperSound.shared.setAir(air.gust); HyperSound.shared.setScan(air.ring())
    }
    /// 確かめ用：オートカメラだけを 1 コマ進める
    func autoCamForTest(_ dt: Double) { tickAutoCam(dt) }
    /// 確かめ用：おくれて追うカメラを 1 コマ進めて、彗星が先へ出た分（画面の横・縦）とカメラの傾き
    func chaseForTest(_ dt: Double) -> (SIMD3<Double>, Double, Double) { if let w = wsrc?() { _ = lagFrame(w, 1, step: dt) }; return (leadOff, bank, simd_length(headWarp)) }
    /// ダイブのカメラをコントローラーで：三人称で寄っている間、選んだスティックで自分（彗星）のまわりを回す（左右・上下。離すとゆっくり元の角度へ）。
    ///   オートカメラは止めず、その上に足す（オートカメラの動きを、さらに手で操れる）。
    ///   そのスティックは、さんぽで歩くのには使わない
    func tickPadCam(_ dt: Double) {
        let wr = HyperLabState.walkRendererGet?()
        if HyperLabState.opModeNow != st.opMode { HyperLabState.opModeNow = st.opMode }
        let on = st.padCam && !st.opMode && st.diveThird && st.diveLive > 0.3 && wr != nil   // 操作モードの間は、スティックはみんな歩くのに使う
        let mask = on ? [1, 2, 3][max(0, min(2, st.padCamStick))] : 0
        if wr?.padCamMask != mask { wr?.padCamMask = mask }
        guard on, let g = wr?.game.sticks() else { st.padHolding = false; return }
        var v = SIMD2<Double>(0, 0)
        if mask & 1 != 0 { v += g.left }; if mask & 2 != 0 { v += g.right }
        let held = simd_length(v) > 0.02
        if held {
            st.diveYawOff += v.x * 1.9 * dt * (st.diveLive > 0.65 ? 1 : -1)
            st.divePitchOff = max(-1.4, min(1.4, st.divePitchOff - v.y * 1.4 * dt))
        }
        st.padHolding = held
    }
    func tickAutoCam(_ dt0: Double) {
        let dt = min(0.1, max(0, dt0))                                     // コマがつかえた時も、カメラが飛ばない
        tickPadCam(dt)
        var ty = 0.0, tp = 0.0
        if st.autoCam && st.diveLive > 0.3 && !st.camHeld {
            st.autoT += dt
            var tr = 0.0, tu = 0.0, vert = 0.0
            if let w = (wsrc)?() {
                let hd = w.head ?? w.fwd
                if let f0 = acFwd, dt > 0, simd_length(w.vR) > 0.5 {
                    let df = hd - f0
                    // 左右に曲がる速さ・上下に曲がる速さ（コマの間隔が不ぞろいでも荒れないよう、1/60 秒より短い間隔では割らない）
                    let dd = max(dt, 1.0 / 60)
                    if simd_length(df) < 0.5 { tr = simd_dot(df, w.vR) / dd; tu = simd_dot(df, w.vU) / dd }
                }
                if simd_length(w.vU) > 0.5 { vert = simd_dot(hd, w.vU) }    // 進む向きの上下の成分（垂直に近いほど ±1）
                acFwd = hd
            }
            acTurn += (tr - acTurn) * (1 - exp(-dt * 1.5)); acTurnU += (tu - acTurnU) * (1 - exp(-dt * 1.5)); acVert += (vert - acVert) * (1 - exp(-dt * 2))
            let a = st.autoT
            ty = 0.6 * sin(2 * .pi * a / 40) - 0.45 * max(-1, min(1, acTurn / 1.2))   // 右へ曲がると左（外側）へ回り込む
            tp = 0.18 * sin(2 * .pi * a / 27 + 1)
            // ダイナミック：きついカーブ・垂直に近い動きの時は、水平の目線から真上近くの目線へ大きく展開（曲がる道すじ全体が見えるように）
            let sharp = min(1, (acTurn * acTurn + acTurnU * acTurnU).squareRoot() / 1.1), vertical = smoothstep(0.35, 0.85, abs(acVert))
            let dyn = max(sharp, vertical)
            st.autoDyn = dyn
            tp += 1.05 * dyn * (1 - 0.18 * sin(2 * .pi * a / 27 + 1))           // 最大およそ 60°、見下ろしを足す
            ty *= 1 - 0.5 * dyn                                               // 真上へ回る間は左右の回り込みを控えめに
            if st.camShow { let (sy, sp, sd, sr) = showShot(dt); ty = sy; tp = sp; showDistT = sd; showRollT = sr } else { showRollT = 0 }
            // 予定の道を全部出している時は、長い矢印の鎖が画面を大きく横切るので、傾き・ずらしを半分に（カメラが荒ぶって見えない）
            if st.planLong { showRollT *= 0.5; showFrameT *= 0.5; ty *= 0.7 }
        } else { showDistT = 1; showRollT = 0; showIdx = 0; showT = 0 }
        // 視点の切りかえは、ばねで S 字に動かす（ゆっくり動き出して、途中で速く、着く前にまたゆっくり。急に向きが変わった感じにしない）
        func spring(_ x: inout Double, _ v: inout Double, _ to: Double, _ w: Double) {
            let n = max(1, Int(ceil(dt / 0.01))), h = dt / Double(n)
            for _ in 0..<n { v += (w * w * (to - x) - 2 * w * v) * h; x += v * h }
        }
        spring(&st.showDist, &sdV, showDistT, 1.3)
        if !(st.camShow && st.autoCam && st.diveLive > 0.3 && !st.camHeld) { showFrameT = .zero }
        spring(&st.showFrame.x, &sfV.x, showFrameT.x, 1.3); spring(&st.showFrame.y, &sfV.y, showFrameT.y, 1.3)
        // 展開する時は少し速く（約 1 秒）、戻る時はゆっくり（約 3 秒）
        let up = tp > st.autoPitch && st.autoDyn > 0.2
        let fast = st.camShow && st.autoCam                               // ショーカメラは、ゆっくり回り込む（切りかえに 2〜3 秒。落ち着いた動き）
        let k = 1 - exp(-dt * (fast ? 0.55 : 0.6)), kp = 1 - exp(-dt * (fast ? 0.55 : up ? 1.1 : 0.35))
        _ = k; _ = kp
        // 四元数のカメラ：左右・上下・傾きを 1 つの回転（四元数）にまとめて、ばねで追いかける。
        //   いつもいちばん近い回り方で、きれいな弧を描いて回り込む（左右を別々に追うと遠回りしたり、真上の近くでロックしたようにガクッと回ったりした）。
        //   向きの組み立て：左右（y 軸）→ 上下（x 軸）→ 傾き（z 軸）。追いかけた四元数を同じ組み立ての角度に戻して、カメラへ渡す
        let rollT = showRollT * 0.6                                           // 傾きは控えめに（ショーカメラ以外は 0）
        func qOf(_ y: Double, _ p: Double, _ rl: Double) -> simd_quatd {
            simd_quatd(angle: y, axis: SIMD3(0, 1, 0)) * simd_quatd(angle: p, axis: SIMD3(1, 0, 0)) * simd_quatd(angle: rl, axis: SIMD3(0, 0, 1))
        }
        var qT = qOf(ty, tp, rollT)
        if simd_dot(qT.vector, camQ.vector) < 0 { qT = simd_quatd(vector: -qT.vector) }
        let wq = up ? 1.9 : fast ? 1.25 : 1.0                                // 展開（見下ろしへ開く）は少し速く、ほかはゆっくり（約 3 秒で弧を描いて着く）
        let nq = max(1, Int(ceil(dt / 0.01))), hq = dt / Double(nq)
        for _ in 0..<nq {
            var e = qT * camQ.inverse; if e.real < 0 { e = simd_quatd(vector: -e.vector) }
            let ang = e.angle, ev = ang > 1e-9 ? e.axis * ang : SIMD3<Double>(0, 0, 0)
            camW += (wq * wq * ev - 2 * wq * camW) * hq                         // 回転のずれへ向かうばね（行き過ぎない）
            let wl = simd_length(camW)
            if wl > 1e-12 { camQ = simd_normalize(simd_quatd(angle: wl * hq, axis: camW / wl) * camQ) }
        }
        let mq = simd_matrix3x3(camQ), c3 = mq.columns.2
        st.autoPitch = asin(max(-1, min(1, -c3.y))); st.autoYaw = atan2(c3.x, c3.z); st.showRoll = atan2(mq.columns.0.y, mq.columns.1.y)
        if abs(st.autoYaw) < 1e-5 && ty == 0 { st.autoYaw = 0 }; if abs(st.autoPitch) < 1e-5 && tp == 0 { st.autoPitch = 0 }
    }
    /// 演出 AI（ジェットコースター）：予定の道の先の落ち込み・昇り・急カーブを読み、先回りして構える。
    ///   落ち込みでは、カメラが前の高い所へゆっくり舞い上がり、向かってくる彗星を見下ろす（彗星はカメラの下へ落ちていく）。抜けたら少しして後ろへ戻る。
    ///   マンネリにならないよう、最近使った 3 つは選ばず、角度・距離に毎回少し揺らぎを入れ、4 回に 1 回はあえて先回りしない
    func aiDirector(_ dt: Double) -> (Double, Double, Double, Double, Double, Double)? {
        // 赤い玉（アナ極）・紫の玉（カタ極）を通る時：真後ろから傾けずに、少し下がって玉へまっすぐ向かう（2 つの玉の交差がわかる）。通り抜けたら、いつもの動きへ
        if let w = (wsrc)?() {
            func toPole(_ p: SIMD4<Double>) -> Double { acos(min(1, abs(p.w) / max(1e-9, simd_length(p)))) }
            let here = toPole(w.pos)
            var next = here
            for i in stride(from: 0, to: min(w.plan.count, 45), by: 3) { next = min(next, toPole(w.plan[i])) }
            if here < 0.42 || next < 0.3 {
                aiShot = nil; aiKey = -99; aiHold = 0
                return (0, 0.14, 1.7, 0, 0, 0)
            }
        }
        var ahead: (cat: Int, sg: Double)? = nil
        if let w = (wsrc)?(), w.plan.count >= 3 {
            let pl = w.plan
            for i in 1..<min(pl.count - 1, 46) {
                guard Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.03 else { continue }   // 1 歩（0.02）で 1.7° より急
                let p = simd_normalize(pl[i]); var bend = (pl[i + 1] - pl[i]) - (pl[i] - pl[i - 1]); bend -= p * simd_dot(bend, p)
                let lr = simd_dot(bend, w.vR), ud = simd_dot(bend, w.vU)
                ahead = abs(ud) > abs(lr) * 0.8 ? (ud < 0 ? 0 : 1, 1) : (2, lr >= 0 ? 1 : -1)   // 0 落ち込み・1 昇り・2 左右（sg ＋右）
                break
            }
        }
        // (左右（0 真後ろ・±π 真正面）、見下ろし、距離、傾き、彗星の横の置き場所、縦の置き場所)
        func shots(_ cat: Int, _ sg: Double) -> [(Double, Double, Double, Double, Double, Double)] {
            let s2: Double = Bool.random() ? 1 : -1
            switch cat {
            case 0: return [(2.4 * s2, 0.85, 1.5, 0.08 * s2, 0, -0.12),   // 先回り：前の高い所から、向かってくる彗星を見下ろす（下へ落ちていく）
                            (0.25, 1.1, 1.6, 0, 0, -0.15),                  // 真後ろの高い所から、落ちていく深さ
                            (1.4 * s2, 0.65, 1.5, 0.1 * s2, 0, -0.1)]       // 横の高い所から、落ちていく高低差
            case 1: return [(2.5 * s2, -0.35, 1.3, 0.06 * s2, 0, 0.18),  // 前の低い所から、昇ってくる彗星を見上げる
                            (1.3 * s2, 0.1, 1.6, 0, 0, 0)]                  // 真横から、高さの変わり方
            default: return [(-1.0 * sg, 0.5, 1.4, 0.12 * sg, 0, 0),       // カーブの外側の高い所
                             (-0.2 * sg, 0.25, 1.0, 0.18 * sg, 0, 0),       // 真後ろで、曲がる側へ軽く傾けて
                             (0.3 * sg, 1.0, 1.7, 0, 0, 0),                 // 上の引き（曲がる道すじ全体）
                             (-0.4 * sg, 0.3, 1.1, 0.85 * sg, 0, 0)]       // 飛行機の旋回のように、曲がる側へ大きく傾けて
            }
        }
        if let a = ahead {
            aiHold = 1.6
            let key = a.cat * 10 + Int(a.sg)
            if key != aiKey {
                aiKey = key
                let c = shots(a.cat, a.sg)
                let recent = Set(aiHist.suffix(3))
                var pool = c.indices.filter { !recent.contains(a.cat * 100 + $0) }; if pool.isEmpty { pool = Array(c.indices) }
                if Double.random(in: 0..<1) < 0.25 { aiShot = nil }                // あえて先回りしない（いつもの構図のまま）
                else {
                    let i = pool.randomElement()!, b = c[i]; aiHist.append(a.cat * 100 + i); if aiHist.count > 8 { aiHist.removeFirst() }
                    func jit(_ v: Double) -> Double { v * Double.random(in: 0.88...1.12) }
                    aiShot = (jit(b.0), jit(b.1), jit(b.2), jit(b.3), b.4, b.5)
                }
            }
        } else {
            aiHold -= dt
            if aiHold <= 0 { aiShot = nil; aiKey = -99 }
        }
        return aiShot
    }
    func showShot(_ dt: Double) -> (Double, Double, Double, Double) {
        // 演出 AI が先回りしている時は、その構図（いつもの回し方は止めておく）
        if st.showMode == 1, let a = aiDirector(dt) {
            showFrameT = SIMD2(a.4, a.5); showT = 0
            let mw = smoothstep(0.52, 0.78, st.diveT)
            let baseY = st.chaseYawS * (1 - 2 * mw) * .pi / 180, baseP = st.chasePitchS * .pi / 180
            return (a.0 - baseY, a.1 - baseP, a.2, a.3)
        }
        var curve = abs(acTurn) > 0.35 || abs(acTurnU) > 0.35
        if let w = (wsrc)?(), w.plan.count >= 3 {
            let pl = w.plan
            for i in 1..<min(pl.count - 1, 36) {
                if Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.012 { curve = true; break }
            }
        }
        if curve { showHold = 2.5 } else { showHold -= dt }   // カーブを抜けて 2.5 秒は構えたまま（すぐ切りかわってカクつかない）
        // (左右（0 で真後ろ、＋で右）、見下ろし、距離の倍率)
        // (左右（0 で真後ろ、＋で右）、見下ろし、距離の倍率、傾き)。斜め上からの斜め構え（傾けて迫力）を、真横・真上・引きの間にはさむ
        //   6 つ目：彗星を画面のどこに置くか（横 −左 ＋右、縦 −下 ＋上。カメラの距離の割合）。左上・右上に置く構図、見下ろす構図も
        let shots: [(Double, Double, Double, Double, Double, Double)] = [
            (0, 0.16, 0.8, 0, 0, 0), (0.8, 0.45, 1.1, 0.34, 0, 0), (0.75, -0.42, 1.0, 0.16, -0.2, 0.2), (1.35, 0.22, 1.05, 0.12, 0, 0), (0.25, 1.2, 1.3, 0, 0, 0),
            (-0.8, 0.45, 1.1, -0.34, 0, 0), (-0.75, -0.42, 1.0, -0.16, 0.2, 0.2), (-1.35, 0.22, 1.05, -0.12, 0, 0), (0.55, 0.6, 1.8, 0.2, 0, 0),
            (0.7, 0.05, 0.9, -0.28, 0, 0),   // 見上げる構図（見下ろしがマイナス）：下から仰ぐので、彗星は画面の左上・右上に
            (0.3, 0.5, 3.0, 0, 0, 0), (-0.9, 0.35, 3.4, -0.08, 0, 0), (1.6, 0.8, 2.8, 0.08, 0, 0),   // 大きく引いた全体（まっすぐな所で、ときどき）
            (0.55, 0.2, 1.1, 0.8, 0, 0), (-0.55, 0.2, 1.1, -0.8, 0, 0)]   // 斜めの構図（地平線を大きく傾ける。飛行機の旋回のようにダイナミックに）
        // カーブの時：真後ろの少し斜め（曲がる側の外から）、曲がる側へ傾けて構える。彗星は真ん中
        let tsg: Double = acTurn >= 0 ? 1 : -1
        var shot: (Double, Double, Double, Double, Double, Double) = (-0.35 * tsg, 0.28, 0.85, 0.12 * tsg, 0, 0)
        if showHold > 0 { showT = 0; showIdx = 0 }
        else {
            showT += dt
            // 7 秒ごとに次の構図（忙しくない）。順番ではなくランダムに（同じのが続かない）。大きく引いた全体もときどき入る
            if showT > 7 { showT = 0; var n = Int.random(in: 0..<shots.count); if n == showIdx { n = (n + 1) % shots.count }; showIdx = n }
            shot = shots[showIdx]
        }
        showFrameT = SIMD2(shot.4, shot.5)
        // 三人称の基本の角度（camBasis：左右 chaseYawS ×（1 − 2 × 鏡の広がり）、見下ろし chasePitchS）からのずれにする
        let mw = smoothstep(0.52, 0.78, st.diveT)
        let baseY = st.chaseYawS * (1 - 2 * mw) * .pi / 180, baseP = st.chasePitchS * .pi / 180
        return (shot.0 - baseY, shot.1 - baseP, shot.2, shot.3)   // 置き場所（showFrameT）は別に渡す
    }
    func tickHeadWarp(_ w: HyperLabState.Walk, _ dt: Double) {
        var tgt = SIMD3<Double>()
        if var l = warpL, simd_dot(l, w.vL) > 0.2 {
            l = l - w.pos * simd_dot(l, w.pos); l = simd_normalize(l + (w.vL - l) * (1 - exp(-dt * 6)))
            let d = w.vL - l
            tgt = SIMD3(-simd_dot(d, w.vR), simd_dot(d, w.vU), 0) / 0.25
            if simd_length(tgt) > 1 { tgt = simd_normalize(tgt) }
            warpL = l
        } else { warpL = w.vL }
        // ばね：ω 9、減衰 0.45（曲がり始め・終わりに、ぷるっと揺れる）
        let om = 9.0, ze = 0.45, n = max(1, Int(ceil(dt / 0.005))), h = dt / Double(n)
        for _ in 0..<n { headWarpV += (om * om * (tgt - headWarp) - 2 * ze * om * headWarpV) * h; headWarp += headWarpV * h }
    }
    func lagFrame(_ w: HyperLabState.Walk, _ k0: Double, step: Double? = nil) -> (SIMD4<Double>, SIMD4<Double>, SIMD4<Double>) {
        let now = nowT, dt = step ?? min(0.05, max(0, now - lagT)); lagT = now
        lagMix += (k0 - lagMix) * (1 - exp(-dt * 2)); if k0 == 0 && lagMix < 1e-3 { lagMix = 0 }   // オートカメラを入り切りした時もなめらかに
        let k = lagMix
        if dt > 0 { tickHeadWarp(w, dt) }
        guard k > 0, var r = lagR, dt > 0 else {
            lagR = w.vR; lagU = w.vU; lagL = w.vL
            leadOff += (SIMD3() - leadOff) * (1 - exp(-dt * 2)); bank += (0 - bank) * (1 - exp(-dt * 1.2))
            return (w.vR, w.vU, w.vL)
        }
        var u = lagU, l = lagL
        if simd_dot(l, w.vL) < 0.2 || simd_dot(u, w.vU) < 0.2 { r = w.vR; u = w.vU; l = w.vL }   // 飛んだ時（初めに戻した時など）は合わせ直す
        // 接空間へ戻して（自分のいる所が進んだ分）、今の向きへ寄せる（約 0.35 秒おくれ）
        let a = 1 - exp(-dt * 2.8)
        func tan(_ v: SIMD4<Double>) -> SIMD4<Double> { v - w.pos * simd_dot(v, w.pos) }
        l = tan(l + (w.vL - l) * a); l = simd_normalize(l)
        u = tan(u + (w.vU - u) * a); u -= l * simd_dot(u, l); u = simd_normalize(u)
        r = tan(r + (w.vR - r) * a); r -= l * simd_dot(r, l); r -= u * simd_dot(r, u); r = simd_normalize(r)
        lagR = r; lagU = u; lagL = l
        // 混ぜる（三人称へ入る途中・出る途中はなめらかに）
        var fr = w.vR + (r - w.vR) * k, fu = w.vU + (u - w.vU) * k, fl = w.vL + (l - w.vL) * k
        fl = simd_normalize(tan(fl)); fu -= fl * simd_dot(fu, fl); fu = simd_normalize(tan(fu)); fr -= fl * simd_dot(fr, fl); fr -= fu * simd_dot(fr, fu); fr = simd_normalize(fr)
        // 今の向きを、おくれたカメラの 3D で：まっすぐなら奥（−z）。曲がった分（横・上下）だけ画面の中を先へ流す
        let hd = w.vL
        let h3 = SIMD3(-simd_dot(hd, fr), simd_dot(hd, fu), -simd_dot(hd, fl))
        let side3 = SIMD3(h3.x, h3.y, 0)
        leadOff += (side3 * k - leadOff) * (1 - exp(-dt * 8))
        // カメラの傾きは、そのあとから（約 0.8 秒おくれ）。曲がる側へ傾ける
        bank += (max(-1, min(1, h3.x / 0.45)) * 0.38 * k - bank) * (1 - exp(-dt * 1.2))
        return (fr, fu, fl)
    }
    /// ダイブの進み（0〜1）を、向きを合わせる分 e1（0〜0.5）と近づく分 e2（0.08〜0.92）へ。どちらもなめらかに
    static func diveEase(_ t: Double) -> (Double, Double) {
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        // 回り込み（e1）と近づき（e2）を重ねて同時に：超球が回って自分の背中が正面に来ながら、カメラがそのまま寄っていく
        return (sm(t / 0.5), sm((t - 0.08) / 0.84))
    }
    /// 毎コマ：右の超球を写す 4D の回転・カメラの位置・遠近の下限を決める（ダイブしていなければ、ふだんの傾きのまま）
    func diveSetup() {
        tickOvShot(); tickNavi()
        let m0 = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        effM = m0; effCamW = st.camW; effClamp = 0.6
        guard side == .right, dvT > 0, let w = (wsrc)?(), simd_length(w.vL) > 0.5 else { return }
        let (e1, e2) = Self.diveEase(dvT)
        // 景色と同じ向き：自分のいる所 → 4D の手前（w）、見ている向き → 画面の奥（−z）、上 → 上（y）、右 → 鏡にした x（画面の右）
        // オートカメラ（三人称）：カメラの向きは、彗星の向きを少しおくれて追う（スター・ウォーズの追いかけ。曲がる時は彗星が先に向きを変えて、
        //   画面の中を曲がる側へ流れ、あとからカメラが追いつく）
        let lagK = st.autoCam && !st.camHeld ? dvThird : 0
        let (lR, lU, lL) = lagFrame(w, lagK)
        var m1 = simd_double4x4(rows: [-lR, lU, -lL, w.pos])
        // 鏡の世界（さんぽの体の向きが裏返し）：ふつうの向きからなめらかに回して鏡写しにはできないので、超球の窓のダイブは裏返さずに描く
        if m1.determinant * m0.determinant < 0 { m1 = simd_double4x4(rows: [lR, lU, -lL, w.pos]) }
        var m = m0 + (m1 - m0) * e1
        // 正規直交に直す（グラム・シュミット。列ごと）
        var c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        for i in 0..<4 { for j in 0..<i { c[i] -= c[j] * simd_dot(c[i], c[j]) }; let l = simd_length(c[i]); if l > 1e-9 { c[i] /= l } }
        m = simd_double4x4(columns: (c[0], c[1], c[2], c[3]))
        // くるくる・ぐるぐる：入る間に、画面の右と 4 次元の奥（x′・w′）の面でもう 1・2 周回る（寄り切ると、ちょうど元の向き）
        if st.diveSpin > 0 {
            let a = 2 * Double.pi * Double(st.diveSpin) * e1, ca = cos(a), sa = sin(a)
            m = simd_double4x4(rows: [SIMD4(ca, 0, 0, -sa), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(sa, 0, 0, ca)]) * m
        }
        effM = m
        // 4D のカメラを、自分のいる所のすぐ外まで（一人称）。三人称は少し手前で止める（すぐ外まで寄ると、すぐ後ろの道が引き伸ばされて、3D のカメラの後ろへ飛んでしまう）
        effCamW = st.camW + (Self.R * (1.012 + (1.15 - 1.012) * dvThird) - st.camW) * e2
        effClamp = 0.6 + (0.004 - 0.6) * e2
        diveFov = w.fov + (55 - w.fov) * dvThird + max(-6, min(14, 22 * st.coastG))   // 三人称は少し狭く（自分のまわりを大きく）。加速で視野が広がり、減速で締まる
        tickFocus(w)
    }
    /// 確かめ用：見せ場の向きを sec 秒ぶん進めて、強さを返す
    func focusForTest(_ sec: Double) -> Double { guard let w = wsrc?() else { return 0 }; diveSetup(); for _ in 0..<Int(sec * 60) { tickFocus(w, step: 1.0 / 60) }; return focusW }
    func tickFocus(_ w: HyperLabState.Walk, step: Double? = nil) {
        let now = nowT, dt = step ?? min(0.05, max(0, now - focusT)); focusT = now
        var bestK = 0.0, bestD = SIMD3<Double>(), bestKey = "", seen: Set<String> = []
        if st.autoCam && !st.camHeld && dvThird > 0.5 && simd_length(w.vL) > 0.5 {
            let c0 = wPlace(w.pos).0
            func consider(_ q: SIMD4<Double>, _ wgt: Double, _ key: String) {
                let cs = simd_dot(q, w.pos), a = acos(max(-1, min(1, cs)))
                guard a > 0.03 else { return }
                var t = q - w.pos * cs; let tl = simd_length(t); guard tl > 1e-9 else { return }
                t /= tl
                let k = wgt * (1 - smoothstep(0.25, 0.9, a)) * smoothstep(0.1, 0.5, simd_dot(t, w.vL))   // 近くて、前の方にあるものほど
                if k > 0.01 { seen.insert(key) }
                if k > bestK && !focusUsed.contains(key) { bestK = k; bestD = wPlace(q).0 - c0; bestKey = key }
            }
            for (i, m) in w.marks.enumerated() where i >= w.hit.count || !w.hit[i] { consider(m, 1, "m\(i)") }
            if st.polesMode != 0 { for (k, p) in FIXED.enumerated() where !w.poles.contains(k) { consider(p.c, 1, "p\(k)") } }
            // カーブ：予定の道で最初に大きく曲がり始める所
            let pl = w.plan
            if pl.count >= 3 { for i in 1..<(pl.count - 1) {
                if Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.012 { let q = pl[min(pl.count - 1, i + 8)]; consider(q, 0.85, "c" + [q.x, q.y, q.z, q.w].map { String(Int(($0 * 6).rounded())) }.joined(separator: ",")); break }
            } }
        }
        // 一瞬のハイライト：新しい行き先へ 1.6 秒だけ向く。向き終えた行き先は、見えなくなる（離れる）まで使わない
        if bestKey != focusKey { focusKey = bestKey; focusAge = 0 }
        focusAge += dt
        if !bestKey.isEmpty && focusAge > 1.6 { focusUsed.insert(bestKey); bestK = 0 }
        focusUsed = focusUsed.filter { seen.contains($0) }
        let k = 1 - exp(-dt * (bestK > focusW ? 1.8 : 0.9))              // 向く時は約 0.55 秒、戻る時は約 1.1 秒
        focusW += (bestK - focusW) * k
        if bestK > 0.05, simd_length(bestD) > 1e-9 { let nd = simd_normalize(bestD); focusDir = simd_length(focusDir) < 1e-9 ? nd : simd_normalize(focusDir + (nd - focusDir) * (1 - exp(-dt * 2))) }
        if focusW < 1e-3 && bestK == 0 { focusW = 0 }
    }
}
