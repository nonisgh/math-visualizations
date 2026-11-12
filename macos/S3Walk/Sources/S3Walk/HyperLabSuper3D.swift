// スーパーマップ 3D：超球の窓の左の列に、3D の断面マップと 3D の S³ の地図を縦に 2 つ（オプション）。宇宙の背景で、ガラスの殻・光る跡と彗星
//   断面マップ 3D：超球を中心を通る 3D の空間（a 上・b 前・c 横）で切る。殻は入れ子の球。空間からはなれた所（4 つめの向き）はうすく
//   S³ の地図 3D：正距方位の玉（真ん中アナ極・半径 0.5 が w ＝ 0・外の球面がカタ極）。どちらもドラッグで回せる（離すとゆっくり自転）
import SwiftUI
import simd

/// 2 枚の 3D の地図の回転（2 枚で共有。いっしょに回すこともできる）
final class HLSuperCam {
    static let shared = HLSuperCam()
    var yaw = [0.55, 0.55], pitch = [0.32, 0.32], lastT = 0.0, dragT = -10.0
    var dragLast: CGSize? = nil
    /// 1 コマ進める（2 枚が同じコマに呼んでも 1 回だけ進む）
    func tick(_ now: Double, spin: Bool) {
        let dt = now - lastT; guard dt > 1e-4 else { return }; lastT = now
        guard dt < 0.25 else { return }
        if spin && now - dragT > 1.5 { for i in 0..<2 { yaw[i] += dt * 0.12 } }
    }
}

/// 3D → 画面（y 上・カメラは +z の側から見る。遠近つき）
struct HL3DProj {
    let cy: Double, sy: Double, cx: Double, sx: Double, c: CGPoint, S: Double, D = 3.4
    init(yaw: Double, pitch: Double, rect: CGRect, fill: Double = 0.38) {
        cy = cos(yaw); sy = sin(yaw); cx = cos(pitch); sx = sin(pitch)
        c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.03); S = Double(min(rect.width, rect.height)) * fill
    }
    func rot(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let x = v.x * cy + v.z * sy, z0 = -v.x * sy + v.z * cy
        return SIMD3(x, v.y * cx - z0 * sx, v.y * sx + z0 * cx)
    }
    /// 画面の点・奥行き（＋が手前）
    func p(_ v: SIMD3<Double>) -> (CGPoint, Double) {
        let r = rot(v), f = D / (D - r.z)
        return (CGPoint(x: c.x + CGFloat(r.x * S * f), y: c.y - CGFloat(r.y * S * f)), r.z)
    }
    /// 中心にある半径 r の球のふち（画面での半径）
    func rim(_ r: Double) -> CGFloat { CGFloat(r * S * D / sqrt(max(0.01, D * D - r * r))) }
}

/// 宇宙の背景（星・天の川・星雲）。向きだけの点なので、地図を回すと背景も回る
enum HLSpace {
    struct Star { var d: SIMD3<Double>; var s: Double; var ph: Double; var col: SIMD3<Double> }
    static let stars: [Star] = {
        var seed: UInt64 = 0x5eed_c0de
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        func dir() -> SIMD3<Double> { while true { let v = SIMD3(rnd() * 2 - 1, rnd() * 2 - 1, rnd() * 2 - 1); let l = simd_length(v); if l > 0.05 && l <= 1 { return v / l } } }
        var out: [Star] = []
        let tints: [SIMD3<Double>] = [[1, 1, 1], [0.75, 0.85, 1], [1, 0.9, 0.75], [0.85, 0.8, 1]]
        for _ in 0..<520 { out.append(Star(d: dir(), s: pow(rnd(), 3) * 2.2 + 0.5, ph: rnd() * 6.28, col: tints[Int(rnd() * 4) % 4])) }
        // 天の川：大きな円のまわりに、うすい星を帯にして
        let n = simd_normalize(SIMD3<Double>(0.35, 1, 0.25)), u = simd_normalize(simd_cross(n, [1, 0, 0])), w = simd_cross(n, u)
        for _ in 0..<2200 {
            let t = rnd() * 6.2832, g = (rnd() + rnd() + rnd() - 1.5) * 0.16
            out.append(Star(d: simd_normalize(u * cos(t) + w * sin(t) + n * g), s: 0, ph: rnd() * 6.28, col: [0.8, 0.85, 1]))
        }
        return out
    }()
    static let nebulae: [(SIMD3<Double>, SIMD3<Double>)] = [
        (simd_normalize([0.6, 0.3, -0.75]), [0.55, 0.25, 0.85]), (simd_normalize([-0.7, -0.2, -0.65]), [0.15, 0.55, 0.75]),
        (simd_normalize([0.1, -0.7, -0.7]), [0.85, 0.3, 0.55]), (simd_normalize([-0.3, 0.8, -0.5]), [0.3, 0.4, 0.95])]
    static func col(_ c: SIMD3<Double>, _ a: Double = 1) -> Color { Color(red: c.x, green: c.y, blue: c.z).opacity(a) }
    static func draw(_ g: GraphicsContext, _ pr: HL3DProj, _ rc: CGRect, _ now: Double) {
        g.fill(Path(rc), with: .linearGradient(Gradient(colors: [Color(red: 0.012, green: 0.016, blue: 0.045), Color(red: 0.03, green: 0.018, blue: 0.065)]), startPoint: CGPoint(x: rc.minX, y: rc.minY), endPoint: CGPoint(x: rc.maxX, y: rc.maxY)))
        let F = Double(min(rc.width, rc.height)) * 0.75
        func sp(_ d: SIMD3<Double>) -> CGPoint? {
            let r = pr.rot(d); guard r.z < -0.12 else { return nil }
            let q = CGPoint(x: rc.midX + CGFloat(r.x / -r.z * F), y: rc.midY - CGFloat(r.y / -r.z * F))
            return rc.insetBy(dx: -40, dy: -40).contains(q) ? q : nil
        }
        var lg = g; lg.blendMode = .plusLighter
        for (d, c) in nebulae {
            guard let q = sp(d) else { continue }
            let R = CGFloat(F) * 0.55
            lg.fill(Path(ellipseIn: CGRect(x: q.x - R, y: q.y - R, width: R * 2, height: R * 2)), with: .radialGradient(Gradient(colors: [col(c, 0.16), col(c, 0.05), col(c, 0)]), center: q, startRadius: 0, endRadius: R))
        }
        var milky = Path()
        var bright: [(CGPoint, Star)] = []
        for s in stars {
            guard let q = sp(s.d) else { continue }
            if s.s == 0 { milky.addRect(CGRect(x: q.x, y: q.y, width: 1, height: 1)) } else { bright.append((q, s)) }
        }
        lg.drawLayer { l in l.addFilter(.blur(radius: 7)); l.fill(milky, with: .color(Color(red: 0.6, green: 0.65, blue: 1).opacity(0.55))) }
        lg.fill(milky, with: .color(Color.white.opacity(0.28)))
        for (q, s) in bright {
            let tw = 0.7 + 0.3 * sin(now * 1.7 + s.ph), r = CGFloat(s.s) * 0.6
            lg.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(col(s.col, min(1, 0.35 + 0.3 * s.s) * tw)))
            if s.s > 2 {                                                    // 明るい星はにじむ
                let R = r * 4
                lg.fill(Path(ellipseIn: CGRect(x: q.x - R, y: q.y - R, width: R * 2, height: R * 2)), with: .radialGradient(Gradient(colors: [col(s.col, 0.25 * tw), col(s.col, 0)]), center: q, startRadius: 0, endRadius: R))
            }
        }
    }
}

struct HLSuper3DPane: View {
    let st: HyperLabState
    let kind: Int                                                       // 0 断面マップ・1 S³ の地図
    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
                Canvas(rendersAsynchronously: true) { g, size in
                    let now = tl.date.timeIntervalSinceReferenceDate
                    HLSuperCam.shared.tick(now, spin: st.superSpin)
                    draw(g, CGRect(origin: .zero, size: size), now)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                let cam = HLSuperCam.shared, last = cam.dragLast ?? .zero
                let dx = Double(v.translation.width - last.width), dy = Double(v.translation.height - last.height)
                cam.dragLast = v.translation; cam.dragT = Date().timeIntervalSinceReferenceDate
                for i in st.superLink ? [0, 1] : [kind] { cam.yaw[i] += dx * 0.009; cam.pitch[i] = max(-1.45, min(1.45, cam.pitch[i] + dy * 0.009)) }
            }.onEnded { _ in HLSuperCam.shared.dragLast = nil; HLSuperCam.shared.dragT = Date().timeIntervalSinceReferenceDate })
            Text(kind == 0 ? "【3D 断面マップ】中心を通る 3D の空間で切った超球（殻は入れ子の球）　ドラッグで回す" : "【3D の S³ の地図】どの向きにいるか：真ん中がアナ極・外の球面ぜんぶがカタ極　ドラッグで回す")
                .font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).padding(.trailing, 120).allowsHitTesting(false)
            HStack(spacing: 3) {
                chip("自転", st.superSpin) { st.superSpin.toggle() }.help("離している間、ゆっくり回す")
                chip("一緒に", st.superLink) { st.superLink.toggle() }.help("2 枚の地図を一緒に回す")
            }.frame(maxWidth: .infinity, alignment: .topTrailing).padding(8)
        }
        .background(Color(red: 0.012, green: 0.016, blue: 0.045))
        .clipped()
    }
    func chip(_ s: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? Color(red: 0.55, green: 1, blue: 0.75) : Color.white.opacity(0.7))
                .frame(width: 48, height: 20).background(on ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(on ? 0.55 : 0.12), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // ---- 描く ----
    static let gold = SIMD3<Double>(1, 0.78, 0.3)
    func draw(_ g: GraphicsContext, _ rc: CGRect, _ now: Double) {
        let cam = HLSuperCam.shared, pr = HL3DProj(yaw: cam.yaw[kind], pitch: cam.pitch[kind], rect: rc, fill: kind == 0 ? 0.4 : 0.37)
        HLSpace.draw(g, pr, rc, now)
        let k = CGFloat(min(rc.width, rc.height) / 420)
        guard let x = st.superPos(), let pl = st.superPlane() else {
            g.draw(Text("さんぽの窓とつながると出ます").font(.system(size: 13)).foregroundColor(.white.opacity(0.7)), at: CGPoint(x: rc.midX, y: rc.midY))
            return
        }
        HLSuperTrail.shared.add(now, x)
        if kind == 0 { section(g, pr, rc, x, pl, now, k) } else { s3(g, pr, rc, x, now, k) }
    }
    /// 線の分け方：手前・奥で明るさを変える（奥は暗く）
    func wire(_ g: GraphicsContext, _ pr: HL3DProj, _ curves: [(Double) -> SIMD3<Double>], _ col: SIMD3<Double>, front: Double, back: Double, width: CGFloat) {
        var fp = Path(), bp = Path()
        for f in curves {
            var prev: (CGPoint, Double)? = nil
            for i in 0...56 {
                let q = pr.p(f(Double(i) / 56 * 2 * .pi))
                if let o = prev { if (o.1 + q.1) > 0 { fp.move(to: o.0); fp.addLine(to: q.0) } else { bp.move(to: o.0); bp.addLine(to: q.0) } }
                prev = q
            }
        }
        g.stroke(bp, with: .color(HLSpace.col(col, back)), lineWidth: width * 0.8)
        var lg = g; lg.blendMode = .plusLighter
        lg.stroke(fp, with: .color(HLSpace.col(col, front)), lineWidth: width)
    }
    func sphereCurves(_ r: Double) -> [(Double) -> SIMD3<Double>] {
        var out: [(Double) -> SIMD3<Double>] = []
        for k in -2...2 { let ph = Double(k) * .pi / 6; out.append { t in SIMD3(r * cos(ph) * cos(t), r * sin(ph), r * cos(ph) * sin(t)) } }
        for k in 0..<4 { let lo = Double(k) * .pi / 4; out.append { t in SIMD3(r * cos(t) * cos(lo), r * sin(t), r * cos(t) * sin(lo)) } }
        return out
    }
    /// ガラスの球：ふちほど明るい（フレネルのように）
    func glass(_ g: GraphicsContext, _ pr: HL3DProj, _ r: Double, _ col: SIMD3<Double>, _ a: Double) {
        let R = pr.rim(r), c = pr.p(.zero).0, rect = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)
        var lg = g; lg.blendMode = .plusLighter
        lg.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: [.init(color: HLSpace.col(col, 0), location: 0), .init(color: HLSpace.col(col, a * 0.12), location: 0.7), .init(color: HLSpace.col(col, a * 0.55), location: 0.97), .init(color: HLSpace.col(col, 0), location: 1)]), center: c, startRadius: 0, endRadius: R))
        lg.drawLayer { l in l.addFilter(.blur(radius: 3)); l.stroke(Path(ellipseIn: rect), with: .color(HLSpace.col(col, a * 0.7)), lineWidth: 2) }
        // 左上のつや
        let hl = CGPoint(x: c.x - R * 0.42, y: c.y - R * 0.48), hr = R * 0.35
        lg.fill(Path(ellipseIn: CGRect(x: hl.x - hr, y: hl.y - hr, width: hr * 2, height: hr * 2)), with: .radialGradient(Gradient(colors: [Color.white.opacity(a * 0.1), .clear]), center: hl, startRadius: 0, endRadius: hr))
    }
    /// 光る線（ぼかした太い線＋芯）。点は古い順、a は 0〜1 の明るさ（点ごと）
    func glowLine(_ g: GraphicsContext, _ pts: [(CGPoint, Double)?], _ col: SIMD3<Double>, _ k: CGFloat) {
        var buckets = [Path](repeating: Path(), count: 8), all = Path()
        var prev: (CGPoint, Double)? = nil, started = false
        for e in pts {
            guard let q = e else { prev = nil; started = false; continue }
            if let o = prev {
                let a = (o.1 + q.1) / 2, b = max(0, min(7, Int(a * 8)))
                buckets[b].move(to: o.0); buckets[b].addLine(to: q.0)
                if a > 0.3 { if !started { all.move(to: o.0); started = true }; all.addLine(to: q.0) } else { started = false }
            }
            prev = q
        }
        var lg = g; lg.blendMode = .plusLighter
        lg.drawLayer { l in l.addFilter(.blur(radius: 6 * k)); l.stroke(all, with: .color(HLSpace.col(col, 0.55)), style: StrokeStyle(lineWidth: 7 * k, lineCap: .round, lineJoin: .round)) }
        for (i, p) in buckets.enumerated() {
            let a = (Double(i) + 0.5) / 8
            lg.stroke(p, with: .color(HLSpace.col(col, 0.95 * a * a)), style: StrokeStyle(lineWidth: (1.2 + 1.6 * a) * k, lineCap: .round, lineJoin: .round))
        }
    }
    /// 彗星の頭：光の玉と十字の光
    func comet(_ g: GraphicsContext, _ p: CGPoint, _ col: SIMD3<Double>, _ k: CGFloat, _ now: Double) {
        var lg = g; lg.blendMode = .plusLighter
        let pulse = 1 + 0.12 * sin(now * 5), R = 22 * k * CGFloat(pulse)
        lg.fill(Path(ellipseIn: CGRect(x: p.x - R, y: p.y - R, width: R * 2, height: R * 2)), with: .radialGradient(Gradient(colors: [HLSpace.col(col, 0.9), HLSpace.col(col, 0.25), HLSpace.col(col, 0)]), center: p, startRadius: 0, endRadius: R))
        for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] {
            let L = 30 * k
            var f = Path(); f.move(to: CGPoint(x: p.x - CGFloat(dx) * L, y: p.y - CGFloat(dy) * L)); f.addLine(to: CGPoint(x: p.x + CGFloat(dx) * L, y: p.y + CGFloat(dy) * L))
            lg.stroke(f, with: .linearGradient(Gradient(colors: [HLSpace.col(col, 0), HLSpace.col(col, 0.8), HLSpace.col(col, 0)]), startPoint: CGPoint(x: p.x - CGFloat(dx) * L, y: p.y - CGFloat(dy) * L), endPoint: CGPoint(x: p.x + CGFloat(dx) * L, y: p.y + CGFloat(dy) * L)), lineWidth: 1.2 * k)
        }
        g.fill(Path(ellipseIn: CGRect(x: p.x - 3.5 * k, y: p.y - 3.5 * k, width: 7 * k, height: 7 * k)), with: .color(.white))
    }
    func text(_ g: GraphicsContext, _ s: String, _ p: CGPoint, _ size: CGFloat, _ c: Color, _ anchor: UnitPoint = .center) {
        g.draw(Text(s).font(.system(size: size, weight: .semibold)).foregroundColor(c), at: p, anchor: anchor)
    }
    func d3(_ c: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
    static func shellRGB(_ r: Double, hot: Bool) -> SIMD3<Double> {
        let t = max(0, min(1, (1 - r) / 0.85)), a = SIMD3<Double>(0.4, 0.85, 1), b = hot ? SIMD3<Double>(1, 0.42, 0.15) : SIMD3<Double>(0.78, 0.55, 1)
        return a + (b - a) * t
    }

    /// 断面マップ 3D
    func section(_ g: GraphicsContext, _ pr: HL3DProj, _ rc: CGRect, _ x: SIMD4<Double>, _ pl: (a: SIMD4<Double>, b: SIMD4<Double>), _ now: Double, _ k: CGFloat) {
        // 3 つめの向き c：a・b に直角（体の右、なければ軸から）
        var cv = SIMD4<Double>.zero
        let wr = HyperLabState.walkSource?().vR ?? SIMD4(1, 0, 0, 0)
        for cand: SIMD4<Double> in [st.tunBase?.c ?? wr, wr, SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)] {
            var v = cand - pl.a * simd_dot(cand, pl.a); v -= pl.b * simd_dot(v, pl.b)
            if simd_length(v) > 0.2 { cv = simd_normalize(v); break }
        }
        func m(_ v: SIMD4<Double>) -> SIMD3<Double> { SIMD3(simd_dot(v, pl.b), simd_dot(v, pl.a), simd_dot(v, cv)) }
        func off(_ v: SIMD4<Double>) -> Double { simd_length(v - pl.b * simd_dot(v, pl.b) - pl.a * simd_dot(v, pl.a) - cv * simd_dot(v, cv)) }
        let hot = st.chaosOn, stage = HyperLabState.stageR
        // 奥の網目 → ガラス → 中心の光 → 跡 → 手前の網目 → 彗星
        for r in stage { wire(g, pr, sphereCurves(r), Self.shellRGB(r, hot: hot), front: 0, back: r == 1 ? 0.16 : 0.1, width: k) }
        for r in stage.reversed() { glass(g, pr, r, Self.shellRGB(r, hot: hot), r == 1 ? 0.75 : 0.45) }
        let c0 = pr.p(.zero).0
        var lg = g; lg.blendMode = .plusLighter
        let pulse = hot ? 0.8 + 0.2 * sin(now * 3.2) : 1, coreR = pr.rim(hot ? 0.38 : 0.2)
        let coreC: SIMD3<Double> = hot ? [1, 0.45, 0.12] : [0.7, 0.8, 1]
        lg.fill(Path(ellipseIn: CGRect(x: c0.x - coreR, y: c0.y - coreR, width: coreR * 2, height: coreR * 2)), with: .radialGradient(Gradient(colors: [HLSpace.col(coreC, (hot ? 0.75 : 0.35) * pulse), HLSpace.col(coreC, 0)]), center: c0, startRadius: 0, endRadius: coreR))
        // 断面の向き：上・前・横（うすい軸）
        let moving = st.runOn || st.drillOn || st.drillTour != 0
        for (v, name) in [(SIMD3<Double>(0, 1.12, 0), moving ? "出発の向き" : "今いる向き"), (SIMD3<Double>(1.12, 0, 0), "前"), (SIMD3<Double>(0, 0, 1.12), "横")] {
            let (q, z) = pr.p(v)
            var ln = Path(); ln.move(to: c0); ln.addLine(to: q)
            g.stroke(ln, with: .color(Color.white.opacity(z > 0 ? 0.28 : 0.14)), style: StrokeStyle(lineWidth: 0.8 * k, dash: [3 * k, 4 * k]))
            text(g, name, q, 10 * k, Color.white.opacity(z > 0 ? 0.7 : 0.4))
        }
        // ランの予定の道（この先 6 秒）
        if st.runOn {
            var path = Path(), first = true, t = st.runT
            let t1 = min(st.runT + 6, st.hrun.length)
            while t <= t1 { let s = st.hrun.at(t); let q = pr.p(m(s.p * s.rho)).0; if first { path.move(to: q); first = false } else { path.addLine(to: q) }; t += 0.04 }
            g.stroke(path, with: .color(HLSpace.col(Self.gold, 0.4)), style: StrokeStyle(lineWidth: 1.1 * k, lineCap: .round, dash: [2 * k, 4 * k]))
        }
        let pts = HLSuperTrail.shared.pts
        glowLine(g, pts.map { e -> (CGPoint, Double)? in (pr.p(m(e.x)).0, max(0, 1 - (now - e.t) / 12) * max(0.15, 1 - off(e.x) * 4)) }, Self.gold, k)
        for r in stage { wire(g, pr, sphereCurves(r), Self.shellRGB(r, hot: hot), front: r == 1 ? 0.42 : 0.26, back: 0, width: k) }
        // 殻の R（画面の右下へ、ふちに）
        for r in stage where r < 1 { let R = pr.rim(r); text(g, String(format: "R%.1f", r), CGPoint(x: c0.x + R * 0.72, y: c0.y + R * 0.69), 9.5 * k, HLSpace.col(Self.shellRGB(r, hot: hot), 0.9)) }
        let p = pr.p(m(x)).0
        comet(g, p, Self.shellRGB(simd_length(x), hot: hot) * 0.4 + Self.gold * 0.6, k, now)
        text(g, String(format: "R %.2f", simd_length(x)), CGPoint(x: p.x + 14 * k, y: p.y - 14 * k), 12 * k, .white, .leading)
    }

    /// S³ の地図 3D：x 右・z 上・y 奥
    func s3(_ g: GraphicsContext, _ pr: HL3DProj, _ rc: CGRect, _ x: SIMD4<Double>, _ now: Double, _ k: CGFloat) {
        func m(_ q: SIMD3<Double>) -> SIMD3<Double> { SIMD3(q.x, q.z, -q.y) }
        let kata = d3(MapRenderer.poleDotCol(1)), ana = d3(MapRenderer.poleDotCol(0))
        let eq = SIMD3<Double>(0.75, 0.85, 1)
        wire(g, pr, sphereCurves(1), kata, front: 0, back: 0.14, width: k)
        wire(g, pr, sphereCurves(0.5), eq, front: 0, back: 0.08, width: k)
        glass(g, pr, 1, kata, 0.8)
        glass(g, pr, 0.5, eq, 0.35)
        let c0 = pr.p(.zero).0
        // 6 つの極（w ＝ 0 の球面の上）と、アナ極からの軸
        var poles: [(CGPoint, Double, String, SIMD3<Double>)] = []
        for i in 2..<8 {
            let mk = FIXED[i], (q, z) = pr.p(m(SIMD3(mk.c.x, mk.c.y, mk.c.z) * 0.5)), col = d3(MapRenderer.poleDotCol(i))
            var ln = Path(); ln.move(to: c0); ln.addLine(to: q)
            g.stroke(ln, with: .color(HLSpace.col(col, z > 0 ? 0.45 : 0.2)), lineWidth: 1 * k)
            poles.append((q, z, MapRenderer.poleName(mk), col))
        }
        // 通った跡（中心を抜けると反対の向きへとぶので、そこで線を切る）
        var tr: [(CGPoint, Double)?] = [], last: SIMD3<Double>? = nil
        for e in HLSuperTrail.shared.pts {
            guard let q = HLSuperMap.ballPoint(e.x) else { tr.append(nil); last = nil; continue }
            if let o = last, simd_length(o - q) > 0.25 { tr.append(nil) }
            tr.append((pr.p(m(q)).0, max(0, 1 - (now - e.t) / 12))); last = q
        }
        glowLine(g, tr, Self.gold, k)
        wire(g, pr, sphereCurves(0.5), eq, front: 0.2, back: 0, width: k)
        wire(g, pr, sphereCurves(1), kata, front: 0.3, back: 0, width: k)
        var lg = g; lg.blendMode = .plusLighter
        for (q, z, name, col) in poles.sorted(by: { $0.1 < $1.1 }) {
            let R = (z > 0 ? 12 : 8) * k
            lg.fill(Path(ellipseIn: CGRect(x: q.x - R, y: q.y - R, width: R * 2, height: R * 2)), with: .radialGradient(Gradient(colors: [HLSpace.col(col, z > 0 ? 0.9 : 0.5), HLSpace.col(col, 0)]), center: q, startRadius: 0, endRadius: R))
            let r = (z > 0 ? 3.2 : 2.4) * k
            g.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(z > 0 ? 0.95 : 0.55)))
            text(g, name, CGPoint(x: q.x, y: q.y - 13 * k), 10.5 * k, HLSpace.col(col, z > 0 ? 1 : 0.5))
        }
        // アナ極（真ん中）：赤く光る
        let pulse = 1 + 0.1 * sin(now * 2.4), AR = 20 * k * CGFloat(pulse)
        lg.fill(Path(ellipseIn: CGRect(x: c0.x - AR, y: c0.y - AR, width: AR * 2, height: AR * 2)), with: .radialGradient(Gradient(colors: [HLSpace.col(ana, 0.95), HLSpace.col(ana, 0.25), HLSpace.col(ana, 0)]), center: c0, startRadius: 0, endRadius: AR))
        g.fill(Path(ellipseIn: CGRect(x: c0.x - 3.5 * k, y: c0.y - 3.5 * k, width: 7 * k, height: 7 * k)), with: .color(.white))
        text(g, "アナ極", CGPoint(x: c0.x - 10 * k, y: c0.y + 14 * k), 11 * k, HLSpace.col(ana), .trailing)
        let R1 = pr.rim(1)
        text(g, "カタ極（外の球面ぜんぶ）", CGPoint(x: c0.x, y: c0.y - R1 - 10 * k), 11 * k, HLSpace.col(kata))
        text(g, "w ＝ 0", CGPoint(x: c0.x + pr.rim(0.5) * 0.74, y: c0.y + pr.rim(0.5) * 0.74), 9.5 * k, HLSpace.col(eq, 0.7))
        if let q = HLSuperMap.ballPoint(x) { comet(g, pr.p(m(q)).0, Self.gold, k, now) }
    }
}
