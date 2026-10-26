// ターンの道（ウェブ版の「🧶 ターン」のうち、半周 180° と極めぐり）：ウェブ版 s3walk.html の fillBuildHalf・fillPlan・fillStep・fqPlan・fqStep・turnStep をそのまま移した
//   半周 180°：アナ極→カタ極、カタ極→アナ極と経線（半円）を進むごとに、両方の極でターン。向きは全部から、すきまが大きく前の経線に直角に近いものを選ぶ。
//     カタ極ではアナ極と東西逆に曲がる（S³ では曲がる回転の軸を前とそろえる）。地図の軌跡が、だんだん球を埋めていく
//   極めぐり：アナ極から、となり合う極（90° はなれている）だけをたどって 8 つの極を全部回り、アナ極に戻る（アナ→東→北→天→カタ→西→南→地→アナ）。
//     90° × 8 本＝4π がいちばん短い 1 周。毎回 90° のターンで、ずっとくり返す。S² の仲間は 6 つの極を同じように回る
//   曲がり方：スムーズ＝来た道と次の道を漸近線にした双曲線で、極を少しよけながら少しずつ曲がる。直角＝極までまっすぐ進み、その場で向きを変えて、まっすぐ出る
import Foundation
import simd
import QuartzCore

// ---- 次元によらないベクトル（平らな地図は 2・3 次元、球面の点は 3・4 次元）----
typealias Vn = [Double]
@inline(__always) private func vdot(_ a: Vn, _ b: Vn) -> Double { var s = 0.0; for i in 0..<a.count { s += a[i] * b[i] }; return s }
@inline(__always) private func vadd(_ a: Vn, _ b: Vn, _ k: Double) -> Vn { var r = a; for i in 0..<a.count { r[i] += b[i] * k }; return r }
@inline(__always) private func vscl(_ a: Vn, _ k: Double) -> Vn { a.map { $0 * k } }
@inline(__always) private func vlen(_ a: Vn) -> Double { vdot(a, a).squareRoot() }
@inline(__always) private func vnrm(_ a: Vn) -> Vn { vscl(a, 1 / vlen(a)) }
private func cl1(_ x: Double) -> Double { max(-1, min(1, x)) }
private func vcross(_ a: Vn, _ b: Vn) -> Vn { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
private extension SIMD4 where Scalar == Double { var vn: Vn { [x, y, z, w] } }
private extension SIMD3 where Scalar == Double { var vn: Vn { [x, y, z] } }
private func v4(_ a: Vn) -> V4 { V4(a[0], a[1], a[2], a[3]) }
private func v3(_ a: Vn) -> V3 { V3(a[0], a[1], a[2]) }

/// 長さで並べた点の表（双曲線・直角の角）
struct TurnTable { var pts: [Vn]; var cum: [Double]; var len: Double }

enum TurnGeo {
    static let DV = 0.1                         // いちばん近づく距離（ウェブ版の FILL_DV）
    /// 曲がる角 θ が 90° をこえると双曲線の先がとがるので、先の半径が DV より小さくならないよう遠めを通る
    static func hypDV(_ th: Double) -> Double { let t = tan((Double.pi - th) / 2); return DV / min(1, t * t) }
    static func table(_ pts: [Vn]) -> TurnTable {
        var cum = [0.0]; for i in 1..<pts.count { cum.append(cum[i - 1] + vlen(vadd(pts[i], pts[i - 1], -1))) }
        return TurnTable(pts: pts, cum: cum, len: cum.last!)
    }
    /// 双曲線：x(τ) = √k (e^{−τ}(−a) + e^{τ} b)。a＝着く向き、b＝出る向き（単位ベクトル）。手前 L で入り、L 先で抜ける
    static func hyp(_ a: Vn, _ b: Vn, _ L: Double, _ n: Int) -> TurnTable {
        let th = acos(cl1(vdot(a, b)))
        var pts: [Vn] = []
        for i in 0...n {
            let f = Double(i) / Double(n)
            if th < 1e-3 { pts.append(vscl(a, -L + 2 * L * f)); continue }
            let sk = hypDV(th) / (2 * sin(th / 2)), t0 = log(max(1.0001, L / sk)), kL = sk * sk / L, tau = -t0 + 2 * t0 * f, sm = f * f * (3 - 2 * f)
            var x = vadd(vscl(a, -sk * exp(-tau)), b, sk * exp(tau))
            x = vadd(vadd(x, b, -kL * (1 - sm)), a, kL * sm)
            pts.append(x)
        }
        return table(pts)
    }
    /// 直角：角の手前 L から角、角から L 先までの 2 本の線
    static func corner(_ a: Vn, _ b: Vn, _ L: Double, _ n: Int) -> TurnTable {
        table((0...n).map { i in let s = -L + 2 * L * Double(i) / Double(n); return s < 0 ? vscl(a, s) : vscl(b, s) })
    }
    static func turn(_ a: Vn, _ b: Vn, _ L: Double, _ n: Int, sharp: Bool) -> TurnTable { sharp ? corner(a, b, L, n) : hyp(a, b, L, n) }
    /// 長さの割合 f（0〜1）の点
    static func at(_ tb: TurnTable, _ f: Double) -> Vn {
        let s = max(0, min(1, f)) * tb.len; var lo = 0, hi = tb.cum.count - 1
        while hi - lo > 1 { let m = (lo + hi) >> 1; if tb.cum[m] <= s { lo = m } else { hi = m } }
        let seg = tb.cum[hi] - tb.cum[lo], w = seg > 0 ? (s - tb.cum[lo]) / seg : 0
        return vadd(vscl(tb.pts[lo], 1 - w), tb.pts[hi], w)
    }
    /// 入る距離 L：双曲線が道に十分近づく（ずれの角が 1° ほど）まで
    static func hypL(_ a: Vn, _ b: Vn) -> Double { let th = acos(cl1(vdot(a, b))); return th < 1e-3 ? 0.3 : max(0.45, hypDV(th) / (2 * sin(th / 2)) / 0.15) }
    /// 平らな地図の点 x → 極のまわりの点（sg＝−1 ならカタ極のまわり）
    static func expN(_ x: Vn, _ sg: Double) -> Vn {
        let r = vlen(x); if r < 1e-12 { return x.map { _ in 0.0 } + [sg] }
        let s = sin(r) / r; return x.map { $0 * s } + [sg * cos(r)]
    }
    /// Q での接ベクトルの正規直交の組（1 本目は着く向き a）
    static func basis(_ Q: Vn, _ a: Vn) -> [Vn] {
        var E = [a]
        for i in 0..<Q.count {
            if E.count >= Q.count - 1 { break }
            var v = Vn(repeating: 0, count: Q.count); v[i] = 1
            var t = vadd(v, Q, -vdot(v, Q)); for e in E { t = vadd(t, e, -vdot(t, e)) }
            if vlen(t) > 1e-3 { E.append(vnrm(t)) }
        }
        return E
    }
    static func fromFlat(_ Q: Vn, _ E: [Vn], _ x: Vn) -> Vn {
        let r = vlen(x); if r < 1e-12 { return Q }
        var t = vscl(Q, 0); for (i, xi) in x.enumerated() { t = vadd(t, E[i], xi) }
        return vadd(vscl(Q, cos(r)), t, sin(r) / r)
    }

    /// 半周 180° の経線の向き（S³ は球面ぜんたいの候補、S² は 0〜360° を 0.5° おき）
    static let half: (dirs: [Vn], gaps: [Double], ph: [Double]) = {
        func pick(_ cand: [Vn], _ d0: Vn, _ N: Int, _ crossOf: (Vn, Vn) -> Vn) -> ([Vn], [Double]) {
            let ang = { (c: Vn, d: Vn) in acos(cl1(vdot(c, d))) }
            var dirs = [d0], gaps = [180.0], best = cand.map { ang($0, d0) }, kPrev: Vn? = nil
            while dirs.count < N {
                let mx = best.max() ?? 0
                if mx < 1e-6 { break }
                let prev = dirs.last!, a = vscl(prev, -1); var bi = -1, bs = Double.infinity
                for i in 0..<cand.count {
                    if best[i] < 0.75 * mx - 1e-9 { continue }
                    let c = cand[i]; var sc = abs(vdot(prev, c)) - 0.15 * best[i] / mx
                    if let kp = kPrev, vdot(crossOf(a, c), kp) < 0 { sc += 0.5 }
                    if sc < bs { bs = sc; bi = i }
                }
                let c = cand[bi]; dirs.append(c); gaps.append(best[bi] / d2r)
                let k = crossOf(vscl(prev, -1), c)
                if vlen(k) > 1e-6 { kPrev = k.count == 1 ? [k[0] > 0 ? 1 : -1] : vnrm(k) }
                for i in 0..<cand.count { best[i] = min(best[i], ang(cand[i], c)) }
            }
            return (dirs, gaps)
        }
        var c3: [Vn] = [], seen = Set<String>()
        for n in [1, 2, 3, 4, 6, 8, 12, 16] { for i in -n...n { for j in -n...n {
            let k0 = n - abs(i) - abs(j); if k0 < 0 { continue }
            for k in k0 != 0 ? [k0, -k0] : [0] {
                let v = vnrm([Double(i), Double(j), Double(k)]), key = v.map { String(Int(($0 * 1e6).rounded())) }.joined(separator: ",")
                if !seen.contains(key) { seen.insert(key); c3.append(v) }
            }
        } } }
        let r3 = pick(c3, [1, 0, 0], 300, vcross)
        let c2: [Vn] = (0..<720).map { i in let t = Double(i) * Double.pi / 360; return [cos(t), sin(t)] }
        let r2 = pick(c2, [1, 0], 300) { a, b in [a[0] * b[1] - a[1] * b[0]] }
        return (r3.0, r3.1, r2.0.map { atan2($0[1], $0[0]) })
    }()
    // 極めぐりの順：アナ・東・北・天・カタ・西・南・地（S² はアナ・東・北・カタ・西・南）
    static let R3: [Vn] = [[0, 0, 0, 1], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, -1], [-1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, 0]]
    static let R2: [Vn] = [[0, 0, 1], [1, 0, 0], [0, 1, 0], [0, 0, -1], [-1, 0, 0], [0, -1, 0]]
    static let R3name = ["アナ極", "東極", "北極", "天極", "カタ極", "西極", "南極", "地極"], R2name = ["アナ極", "東極", "北極", "カタ極", "西極", "南極"]
}

/// ターン 1 回ぶん（S³ と S² の表、直角の時の向きの回し）
struct TurnRun {
    var f = 0.0, L: Double, h3: TurnTable, h2: TurnTable, sharp: Bool
    var to3: (Vn) -> Vn, to2: (Vn) -> Vn
    var pv: Pivot? = nil, pvDone = false
    struct Pivot { var t = 0.0, len: Double, F: Walker, G: Walker2, A3: V4, B3: V4, th3: Double, A2: V3, B2: V3, th2: Double }
}
/// ターンの道の進み具合
struct TurnWalk {
    // 半周 180°
    var T = 0.002, nx = 1, half: (lap: Int, run: TurnRun)? = nil, turning = false
    // 極めぐり
    var leg = 0, P: Vn = [0, 0, 0, 1], b: Vn = [1, 0, 0, 0], P2: Vn = [0, 0, 1], b2: Vn = [1, 0, 0], s = 0.002, plan: (TurnRun, Int)? = nil, tourTurn = false
}

extension Renderer {
    // ---- 半周 180° ----
    private func hU(_ lap: Int) -> Vn { TurnGeo.half.dirs[lap % TurnGeo.half.dirs.count] }
    private func hU2(_ lap: Int) -> Vn { let ph = TurnGeo.half.ph[lap % TurnGeo.half.ph.count]; return [cos(ph), sin(ph)] }
    private func hPoint(_ T: Double) -> (V4, V3) {
        let lap = max(0, Int(floor(T / Double.pi))), th = T - Double(lap) * Double.pi, sn = sin(th), cs = cos(th) * (lap % 2 == 1 ? -1 : 1)   // カタ極からの半円は w を逆に
        let u = hU(lap), ph = TurnGeo.half.ph[lap % TurnGeo.half.ph.count]
        return (V4(sn * u[0], sn * u[1], sn * u[2], cs), V3(sn * cos(ph), sn * sin(ph), cs))
    }
    private func hPlan(_ nx: Int) -> TurnRun {
        let lap = nx - 1, a3 = vscl(hU(lap), -1), b3 = hU(nx), a2 = vscl(hU2(lap), -1), b2 = hU2(nx)   // 着く向き：極へ向かうので −u
        let L = min(1.3, max(TurnGeo.hypL(a3, b3), TurnGeo.hypL(a2, b2))), sg: Double = nx % 2 == 1 ? -1 : 1
        return TurnRun(L: L, h3: TurnGeo.turn(a3, b3, L, 240, sharp: set.turnSharp), h2: TurnGeo.turn(a2, b2, L, 240, sharp: set.turnSharp), sharp: set.turnSharp,
                       to3: { TurnGeo.expN($0, sg) }, to2: { TurnGeo.expN($0, sg) })
    }
    // ---- 極めぐり ----
    private func tourPlan() -> TurnRun {
        let LEN = Double.pi / 2, t = turn
        let Q = vadd(vscl(t.P, cos(LEN)), t.b, sin(LEN)), a = vnrm(vadd(vscl(t.P, -sin(LEN)), t.b, cos(LEN)))
        let Q2 = vadd(vscl(t.P2, cos(LEN)), t.b2, sin(LEN)), a2 = vnrm(vadd(vscl(t.P2, -sin(LEN)), t.b2, cos(LEN)))
        let T3 = TurnGeo.R3[(t.leg + 2) % 8], T2 = TurnGeo.R2[(t.leg + 2) % 6]
        let E3 = TurnGeo.basis(Q, a), E2 = TurnGeo.basis(Q2, a2), u3 = E3.map { vdot(T3, $0) }, u2 = E2.map { vdot(T2, $0) }
        let f3: Vn = [1, 0, 0], f2: Vn = [1, 0], L = min(0.75, max(TurnGeo.hypL(f3, u3), TurnGeo.hypL(f2, u2)))
        let run = TurnRun(L: L, h3: TurnGeo.turn(f3, u3, L, 240, sharp: set.turnSharp), h2: TurnGeo.turn(f2, u2, L, 240, sharp: set.turnSharp), sharp: set.turnSharp,
                          to3: { TurnGeo.fromFlat(Q, E3, $0) }, to2: { TurnGeo.fromFlat(Q2, E2, $0) })
        return run
    }

    /// ターンの道を歩き始める（アナ極から）
    func startTurn(_ m: PathMode) {
        resetNorth(); pathMode = m; turn = TurnWalk()
        if m == .half {
            _ = TurnGeo.half
            let (p, p2) = hPoint(turn.T); cam.w.p = p; journey.w2.p = p2; orthoFrame(&cam.w); orthoW2()
            say?("半周 180°：アナ極→カタ極→アナ極と経線を進み、両方の極でターン（" + (set.turnSharp ? "直角" : "スムーズ") + "）")
        } else {
            let s = turn.s
            cam.w.p = v4(vadd(vscl(turn.P, cos(s)), turn.b, sin(s))); journey.w2.p = v3(vadd(vscl(turn.P2, cos(s)), turn.b2, sin(s))); orthoFrame(&cam.w); orthoW2()
            say?("極めぐり：となりの極だけをたどって 8 つの極を回る（" + (set.turnSharp ? "直角" : "スムーズ") + "）")
        }
    }

    /// qp・qp2 へ進む（体は進む向きにそろえる＝前を向いたまま曲がる。S² も同じ。ウェブ版の fillGo）
    private func turnGo(_ qp: V4, _ qp2: V3) {
        let W = cam.w, W2 = journey.w2
        let dr = qp - W.p * dot4(qp, W.p), dr2 = qp2 - W2.p * simd_dot(qp2, W2.p)
        let s3 = acos(cl1(dot4(qp, W.p)))
        guard s3 > 1e-9, simd_length(dr) > 1e-12, simd_length(dr2) > 1e-12 else { return }
        let d = nrm(dr), d2 = simd_normalize(dr2), s2 = acos(cl1(simd_dot(qp2, W2.p)))
        let p0 = W.p, p02 = W2.p
        moveAlong(&cam.w, d, s3); moveAlong2(&journey.w2, d2, s3)
        lastDir = d; lastDirT = CACurrentMediaTime()
        cam.w.p = qp; journey.w2.p = qp2
        journey.walked(cam.w.p, s3, footOn: set.foot) { [weak self] m in
            if self?.set.haptics == true { Haptic.milestone() }
            self?.say?(m)
        }
        let dd = nrm(p0 * -sin(s3) + d * cos(s3)), dd2 = simd_normalize(p02 * -sin(s2) + d2 * cos(s2))
        func g(_ v: V4, _ P: V4, _ others: [V4]) -> V4 { var t = v - P * dot4(v, P); for o in others { t -= o * dot4(t, o) }; return nrm(t) }
        cam.w.f = dd; cam.w.r = g(cam.w.r, cam.w.p, [cam.w.f]); cam.w.u = g(cam.w.u, cam.w.p, [cam.w.f, cam.w.r])
        var r2 = journey.w2.r - qp2 * simd_dot(journey.w2.r, qp2); r2 -= dd2 * simd_dot(r2, dd2)
        journey.w2.f = dd2; journey.w2.r = simd_normalize(r2)
        cam.az = 0; cam.el = 0
    }
    /// ターンを 1 歩すすめる。終わったら true（直角では角でいったん止まり、その場で向きを回す）
    private func turnStepRun(_ tu: inout TurnRun, _ ds: Double) -> Bool {
        if var pv = tu.pv {
            pv.t = min(1, pv.t + ds / pv.len); let e = pv.t * pv.t * (3 - 2 * pv.t)
            func rot4(_ v: V4) -> V4 { let c1 = dot4(v, pv.A3), c2 = dot4(v, pv.B3), co = cos(pv.th3 * e) - 1, si = sin(pv.th3 * e); return v + pv.A3 * (c1 * co - c2 * si) + pv.B3 * (c1 * si + c2 * co) }
            func rot3(_ v: V3) -> V3 { let c1 = simd_dot(v, pv.A2), c2 = simd_dot(v, pv.B2), co = cos(pv.th2 * e) - 1, si = sin(pv.th2 * e); return v + pv.A2 * (c1 * co - c2 * si) + pv.B2 * (c1 * si + c2 * co) }
            cam.w.f = rot4(pv.F.f); cam.w.r = rot4(pv.F.r); cam.w.u = rot4(pv.F.u); orthoFrame(&cam.w)
            journey.w2.f = rot3(pv.G.f); journey.w2.r = rot3(pv.G.r); orthoW2()
            cam.az = 0; cam.el = 0
            if pv.t >= 1 { tu.pv = nil; tu.pvDone = true } else { tu.pv = pv }
            return false
        }
        let f = min(1, tu.f + ds / max(1e-6, tu.h3.len))
        if tu.sharp && !tu.pvDone && f >= 0.5 {   // 角に着いた：ちょうど角まで進んで、向きを回し始める
            tu.f = 0.5; turnGo(v4(tu.to3(TurnGeo.at(tu.h3, 0.5))), v3(tu.to2(TurnGeo.at(tu.h2, 0.5))))
            func plane4(_ P: V4, _ Q: V4, _ d: V4) -> (V4, V4, Double) {
                let t = nrm(Q - P * dot4(Q, P)), A = nrm(d - P * dot4(d, P)), B0 = t - A * dot4(t, A), bl = simd_length(B0)
                return (A, bl > 1e-6 ? B0 / bl : A, acos(cl1(dot4(A, t))))
            }
            func plane3(_ P: V3, _ Q: V3, _ d: V3) -> (V3, V3, Double) {
                let t = simd_normalize(Q - P * simd_dot(Q, P)), A = simd_normalize(d - P * simd_dot(d, P)), B0 = t - A * simd_dot(t, A), bl = simd_length(B0)
                return (A, bl > 1e-6 ? B0 / bl : A, acos(cl1(simd_dot(A, t))))
            }
            let p3 = plane4(cam.w.p, v4(tu.to3(TurnGeo.at(tu.h3, 0.52))), cam.w.f), p2 = plane3(journey.w2.p, v3(tu.to2(TurnGeo.at(tu.h2, 0.52))), journey.w2.f)
            tu.pv = TurnRun.Pivot(len: 0.12 + 0.3 * max(p3.2, p2.2) / (Double.pi / 2), F: cam.w, G: journey.w2, A3: p3.0, B3: p3.1, th3: p3.2, A2: p2.0, B2: p2.1, th2: p2.2)
            return false
        }
        tu.f = f; turnGo(v4(tu.to3(TurnGeo.at(tu.h3, f))), v3(tu.to2(TurnGeo.at(tu.h2, f))))
        return f >= 1
    }

    /// ターンの道に沿って ds 進む（ウェブ版の fillStep・fqStep）
    func turnStep(_ ds: Double) {
        if pathMode == .half {
            if turn.turning, var tu = turn.half?.run {
                let done = turnStepRun(&tu, ds); turn.half?.run = tu
                if done, let h = turn.half { turn.turning = false; turn.T = Double(h.lap) * Double.pi + h.run.L; turn.half = (h.lap + 1, hPlan(h.lap + 1)) }
                return
            }
            let lap = Int(floor(turn.T / Double.pi))
            turn.T += ds
            if turn.half == nil || turn.half!.lap != lap + 1 { turn.half = (lap + 1, hPlan(lap + 1)) }
            let P = turn.half!.run
            if Double(lap + 1) * Double.pi - turn.T <= P.L {   // 極の手前 L：ターンに入る
                let nx = lap + 1
                turn.turning = true; turn.half!.run.f = 0
                turn.T = Double(nx) * Double.pi - P.L
                let (q, q2) = hPoint(turn.T); turnGo(q, q2)
                let a3 = vscl(hU(lap), -1), b3 = hU(nx), a2 = vscl(hU2(lap), -1), b2 = hU2(nx)
                let th = acos(cl1(vdot(a3, b3))) / d2r, th2 = acos(cl1(vdot(a2, b2))) / d2r
                say?(String(format: "%d 本目へ：%@で %.1f° ターン（S² では %.1f°、%@）", nx + 1, nx % 2 == 1 ? "カタ極" : "アナ極", th, th2, set.turnSharp ? "直角" : "双曲線"))
                return
            }
            let (q, q2) = hPoint(turn.T); turnGo(q, q2)
        } else if pathMode == .tour {
            let LEN = Double.pi / 2
            if turn.tourTurn, var tu = turn.plan?.0 {
                let done = turnStepRun(&tu, ds); turn.plan?.0 = tu
                if done {
                    let k = turn.leg + 2
                    turn.tourTurn = false; turn.leg += 1
                    turn.P = tu.to3(vscl([1, 0, 0], 0)); turn.b = TurnGeo.R3[k % 8]
                    turn.P2 = tu.to2(vscl([1, 0], 0)); turn.b2 = TurnGeo.R2[k % 6]
                    turn.s = tu.L; turn.plan = nil
                }
                return
            }
            turn.s += ds
            if turn.plan == nil && turn.s >= LEN - 0.75 { turn.plan = (tourPlan(), turn.leg) }
            if let pl = turn.plan, LEN - turn.s <= pl.0.L {   // ターンに入る
                turn.s = LEN - pl.0.L
                turnGo(v4(vadd(vscl(turn.P, cos(turn.s)), turn.b, sin(turn.s))), v3(vadd(vscl(turn.P2, cos(turn.s)), turn.b2, sin(turn.s))))
                turn.tourTurn = true; turn.plan!.0.f = 0
                let i = (turn.leg + 1) % 8, j = (turn.leg + 2) % 8, i2 = (turn.leg + 1) % 6, j2 = (turn.leg + 2) % 6
                say?("\(TurnGeo.R3name[i])で 90° ターン → \(TurnGeo.R3name[j])へ（S² では \(TurnGeo.R2name[i2]) → \(TurnGeo.R2name[j2])）")
                return
            }
            turnGo(v4(vadd(vscl(turn.P, cos(turn.s)), turn.b, sin(turn.s))), v3(vadd(vscl(turn.P2, cos(turn.s)), turn.b2, sin(turn.s))))
        }
    }
}
