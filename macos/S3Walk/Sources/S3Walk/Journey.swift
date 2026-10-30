// 歩いた記録：進んだ距離・足あと・置いた目印・赤道や極を通った知らせ・縦横無尽（ウェブ版の W・step・addMark・loop の roam）
import Foundation
import simd

struct Journey {
    var dist = 0.0, lastFoot = 0.0
    var foot: [V4] = []                  // 足あと：0.6 進むごと、最大 40（ウェブ版と同じ）
    var trail: [V4] = []                 // 地図の軌跡：0.02 進むごと、最大 12000（ウェブ版と同じ）
    var lastTrail = 0.0
    var w2 = Walker2.north               // S² の仲間
    var trail2: [V3] = [], foot2: [V3] = [], marks2: [V3] = []
    var marks: [V4] = []                 // 「ここに目印を置く」で置いた目印
    var markKinds: [Int] = []            // 目印ごとの模型（シェーダーの番号 0〜8。−1 は前の版で置いたもの＝全体の「模型」に従う）。marks と同じ数
    /// チェックポイント：歩いて通った目印（その目印の位置。並びは通った順）。目印のそば（0.12 以内）に外から入った時に記録する
    var marksHit: [V4] = []
    var polesHit: [Int] = []             // 通った極（FIXED の番号。通った順）
    var lapPoles: [Int] = []             // 歩いている自分の道が通る極（2 つ以上あれば、この極を全部通って 1 周。8 つの極を全部通らない道でも周回する）
    /// 自分の道の点（ランダムな点・座標で入れた点など。極・目印と同じ所は除く）も、歩いている間はチェックポイント。routeNames は知らせの名前
    var routePts: [V4] = [], routeNames: [String] = [], routeHit: [V4] = [], enteredRoute: [V4] = []
    func isRouteHit(_ m: V4) -> Bool { routeHit.contains { simd_distance($0, m) < 1e-9 } }
    /// 周回：目印（2 つ以上）を全部通ったら 1 周。目印が 2 つより少ない時は 8 つの極を全部通ったら 1 周。チェックをリセットして次の周へ（1 ＝ 1 周目）
    var lap = 1
    /// 1 周したら歩いた跡（道すじ・足あと）も消す（4D 球アナロジーの「1 周で跡を消す」で入り切り）
    static var lapClearsTrail = true
    var lastP: V4? = nil
    /// 外から目印・極のそば（checkR）に入って、まだ数えていないもの。いちばん近づいて離れ始めた所で数える（すぐ横を通り過ぎた瞬間）
    var enteredMarks: [V4] = [], enteredPoles: Set<Int> = []
    /// 当たった瞬間の記録（場所・時刻 systemUptime・極の番号、目印は −1）。4D 球アナロジーがピカッと光らせる。周回でチェックが消えても光るよう、ここに残す（2 秒で消す）
    static var hitPulse: [(p: V4, t: Double, pole: Int)] = []
    static let checkR = 0.12
    func isHit(_ m: V4) -> Bool { marksHit.contains { simd_distance($0, m) < 1e-9 } }
    var wasW = 1.0
    var prevS: Double? = nil, prevN: Double? = nil
    var passedN = true, passedS = false
    var roamT = 0.0

    static let footEvery = 0.6, footMax = 40

    /// 歩いた後に呼ぶ：距離・足あと・知らせ。say は知らせの文を受ける
    mutating func walked(_ p: V4, _ s: Double, footOn: Bool, say: (String) -> Void) {
        dist += s
        if dist - lastTrail >= 0.02 {
            trail.append(p); trail2.append(w2.p); lastTrail = dist
            if trail.count > 12000 { trail.removeFirst(trail.count - 12000); trail2.removeFirst(max(0, trail2.count - 12000)) }
        }
        if footOn && dist - lastFoot >= Journey.footEvery {
            foot.append(p); foot2.append(w2.p); lastFoot = dist
            if foot.count > Journey.footMax { foot.removeFirst(); foot2.removeFirst() }
        }
        let w = p.w, dN = acos(max(-1, min(1, w))), dS = Double.pi - dN
        if wasW > 0 && w <= 0 { say("赤道を通過（アナ極から π/2 ≈ 1.57）") }
        if wasW < 0 && w > 0 { say("赤道を通過（アナ極まであと π/2）") }
        // カタ極・アナ極のいちばん近く（距離が減ってから増えに転じた所）を通ったら知らせる
        if let ps = prevS, ps < 0.2, dS > ps, !passedS {
            say(dS < 0.03 ? "カタ極を通過！ ここはアナ極の反対側（対蹠点）" : String(format: "カタ極のすぐそば（%.2f）を通過。アナ極の反対側", ps))
            passedS = true; passedN = false
        }
        if let pn = prevN, pn < 0.2, dN > pn, !passedN, dist > 1 {
            say(dN < 0.03 ? "アナ極に戻ってきた！（1 周 = 2π ≈ 6.28）" : String(format: "アナ極のすぐそば（%.2f）まで戻ってきた（1 周 ≈ 6.28）", pn))
            passedN = true; passedS = false
        }
        // チェックポイント：目印のそばに外から入ったら、通ったと記録して知らせる（置いた所に立っている間は数えない。離れて戻ってきたら数える）
        let cR = cos(Journey.checkR)
        // 入った：外からそばに入った目印を覚える（置いた所に立っている間は数えない＝外から入った時だけ）。そばを出たら忘れる
        for m in marks where !isHit(m) {
            let inNow = simd_dot(p, m) > cR, wasOut = lastP.map { simd_dot($0, m) <= cR } ?? false
            if inNow && wasOut && !enteredMarks.contains(where: { simd_distance($0, m) < 1e-9 }) { enteredMarks.append(m) }
            if !inNow { enteredMarks.removeAll { simd_distance($0, m) < 1e-9 } }
        }
        // 数える：入っていて、いちばん近づいた所を過ぎた（前より離れた）時
        for (i, m) in marks.enumerated() where !isHit(m) && enteredMarks.contains(where: { simd_distance($0, m) < 1e-9 }) && (lastP.map { simd_dot(p, m) < simd_dot($0, m) } ?? false) {
            enteredMarks.removeAll { simd_distance($0, m) < 1e-9 }
            Journey.hitPulse.append((m, ProcessInfo.processInfo.systemUptime, -1))
            marksHit.append(m)
            let n = marks.filter { isHit($0) }.count
            if n == marks.count && marks.count >= 2 && routePts.count < 2 {
                // 1 周：チェックをリセットして次の周へ（今いる目印は、離れてまた入った時に数える）
                lap += 1; marksHit = []; polesHit = []
                if Journey.lapClearsTrail { trail = [p]; trail2 = [w2.p]; foot = []; foot2 = [] }   // 跡も新しい周から
                say("チェック！ 目印 \(i + 1) を通過。\(lap - 1) 周！ チェックポイントをリセットして \(lap) 周目へ")
            } else {
                say(n == marks.count ? "チェック！ 目印 \(i + 1) を通過。これで全部の目印を通った（\(n)/\(marks.count)）" : "チェック！ 目印 \(i + 1) を通過（\(n)/\(marks.count)）")
            }
        }
        // 自分の道の点も同じように（当たった時の光とチリンは目印と同じ）。2 つ以上あれば、全部通って 1 周
        for m in routePts where !isRouteHit(m) {
            let inNow = simd_dot(p, m) > cR, wasOut = lastP.map { simd_dot($0, m) <= cR } ?? false
            if inNow && wasOut && !enteredRoute.contains(where: { simd_distance($0, m) < 1e-9 }) { enteredRoute.append(m) }
            if !inNow { enteredRoute.removeAll { simd_distance($0, m) < 1e-9 } }
        }
        for (i, m) in routePts.enumerated() where !isRouteHit(m) && enteredRoute.contains(where: { simd_distance($0, m) < 1e-9 }) && (lastP.map { simd_dot(p, m) < simd_dot($0, m) } ?? false) {
            enteredRoute.removeAll { simd_distance($0, m) < 1e-9 }
            Journey.hitPulse.append((m, ProcessInfo.processInfo.systemUptime, -1))
            routeHit.append(m)
            let n = routePts.filter { isRouteHit($0) }.count, name = i < routeNames.count ? routeNames[i] : "道の点 \(i + 1)"
            if n == routePts.count && routePts.count >= 2 {
                lap += 1; routeHit = []; polesHit = []
                if Journey.lapClearsTrail { trail = [p]; trail2 = [w2.p]; foot = []; foot2 = [] }
                say("チェック！ \(name) を通過。\(lap - 1) 周！ チェックポイントをリセットして \(lap) 周目へ")
            } else {
                say("チェック！ \(name) を通過（\(n)/\(routePts.count)）")
            }
        }
        // 極も同じように：外からそばに入って、いちばん近づいた所を過ぎたら通ったと記録（アナ極・カタ極は上の知らせがあるので、ほかの 6 つだけ知らせる）
        for (k, m) in FIXED.enumerated() where !polesHit.contains(k) {
            let inNow = simd_dot(p, m.c) > cR, wasOut = lastP.map { simd_dot($0, m.c) <= cR } ?? false
            if inNow && wasOut { enteredPoles.insert(k) }
            if !inNow { enteredPoles.remove(k) }
        }
        for (k, m) in FIXED.enumerated() where !polesHit.contains(k) && enteredPoles.contains(k) && (lastP.map { simd_dot(p, m.c) < simd_dot($0, m.c) } ?? false) {
            enteredPoles.remove(k)
            Journey.hitPulse.append((m.c, ProcessInfo.processInfo.systemUptime, k))
            polesHit.append(k)
            if k >= 2 { say("チェック！ \(MapRenderer.poleName(m))を通過（極 \(polesHit.count)/8）") }
        }
        // 目印が 2 つより少ない時は、8 つの極が周回のチェックポイント
        if marks.count < 2 && routePts.count < 2 && (lapPoles.count >= 2 ? lapPoles.allSatisfy { polesHit.contains($0) } : polesHit.count >= FIXED.count) {
            lap += 1; polesHit = []
            if Journey.lapClearsTrail { trail = [p]; trail2 = [w2.p]; foot = []; foot2 = [] }
            say(lapPoles.count >= 2 ? "道の極を全部通った！ \(lap - 1) 周。チェックポイントをリセットして \(lap) 周目へ" : "8 つの極を全部通った！ \(lap - 1) 周。チェックポイントをリセットして \(lap) 周目へ")
        }
        lastP = p
        if !Journey.hitPulse.isEmpty { let now = ProcessInfo.processInfo.systemUptime; Journey.hitPulse.removeAll { now - $0.t > 2 } }
        prevS = dS; prevN = dN; wasW = w
    }

    /// 縦横無尽：ゆっくりした波（周期のちがう sin の和）で、方位の回る速さと仰角の目標を決め、なめらかに追いかける
    mutating func roam(_ cam: inout Camera, _ dt: Double, _ k: Double) {
        roamT += dt * k
        let T = roamT
        let azRate = 42 * sin(0.31 * T) + 26 * sin(0.77 * T + 1.3) + 14 * sin(1.9 * T + 2.1)
        let elTarget = 34 * sin(0.23 * T + 0.5) + 16 * sin(0.61 * T + 2.0)
        cam.az += azRate * dt * k
        cam.el += (elTarget - cam.el) * min(1, 1.2 * dt * k)
        cam.el = max(-80, min(80, cam.el))
    }

    /// 置いた目印の色（ウェブ版の addMark：色相 i·47 + 20、彩度 0.9、明るさ 0.6）
    static func markColor(_ i: Int) -> SIMD3<Float> {
        let h = Double((i * 47 + 20) % 360) / 360, s = 0.9, l = 0.6
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func f(_ t0: Double) -> Double {
            var t = t0.truncatingRemainder(dividingBy: 1); if t < 0 { t += 1 }
            return t < 1.0 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2.0 / 3 ? p + (q - p) * (2.0 / 3 - t) * 6 : p
        }
        return SIMD3(Float(f(h + 1.0 / 3)), Float(f(h)), Float(f(h - 1.0 / 3)))
    }
}

// ---- 保存：設定・いる場所と向き・置いた目印を UserDefaults に（次に開いた時に続きから）----
extension Settings {
    /// 確かめ用：光る線なし（ウェブ版と同じ絵）
    static var plain: Settings { var s = Settings(); s.glow = 0; s.lineCrisp = false; s.solidWire = 0.35; s.cine = false; s.nebula = false; s.polePlanet = false; s.free360 = false; s.wireFloor = 0; s.lineViv = 0; s.mapExpand = 0; s.hazeK = 1; s.trailLight = false; return s }
    static let dKeys: [(String, WritableKeyPath<Settings, Double>)] = [
        ("fov", \.fov), ("maxD", \.maxD), ("fog", \.fog), ("fade", \.fade), ("depth", \.depth),
        ("shellOp", \.shellOp), ("shellBack", \.shellBack), ("shellLum", \.shellLum), ("shellRange", \.shellRange),
        ("spd", \.spd), ("cruise", \.cruise), ("routeStart", \.routeStart), ("quietScale", \.quietScale), ("mapMini", \.mapMini), ("roamK", \.roamK), ("scale", \.scale), ("mapXW", \.mapXW), ("mapYW", \.mapYW), ("mapZW", \.mapZW), ("mapD", \.mapD), ("glow", \.glow), ("uniL", \.uniL), ("mapBright", \.mapBright), ("lineViv", \.lineViv), ("modelSize", \.modelSize), ("planetSize", \.planetSize), ("gridTilt", \.gridTilt), ("gridAz", \.gridAz), ("gridSpinRate", \.gridSpinRate), ("followD", \.followD), ("mapExpand", \.mapExpand), ("trailKeep", \.trailKeep), ("hazeK", \.hazeK), ("mapWidth", \.mapWidth), ("mapSplit2", \.mapSplit2), ("mapSplit3a", \.mapSplit3a), ("mapSplit3b", \.mapSplit3b), ("autoAccel", \.autoAccel), ("autoMax", \.autoMax), ("autoAccelK", \.autoAccelK), ("autoMin", \.autoMin), ("wireFloor", \.wireFloor), ("stars", \.stars), ("band", \.band), ("nebK", \.nebK), ("bloom", \.bloom), ("expo", \.expo), ("grain", \.grain), ("lineW", \.lineW), ("solidWire", \.solidWire), ("picLine", \.picLine), ("turns", \.turns), ("tilt", \.tilt), ("prec", \.prec), ("ringStep", \.ringStep), ("map2XW", \.map2XW), ("map2YW", \.map2YW), ("map2ZW", \.map2ZW), ("mapAltXW", \.mapAltXW), ("mapAltYW", \.mapAltYW), ("mapAltZW", \.mapAltZW), ("map2AltXW", \.map2AltXW), ("map2AltYW", \.map2AltYW), ("map2AltZW", \.map2AltZW)]
    static let bKeys: [(String, WritableKeyPath<Settings, Bool>)] = [
        ("shell", \.shell), ("shellSolid", \.shellSolid), ("shellBare", \.shellBare), ("eq", \.eq), ("lite", \.lite), ("grand", \.grand),
        ("poles", \.poles), ("hidePair", \.hidePair), ("orient", \.orient), ("selfBall", \.selfBall), ("foot", \.foot), ("marksOn", \.marksOn),
        ("fps60", \.fps60), ("autoQ", \.autoQ), ("mapFollow", \.mapFollow), ("routeSmart", \.routeSmart), ("quiet", \.quiet), ("routeFlow", \.routeFlow), ("tourFlow", \.tourFlow), ("tourShow", \.tourShow), ("cursor3D", \.cursor3D), ("mapAxes", \.mapAxes), ("mapTrail", \.mapTrail), ("mapPan", \.mapPan), ("turnSharp", \.turnSharp), ("edrOn", \.edrOn), ("space", \.space), ("polePlanet", \.polePlanet), ("trailLight", \.trailLight), ("autoRewind", \.autoRewind), ("modelPoles", \.modelPoles), ("modelMarks", \.modelMarks), ("modelSelf", \.modelSelf), ("follower", \.follower), ("idleReuse", \.idleReuse), ("rainbow4", \.rainbow4), ("turboHold", \.turboHold), ("gridSpin", \.gridSpin), ("free360", \.free360), ("shAxis", \.shAxis), ("shAxX", \.shAxX), ("shAxY", \.shAxY), ("shAxZ", \.shAxZ), ("shAxW", \.shAxW), ("markGrow", \.markGrow), ("padSwap", \.padSwap), ("nebula", \.nebula), ("cine", \.cine), ("map2On", \.map2On), ("s2On", \.s2On), ("lineCrisp", \.lineCrisp), ("mapLeft", \.mapLeft), ("map2Follow", \.map2Follow), ("haptics", \.haptics), ("gamepad", \.gamepad), ("padGame", \.padGame), ("padInvX", \.padInvX), ("padInvY", \.padInvY), ("ghostBack", \.ghostBack), ("circ", \.circ), ("room", \.room)]
    static let iKeys: [(String, WritableKeyPath<Settings, Int>)] = [("shellN", \.shellN), ("mapCorner", \.mapCorner), ("cursorShape", \.cursorShape), ("passes", \.passes), ("mapRange", \.mapRange), ("map2Range", \.map2Range), ("mk", \.mk), ("lens", \.lens), ("ringAxis", \.ringAxis), ("modelKind", \.modelKind), ("markModel", \.markModel), ("shCap", \.shCap)]
    func dict() -> [String: Any] {
        var d: [String: Any] = [:]
        for (k, kp) in Settings.dKeys { d[k] = self[keyPath: kp] }
        for (k, kp) in Settings.bKeys { d[k] = self[keyPath: kp] }
        for (k, kp) in Settings.iKeys { d[k] = self[keyPath: kp] }
        return d
    }
    mutating func load(_ d: [String: Any]) {
        for (k, kp) in Settings.dKeys { if let v = d[k] as? Double, v.isFinite { self[keyPath: kp] = v } }
        for (k, kp) in Settings.bKeys { if let v = d[k] as? Bool { self[keyPath: kp] = v } }
        for (k, kp) in Settings.iKeys { if let v = d[k] as? Int { self[keyPath: kp] = v } }
    }
}

enum Store {
    static let key = "s3walk.state.v1"
    static func arr(_ v: V4) -> [Double] { [v.x, v.y, v.z, v.w] }
    static func a3(_ v: V3) -> [Double] { [v.x, v.y, v.z] }
    static func v3(_ a: Any?) -> V3? { guard let a = a as? [Double], a.count == 3 else { return nil }; return V3(a[0], a[1], a[2]) }
    static func v4(_ a: Any?) -> V4? { guard let a = a as? [Double], a.count == 4 else { return nil }; return V4(a[0], a[1], a[2], a[3]) }
    static func snapshot(_ r: Renderer) -> [String: Any] {
        let c = r.cam
        return ["set": r.set.dict(), "p": arr(c.w.p), "r": arr(c.w.r), "u": arr(c.w.u), "f": arr(c.w.f),
                "az": c.az, "el": c.el, "dist": r.journey.dist, "marks": r.journey.marks.map(arr), "markKinds": r.journey.markKinds, "marksHit": r.journey.marksHit.map(arr), "polesHit": r.journey.polesHit, "lap": r.journey.lap,
                "p2": a3(r.journey.w2.p), "r2": a3(r.journey.w2.r), "f2": a3(r.journey.w2.f), "marks2": r.journey.marks2.map(a3)]
    }
    static func save(_ r: Renderer) { UserDefaults.standard.set(snapshot(r), forKey: key) }
    static func restore(_ r: Renderer) {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return }
        if let s = d["set"] as? [String: Any] { r.set.load(s) }
        if r.set.autoQ { r.set.scale = 1 }               // 細かさが自動の時は、いちばん細かい所から始める（前に下げた値を持ち越さない）
        applyPosition(r, d)
    }
    /// 今いる所・向き・目印（snapshot の set 以外）を当てる。同期で Supabase から読んだ時にも使う
    static func applyPosition(_ r: Renderer, _ d: [String: Any]) {
        if let p = v4(d["p"]), let rr = v4(d["r"]), let u = v4(d["u"]), let f = v4(d["f"]) {
            var w = Walker(p: nrm(p), r: rr, u: u, f: f); orthoFrame(&w); r.cam.w = w
        }
        if let az = d["az"] as? Double { r.cam.az = az }
        if let el = d["el"] as? Double { r.cam.el = el }
        if let m = d["marks"] as? [[Double]] { r.journey.marks = m.compactMap { v4($0) } }
        r.journey.markKinds = (d["markKinds"] as? [Int]) ?? []
        r.journey.marksHit = ((d["marksHit"] as? [[Double]]) ?? []).compactMap { v4($0) }
        r.journey.polesHit = ((d["polesHit"] as? [Int]) ?? []).filter { $0 >= 0 && $0 < 8 }
        r.journey.lap = max(1, (d["lap"] as? Int) ?? 1)
        if r.journey.markKinds.count != r.journey.marks.count { r.journey.markKinds = Array((r.journey.markKinds + Array(repeating: -1, count: r.journey.marks.count)).prefix(r.journey.marks.count)) }
        if let p = v3(d["p2"]), let rr = v3(d["r2"]), let f = v3(d["f2"]) { r.journey.w2 = Walker2(p: simd_normalize(p), r: rr, f: f) }
        if let m = d["marks2"] as? [[Double]] { r.journey.marks2 = m.compactMap { v3($0) } }
        if r.journey.marks2.count != r.journey.marks.count { r.journey.marks2 = Array(repeating: r.journey.w2.p, count: r.journey.marks.count) }
        if let dist = d["dist"] as? Double { r.journey.dist = dist; r.journey.lastFoot = dist }
        let w = r.cam.w.p.w; r.journey.wasW = w
        r.journey.passedN = acos(max(-1, min(1, w))) < 0.2
    }
}
