// スーパーマップ：超球（中身のある 4 次元の球）の中のどこにいるかを、4 つの小さな窓で同時に見せる（オプション。今の地図には手をつけない）
//   1. 断面マップ：自分の道をふくむ面（中心を通る 2 次元の面）で切った超球。何枚目の殻にいるか、どれだけもぐったか
//   2. S³ の地図：どの向きにいるか（中心からの方向）。真ん中がアナ極、外の球面ぜんぶがカタ極の「正距方位図法」
//   3. 深さのものさし：R（中心からの距離）の 12 秒分の動き。ランの階段・ドリルの V の字が見える
//   4. 4 本の首：今いる点の x y z w（x² + y² + z² + w² ＝ R²）
import SwiftUI
import simd

/// スーパーマップの跡（4D の点。1 秒に 20 回、12 秒分）。見せるだけ
final class HLSuperTrail {
    static let shared = HLSuperTrail()                                  // 2D と 3D の地図で同じ跡を使う
    var pts: [(t: Double, x: SIMD4<Double>)] = []
    func add(_ t: Double, _ x: SIMD4<Double>) {
        if let l = pts.last {
            if t - l.t < 0.045 { return }                                // 1 秒に 20 回まで（時計が戻った時も、足さずに待つ）
            if simd_length(l.x - x) > 0.6 { pts = [] }                  // 場所がとんだ：跡を切る
        }
        pts.append((t, x))
        if let i = pts.firstIndex(where: { $0.t >= t - 12 }), i > 0 { pts.removeFirst(i) }
    }
}

extension HyperLabState {
    /// 今いる点（超球の中の 4D の点。長さが R）。ラン・ドリル・R の世界の歩き
    func superPos() -> SIMD4<Double>? {
        if runOn { let s = hrun.at(runT); return s.p * s.rho }
        guard let w = Self.walkSource?() else { return nil }
        if drillOn {
            let p0 = drillS < 1 ? w.pos : -w.pos
            return p0 * (drillR0 * (1 - drillS))
        }
        return simd_normalize(w.pos) * worldR
    }
    /// 断面マップの面（a が上、b が右）。ラン・ドリルの間は道の面（動かない）、歩く間は今いる向きと前の向き
    func superPlane() -> (a: SIMD4<Double>, b: SIMD4<Double>)? {
        if runOn || drillOn || drillK > 0.01 || drillTour != 0, let t = tunBase { return (t.a, t.b) }
        guard let w = Self.walkSource?() else { return nil }
        let t = Self.tunnelBase(w); return (t.a, t.b)
    }
}

struct HLSuperMap: View {
    let st: HyperLabState
    var scale: CGFloat = 1
    var close: () -> Void
    var compact = false                                                 // 3D の時：ものさしと 4 本の首だけ
    @State private var trail: HLSuperTrail
    init(st: HyperLabState, scale: CGFloat = 1, trail: HLSuperTrail = .shared, compact: Bool = false, close: @escaping () -> Void) {
        self.st = st; self.scale = scale; self.compact = compact; self.close = close; _trail = State(initialValue: trail)
    }
    var body: some View {
        let k = scale, cw = 190 * k, ch = 170 * k, gap = 8 * k
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack(spacing: 8 * k) {
                Text("スーパーマップ").font(.system(size: 12 * k, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.45))
                Text("超球の中のどこにいるか").font(.system(size: 10 * k)).foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 10 * k, weight: .bold)).frame(width: 18 * k, height: 18 * k) }
                    .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.6)).help("スーパーマップを閉じる（パネルの「スーパーマップ」でまた出す）")
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { g, _ in draw(g, tl.date.timeIntervalSinceReferenceDate, cw, ch, gap, k) }
                    .frame(width: cw * 2 + gap, height: compact ? ch : ch * 2 + gap)
            }
        }
        .padding(8 * k)
        .frame(width: cw * 2 + gap + 16 * k)
        .background(Color(red: 0.03, green: 0.05, blue: 0.1).opacity(0.88), in: RoundedRectangle(cornerRadius: 10 * k))
        .overlay(RoundedRectangle(cornerRadius: 10 * k).stroke(Color(red: 0.3, green: 0.36, blue: 0.48), lineWidth: 1))
    }

    // ---- 色 ----
    static let gold = Color(red: 1, green: 0.78, blue: 0.3)
    static func rgb(_ c: SIMD3<Float>) -> Color { Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)) }
    /// 殻の色：外は水色、内ほど紫（内核の演出の時は、焼けた鉄の色）
    static func shellCol(_ r: Double, hot: Bool) -> Color {
        let t = max(0, min(1, (1 - r) / 0.85))
        let a = SIMD3<Double>(0.4, 0.85, 1), b = hot ? SIMD3<Double>(1, 0.42, 0.15) : SIMD3<Double>(0.78, 0.55, 1)
        let c = a + (b - a) * t
        return Color(red: c.x, green: c.y, blue: c.z)
    }
    func label(_ g: GraphicsContext, _ s: String, _ p: CGPoint, _ size: CGFloat, _ c: Color, _ anchor: UnitPoint = .center, bold: Bool = false) {
        g.draw(Text(s).font(.system(size: size, weight: bold ? .semibold : .regular)).foregroundColor(c), at: p, anchor: anchor)
    }

    func draw(_ g: GraphicsContext, _ now: Double, _ cw: CGFloat, _ ch: CGFloat, _ gap: CGFloat, _ k: CGFloat) {
        let row1 = compact ? 0 : ch + gap
        let cells = [CGRect(x: 0, y: 0, width: cw, height: ch), CGRect(x: cw + gap, y: 0, width: cw, height: ch),
                     CGRect(x: 0, y: row1, width: cw, height: ch), CGRect(x: cw + gap, y: row1, width: cw, height: ch)]
        let titles = ["断面マップ（深さ）", "S³ の地図（向き）", "深さのものさし", "4 本の首 x y z w"]
        for (i, r) in cells.enumerated() where !compact || i >= 2 {
            g.fill(Path(roundedRect: r, cornerRadius: 7 * k), with: .color(Color.white.opacity(0.04)))
            label(g, titles[i], CGPoint(x: r.minX + 7 * k, y: r.minY + 9 * k), 10 * k, Color.white.opacity(0.85), .leading, bold: true)
        }
        guard let x = st.superPos(), let pl = st.superPlane() else {
            label(g, "さんぽの窓とつながると出ます", CGPoint(x: cw + gap / 2, y: compact ? ch / 2 : ch + gap / 2), 11 * k, Color.white.opacity(0.7))
            return
        }
        trail.add(now, x)
        if !compact { section(g, cells[0], x, pl, now, k); s3map(g, cells[1], x, now, k) }
        depth(g, cells[2], x, now, k)
        necks(g, cells[3], x, k)
    }

    /// 1. 断面マップ：道をふくむ面で切った超球（殻は同心円）
    func section(_ g: GraphicsContext, _ rc: CGRect, _ x: SIMD4<Double>, _ pl: (a: SIMD4<Double>, b: SIMD4<Double>), _ now: Double, _ k: CGFloat) {
        let c = CGPoint(x: rc.midX, y: rc.midY + 4 * k), S = min(rc.width, rc.height - 30 * k) * 0.47
        func P(_ v: SIMD4<Double>) -> CGPoint { CGPoint(x: c.x + CGFloat(simd_dot(v, pl.b)) * S, y: c.y - CGFloat(simd_dot(v, pl.a)) * S) }
        func off(_ v: SIMD4<Double>) -> Double { simd_length(v - pl.a * simd_dot(v, pl.a) - pl.b * simd_dot(v, pl.b)) }   // 面からのはなれ
        let hot = st.chaosOn
        if hot {                                                          // 内核：中心ほど熱く光る
            let rr = 0.5 * S
            g.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.15).opacity(0.45), Color(red: 1, green: 0.3, blue: 0.1).opacity(0)]), center: c, startRadius: 0, endRadius: rr))
        }
        for r in HyperLabState.stageR {
            let rr = CGFloat(r) * S
            g.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(Self.shellCol(r, hot: hot).opacity(r == 1 ? 0.9 : 0.6)), lineWidth: (r == 1 ? 1.4 : 0.9) * k)
            let q = CGPoint(x: c.x + rr * 0.72, y: c.y + rr * 0.69)
            if r < 1 { label(g, String(format: "%.1f", r), q, 7.5 * k, Self.shellCol(r, hot: hot).opacity(0.85)) }
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - 2 * k, y: c.y - 2 * k, width: 4 * k, height: 4 * k)), with: .color(Color.white.opacity(0.7)))
        // ランの予定の道（この先 6 秒）：うすい点線
        if st.runOn {
            var path = Path(), first = true
            let t1 = min(st.runT + 6, st.hrun.length)
            var t = st.runT
            while t <= t1 { let s = st.hrun.at(t); let p = P(s.p * s.rho); if first { path.move(to: p); first = false } else { path.addLine(to: p) }; t += 0.05 }
            g.stroke(path, with: .color(Self.gold.opacity(0.35)), style: StrokeStyle(lineWidth: 1 * k, lineCap: .round, dash: [2 * k, 3 * k]))
        }
        // 通った跡：古いほどうすい。面からはなれている所（歩いて曲がった所）もうすく
        let pts = trail.pts
        if pts.count > 1 {
            for i in 1..<pts.count {
                let f = max(0, 1 - (now - pts[i].t) / 12), o = max(0.15, 1 - off(pts[i].x) * 4)
                var seg = Path(); seg.move(to: P(pts[i - 1].x)); seg.addLine(to: P(pts[i].x))
                g.stroke(seg, with: .color(Self.gold.opacity(0.9 * f * f * o)), style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round))
            }
        }
        // 今いる所と、進む向きの矢印
        let p = P(x), R = simd_length(x)
        if let old = pts.last(where: { now - $0.t > 0.25 }) {
            let q = P(old.x), d = CGPoint(x: p.x - q.x, y: p.y - q.y), l = hypot(d.x, d.y)
            if l > 0.8 * k {
                let u = CGPoint(x: d.x / l, y: d.y / l), tip = CGPoint(x: p.x + u.x * 15 * k, y: p.y + u.y * 15 * k)
                var a = Path(); a.move(to: p); a.addLine(to: tip)
                a.move(to: tip); a.addLine(to: CGPoint(x: tip.x - u.x * 5 * k - u.y * 3.5 * k, y: tip.y - u.y * 5 * k + u.x * 3.5 * k))
                a.move(to: tip); a.addLine(to: CGPoint(x: tip.x - u.x * 5 * k + u.y * 3.5 * k, y: tip.y - u.y * 5 * k - u.x * 3.5 * k))
                g.stroke(a, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.3 * k, lineCap: .round))
            }
        }
        let dc = Self.shellCol(R, hot: hot)
        g.fill(Path(ellipseIn: CGRect(x: p.x - 7 * k, y: p.y - 7 * k, width: 14 * k, height: 14 * k)), with: .color(dc.opacity(0.35)))
        g.fill(Path(ellipseIn: CGRect(x: p.x - 3 * k, y: p.y - 3 * k, width: 6 * k, height: 6 * k)), with: .color(.white))
        let moving = st.runOn || st.drillOn || st.drillTour != 0
        label(g, moving ? "上＝出発した向き　中心を通る道の面" : "上＝今いる向き　右＝前", CGPoint(x: rc.midX, y: rc.maxY - 7 * k), 7.5 * k, Color.white.opacity(0.55))
    }

    /// 4D の点 → S³ の地図の玉の中の点（真ん中がアナ極 +w、半径 0.5 が w ＝ 0、外の球面がカタ極 −w）。向きは x 右・z 上・y 奥
    static func ballPoint(_ x: SIMD4<Double>) -> SIMD3<Double>? {
        let l = simd_length(x); guard l > 1e-4 else { return nil }
        let p = x / l, th = acos(max(-1, min(1, p.w)))
        let u = SIMD3<Double>(p.x, p.y, p.z), ul = simd_length(u)
        if ul < 1e-6 { return th < 1 ? .zero : SIMD3(0, 0, 1) }
        return u / ul * (th / Double.pi)
    }
    func s3map(_ g: GraphicsContext, _ rc: CGRect, _ x: SIMD4<Double>, _ now: Double, _ k: CGFloat) {
        let c = CGPoint(x: rc.midX, y: rc.midY + 3 * k), S = min(rc.width, rc.height - 34 * k) * 0.5
        let yaw = 0.5, pit = 0.32, cy = cos(yaw), sy = sin(yaw), cp = cos(pit), sp = sin(pit)
        // x 右・z 上・y 奥 を、少し斜め上から
        func P(_ q: SIMD3<Double>) -> (CGPoint, Double) {
            let X = q.x, Y = q.z, Z = -q.y
            let x1 = X * cy + Z * sy, z1 = -X * sy + Z * cy
            let y2 = Y * cp - z1 * sp, d = Y * sp + z1 * cp
            return (CGPoint(x: c.x + CGFloat(x1) * S, y: c.y - CGFloat(y2) * S), d)
        }
        let kata = Self.rgb(MapRenderer.poleDotCol(1)), ana = Self.rgb(MapRenderer.poleDotCol(0))
        g.fill(Path(ellipseIn: CGRect(x: c.x - S, y: c.y - S, width: S * 2, height: S * 2)), with: .color(kata.opacity(0.06)))
        g.stroke(Path(ellipseIn: CGRect(x: c.x - S, y: c.y - S, width: S * 2, height: S * 2)), with: .color(kata.opacity(0.7)), lineWidth: 1.2 * k)
        let h = S * 0.5
        g.stroke(Path(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: h * 2, height: h * 2)), with: .color(Color.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.8 * k, dash: [3 * k, 3 * k]))
        // 6 つの極（w ＝ 0 の球面の上）と、アナ極へ向かう軸
        for i in 2..<8 {
            let m = FIXED[i], q = SIMD3<Double>(m.c.x, m.c.y, m.c.z) * 0.5, (p, d) = P(q), col = Self.rgb(MapRenderer.poleDotCol(i))
            var ln = Path(); ln.move(to: c); ln.addLine(to: p)
            g.stroke(ln, with: .color(col.opacity(d < 0 ? 0.15 : 0.3)), lineWidth: 0.7 * k)
            let rr = (d < 0 ? 2.2 : 3) * k
            g.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(col.opacity(d < 0 ? 0.5 : 1)))
            label(g, MapRenderer.poleName(m), CGPoint(x: p.x, y: p.y - 7 * k), 7.5 * k, col.opacity(d < 0 ? 0.55 : 0.95))
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - 3.5 * k, y: c.y - 3.5 * k, width: 7 * k, height: 7 * k)), with: .color(ana))
        label(g, "アナ極", CGPoint(x: c.x - 5 * k, y: c.y + 9 * k), 7.5 * k, ana, .trailing)   // 南極（奥）が真ん中の右に重なるので、左下に
        // 通った跡（中心を抜けると反対の向きへとぶので、そこで線を切る）
        let pts = trail.pts
        var prev: (CGPoint, SIMD3<Double>)? = nil
        for e in pts {
            guard let q = Self.ballPoint(e.x) else { prev = nil; continue }
            let p = P(q).0
            if let o = prev, simd_length(o.1 - q) < 0.25 {
                let f = max(0, 1 - (now - e.t) / 12)
                var seg = Path(); seg.move(to: o.0); seg.addLine(to: p)
                g.stroke(seg, with: .color(Self.gold.opacity(0.85 * f * f)), style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round))
            }
            prev = (p, q)
        }
        if let q = Self.ballPoint(x) {
            let p = P(q).0
            g.fill(Path(ellipseIn: CGRect(x: p.x - 6 * k, y: p.y - 6 * k, width: 12 * k, height: 12 * k)), with: .color(Self.gold.opacity(0.35)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - 3 * k, y: p.y - 3 * k, width: 6 * k, height: 6 * k)), with: .color(.white))
        }
        label(g, "外の球面ぜんぶ＝カタ極　点線＝w が 0", CGPoint(x: rc.midX, y: rc.maxY - 7 * k), 7.5 * k, Color.white.opacity(0.55))
    }

    /// 3. 深さのものさし：R の 12 秒分（右はしが今）
    func depth(_ g: GraphicsContext, _ rc: CGRect, _ x: SIMD4<Double>, _ now: Double, _ k: CGFloat) {
        let x0 = rc.minX + 34 * k, x1 = rc.maxX - 10 * k, top = rc.minY + 26 * k, bot = rc.maxY - 18 * k
        func Y(_ r: Double) -> CGFloat { bot - CGFloat(max(0, min(1, r))) * (bot - top) }
        func X(_ t: Double) -> CGFloat { x1 - CGFloat((now - t) / 12) * (x1 - x0) }
        let hot = st.chaosOn
        for r in HyperLabState.stageR {
            var ln = Path(); ln.move(to: CGPoint(x: x0, y: Y(r))); ln.addLine(to: CGPoint(x: x1, y: Y(r)))
            let col = Self.shellCol(r, hot: hot)
            g.stroke(ln, with: .color(col.opacity(0.4)), style: StrokeStyle(lineWidth: 0.8 * k, dash: r == 1 ? [] : [3 * k, 3 * k]))
            label(g, r == 1 ? "地表 1" : String(format: "%.1f", r), CGPoint(x: x0 - 4 * k, y: Y(r)), 7.5 * k, col.opacity(0.9), .trailing)
        }
        var base = Path(); base.move(to: CGPoint(x: x0, y: bot)); base.addLine(to: CGPoint(x: x1, y: bot))
        g.stroke(base, with: .color(Color.white.opacity(0.45)), lineWidth: 0.8 * k)
        label(g, "中心 0", CGPoint(x: x0 - 4 * k, y: bot), 7.5 * k, Color.white.opacity(0.7), .trailing)
        let pts = trail.pts
        if pts.count > 1 {
            var path = Path()
            for (i, e) in pts.enumerated() { let p = CGPoint(x: X(e.t), y: Y(simd_length(e.x))); if i == 0 { path.move(to: p) } else { path.addLine(to: p) } }
            g.stroke(path, with: .color(Self.gold.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round))
        }
        let R = simd_length(x), p = CGPoint(x: x1, y: Y(R))
        g.fill(Path(ellipseIn: CGRect(x: p.x - 3.5 * k, y: p.y - 3.5 * k, width: 7 * k, height: 7 * k)), with: .color(.white))
        label(g, String(format: "R %.2f", R), CGPoint(x: rc.maxX - 8 * k, y: rc.minY + 9 * k), 10 * k, Self.shellCol(R, hot: hot), .trailing, bold: true)
        label(g, "← 12 秒前　　　今 →", CGPoint(x: (x0 + x1) / 2, y: rc.maxY - 7 * k), 7.5 * k, Color.white.opacity(0.55))
    }

    /// 4. 4 本の首：今いる点の x y z w（−1 〜 1）
    func necks(_ g: GraphicsContext, _ rc: CGRect, _ x: SIMD4<Double>, _ k: CGFloat) {
        let names = ["x", "y", "z", "w"], top = rc.minY + 30 * k, row = (rc.height - 52 * k) / 4
        let bx0 = rc.minX + 40 * k, bx1 = rc.maxX - 44 * k, mid = (bx0 + bx1) / 2, half = (bx1 - bx0) / 2
        for i in 0..<4 {
            let y = top + row * (CGFloat(i) + 0.5), v = x[i], col = Self.rgb(HyperLabRenderer.axisCol[i])
            label(g, "🐲 " + names[i], CGPoint(x: rc.minX + 8 * k, y: y), 10 * k, col, .leading, bold: true)
            g.fill(Path(roundedRect: CGRect(x: bx0, y: y - 4 * k, width: bx1 - bx0, height: 8 * k), cornerRadius: 3 * k), with: .color(Color.white.opacity(0.07)))
            let w = CGFloat(max(-1, min(1, v))) * half
            g.fill(Path(roundedRect: CGRect(x: min(mid, mid + w), y: y - 4 * k, width: abs(w), height: 8 * k), cornerRadius: 3 * k), with: .color(col.opacity(0.9)))
            var z = Path(); z.move(to: CGPoint(x: mid, y: y - 6 * k)); z.addLine(to: CGPoint(x: mid, y: y + 6 * k))
            g.stroke(z, with: .color(Color.white.opacity(0.5)), lineWidth: 0.8 * k)
            label(g, String(format: "%+.2f", v), CGPoint(x: rc.maxX - 7 * k, y: y), 9 * k, col, .trailing)
        }
        let R = simd_length(x)
        label(g, String(format: "x² + y² + z² + w² ＝ R² ＝ %.2f", R * R), CGPoint(x: rc.midX, y: rc.maxY - 9 * k), 8 * k, Color.white.opacity(0.6))
    }
}

#if os(macOS)
extension HLSuperMap {
    /// 確かめの絵（--superpng <dir>）：決まった場所から超球ランをして、途中のスーパーマップを PNG に
    @MainActor static func png(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let old = HyperLabState.walkSource
        let p0 = simd_normalize(SIMD4<Double>(0.35, 0.25, 0.2, 0.88)), f0 = simd_normalize(SIMD4<Double>(0.6, -0.3, 0.5, 0) - p0 * simd_dot(SIMD4<Double>(0.6, -0.3, 0.5, 0), p0))
        HyperLabState.walkSource = { HyperLabState.Walk(trail: [], pos: p0, fwd: f0) }
        for (name, until, hot, run) in [("ラン4秒", 4.0, false, true), ("ラン8秒", 8.0, false, true), ("ラン12秒", 12.0, true, true), ("ラン16秒", 16.0, false, true), ("歩きR0.6", 0.0, false, false), ("左右に曲がる16秒", 16.0, false, true), ("4Dにも曲がる16秒", 16.0, false, true)] {
            let st = HyperLabState(); st.tunnelView = true; st.chaosOn = hot
            st.runTurn = name.hasPrefix("左右") ? 1 : name.hasPrefix("4D") ? 2 : 0
            let tr = HLSuperTrail(), now = Date().timeIntervalSinceReferenceDate
            if run {
                st.runOn = true
                var t = 0.0
                while t < until { st.tickRun(0.05); t += 0.05; if let x = st.superPos() { tr.add(now - until + t, x) } }
            } else { st.worldR = 0.6 }
            HLSuperTrail.shared.pts = tr.pts
            let v = HLSuperMap(st: st, scale: 1.5) {}.environment(\.colorScheme, .dark).background(Color.black)
            let r = ImageRenderer(content: v); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir + "/スーパーマップ_" + name + ".png")); print("書いた", name, String(format: "R %.2f", simd_length(st.superPos() ?? .zero)))
            } else { print("✗ 描けない", name) }
            // 3D の 2 枚（左の列）と、3D の時の小さな板
            HLSuperTrail.shared.pts = tr.pts
            for (kind, nm) in [(0, "3D断面"), (1, "3DのS3")] {
                let v3 = HLSuper3DPane(st: st, kind: kind).frame(width: 640, height: 430).environment(\.colorScheme, .dark)
                let r3 = ImageRenderer(content: v3); r3.scale = 2
                if let img = r3.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir + "/スーパーマップ_" + nm + "_" + name + ".png"))
                }
            }
            if name == "ラン12秒" {
                let vc = HLSuperMap(st: st, scale: 1.2, compact: true) {}.environment(\.colorScheme, .dark).background(Color.black)
                let rc = ImageRenderer(content: vc); rc.scale = 2
                if let img = rc.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir + "/スーパーマップ_小さな板.png"))
                }
            }
            st.runOn = false
        }
        HyperLabState.walkSource = old
    }
}
#endif
