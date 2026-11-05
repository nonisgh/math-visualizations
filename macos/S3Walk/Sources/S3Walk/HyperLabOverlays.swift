// 超球の窓の上に重ねるもの：座標軸・2 重回転の円・名前の札・鏡・照り返しの加減・目印と極・切り口・星・光の回り込み・フレア
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    /// a から b への矢印（細い管＋円すいの頭。マイナスの側は細く）。光の当たり方は輪と同じ（つや）
    static func arrow(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, r: Double = 0.016, plus: Bool = false) -> [HLVert] {
        let d = b - a, L = simd_length(d); guard L > 1e-6 else { return [] }
        let f = d / L, up0 = abs(f.y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let ex = simd_normalize(simd_cross(up0, f)), ey = simd_cross(f, ex)
        let head = min(0.16, L * 0.2), mid = (a + b) / 2, neck = b - f * head, seg = 14
        var out: [HLVert] = []
        func v(_ p: SIMD3<Double>, _ n: SIMD3<Double>, _ c: SIMD3<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: SIMD4(SIMD3<Float>(n), 0), c: SIMD4(c, 1)) }
        for k in 0..<seg {
            let t0 = Double(k) / Double(seg) * 2 * .pi, t1 = Double(k + 1) / Double(seg) * 2 * .pi
            let n0 = ex * cos(t0) + ey * sin(t0), n1 = ex * cos(t1) + ey * sin(t1)
            // 管：マイナス側（a → 真ん中）は細く暗め、プラス側（真ん中 → 頭）は太く
            for (p, q, rr, c) in plus ? [(a, neck, r, col)] : [(a, mid, r * 0.55, col * 0.6), (mid, neck, r, col)] {
                out += [v(p + n0 * rr, n0, c), v(q + n0 * rr, n0, c), v(q + n1 * rr, n1, c), v(p + n0 * rr, n0, c), v(q + n1 * rr, n1, c), v(p + n1 * rr, n1, c)]
            }
            // 頭（円すい）と、その底
            let hr = r * 3.2, s0 = simd_normalize(n0 * head + f * hr), s1 = simd_normalize(n1 * head + f * hr)
            out += [v(neck + n0 * hr, s0, col), v(b, simd_normalize(s0 + s1), col), v(neck + n1 * hr, s1, col)]
            out += [v(neck, -f, col * 0.7), v(neck + n1 * hr, -f, col * 0.7), v(neck + n0 * hr, -f, col * 0.7)]
        }
        return out
    }
    /// 細い線の矢印：カメラに向いた細い帯と、平たい三角の矢じり（光は当てない。マイナス側は淡く）
    /// perspW：ダイブで寄る時。太さを目からの距離に比べて変える（距離 perspW の所で w。画面の上ではどこもだいたい同じ細さ。寄っても太い帯にならない）
    static func flatArrow(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, eye: SIMD3<Double>, w: Double, plus: Bool, perspW: Double? = nil) -> [HLVert] {
        let d = b - a, L = simd_length(d); guard L > 1e-6 else { return [] }
        let f = d / L, head = min(0.13, L * 0.18), neck = b - f * head, mid = (a + b) / 2
        if let D0 = perspW {
            func v(_ p: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: c) }
            func side(_ p: SIMD3<Double>) -> SIMD3<Double> {
                var s = simd_cross(f, eye - p); let l = simd_length(s); s = l < 1e-9 ? .zero : s / l
                return s * w * max(0.002, simd_length(eye - p) / D0)
            }
            func strip(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ c: SIMD4<Float>) -> [HLVert] {
                var o: [HLVert] = []; let n = 64
                for i in 0..<n {
                    let p0 = p + (q - p) * (Double(i) / Double(n)), p1 = p + (q - p) * (Double(i + 1) / Double(n)), s0 = side(p0), s1 = side(p1)
                    o += [v(p0 - s0, c), v(p1 - s1, c), v(p1 + s1, c), v(p0 - s0, c), v(p1 + s1, c), v(p0 + s0, c)]
                }
                return o
            }
            let on = SIMD4(col, 1), dim = SIMD4(col * 0.75, 0.55)
            var out = plus ? strip(a, neck, on) : strip(a, mid, dim) + strip(mid, neck, on)
            let sn = side(neck) * 4.5
            out += [v(neck - sn, on), v(b, on), v(neck + sn, on)]
            return out
        }
        var sd = simd_cross(f, eye - mid); let sl = simd_length(sd); sd = sl < 1e-9 ? SIMD3(0, 0, 0) : sd / sl
        func v(_ p: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: c) }
        func band(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ c: SIMD4<Float>) -> [HLVert] {
            [v(p - sd * w, c), v(q - sd * w, c), v(q + sd * w, c), v(p - sd * w, c), v(q + sd * w, c), v(p + sd * w, c)]
        }
        let on = SIMD4(col, 1), dim = SIMD4(col * 0.75, 0.55)
        var out = plus ? band(a, neck, on) : band(a, mid, dim) + band(mid, neck, on)
        out += [v(neck - sd * w * 4.5, on), v(b, on), v(neck + sd * w * 4.5, on)]
        return out
    }
    /// 左：x・y・z の 3 本（球と一緒に傾く）。z は右の w に当たるので紫
    func drawAxes3(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let lr = leftRot(), (eye, _, _, _) = camBasis()
        var tri: [HLVert] = []
        for k in 0..<3 {
            var d = SIMD3<Double>(0, 0, 0); d[k] = Self.AXL
            let a = st.axPlus ? SIMD3<Double>(0, 0, 0) : lr * -d, b = lr * d, c = Self.axisCol[k == 2 ? 3 : k]
            tri += st.axThin ? Self.flatArrow(a, b, c, eye: eye, w: 0.006, plus: st.axPlus) : Self.arrow(a, b, c, plus: st.axPlus)
        }
        drawAxisTris(e, u0, tri, depthTest: true)
    }
    func drawAxisTris(_ e: MTLRenderCommandEncoder, _ u0: HLUni, _ tri: [HLVert], depthTest: Bool, flat: Bool = false) {
        guard !tri.isEmpty else { return }
        var u = u0; u.model = matrix_identity_float4x4; u.cut = .zero
        if st.axThin || flat { u.g.z = 0; e.setRenderPipelineState(alphaPipe) } else { u.g.z = 1; u.g.w = 1; e.setRenderPipelineState(opaquePipe) }
        e.setDepthStencilState(depthWrite)
        tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 右：x・y・z・w の 4 本の軸を、殻と同じ 4D の回転・遠近で写す（4D の直線は遠近で写しても直線）
    func axis4(_ k: Int, _ s: Double) -> SIMD3<Double> {
        var e4 = SIMD4<Double>(0, 0, 0, 0); e4[k] = s * Self.AXL
        let v = xf(e4), sc = st.camW / max(0.6, st.camW - v.w) * Self.SCALE
        return SIMD3(v.x, v.y, v.z) * sc
    }
    func drawAxes4(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let (eye, _, _, _) = camBasis()
        var tri: [HLVert] = []
        for k in 0..<4 {
            let a = axis4(k, st.axPlus ? 0 : -1), b = axis4(k, 1)
            let zoom = side == .right && dvT > 0                     // ダイブ：寄っても細い線のまま（立体の矢印も、この間は線に）
            tri += st.axThin || zoom ? Self.flatArrow(a, b, Self.axisCol[k], eye: eye, w: zoom ? 0.012 : 0.007, plus: st.axPlus, perspW: zoom ? st.viewDist : nil) : Self.arrow(a, b, Self.axisCol[k], plus: st.axPlus)
        }
        drawAxisTris(e, u0, tri, depthTest: true)
    }
    /// 2 重回転の 2 つの円：X-Y の円（東・北・西・南）と Z-W の円（アナ・天・カタ・地）。超球と一緒に回すので、円の形は動かず、点線が円に沿って流れる
    func drawRot2Rings(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let eye = camBasis().0, n = 180, dash = 6
        var tri: [HLVert] = []
        func ring(_ col: SIMD3<Float>, _ at: (Double) -> SIMD4<Double>) {
            let pts = (0...n).map { walkPlace(at(Double($0) / Double(n) * 2 * .pi)) }
            for i in 0..<n where (i / dash) % 2 == 0 {
                let (a, fa) = pts[i], (b, fb) = pts[i + 1]
                var s = simd_cross(b - a, eye - a); let l = simd_length(s)
                guard l > 1e-9 else { continue }
                s *= 0.014 / l
                func v(_ p: SIMD3<Double>, _ f: Double) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: SIMD4(col, Float(0.4 + 0.6 * f))) }
                tri += [v(a - s, fa), v(b - s, fb), v(b + s, fb), v(a - s, fa), v(b + s, fb), v(a + s, fa)]
            }
        }
        ring(SIMD3(1.0, 0.72, 0.2)) { SIMD4(cos($0), sin($0), 0, 0) }
        ring(SIMD3(1.0, 0.35, 0.9)) { SIMD4(0, 0, cos($0), sin($0)) }
        drawAxisTris(e, u0, tri, depthTest: false, flat: true)
    }
    /// 軸の名前の文字の絵（数式の斜体。暗いふちどりつき。1 度だけ作る）
    func labelTexture(_ s: String, _ col: SIMD3<Float>, math: Bool = true, serif: Bool = false) -> MTLTexture? {
        let key = "\(s)|\(col)|\(math)|\(serif)"
        if let t = labelTex[key] { return t }
        let size: CGFloat = 96
        let name = ["KaTeX_Math-Italic", "STIXTwoText-Italic", "Georgia-Italic"].first { (CTFontCopyPostScriptName(CTFontCreateWithName($0 as CFString, 12, nil)) as String) == $0 } ?? "Georgia-Italic"
        // 軸の名前は数式の斜体、目印の番号と ✓ はふつうの太字（数式の書体だと ✓ が √ のように見える）
        let font = serif ? CTFontCreateWithName("Baskerville-SemiBold" as CFString, size * 0.95, nil)   // 英語モードの極の名前（セリフ体）
            : math ? CTFontCreateWithName(name as CFString, size, nil) : (CTFontCreateUIFontForLanguage(.emphasizedSystem, size * 0.9, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size * 0.9, nil))
        func line(_ stroke: Bool) -> CTLine {
            var a: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let c = CGColor(srgbRed: CGFloat(col.x), green: CGFloat(col.y), blue: CGFloat(col.z), alpha: 1), dark = CGColor(srgbRed: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 0.92)
            a[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = stroke ? dark : c
            if stroke { a[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 22.0; a[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = dark }
            let m = NSMutableAttributedString(string: s, attributes: a)
            // 通った極・目印の ✓ だけ蛍光の黄緑（名前はその色のまま）
            if !stroke && s.hasPrefix("✓") { m.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 1), range: NSRange(location: 0, length: 1)) }
            return CTLineCreateWithAttributedString(m)
        }
        let fill = line(false), bounds = CTLineGetBoundsWithOptions(fill, .useGlyphPathBounds)
        let check = s.hasPrefix("✓"), pad: CGFloat = check ? 40 : 18, W = Int(ceil(bounds.width + pad * 2)), H = Int(ceil(size * (check ? 1.55 : 1.3)))
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if check {
            // 通った極・目印：蛍光の黄緑の長丸で囲む（中はうすく光らせる）
            let r = CGRect(x: 8, y: 8, width: CGFloat(W) - 16, height: CGFloat(H) - 16), path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
            ctx.addPath(path); ctx.setFillColor(CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 0.10)); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(CGColor(srgbRed: 0.02, green: 0.04, blue: 0.08, alpha: 0.7)); ctx.setLineWidth(12); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 1)); ctx.setLineWidth(6); ctx.strokePath()
        }
        ctx.textPosition = CGPoint(x: pad - bounds.minX, y: (CGFloat(H) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line(true), ctx)
        ctx.textPosition = CGPoint(x: pad - bounds.minX, y: (CGFloat(H) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(fill, ctx)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: W, height: H, mipmapped: false); d.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: px, bytesPerRow: W * 4)   // 記憶の 1 行目が絵の上（そのまま送る）
        labelTex[key] = tex
        return tex
    }
    /// 描いた絵 src を、鏡を広げながら dst へ
    func mirrorPass(_ cb: MTLCommandBuffer, _ src: MTLTexture, _ dst: MTLTexture) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let f = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        // y：周辺減光とコントラスト（ダイブで寄るほど。黒をより黒く・端を暗く）、z：横÷縦
        var k = SIMD4<Float>(Float(diveMirror), Float(Self.diveEase(dvT).1), Float(src.width) / Float(max(1, src.height)), 1)
        f.setRenderPipelineState(mirPipe); f.setFragmentTexture(src, index: 0); f.setFragmentBytes(&k, length: 16, index: 0)
        f.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); f.endEncoding()
    }
    /// 札を 1 枚：c を真ん中に、いつも画面に向く板で（大きさは画面の上でだいたい同じに。k で倍率）
    func drawLabel(_ e: MTLRenderCommandEncoder, _ s: String, _ col: SIMD3<Float>, _ c: SIMD3<Double>, k: Double = 1, math: Bool = true, serif: Bool = false) {
        guard let tex = labelTexture(s, col, math: math, serif: serif) else { return }
        let (eye, Rv, Uv, _) = camBasis()
        let dist = simd_length(eye - c), hgt = 0.075 * dist / 5.5 * 2.6 * k, wid = hgt * Double(tex.width) / Double(tex.height)
        let rx = Rv * (wid / 2 * mirrorX), uy = Uv * (hgt / 2)
        func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
        var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
        e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    func tickGlint(_ eye: SIMD3<Double>, _ Rv: SIMD3<Double>, _ Uv: SIMD3<Double>, _ key: SIMD3<Double>) -> Float {
        let now = nowT, dt = max(0, min(0.1, now - glintLast)); glintLast = now
        if abs(now - glintT) >= 0.1 { glintT = now; glintNow = glintMeasure(eye, Rv, Uv, key) }
        // 反射カット：強いと判断したら、まず 1 秒あまりテカーッと見せてから、さっと切る。その向きにいる間も 7〜12 秒に 1 回テカーッと光らせる。
        //   十分弱くなったと判断したら戻す。切る値と戻す値を離して、行き来してちらつかないように
        if glintNow >= Self.glintHi {
            if !glintCut { glintCut = true; glintFlashT = now - 0.2; glintNext = now + Double.random(in: 7...12) }   // 入った時は、もう光っているので、光り始めから
        } else if glintNow < Self.glintLo { glintCut = false }
        if glintCut && now >= glintNext { glintFlashT = now; glintNext = now + Double.random(in: 7...12) }
        let fa = now - glintFlashT                                        // テカーッ：0.2 秒で明るく、0.7 秒そのまま、0.4 秒で消える
        let flash = fa < 0 ? 0 : Float(smoothstep(0, 0.2, fa) * (1 - smoothstep(0.9, 1.3, fa)))
        let target: Float = glintCut ? max(0.02, flash) : 1               // ふだんは、殻が何十枚も重なって足されるので、ぐっと下げる（ほんのり残す）
        glintK += (target - glintK) * Float(1 - exp(-dt * (glintCut ? 14 : 2.2)))
        return glintK
    }
    func glintMeasure(_ eye: SIMD3<Double>, _ Rv: SIMD3<Double>, _ Uv: SIMD3<Double>, _ key: SIMD3<Double>) -> Double {
        let N = 6, shells = 7, rad = Self.R * Self.SCALE * 1.15
        var grid = [Double](repeating: 0, count: N * N)
        func pt(_ th: Double, _ ph: Double, _ la: Double) -> SIMD4<Double> {
            let st0 = sin(th), sp = sin(ph)
            return SIMD4(st0 * sp * cos(la), st0 * sp * sin(la), st0 * cos(ph), cos(th))
        }
        for t in 0..<shells {
            let th = 0.35 + (Double.pi - 0.7) * Double(t) / Double(shells - 1)
            for i in 1..<9 { let ph = Double.pi * Double(i) / 9
                for j in 0..<16 {
                    let la = 2 * Double.pi * Double(j) / 16, e = 0.02
                    let P = walkPlace(pt(th, ph, la)).0, A = walkPlace(pt(th, ph + e, la)).0, B = walkPlace(pt(th, ph, la + e)).0
                    var n = simd_cross(A - P, B - P); let nl = simd_length(n); if nl < 1e-12 { continue }; n /= nl
                    let v = simd_normalize(eye - P); if simd_dot(n, v) < 0 { n = -n }
                    func spec(_ l: SIMD3<Double>) -> Double { pow(max(0, simd_dot(n, simd_normalize(v + l))), 60) * max(0, simd_dot(n, l)) }
                    let sp = (spec(key) * 0.35 + spec(Self.glintL1)) * sin(ph)    // カメラについて回る光と、固定の光（シェーダーの L1）。極の近くは点が密なので、面積に合わせて減らす
                    let fx = (simd_dot(P, Rv) / rad * 0.5 + 0.5) * Double(N), fy = (simd_dot(P, Uv) / rad * 0.5 + 0.5) * Double(N)
                    if !fx.isFinite || !fy.isFinite || abs(fx) > 1e6 || abs(fy) > 1e6 { continue }   // 遠近で画面のはるか外へ飛んだ点は数えない
                    let gx = Int(fx), gy = Int(fy)
                    if gx >= 0 && gx < N && gy >= 0 && gy < N { grid[gy * N + gx] += sp }
                }
            }
        }
        let m = (grid.max() ?? 0) * Double(max(1, st.layers)) / Double(shells)
        if Self.glintLog && overview { print(String(format: "反射 %.1f 秒 %.2f 効き %.2f", nowT, m, glintK)) }
        return m
    }
    /// 極の色：軸の色の球層の時は、その極が乗る軸の色（アナ・カタ＝w 紫、東西＝x 赤、北南＝y 緑、天地＝z 青）。ほかは地図と同じ色
    func poleColor(_ k: Int) -> SIMD3<Float> {
        guard st.shellModeNow == 2 else { return MapRenderer.poleDotCol(k) }
        return Self.axisCol[[3, 3, 0, 0, 1, 1, 2, 2][k]]
    }
    /// 球面さんぽの目印（チェックポイント）：まだ通っていない目印は目印の色の輪、通った目印は塗りつぶしの丸と ✓。番号は地図と同じ（置いた順）
    func drawMarks(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.marksOn || st.polesMode > 0, let src = wsrc else { return }
        let wk = src()
        let poles = (0..<FIXED.count).filter { st.polesMode == 2 || (st.polesMode == 1 && wk.poles.contains($0)) }
        guard (st.marksOn && !wk.marks.isEmpty) || !poles.isEmpty else { return }
        let (eye, _, Uv, _) = camBasis()
        var tri: [HLVert] = []
        func disc(_ c: SIMD3<Double>, _ r00: Double, _ r10: Double, _ col: SIMD4<Float>) {
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), r0 = r00 * sc, r1 = r10 * sc   // カメラに近いと縮める（ダイブ）
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            for k in 0..<28 {
                let a0 = Double(k) / 28 * 2 * .pi, a1 = Double(k + 1) / 28 * 2 * .pi
                let d0: SIMD3<Double> = ax * cos(a0) + ay * sin(a0), d1: SIMD3<Double> = ax * cos(a1) + ay * sin(a1)
                let ps: [SIMD3<Double>] = [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d0 * r0, c + d1 * r1, c + d1 * r0]
                for q in ps { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        var tags: [(String, SIMD3<Float>, SIMD3<Double>, Bool, Bool)] = []   // 名前・色・場所・英語（セリフ体）・極
        // 光で描く時：画面に向く板 1 枚に、cmf が色の光・十字のきらめき（通った）／光の輪（まだ）を描く
        var ctri: [HLCometVert] = []
        let now = ProcessInfo.processInfo.systemUptime
        /// 当たった瞬間の光の強さ（1 → 0、約 0.9 秒）。極は番号、目印は場所で探す（周回でチェックが消えても光る）
        func flashOf(pole k: Int) -> Float {
            guard let h = Journey.hitPulse.last(where: { $0.pole == k }) else { return 0 }
            let f = max(0, 1 - (now - h.t) / 0.9); return Float(f * f)
        }
        func flashOf(mark m: SIMD4<Double>) -> Float {
            guard let h = Journey.hitPulse.last(where: { $0.pole < 0 && simd_distance($0.p, m) < 1e-9 }) else { return 0 }
            let f = max(0, 1 - (now - h.t) / 0.9); return Float(f * f)
        }
        /// ピカッ：大きな板に、弾ける光と広がる輪
        func flash(_ c: SIMD3<Double>, _ col: SIMD3<Float>, _ fl: Float, _ big: Double) {
            guard fl > 0.001 else { return }
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), hs = big * sc * 2.6
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            func v(_ x: Double, _ y: Double) -> HLCometVert {
                HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), 6, fl), c: SIMD4(col, 1))
            }
            ctri += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        func glow(_ c: SIMD3<Double>, _ col: SIMD3<Float>, _ hit: Bool, _ vis: Float, _ big: Double) {
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), hs = big * sc
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            func v(_ x: Double, _ y: Double) -> HLCometVert {
                HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), hit ? 4 : 5, vis), c: SIMD4(col, 1))
            }
            ctri += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        // 8 つの極（さんぽの地図と同じ色・名前）：通った極は塗りつぶしと ✓、まだの極（いつも出す時）は輪
        let wt = MapRenderer.worldTag(st.worldR), rTag = wt.isEmpty ? "" : " " + wt   // R の世界の極：その S³ の上に描き、札に R0.2 などを添える（アナ極 +w R0.2）
        for k in poles {
            let (c, f) = wPlace(FIXED[k].c), col = poleColor(k), vis = Float(0.5 + 0.5 * f), hit = wk.poles.contains(k)
            let fl = flashOf(pole: k)
            flash(c, col, fl, 0.3)                                         // 当たった瞬間：ピカッ
            if ovMotion && st.ovView == 3 && k < 2 {                       // W 消失地図の真ん中：光は足さず、紫の点の上に赤の点を、そのままの場所に（2 つは同じ点に重なる）
                if k == 0 { disc(c, 0, 0.07, SIMD4(poleColor(1), 1)); disc(c, 0, 0.04, SIMD4(poleColor(0), 1)) }
                let pn = (st.poleEN ? MapRenderer.poleNameEN(FIXED[k]) : MapRenderer.poleName(FIXED[k])) + " " + MapRenderer.poleAxis(FIXED[k]) + rTag
                tags.append((hit ? "✓" + pn : pn, col, c + Uv * (k == 0 ? 0.2 : -0.2), st.poleEN, true))
                continue
            }
            if overview && k < 2 { disc(c, 0, 0.1, SIMD4(col, 0.45 * vis)); disc(c, 0, 0.055, SIMD4(col, vis)) }   // 地図の赤玉・紫玉：玉のまわりの殻（だいだい・黄色）に色が負けないよう、光の下に玉の色の丸を敷く
            if !overview && k < 2 { disc(c, 0, 0.16, SIMD4(col, 0.25 * vis)); disc(c, 0, 0.08, SIMD4(col, 0.6 * vis)) }   // ダイブ画面の赤星・紫星：光のにじみで、遠くでも見える
            if st.symGlow { glow(c, col, hit, vis, 0.3 * Double(1 + 0.8 * fl)) }   // 光る星（極の色がほんのり。光っている間は少し大きく）
            else if hit { disc(c, 0, 0.11, SIMD4(col, 0.25 * vis)); disc(c, 0, 0.06, SIMD4(col, vis)); disc(c, 0.06, 0.072, SIMD4(1, 1, 1, 0.9 * vis)) }
            else { disc(c, 0, 0.06, SIMD4(col, 0.14 * vis)); disc(c, 0.045, 0.062, SIMD4(col, 0.9 * vis)) }
            let pn = (st.poleEN ? MapRenderer.poleNameEN(FIXED[k]) : MapRenderer.poleName(FIXED[k])) + " " + MapRenderer.poleAxis(FIXED[k]) + rTag
            tags.append((hit ? "✓" + pn : pn, col, c + Uv * 0.15, st.poleEN, true))   // 名前は極の色、✓ だけ蛍光（labelTexture）
        }
        for (i, m) in wk.marks.enumerated() where st.marksOn {
            let (c, f) = wPlace(m), col = Journey.markColor(i), vis = Float(0.5 + 0.5 * f)
            let hit = i < wk.hit.count && wk.hit[i]
            let fl = flashOf(mark: m)
            flash(c, SIMD3(1, 1, 1), fl, 0.27)                                // 目印は白く光る
            if st.symGlow { glow(c, col, hit, vis, 0.27 * Double(1 + 0.8 * fl)) }
            else if hit {
                disc(c, 0, 0.12, SIMD4(col, 0.28 * vis))                       // にじみ
                disc(c, 0, 0.068, SIMD4(col, vis))                             // 塗りつぶし
                disc(c, 0.068, 0.082, SIMD4(1, 1, 1, 0.9 * vis))               // 白いふち
            } else {
                disc(c, 0, 0.07, SIMD4(col, 0.16 * vis))                       // うすい中
                disc(c, 0.055, 0.075, SIMD4(col, 0.95 * vis))                  // 輪
            }
            tags.append((hit ? "✓\(i + 1)" : "\(i + 1)", col, c + Uv * 0.15, false, false))   // 番号は目印の色、✓ だけ蛍光
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        if !tri.isEmpty {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
            tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        }
        if !ctri.isEmpty {                                              // 光の極・目印（足し合わせ）
            e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
            ctri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
            var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ctri.count)
        }
        e.setRenderPipelineState(lbPipe); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        let lk = side == .right && dvT > 0 ? 0.5 : 0.7                // 寄っている間も名前を（小さく）。目印の番号はこの大きさ
        for (s, col, c, en, pole) in tags { drawLabel(e, s, col, c, k: pole ? lk * 0.78 : lk, math: false, serif: en) }   // 極の名前は小さく（英語はセリフ体）
    }
    /// 軸の名前の札：矢印の先の少し外に、いつも画面に向く板で。左の z は右の w に当たるので「z(w)」（紫）
    func drawAxisLabels(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let (eye, Rv, Uv, _) = camBasis(), lr = leftRot()
        var items: [(String, SIMD3<Float>, SIMD3<Double>)] = []
        if side == .left { for k in 0..<3 { var d = SIMD3<Double>(0, 0, 0); d[k] = Self.AXL + 0.2; items.append((k == 2 ? "z(w)" : Self.axisName[k], Self.axisCol[k == 2 ? 3 : k], lr * d)) } }
        else { for k in 0..<4 { let tip = axis4(k, 1), dir = simd_normalize(tip + SIMD3(1e-9, 0, 0)); items.append((Self.axisName[k], Self.axisCol[k], tip + dir * 0.2)) } }
        var u = u0; u.model = matrix_identity_float4x4
        e.setRenderPipelineState(lbPipe); e.setDepthStencilState(depthAlways)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        for (s, col, c0) in items {
            guard let tex = labelTexture(s, col) else { continue }
            var c = c0
            let dist = simd_length(eye - c), hgt = 0.075 * dist / 5.5 * 2.6 * (overview ? 0.72 : 1), wid = hgt * Double(tex.width) / Double(tex.height)   // 画面の上でだいたい同じ大きさに（地図は小さめ）
            let rx = Rv * (wid / 2 * mirrorX), uy = Uv * (hgt / 2)
            // 文字が画面の外へ切れないよう、内側へ寄せる（地図の左上の見出しにも重ねない）
            if overview || dvT <= 0 {
                func ndc(_ p: SIMD3<Double>) -> SIMD2<Double>? { let q = u0.mvp * SIMD4<Float>(SIMD3<Float>(p), 1); return q.w > 1e-4 ? SIMD2(Double(q.x / q.w), Double(q.y / q.w)) : nil }
                if let n0 = ndc(c), let nr = ndc(c + rx), let nu = ndc(c + uy) {
                    let sx = nr.x - n0.x, sy = nu.y - n0.y, mx = 1 - abs(sx) * 1.2, my = 1 - abs(sy) * 1.2
                    let nx = max(-mx, min(mx, n0.x)); var ny = max(-my, min(my, n0.y))
                    if overview && nx < -0.66 && ny > 0.7 { ny = 0.7 }
                    if abs(sx) > 1e-9 { c += rx * ((nx - n0.x) / sx) }
                    if abs(sy) > 1e-9 { c += uy * ((ny - n0.y) / sy) }
                }
            }
            func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
            var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
            e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    /// 平面で切る：平面の向きと位置を定数へ（左右とも。くさびは右だけ、別に）。画面に固定は手前・右・上、物体に固定は x・y・z（左は球と一緒に傾く）
    func planeCut(_ u: inout HLUni) {
        if overview && ovWedgeK > 0.005 && ovWedgeK >= ovCutK {           // 見せ場：地球の断面図のように、YZ の面ともう 1 枚の面で、カメラの側を 90° 開く
            let cb0 = camBasis(), (c, t) = st.ovView == 3 ? (cb0.3, cb0.1) : ovWedgeAxes(), h = Double.pi / 4 * ovWedgeK     // 閉じた所から、c を中心に開いていく（W はカメラの正面を開く）
            let n1: SIMD3<Double> = c * sin(h) - t * cos(h), n2: SIMD3<Double> = c * sin(h) + t * cos(h)
            u.cut = SIMD4(4, Float(n2.x), Float(n2.y), Float(n2.z)); u.cutN = SIMD4(SIMD3<Float>(n1), 0)
            return
        }
        if overview && ovCutK > 0.001 {                                   // 地図の断面のカット：手前の半分を、カメラに向いた平面で切る
            let rad = Self.R * Self.SCALE * 1.15, cb0 = camBasis(), a = nowT * 0.45, sw = 0.75 * ovSpinK         // 回る断面：切る面がカメラの正面のまわりをゆっくり回る
            let cn: SIMD3<Double> = cb0.3 * cos(sw) + (cb0.1 * cos(a) + cb0.2 * sin(a)) * sin(sw)
            u.cut = SIMD4(3, 0, 0, 0); u.cutN = SIMD4(SIMD3<Float>(simd_normalize(cn)), Float((1 - ovCutK) * rad))
            return
        }
        guard st.cutOn && st.cutKind == 1 else { return }
        let (_, Rv, Uv, Bv) = camBasis()
        var n: SIMD3<Double>
        switch st.planeDir {
        case 0: n = Bv
        case 1: n = Rv
        case 2: n = Uv
        default: var a = SIMD3<Double>(0, 0, 0); a[st.planeDir - 3] = 1; n = side == .left ? leftRot() * a : a
        }
        let rad = side == .left ? Self.R * 1.05 : Self.R * Self.SCALE * 1.08
        u.cut = SIMD4(3, 0, 0, 0); u.cutN = SIMD4(SIMD3<Float>(simd_normalize(n)), Float(st.cutPos * rad))
    }
    /// 線を、カメラに向いた細い帯に（光は当てない）
    static func ribbon(_ pts: [SIMD3<Double>], _ col: SIMD4<Float>, w: Double, eye: SIMD3<Double>) -> [HLVert] {
        guard pts.count >= 2 else { return [] }
        var out: [HLVert] = []; out.reserveCapacity(pts.count * 6)
        func v(_ p: SIMD3<Double>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: col) }
        var prev: (SIMD3<Double>, SIMD3<Double>)?
        for i in 0..<pts.count {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)], p = pts[i]
            var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * w
            if let (pl, pr) = prev { out += [v(pl), v(pr), v(p + sd), v(pl), v(p + sd), v(p - sd)] }
            prev = (p - sd, p + sd)
        }
        return out
    }
    /// 4D で切る（右）：見る人に固定の超平面 w′ ＝ c（c ＝ cutPos × R）と超球の切り口。切り口は半径 √(R² − c²) の球（2 次元球面）で、
    ///   各層の殻（w ＝ 一定の球）はその中の円になる（左の「輪 ∩ 平面 ＝ 2 点」のアナロジー）。切り口の 3D をそのまま（遠近なし、ウェブ版と同じ）
    func drawSlice4(_ e: MTLRenderCommandEncoder, _ u0: HLUni, _ m: simd_double4x4) {
        let R = Self.R, c = st.cutPos * R, (eye, Rv, Uv, _) = camBasis(), ax = st.cut4Axis
        // 超平面 v[ax] ＝ c（v ＝ 回した後の 4D の点）。殻の点 p ＝ (u, w) では v[ax] ＝ a·u ＋ b·w
        let a = SIMD3(m.columns.0[ax], m.columns.1[ax], m.columns.2[ax]), b = m.columns.3[ax], la = simd_length(a)
        // 切り口の 3D：残りの 3 つの軸。切った軸の所に w を置く（x′ で切ると w は横、y′ は縦、z′ は手前＝左の「z(w)」と同じ）
        func disp(_ p: SIMD4<Double>) -> SIMD3<Double> { let v = m * p; var q = SIMD3(v.x, v.y, v.z); if ax < 3 { q[ax] = v.w }; return q * Self.SCALE }
        var tri: [HLVert] = []
        for (r, w, col) in layerList() {
            let cc = SIMD4(simd_min(col * 1.3, SIMD3(repeating: 1)), 1)
            if la < 1e-6 {                                             // 超平面が殻と平行（回していない時）：w ＝ c の殻がまるごと切り口
                guard abs(b * w - c) < 0.03 else { continue }
                for k in 1..<6 { let th = Double(k) / 6 * .pi
                    tri += Self.ribbon((0...72).map { j in let f = Double(j) / 72 * 2 * .pi; return disp(SIMD4(-r * sin(th) * cos(f), r * cos(th), r * sin(th) * sin(f), w)) }, cc, w: 0.006, eye: eye) }
                for k in 0..<6 { let f = Double(k) / 6 * .pi
                    tri += Self.ribbon((0...72).map { j in let th = Double(j) / 72 * 2 * .pi; return disp(SIMD4(-r * sin(th) * cos(f), r * cos(th), r * sin(th) * sin(f), w)) }, cc, w: 0.006, eye: eye) }
                continue
            }
            let ah = a / la, d = (c - b * w) / la
            guard abs(d) < r else { continue }                         // この殻は超平面と交わらない
            let rho = (r * r - d * d).squareRoot(), u0 = ah * d
            let e1 = simd_normalize(simd_cross(ah, abs(ah.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0))), e2 = simd_cross(ah, e1)
            let pts = (0...120).map { j -> SIMD3<Double> in let f = Double(j) / 120 * 2 * .pi; let q = u0 + (e1 * cos(f) + e2 * sin(f)) * rho; return disp(SIMD4(q, w)) }
            tri += Self.ribbon(pts, cc, w: 0.009, eye: eye)
        }
        // 切り口の球のふち（見る向きから見た輪郭）
        let rs = (max(0, R * R - c * c)).squareRoot() * Self.SCALE
        tri += Self.ribbon((0...120).map { j in let f = Double(j) / 120 * 2 * .pi; return (Rv * cos(f) + Uv * sin(f)) * rs }, SIMD4(0.85, 0.9, 1.0, 0.4), w: 0.006, eye: eye)
        guard !tri.isEmpty else { return }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthWrite)
        tri.withUnsafeBytes { bb in if let buf = device.makeBuffer(bytes: bb.baseAddress!, length: bb.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 4D で切る（左）：アナロジー。見る人に固定の平面（右の切る向きに当たる軸 ＝ c）の円盤と、輪（円）がそれを貫く点（2 点ずつ）。
    ///   右の「殻（球）∩ 超平面 ＝ 円」に当たるのが、左の「輪（円）∩ 平面 ＝ 2 点」
    func drawSlicePlane2(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let R = Self.R, c = st.cutPos * R, lr = leftRot(), (eye, Rv, Uv, _) = camBasis()
        let rs = (max(0, R * R - c * c)).squareRoot()
        var tri: [HLVert] = []
        // 右で切る向きに当たる左の平面：x′ → x ＝ c、y′ → y ＝ c、w′ → z ＝ c（左の z は右の w）。z′ は左の球に当たる軸がないので出さない
        guard st.cut4Axis != 2 else { return }
        var nv = SIMD3<Double>(0, 0, 0); nv[st.cut4Axis == 3 ? 2 : st.cut4Axis] = 1
        let ctr = nv * c, e1 = simd_normalize(simd_cross(nv, abs(nv.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0))), e2 = simd_cross(nv, e1)
        // 円盤（うすい面）とふち
        for k in 0..<64 {
            let f0 = Double(k) / 64 * 2 * .pi, f1 = Double(k + 1) / 64 * 2 * .pi
            let q0: SIMD3<Double> = ctr + (e1 * cos(f0) + e2 * sin(f0)) * rs, q1: SIMD3<Double> = ctr + (e1 * cos(f1) + e2 * sin(f1)) * rs
            for q in [ctr, q0, q1] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: SIMD4(0.75, 0.85, 1.0, 0.10))) }
        }
        tri += Self.ribbon((0...96).map { j in let f = Double(j) / 96 * 2 * .pi; let d: SIMD3<Double> = e1 * cos(f) + e2 * sin(f); return ctr + d * rs }, SIMD4(0.85, 0.9, 1.0, 0.55), w: 0.006, eye: eye)
        // 輪が平面を貫く点：輪 (ρ cos u, ρ sin u, h) を傾けた点の nv の成分が c になる u（2 つ）
        let r2 = lr.transpose * nv
        func dot(_ p: SIMD3<Double>, _ col: SIMD3<Float>) {
            let rings: [(Double, SIMD4<Float>)] = [(0.07, SIMD4<Float>(col, 0.35)), (0.042, SIMD4<Float>(col, 1)), (0.018, SIMD4<Float>(1, 1, 1, 1))]
            func rim(_ f: Double, _ rad: Double) -> SIMD3<Double> { let d: SIMD3<Double> = Rv * cos(f) + Uv * sin(f); return p + d * rad }
            for (rad, cc) in rings {
                for k in 0..<20 {
                    let f0 = Double(k) / 20 * 2 * .pi, f1 = Double(k + 1) / 20 * 2 * .pi
                    for q in [p, rim(f0, rad), rim(f1, rad)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: cc)) }
                }
            }
        }
        for (rho, h, col) in leftRings {
            let A = r2.x * rho, B = r2.y * rho, C = c - r2.z * h, M = (A * A + B * B).squareRoot()
            guard M > 1e-9, abs(C) <= M else { continue }
            let base = atan2(B, A), dl = acos(max(-1, min(1, C / M)))
            for uu in [base + dl, base - dl] { dot(lr * SIMD3(rho * cos(uu), rho * sin(uu), h), col) }
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
        tri.withUnsafeBytes { bb in if let buf = device.makeBuffer(bytes: bb.baseAddress!, length: bb.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 宇宙の背景の絵：画面の大きさ（左は 2 倍で描くので、その半分）で 1 度だけ作る
    func spaceBackground(_ sz: CGSize) -> MTLTexture? {
        let sc = side == .left ? 2.0 : 1.0, w = max(1, Int(Double(sz.width) / sc)), h = max(1, Int(Double(sz.height) / sc))
        if let t = bgTex, t.width == w, t.height == h { return t }
        if let t = bgTex2, t.width == w, t.height == h { return t }        // 動画を書き出している間は、画面の大きさと 16:9 の 2 つを覚えておく
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        guard let tex = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return nil }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        var k = SIMD4<Float>(Float(Double(w) / Double(h)), 0, 0, 0)
        e.setRenderPipelineState(bgMakePipe); e.setFragmentBytes(&k, length: 16, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        cb.commit()                                                     // この後で積む絵より先に GPU で描かれる（同じ列）
        bgTex2 = bgTex; bgTex = tex
        return tex
    }
    /// 宇宙モードの星（球面さんぽと同じ 12000 個）。星の数で間引く。右は超球の上、左は影（球の中）
    func drawStars(_ e: MTLRenderCommandEncoder, _ u: HLUni, _ h: HLRight, slice: Bool = false) {
        let z = side == .right && dvT > 0 ? Float(Self.diveEase(dvT).1) : 0   // ダイブで寄った割合
        guard st.spaceNow || z > 0.02, let b = starBuf else { return }
        let all = Renderer.starList.count, step = st.spaceNow ? max(1, Int((100 / max(5, st.starsPct)).rounded())) : 1
        var uu = u, hh = h, k = SIMD4<Float>(side == .right ? 0.02 : 0.015, side == .right ? 0 : 1, Float(step), (side == .right ? 0.9 : 0.42) * (st.spaceNow ? 1 : 0.6 * z))   // 左は球の中に詰まるので小さく淡く
        // またたき・十字の光：寄るほど強く（宇宙モードで外から見ている時も、ほんの少し）
        var tz = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), st.spaceNow ? 0.15 : 0, z, Float(st.starDepth) * (1 - z))   // またたきはほんの少し。z：寄った時の遠近、w：引きの遠近
        // 4 方向レインボー：網目がにぎやかなので、星屑を強めに（大きく・明るく・よくまたたく）。網目に負けずに星の海が見えるように
        //   星は遠近つき（近いほど大きくくっきり、遠いほど小さく淡く。hh.e.z）で、空間の奥行きがわかるように
        if (st.shellModeNow == 1 || st.shellModeNow == 2) && !slice { k.w *= 1.8 + 0.8 * z; tz.y = max(tz.y, 0.1) * 2.2; hh.e.z = 1 }   // ダイブで寄るほど、さらに明るく
        else if !slice && z > 0.02 { k.w *= 1 + 1.4 * z; tz.y = max(tz.y, 0.1) * 1.6; hh.e.z = Float(smoothstep(0.2, 0.8, Double(z))) }   // ふつうのレインボーも、ダイブでは星屑を遠近つきの小さな点で多めに（牡丹雪にはしない）
        e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
        uu.cut = .zero
        if slice { k.y = 2; k.w = 2.2; k.z = 1 }                       // 4D の切り口：そばの星だけ（間引かず、明るく）
        e.setRenderPipelineState(starPipe); e.setDepthStencilState(depthRead)
        e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&uu, length: MemoryLayout<HLUni>.stride, index: 1)
        e.setVertexBytes(&hh, length: MemoryLayout<HLRight>.stride, index: 2); e.setVertexBytes(&k, length: 16, index: 3)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: slice ? all : all / step)
    }
    func drawLightWrap(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.lightWrap, side == .right, !overview, !diveWipe, dvT == 0, st.walk, let src = wsrc else { return }
        let p = src().pos, poleD: Double = acos(min(1, abs(p.w))), kk: Double = 1 - smoothstep(0.55, 1.05, poleD), k = Float(kk)   // 近い方の極までの角度で、だんだん出す
        guard k > 0.01 else { return }
        let (eye, _, _, _) = camBasis(), T = nowT / 2.8
        let far = p.w > 0 ? SIMD3<Float>(0.72, 0.32, 1) : SIMD3<Float>(1, 0.22, 0.16)   // 反対側の極の色（アナ極の近くなら紫、カタ極の近くなら赤）
        var v: [HLCometVert] = []; v.reserveCapacity(18 * 80 * 6)
        func vert(_ a: SIMD3<Double>, _ q: SIMD4<Float>, _ c: SIMD4<Float>) -> HLCometVert { let f = SIMD3<Float>(a); return HLCometVert(p: SIMD4<Float>(f.x, f.y, f.z, 1), q: q, c: c) }
        func put(_ a: [SIMD3<Double>], _ q: [SIMD4<Float>], _ c: SIMD4<Float>) { for i in [0, 1, 2, 0, 2, 3] { v.append(vert(a[i], q[i], c)) } }
        func bead(_ c: SIMD3<Double>, _ r: Double, _ col: SIMD3<Float>, _ a: Float) {
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax: SIMD3<Double> = simd_normalize(simd_cross(up0, fw)) * (r * 1.5), ay: SIMD3<Double> = simd_normalize(simd_cross(fw, ax)) * (r * 1.5), s: Float = 1.5
            let c0: SIMD3<Double> = c - ax - ay, c1: SIMD3<Double> = c + ax - ay, c2: SIMD3<Double> = c + ax + ay, c3: SIMD3<Double> = c - ax + ay
            let q0 = SIMD4<Float>(-s, -s, 15, 1), q1 = SIMD4<Float>(s, -s, 15, 1), q2 = SIMD4<Float>(s, s, 15, 1), q3 = SIMD4<Float>(-s, s, 15, 1)
            let cc: SIMD3<Float> = col * a
            put([c0, c1, c2, c3], [q0, q1, q2, q3], SIMD4<Float>(cc.x, cc.y, cc.z, a))
        }
        let M = 72
        for (n, dd) in Self.wrapDirs.enumerated() {
            var d = SIMD4<Double>(dd.x, dd.y, dd.z, 0); d -= p * simd_dot(d, p)
            let dl = simd_length(d); guard dl > 1e-6 else { continue }
            d /= dl
            func at(_ t: Double) -> (SIMD3<Double>, Double) { wPlace(p * cos(t) + d * sin(t)) }
            let phase = [0.0, 0.5].map { (T + $0 + Double(n) * 0.013).truncatingRemainder(dividingBy: 1) }
            let front = phase.map { Double.pi * (1 - $0) }                // 反対側（π）から自分（0）へ
            func light(_ t: Double) -> Float {
                var best = 0.0
                for f0 in front { let x = (t - f0) / 0.32; best = max(best, exp(-x * x)) }
                return Float(best)
            }
            var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
            for i in 0...M {
                let t = Double.pi * Double(i) / Double(M), (c, face) = at(t), a0 = at(max(0, t - 0.03)).0, b0 = at(min(.pi, t + 0.03)).0
                var sd: SIMD3<Double> = simd_cross(b0 - a0, eye - c)
                let l = simd_length(sd), wid: Double = 0.0065 * max(0.5, min(1, simd_length(eye - c) / 7.5))
                sd = l < 1e-12 ? SIMD3<Double>() : sd / l * wid
                let m = Float(t / .pi), base: SIMD3<Float> = simd_mix(SIMD3<Float>(0.75, 0.9, 1), far, SIMD3<Float>(repeating: m))
                let fk = Float(0.45 + 0.55 * face), st0d: Double = smoothstep(0, 0.1, t), st0 = Float(st0d)
                let lum: Float = (0.2 + 1.3 * light(t)) * k * fk * st0
                let bc: SIMD3<Float> = base * lum
                let col = SIMD4<Float>(bc.x, bc.y, bc.z, lum), lo: SIMD3<Double> = c - sd, hi: SIMD3<Double> = c + sd, kq = SIMD4<Float>(1, 0, 17, 1)
                if let (pl, pr, pc) = prev {
                    v.append(vert(pl, kq, pc)); v.append(vert(pr, kq, pc)); v.append(vert(hi, kq, col))
                    v.append(vert(pl, kq, pc)); v.append(vert(hi, kq, col)); v.append(vert(lo, kq, col))
                }
                prev = (lo, hi, col)
            }
            for t in front where t > 0.04 {
                let (c, face) = at(t), mixK = SIMD3<Float>(repeating: Float(t / .pi) * 0.8), bc: SIMD3<Float> = simd_mix(SIMD3<Float>(1, 1, 1), far, mixK)
                bead(c, 0.032, bc, k * Float(0.5 + 0.5 * face))
            }
        }
        bead(wPlace(-p).0, 0.075, far, k)                              // 自分の反対側の点：全部の線がここに集まる
        guard !v.isEmpty else { return }
        var u = u0
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
        v.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
    }
    /// レンズフレア：天の川（さんぽと同じ y・z の大きな円）が画面に入ると、帯の上で画面の真ん中にいちばん近い所を光の元にして、
    ///   そこに光のにじみ、画面の真ん中をはさんだ反対側へ光の輪（色つき）が並び、横に光の筋。真ん中に近いほど強く、端から出ると消える。
    ///   ダイブの景色の時だけ（外から眺める時は出さない）。光の輪は、画面の手前の板（カメラの前）に置いて描く
    func drawFlare(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let dz = side == .right ? Self.diveEase(dvT).1 : 0
        var best = 0.0, nx = 0.0, ny = 0.0
        for i in 0..<96 {
            let th = Double(i) / 96 * 2 * .pi, (q, face) = walkPlace(SIMD4(0, cos(th), sin(th), 0))
            let clip = u0.mvp * SIMD4<Float>(SIMD3<Float>(q), 1)
            guard clip.w > 1e-4 else { continue }
            let x = Double(clip.x / clip.w), y = Double(clip.y / clip.w), edge = max(abs(x), abs(y)), r0 = (x * x + y * y).squareRoot()
            let sc = (1 - smoothstep(0.85, 1.25, edge)) * (0.35 + 0.65 * (1 - smoothstep(0, 1.1, r0))) * (face + (1 - face) * dz)
            if sc > best { best = sc; nx = x; ny = y }
        }
        let vis = best * smoothstep(0.3, 0.9, dz)                         // ダイブの景色の時だけ（外から超球を見ている時は出さない）
        guard vis > 0.01 else { return }
        let (eye, Rv, Uv, Bv) = camBasis(), D = 0.5, ty = tan(lastFov * .pi / 360), tx = ty * lastAsp
        func at(_ x: Double, _ y: Double) -> SIMD3<Double> { eye - Bv * D + Rv * (x * tx * D) + Uv * (y * ty * D) }
        var vs: [HLCometVert] = []
        // (位置：中心から見て source の何倍か、大きさ（画面の縦の割合）、色、強さ、種類 8 光の輪・9 横の筋)
        let parts: [(Double, Double, SIMD3<Float>, Float, Float)] = [
            (1.0, 0.16, SIMD3(1.0, 0.92, 0.8), 0.55, 8), (1.0, 0.9, SIMD3(0.75, 0.85, 1.0), 0.32, 9),
            (0.55, 0.05, SIMD3(0.6, 0.5, 1.0), 0.22, 8), (0.25, 0.09, SIMD3(0.4, 1.0, 0.8), 0.14, 8),
            (-0.2, 0.035, SIMD3(1.0, 0.8, 0.4), 0.25, 8), (-0.45, 0.12, SIMD3(0.5, 0.7, 1.0), 0.12, 8),
            (-0.8, 0.06, SIMD3(1.0, 0.5, 0.8), 0.18, 8), (-1.25, 0.2, SIMD3(0.55, 1.0, 0.7), 0.1, 8)]
        for (t, sz, col, a, kind) in parts {
            let cx = nx * t, cy = ny * t, c = at(cx, cy), h = sz * ty * D, w = kind > 8.5 ? h * 1.0 : h, hh = kind > 8.5 ? h * 0.06 : h
            let al = Float(vis) * a * 0.4                                 // うーっすら
            func v(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + Rv * (x * w) + Uv * (y * hh)), 1), q: SIMD4(Float(x), Float(y), kind, al), c: SIMD4(col, 1)) }
            vs += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        var u = u0; u.model = matrix_identity_float4x4
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
        vs.withUnsafeBytes { b in e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vs.count)
    }
    /// 視点：左は正面（+z の 5.5 から、北極が手前）。右は正面から、ドラッグで回した向き
    /// 画面（観察者）の向きを超球の元の座標へ戻して、手前を向いている経度（ウェブ版の viewerPhi。SphereGeometry：x ＝ −cosφ·sinθ、z ＝ sinφ·sinθ）
    /// 断面カットが手前を切っているか：手前を切ると、見えるのは残った殻のお椀の内側（奥の半分）なので、殻を外から順に重ねる
    ///   （ふだんの順のままだと、いちばん外の殻の奥の面が最後に全部の上へ重なって、切る前の丸い球に見える）
    func cutFacesViewer() -> Bool {
        guard st.cutOn else { return false }
        switch st.cutKind {
        case 0:
            if st.cutRef == 0 { return cos(st.cutAngDeg * .pi / 180) > 0 }   // 画面に固定：0° ＝ 手前
            // 物体に固定・ポリゴンカット：切り欠きの真ん中の経度（SphereGeometry：x ＝ −cosφ、z ＝ sinφ）が、今こちらを向いているか
            let ph = st.cutRef == 2 ? st.cutPhi : st.cutAngDeg * .pi / 180, v = xf(SIMD4(-cos(ph), 0, sin(ph), 0))
            return simd_dot(SIMD3(v.x, v.y, v.z), camBasis().3) > 0
        case 1:
            if st.planeDir == 0 { return true }
            guard st.planeDir >= 3 else { return false }
            var a = SIMD3<Double>(0, 0, 0); a[st.planeDir - 3] = 1
            return simd_dot(a, camBasis().3) > 0.5
        default: return false
        }
    }
    func viewerPhi() -> Double {
        let m = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        let (eye, _, _, _) = camBasis(), o = m.transpose * SIMD4(eye, 0)
        if (o.x * o.x + o.z * o.z).squareRoot() < 1e-3 { return st.cutPhi }   // 真上・真下から見ている時は前のまま
        var a = atan2(o.z, -o.x); if a < 0 { a += 2 * .pi }
        return a
    }
    /// ナイフで切る殻：w 一定の殻のうち、画面の上でいちばん大きいもの（中心と半径。S³ の半径を 1 とした 4D）
    func knifeShell() -> (c: SIMD4<Double>, r: Double)? {
        let sh = ranges.filter { simd_length(SIMD3($0.c.x, $0.c.y, $0.c.z)) < 1e-9 }
        func size(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)) -> Double { simd_length(walkPlace(r.e).0 - walkPlace(r.c).0) }
        guard let b = sh.max(by: { size($0) < size($1) }) else { return nil }
        let k = st.rOnly ? st.rOnlyR : 1                                  // この R だけ表示の時は、その S³ の上を切る
        return (b.c * k, simd_length(b.e - b.c) * k)
    }
    /// 殻の上の点（SphereGeometry と同じ並び：θ は y から、φ は経度。x ＝ −sinθ cosφ、z ＝ sinθ sinφ）
    static func knifePoint(_ c: SIMD4<Double>, _ r: Double, _ th: Double, _ ph: Double) -> SIMD4<Double> { c + SIMD4(-sin(th) * cos(ph), cos(th), sin(th) * sin(ph), 0) * r }
    /// ナイフの指している経度：画面の点（左上が 0 の点の座標、sz は画面の大きさ）の下にある、いちばん外の殻の手前の点の経度。殻の外なら nil
    ///   殻の点を画面に写して探すので、4D で回していても正しい（物体に固定の経度）
    func knifePick(_ pt: CGPoint, _ mvp: simd_float4x4, _ sz: CGSize) -> Double? {
        let W = Double(sz.width), H = Double(sz.height)
        guard W > 1, H > 1, let ks = knifeShell() else { return nil }
        let c = ks.c, rr = ks.r
        func scr(_ th: Double, _ ph: Double) -> (d: Double, z: Double)? {
            let q = mvp * SIMD4(SIMD3<Float>(walkPlace(Self.knifePoint(c, rr, th, ph)).0), 1)
            guard q.w > 1e-5 else { return nil }
            let sx = (Double(q.x / q.w) * 0.5 + 0.5) * W, sy = (0.5 - Double(q.y / q.w) * 0.5) * H
            return (hypot(sx - Double(pt.x), sy - Double(pt.y)), Double(q.z / q.w))
        }
        // 粗く：点の近くに写る殻の点のうち、いちばん手前（奥行きが小さい）
        let thr = 0.035 * min(W, H)
        var best: (th: Double, ph: Double, z: Double)? = nil
        for i in 1..<48 {
            let th = Double(i) / 48 * .pi
            for j in 0..<96 {
                let ph = Double(j) / 96 * 2 * .pi
                if let s = scr(th, ph), s.d < thr, s.z < (best?.z ?? .infinity) { best = (th, ph, s.z) }
            }
        }
        guard var b = best else { return nil }
        // 細かく：手前の面の上をたどって、画面の点にいちばん近い所へ（近づかなくなるまで歩く。ふちの近くは画面で縮んで見えるので、遠くまで歩くこともある）
        var bd = scr(b.th, b.ph)?.d ?? .infinity
        for step in [0.04, 0.01, 0.0025, 0.0006] {
            for _ in 0..<60 {
                var moved = false
                for di in -1...1 { for dj in -1...1 where di != 0 || dj != 0 {
                    let th = min(.pi - 1e-3, max(1e-3, b.th + Double(di) * step)), ph = b.ph + Double(dj) * step
                    if let s = scr(th, ph), s.d < bd { bd = s.d; b = (th, ph, s.z); moved = true }
                } }
                if !moved { break }
            }
        }
        let a = b.ph.truncatingRemainder(dividingBy: 2 * .pi)
        return a < 0 ? a + 2 * .pi : a
    }
    /// ナイフモード：指している経度を読み、押している間は切り欠き（ポリゴンカットの経度・開き具合）をリアルタイムに動かす。大きな超球の係だけ、毎コマ
    ///   引いて広げる：押した経度からドラッグした経度までを切る（回り込んだ分も足していく。最大 1 周）。付いてくる：開き具合の切り欠きの真ん中がナイフ
    func knifeStep(_ mvp: simd_float4x4, _ sz: CGSize) {
        guard st.knifeOn else { knifeWasDown = false; st.knifeLon = nil; return }
        let lon = (st.knifeDown ? st.knifePtr : st.knifeHover).flatMap { knifePick($0, mvp, sz) }
        if lon != nil || !st.knifeDown { st.knifeLon = lon }
        guard st.knifeDown else { knifeWasDown = false; return }
        if !knifeWasDown {
            knifeWasDown = true
            knifeStartLon = knifePick(st.knifeStart, mvp, sz)
            guard let s = knifeStartLon else { return }
            knifePrevLon = s; knifeSpan = 0
            st.cutOn = true; st.cutKind = 0; st.cutRef = 2; st.cutPhi = s
            if st.knifeMove { if st.cutWDeg < 10 { st.cutWDeg = 90 } } else { st.cutWDeg = 0 }
            return
        }
        guard let s = knifeStartLon, let l = lon else { return }
        if st.knifeMove { st.cutPhi = l; return }
        var d = l - knifePrevLon; d -= 2 * .pi * floor((d + .pi) / (2 * .pi))
        knifePrevLon = l; knifeSpan = max(-2 * .pi, min(2 * .pi, knifeSpan + d))
        st.cutPhi = s + knifeSpan / 2; st.cutWDeg = min(360, abs(knifeSpan) * 180 / .pi)
    }
    /// ドリルの穴：掘り始めた点から今いる所まで、超球の中をまっすぐ通る金色の線（中心を抜けると反対側へ続く）
    func drawDrill(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard side == .right, !overview, st.drillK > 0.01, let w = wsrc?() else { return }
        if st.runLine { drawRunLine(e, u0); return }
        let p0 = st.drillS < 1 ? w.pos : -w.pos, R0 = st.drillR0, s = st.drillS, (eye, _, _, _) = camBasis()
        var v: [HLCometVert] = []
        func vert(_ a: SIMD3<Double>, _ q: SIMD4<Float>, _ c: SIMD4<Float>) -> HLCometVert { let f = SIMD3<Float>(a); return HLCometVert(p: SIMD4<Float>(f.x, f.y, f.z, 1), q: q, c: c) }
        func at(_ t: Double) -> SIMD3<Double> { walkPlace(p0 * (R0 * (1 - t))).0 }
        let M = 64, kq = SIMD4<Float>(1, 0, 17, 1), k = Float(st.drillK)
        var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
        for i in 0...M {
            let t = s * Double(i) / Double(M), p = at(t), a0 = at(max(0, t - 0.02)), b0 = at(t + 0.02)
            var sd: SIMD3<Double> = simd_cross(b0 - a0, eye - p)
            let l = simd_length(sd), wid: Double = 0.011 * max(0.5, min(1.4, simd_length(eye - p) / 7.5))
            sd = l < 1e-12 ? SIMD3<Double>() : sd / l * wid
            // 足し合わせで白く飛ばないよう、明るさは 0.7 まで
            let lum = k * Float(0.3 + 0.4 * Double(i) / Double(M)), col = SIMD4<Float>(lum, 0.62 * lum, 0.16 * lum, lum), lo = p - sd, hi = p + sd
            if let (pl, pr, pc) = prev {
                v.append(vert(pl, kq, pc)); v.append(vert(pr, kq, pc)); v.append(vert(hi, kq, col))
                v.append(vert(pl, kq, pc)); v.append(vert(hi, kq, col)); v.append(vert(lo, kq, col))
            }
            prev = (lo, hi, col)
        }
        guard !v.isEmpty else { return }
        var u = u0
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthRead)
        v.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
    }
    /// 超球ラン（ダイブ画面）：通った道を金色の線で。古い所ほど薄く、中心を抜けて反対側へ続く
    func drawRunLine(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let pts4 = st.runPathPoints()
        guard pts4.count > 1 else { return }
        let (eye, _, _, _) = camBasis(), pts = pts4.map { walkPlace($0).0 }
        var v: [HLCometVert] = []; v.reserveCapacity(pts.count * 6)
        func vert(_ a: SIMD3<Double>, _ q: SIMD4<Float>, _ c: SIMD4<Float>) -> HLCometVert { let f = SIMD3<Float>(a); return HLCometVert(p: SIMD4<Float>(f.x, f.y, f.z, 1), q: q, c: c) }
        let kq = SIMD4<Float>(1, 0, 17, 1), k = Float(st.drillK), n = pts.count
        var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
        for i in 0..<n {
            let p = pts[i], a0 = pts[max(0, i - 1)], b0 = pts[min(n - 1, i + 1)]
            var sd: SIMD3<Double> = simd_cross(b0 - a0, eye - p)
            let l = simd_length(sd), wid: Double = 0.011 * max(0.5, min(1.4, simd_length(eye - p) / 7.5))
            sd = l < 1e-12 ? SIMD3<Double>() : sd / l * wid
            let f = Double(i) / Double(n - 1), lum = k * Float(0.7 * f * f)          // 足し合わせで白く飛ばないよう、明るさは 0.7 まで
            let col = SIMD4<Float>(lum, 0.62 * lum, 0.16 * lum, lum), lo = p - sd, hi = p + sd
            if let (pl, pr, pc) = prev {
                v.append(vert(pl, kq, pc)); v.append(vert(pr, kq, pc)); v.append(vert(hi, kq, col))
                v.append(vert(pl, kq, pc)); v.append(vert(hi, kq, col)); v.append(vert(lo, kq, col))
            }
            prev = (lo, hi, col)
        }
        guard !v.isEmpty else { return }
        var u = u0
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthRead)
        v.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
    }
    /// ナイフの刃：指している経度に、いちばん外の殻の少し外を北極から南極まで光る線。殻の向こう側は薄く
    func drawKnife(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.knifeOn, side == .right, !overview, !diveWipe, dvT == 0, let ph = st.knifeLon, let ks = knifeShell() else { return }
        let c = ks.c, rr = ks.r, (eye, _, _, _) = camBasis(), ctr = walkPlace(c).0
        var v: [HLCometVert] = []; v.reserveCapacity(64 * 6)
        func vert(_ a: SIMD3<Double>, _ q: SIMD4<Float>, _ c: SIMD4<Float>) -> HLCometVert { let f = SIMD3<Float>(a); return HLCometVert(p: SIMD4<Float>(f.x, f.y, f.z, 1), q: q, c: c) }
        func at(_ t: Double) -> SIMD3<Double> { walkPlace(Self.knifePoint(c, rr * 1.012, t, ph)).0 }
        let M = 64, kq = SIMD4<Float>(1, 0, 17, 1)
        var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
        for i in 0...M {
            let t = Double.pi * Double(i) / Double(M), p = at(t), a0 = at(max(0, t - 0.03)), b0 = at(min(.pi, t + 0.03))
            var sd: SIMD3<Double> = simd_cross(b0 - a0, eye - p)
            let l = simd_length(sd), wid: Double = 0.009 * max(0.5, min(1.4, simd_length(eye - p) / 7.5))
            sd = l < 1e-12 ? SIMD3<Double>() : sd / l * wid
            let front = simd_dot(p - ctr, eye - p) > 0
            let lum: Float = (front ? 1.5 : 0.3) * (st.knifeDown ? 1.3 : 1)
            let col = SIMD4<Float>(lum, 0.96 * lum, 0.82 * lum, lum), lo = p - sd, hi = p + sd
            if let (pl, pr, pc) = prev {
                v.append(vert(pl, kq, pc)); v.append(vert(pr, kq, pc)); v.append(vert(hi, kq, col))
                v.append(vert(pl, kq, pc)); v.append(vert(hi, kq, col)); v.append(vert(lo, kq, col))
            }
            prev = (lo, hi, col)
        }
        guard !v.isEmpty else { return }
        var u = u0
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
        v.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
    }
}
