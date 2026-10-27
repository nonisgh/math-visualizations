// 自分の道（カスタムルート）：選んだ点（8 つの極か、入れた座標）を順に歩く。道はいくつでも作れて、名前をつけて保存（UserDefaults）。
//   1 点：今いる所からそこへまっすぐ（大円で）行って止まる。2 点：①へ行ってから ①⇄② を往復。3 点以上：①へ行ってから ①→②→…→最後→① と巡回。上限 16 点。
//   点と点の間は大円（S³ のまっすぐ）。点でのターンは、ほかの決まった道と同じ（スムーズ＝双曲線／直角）。引き返す時（150° より大きいターン）は、点で止まって向きを回す。
//   つなぎ方「おまかせ」（初め）：点ごとに、短い弧と、まっすぐ回る長い弧（2π − 距離）を比べ、「長さ ＋ 0.3 × 曲がる角²」の小さい方へ。
//     ちょうど反対側（天 → 地など、どの向きでも π）は、来た向きのまままっすぐ。2 点は引き返さずに、2 点を通る大円をぐるっと回る（ループ）。
//   つなぎ方「最短」：いつも短い弧（2 点は往復で引き返す）。反対側へは、軸と軸のまん中の向き（ウェブ版と同じ、ほかの極を踏まない）。
//   スムーズの時、150° より大きい引き返しは、点を過ぎてから電球の形にぐるっと回って、点を通って戻る（止まって向きを回さない）。直角の時は点で止まって回す
//   S² の仲間は、この道では動かない
//   座標の入れ方はウェブ版の「座標へ向かう」と同じ：最後に入れた数ほど優先（そのまま）、前に入れた数は残りの幅に合わせて調整、まだ入れていない軸は残りを等しく分け合う
import SwiftUI
import simd
import QuartzCore

// ---- 道の点と道（保存する形）----
struct RoutePoint: Codable, Equatable, Identifiable {
    var id = UUID()
    var p: [Double]                    // x・y・z・w（長さ 1）
    var name: String
}
struct CustomRoute: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var pts: [RoutePoint]
}

/// 道の一覧と、選んでいる道（UserDefaults に保存）
final class RouteStore: ObservableObject {
    static let shared = RouteStore()
    static let key = "s3walk.routes.v1"
    static let maxPts = 16
    static let nums = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯").map(String.init)
    /// 8 つの極（ボタンの並び：アナ・カタ・東・西・北・南・天・地）
    static let poles: [(String, [Double])] = [("アナ極", [0, 0, 0, 1]), ("カタ極", [0, 0, 0, -1]), ("東極", [1, 0, 0, 0]), ("西極", [-1, 0, 0, 0]),
                                               ("北極", [0, 1, 0, 0]), ("南極", [0, -1, 0, 0]), ("天極", [0, 0, 1, 0]), ("地極", [0, 0, -1, 0])]
    @Published var routes: [CustomRoute] = [] { didSet { save() } }
    @Published var sel: UUID? = nil { didSet { save() } }
    private var loading = false
    init() {
        loading = true
        if let d = UserDefaults.standard.data(forKey: RouteStore.key), let v = try? JSONDecoder().decode(Saved.self, from: d) { routes = v.routes; sel = v.sel }
        if routes.isEmpty {                                           // はじめの道：アナ極・東極・天極の三角（どの角も 90°）
            let p = RouteStore.poles
            routes = [CustomRoute(name: "道 1", pts: [RoutePoint(p: p[0].1, name: p[0].0), RoutePoint(p: p[2].1, name: p[2].0), RoutePoint(p: p[6].1, name: p[6].0)])]
        }
        if sel == nil || !routes.contains(where: { $0.id == sel }) { sel = routes.first?.id }
        loading = false
    }
    private struct Saved: Codable { var routes: [CustomRoute]; var sel: UUID? }
    func save() { guard !loading, let d = try? JSONEncoder().encode(Saved(routes: routes, sel: sel)) else { return }; UserDefaults.standard.set(d, forKey: RouteStore.key) }
    var index: Int? { routes.firstIndex { $0.id == sel } }
    func add() {
        var k = routes.count + 1; while routes.contains(where: { $0.name == "道 \(k)" }) { k += 1 }
        let r = CustomRoute(name: "道 \(k)", pts: []); routes.append(r); sel = r.id
    }
    func remove() {
        guard let i = index else { return }
        routes.remove(at: i)
        if routes.isEmpty { routes = [CustomRoute(name: "道 1", pts: [])] }
        sel = routes[min(i, routes.count - 1)].id
    }
    func append(_ p: [Double], _ name: String) {
        guard let i = index, routes[i].pts.count < RouteStore.maxPts else { return }
        routes[i].pts.append(RoutePoint(p: p, name: name))
    }
}

/// 座標の入力（ウェブ版の gtFix・gtSet・gtParse と同じ考え）。軸の番号は 0 x・1 y・2 z・3 w
struct CoordInput {
    var v: [Double] = [0.5, 0.5, 0.5, 0.5]
    var e: [Double?] = [nil, nil, nil, nil]   // 入れた数（そのまま覚えておく。幅が広がれば戻る）
    var ord: [Int] = []                        // 入れた順（古い → 新しい、3 つまで）
    var sg: [Double] = [1, 1, 1, 1]           // まだ入れていない軸の符号
    var lim: [Double] = [1, 1, 1, 1], rank: [Int] = [0, 0, 0, 0], free: [Int] = [0, 1, 2, 3], rr = 1.0
    /// 新しい順に残りの半径に丸め、まだ入れていない軸は残りを等しく分け合う
    mutating func fix() {
        var rem = 1.0; rank = [0, 0, 0, 0]
        for (k, a) in ord.reversed().enumerated() {
            let r = max(0, rem).squareRoot(); lim[a] = r; rank[a] = k + 1
            v[a] = max(-r, min(r, e[a] ?? v[a])); rem -= v[a] * v[a]
        }
        free = (0..<4).filter { !ord.contains($0) }; rr = max(0, rem).squareRoot()
        for a in free { lim[a] = rr; v[a] = (sg[a] < 0 ? -1 : 1) * rr / Double(free.count).squareRoot() }
    }
    /// 軸 a に val を入れる（いちばん優先に。4 つ目なら、いちばん前に入れた軸が外れて自動の側へ）
    mutating func set(_ a: Int, _ val: Double) {
        ord.removeAll { $0 == a }; ord.append(a); v[a] = val; e[a] = val; sg[a] = val < 0 ? -1 : 1
        if ord.count > 3 { let old = ord.removeFirst(); sg[old] = v[old] < 0 ? -1 : 1; e[old] = nil }
        fix()
    }
    mutating func reset() { self = CoordInput(); fix() }
    /// 今いる所（x → y → z の順に入れて、w は自動）
    mutating func setHere(_ p: V4) { reset(); sg[3] = p.w < 0 ? -1 : 1; set(0, p.x); set(1, p.y); set(2, p.z) }
    /// 1 → 1、5 → 0.5、34 → 0.34、-5 → −0.5（小数点なしは桁の数だけ 10 で割る。小数点があればそのまま）。全角も読む
    static func parse(_ str: String) -> Double? {
        var t = str.trimmingCharacters(in: .whitespaces).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? str
        t = t.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "ー", with: "-").replacingOccurrences(of: "。", with: ".")
        if t.contains(".") { return Double(t) }
        let neg = t.hasPrefix("-"), digits = t.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let n = Double(digits) else { return nil }
        let v = digits == "1" ? 1 : n / pow(10, Double(digits.count))
        return neg ? -v : v
    }
    var point: [Double] { let l = (v.map { $0 * $0 }.reduce(0, +)).squareRoot(); return l > 1e-9 ? v.map { $0 / l } : [0, 0, 0, 1] }
}

// ---- 歩く ----
/// 自分の道の進み具合
struct CRWalk {
    var pts: [V4] = [], names: [String] = [], title = ""
    var once = false                       // 1 点：着いたら止まる
    var to = 0                             // 今の道の行き先（pts の番号）
    var P = V4(0, 0, 0, 1), b = V4(1, 0, 0, 0), len = 0.0, s = 0.0
    var run: CRTurn? = nil, plan: CRTurn? = nil   // plan：次の点でのターン（道の終わりの手前で 1 回だけ作る）
}
/// 点でのターン 1 回
struct CRTurn {
    // 初めの値のあるものとないものを 1 行に混ぜると、Xcode のデバッグのビルドで初期化子が作れないので分ける
    var f = 0.0
    var h: TurnTable, Q: V4, E: [Vn], sharp: Bool, L: Double, nb: V4, nlen: Double, nt: Int, th: Double
    var pv: (t: Double, len: Double, A: V4, B: V4, th: Double, F: Walker)? = nil, pvDone = false
    var long = false                       // 次の道は、まっすぐ回る長い弧（ループ）
    var bulb = false                       // 電球の形の U ターン
}

extension TurnGeo {
    /// 電球の形の U ターン（平らな地図の上）：着く向き [1, 0, 0] で点（原点）まで来て、そのまま進みながら −α 曲がり、反対へ θ ＋ 2α 回り、−α 曲がると、
    ///   ちょうど点に戻って、出る向き u（着く向きから θ）で出ていく。α は点に戻るように数値で探す（θ ＝ 180° なら 60°）。半径 rho、入る・出るまっすぐの長さ L
    static func bulb(_ u: Vn, side: Vn, L: Double, rho: Double) -> TurnTable {
        let th = acos(max(-1, min(1, u[0])))
        var n = [0.0, u[1], u[2]]; var nl = (n[1] * n[1] + n[2] * n[2]).squareRoot()
        if nl < 1e-6 { n = [0, side[1], side[2]]; nl = (n[1] * n[1] + n[2] * n[2]).squareRoot(); if nl < 1e-6 { n = [0, 1, 0]; nl = 1 } }
        n = n.map { $0 / nl }
        func arcs(_ al: Double, _ k: Int) -> [(Double, Double)] {        // 原点から、電球の形の点の並び（x：着く向き・y：n の向き）
            var x = 0.0, y = 0.0, h = 0.0, out: [(Double, Double)] = []
            for ang in [-al, th + 2 * al, -al] {
                let m = max(2, Int(Double(k) * abs(ang) / Double.pi)), d = ang / Double(m)
                for _ in 0..<m { h += d / 2; x += rho * abs(d) * cos(h); y += rho * abs(d) * sin(h); h += d / 2; out.append((x, y)) }
            }
            return out
        }
        var best = (Double.pi / 3, Double.infinity)
        for i in 0...400 {                                               // 40°〜100° で、点にいちばん近く戻る α
            let al = (40 + Double(i) * 0.15) * Double.pi / 180, e = arcs(al, 120).last!
            let r = (e.0 * e.0 + e.1 * e.1).squareRoot(); if r < best.1 { best = (al, r) }
        }
        var pts: [Vn] = []
        for i in 0...20 { let x = -L + L * Double(i) / 20; pts.append([x, 0, 0]) }
        for (x, y) in arcs(best.0, 240) { pts.append([x + n[0] * y, n[1] * y, n[2] * y]) }
        for i in 1...20 { let s = L * Double(i) / 20; pts.append(u.map { $0 * s }) }
        return table(pts)
    }
}

private func vn(_ v: V4) -> Vn { [v.x, v.y, v.z, v.w] }
private func v4(_ a: Vn) -> V4 { V4(a[0], a[1], a[2], a[3]) }
private func clamp1(_ x: Double) -> Double { max(-1, min(1, x)) }

extension Renderer {
    /// 自分の道を歩き始める（今いる所から ① へ）
    func startCustom(_ route: CustomRoute) {
        var pts: [V4] = [], names: [String] = []
        for q in route.pts where q.p.count == 4 {
            let p = nrm(V4(q.p[0], q.p[1], q.p[2], q.p[3]))
            if let last = pts.last, dot4(last, p) > cos(0.002) { continue }   // 続けて同じ点は 1 つに
            pts.append(p); names.append(q.name)
        }
        if pts.count > 1, dot4(pts[0], pts[pts.count - 1]) > cos(0.002) { pts.removeLast(); names.removeLast() }   // 最後が ① と同じなら、巡回で ① に戻る
        guard !pts.isEmpty else { say?("点を 1 つ以上入れてください（極のボタンか、座標を入れて「この点を足す」）"); return }
        pathSpeed = 1; pathMode = .custom
        cr = CRWalk(pts: pts, names: names, title: route.name, once: pts.count == 1)
        let dist = acos(clamp1(dot4(cam.w.p, pts[0])))
        if dist < 0.003 {
            if cr.once { pathMode = .none; say?("もう \(names[0]) にいる"); return }
            setLeg(from: pts[0], to: 1, arrival: cam.lookFrame().L)
        } else { setLeg(from: cam.w.p, to: 0, arrival: cam.lookFrame().L) }
        let n = pts.count
        say?("自分の道「\(route.name)」：" + (n == 1 ? "\(names[0]) へ行って止まる" : n == 2 ? (set.routeSmart ? "\(names[0]) と \(names[1]) を通る大円をぐるっと回る（ループ）" : "\(names[0]) と \(names[1]) を往復") : "\(n) 点を ①→…→\(RouteStore.nums[n - 1])→① と巡回") + "（" + (set.turnSharp ? "直角" : "スムーズ") + "）")
    }
    /// A から B への道（向き b と長さ）。ちょうど反対側（距離 π）へは、どの向きでも着くので、ウェブ版と同じく選ぶ：
    ///   軸と軸のまん中の向き（途中で極を踏まない）のうち、その次の点 T2 と直交するもの（反対側で 90° に曲がれる）で、来た向き a にいちばん近いもの
    private func legDir(_ A: V4, _ B: V4, _ a: V4, next T2: V4?) -> (V4, Double) {
        let c = clamp1(dot4(A, B)), t = B - A * c
        if simd_length(t) > 1e-6 { return (nrm(t), acos(c)) }
        let E = [V4(1, 0, 0, 0), V4(0, 1, 0, 0), V4(0, 0, 1, 0), V4(0, 0, 0, 1)]
        let side: [V4] = T2.map { abs(dot4($0, A)) > 0.5 ? [] : [$0] } ?? []
        let axes = E.filter { e in abs(dot4(e, A)) < 0.5 && side.allSatisfy { abs(dot4(e, $0)) < 0.5 } }
        var cands: [V4] = []
        if axes.count >= 2 { for i in 0..<axes.count { for j in (i + 1)..<axes.count { for si in [1.0, -1.0] { for sj in [1.0, -1.0] { cands.append(axes[i] * si + axes[j] * sj) } } } } }
        else { for e in axes { cands += [e, -e] } }
        cands = cands.map { $0 - A * dot4($0, A) }.filter { simd_length($0) > 1e-6 }.map(nrm)
        let aa = a - A * dot4(a, A)
        guard let best = cands.max(by: { dot4($0, aa) < dot4($1, aa) }) else {
            var d = aa; if simd_length(d) < 1e-6 { d = E[0] - A * A.x; if simd_length(d) < 1e-6 { d = E[1] - A * A.y } }
            return (nrm(d), acos(c))
        }
        return (best, acos(c))
    }
    /// 次の道を選ぶ（つなぎ方「最短」は legDir のまま）。おまかせ：短い弧とまっすぐ回る長い弧を、長さ ＋ 0.3 × 曲がる角² で比べる。
    ///   反対側（どの向きでも π）は来た向きのまま。2 点の道は、曲がる角の小さい方（＝引き返さずにループ）。start：最初の道（今いる所から ①）は短い弧
    private func chooseLeg(_ A: V4, _ B: V4, _ a: V4, next T2: V4?, start: Bool) -> (V4, Double, Bool) {
        guard set.routeSmart else { let (b, l) = legDir(A, B, a, next: T2); return (b, l, false) }
        let c = clamp1(dot4(A, B)), t = B - A * c, aa = a - A * dot4(a, A)
        if simd_length(t) <= 1e-6 {                                  // ちょうど反対側：まっすぐ
            if simd_length(aa) > 1e-6 { return (nrm(aa), acos(c), false) }
            let (b, l) = legDir(A, B, a, next: T2); return (b, l, false)
        }
        let ts = nrm(t), d = acos(c)
        if start || simd_length(aa) < 1e-6 { return (ts, d, false) }
        let an = nrm(aa), thS = acos(clamp1(dot4(an, ts))), thL = Double.pi - thS
        let useLong: Bool
        if cr.pts.count == 2 { useLong = thL < thS - 1e-6 }            // 2 点：引き返さずにループ
        else { useLong = 2 * Double.pi - d + 0.3 * thL * thL < d + 0.3 * thS * thS }
        return useLong ? (-ts, 2 * Double.pi - d, true) : (ts, d, false)
    }
    private func setLeg(from A: V4, to k: Int, arrival a: V4) {
        let (b, len, _) = chooseLeg(A, cr.pts[k], a, next: cr.once ? nil : cr.pts[(k + 1) % cr.pts.count], start: true)
        cr.P = A; cr.b = b; cr.len = len; cr.to = k; cr.s = 0.002; cr.run = nil; cr.plan = nil
    }
    /// qp へ進む（体は進む向きにそろえる＝前を向いたまま曲がる）。S² の仲間は動かさない
    private func crGo(_ qp: V4) {
        let p0 = cam.w.p, s3 = acos(clamp1(dot4(qp, p0))), dr = qp - p0 * dot4(qp, p0)
        guard s3 > 1e-9, simd_length(dr) > 1e-12 else { return }
        let d = nrm(dr)
        moveAlong(&cam.w, d, s3)
        lastDir = d; lastDirT = CACurrentMediaTime()
        cam.w.p = qp
        journey.walked(cam.w.p, s3, footOn: set.foot) { [weak self] m in
            if self?.set.haptics == true { Haptic.milestone() }
            self?.say?(m)
        }
        let dd = nrm(p0 * -sin(s3) + d * cos(s3))
        func g(_ v: V4, _ others: [V4]) -> V4 { var t = v - qp * dot4(v, qp); for o in others { t -= o * dot4(t, o) }; return nrm(t) }
        cam.w.f = dd; cam.w.r = g(cam.w.r, [cam.w.f]); cam.w.u = g(cam.w.u, [cam.w.f, cam.w.r])
        cam.az = 0; cam.el = 0
    }
    /// 今の道の終わり（pts[to]）でのターン
    private func crPlan() -> CRTurn {
        let Q = cr.P * cos(cr.len) + cr.b * sin(cr.len), a = nrm(cr.P * -sin(cr.len) + cr.b * cos(cr.len))
        let nt = (cr.to + 1) % cr.pts.count
        let (nb, nlen, long) = chooseLeg(Q, cr.pts[nt], a, next: cr.pts[(nt + 1) % cr.pts.count], start: false)
        let E = TurnGeo.basis(vn(Q), vn(a)), u = E.map { e in zip(e, vn(nb)).map(*).reduce(0, +) }, f: Vn = [1, 0, 0]
        let th = acos(clamp1(u[0])) / d2r, back = th > 150
        if back && !set.turnSharp {                                    // スムーズの引き返し：電球の形の U ターン
            let L = max(0.002, min(0.3, cr.len * 0.4, nlen * 0.4)), rho = max(0.01, min(0.12, 0.3 * min(cr.len, nlen)))
            let side = E.map { e in zip(e, vn(cam.w.r)).map(*).reduce(0, +) }   // ちょうど引き返す時は、体の右の側へふくらむ
            var tu = CRTurn(h: TurnGeo.bulb(u, side: side, L: L, rho: rho), Q: Q, E: E, sharp: false, L: L, nb: nb, nlen: nlen, nt: nt, th: th)
            tu.long = long; tu.bulb = true; return tu
        }
        let L = max(0.002, min(0.75, cr.len * 0.45, nlen * 0.45, back ? 0.3 : TurnGeo.hypL(f, u)))
        let sharp = set.turnSharp
        var tu = CRTurn(h: TurnGeo.turn(f, u, L, 240, sharp: sharp), Q: Q, E: E, sharp: sharp, L: L, nb: nb, nlen: nlen, nt: nt, th: th)
        tu.long = long; return tu
    }
    /// 自分の道に沿って ds 進む
    func crStep(_ ds: Double) {
        guard !cr.pts.isEmpty else { pathMode = .none; return }
        if var tu = cr.run {
            if var pv = tu.pv {                                        // 直角・引き返し：点で止まって向きを回す
                pv.t = min(1, pv.t + ds / pv.len); let e = pv.t * pv.t * (3 - 2 * pv.t)
                func rot(_ v: V4) -> V4 { let c1 = dot4(v, pv.A), c2 = dot4(v, pv.B), co = cos(pv.th * e) - 1, si = sin(pv.th * e); return v + pv.A * (c1 * co - c2 * si) + pv.B * (c1 * si + c2 * co) }
                cam.w.f = rot(pv.F.f); cam.w.r = rot(pv.F.r); cam.w.u = rot(pv.F.u); orthoFrame(&cam.w); cam.az = 0; cam.el = 0
                if pv.t >= 1 { tu.pv = nil; tu.pvDone = true } else { tu.pv = pv }
                cr.run = tu; return
            }
            let f = min(1, tu.f + ds / max(1e-6, tu.h.len))
            if tu.sharp && !tu.pvDone && f >= 0.5 {
                tu.f = 0.5; crGo(v4(TurnGeo.fromFlat(vn(tu.Q), tu.E, TurnGeo.at(tu.h, 0.5))))
                let nxt = v4(TurnGeo.fromFlat(vn(tu.Q), tu.E, TurnGeo.at(tu.h, 0.52))), p = cam.w.p
                let t = nrm(nxt - p * dot4(nxt, p)), A = cam.w.f, B0 = t - A * dot4(t, A), bl = simd_length(B0)
                let B = bl > 1e-6 ? B0 / bl : cam.w.r                // ちょうど引き返す時は、体の上のまわりに回る
                let th = acos(clamp1(dot4(A, t)))
                tu.pv = (0, 0.12 + 0.3 * th / (Double.pi / 2), A, B, th, cam.w)
                cr.run = tu; return
            }
            tu.f = f; crGo(v4(TurnGeo.fromFlat(vn(tu.Q), tu.E, TurnGeo.at(tu.h, f))))
            if f >= 1 { cr.P = tu.Q; cr.b = tu.nb; cr.len = tu.nlen; cr.to = tu.nt; cr.s = tu.L; cr.run = nil; cr.plan = nil } else { cr.run = tu }
            return
        }
        cr.s += ds
        if cr.once {                                                   // 1 点：着いたら止まる
            if cr.s >= cr.len { crGo(cr.pts[0]); pathMode = .none; say?("\(cr.names[0]) に着いた"); return }
            crGo(cr.P * cos(cr.s) + cr.b * sin(cr.s)); return
        }
        if cr.s >= cr.len - 0.8 {
            if cr.plan == nil { cr.plan = crPlan() }
            let pl = cr.plan!
            if cr.len - cr.s <= pl.L {                                 // ターンに入る
                cr.s = cr.len - pl.L; crGo(cr.P * cos(cr.s) + cr.b * sin(cr.s))
                cr.run = pl
                let n = cr.pts.count, i = cr.to, j = pl.nt
                let how = pl.th < 1 ? "まっすぐ" : pl.bulb ? String(format: "ぐるっと U ターン（%.0f°）", pl.th) : String(format: "%.0f° ターン", pl.th)
                say?(String(format: "%@ %@で %@ → %@ %@へ", RouteStore.nums[i % 16], cr.names[i], how, RouteStore.nums[j % 16], cr.names[j]) + (pl.long ? "（まっすぐ回る長い方・ループ）" : n == 2 ? "（往復）" : ""))
                return
            }
        }
        crGo(cr.P * cos(cr.s) + cr.b * sin(cr.s))
    }
}

// ---- パネル（歩くの「決まった道」の下）----
struct CustomRoutePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store = RouteStore.shared
    @State private var ci: CoordInput = { var c = CoordInput(); c.fix(); return c }()
    @State private var texts = ["", "", "", ""]
    @FocusState private var focus: Int?
    static let axisNames = ["x", "y", "z", "w"]
    static let axisColors: [Color] = AXIS_RGB.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }

    var body: some View {
        let r = model.r
        VStack(alignment: .leading, spacing: 6) {
            Text("自分の道").font(.caption.bold()).foregroundStyle(Space.lilac).padding(.top, 4)
            Picker("つなぎ方", selection: model.b(\.routeSmart)) { Text("おまかせ（なるべくまっすぐ・ループ）").tag(true); Text("最短（往復は引き返す）").tag(false) }.pickerStyle(.segmented)
            HStack(spacing: 6) {
                Picker("道", selection: Binding(get: { store.sel ?? UUID() }, set: { store.sel = $0 })) {
                    ForEach(store.routes) { Text($0.name + "（\($0.pts.count) 点）").tag($0.id) }
                }.pickerStyle(.menu).labelsHidden().fixedSize()
                Button("新しい道") { store.add() }
                Button("この道を消す") { store.remove() }.disabled(store.routes.count <= 1 && (store.routes.first?.pts.isEmpty ?? true))
            }
            if let i = store.index {
                TextField("道の名前", text: Binding(get: { store.routes[i].name }, set: { store.routes[i].name = $0 })).textFieldStyle(.roundedBorder)
                let pts = store.routes[i].pts
                if pts.isEmpty { Text("まだ点がない（下の極のボタンか、座標を入れて「この点を足す」）").font(.caption).foregroundStyle(Space.slate) }
                ForEach(Array(pts.enumerated()), id: \.element.id) { k, q in
                    HStack(spacing: 6) {
                        Text(RouteStore.nums[k]).foregroundStyle(Space.sky)
                        Text(q.name).lineLimit(1)
                        Text(String(format: "(%.2f, %.2f, %.2f, %.2f)", q.p[0], q.p[1], q.p[2], q.p[3])).font(.system(size: 10, design: .monospaced)).foregroundStyle(Space.slate).lineLimit(1)
                        Spacer(minLength: 2)
                        Button { store.routes[i].pts.swapAt(k, k - 1) } label: { Image(systemName: "arrow.up") }.disabled(k == 0).help("1 つ前へ")
                        Button { store.routes[i].pts.remove(at: k) } label: { Image(systemName: "xmark") }.help("この点を外す")
                    }
                    .buttonStyle(.borderless).font(.callout)
                }
                Text("\(pts.count) ／ \(RouteStore.maxPts) 点").font(.caption2).foregroundStyle(Space.slate)
                // 極のボタン（押すと最後に足す）
                let full = pts.count >= RouteStore.maxPts
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<2) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<4) { c in
                                let (n, p) = RouteStore.poles[row * 4 + c]
                                Button(n) { store.append(p, n) }.disabled(full)
                            }
                        }
                    }
                }
                .controlSize(.small).buttonStyle(.bordered)                // iPad でもボタンとわかるように枠をつける
                // 座標を入れる（ウェブ版と同じ：最後に入れた数ほど優先）
                Text("座標を入れる（x² ＋ y² ＋ z² ＋ w² ＝ 1。最後に入れた数がいちばん優先、まだ入れていない軸は残りを分け合う。5 → 0.5、34 → 0.34、-5 → −0.5）")
                    .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
                ForEach(0..<4) { a in coordRow(a) }
                HStack(spacing: 6) {
                    Button("今いる所") { ci.setHere(r.cam.w.p); syncTexts() }
                    Button("やり直す") { ci.reset(); syncTexts() }
                    Button("この点を足す") {
                        let p = ci.point
                        store.append(p, String(format: "(%.2f, %.2f, %.2f, %.2f)", p[0], p[1], p[2], p[3]))
                    }.disabled(full)
                }
                .controlSize(.small).buttonStyle(.bordered)
                HStack(spacing: 6) {
                    Button(r.pathMode == .custom ? "はじめから歩き直す" : "この道を歩く") { r.startCustom(store.routes[i]); model.changed() }.disabled(pts.isEmpty)
                    if r.pathMode == .custom { Button("止める") { r.pathMode = .none; model.changed() } }
                }
            }
            Text("1 点：今いる所からそこへ行って止まる。2 点：おまかせは ①・② を通る大円をぐるっと回る（ループ）、最短は ①⇄② を往復。3 点以上：① へ行ってから ①→②→…→① と巡回（おまかせは、引き返すくらいなら、まっすぐ回る長い方を選ぶことも。天 → 地のような反対側へはまっすぐ）。スムーズでは、引き返す所もぐるっと電球の形に回る。点と点の間は大円（S³ のまっすぐ）、曲がり方は上の「スムーズ・直角」。上限 16 点（超立方体の 16 頂点も入る）。S² の仲間は、この道では動かない")
                .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { ci.fix(); syncTexts() }
    }

    func syncTexts() { for a in 0..<4 where focus != a { texts[a] = String(format: "%.2f", ci.v[a]) } }
    func coordRow(_ a: Int) -> some View {
        HStack(spacing: 6) {
            Text(CustomRoutePanel.axisNames[a]).font(.system(size: 13, weight: .bold, design: .serif)).italic().foregroundStyle(CustomRoutePanel.axisColors[a]).frame(width: 14)
            Slider(value: Binding(get: { ci.v[a] }, set: { ci.set(a, ($0 * 100).rounded() / 100); syncTexts() }), in: -1...1)
            TextField("", text: $texts[a]).textFieldStyle(.roundedBorder).frame(width: 52).focused($focus, equals: a)
                .onSubmit { if let v = CoordInput.parse(texts[a]) { ci.set(a, max(-1, min(1, v))) }; focus = nil; syncTexts() }
            Text(ci.rank[a] > 0 ? RouteStore.nums[ci.rank[a] - 1] + (ci.rank[a] == 1 ? "最新" : "") + String(format: " ±%.2f", ci.lim[a])
                 : ci.free.count == 1 ? String(format: "自動 %@%.2f", ci.v[a] >= 0 ? "+" : "−", ci.rr) : "分け合う")
                .font(.system(size: 10)).foregroundStyle(ci.rank[a] > 0 ? Space.sky : Space.slate).frame(width: 74, alignment: .leading)
        }
    }
}
