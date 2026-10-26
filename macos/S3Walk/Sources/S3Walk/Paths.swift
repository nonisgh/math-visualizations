// 決まった道を歩く（ウェブ版の螺旋・回る輪）：道の式 point(T) を、道のりが 1 コマぶん進むように T を進めてたどる
//   螺旋（竜巻）：アナ極からの距離 θ を進めながら、まわりの角 φ = 2·巻き数·θ を回す。傾きで巻く面がアナ→カタで傾き、歳差で 1 周ごとに輪の面が回る
//   回る輪：アナ極とカタ極を通る大円を歩き、1 周ごとに輪の向きを少し回す（軸 x・y・z は球面 S² の上、w は赤道 w = 0 の上、全部は向きの球ぜんたい）
import Foundation
import simd

/// 決まった道：螺旋・回る輪（この下）、半周 180° のターン・極めぐり（Turns.swift）
enum PathMode: Int { case none = 0, spiral = 1, ring = 2, half = 3, tour = 4 }

struct PathWalk {
    var th = 0.002, lap = 0            // 螺旋
    var T = 0.002, lapSaid = 0         // 回る輪

    static func spiralPoint(_ th: Double, _ lap: Int, _ s: Settings) -> (V4, V3) {
        let k = 2 * s.turns, ph = k * th, sn = sin(th)
        let psi = Double.pi / 2 - s.tilt * (Double.pi / 2) * cos(th), sp = sin(psi), cp = cos(psi)
        var x = sp * cos(ph), y = sp * sin(ph), z = cp
        if s.prec != 0 {                                         // 歳差：輪の面を x 軸のまわりに、1 周で prec 度
            let a = s.prec * d2r * (Double(lap) + th / (2 * Double.pi)), ca = cos(a), sa = sin(a)
            let y2 = ca * y - sa * z, z2 = sa * y + ca * z; y = y2; z = z2
        }
        return (V4(sn * x, sn * y, sn * z, cos(th)), V3(sn * cos(ph), sn * sin(ph), cos(th)))
    }
    static func ringDir(_ T: Double, _ s: Settings) -> V3 {
        let ph = s.ringStep * d2r * (T / (2 * Double.pi))
        if s.ringAxis == 4 { let al = Double.pi / 2 + (Double.pi / 2 - 0.08) * sin(ph / 9); return V3(sin(al) * cos(ph), sin(al) * sin(ph), cos(al)) }
        let c = cos(ph), sn = sin(ph)
        return s.ringAxis == 0 ? V3(0, c, sn) : s.ringAxis == 1 ? V3(sn, 0, c) : V3(c, sn, 0)
    }
    static func ringPoint(_ T: Double, _ s: Settings) -> (V4, V3) {
        let th = T.truncatingRemainder(dividingBy: 2 * Double.pi), sn = sin(th), cs = cos(th), ph = s.ringStep * d2r * (T / (2 * Double.pi))
        let p2 = V3(sn * cos(ph), sn * sin(ph), cs)
        if s.ringAxis == 3 { return (V4(sn * cos(ph), sn * sin(ph), cs, 0), p2) }   // 軸 w：輪は +z と −z を通り、赤道 w = 0 の上を回る
        let u = ringDir(T, s); return (V4(sn * u.x, sn * u.y, sn * u.z, cs), p2)
    }
}

extension Renderer {
    /// 決まった道を歩き始める（アナ極から）
    func startPath(_ m: PathMode) {
        pathSpeed = 1
        if m == .half || m == .tour { startTurn(m); return }
        resetNorth(); pathMode = m; path = PathWalk()
        if m == .ring {
            if set.ringAxis == 3 { cam.w = Walker(p: [0, 0, 1, 0], r: [0, -1, 0, 0], u: [0, 0, 0, 1], f: [1, 0, 0, 0]) }   // +z から出発。体の上＝アナ極の向き
            let (p, p2) = PathWalk.ringPoint(path.T, set); cam.w.p = p; journey.w2.p = p2; orthoFrame(&cam.w); orthoW2()
            say?("回る輪：アナ極とカタ極を通る大円を歩き、1 周ごとに輪を \(Int(set.ringStep))° 回す")
        } else if m == .spiral {
            say?("アナ極から螺旋で出発。極では小回り、赤道では大回り")
        }
    }
    func orthoW2() {
        var w = journey.w2; w.r = simd_normalize(w.r - w.p * simd_dot(w.r, w.p)); w.f = w.f - w.p * simd_dot(w.f, w.p); w.f = simd_normalize(w.f - w.r * simd_dot(w.f, w.r)); journey.w2 = w
    }
    /// 道に沿って ds 進む（ウェブ版の spiralStep・ringStep）
    func pathStep(_ ds: Double) {
        let h = 1e-4
        func pt(_ T: Double) -> (V4, V3) { pathMode == .spiral ? PathWalk.spiralPoint(T, path.lap, set) : PathWalk.ringPoint(T, set) }
        let a = pt((pathMode == .spiral ? path.th : path.T) - h).0, b = pt((pathMode == .spiral ? path.th : path.T) + h).0
        let speed = max(1e-6, simd_length(b - a) / (2 * h))     // |dp/dT|（数値で）
        if pathMode == .spiral {
            path.th += ds / speed
            if path.th > 2 * Double.pi {
                path.th -= 2 * Double.pi; path.lap += 1
                if set.prec != 0 { say?("\(path.lap + 1) 周目：輪の面が \(Int((Double(path.lap) * set.prec).truncatingRemainder(dividingBy: 360)))° 傾いた") }
            }
        } else { path.T += ds / speed }
        let (q, q2) = pt(pathMode == .spiral ? path.th : path.T)
        let d = q - cam.w.p * dot4(q, cam.w.p), d2 = q2 - journey.w2.p * simd_dot(q2, journey.w2.p)
        let s3 = acos(max(-1, min(1, dot4(q, cam.w.p))))
        guard s3 > 1e-9, simd_length(d) > 1e-12, simd_length(d2) > 1e-12 else { return }
        let dn = nrm(d), dn2 = simd_normalize(d2)
        moveAlong(&cam.w, dn, s3); moveAlong2(&journey.w2, dn2, s3)
        cam.w.p = q; journey.w2.p = q2; orthoFrame(&cam.w); orthoW2()   // 丸めがたまらないように、道の上の点に合わせる
        cam.az = atan2(dot4(dn, cam.w.r), dot4(dn, cam.w.f)) / d2r       // 見る向き＝進む向き
        cam.el = asin(max(-1, min(1, dot4(dn, cam.w.u)))) / d2r
        journey.walked(cam.w.p, s3, footOn: set.foot) { [weak self] m in
            if self?.set.haptics == true { Haptic.milestone() }
            self?.say?(m)
        }
        if pathMode == .ring {
            let lap = Int(floor(path.T / (2 * Double.pi)))
            if lap > path.lapSaid { path.lapSaid = lap; say?("\(lap + 1) 周目：輪が \(Int((Double(lap) * set.ringStep).truncatingRemainder(dividingBy: 360)))° 回った") }
        }
    }
}
