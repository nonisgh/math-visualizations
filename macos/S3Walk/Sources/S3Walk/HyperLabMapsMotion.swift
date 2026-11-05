// 超球の窓の地図の動き：下の地図の見せ場（切る・回り込む）と、上の地図のナビ
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    /// YZ の面（x ＝ 0）の法線：x 軸が地図の 3D でどちらを向いているか
    func ovYZNormal() -> SIMD3<Double> { let v = xf(st.ovView == 1 ? SIMD4(0, 1, 0, 0) : SIMD4(1, 0, 0, 0)); return SIMD3(v.x, v.y, v.z) }   // X-W 地図は x をつぶすので y
    /// くさびの向き：c は開く真ん中の向き（カメラの側）、t は c と軸に直角な向き
    func ovWedgeAxes() -> (c: SIMD3<Double>, t: SIMD3<Double>) {
        let B = camBasis().3
        var n = ovYZNormal(); let l = simd_length(n); n = l > 1e-6 ? n / l : camBasis().1
        if simd_dot(n, B) < 0 { n = -n }
        let v4 = xf(SIMD4(0, 0, 0, 1)); var a = SIMD3(v4.x, v4.y, v4.z); a -= n * simd_dot(a, n)    // くさびの軸：w 軸の見え方（YZ の面の中）
        if simd_length(a) < 1e-6 { a = camBasis().2 - n * simd_dot(camBasis().2, n) }
        a = simd_normalize(a)
        var m = simd_cross(a, n); if simd_dot(m, B) < 0 { m = -m }
        let hw = Double.pi / 4                                            // 90° の半分。開ききった時、2 枚の面が YZ の面とそれに直角の面になる
        return (m * cos(hw) + n * sin(hw), n * cos(hw) - m * sin(hw))
    }
    func tickOvShot() {
        guard overview, ovMotion, st.ovShow, ovLive, let w = (wsrc)?() else { ovM = nil; ovBase = nil; ovCutK = 0; ovPeekT = -1; ovWedgeT = -1; ovWedgeK = 0; ovPitch = 0; ovPitchV = 0; ovViewYaw = 0; ovYawV = 0; ovBall = 0; ovSpin = 0; ovSpinRate = 0; ovBornT = -1; ovFlipT = -1; return }
        let now = nowT, dt = max(0, min(0.1, now - ovLast)); ovLast = now
        let rr = simd_length(wPlace(w.pos).0) / (Self.R * Self.SCALE)
        // シャッフル：消失させる軸を、14 秒ごとにランダムに切りかえる
        if st.ovShuffle && now - ovShufT > 14 { ovShufT = now; if ovM != nil { st.ovView = [0, 1, 2, 3].filter { $0 != st.ovView }.randomElement() ?? 0; st.ovFlip = Bool.random() } }
        if !st.ovShuffle { ovShufT = now }
        // 地図の奥深くを横へ通る時だけ：彗星のすぐ手前までを切って中を見せて、3 秒でゆっくり閉じる（30 秒あける）
        let climb = abs(w.fwd.w)
        if ovM == nil { ovCutLast = now; ovWedgeLast = now; ovBornT = now; ovFlipT = now }   // はじめの 30 秒は切らない（地図の向きが定まる前）
        // 見せ場：玉の近くを w に沿って上り下りする時に、地球の断面図のように 90° 開いて中を見せる（8 秒。45 秒あける）
        let nested = st.ovView == 3, manual = nested && st.ovFx > 0      // W 消失地図：おまかせはほかの地図と同じ見せ場。切り方を手で選ぶと、その切り方のまま
        if !manual && ovWedgeT < 0 && ovPeekT < 0 && (nested || ovCutK < 0.05) && climb > 0.6 && abs(w.pos.w) > 0.55 && now - max(ovWedgeLast + 15, ovCutLast) > 30 && simd_length(ovYZNormal()) > 0.3 {
            ovWedgeT = now; ovWedgeLast = now
            if Self.glintLog { print(String(format: "くさび %.1f 秒 %@", now, w.fwd.w > 0 ? "上り" : "下り")) }
        }
        if ovWedgeT >= 0 && now - ovWedgeT > 8 { ovWedgeT = -1 }
        // W 消失地図で手で選んだ切り方：0 半分・1 くさび・2 玉ねぎ・3 ポリゴン・4 回る断面
        let fx = manual ? st.ovFx - 1 : -1
        if fx != ovFxNow { ovFxNow = fx; if fx == 3 { ovFxSeed = Float.random(in: 0..<100) } }
        let fxRate = 1 - exp(-dt * 1.5)
        ovOnionK += ((fx == 2 ? 1 : 0) - ovOnionK) * fxRate; ovPolyK += ((fx == 3 ? 1 : 0) - ovPolyK) * fxRate; ovSpinK += ((fx == 4 ? 1 : 0) - ovSpinK) * fxRate
        ovWedgeK += ((ovWedgeT >= 0 || fx == 1 ? 1 : 0) - ovWedgeK) * (1 - exp(-dt * 1.2))
        if ovWedgeK < 0.002 { ovWedgeK = 0 }
        if !manual && ovPeekT < 0 && ovWedgeT < 0 && ovWedgeK < 0.05 && rr < 0.5 && climb < 0.35 && now - ovCutLast > 30 {
            ovPeekT = now; ovCutLast = now
            if Self.glintLog { print(String(format: "中の断面 %.1f 秒 中心から %.2f", now, rr)) }
        }
        if ovPeekT >= 0 && now - ovPeekT > 3 { ovPeekT = -1 }
        var open = fx == 0 || fx == 4 || (nested && !manual && ovWedgeT < 0) ? 0.97 : 0.0   // W 消失地図のおまかせ：入れ子なので手前をいつも切って中を見せ、その上にほかの地図と同じ見せ場（くさびで 90° 開く・透かし）を重ねる
        if ovPeekT >= 0 && !nested {
            let depth = simd_dot(wPlace(w.pos).0, camBasis().3) / (Self.R * Self.SCALE * 1.15)
            open = max(0.2, min(0.75, 0.9 - depth))
        }
        ovCutK += (open - ovCutK) * (1 - exp(-dt * (open > ovCutK ? 4 : 2)))
        if ovCutK < 0.002 { ovCutK = 0 }
        // 中を上り下りする間は、間の殻を消す（層を動いているのがよくわかる）。切っている間は切り口を見せる
        let fadeTo: Double = !manual && climb > 0.45 && rr < 0.92 && ovPeekT < 0 && ovWedgeT < 0 ? 1 : 0
        if Self.glintLog && fadeTo > 0 && ovBall < 0.02 { print(String(format: "下を消す %.1f 秒", now)) }
        ovBall += (fadeTo - ovBall) * (1 - exp(-dt * (fadeTo > ovBall ? 3.5 : 1.2)))
        if ovBall < 0.002 { ovBall = 0 }
        // 向き：選んだ地図の軸へ、なめらかに回す（消失させる軸を 4 次元の奥行きに）。Y：w が上で球層は水平。X：w が右で球層は縦。Z：w が手前でアナ極が正面。W：赤と紫が真ん中で入れ子
        let (ri, ui, di, hi) = [(0, 3, 2, 1), (3, 1, 2, 0), (0, 1, 3, 2), (0, 1, 2, 3)][max(0, min(3, st.ovView))]
        func axis(_ i: Int) -> SIMD4<Double> { var v = SIMD4<Double>(repeating: 0); v[i] = 1; return v }
        var rowsTo = [axis(ri), axis(ui), axis(di), axis(hi)]
        if st.ovFlip { for i in 0..<4 where rowsTo[i].w != 0 { rowsTo[i] = -rowsTo[i] } }   // 反転：w の頭とケツを入れかえる
        var goal = simd_double4x4(rows: rowsTo)
        if simd_determinant(goal) < 0 { rowsTo[hi == 3 ? 0 : 3] = -rowsTo[hi == 3 ? 0 : 3]; goal = simd_double4x4(rows: rowsTo) }   // 鏡写しにしない
        let m0 = ovBase ?? simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        let t = m0.transpose, g2 = goal.transpose, k = 1 - exp(-dt * 1.2)
        var rows = [t.columns.0, t.columns.1, t.columns.2, t.columns.3].enumerated().map { i, r in r + ((i == 0 ? g2.columns.0 : i == 1 ? g2.columns.1 : i == 2 ? g2.columns.2 : g2.columns.3) - r) * k }
        for i in 0..<4 { for j in 0..<i { rows[i] -= rows[j] * simd_dot(rows[i], rows[j]) }; let l = simd_length(rows[i]); rows[i] = l > 1e-9 ? rows[i] / l : axis(i) }   // 回転の形に直す
        ovBase = simd_double4x4(rows: rows); ovM = ovBase
        // カメラは地図のまわりをゆっくり回り込む：奥へ向かう動きは横から見える向きへ（35° まで）、上り下りは少し上・下から（17° まで）。ばねでゆっくり
        let a3 = wPlace(w.pos).0, v3 = wPlace(simd_normalize(w.pos + w.fwd * 0.05)).0 - a3, vl = simd_length(v3)
        var yawTo = 0.0, pitTo = 0.0
        if vl > 1e-6 {
            if hypot(v3.x, v3.z) / vl > 0.3 { var y = atan2(-v3.z, v3.x); if y > .pi / 2 { y -= .pi } else if y <= -.pi / 2 { y += .pi }; yawTo = max(-0.6, min(0.6, y)) }
            pitTo = 0.3 * v3.y / vl
        }
        if ovWedgeT >= 0 && !nested { let c = ovWedgeAxes().c; yawTo = max(-0.7, min(0.7, atan2(c.x, c.z))); pitTo = 0.35 }   // 開いている間は、くさびの正面の少し上へ回って、2 枚の切り口を見せる
        let camOm = 0.3
        // W 消失地図のおまかせ：地図が定まって 6 秒たったら、カメラがゆっくり回り続ける（跡と自分の場所をいろいろな側から）。
        //   自分が裏（カメラから見て奥の半分）を走っている間は、もっとゆっくり。手で選んだ切り方の時は回さない
        let behind = simd_dot(a3, camBasis().3) < 0
        let spinTo = nested && !manual && now - ovBornT > 6 ? (behind ? 0.035 : 0.1) : 0
        ovSpinRate += (spinTo - ovSpinRate) * (1 - exp(-dt * 0.8)); ovSpin += ovSpinRate * dt
        if ovSpin > 2 * .pi { ovSpin -= 2 * .pi }
        // ときどき w の頭とケツを反転する（45 秒に 1 回。真ん中あたりを走っている時だけ：入れ子の内と外が入れかわっても、自分の場所の見た目が大きく変わらない）
        if nested && !manual && !st.ovShuffle && now - ovFlipT > 45 && abs(w.pos.w) < 0.35 { ovFlipT = now; st.ovFlip.toggle() }
        ovYawV += (camOm * camOm * (yawTo - ovViewYaw) - 2 * camOm * ovYawV) * dt; ovViewYaw += ovYawV * dt
        ovPitchV += (camOm * camOm * (pitTo - ovPitch) - 2 * camOm * ovPitchV) * dt; ovPitch += ovPitchV * dt
        ovZoomK += ((nested && st.ovZoom ? 0.3 : 1) - ovZoomK) * (1 - exp(-dt * 2.2))   // 真ん中へ寄る
        // 手で回した分は、離して 0.8 秒たったら、なめらかに元へ戻す
        if !st.ovDragging && CACurrentMediaTime() - st.ovDragT > 0.8 { let k = 1 - exp(-dt * 1.6); st.ovDragYaw -= st.ovDragYaw * k; st.ovDragPitch -= st.ovDragPitch * k }
    }
    func tickNavi() {
        guard overview, !ovMotion, st.naviCenter, ovLive, let w = (wsrc)?(), simd_length(w.vL) > 0.5, simd_length(w.vR) > 0.5 else {
            if overview && !ovMotion && naviM != nil { st.splitK = 0; st.splitP = 0; st.splitA.k = 0; splitVel = 0 }
            naviM = nil; naviBall = 0; naviHole = 0; return }
        let now = nowT, dt = max(0, min(0.1, now - naviLast)); naviLast = now
        let p = simd_normalize(w.pos), f0 = simd_length(w.fwd) > 0.5 ? w.fwd : w.vL
        if naviM == nil { naviR = w.vR; naviF = f0; naviU = w.vU }
        let k = 1 - exp(-dt * 3)
        // 地図の右は w の方向へそろえる（球面を回ると体の向きは少しずつ回ってたまるので、体の右のままだと、一番大きな球殻を走る線が斜めになる）。
        //   w に沿って上り下りする所と玉のそばは、w の方向が決まらないので体の右のまま。なめらかにつなぐ。左右は今の向きに近い方
        var rTo = w.vR, up = 1.0
        let w4 = SIMD4<Double>(0, 0, 0, 1), f1 = simd_normalize(f0 - p * simd_dot(f0, p)), wt = w4 - p * p.w - f1 * f1.w, wl = simd_length(wt)
        if wl > 1e-6 {
            let lv = smoothstep(0.25, 0.6, wl), tn = wt / wl
            rTo = w.vR * (1 - lv) + (simd_dot(tn, naviR) >= 0 ? tn : -tn) * lv; up = 1 - lv
        }
        naviF += (f0 - naviF) * k; naviR += (rTo - naviR) * k; naviU += (w.vU - naviU) * k * up
        // 今いる所に接する向きへ直して、たがいに直交させる
        func clean(_ v: SIMD4<Double>, _ o: [SIMD4<Double>]) -> SIMD4<Double> { var t = v; for q in o { t -= q * simd_dot(t, q) }; let l = simd_length(t); return l < 1e-9 ? v : t / l }
        naviF = clean(naviF, [p]); naviR = clean(naviR, [p, naviF]); naviU = clean(naviU, [p, naviF, naviR])
        // 右・上はそのままで、奥行きの向きを選ぶ：鏡写しにならないように（下の地図と同じ向きの世界になる）
        let m = simd_double4x4(rows: [naviR, naviF, naviU, p])
        naviM = simd_determinant(m) < 0 ? simd_double4x4(rows: [naviR, naviF, -naviU, p]) : m
        // 赤玉・紫玉の交差の間だけ、間の殻を透かす（正反対の玉と交わる所が見える）。さっと透けて、少し遅れて戻る
        let ap = abs(p), ak = (0..<4).max { ap[$0] < ap[$1] } ?? 3
        let toBall = acos(min(1, ap[ak])), want: Double = toBall < 0.62 && ak == 3 ? 1 : 0
        if Self.glintLog && want > 0 && naviBall < 0.02 { print(String(format: "透かす %.1f 秒", now)) }
        naviBall += (want - naviBall) * (1 - exp(-dt * (want > 0 ? 3.5 : 2.4)))
        // 赤玉・紫玉の交差：上の地図をゆっくり大きくして、通り過ぎたらゆっくり戻す。単振動のなめらかさ（cos の半周。動き出しと止まりの速さが 0）で、3.2 秒で開いて 3.6 秒で戻す
        let bigTo: Double = ak == 3 && toBall < 0.75 ? 1 : 0
        st.splitP = max(0, min(1, st.splitP + (bigTo > 0 ? dt / 3.2 : -dt / 3.6)))
        // 折り返しの角を少し丸める：cos の動きを、弱いばねで追う
        let splitTo = 0.5 - 0.5 * cos(.pi * st.splitP)
        splitVel += (16 * (splitTo - st.splitK) - 8 * splitVel) * dt
        st.splitK = max(0, min(1, st.splitK + splitVel * dt))
        if st.splitK < 1e-4 && splitTo == 0 { st.splitK = 0; splitVel = 0 }
        if abs(st.splitA.k - st.splitK) > 0.004 || (st.splitK == 0 && st.splitA.k != 0) { st.splitA.k = st.splitK }
        // 自分のまわりの穴：入れている間は開けておく。赤玉・紫玉の交差の間は閉じる（間の殻が透けるので見える）
        naviHole += ((want > 0 || !st.holeOn ? 0 : 1) - naviHole) * (1 - exp(-dt * 2.5))
    }
}
