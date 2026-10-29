// 自分の道（カスタムルート）：選んだ点（8 つの極か、入れた座標）を順に歩く。道はいくつでも作れて、名前をつけて保存（UserDefaults）。
//   1 点：今いる所からそこへまっすぐ（大円で）行って止まる。2 点：①へ行ってから ①⇄② を往復。3 点以上：①へ行ってから ①→②→…→最後→① と巡回。上限 16 点。
//   点と点の間は大円（S³ のまっすぐ）。点でのターンは、ほかの決まった道と同じ（スムーズ＝双曲線／直角）。引き返す時（150° より大きいターン）は、点で止まって向きを回す。
//   つなぎ方「おまかせ」（初め）：点ごとに、短い弧と、まっすぐ回る長い弧（2π − 距離）を比べ、「長さ ＋ 0.3 × 曲がる角²」の小さい方へ。
//     ちょうど反対側（天 → 地など、どの向きでも π）は、来た向きのまままっすぐ。2 点は引き返さずに、2 点を通る大円をぐるっと回る（ループ）。
//   つなぎ方「最短」：いつも短い弧（2 点は往復で引き返す）。反対側へは、軸と軸のまん中の向き（ウェブ版と同じ、ほかの極を踏まない）。
//   スムーズの時、150° より大きい引き返しは、点を過ぎてから電球の形にぐるっと回って、点を通って戻る（止まって向きを回さない）。直角の時は点で止まって回す
//   つなぎ方「素通り」：全部の点をちょうど通る滑らかな曲線（球面の上のエルミート曲線。各点の向きは、来る向きと出る向きの平均）を、止まらずにぐるぐる回る。
//     曲がりは道の全体にならして、きつい角も手前から少しずつ曲がって点を通る。2 点は 2 点を通る大円（ループ）。今いる所からの入りも、今の向きから滑らかに
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
    /// 同期：道の一覧と選んでいる道を書き出す・当てる
    func export() -> Any {
        guard let d = try? JSONEncoder().encode(Saved(routes: routes, sel: sel)), let o = try? JSONSerialization.jsonObject(with: d) else { return [String: Any]() }
        return o
    }
    func load(_ o: Any) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let v = try? JSONDecoder().decode(Saved.self, from: d), !v.routes.isEmpty else { return }
        if v.routes != routes { routes = v.routes }
        if v.sel != sel { sel = v.sel ?? routes.first?.id }
    }
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
    /// 目印から足した点（名前が「目印」で始まり、場所が同じ）を、全部の道から外す。返り値は外した数
    func removeMarkPoints(_ marks: [V4]) -> Int {
        guard !marks.isEmpty else { return 0 }
        var n = 0, rs = routes
        for i in rs.indices {
            let before = rs[i].pts.count
            rs[i].pts.removeAll { q in q.name.hasPrefix("目印") && q.p.count == 4 && marks.contains { m in abs(m.x - q.p[0]) + abs(m.y - q.p[1]) + abs(m.z - q.p[2]) + abs(m.w - q.p[3]) < 1e-9 } }
            n += before - rs[i].pts.count
        }
        if n > 0 { routes = rs }
        return n
    }
    /// S³ の上に一様にばらまいた点（4 つの正規分布の数を長さ 1 に）
    static func randomPoint() -> [Double] {
        func gauss() -> Double { let u = max(1e-12, Double.random(in: 0..<1)), v = Double.random(in: 0..<1); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
        var q = [gauss(), gauss(), gauss(), gauss()]
        let l = (q.map { $0 * $0 }.reduce(0, +)).squareRoot()
        if l < 1e-9 { return [0, 0, 0, 1] }
        q = q.map { $0 / l }; return q
    }
    /// ランダムな点 n 個（1〜16）の新しい道を作って選ぶ
    @discardableResult func addRandom(_ n: Int) -> CustomRoute {
        let n = max(1, min(RouteStore.maxPts, n))
        var k = 1; while routes.contains(where: { $0.name == "ランダム \(k)" }) { k += 1 }
        let r = CustomRoute(name: "ランダム \(k)", pts: (0..<n).map { j in RoutePoint(p: RouteStore.randomPoint(), name: "ランダム \(RouteStore.nums[j])") })
        routes.append(r); sel = r.id
        return r
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
    ///   simple ＝ false（簡易入力オフ）：書いたとおりの数（1 より大きい数は 1 に丸める）
    static func parse(_ str: String, simple: Bool = true) -> Double? {
        var t = str.trimmingCharacters(in: .whitespaces).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? str
        t = t.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "ー", with: "-").replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "＋", with: "+")
        if t.contains(".") || !simple { return Double(t) }
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
    var routeID: UUID? = nil               // 歩いている道（パネルで、今向かっている点を光らせる）
    var src: [Int] = []                    // pts の点が、道の何番目の点か（続けて同じ点を 1 つにまとめた分ずれる）
    /// 今向かっている点（pts の番号）。ターンの途中は、もう次の点へ向かっている
    var heading: Int { run?.nt ?? to }
    var once = false                       // 1 点：着いたら止まる
    var to = 0                             // 今の道の行き先（pts の番号）
    var P = V4(0, 0, 0, 1), b = V4(1, 0, 0, 0), len = 0.0, s = 0.0
    var flowIn: TurnTable? = nil           // 素通り：今いる所から ① への入り
    var flow: TurnTable? = nil             // 素通り：全部の点を通って ① に戻る曲線（ぐるぐる回る）
    var flowMarks: [Double] = []           // 素通り：曲線の上で、② ③ … ① を通る所（道のり）
    var flowS = 0.0, flowPassed = -1
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
        var pts: [V4] = [], names: [String] = [], src: [Int] = []
        for (k, q) in route.pts.enumerated() where q.p.count == 4 {
            let p = nrm(V4(q.p[0], q.p[1], q.p[2], q.p[3]))
            if let last = pts.last, dot4(last, p) > cos(0.002) { continue }   // 続けて同じ点は 1 つに
            pts.append(p); names.append(q.name); src.append(k)
        }
        if pts.count > 1, dot4(pts[0], pts[pts.count - 1]) > cos(0.002) { pts.removeLast(); names.removeLast(); src.removeLast() }   // 最後が ① と同じなら、巡回で ① に戻る
        guard !pts.isEmpty else { say?("点を 1 つ以上入れてください（極のボタンか、座標を入れて「この点を足す」）"); return }
        pathSpeed = max(0.1, set.routeStart); pathMode = .custom   // 出発の速さ（パネルの「出発の速さ」）
        cr = CRWalk(pts: pts, names: names, title: route.name, once: pts.count == 1)
        cr.routeID = route.id; cr.src = src
        // 道の点をチェックポイントに（極・目印と同じ所は、そちらで数えるので除く）。周回は道の点で数える（2 つ以上の時）
        var cp: [V4] = [], cn: [String] = []
        for (k, p) in pts.enumerated() where !FIXED.contains(where: { dot4($0.c, p) > cos(0.002) }) && !journey.marks.contains(where: { dot4($0, p) > cos(0.002) }) { cp.append(p); cn.append(names[k]) }
        journey.routePts = cp; journey.routeNames = cn; journey.routeHit = []; journey.enteredRoute = []
        if set.routeFlow && pts.count >= 2 { startFlow(); return }
        let dist = acos(clamp1(dot4(cam.w.p, pts[0])))
        if dist < 0.003 {
            if cr.once { pathMode = .none; say?("もう \(names[0]) にいる"); return }
            setLeg(from: pts[0], to: 1, arrival: cam.lookFrame().L)
        } else { setLeg(from: cam.w.p, to: 0, arrival: cam.lookFrame().L) }
        let n = pts.count
        say?("自分の道「\(route.name)」：" + (n == 1 ? "\(names[0]) へ行って止まる" : n == 2 ? (set.routeSmart ? "\(names[0]) と \(names[1]) を通る大円をぐるっと回る（ループ）" : "\(names[0]) と \(names[1]) を往復") : "\(n) 点を ①→…→\(RouteStore.nums[n - 1])→① と巡回") + "（" + (set.turnSharp ? "直角" : "スムーズ") + "）")
    }
    // ---- 素通り ----
    /// 点 P での、向き d（P に直交）を P に接する向きにそろえる
    private func tang(_ P: V4, _ d: V4) -> V4 { let t = d - P * dot4(d, P); return simd_length(t) > 1e-9 ? nrm(t) : t }
    /// P から Q へ向かう大円の向き（ちょうど反対側なら nil）
    private func toward(_ P: V4, _ Q: V4) -> V4? { let t = Q - P * dot4(Q, P); return simd_length(t) > 1e-6 ? nrm(t) : nil }
    /// 球面の上の大円の補間（slerp）：a から b へ割合 t
    private func slerp(_ a: V4, _ b: V4, _ t: Double) -> V4 {
        let w = acos(clamp1(dot4(a, b))); if w < 1e-7 { return a }
        if Double.pi - w < 1e-6 { return nrm(a * (1 - t) + b * t + tang(a, V4(0.1, 0.2, 0.3, 0.4)) * 1e-3) }
        return (a * sin((1 - t) * w) + b * sin(t * w)) / sin(w)
    }
    /// 球面の上のなめらかな曲線：P0（向き T0）から P1（向き T1）へ。球面の上のベジェ曲線（制御点を大円で動かし、大円の補間で組み立てる）。点の並び（P0 は入れない）
    ///   向きの大きさ m：ふつうは区間の角 θ。点での向きが区間の向きと大きくずれる時（引き返す点・短い区間）は大きくして、手前から大きく回り込む（急に曲がらない）
    private func hermite(_ P0: V4, _ T0: V4, _ P1: V4, _ T1: V4) -> [Vn] {
        let th = acos(clamp1(dot4(P0, P1)))
        let c0 = toward(P0, P1), c1 = toward(P1, P0).map { -$0 }
        let dev0 = c0.map { acos(clamp1(dot4($0, T0))) } ?? 0, dev1 = c1.map { acos(clamp1(dot4($0, T1))) } ?? 0
        // 制御点の離れ h は区間の 4 割まで（越えると制御点が行き先を通り越して、曲線にとがりができる）
        let m = max(th, 0.05) + 0.45 * (dev0 + dev1), h = min(m / 3, 0.4 * th, 1.2)
        let B0 = P0, B1 = nrm(P0 * cos(h) + T0 * sin(h)), B2 = nrm(P1 * cos(h) - T1 * sin(h)), B3 = P1
        let k = max(24, Int((th + m) / 0.004))
        return (1...k).map { i in
            let t = Double(i) / Double(k)
            let a = slerp(B0, B1, t), b = slerp(B1, B2, t), c = slerp(B2, B3, t)
            let d = slerp(a, b, t), e = slerp(b, c, t)
            return vn(slerp(d, e, t))
        }
    }
    /// 素通りの曲線を作って歩き始める：各点の向き＝来る向きと出る向きの平均（ちょうど反対側の点は、もう一方の向きのまま）
    private func startFlow() {
        let P = cr.pts, n = P.count
        var T: [V4] = []
        if n == 2 {                                                    // 2 点：2 点を通る大円（ループ）
            // 向き：② へ向かう大円（② がちょうど反対側なら、今の向きのまままっすぐ）
            let a = tang(P[0], cam.lookFrame().L), t0 = toward(P[0], P[1]) ?? (simd_length(a) > 1e-6 ? a : tang(P[0], V4(1, 0, 0, 0) + V4(0, 1, 0, 0)))
            // 大円 ① → ② → ① を 1 本の表に（② を通るのは距離 d、① に戻るのは 2π）
            let d = acos(clamp1(dot4(P[0], P[1]))), k = Int(2 * Double.pi / 0.006)
            var pts: [Vn] = [vn(P[0])]
            for i in 1...k { let s = 2 * Double.pi * Double(i) / Double(k); pts.append(vn(P[0] * cos(s) + t0 * sin(s))) }
            cr.flow = TurnGeo.table(pts); cr.flowMarks = [d, 2 * Double.pi]
            T = [t0, nrm(P[0] * -sin(d) + t0 * cos(d))]
        } else {
            for i in 0..<n {
                // 点の向き：来る向き b と出る向き o を、となりの区間の長さで重みをつけて平均（短い区間の向きを重く＝短い区間で急に曲がらない。長さで重みのキャットマル・ロム曲線と同じ考え）
                let o = toward(P[i], P[(i + 1) % n]), b = toward(P[i], P[(i + n - 1) % n]).map { -$0 }
                let Lo = acos(clamp1(dot4(P[i], P[(i + 1) % n]))), Li = acos(clamp1(dot4(P[i], P[(i + n - 1) % n])))
                let oo = o ?? b ?? V4(0, 0, 0, 0), bb = b ?? o ?? V4(0, 0, 0, 0)
                let turn = acos(clamp1(dot4(bb, oo)))
                var t = bb * Lo + oo * Li
                // 引き返すほどの角（120° より大きい）：重みなしの平均に、横へ逃げる向きを足して、ぐるっと回り込んで通る
                //   （長さの重みをつけると、向きが行き先の反対を向いて曲線がとがる。来る・出る向きが一直線でもとがる）
                if turn > 2 * Double.pi / 3 {
                    t = bb + oo
                    var side = tang(P[i], V4(0, 0, 1, 0)); side = side - oo * dot4(side, oo)
                    if simd_length(side) < 1e-6 { side = tang(P[i], V4(0, 1, 0, 0)); side = side - oo * dot4(side, oo) }
                    if simd_length(side) < 1e-6 { side = tang(P[i], V4(1, 0, 0, 0)); side = side - oo * dot4(side, oo) }
                    t += nrm(side) * ((turn - 2 * Double.pi / 3) / (Double.pi / 3))
                }
                if simd_length(t) < 1e-9 { t = oo }
                T.append(nrm(tang(P[i], t)))
            }
            var pts: [Vn] = [vn(P[0])], marks: [Double] = []
            for i in 0..<n {
                pts += hermite(P[i], T[i], P[(i + 1) % n], T[(i + 1) % n])
                marks.append(TurnGeo.table(pts).len)
            }
            cr.flow = TurnGeo.table(pts); cr.flowMarks = marks
        }
        // 今いる所から ① へ：今の向きから ① の向きへ滑らかに（もう ① にいれば、すぐ曲線へ）
        let here = cam.w.p
        if acos(clamp1(dot4(here, P[0]))) > 0.003 {
            var t0 = tang(here, cam.lookFrame().L); if simd_length(t0) < 1e-6 { t0 = toward(here, P[0]) ?? tang(here, V4(1, 0, 0, 0)) }
            cr.flowIn = TurnGeo.table([vn(here)] + hermite(here, t0, P[0], T[0]))
        } else { cr.flowIn = nil }
        cr.flowS = 0; cr.flowPassed = -1; cr.to = 0
        let nm = cr.names
        say?("自分の道「\(cr.title)」：素通り（" + (n == 2 ? "\(nm[0]) と \(nm[1]) を通る大円をぐるっと" : "\(n) 点を全部通る滑らかな曲線で、止まらずに巡回") + "）")
    }
    /// 素通りの曲線に沿って ds 進む
    private func flowStep(_ ds: Double) {
        guard let loop = cr.flow, loop.len > 1e-9 else { pathMode = .none; return }
        cr.flowS += ds
        if let fin = cr.flowIn {
            if cr.flowS < fin.len { crGo(nrm(v4(TurnGeo.at(fin, cr.flowS / fin.len)))); cr.to = 0; return }
            cr.flowS -= fin.len; cr.flowIn = nil; passed(0)
        }
        if cr.flowS >= loop.len { cr.flowS -= loop.len }
        crGo(nrm(v4(TurnGeo.at(loop, cr.flowS / loop.len))))
        let n = cr.pts.count, k = cr.flowMarks.firstIndex { $0 > cr.flowS } ?? (n - 1)   // 次に通る点：曲線の k 本目の終わり＝点 k + 1
        let next = (k + 1) % n
        if next != cr.to { passed(cr.to); cr.to = next }
    }
    private func passed(_ i: Int) {
        guard i != cr.flowPassed else { return }
        cr.flowPassed = i
        let n = cr.pts.count, j = (i + 1) % n
        say?("\(RouteStore.nums[i % 16]) \(cr.names[i]) を素通り → \(RouteStore.nums[j % 16]) \(cr.names[j])へ")
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
        if cr.flow != nil { flowStep(ds); return }
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
    @AppStorage("s3walk.coord.simple") private var simple = true   // 簡易入力：2 → 0.2、35 → 0.35、-999 → −0.999（ウェブ版と同じ）
    @AppStorage("s3walk.random.n") private var randN = 6               // ランダムな道の点の数（1〜16）
    @AppStorage("s3walk.random.marks") private var randMarks = true    // ランダムな点を目印にも置く（光る・通るとチェック）
    static let axisNames = ["x", "y", "z", "w"]
    /// 蛍光ペンの黄緑（今向かっている点）
    static let marker = Color(red: 0.84, green: 1.0, blue: 0.18)
    static let axisColors: [Color] = AXIS_RGB.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
    /// 目印の名前（模型のモードなら模型の名前も）：「目印 3（たぬき）」
    static func markName(_ r: Renderer, _ k: Int) -> String { "目印 \(k + 1)" + (r.set.mk == 4 && r.set.modelMarks ? "（" + Renderer.modelNames[r.markKind(k)] + "）" : "") }

    var body: some View {
        let r = model.r
        VStack(alignment: .leading, spacing: 6) {
            Text("自分の道").font(.caption.bold()).foregroundStyle(Space.lilac).padding(.top, 4)
            Picker("つなぎ方", selection: Binding(get: { r.set.routeFlow ? 2 : r.set.routeSmart ? 0 : 1 }, set: { v in
                r.set.routeFlow = v == 2; if v != 2 { r.set.routeSmart = v == 0 }; model.changed() })) {
                Text("おまかせ").tag(0); Text("最短").tag(1); Text("素通り").tag(2)
            }.pickerStyle(.segmented)
            Text(r.set.routeFlow ? "素通り：全部の点をちょうど通る滑らかな曲線で、止まらずに巡回（きつい角も手前から少しずつ曲がる。曲がり方の設定は使わない）"
                 : r.set.routeSmart ? "おまかせ：なるべくまっすぐ（引き返すくらいなら、まっすぐ回る長い方）・2 点はループ・天 → 地のような反対側はまっすぐ"
                 : "最短：いつも短い弧（2 点は往復で引き返す）")
                .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Picker("道", selection: Binding(get: { store.sel ?? UUID() }, set: { store.sel = $0 })) {
                    ForEach(store.routes) { Text($0.name + "（\($0.pts.count) 点）").tag($0.id) }
                }.pickerStyle(.menu).labelsHidden().fixedSize()
                Button("新しい道") { store.add() }
                Button("この道を消す") { store.remove() }.disabled(store.routes.count <= 1 && (store.routes.first?.pts.isEmpty ?? true))
            }
            // ランダムな点の道：S³ の上に一様にばらまいた点を n 個（1〜16）。目印にも置くと、光って・通るとチェックが付く
            HStack(spacing: 6) {
                Text("ランダムな点").font(.caption)
                Stepper(value: $randN, in: 1...RouteStore.maxPts) { Text("\(randN) 個").font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing) }.fixedSize()
                Toggle("目印にも置く", isOn: $randMarks).font(.caption).fixedSize()
                    .help("ランダムな点を目印にも置く（光る星になり、通るとチェックが付く。周回も数える）")
                Button("作る") { makeRandom(walk: false) }.help("ランダムな点の新しい道を作る（まだ歩かない）")
                Button("作って歩く") { makeRandom(walk: true) }.help("ランダムな点の新しい道を作って、すぐ歩き出す（1 点は行って止まる、2 点は往復、3 点以上は巡回）")
            }
            .controlSize(.small).buttonStyle(.bordered)
            if let i = store.index {
                TextField("道の名前", text: Binding(get: { store.routes[i].name }, set: { store.routes[i].name = $0 })).textFieldStyle(.roundedBorder)
                let pts = store.routes[i].pts
                if pts.isEmpty { Text("まだ点がない（下の極のボタン・置いた目印のボタンか、座標を入れて「この点を足す」）").font(.caption).foregroundStyle(Space.slate) }
                // 今向かっている点は、蛍光ペンの黄緑で光らせる（歩いている間、0.2 秒ごとに見直す）
                TimelineView(.periodic(from: .now, by: r.set.quiet ? 0.5 : 0.2)) { _ in
                    let walking = r.pathMode == .custom && r.cr.routeID == store.routes[i].id
                    let target = walking && r.cr.heading < r.cr.src.count ? r.cr.src[r.cr.heading] : -1
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pts.enumerated()), id: \.element.id) { k, q in
                            let on = k == target
                            HStack(spacing: 6) {
                                Text(RouteStore.nums[k]).foregroundStyle(on ? CustomRoutePanel.marker : Space.sky)
                                Text(q.name).lineLimit(1).foregroundStyle(on ? CustomRoutePanel.marker : Color.primary).fontWeight(on ? .bold : .regular)
                                Text(String(format: "(%.2f, %.2f, %.2f, %.2f)", q.p[0], q.p[1], q.p[2], q.p[3])).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(on ? CustomRoutePanel.marker.opacity(0.85) : Space.slate).lineLimit(1)
                                if on { Text("← 今ここへ").font(.caption2.bold()).foregroundStyle(CustomRoutePanel.marker).fixedSize() }
                                Spacer(minLength: 2)
                                Button { store.routes[i].pts.swapAt(k, k - 1) } label: { Image(systemName: "arrow.up") }.disabled(k == 0).help("1 つ前へ")
                                Button { store.routes[i].pts.remove(at: k) } label: { Image(systemName: "xmark") }.help("この点を外す")
                            }
                            .buttonStyle(.borderless).font(.callout)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(on ? CustomRoutePanel.marker.opacity(0.16) : .clear))
                            .shadow(color: on ? CustomRoutePanel.marker.opacity(0.7) : .clear, radius: 4)
                        }
                    }
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
                // 置いた目印（押すと最後に足す）。広い宇宙では目印にたどり着きにくいので、道にして往復・巡回できるように
                let marks = r.journey.marks
                if !marks.isEmpty { VStack(alignment: .leading, spacing: 4) {
                    Text("置いた目印").font(.caption).foregroundStyle(Space.slate)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], alignment: .leading, spacing: 4) {
                        ForEach(marks.indices, id: \.self) { k in
                            let c = Journey.markColor(k), name = CustomRoutePanel.markName(r, k)
                            Button { store.append(Store.arr(marks[k]), name) } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))).frame(width: 9, height: 9)
                                    Text(name).lineLimit(1)
                                }
                            }.disabled(full)
                        }
                    }
                    Button("目印を全部、順に足す（目印めぐり）") {
                        for k in marks.indices where (store.index.map { store.routes[$0].pts.count } ?? RouteStore.maxPts) < RouteStore.maxPts {
                            store.append(Store.arr(marks[k]), CustomRoutePanel.markName(r, k))
                        }
                    }.disabled(full).help("置いた目印を番号の順に、この道の最後へ足す（16 点まで）。2 つなら往復、3 つ以上なら巡回")
                }.controlSize(.small).buttonStyle(.bordered) }
                // 座標を入れる（ウェブ版と同じ：最後に入れた数ほど優先）
                Text("座標を入れる（x² ＋ y² ＋ z² ＋ w² ＝ 1。最後に入れた数がいちばん優先、まだ入れていない軸は残りを分け合う）")
                    .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
                Toggle("簡易入力（小数点なしの n 桁は 1/10ⁿ に：2 → 0.2、35 → 0.35、-999 → −0.999。1 と −1 はそのまま）", isOn: $simple)
                    .font(.caption).help("オフにすると書いたとおりの数（1 より大きい数は 1 に丸める）。小数点を打てば、オンでもそのまま")
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
        // ほかの欄へ移った時も、それまで打っていた数を入れる（Return を押さなくても）
        .onChange(of: focus) { old, _ in if let a = old { commit(a); syncTexts() } }
    }

    /// ランダムな点の道を作る（目印にも置く時は、その点に目印を置く）。walk なら、すぐ歩き出す
    func makeRandom(walk: Bool) {
        let r = model.r, rt = store.addRandom(randN)
        if randMarks { r.addMarks(rt.pts.map { V4($0.p[0], $0.p[1], $0.p[2], $0.p[3]) }) }
        if walk { r.startCustom(rt) }
        r.say?("ランダムな \(rt.pts.count) 点の道「\(rt.name)」を作った" + (randMarks ? "（目印にも置いた）" : "") + (walk ? "。歩き出す" : ""))
        model.changed()
    }
    /// 欄 a の文字を数にして入れる（簡易入力の時は 35 → 0.35 など。読めない時は元に戻す）
    func commit(_ a: Int) { if let v = CoordInput.parse(texts[a], simple: simple) { ci.set(a, max(-1, min(1, v))) } }
    func syncTexts() { for a in 0..<4 where focus != a { texts[a] = CustomRoutePanel.num(ci.v[a]) } }
    /// 欄に出す数：小数 4 桁まで、余分な 0 は消す（−0.999 が −1.00 に見えないように）
    static func num(_ v: Double) -> String {
        var t = String(format: "%.4f", v)
        while t.hasSuffix("0") { t.removeLast() }; if t.hasSuffix(".") { t += "0" }
        return t == "-0.0" ? "0.0" : t
    }
    func coordRow(_ a: Int) -> some View {
        HStack(spacing: 6) {
            Text(CustomRoutePanel.axisNames[a]).font(.system(size: 13, weight: .bold, design: .serif)).italic().foregroundStyle(CustomRoutePanel.axisColors[a]).frame(width: 14)
            Slider(value: Binding(get: { ci.v[a] }, set: { ci.set(a, ($0 * 100).rounded() / 100); syncTexts() }), in: -1...1)
            TextField("", text: $texts[a]).textFieldStyle(.roundedBorder).frame(width: 52).focused($focus, equals: a)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .onSubmit { commit(a); focus = nil; syncTexts() }
                // 打っている間：変換した数を横に（簡易入力で 35 → 0.35 など）
                .overlay(alignment: .bottomTrailing) {
                    if focus == a, let v = CoordInput.parse(texts[a], simple: simple), String(format: "%g", v) != texts[a].trimmingCharacters(in: .whitespaces) {
                        Text(String(format: "→ %g", max(-1, min(1, v)))).font(.system(size: 10, weight: .bold)).foregroundStyle(CustomRoutePanel.marker)
                            .padding(.horizontal, 4).background(Space.panel.opacity(0.95), in: Capsule()).offset(y: 14).fixedSize().allowsHitTesting(false)
                    }
                }
            Text(ci.rank[a] > 0 ? RouteStore.nums[ci.rank[a] - 1] + (ci.rank[a] == 1 ? "最新" : "") + String(format: " ±%.2f", ci.lim[a])
                 : ci.free.count == 1 ? String(format: "自動 %@%.2f", ci.v[a] >= 0 ? "+" : "−", ci.rr) : "分け合う")
                .font(.system(size: 10)).foregroundStyle(ci.rank[a] > 0 ? Space.sky : Space.slate).frame(width: 74, alignment: .leading)
        }
    }
}
