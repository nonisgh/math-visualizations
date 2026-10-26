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
        print("== パネルのドック（並べかえ・たたみ・保存）==")
        dockChecks()
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
            r.game.fakeDpad = 1; run(240, 0); r.game.fakeDpad = nil; let fast = r.autoSpeed   // 十字の上で速く
            run(120, 0); let cruise = r.autoSpeed, nTr = r.journey.trail.count, far = r.journey.dist
            run(450, -1); let back = r.journey.dist, nTr2 = r.journey.trail.count, rew = r.rewinding
            run(10, 0)
            r.walking = false; r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
            check(d1 > 0 && fwd > 1.02 && fwd < 1.5 && fast > 2 && abs(cruise - fast) < 1e-9 && rew && back < far - 0.3 && nTr2 < nTr && !r.rewinding,
                  String(format: "自走：左スティックの前でゆっくり加速、十字の上で ×%.1f（離してもそのまま）、手前でブレーキ→巻き戻し（道のり %.2f → %.2f、軌跡 %d → %d 点）", fast, far, back, nTr, nTr2))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 決まった道の速さ：十字の上を 1 秒押すと 2 倍、下を 2 秒で 1/2（極めぐりの道のままで）
        do {
            r.set = .plain; r.set.gamepad = true; r.startPath(.tour); r.game.fake = (.zero, .zero, false, false, false)
            func run(_ n: Int, _ y: Double) { r.game.fakeDpad = y; for _ in 0..<n { r.step(1.0 / 120) } }
            run(60, 0); let d0 = r.journey.dist; run(120, 1); let up = r.pathSpeed; run(240, -1); let dn = r.pathSpeed
            run(60, 0); let d1 = r.journey.dist, still = r.pathMode == .tour
            r.game.fake = nil; r.game.fakeDpad = nil; r.pathMode = .none; r.set.gamepad = false
            check(abs(up - 2) < 0.02 && abs(dn - 0.5) < 0.01 && still && d1 > d0, String(format: "決まった道の速さ：十字の上 1 秒で ×%.2f、下 2 秒で ×%.2f（極めぐりのまま）", up, dn))
            r.set = .plain; r.cam = Camera(); r.journey = Journey()
        }
        // 歩き続ける時の十字の上下：速さが変わり、殻の見える距離は変わらない（前は下で 0.3 まで縮んで、殻が見えなくなった）
        do {
            r.set = .plain; r.set.gamepad = true; r.cam = Camera(); r.journey = Journey(); r.walking = true; r.game.fake = (.zero, .zero, false, false, false)
            let sr = r.set.shellRange
            r.game.fakeDpad = 0; r.step(1.0 / 120); r.game.fakeDpad = 1; for _ in 0..<120 { r.step(1.0 / 120) }; let up = r.autoSpeed
            r.game.fakeDpad = nil; r.game.fake = nil; r.walking = false; r.set.gamepad = false; r.step(1.0 / 120)
            check(abs(up - 2) < 0.03 && r.set.shellRange == sr, String(format: "歩き続ける時の十字の上：速さ ×%.2f（1 秒）、殻の見える距離はそのまま", up))
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
            run(10, 0); r.game.fakeDpad = 1; run(1200, 0); r.game.fakeDpad = nil; let hi = r.autoSpeed
            run(1200, -1); let lo = r.autoSpeed, rew = r.rewinding
            r.walking = false; r.game.fake = (.zero, .zero, false, false, false); r.set.gamepad = false; r.step(1.0 / 120); r.game.fake = nil
            check(abs(hi - 3) < 1e-9 && abs(lo - 0.5) < 1e-9 && !rew, String(format: "自走の最高・最低：十字の上を押し続けて ×%.1f（最高 3）、手前で ×%.1f（最低 0.5、巻き戻さない）", hi, lo))
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
        for i in 0..<3 { r.game.fake = (.zero, .zero, false, i == 1, false); r.step(1.0 / 120) }
        let cleared = nTrail > 10 && r.journey.trail.count <= 1 && r.journey.foot.isEmpty && r.journey.trail2.count <= 1
        check(backDot < -0.1 && abs(vHalf / base - 0.6) < 0.02 && abs(vFull / base - 2.5) < 0.05 && abs(vBack / base - 2.5) < 0.05 && cleared,
              String(format: "コントローラー：手前に倒すと後ろへ（前との内積 %.2f）。速さ 6 割倒し ×%.2f・倒しきり ×%.2f・後ろへ倒しきり ×%.2f。L3 で軌跡を消す（%d 点 → %d 点）", backDot, vHalf / base, vFull / base, vBack / base, nTrail, r.journey.trail.count))
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
    static func nearEast(_ d: Double) -> Walker {
        let n = V4(0, 1, 0, 1) / 2.0.squareRoot(), p = V4(1, 0, 0, 0) * cos(d) + n * sin(d), f = nrm(V4(1, 0, 0, 0) * sin(d) - n * cos(d)), u = V4(0, 0, 1, 0)
        var r = V4(0, 1, 0, -1) / 2.0.squareRoot(); r -= p * dot4(r, p); r -= f * dot4(r, f); r = nrm(r)
        let m = simd_double4x4(rows: [r, u, f, p])
        if m.determinant < 0 { r = -r }
        return Walker(p: p, r: r, u: u, f: f)
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
    static func walkPNG(_ dir: String) {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev), let d = UserDefaults(suiteName: "io.github.nonisgh.s3walk")?.dictionary(forKey: Store.key) else { return }
        var us = Settings(); us.load((d["set"] as? [String: Any]) ?? [:]); r.set = us
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
