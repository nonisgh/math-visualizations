// 次元おりがみ（ネイティブ版）の宇宙：組み立てていくと、箱が「超球の窓の球殻の宇宙モード」の雰囲気になる。組み上がった瞬間に光の波が広がる。
//   箱の宇宙：面はうすいガラスに、面に光の網目（tlf。ふだんは切）、胞の中に星屑（右は 8 つの立方体の胞、左は 6 枚の正方形の面に。折る・離すと一緒に動く）。
//   背景も宇宙にする時（「背景も宇宙」）は、下の星空と星雲を背景に混ぜる。
//   星は「大きな超立方体（左は大きな立方体）の表面」に散らばった点。形と同じ回転で回すので、W 回転すると星空も 4 次元に回る。
//     見える向き：回したあとの xyz の向き（遠い空）。超立方体の星は w の手前（＋）ほど明るく大きく、奥（−）ほど暗く小さい。
//     天の川：大きな超立方体の 32 本の辺（立方体は 12 本）のまわりの細かい星くず。組み立ての最後のほうで灯る。
//   背景は星雲（深い紺に、右は紫・青、左は青・桃のうすい雲）。星は組み立て具合に合わせて 1 つずつ灯る（星ごとのしきい値）。
//   ほかの窓（超球の窓・さんぽ）には頼らない（いずれ別のアプリに分けられるように、ここだけで完結）。
import SwiftUI
import MetalKit

struct OGStar { var p, c, k: SIMD4<Float> }               // p：4D の位置、c：色・明るさ、k：灯るしきい値・種類（0 星・1 星くず・2 淡い光の雲）・またたきの位相
struct OGDust { var p, c: SIMD4<Float> }                 // p：景色の位置・またたきの位相、c：色・明るさ
struct OGSkyU {
    var M = matrix_identity_float4x4                        // 星の回転（形と同じ）
    var a = SIMD4<Float>(0, 0, 0, 0)                        // 空の tan（縦の半分）・横÷縦・宇宙の量・時刻（星屑の時は M の列 0 がカメラの位置）
    var b = SIMD4<Float>(0, 0, 0, 0)                        // 1 画素（縦の 2÷高さ）・使わない・4D なら 1・星の大きさの倍率
    var f = SIMD4<Float>(0, 0, 0, 0)                        // 光の強さ（1 → 0）・光の波の進み（0 → 1）
}

extension OrigamiState {
    static let FLASH_DUR = 1.8
    /// 宇宙の量（0 紺・1 宇宙）。組み立てに合わせる時は、0.3 から灯りはじめて組み上がりで満天
    var spaceK: Double {
        switch spaceMode {
        case 1: return 1
        case 2: return 0
        default: let c = max(0, min(1, (progress - 0.3) / 0.7)); return c * c * (3 - 2 * c)
        }
    }
    /// 組み上がった瞬間の光の波の進み（0 → 1。出していない時は nil）
    var spaceFlashT: Double? { spaceMode == 2 || flashT >= Self.FLASH_DUR ? nil : flashT / Self.FLASH_DUR }
    var spaceFlash: Double { spaceFlashT.map { 1 - $0 } ?? 0 }
    /// 星の回転（形と同じ。手で回した分も。遠近は使わない）
    func skyRot(_ n: Int) -> simd_float4x4 {
        let m = n == 4 ? m4 : rxy * l3
        func f(_ c: SIMD4<Double>) -> SIMD4<Float> { SIMD4<Float>(Float(c.x), Float(c.y), Float(c.z), Float(c.w)) }
        return simd_float4x4(f(m.columns.0), f(m.columns.1), f(m.columns.2), n == 4 ? f(m.columns.3) : SIMD4(0, 0, 0, 1))
    }
}

let ogSkyShader = """
#include <metal_stdlib>
using namespace metal;
struct Star { float4 p, c, k; };
struct SU { float4x4 M; float4 a, b, f; };
struct QO { float4 pos [[position]]; float2 uv; };
struct SO { float4 pos [[position]]; float4 c; float2 q; float ph; };
constant float2 CO[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
vertex QO ogq(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); QO o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = p; return o; }
inline float hh(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
inline float vn(float2 p) { float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hh(i), hh(i + float2(1, 0)), f.x), mix(hh(i + float2(0, 1)), hh(i + float2(1, 1)), f.x), f.y); }
inline float fbm(float2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + float2(1.7, 9.2); a *= 0.5; } return s; }
// 星雲：深い紺に、うすい雲（右は紫・青、左は青・桃）と、小さな遠い星
fragment float4 ogneb(QO in [[stage_in]], constant SU& u [[buffer(0)]]) {
    float2 uv = in.uv * float2(u.a.y, 1.0);
    float3 c = mix(float3(0.006, 0.010, 0.030), float3(0.020, 0.028, 0.075), smoothstep(1.3, 0.0, length(in.uv - 0.5) * 1.6));
    float n1 = fbm(uv * 2.2 + float2(3.1, 1.3)), n2 = fbm(uv * 3.7 + float2(8.4, 2.2));
    bool four = u.b.z > 0.5;
    float3 c1 = four ? float3(0.30, 0.14, 0.42) : float3(0.12, 0.20, 0.44), c2 = four ? float3(0.10, 0.22, 0.45) : float3(0.30, 0.12, 0.30);
    c += c1 * pow(smoothstep(0.45, 0.95, n1), 2.0) * 0.55 + c2 * pow(smoothstep(0.5, 1.0, n2), 2.0) * 0.5;
    float2 g = floor(uv * 260.0); float r = hh(g);
    if (r > 0.9965) { float2 f = fract(uv * 260.0) - 0.5; c += float3(0.8, 0.85, 1.0) * (r - 0.9965) * 250.0 * exp(-dot(f, f) * 30.0); }
    return float4(c, 1.0);
}
fragment float4 ogcp(QO in [[stage_in]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear, address::clamp_to_edge); return t.sample(s, float2(in.uv.x, 1.0 - in.uv.y)); }
// 星：回したあとの xyz の向きを、カメラ（+z の側から −z を見る・y が上）の空へ
vertex SO skv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Star* S [[buffer(0)]], constant SU& u [[buffer(1)]]) {
    Star s = S[iid]; float4 v = u.M * s.p; float3 x = v.xyz; float L = length(x);
    SO o; o.q = CO[vid]; o.ph = s.k.z; o.c = float4(0.0); o.pos = float4(3.0, 3.0, 0.0, 1.0);
    if (L < 0.05 || -x.z < 0.05 * L) return o;
    float2 sc = float2(x.x / (-x.z) / (u.a.x * u.a.y), x.y / (-x.z) / u.a.x);
    float wk = u.b.z > 0.5 ? 0.3 + 0.7 * smoothstep(-1.0, 1.0, v.w) : 1.0;   // 4D：w の手前ほど明るく大きく
    float on = smoothstep(s.k.x * 0.9, s.k.x * 0.9 + 0.1, u.a.z);            // 組み立て具合で 1 つずつ灯る
    float px = (s.k.y > 1.5 ? 18.0 : s.k.y > 0.5 ? 1.5 : 1.4 + 2.8 * s.c.w) * (0.55 + 0.45 * wk) * u.b.w * (1.0 + 0.5 * u.f.x);
    o.ph = s.k.y > 1.5 ? -1.0 : s.k.z;                                       // 光の雲はまたたかない（ぼんやり光るだけ）
    o.pos = float4(sc + CO[vid] * px * u.b.x * float2(1.0 / u.a.y, 1.0), 0.0, 1.0);
    o.c = float4(s.c.rgb, s.c.w * wk * on * (1.0 + 1.5 * u.f.x));
    return o;
}
fragment float4 skf(SO in [[stage_in]], constant SU& u [[buffer(1)]]) {
    float dd = dot(in.q, in.q); if (dd > 1.0) discard_fragment();
    if (in.ph < 0.0) return float4(in.c.rgb * in.c.a * exp(-dd * 2.5) * (1.0 - dd), 1.0);
    float a = in.c.a * exp(-dd * 4.5);
    float t = u.a.w, w = 1.0 + 0.3 * (0.6 * sin(t * (1.7 + 2.3 * fract(in.ph * 0.37)) + in.ph) + 0.3 * sin(t * 5.3 + in.ph * 2.1));   // またたき（星ごとに速さと位相をずらす）
    return float4(in.c.rgb * a * max(0.0, w), 1.0);
}
// 胞の中の星屑：景色の位置を、カメラ（M の列 0 の位置から −z を見る・y が上）の画面へ。近いほど大きく
struct Dust { float4 p, c; };
vertex SO dsv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Dust* D [[buffer(0)]], constant SU& u [[buffer(1)]]) {
    Dust s = D[iid]; float3 r = s.p.xyz - u.M[0].xyz;
    SO o; o.q = CO[vid]; o.ph = s.p.w; o.c = s.c; o.pos = float4(3.0, 3.0, 0.0, 1.0);
    float z = -r.z; if (z < 0.1 || s.c.a <= 0.001) return o;
    float2 sc = float2(r.x / (z * u.a.x * u.a.y), r.y / (z * u.a.x));
    float px = (1.3 + 1.6 * s.c.a) * u.b.w * clamp(7.0 / z, 0.6, 2.0);
    o.pos = float4(sc + CO[vid] * px * u.b.x * float2(1.0 / u.a.y, 1.0), 0.0, 1.0);
    return o;
}
// 組み上がった瞬間の光の波：真ん中から輪が広がり、真ん中がふわっと光る
fragment float4 ogfl(QO in [[stage_in]], constant SU& u [[buffer(0)]]) {
    float t = u.f.y, k = 1.0 - t;
    float2 q = (in.uv - 0.5) * float2(u.a.y, 1.0); float r = length(q);
    float R = 0.04 + 1.25 * t, wd = 0.035 + 0.08 * t;
    float ring = exp(-pow((r - R) / wd, 2.0)) * k * k, core = exp(-r * r * 10.0) * k * k * k * 0.7;
    float3 col = mix(float3(0.55, 0.85, 1.0), float3(0.85, 0.6, 1.0), smoothstep(0.0, 0.8, r));
    return float4(col * (ring * 0.9 + core), 1.0);
}
"""

/// 宇宙の背景を、毎コマ 1 枚の絵に描く（星雲は大きさが変わった時だけ）。次元おりがみの光で描くシェーダー（tlf）がそれを背景に混ぜる
final class OrigamiSky {
    let n: Int
    private let device: MTLDevice
    private let nebPipe, copyPipe, starPipe, flashPipe, dustPipe: MTLRenderPipelineState
    private let stars: MTLBuffer, count: Int
    private var neb: MTLTexture?, out: MTLTexture?

    init?(device d: MTLDevice, n: Int) {
        guard let lib = try? d.makeLibrary(source: ogSkyShader, options: nil) else { return nil }
        func pipe(_ v: String, _ f: String, add: Bool) -> MTLRenderPipelineState? {
            let p = MTLRenderPipelineDescriptor(); p.vertexFunction = lib.makeFunction(name: v); p.fragmentFunction = lib.makeFunction(name: f)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm
            if add {
                let c = p.colorAttachments[0]!; c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
            }
            return try? d.makeRenderPipelineState(descriptor: p)
        }
        guard let a = pipe("ogq", "ogneb", add: false), let b = pipe("ogq", "ogcp", add: false), let c = pipe("skv", "skf", add: true), let e = pipe("ogq", "ogfl", add: true),
              let g = pipe("dsv", "skf", add: true) else { return nil }
        nebPipe = a; copyPipe = b; starPipe = c; flashPipe = e; dustPipe = g
        let list = Self.makeStars(n)
        guard let buf = list.withUnsafeBytes({ d.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }
        stars = buf; count = list.count; device = d; self.n = n
    }

    /// 星の並び：大きな超立方体（立方体）の表面の星と、辺のまわりの星くず。順番は混ぜておく（星の数で前から使う）
    static func makeStars(_ n: Int) -> [OGStar] {
        var seed: UInt64 = n == 4 ? 0x0516_A4D4 : 0x0516_A3D3
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
        func gauss() -> Float { let u = max(1e-6, rnd()), v = rnd(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
        var out: [OGStar] = []
        // 表面の星：決まった軸を 1 本選んで ±1、ほかの軸は −1〜1。青白い星が多く、ときどき暖かい色
        for _ in 0..<(n == 4 ? 9000 : 5000) {
            var p = SIMD4<Float>(0, 0, 0, 0)
            for j in 0..<n { p[j] = rnd() * 2 - 1 }
            p[min(n - 1, Int(rnd() * Float(n)))] = rnd() < 0.5 ? -1 : 1
            let warm = rnd() < 0.22 ? rnd() : 0
            let col = simd_mix(SIMD3<Float>(0.75, 0.85, 1.0), SIMD3<Float>(1.0, 0.86, 0.66), SIMD3(repeating: warm))
            out.append(OGStar(p: p, c: SIMD4(col, 0.2 + 1.1 * rnd() * rnd()), k: SIMD4(rnd() * 0.8, 0, rnd() * 40, 0)))
        }
        // 辺の星くず（超立方体の天の川）：辺は軸 1 本だけ動いて、ほかは ±1。少しだけ散らす。組み立ての最後のほうで灯る
        //   星くず（細かい点）と、淡い光の雲（大きくぼんやり。帯に見えるように）
        let per = n == 4 ? 520 : 700, hazePer = n == 4 ? 70 : 90
        for f in 0..<n {
            let others = (0..<n).filter { $0 != f }
            for bits in 0..<(1 << others.count) {
                for j in 0..<(per + hazePer) {
                    let haze = j >= per
                    var p = SIMD4<Float>(0, 0, 0, 0); p[f] = rnd() * 2 - 1
                    for (k, a) in others.enumerated() { p[a] = (bits & (1 << k) != 0 ? 1 : -1) + gauss() * (haze ? 0.03 : 0.045) }
                    let col = simd_mix(SIMD3<Float>(0.62, 0.72, 1.0), SIMD3<Float>(0.92, 0.78, 1.0), SIMD3(repeating: rnd()))
                    out.append(OGStar(p: p, c: SIMD4(col, haze ? 0.05 + 0.05 * rnd() : 0.25 + 0.45 * rnd()), k: SIMD4(0.5 + 0.5 * rnd(), haze ? 2 : 1, rnd() * 40, 0)))
                }
            }
        }
        for i in stride(from: out.count - 1, to: 0, by: -1) { out.swapAt(i, min(i, Int(rnd() * Float(i + 1)))) }
        return out
    }

    /// 胞の中の星屑の種：どの胞か・胞の中の位置（決まった軸は ±1、ほかは −0.92〜0.92）・灯るしきい値・明るさ・またたきの位相
    struct DustSeed { let cell: Int; let p: [Double]; let thr, bright, ph: Float }
    static func makeDust(_ n: Int) -> [DustSeed] {
        var seed: UInt64 = n == 4 ? 0xD057_4D : 0xD057_3D
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
        let cells = OrigamiState.cells(n)
        var out: [DustSeed] = []
        for _ in 0..<(n == 4 ? 260 : 220) {
            for (ci, cell) in cells.enumerated() {
                let (fa, fv) = OrigamiState.fixed(cell, n)
                var p = (0..<n).map { _ in Double(rnd() * 1.84 - 0.92) }; p[fa] = fv
                out.append(DustSeed(cell: ci, p: p, thr: rnd() * 0.85, bright: 0.25 + 0.75 * rnd() * rnd(), ph: rnd() * 40))
            }
        }
        return out
    }
    lazy var dustSeeds = Self.makeDust(n)
    /// 星屑を描く（形の絵のあとに、足し合わせで。透けたガラスの中に光る点）。off：胞を離した量、eye：カメラの位置（景色の座標）
    func drawDust(_ e: MTLRenderCommandEncoder, _ st: OrigamiState, _ off: [SIMD3<Double>], eye: SIMD3<Double>, tanF: Double, w: Int, h: Int, now: Double) {
        let sk = Float(st.spaceK), fl = Float(st.spaceFlash)
        guard sk > 0.001 else { return }
        let cells = OrigamiState.cells(n), use = max(1, Int(Double(dustSeeds.count) * max(5, min(100, st.starsPct)) / 100))
        let cols = st.cellColors(n)
        var list: [OGDust] = []; list.reserveCapacity(use)
        for d in dustSeeds.prefix(use) {
            let on = max(0, min(1, (sk - d.thr * 0.9) / 0.1)); if on <= 0 { continue }
            let (q, k) = st.place(st.fold(cells[d.cell], d.p, n), n)
            let pos = q + (d.cell < off.count ? off[d.cell] : .zero)
            let kb = Float(n == 4 ? max(0.45, min(1.6, k)) : 1)                   // 4D の遠近：手前の胞ほど明るく
            let col = simd_mix(OrigamiState.rgb(cols[d.cell]), SIMD3<Float>(0.9, 0.95, 1.0), SIMD3(repeating: 0.55))
            list.append(OGDust(p: SIMD4(Float(pos.x), Float(pos.y), Float(pos.z), d.ph), c: SIMD4(col, d.bright * on * kb * (1 + 1.5 * fl))))
        }
        guard !list.isEmpty, let buf = list.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return }
        var u = OGSkyU()
        u.M.columns.0 = SIMD4(Float(eye.x), Float(eye.y), Float(eye.z), 1)
        u.a = SIMD4(Float(tanF), Float(Double(w) / Double(max(1, h))), sk, Float(now.truncatingRemainder(dividingBy: 1000)))
        u.b = SIMD4(2 / Float(max(1, h)), 0, n == 4 ? 1 : 0, Float(max(1, Double(h) / 900)))
        e.setRenderPipelineState(dustPipe); e.setVertexBuffer(buf, offset: 0, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: list.count)
    }

    /// 組み上がった瞬間の光の波を、画面へ直接（背景を宇宙にしていない時。足し合わせで）
    func drawFlash(_ e: MTLRenderCommandEncoder, _ st: OrigamiState, w: Int, h: Int) {
        guard let t = st.spaceFlashT else { return }
        var u = OGSkyU(); u.a = SIMD4(0.9, Float(Double(w) / Double(max(1, h))), 0, 0); u.f = SIMD4(Float(1 - t), Float(t), 0, 0)
        e.setRenderPipelineState(flashPipe); e.setFragmentBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private func tex(_ old: MTLTexture?, _ w: Int, _ h: Int) -> MTLTexture? {
        if let t = old, t.width == w, t.height == h { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// 宇宙の絵を描く（この後で積む絵より先に GPU で描かれる。同じ列）
    func render(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int, _ st: OrigamiState, _ now: Double) -> MTLTexture? {
        var u = OGSkyU()
        u.M = st.skyRot(n)
        u.a = SIMD4(0.9, Float(Double(w) / Double(max(1, h))), Float(st.spaceK), Float(now.truncatingRemainder(dividingBy: 1000)))
        u.b = SIMD4(2 / Float(max(1, h)), 0, n == 4 ? 1 : 0, Float(max(1, Double(h) / 900)))
        if let t = st.spaceFlashT { u.f = SIMD4(Float(1 - t), Float(t), 0, 0) }
        if neb?.width != w || neb?.height != h {
            guard let t = tex(nil, w, h) else { return nil }
            neb = t
            let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
            guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
            e.setRenderPipelineState(nebPipe); e.setFragmentBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        }
        guard let nt = neb, let ot = tex(out, w, h) else { return nil }
        out = ot
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = ot; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        e.setRenderPipelineState(copyPipe); e.setFragmentTexture(nt, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        let use = max(1, Int(Double(count) * max(5, min(100, st.starsPct)) / 100))
        e.setRenderPipelineState(starPipe); e.setVertexBuffer(stars, offset: 0, index: 0)
        e.setVertexBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: use)
        if u.f.x > 0 { e.setRenderPipelineState(flashPipe); e.setFragmentBytes(&u, length: MemoryLayout<OGSkyU>.stride, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3) }
        e.endEncoding()
        return ot
    }
}

#if os(macOS)
extension OrigamiRenderer {
    /// 確かめ：OGSET="mul4=0,glass4=0" で、見た目のつまみを上書き
    static func applyOGSET(_ st: OrigamiState) {
        guard let kv = ProcessInfo.processInfo.environment["OGSET"] else { return }
        let keys: [String: ReferenceWritableKeyPath<OrigamiState, Double>] = ["mul4": \.mul4, "glow4": \.glow4, "glass4": \.glass4, "reflSelf": \.reflSelf, "squash4": \.squash4, "slant3": \.slant3, "netMul": \.netMul, "netSolid": \.netSolid, "fantasy": \.fantasy, "stripK": \.stripK, "softMul": \.softMul, "smartLine": \.smartLine, "lineTint": \.lineTint, "deep": \.deep, "inner": \.inner, "depth3": \.depth3]
        for p in kv.split(separator: ",") { let q = p.split(separator: "="); if q.count == 2, let k = keys[String(q[0])], let v = Double(q[1]) { st[keyPath: k] = v } }
    }
    /// 確かめの絵（--ogpng 出力先）：左の立方体と右の超立方体を並べた 1 枚を、組み立て具合ごとに
    static func png(_ dir: String) {
        guard let d = MTLCreateSystemDefaultDevice() else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let st = OrigamiState()
        guard let r3 = OrigamiRenderer(n: 3, state: st, device: d), let r4 = OrigamiRenderer(n: 4, state: st, device: d),
              let r4L = OrigamiRenderer(n: 4, state: st, device: d), let r5 = OrigamiRenderer(n: 5, state: st, device: d) else { print("組み立てに失敗"); return }
        let w = 900, h = 860
        func tex() -> MTLTexture {
            let t = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false); t.usage = [.renderTarget, .shaderRead]; t.storageMode = .managed
            return d.makeTexture(descriptor: t)!
        }
        let t3 = tex(), t4 = tex()
        func render(_ r: OrigamiRenderer, _ t: MTLTexture) {
            let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = t; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
            let cb = r.queue.makeCommandBuffer()!; r.encode(cb, rpd, w, h, now: 12.3, dt: 0.3)
            let bl = cb.makeBlitCommandEncoder()!; bl.synchronize(resource: t); bl.endEncoding()
            cb.commit(); cb.waitUntilCompleted()
        }
        // 5 次元の見え方のおすすめの角度を、なめらか移動なしで（0 3D展開・1 4D展開）
        func set5(_ s: OrigamiState, _ k: Int) {
            let dg = Double.pi / 180
            s.ax = 0; s.ay = 0; s.zw = 0; s.xy = 15 * dg; s.xz = 30 * dg; s.yz = 20 * dg
            s.xw5 = k == 1 ? 45 * dg : 0; s.yw5 = k == 1 ? 35.264 * dg : 0; s.zw5 = k == 1 ? 30 * dg : 0; s.wv5 = 0
            s.presetPar = Double(k); s.projBlend = Double(k); s.updateMats()
        }
        let scenes: [(String, (OrigamiState) -> Void)] = [
            ("H1_内接球・正面", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.inSphere = true }),
            ("H3_内接球・レインボー（前の見た目）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.inSphere = true; $0.inSphereColor = 1; $0.inSphereLayers = 6 }),
            ("H4_内接球・アプリの色・27 枚", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0.8; $0.ay = 0.5; $0.inSphere = true; $0.inSphereLayers = 14 }),
            ("H2_内接球・W 回転", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0.8; $0.ay = 0.5; $0.inSphere = true }),
            ("KT1_内接球の接点・光の輪", { $0.progress = 1; $0.inSphere = true }),
            ("KT2_内接球の接点・胞の中心の点と重ねる", { $0.progress = 1; $0.inSphere = true; $0.addCellCtrs() }),
            ("KT3_内接球の接点・胞の色", { $0.progress = 1; $0.inSphere = true; $0.inSphereTouchCol = 1 }),
            ("SM1_内接球の模様・緯度だけ", { $0.progress = 1; $0.inSphere = true; $0.inSphereLon = false; $0.inSphereCone = false }),
            ("SM2_内接球の模様・経度だけ", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereCone = false }),
            ("SM3_内接球の模様・円錐だけ", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false }),
            ("SM4_内接球の模様・全部", { $0.progress = 1; $0.inSphere = true }),
            ("LW1_線の太さ 2 倍", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2 }),
            ("LW2_線の太さ 2 倍・奥ほど太く", { $0.progress = 1; $0.lineWidthSolid = 2; $0.line4W = 1; $0.line4 = 0 }),
            ("LW3_線の太さ 2 倍・奥ほど細く・胞の色でなじませる", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2; $0.line4W = -1; $0.lineTint = 1 }),
            ("L3a_線の 3D の奥行きなし・太さ 2 倍", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2; $0.line4W = 0; $0.line4 = 0 }),
            ("L3b_線の 3D の奥行き 太さ −100%・濃さ 100%", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2; $0.line4W = 0; $0.line4 = 0; $0.line3W = -1; $0.line3K = 1 }),
            ("OIL0_今のガラス・3 つ全部", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true }),
            ("OIL1_油膜 トーン 100%・3 つ全部", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereFilm = true; $0.inSphereTone = 1 }),
            ("OIL2_油膜 トーン 75%・3 つ全部", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereFilm = true; $0.inSphereTone = 0.75 }),
            ("OIL3_油膜 トーン 50%・3 つ全部", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereFilm = true; $0.inSphereTone = 0.5 }),
            ("OIL4_油膜 トーン 75%・緯度だけ", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereFilm = true; $0.inSphereTone = 0.75; $0.inSphereLon = false; $0.inSphereCone = false }),
            ("OIL5_油膜 トーン 75%・W で回した", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereFilm = true; $0.inSphereTone = 0.75; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("AP1_出現 25%・正120胞体", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereAppear = 0.25 }),
            ("AP2_出現 50%・正120胞体", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereAppear = 0.5 }),
            ("AP3_出現 75%・正120胞体", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereAppear = 0.75 }),
            ("AP4_出現 40%・緯度", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphereAppear = 0.4 }),
            ("AP5_出現 70%・緯度", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphereAppear = 0.7 }),
            ("AP6_出現 50%・5 次元の正軸体", { $0.dim5 = true; $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphere120 = true; $0.inSphereLat = false; $0.inSphereAppear = 0.5; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.zw5 = 0.2; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.updateMats() }),
            ("ID0_内接球の遠近なし・正120胞体", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true }),
            ("ID1_内接球の遠近 100%・正120胞体", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereDepth = 1 }),
            ("ID2_内接球の遠近 60%・緯度", { $0.progress = 1; $0.spaceMode = 2; $0.inSphere = true; $0.inSphereDepth = 0.6 }),
            ("ID3_ワイヤー", { $0.progress = 1; $0.spaceMode = 2; $0.wireOnly = true }),
            ("SH0_立体感なし（あなたの設定に近い）", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13 }),
            ("SH1_斜めの面の照り返し 50%・奥を色濃く 50%", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13; $0.slantSheen = 0.5; $0.depthDeep = 0.5 }),
            ("SH2_斜めの面の照り返し 100%", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13; $0.slantSheen = 1 }),
            ("SH3_奥を色濃く 100%", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13; $0.depthDeep = 1 }),
            ("SH4_照り返し 50%・奥 50%・W で回した", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13; $0.slantSheen = 0.5; $0.depthDeep = 0.5; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("SH5_立体感なし・W で回した", { $0.progress = 1; $0.spaceMode = 2; $0.depth3 = 0.41; $0.mul4 = 0.5; $0.glow4 = 0.67; $0.glass4 = 0.22; $0.squash4 = 0.56; $0.slant3 = 0.48; $0.reflSelf = 0.33; $0.stripK = 0.13; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("MU0_4D の奥の乗算なし", { $0.progress = 1; $0.spaceMode = 2; $0.mul4 = 0; $0.glow4 = 0; $0.glass4 = 0; $0.squash4 = 0; $0.slant3 = 0; $0.netMul = 0 }),
            ("MU1_4D の奥の乗算だけ 100%", { $0.progress = 1; $0.spaceMode = 2; $0.mul4 = 1; $0.glow4 = 0; $0.glass4 = 0; $0.squash4 = 0; $0.slant3 = 0; $0.netMul = 0 }),
            ("MU2_4D の奥の乗算・ふだんの組み合わせ", { $0.progress = 1; $0.spaceMode = 2 }),
            ("MU3_4D の奥の乗算だけ 100%・正面", { $0.progress = 1; $0.spaceMode = 2; $0.mul4 = 1; $0.glow4 = 0; $0.glass4 = 0; $0.squash4 = 0; $0.slant3 = 0; $0.netMul = 0; $0.xz = 0.25; $0.yz = -0.2; $0.updateMats() }),
            ("LW0_ふつう（くらべる用）", { $0.progress = 1; $0.spaceMode = 2 }),
            ("LW4_画面の色を濃く・太さ 2 倍", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2; $0.lineTint = 1; $0.lineTintMode = 2 }),
            ("LW9_重なりの乗算色・太さ 2 倍", { $0.progress = 1; $0.spaceMode = 2; $0.lineWidthSolid = 2; $0.lineTint = 1; $0.lineTintMode = 1 }),
            ("LW5_画面の色を濃く・ふつうの太さ", { $0.progress = 1; $0.spaceMode = 2; $0.lineTint = 1; $0.lineTintMode = 2 }),
            ("LW6_展開図は細く・組み上がりは太く（展開図）", { $0.progress = 0; $0.lineWidthNet = 0.6; $0.lineWidthSolid = 2.5 }),
            ("LW7_内接球・正120胞体・ワイヤー 2 倍", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereWireW = 2 }),
            ("LW8_内接球・正120胞体・ワイヤー 1 倍", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true }),
            ("SM6_内接球・正120胞体だけ（軸の色）", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true }),
            ("SM7_内接球・正120胞体＋緯度（胞の色）", { $0.progress = 1; $0.inSphere = true; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereTouchCol = 1 }),
            ("SM8_内接球・正120胞体・レインボー・ななめ", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false; $0.inSphere120 = true; $0.inSphereColor = 1; $0.ax = 0.75; $0.ay = 0.55; $0.updateMats() }),
            ("SM5_内接球の模様・なし（接点だけ）", { $0.progress = 1; $0.inSphere = true; $0.inSphereLat = false; $0.inSphereLon = false; $0.inSphereCone = false }),
            ("AX1_軸の長さ・回さない", { $0.progress = 1; $0.xz = 0; $0.yz = 0; $0.updateMats() }),
            ("AX2_軸の長さ・X-W ＋0.6", { $0.progress = 1; $0.xz = 0; $0.yz = 0; $0.ax = 0.6; $0.updateMats() }),
            ("AX3_軸の長さ・X-W −0.6", { $0.progress = 1; $0.xz = 0; $0.yz = 0; $0.ax = -0.6; $0.updateMats() }),
            ("AX4_軸の長さ・X-Z 0.9（3D の回転）", { $0.progress = 1; $0.xz = 0.9; $0.yz = 0; $0.updateMats() }),
            ("AU1_おまかせ・ゆがませて組み上がり", { let a = [0.9, -0.6, 0.5, 0.3, 0.6, -0.2]; $0.progress = 1; $0.ax = a[0]; $0.ay = a[1]; $0.zw = a[2]; $0.xy = a[3]; $0.xz = a[4]; $0.yz = a[5]; $0.updateMats() }),
            ("AU2_おまかせ・いちばん近いまっすぐで開く", { let a = OrigamiState.nearestFlat([0.9, -0.6, 0.5, 0.3, 0.6, -0.2]); $0.progress = 0; $0.ax = a[0]; $0.ay = a[1]; $0.zw = a[2]; $0.xy = a[3]; $0.xz = a[4]; $0.yz = a[5]; $0.updateMats() }),
            ("AU3_前のまっすぐ・4D だけ 0 で開く", { let a = [0.9, -0.6, 0.5, 0.3, 0.6, -0.2]; $0.progress = 0; $0.ax = 0; $0.ay = 0; $0.zw = 0; $0.xy = a[3]; $0.xz = a[4]; $0.yz = a[5]; $0.updateMats() }),
            ("MK1_目印・頂点から重なる（同じ大きさ）", { $0.progress = 1; $0.xz = 0.5; $0.yz = -0.4; $0.ax = 0.35; $0.updateMats(); $0.markAlignNow(); $0.markSize = 1.2 }),
            ("MK2_目印・頂点から重なる（遠近の大きさ）", { $0.progress = 1; $0.xz = 0.5; $0.yz = -0.4; $0.ax = 0.35; $0.updateMats(); $0.markAlignNow(); $0.markSize = 1.2; $0.markSame = false }),
            ("MK3_目印・重なった光", { $0.progress = 1; $0.xz = 0.5; $0.yz = -0.4; $0.ax = 0.35; $0.updateMats(); $0.markAlignNow(); $0.markSize = 1.2; $0.markFlashT = 0.22 }),
            // 5 次元 β：左に超立方体・右に 5 次元超立方体（4D展開＝5 次元だけの X-W 45°・Y-W 35.3°・Z-W 30°＋ななめ・平行）
            ("LT0_線・その胞の色", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.3; $0.lineTint = 0.55; $0.smartLine = 0.69; $0.lineTintMode = 0; $0.updateMats() }),
            ("LT1_線・重なりの乗算色", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.3; $0.lineTint = 0.55; $0.smartLine = 0.69; $0.lineTintMode = 1; $0.updateMats() }),
            ("LT2_線・重なりの乗算色・つよく", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.3; $0.lineTint = 1; $0.smartLine = 0; $0.lineTintMode = 1; $0.updateMats() }),
            ("SW_組み立ての色（OGSWEEP で 0〜1 を 1% ずつ）", { $0.progress = 0.5; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("SW95_組み立て 0.95", { $0.progress = 0.95; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("SW96_組み立て 0.96", { $0.progress = 0.96; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats() }),
            ("D5_1_展開図・4D展開", { $0.dim5 = true; $0.progress = 0; set5($0, 1) }),
            ("D5_2_半分・4D展開", { $0.dim5 = true; $0.progress = 0.5; set5($0, 1) }),
            ("D5_3_組み上がり・4D展開", { $0.dim5 = true; $0.progress = 1; set5($0, 1) }),
            ("D5_4_展開図・3D展開", { $0.dim5 = true; $0.progress = 0; set5($0, 0) }),
            ("D5_5_組み上がり・3D展開", { $0.dim5 = true; $0.progress = 1; set5($0, 0) }),
            ("D5_6_組み上がり・5 次元で回した", { $0.dim5 = true; $0.progress = 1; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.zw5 = 0.2; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.updateMats() }),
            ("D5_7_バラした", { $0.dim5 = true; $0.progress = 1; set5($0, 1); $0.explodeRaw = 1 }),
            ("D5_N1_図鑑 No.1", { $0.dim5 = true; $0.progress = 0; set5($0, 1); $0.net5Step(0) }),
            ("D5_N2_図鑑 No.5000", { $0.dim5 = true; $0.progress = 0; set5($0, 1); $0.net5No = 1; $0.net5Step(4999) }),
            ("D5_N3_図鑑 最後", { $0.dim5 = true; $0.progress = 0; set5($0, 1); $0.net5No = 1; $0.net5Step(-1) }),
            ("D5_N4_階段", { $0.dim5 = true; $0.progress = 0; set5($0, 1); $0.setNet5(OrigamiState.net5Presets[1].1) }),
            ("D5_N5_ねじれ・半分", { $0.dim5 = true; $0.progress = 0.5; set5($0, 1); $0.setNet5(OrigamiState.net5Presets[2].1) }),
            ("D5_M1_組み変わりの途中・ダリ→ねじれ", { $0.dim5 = true; $0.progress = 0; set5($0, 1); $0.netAnim = true; $0.switchNet5(OrigamiState.net5Presets[2].1); $0.netMorph?.t = 0.55 }),
            ("D5_M2_組み変わりの途中・3D展開", { $0.dim5 = true; $0.progress = 0; set5($0, 0); $0.netAnim = true; $0.switchNet5(OrigamiState.net5Presets[3].1); $0.netMorph?.t = 0.6 }),
            ("D5_11_内接球・正軸体・5 次元で回した", { $0.dim5 = true; $0.progress = 1; $0.inSphere = true; $0.inSphere120 = true; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.zw5 = 0.2; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.updateMats() }),
            ("D5_12_内接球・正軸体だけ・胞の色", { $0.dim5 = true; $0.progress = 1; $0.inSphere = true; $0.inSphere120 = true; $0.inSphereLat = false; $0.inSphereTouchCol = 1; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.zw5 = 0.2; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.updateMats() }),
            ("D5_8_内接球・3D展開の向き", { $0.dim5 = true; $0.progress = 1; set5($0, 0); $0.inSphere = true }),
            ("D5_9_内接球・5 次元で回した", { $0.dim5 = true; $0.progress = 1; $0.inSphere = true; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.zw5 = 0.2; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.xz = 0.55; $0.yz = -0.4; $0.updateMats() }),
            ("D5_10_内接球・レインボー・胞の色の接点", { $0.dim5 = true; $0.progress = 1; $0.inSphere = true; $0.inSphereColor = 1; $0.inSphereTouchCol = 1; $0.xw5 = 0.5; $0.yw5 = 0.3; $0.wv5 = 0.6; $0.ax = 0.3; $0.ay = 0.2; $0.updateMats() }),
            ("SP1_内接球・3D 回転（層ごとの差）", { $0.progress = 1; $0.inSphere = true; $0.inSphereSpin = 1; $0.inSphereDiff = 1; $0.inSphereT = 1.6; $0.inSphereColor = 1 }),
            ("SP2_内接球・二重回転 1：1 とホップの輪", { $0.progress = 1; $0.inSphere = true; $0.inSphereSpin = 2; $0.inSphereT = 0.9; $0.inSphereColor = 1; $0.inSphereCone = false }),
            ("SP3_内接球・二重回転 1：2", { $0.progress = 1; $0.inSphere = true; $0.inSphereSpin = 2; $0.inSphereRatio = 1; $0.inSphereT = 0.9; $0.inSphereColor = 1; $0.inSphereCone = false; $0.inSphereLon = false }),
            ("DN1_めりこみ・正面", { $0.progress = 1; $0.inSphere = true; $0.xz = 0; $0.yz = 0; $0.updateMats() }),
            ("DN2_めりこみ・ななめ", { $0.progress = 1; $0.inSphere = true }),
            ("DN3_めりこみ・切", { $0.progress = 1; $0.inSphere = true; $0.inSphereDent = false }),
            ("DN4_めりこみ・正面・ふんわり", { $0.progress = 1; $0.inSphere = true; $0.xz = 0; $0.yz = 0; $0.updateMats(); $0.inSphereDentSharp = false }),
            ("DN5_めりこみ・ななめ・ふんわり", { $0.progress = 1; $0.inSphere = true; $0.inSphereDentSharp = false }),
            ("EX1_積分の超球・正確（4D で回した）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.0; $0.ay = 0.45; $0.zw = 0.3; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("EX2_積分の超球・ぷよぷよ（4D で回した）", { $0.intExact = false; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.0; $0.ay = 0.45; $0.zw = 0.3; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("KE1_辺の強調・好きな胞（＋X 黄・−Y 緑、奥は切る）", { $0.progress = 1; $0.ehOn = true; $0.ehFarOn = false; $0.ehCells = ["4:px": SIMD3(1, 0.85, 0.1), "4:ny": SIMD3(0.2, 1, 0.3), "3:px": SIMD3(1, 0.85, 0.1), "3:ny": SIMD3(0.2, 1, 0.3)]; $0.ehWidthOther = 4 }),
            ("KE2_辺の強調・好きな胞・展開図", { $0.progress = 0; $0.ehOn = true; $0.ehCells = ["4:px": SIMD3(1, 0.85, 0.1), "4:nz": SIMD3(1, 0.4, 0.1), "3:px": SIMD3(1, 0.85, 0.1)] }),
            ("K1_目印・既定（置いた点と並べる）", { $0.progress = 1; $0.userPts = [UPoint(c: [1, -1, 1, 1, 0], color: 0xffd54a, label: "", lock: false)] }),
            ("K2_目印・色を変えて奥を隠す", { $0.progress = 1; $0.markNear = SIMD3(1, 0.85, 0.1); $0.markFar = SIMD3(0.3, 1, 0.4); $0.markShowFar = false; $0.markSize = 1.2 }),
            ("K3_目印・重なり（乗算あり）", { $0.progress = 1; $0.xz = -0.7854; $0.yz = 0.6155; $0.updateMats(); $0.markSize = 1.6 }),
            ("K4_目印・重なり（乗算なし）", { $0.progress = 1; $0.xz = -0.7854; $0.yz = 0.6155; $0.updateMats(); $0.markSize = 1.6; $0.markGlue = false }),
            ("Y9_球柱・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intShape = 1; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("YA_内接超球・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("YB_レインボーボール・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intColor = 5; $0.intN = 9; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("RB1_レインボーボール・w だけ・途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 5; $0.intBallSpin = true; $0.intAxes = 8; $0.intN = 41; $0.intT = 3.0; $0.intItems = $0.intUpdate() }),
            ("RB2_レインボーボール・x と w・途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 5; $0.intBallSpin = true; $0.intAxes = 9; $0.intN = 41; $0.intT = 3.0; $0.intItems = $0.intUpdate() }),
            ("RB5_枠だけ（玉なし）・x と w・途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 4; $0.intBallSpin = true; $0.intAxes = 9; $0.intN = 41; $0.intT = 3.0; $0.intItems = $0.intUpdate() }),
            ("RB6_レインボーボール・x と w・途中・立方体の面なし", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 5; $0.intBallSpin = true; $0.intAxes = 9; $0.intN = 41; $0.intT = 3.0; $0.wireOnly = true; $0.intItems = $0.intUpdate() }),
            ("RB3_レインボーボール・4 方向・途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 5; $0.intBallSpin = true; $0.intAxes = 15; $0.intN = 41; $0.intT = 3.0; $0.intItems = $0.intUpdate() }),
            ("RB4_レインボーボール・x と w・n69・途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 5; $0.intBallSpin = true; $0.intAxes = 9; $0.intN = 69; $0.intT = 4.0; $0.intOutOpp = true; $0.intPace = 1; $0.intItems = $0.intUpdate() }),
            ("SH5a_形・4 次元の円すい 途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 5; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH5b_形・4 次元の円すい いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 5; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH6a_形・超立方体を角から 途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 6; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH6b_形・超立方体を角から いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 6; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH7a_形・球のドーナツ 途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 7; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH7b_形・球のドーナツ いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 7; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("IV1_横（x）から・球すい 途中", { $0.progress = 1; $0.spaceMode = 2; $0.intOn = true; $0.intShape = 5; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate(); $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1; $0.updateMats() }),
            ("IV2_横（y）から・球すい 途中", { $0.progress = 1; $0.spaceMode = 2; $0.intOn = true; $0.intShape = 5; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate(); $0.ax = 0; $0.ay = .pi / 2; $0.zw = 0; $0.xy = 0; $0.xz = 0.45; $0.yz = -0.2; $0.projBlend = 1; $0.updateMats() }),
            ("IV3_横（x）から・超立方体を角から いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.intOn = true; $0.intShape = 6; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate(); $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1; $0.updateMats() }),
            ("IV4_横（y）から・球のドーナツ いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.intOn = true; $0.intShape = 7; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate(); $0.ax = 0; $0.ay = .pi / 2; $0.zw = 0; $0.xy = 0; $0.xz = 0.45; $0.yz = -0.2; $0.projBlend = 1; $0.updateMats() }),
            ("SH8a_形・キュービンダー 途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 8; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("SH8b_形・キュービンダー いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 8; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Y1_形・球柱", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 1; $0.intN = 41; $0.intT = 5.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Y2_形・デュオシリンダー", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 2; $0.intN = 41; $0.intT = 5.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Y3_形・タイガー", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 3; $0.intN = 41; $0.intT = 5.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Y4_形・超球（内接）途中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = 4.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Y5_形・超球（内接）いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("V1_見本・七色の縞", { $0.isPreview = true; $0.progress = 1; $0.spaceMode = 2; $0.showAxes = false; $0.intOn = true; $0.intMethod = 0; $0.intLook = 2; $0.intColor = 2; $0.intBallSpin = false; $0.intItems = [IntItem(t: 0, slot: 0.5, a: 1, fa: 1, fly: false, k: 0)]; $0.xz = 0.5; $0.yz = -0.45; $0.zoom = [1, 1.9]; $0.updateMats() }),
            ("V2_見本・レインボーボール", { $0.isPreview = true; $0.progress = 1; $0.spaceMode = 2; $0.showAxes = false; $0.intOn = true; $0.intMethod = 0; $0.intLook = 2; $0.intColor = 5; $0.intBallSpin = false; $0.intItems = [IntItem(t: 0, slot: 0.5, a: 1, fa: 1, fly: false, k: 0)]; $0.xz = 0.5; $0.yz = -0.45; $0.zoom = [1, 1.9]; $0.updateMats() }),
            ("V3_見本・同心球", { $0.isPreview = true; $0.progress = 1; $0.spaceMode = 2; $0.showAxes = false; $0.intOn = true; $0.intMethod = 0; $0.intLook = 2; $0.intColor = 7; $0.intBallSpin = false; $0.intItems = [IntItem(t: 0, slot: 0.5, a: 1, fa: 1, fly: false, k: 0)]; $0.xz = 0.5; $0.yz = -0.45; $0.zoom = [1, 1.9]; $0.updateMats() }),
            ("V4_見本・ドラゴンボール", { $0.isPreview = true; $0.progress = 1; $0.spaceMode = 2; $0.showAxes = false; $0.intOn = true; $0.intMethod = 0; $0.intLook = 2; $0.intColor = 3; $0.intBallSpin = false; $0.intItems = [IntItem(t: 0, slot: 0.5, a: 1, fa: 1, fly: false, k: 0)]; $0.xz = 0.5; $0.yz = -0.45; $0.zoom = [1, 1.9]; $0.updateMats() }),
            ("W1_水・注いでいる", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(6.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("RP1_波紋・浅水・注いでいる", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; if let a = ProcessInfo.processInfo.environment["VXA"], let b = ProcessInfo.processInfo.environment["VXB"] { $0.ax = (Double(a) ?? 0) * .pi / 180; $0.ay = (Double(b) ?? 0) * .pi / 180 }; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterFree = false; $0.waterReal = true; $0.drainMode = 0; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset(); let T = Double(ProcessInfo.processInfo.environment["RPT"] ?? "") ?? 5.0; for _ in 0..<Int(T * 60) { $0.waterTick(1.0 / 60) }; let st = $0; print("波紋の確かめ 3D(4D の水面) 最大", st.swe.rz.map { abs($0) }.max() ?? 0, " 2D 最大", st.swe.rz2.map { abs($0) }.max() ?? 0, " 浅水 η 最大", st.swe.eta.map { abs($0) }.max() ?? 0, " h", st.waterH) }),
            ("W2_水・いっぱい（揺れ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(11.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("W1o_水・注いでいる（前の図）", { $0.waterReal = false; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(6.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("W2o_水・いっぱい（前の図）", { $0.waterReal = false; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(11.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("LD1_ふた・入れている（w）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 2; $0.intAxes = 8; $0.intN = 21; $0.intT = 2.0; $0.intItems = $0.intUpdate() }),
            ("LD2_ふた・閉じかけ（w）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 2; $0.intAxes = 8; $0.intN = 21; let M = $0.intM, ST = $0.intST(M); $0.intT = ST[M - 1] + OrigamiState.intD + 0.25; $0.intItems = $0.intUpdate() }),
            ("LD3_反対側から出す（−W が開く）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 2; $0.intAxes = 8; $0.intN = 21; $0.intOutOpp = true; let M = $0.intM, ST = $0.intST(M); $0.intT = ST[M - 1] + OrigamiState.intD + $0.intHoldNow + 0.6; $0.intItems = $0.intUpdate() }),
            ("LD4_何方向も同時（w・x・y）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 4; $0.intAxes = 8 | 1 | 2; $0.intN = 41; $0.intT = 2.0; $0.intItems = $0.intUpdate() }),
            ("LD5_水・底を開けて抜く", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(14.9 * 60) { $0.waterTick(1.0 / 60) } }),
            ("LD6_ふた・消す（薄く）", { $0.intLidMode = 2; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.intOn = true; $0.intShape = 0; $0.intColor = 2; $0.intAxes = 8; $0.intN = 21; $0.intT = 2.0; $0.intItems = $0.intUpdate() }),
            ("DR1_排水口・抜いている（渦）", { $0.drainMode = 1; $0.holeShow = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(17.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeDA = $0.holeDTarget; $0.holeVA = $0.waterVent ? 1 : 0 }),
            ("DR2_排水口・抜いている・横から", { $0.drainMode = 1; $0.holeShow = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(17.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeDA = $0.holeDTarget; $0.holeVA = $0.waterVent ? 1 : 0 }),
            ("DR3_開けっぱなし・つり合う水位", { $0.drainMode = 1; $0.holeShow = 1; $0.holesOpenSet = true; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(12.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeDA = $0.holeDTarget; $0.holeVA = $0.waterVent ? 1 : 0 }),
            ("DR4_通気口なし・ごぼっ", { $0.drainMode = 1; $0.waterVent = false; $0.holeShow = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(18.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeDA = $0.holeDTarget; $0.holeVA = $0.waterVent ? 1 : 0 }),
            ("DR5_排水口のふた・半分開き", { $0.drainSize = Double(ProcessInfo.processInfo.environment["DS"] ?? "") ?? 0.58; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = (Double(ProcessInfo.processInfo.environment["VXA"] ?? "") ?? 29) * .pi / 180; $0.ay = (Double(ProcessInfo.processInfo.environment["VXB"] ?? "") ?? 17) * .pi / 180; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(17.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeLastT = CACurrentMediaTime() + 1e6; $0.holeShow = 1; $0.holeDA = Double(ProcessInfo.processInfo.environment["HDA"] ?? "") ?? 0.5; $0.holeVA = 1 }),
            ("DR6_排水口が現れる途中", { $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = (Double(ProcessInfo.processInfo.environment["VXA"] ?? "") ?? 29) * .pi / 180; $0.ay = (Double(ProcessInfo.processInfo.environment["VXB"] ?? "") ?? 17) * .pi / 180; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(17.0 * 60) { $0.waterTick(1.0 / 60) }; $0.holeLastT = CACurrentMediaTime() + 1e6; $0.holeShow = 0.5; $0.holeDA = 0; $0.holeVA = 0 }),
            ("DN1_途中で抜く（数字）", { let E = ProcessInfo.processInfo.environment; $0.drainMode = Int(E["DM"] ?? "1") ?? 1; $0.drainSize = Double(E["DS"] ?? "") ?? 0.58; $0.waterNS = E["NS"] == "1"; $0.waterNSRes = 16; $0.progress = 1; $0.intOn = true; $0.intMethod = 1; $0.waterFree = false; $0.waterT = 0; $0.swe.reset(); var T = 0.0, last = -1, log: [String] = []; let at = Double(E["AT"] ?? "") ?? 4; var pressed = false; while T < 120 { if !pressed && T >= at { log.append(String(format: "押す@%.1f(h %.2f)", T, $0.waterH)); $0.waterDrainNow(); pressed = true }; $0.waterTick(1.0 / 60); T += 1.0 / 60; let ph = $0.waterPhase; if ph != last { log.append(String(format: "%d@%.1f(h %.2f)", ph, T, $0.waterH)); last = ph }; if pressed && ph == 1 { break } }; print("途中で抜く：" + log.joined(separator: " ")) }),
            ("NS1_本物の4D・注いでいる", { $0.waterSyrup = Double(ProcessInfo.processInfo.environment["NSSY"] ?? "0") ?? 0; $0.waterRainbow = ProcessInfo.processInfo.environment["NSRB"] != nil; if ProcessInfo.processInfo.environment["NSBALL"] != nil { $0.inSphere = true; $0.inSphereAppear = 1 }; $0.drainMode = 0; $0.waterNSRes = Int(ProcessInfo.processInfo.environment["NSRES"] ?? "32") ?? 32; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int((Double(ProcessInfo.processInfo.environment["NST"] ?? "5") ?? 5) * 60) { $0.waterTick(1.0 / 60) } }),
            ("NS2_本物の4D・いっぱい", { $0.drainMode = 0; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(12.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("NSZ_はちみつの拡大実験", { _ in NS4.zoomExperiment() }),
            ("NS3_本物の4D・排水口（渦）", { let E = ProcessInfo.processInfo.environment; $0.waterRainbow = E["NSRB"] != nil; $0.waterNSRes = Int(E["NSRES"] ?? "") ?? $0.waterNSRes; if let sw = E["NSSW"] { $0.waterSwirl = Double(sw) ?? 0.3 }; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int((Double(E["NST"] ?? "17.5") ?? 17.5) * 60) { $0.waterTick(1.0 / 60) }; if let ns = $0.ns4, ns.phiShow.count == ns.MM { var a0 = 0, a1 = 0; for k in 0..<ns.N { for j in 0..<ns.N { for i in 0..<ns.N { let id = ns.at(i, j, k, 0); if ns.phiDisp[id] >= 0 { a0 += 1 }; if ns.phiShow[id] >= 0 { a1 += 1 } } } }; print("床の空気のマス：井戸なし \(a0)・井戸あり \(a1)") }
                print(String(format: "井戸：深さ %.2f・強さ %.2f・水 %.0f%%", $0.ns4?.well.x ?? 0, $0.nsWellK, 100 * ($0.ns4?.lastVol ?? 0) / (16 * pow(OrigamiState.half, 4))))
                if let ns = $0.ns4, ns.extended { print("上下の筋：上 \(ns.upperStream.count) 層・下 \(ns.lowerStream.count) 層・穴の半分の幅 \(ns.par.hole)・出ていく量 \(String(format: "%.3f", ns.lastOutflow))・" + ns.lowerStream.prefix(4).map { String(format: "w%.2f r%.3f", $0.w, $0.r) }.joined(separator: " ")) } }),
            ("NS4_本物の4D・底を全部開けて落ちる", { $0.drainMode = 0; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(15.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("NS5_本物の4D・排水口・リアルでない図", { $0.drainMode = 1; $0.waterReal = false; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(17.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("FR1_遊ぶ・ふたを下へ傾けてこぼす", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0.3; $0.ay = 0.2; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterLidSet = true; $0.waterNSRes = 24; $0.updateMats(); $0.waterFreeFill(0); for n in 0..<150 { $0.ay = 0.2 + 2.6 * Double(n) / 150; $0.updateMats(); $0.waterTick(1.0 / 60) } }),
            ("FR3_遊ぶ・ななめのジョッキに上から注ぐ", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0; $0.ay = -0.95; $0.xz = 0.45; $0.yz = -0.25; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterLidSet = true; $0.waterNSRes = 24; $0.waterPourX = 0; $0.waterPourY = 0; $0.waterPourZ = 0; $0.updateMats(); $0.waterFreeFill(-1); $0.waterPourHold = true; for _ in 0..<240 { $0.waterTick(1.0 / 60) } }),
            ("FR4_遊ぶ・画面の奥の重力・ためて傾ける", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0; $0.ay = 0; $0.xz = 0.35; $0.yz = -0.3; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterGravMode = 0; $0.waterLidSet = true; $0.waterNSRes = 24; $0.tween = nil; $0.updateMats(); $0.waterFreeFill(-1); for n in 0..<330 { $0.waterPourHold = n < 240; if n >= 240 { $0.ay = Double(n - 240) / 90 * 1.4; $0.updateMats() }; $0.waterTick(1.0 / 60) } }),
            ("FR5_遊ぶ・画面の下の重力・左も傾く", { $0.progress = 1; $0.ax = 0.55; $0.ay = -0.75; $0.xz = 0.6; $0.yz = -0.45; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterGravMode = 1; $0.waterLidSet = false; $0.waterNSRes = 16; $0.tween = nil; $0.updateMats(); $0.waterFreeFill(0); for _ in 0..<200 { $0.waterTick(1.0 / 60) } }),
            ("FR6_遊ぶ・+W→−W・左は z の下", { $0.progress = 1; $0.ax = 0.55; $0.ay = -0.75; $0.xz = 0.6; $0.yz = -0.45; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterGravMode = 2; $0.waterLidSet = false; $0.waterNSRes = 16; $0.tween = nil; $0.updateMats(); $0.waterFreeFill(0); for _ in 0..<200 { $0.waterTick(1.0 / 60) } }),
            ("FR7_遊ぶ・画面の奥の重力・左も", { $0.progress = 1; $0.ax = 0.55; $0.ay = -0.75; $0.xz = 0.6; $0.yz = -0.45; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterGravMode = 0; $0.waterLidSet = false; $0.waterNSRes = 16; $0.tween = nil; $0.updateMats(); $0.waterFreeFill(0); for _ in 0..<200 { $0.waterTick(1.0 / 60) } }),
            ("ND2_設定どおり・場面の移り", { let E = ProcessInfo.processInfo.environment; $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = E["NS"] != "0"; $0.waterNSRes = 16; $0.drainMode = Int(E["DM"] ?? "1") ?? 1; $0.holeShow = 1; $0.holesOpenSet = E["HO"] == "1"; $0.waterVent = E["VENT"] == "1"; $0.intLidMode = Int(E["LID"] ?? "2") ?? 2; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                var T = 0.0, last = -1, log: [String] = []
                let ns = $0.waterNS ? $0.ns4Get() : nil
                func vol() -> Double { (ns?.lastVol ?? 0) / (16 * pow(0.9, 4)) * 100 }
                while T < 60 {
                    $0.waterTick(1.0 / 60); T += 1.0 / 60
                    let ph = $0.waterPhase
                    if ph != last { log.append(String(format: "%d@%.1f(V%.0f%% h%.2f)", ph, T, vol(), $0.waterH)); last = ph }
                    if Int(T * 60) % 180 == 0 { log.append(String(format: "  [%.0f秒 t%.1f V%.1f%% h%.2f out%@ blid%.2f]", T, $0.waterT, vol(), $0.waterH, $0.waterOut == nil ? "なし" : "あり", $0.waterBLid)) }
                }
                print("ND2：" + log.joined(separator: " "))
            }),
            ("NW1_波立ちくらべ（NWFREE 手で・NWG 重力の倍率・NWH 重さ・NWRES）", { (st: OrigamiState) in
                let E = ProcessInfo.processInfo.environment, free = E["NWFREE"] != nil
                st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = Int(E["NWRES"] ?? "12") ?? 12; st.drainMode = 1; st.waterFree = free; st.waterGravMode = 2
                st.waterHeavy = Double(E["NWH"] ?? "0.5") ?? 0.5; st.waterSyrup = Double(E["NSSY"] ?? "0") ?? 0; if E["NWBALL"] != nil { st.inSphere = true; st.inSphereAppear = 1 }; st.waterRainbow = E["NSRB"] != nil; if let g = E["NWGG"] { st.waterG = Double(g) ?? 9.8 }; if let r = E["NWR"] { st.waterPourRate = Double(r) ?? 1 }; st.waterPourForce = Double(E["NWF"] ?? "0.5") ?? 0.5; st.tween = nil; st.updateMats()
                OrigamiState.nsGTestK = Double(E["NWG"] ?? "1") ?? 1
                guard let ns = st.ns4Get() else { return }
                if free { st.waterPourHold = true }
                let turn = E["NWVIEW"] != nil, spin = E["NWSPIN"] != nil      // ▶ はじめる の見る向き（Y‐W を 90° 回す）・回し続ける（X‐W）
                if turn { st.intView = 2; st.intApplyView(2) }
                if spin { st.spinX = true }
                var T = 0.0, log: [String] = []
                while T < (Double(E["NWT"] ?? "8") ?? 8) {
                    if turn || spin { st.tickView(1.0 / 60); if spin { st.ax += 0.6 / 60 }; st.updateMats() }
                    st.waterTick(1.0 / 60); T += 1.0 / 60
                    if Int((T * 60).rounded()) % 60 == 0 {
                        // 水面のでこぼこ：柱ごとの水面の高さ（マスの単位）の、ばらつき（標準偏差）。注ぐ所のまわり（筋の太さの 2 倍）は除く
                        let N = ns.N, jc = ns.par.jetC, jr = ns.par.jetR * 2
                        var sum = 0.0, sq = 0.0, cnt = 0.0
                        for k in 0..<N { for j in 0..<N { for i in 0..<N {
                            if simd_length(SIMD3<Float>(Float(i) + 0.5, Float(j) + 0.5, Float(k) + 0.5) - SIMD3(jc.x, jc.y, jc.z)) < jr { continue }
                            let h = Double(ns.surfaceW(i, j, k)); sum += h; sq += h * h; cnt += 1
                        } } }
                        let m = sum / max(1, cnt), sd = (max(0, sq / max(1, cnt) - m * m)).squareRoot()
                        log.append(String(format: "%.0f秒 %.0f%% でこぼこ%.2f", T, 100 * ns.lastVol / ns.capVolCompat, sd))
                        if E["NWLAYER"] != nil {
                            // 高さ（w の層）ごとの水のマスの割合（下 → 上）
                            let f = ns.phi.contents().bindMemory(to: Float.self, capacity: ns.MM)
                            var row: [String] = []
                            for l in 0..<N { var c = 0; for k in 0..<N { for j in 0..<N { for i in 0..<N { if f[ns.at(i, j, k, l)] < 0 { c += 1 } } } }; row.append(String(format: "%.0f", 100 * Double(c) / Double(N * N * N))) }
                            // ふた（+w の胞）が水に描かれる割合：前の描き方（3 層の平均）と今の描き方（かべの所まで のばす）
                            var cAvg = 0, cExt = 0
                            for k in 0..<N { for j in 0..<N { for i in 0..<N { let a0 = f[ns.at(i, j, k, N - 1)], a1 = f[ns.at(i, j, k, N - 2)], a2 = f[ns.at(i, j, k, N - 3)]; if (a0 + a1 + a2) / 3 < 0 { cAvg += 1 }; if 1.5 * a0 - 0.5 * a1 < 0 { cExt += 1 } } } }
                            log.append("層[" + row.joined(separator: " ") + "] 入れ口l" + String(format: "%.0f ふたの水 前%.0f%% 今%.0f%%", ns.par.jetC.w, 100 * Double(cAvg) / Double(N * N * N), 100 * Double(cExt) / Double(N * N * N)))
                        } }
                }
                print("波立ちくらべ（" + (free ? "手で" : "自動") + "）：" + log.joined(separator: "・")) }),
            ("PS1_一時停止中にマウスで回すと水がゆれる（数字）", { (st: OrigamiState) in
                st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 12; st.drainMode = 1; st.waterFree = false; st.tween = nil; st.updateMats()
                guard let ns = st.ns4Get() else { return }
                for _ in 0..<(5 * 60) { st.waterTick(1.0 / 60) }
                st.intPaused = true
                for _ in 0..<(3 * 60) { st.waterTick(1.0 / 60) }
                let v0 = ns.maxSpeed()
                for k in 0..<45 { let m = [1.0, 0, 2, 1, 1, 0, 2][k % 7]; st.drag(.r3x, 0.02 * m); st.updateMats(); st.waterTick(1.0 / 60) }
                let v1 = ns.maxSpeed()
                for _ in 0..<(3 * 60) { st.waterTick(1.0 / 60) }
                print(String(format: "一時停止中のゆれ：止めて 3 秒 いちばん速い %.3f → マウスで回した直後 %.3f → 3 秒後 %.3f", v0, v1, ns.maxSpeed())) }),
            ("VB1_マス目の切りかえの重さ", { (st: OrigamiState) in
                guard let a = NS4(N: 8) else { return }; a.reset(level: 0.4)
                let t0 = CACurrentMediaTime(); guard let b = NS4(N: 12) else { return }; let t1 = CACurrentMediaTime()
                b.copyResampled(from: a); let t2 = CACurrentMediaTime()
                a.copyResampled(from: b); let t3 = CACurrentMediaTime()
                print(String(format: "切りかえの重さ：12⁴ を作る %.1f ミリ秒・8⁴→12⁴ 写す %.1f ミリ秒・12⁴→8⁴ 写す %.1f ミリ秒・体積 8⁴ %.3f 12⁴ %.3f", (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, a.lastVol, b.lastVol)) }),
            ("WP1_水を描く重さ（WPRES・WPT 秒）", { (st: OrigamiState) in
                let E = ProcessInfo.processInfo.environment
                st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = Int(E["WPRES"] ?? "16") ?? 16; st.drainMode = 1; st.waterFree = false; st.tween = nil; st.updateMats()
                NS4.syncAll = true
                guard let ns = st.ns4Get(), let d = MTLCreateSystemDefaultDevice(), let r = OrigamiRenderer(n: 4, state: st, device: d) else { return }
                let T = Double(E["WPT"] ?? "3") ?? 3
                for _ in 0..<Int(T * 60) { st.waterTick(1.0 / 60) }
                let t0 = CACurrentMediaTime(); let m = ns.buildMesh(ns.phiCPU); let t1 = CACurrentMediaTime()
                var rods: [TLRod] = []; var nTri = 0
                let t2 = CACurrentMediaTime(); for _ in 0..<5 { rods = []; let b = r.waterGeometry(&rods, eye: SIMD3(0, 0, 9)); nTri = b.reduce(0) { $0 + $1.verts.count / 3 } }; let t3 = CACurrentMediaTime()
                _ = ns.thicknessField(axis: 3); let t4 = CACurrentMediaTime(); _ = ns.thicknessField(axis: 0); let t5 = CACurrentMediaTime()
                print(String(format: "水を描く重さ（%d⁴・%.0f 秒）：水面を作る %.1f ミリ秒（三角形 %d）・描く形 1 回 %.1f ミリ秒（三角形 %d）・厚み %.1f ミリ秒・泡 %d", ns.N, T, (t1 - t0) * 1000, m.kind.count, (t3 - t2) * 200, nTri, (t5 - t4) * 1000, st.nsBubbles.count))
                print(ns.fineDetailStats())
                NS4.syncAll = false }),
            ("ND3_遊ぶ・底を開けて抜く", { let E = ProcessInfo.processInfo.environment; $0.progress = 1; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = Int(E["DM"] ?? "1") ?? 1; $0.waterFree = true; $0.waterGravMode = Int(E["GM"] ?? "1") ?? 1; $0.waterLidSet = true; $0.waterBottomSet = false; $0.tween = nil; $0.ay = $0.waterFreeAY(0); $0.xz = 0; $0.yz = 0; $0.updateMats()
                guard let ns = $0.ns4Get() else { return }
                $0.waterFreeFill(0.4); var T = 0.0, log: [String] = []
                for _ in 0..<60 { $0.waterTick(1.0 / 60) }
                $0.waterBottomSet = true
                while T < 60 {
                    $0.waterTick(1.0 / 60); T += 1.0 / 60
                    if Int(T * 60) % 120 == 0 { log.append(String(format: "[%.0f秒 V%.2f%% 出%.4f ph%d g(%.2f,%.2f,%.2f,%.2f)]", T, 100 * ns.lastVol / (16 * pow(0.9, 4)), ns.lastOutflow, $0.waterPhase, $0.waterGDir.x, $0.waterGDir.y, $0.waterGDir.z, $0.waterGDir.w)) }
                }
                print("ND3：" + log.joined(separator: " "))
            }),
            ("VX1_渦・浅水・抜き始め", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; if let a = ProcessInfo.processInfo.environment["VXA"], let b = ProcessInfo.processInfo.environment["VXB"] { $0.ax = (Double(a) ?? 0) * .pi / 180; $0.ay = (Double(b) ?? 0) * .pi / 180 }; if ProcessInfo.processInfo.environment["VXSIDE"] == "1" { $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1 }; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterSwirl = 0.42; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 60 && !($0.waterPhase == 4 && $0.waterH < 0.4) { $0.waterTick(1.0 / 60); n += 1 }
                for _ in 0..<20 { $0.waterTick(1.0 / 60) }; print(String(format: "渦の確かめ：h %.2f  vd %.3f  渦の強さ %.2f", $0.waterH, $0.waterVD, $0.waterSwirl)) }),
            ("VX2_渦・浅水・浅い", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; if let a = ProcessInfo.processInfo.environment["VXA"], let b = ProcessInfo.processInfo.environment["VXB"] { $0.ax = (Double(a) ?? 0) * .pi / 180; $0.ay = (Double(b) ?? 0) * .pi / 180 }; if ProcessInfo.processInfo.environment["VXSIDE"] == "1" { $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1 }; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterSwirl = 0.42; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 60 && !($0.waterPhase == 4 && $0.waterH < -0.6) { $0.waterTick(1.0 / 60); n += 1 }
                for _ in 0..<20 { $0.waterTick(1.0 / 60) }; print(String(format: "渦の確かめ：h %.2f  vd %.3f  渦の強さ %.2f", $0.waterH, $0.waterVD, $0.waterSwirl)) }),
            ("VX3_渦・本物の水・半分", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; if let a = ProcessInfo.processInfo.environment["VXA"], let b = ProcessInfo.processInfo.environment["VXB"] { $0.ax = (Double(a) ?? 0) * .pi / 180; $0.ay = (Double(b) ?? 0) * .pi / 180 }; if ProcessInfo.processInfo.environment["VXSIDE"] == "1" { $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1 }; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterSwirl = 0.42; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 60 && !($0.waterPhase == 4 && $0.waterH < 0.0) { $0.waterTick(1.0 / 60); n += 1 }
                for _ in 0..<20 { $0.waterTick(1.0 / 60) }; print(String(format: "渦の確かめ：h %.2f  vd %.3f  渦の強さ %.2f", $0.waterH, $0.waterVD, $0.waterSwirl)) }),
            ("VX4_渦・本物の水・浅い", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; if let a = ProcessInfo.processInfo.environment["VXA"], let b = ProcessInfo.processInfo.environment["VXB"] { $0.ax = (Double(a) ?? 0) * .pi / 180; $0.ay = (Double(b) ?? 0) * .pi / 180 }; if ProcessInfo.processInfo.environment["VXSIDE"] == "1" { $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1 }; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterSwirl = 0.42; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 60 && !($0.waterPhase == 4 && $0.waterH < -0.7) { $0.waterTick(1.0 / 60); n += 1 }
                for _ in 0..<20 { $0.waterTick(1.0 / 60) }; print(String(format: "渦の確かめ：h %.2f  vd %.3f  渦の強さ %.2f", $0.waterH, $0.waterVD, $0.waterSwirl)) }),
            ("CP1_ちゃぷちゃぷ・浅水", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 40 && !($0.waterPhase == 2) { $0.waterTick(1.0 / 60); n += 1 }
                let st = $0; func rms() -> Double { var s = 0.0; for e in st.swe.eta { s += Double(e * e) }; return sqrt(s / Double(st.swe.eta.count)) }
                let r0 = rms()
                for k in 0..<30 { $0.ay = 17 * .pi / 180 + 1.2 * Double(k) / 30; $0.updateMats(); $0.waterTick(1.0 / 60) }
                let r1 = rms(); for _ in 0..<12 { $0.waterTick(1.0 / 60) }
                print(String(format: "ちゃぷちゃぷ：回す前 %.4f → 回した直後 %.4f → 0.2 秒後 %.4f（η の RMS）", r0, r1, rms())) }),
            ("CP3_マウスでゆさぶる・浅水（荒れの数字）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 40 && !($0.waterPhase == 2) { $0.waterTick(1.0 / 60); n += 1 }
                let tHold = $0.waterT, st = $0
                // 荒れ：となりとの差（格子の細かいでこぼこ）の RMS と、全体のゆれ（η の RMS）。4D の水面（3D の格子）と左の 3D の水面（2D の格子）
                func rough() -> String {
                    let N = WaterSWE.N, M = WaterSWE.M; var a = 0.0, b = 0.0, c = 0.0, d = 0.0
                    for i in 1..<(N - 1) { for j in 1..<(N - 1) { for k in 1..<(N - 1) { let q = (i * N + j) * N + k, e = st.swe.eta; let hp = Double(e[q]) - Double(e[q - 1] + e[q + 1] + e[q - N] + e[q + N] + e[q - N * N] + e[q + N * N]) / 6; a += hp * hp; b += Double(e[q] * e[q]) } } }
                    for i in 1..<(M - 1) { for j in 1..<(M - 1) { let q = i * M + j, e = st.swe.e2; let hp = Double(e[q]) - Double(e[q - 1] + e[q + 1] + e[q - M] + e[q + M]) / 4; c += hp * hp; d += Double(e[q] * e[q]) } }
                    let n3 = Double((N - 2) * (N - 2) * (N - 2)), n2 = Double((M - 2) * (M - 2))
                    return String(format: "4D でこぼこ %.4f ゆれ %.4f ｜ 3D でこぼこ %.4f ゆれ %.4f", sqrt(a / n3) * 1000, sqrt(b / n3) * 1000, sqrt(c / n2) * 1000, sqrt(d / n2) * 1000)
                }
                print("ゆさぶる前　 " + rough())
                // 1.5 秒ドラッグ：マウスの知らせはコマごとに 0・1・2 回とばらつく（1 回 0.012 ラジアン）。横と縦をまぜて
                for k in 0..<90 { let m = [1.0, 0, 2, 1, 1, 0, 2][k % 7]; st.drag(.r3x, 0.012 * m); if k % 3 == 0 { st.drag(.r3y, 0.008 * m) }; st.waterT = tHold; st.waterTick(1.0 / 60) }
                print("止めた時　　 " + rough())
                for sec in [0.5, 1.0, 2.0, 3.0] { var t = 0.0; while t < 0.5 - 1e-9 || (sec > 1 && t < 1 - 1e-9) { st.waterT = tHold; st.waterTick(1.0 / 60); t += 1.0 / 60 }; print(String(format: "止めて %.1f 秒 ", sec) + rough()) }
            }),
            ("GV1_好きな向きの重力・浅水（傾き）", { let E = ProcessInfo.processInfo.environment; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = E["NS"] == "1"; $0.waterNSRes = 16; $0.drainMode = 0; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                $0.waterGravMode = 3; let deg = Double(E["GDEG"] ?? "") ?? 30; $0.gravSet(SIMD4(sin(deg * .pi / 180), 0, 0, -cos(deg * .pi / 180)))
                var n = 0; while n < 60 * 40 && !($0.waterPhase == 2) { $0.waterTick(1.0 / 60); n += 1 }
                let tHold = $0.waterT, st = $0; for _ in 0..<120 { st.waterT = tHold; st.waterTick(1.0 / 60) }
                // 水面の傾き：4D の水面（x の −側と＋側の η の平均）・左の 3D の水面
                let N = WaterSWE.N, M = WaterSWE.M; var lo = 0.0, hi = 0.0, l2 = 0.0, h2 = 0.0
                for i in 0..<N { for j in 0..<N { for k in 0..<N { let e = Double(st.swe.eta[(i * N + j) * N + k]); if i < N / 4 { lo += e } else if i >= 3 * N / 4 { hi += e } } } }
                for i in 0..<M { for j in 0..<M { let e = Double(st.swe.e2[i * M + j]); if i < M / 4 { l2 += e } else if i >= 3 * M / 4 { h2 += e } } }
                let q3 = Double(N * N * N / 4), q2 = Double(M * M / 4), H = OrigamiState.half
                print(String(format: "重力 %.0f°（実際 %.1f°）：4D の水面 x−側 %+.3f・x＋側 %+.3f（H の何倍）｜3D x−側 %+.3f・x＋側 %+.3f｜つり合いの傾きなら ±%.3f くらい", deg, st.gravTiltDeg, lo / q3 / H, hi / q3 / H, l2 / q2 / H, h2 / q2 / H, tan(min(deg, 35) * .pi / 180) * 0.75))
                // ハンドルのドラッグ：先の玉が指についてくるか（窓 900×860）
                let sz = CGSize(width: 900, height: 860), s0 = st.gravScreen(4, st.gravHandlePts(4).1, size: sz)!
                for _ in 0..<5 { st.gravDrag(4, 6, 0, alt: false, size: sz) }
                let s1 = st.gravScreen(4, st.gravHandlePts(4).1, size: sz)!
                print(String(format: "ハンドル：右へ 30 ポイント動かす → 玉は (%+.1f, %+.1f) 動いた・傾き %.1f°", s1.x - s0.x, s1.y - s0.y, st.gravTiltDeg))
                for _ in 0..<40 { st.gravDrag(4, 0, 12, alt: false, size: sz) }
                print(String(format: "下へうんと動かす → 傾き %.1f°（35° で止まるはず）", st.gravTiltDeg))
                // w のメーターの輪：輪の右はしをつかんで外へ → w が増える（傾きが大きくなる）、内へ → −w へ戻る
                st.gravSet(SIMD4(sin(0.2), 0, 0, -cos(0.2)))
                let (o4, _) = st.gravHandlePts(4), c4 = st.gravScreen(4, o4, size: sz)!, e4 = st.gravScreen(4, o4 + SIMD3(st.gravRingR(), 0, 0), size: sz)!
                let hitR = st.gravHit(4, CGPoint(x: 2 * c4.x - e4.x, y: c4.y), size: sz), w0 = st.gravDown.w   // 輪の左はし（矢印の先と重ならない側）
                for _ in 0..<5 { st.gravDrag(4, -4, 0, alt: false, size: sz) }
                let w1 = st.gravDown.w; for _ in 0..<30 { st.gravDrag(4, 6, 0, alt: false, size: sz) }
                print(String(format: "輪をつかめた %@・半径 %.0f ポイント：w %.3f → 外へ %.3f → 内へ %.3f（傾き %.1f°）", hitR && st.gravGrabW ? "○" : "×", hypot(e4.x - c4.x, e4.y - c4.y), w0, w1, st.gravDown.w, st.gravTiltDeg))
                st.gravGrab = false; st.gravGrabW = false; st.gravSet(SIMD4(sin(0.5), 0, 0, -cos(0.5)))
            }),
            ("SH1_4 次元の立体（SHK 立体・SHC 切る位置・SHSEC 断面）", { let E = ProcessInfo.processInfo.environment; $0.progress = 1; $0.ax = (Double(E["VXA"] ?? "") ?? 25) * .pi / 180; $0.ay = (Double(E["VXB"] ?? "") ?? 15) * .pi / 180; $0.xz = 0.35; $0.yz = -0.25; $0.spaceMode = 2; $0.shapeOn = E["SHOFF"] == nil; $0.shapeKind = Int(E["SHK"] ?? "3") ?? 3; $0.shapeCut = Double(E["SHC"] ?? "0") ?? 0; $0.shapeMainProj = E["SHSEC"] != nil; $0.shapeShadowMode = Int(E["SHMODE"] ?? "0") ?? 0; $0.tween = nil; $0.updateMats(); let t0 = CACurrentMediaTime(); let m = $0.shapeSection(); let t1 = CACurrentMediaTime(); _ = $0.shapeLayers(); let t2 = CACurrentMediaTime(); print(String(format: "立体の確かめ：断面 %d 三角形 %.0f ミリ秒・影の輪切り %.0f ミリ秒", m.p.count / 3, (t1 - t0) * 1000, (t2 - t1) * 1000)) }),
            ("ST1_まっすぐ", { (st: OrigamiState) in st.progress = 1; st.ax = 0.4; st.ay = 0.3; st.xy = 0.5; st.xz = 0.3; st.yz = -0.2; st.spaceMode = 2; st.tween = nil; st.updateMats(); st.straighten(); for _ in 0..<40 { st.tickView(1.0 / 60) }; st.updateMats()
                var a: [String] = []
                for k in 0..<4 { let v = SIMD2<Double>(st.m4[k][0], st.m4[k][1]); a.append(String(format: "%@ %.1f°（長さ %.2f）", ["x", "y", "z", "w"][k], atan2(v.y, v.x) * 180 / Double.pi, simd_length(v))) }
                print("まっすぐの確かめ：" + a.joined(separator: "・")) }),
            ("PD1_水玉（PDT 秒・DM 抜き方）", { let E = ProcessInfo.processInfo.environment; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = (Double(E["VXA"] ?? "") ?? 29) * .pi / 180; $0.ay = (Double(E["VXB"] ?? "") ?? 17) * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.drainMode = Int(E["DM"] ?? "0") ?? 0; $0.holeShow = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset(); let T = Double(E["PDT"] ?? "") ?? 1.6; for _ in 0..<Int(T * 60) { $0.waterTick(1.0 / 60) }; $0.holeDA = $0.holeDTarget; print(String(format: "水玉の確かめ：%.1f 秒・場面 %d・水位 h %.3f", T, $0.waterPhase, $0.waterH)) }),
            ("CP2_ちゃぷちゃぷ・本物の水", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats(); $0.waterT = 0; $0.swe.reset()
                var n = 0; while n < 60 * 40 && !($0.waterPhase == 2) { $0.waterTick(1.0 / 60); n += 1 }
                let st = $0; func rms() -> Double { var s = 0.0; for e in st.swe.eta { s += Double(e * e) }; return sqrt(s / Double(st.swe.eta.count)) }
                let r0 = rms()
                for k in 0..<30 { $0.ay = 17 * .pi / 180 + 1.2 * Double(k) / 30; $0.updateMats(); $0.waterTick(1.0 / 60) }
                let r1 = rms(); for _ in 0..<12 { $0.waterTick(1.0 / 60) }
                print(String(format: "ちゃぷちゃぷ：回す前 %.4f → 回した直後 %.4f → 0.2 秒後 %.4f（η の RMS）", r0, r1, rms())) }),
            ("ND1_本物の水・排水口で抜く時間", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = Int(ProcessInfo.processInfo.environment["NDRES"] ?? "16") ?? 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                var T = 0.0, tPour = -1.0, tOpen = -1.0, tEmpty = -1.0, last = -1, log: [String] = []
                guard let ns = $0.ns4Get() else { return }
                while T < 90 {
                    let dtJ = ProcessInfo.processInfo.environment["NDJIT"] != nil ? (Int(T * 997) % 2 == 0 ? 1.0 / 45 : 1.0 / 90) : 1.0 / 60   // NDJIT：コマの長さをばらつかせる（アプリと同じ）
                    $0.waterTick(dtJ); T += dtJ
                    let ns = $0.ns4 ?? ns                                       // マス目の VBR で切りかわったら、新しい水を読む
                    let ph = $0.waterPhase
                    if ph != last { log.append(String(format: "%d@%.1f(%.0f%%)", ph, T, 100 * ns.lastVol / (16 * pow(0.9, 4)))); last = ph }
                    if ph == 1 && tPour < 0 { tPour = T }
                    if ph == 4 && tOpen < 0 { tOpen = T }
                    if tOpen > 0 && ph >= 5 && tEmpty < 0 { tEmpty = T }
                    if tEmpty > 0 && ph == 1 { log.append(String(format: "→ 次に注ぐまで %.1f 秒", T - tEmpty)); break }
                    if tOpen > 0 && Int(T * 60) % 120 == 0 { log.append(String(format: "  %.0f秒 %.1f%%", T - tOpen, 100 * ns.lastVol / (16 * pow(0.9, 4)))) }
                }
                print("排水口：場面の移り " + log.joined(separator: " "))
                print(String(format: "排水口（%d⁴）：開けてから空になるまで %.1f 秒（浅水の水は %.1f 秒）", ns.N, tEmpty - tOpen, $0.wDrainHoleT))
                // 1 歩にかかる本当の時間（画面では 1 歩 最大 1/30 秒しか進めないので、これが 1/30 秒より長いと、水の時間が実際よりゆっくりになる）
                let c0 = CACurrentMediaTime(); for _ in 0..<30 { $0.waterTick(1.0 / 60) }
                print(String(format: "排水口（%d⁴）：1 歩 %.1f ミリ秒", ns.N, (CACurrentMediaTime() - c0) / 30 * 1000)) }),
            ("PZ2_本物の水・注ぐ途中で止めても減らない", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                guard let ns = $0.ns4Get() else { return }
                var n = 0
                while ($0.waterPhase != 1 || $0.waterH < 0) && n < 60 * 30 { $0.waterTick(1.0 / 60); n += 1 }
                for _ in 0..<30 { $0.waterTick(1.0 / 60) }
                $0.intPaused = true
                for _ in 0..<20 { $0.waterTick(1.0 / 60) }
                let v0 = ns.lastVol
                for _ in 0..<(60 * 20) { $0.waterTick(1.0 / 60) }
                print(String(format: "本物の水：止めて 20 秒で 水の量 %.3f → %.3f（%+.1f%%）", v0, ns.lastVol, 100 * (ns.lastVol - v0) / v0)) }),
            ("NV4_本物の水・排水口で残り 4%", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                guard let ns = $0.ns4Get() else { return }
                var n = 0
                while n < 60 * 40 && !($0.waterPhase == 4 && ns.lastVol / (16 * pow(0.9, 4)) < 4 * 0.01) { $0.waterTick(1.0 / 60); n += 1 } }),
            ("NV2_本物の水・排水口で残り 2%", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                guard let ns = $0.ns4Get() else { return }
                var n = 0
                while n < 60 * 40 && !($0.waterPhase == 4 && ns.lastVol / (16 * pow(0.9, 4)) < 2 * 0.01) { $0.waterTick(1.0 / 60); n += 1 } }),
            ("NV1_本物の水・排水口で残り 1%", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.drainMode = 1; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                guard let ns = $0.ns4Get() else { return }
                var n = 0
                while n < 60 * 40 && !($0.waterPhase == 4 && ns.lastVol / (16 * pow(0.9, 4)) < 1 * 0.01) { $0.waterTick(1.0 / 60); n += 1 } }),
            ("PZ1_一時停止・注ぐ途中で止めて静かに", { $0.progress = 1; $0.ax = 0.5; $0.ay = 0.35; $0.xz = 0; $0.yz = 0; $0.intOn = true; $0.intMethod = 1; $0.waterNS = false; $0.waterFree = false; $0.tween = nil; $0.updateMats()
                while $0.waterPhase != 1 || $0.waterH < -0.2 { $0.waterTick(1.0 / 60) }
                func amp(_ s: OrigamiState) -> Float { sqrt(s.swe.eta.reduce(0) { $0 + $1 * $1 } / Float(s.swe.eta.count)) }   // 波の高さ（ならした大きさ）
                let a0 = amp($0), h0 = $0.waterH, t0 = $0.waterT
                $0.intPaused = true
                for _ in 0..<40 { $0.waterTick(1.0 / 60) }
                let a1 = amp($0)
                for _ in 0..<200 { $0.waterTick(1.0 / 60) }
                print(String(format: "一時停止：波の高さ %.4f → %.4f → %.4f（静かになる）・水位 %.3f → %.3f（増えない）・時計 %.2f → %.2f（止まる）・筋のしっぽ %.2f", a0, a1, amp($0), h0, $0.waterH, t0, $0.waterT, $0.waterPour))
                $0.intPaused = false; $0.waterPauseT = 0
                $0.intPaused = true; for _ in 0..<20 { $0.waterTick(1.0 / 60) } }),
            ("SL1_輪切り z・注いでいる", { $0.waterSlice = 3; $0.waterSlicePos = 0.2; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(6.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("SL2_輪切り z・排水口で抜く", { $0.waterSlice = 3; $0.waterSlicePos = 0.05; $0.drainMode = 1; $0.waterSwirl = 0.6; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.6 * 60) { $0.waterTick(1.0 / 60) } }),
            ("OUT1_出る水・本物の4D・排水口", { $0.waterNS = true; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("OUT2_出る水・浅水・排水口", { $0.waterNS = false; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("OUT3_出る水・底を全部（かたまり）", { $0.waterNS = false; $0.drainMode = 0; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(15.2 * 60) { $0.waterTick(1.0 / 60) } }),
            ("OUT4_出る水・本物の4D・排水口・横から", { $0.waterNS = true; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("OUT5_出る水・底を全部・横から", { $0.waterNS = false; $0.drainMode = 0; $0.progress = 1; $0.spaceMode = 2; $0.ax = .pi / 2; $0.ay = 0; $0.zw = 0; $0.xy = 0; $0.xz = 0.35; $0.yz = -0.3; $0.projBlend = 1; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(15.2 * 60) { $0.waterTick(1.0 / 60) } }),
            ("YL1_黄色い線（排水口・横から y）", { $0.waterNS = true; $0.drainMode = 1; $0.progress = 1; $0.spaceMode = 2; $0.ax = 0; $0.ay = .pi / 2; $0.zw = 0; $0.xy = 0; $0.xz = 0.45; $0.yz = -0.2; $0.projBlend = 1; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("YL2_黄色い線（排水口・横から y・輪切り z）", { $0.waterNS = true; $0.drainMode = 1; $0.waterSlice = 3; $0.progress = 1; $0.spaceMode = 2; $0.ax = 0; $0.ay = .pi / 2; $0.zw = 0; $0.xy = 0; $0.xz = 0.45; $0.yz = -0.2; $0.projBlend = 1; $0.updateMats(); $0.intOn = true; $0.intMethod = 1; $0.waterNSRes = 16; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(16.0 * 60) { $0.waterTick(1.0 / 60) } }),
            ("BL1_玉を詰める・どんどん", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 2; $0.ballsAuto = true; for _ in 0..<Int(9.0 * 60) { $0.ballsTick(1.0 / 60) } }),
            ("BL2_玉・角に16個と真ん中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 2; $0.ballsCorners(); for _ in 0..<60 { $0.ballsTick(1.0 / 60) } }),
            ("BL3_玉1つ・+x の壁に接する", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 2; $0.ballR = 0.45; $0.balls4.clear(); $0.balls3.clear(); $0.balls4.g = 0; $0.balls3.g = 0; let H = OrigamiState.half, r = 0.45 * H; $0.balls4.r = r; $0.balls3.r = r; $0.balls4.p = [SIMD4(H - r, 0, 0, 0)]; $0.balls4.v = [.zero]; $0.balls4.hue = [0.3]; $0.balls4.rad = [r]; $0.balls3.p = [SIMD4(H - r, 0, 0, 0)]; $0.balls3.v = [.zero]; $0.balls3.hue = [0.3]; $0.balls3.rad = [r] }),
            ("BL4_玉・重力 画面の下", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 2; $0.ballGravMode = 1; $0.ballsAuto = true; for _ in 0..<Int(8.0 * 60) { $0.ballsTick(1.0 / 60) } }),
            ("BL5_玉・無重力", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 0.5; $0.ay = 0.3; $0.updateMats(); $0.intOn = true; $0.intMethod = 2; $0.ballG = 0; for i in 0..<12 { $0.ballsDropOne(); for _ in 0..<20 { $0.ballsTick(1.0 / 60) }; _ = i } }),
            ("FR2_遊ぶ・注いでいる", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterNS = true; $0.waterFree = true; $0.waterLidSet = true; $0.waterNSRes = 24; $0.updateMats(); $0.waterFreeFill(-0.6); $0.waterPourHold = true; for _ in 0..<120 { $0.waterTick(1.0 / 60) } }),
            ("W4o_水・いっぱい（4D で回した・前の図）", { $0.waterReal = false; $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.3; $0.yz = -0.25; $0.ax = 0.9; $0.ay = 0.4; $0.zw = 0.35; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(11.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("W4e_水なし（4D で回した）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.3; $0.yz = -0.25; $0.ax = 0.9; $0.ay = 0.4; $0.zw = 0.35 }),
            ("W4_水・いっぱい（4D で回した）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.3; $0.yz = -0.25; $0.ax = 0.9; $0.ay = 0.4; $0.zw = 0.35; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(11.5 * 60) { $0.waterTick(1.0 / 60) } }),
            ("W3_水・底から落ちる", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(15.6 * 60) { $0.waterTick(1.0 / 60) } }),
            ("Q4_積分・4 方向から同時・レインボーボール", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 5; $0.intN = 32; $0.intAxes = 15; $0.intT = 4.5; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("Q1_積分・入れる量 50%（いっぱい）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 2; $0.intN = 41; $0.intAmount = 0.5; $0.intT = 6; $0.intItems = $0.intUpdate() }),
            ("Q2_積分・w と x から同時", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 2; $0.intN = 41; $0.intAxes = 9; $0.intT = 3.5; $0.intItems = $0.intUpdate() }),
            ("Q3_積分・4 方向から同時", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 1; $0.intN = 64; $0.intAxes = 15; $0.intT = 3.5; $0.intItems = $0.intUpdate() }),
            ("J1_積分・七色の枠だけ", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 4; $0.intN = 41; $0.intT = 5.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("J2_積分・レインボーボール", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 5; $0.intN = 12; $0.intT = 5.5; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("J3_積分・同心の七色", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 6; $0.intN = 41; $0.intT = 5.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("J4_積分・同心球3Dプリント", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 7; $0.intN = 41; $0.intT = 8.0; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("I1_積分・白・敷きつめ中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 0; $0.intStars = 1; $0.intN = 41; $0.intT = 5.0; $0.intItems = $0.intUpdate() }),
            ("I2_積分・層ごと・いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 1; $0.intStars = 1; $0.intN = 41; $0.intT = 8.0; $0.intItems = $0.intUpdate() }),
            ("I3_積分・七色の縞・敷きつめ中", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 2; $0.intStars = 1; $0.intN = 41; $0.intT = 5.0; $0.intItems = $0.intUpdate() }),
            ("I4_積分・七色の縞・いっぱい", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 2; $0.intStars = 1; $0.intN = 41; $0.intT = 8.0; $0.intItems = $0.intUpdate() }),
            ("I5_積分・ドラゴンボール一星球", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 3; $0.intStars = 1; $0.intN = 12; $0.intT = 5.5; $0.intItems = $0.intUpdate() }),
            ("I6_積分・ドラゴンボール四星球", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intColor = 3; $0.intStars = 4; $0.intN = 12; $0.intT = 6.5; $0.intItems = $0.intUpdate() }),
            ("K1_断面・頂点から −75%（四面体）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false); $0.secOn = true; $0.secPos = -0.75 }),
            ("K2_断面・頂点から −25%（切頂四面体）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false); $0.secOn = true; $0.secPos = -0.25 }),
            ("K3_断面・頂点から 0（八面体）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false); $0.secOn = true; $0.secPos = 0.0 }),
            ("K4_断面・胞から（立方体）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false); $0.secOn = true; $0.secPos = 0.3 }),
            ("K5_断面・辺から 0", { $0.progress = 1; $0.spaceMode = 2; $0.goView(2, animated: false); $0.secOn = true; $0.secPos = 0.0 }),
            ("K6_断面・面から 0", { $0.progress = 1; $0.spaceMode = 2; $0.goView(1, animated: false); $0.secOn = true; $0.secPos = 0.0 }),
            ("K7_断面・ななめに回した形 0.2", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0.7; $0.ay = 0.45; $0.zw = 0.3; $0.secOn = true; $0.secPos = 0.2 }),
            ("L0_線 今まで（賢く 0）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.smartLine = 0 }),
            ("L1_線 賢く 70%", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.smartLine = 0.7 }),
            ("L2_線 賢く 100%", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.smartLine = 1 }),
            ("L3_W回転・線 賢く 70%", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.smartLine = 0.7 }),
            ("A1_軸の矢印（こっちを向く・ずれ 0.0）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.0 }),
            ("A2_軸の矢印（こっちを向く・ずれ 0.06）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.06 }),
            ("A3_軸の矢印（こっちを向く・ずれ 0.12）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.12 }),
            ("A4_軸の矢印（こっちを向く・ずれ 0.18）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.18 }),
            ("A5_軸の矢印（こっちを向く・ずれ 0.26）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.26 }),
            ("A6_軸の矢印（こっちを向く・ずれ 0.4）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 0; $0.ay = 0.4 }),
            ("F6_展開図・表だけ（全部見える）", { $0.progress = 0; $0.spaceMode = 2; $0.goView(3, animated: false); $0.progress = 0; $0.faceSide = 1 }),
            ("F7_組み立て 0.7・表だけ（裏が消えていく）", { $0.progress = 0.7; $0.spaceMode = 2; $0.goView(3, animated: false); $0.progress = 0.7; $0.faceSide = 1 }),
            ("Z1_展開図・z をつぶす（Z-W 90°）", { $0.progress = 0; $0.spaceMode = 2; $0.zw = .pi / 2; $0.xz = 0.3; $0.yz = -0.35 }),
            ("Z2_展開図・z をつぶす（Z-W 90°・少し回す）", { $0.progress = 0; $0.spaceMode = 2; $0.zw = .pi / 2; $0.ax = 0.15; $0.xz = 0.5; $0.yz = -0.2 }),
            ("M1_移動（左は右上へ・右は左下へ 120 ポイント）", { $0.progress = 1; $0.spaceMode = 2; $0.paneWpt = [450, 450]; $0.paneHpt = [430, 430]; $0.panBy(0, 120, -120); $0.panBy(1, -120, 120) }),
            ("S0_やわらかい乗算 0（今までの乗算）", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.softMul = 0 }),
            ("S1_やわらかい乗算 50%", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.softMul = 0.5 }),
            ("S2_やわらかい乗算 100%", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.softMul = 1 }),
            ("S3_W 90°近く・やわらかい乗算 0", { $0.progress = 1; $0.ax = 1.35; $0.ay = 0.25; $0.spaceMode = 2; $0.softMul = 0 }),
            ("S4_W 90°近く・やわらかい乗算 50%", { $0.progress = 1; $0.ax = 1.35; $0.ay = 0.25; $0.spaceMode = 2; $0.softMul = 0.5 }),
            ("P1_点・頂点と辺の中点（組み上がり）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.addAllVertices(); $0.addPt([0.5, 0.3, 0, 0], 0xffffff, "まんなか") }),
            ("P2_点・辺の中点と面の中心（展開図）", { $0.progress = 0; $0.spaceMode = 2; $0.addEdgeMids(); $0.addCellCtrs(); $0.ptLabels = false }),
            ("P3_点・頂点（組み立て0.5）", { $0.progress = 0.5; $0.spaceMode = 2; $0.addAllVertices() }),
            ("P4_点・胞の中心（分解）", { $0.progress = 1; $0.explodeRaw = 1; $0.spaceMode = 2; $0.addCellCtrs(); $0.addW0Slice(); $0.ptSize = 1 }),
            ("0_初め（ウェブ版と同じ正面・宇宙は切）", { $0.spaceMode = 2; $0.xz = 0; $0.yz = 0 }),
            ("0b_初め・展開図", { $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.progress = 0 }),
            ("0c_ウェブ版と同じ角度（X-W 29°・Y-W 17°）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180 }),
            ("0c2_奥の表現なし（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.depth3 = 0; $0.mul4 = 0; $0.glow4 = 0; $0.glass4 = 0; $0.reflSelf = 0; $0.stripK = 0 }),
            ("0c3_4D の手前を光らせる 100%", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.glow4 = 1 }),
            ("0d2_胞から・光の帯なし（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false); $0.stripK = 0 }),
            ("0d3_胞から・色ガラスなし（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false); $0.glass4 = 0 }),
            ("0c4_色ガラスなし（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.glass4 = 0 }),
            ("0c5_線の4D・同じ（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.line4 = 0 }),
            ("0c6_線の4D・奥ほど濃く", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.line4 = 2 }),
            ("0d4_胞から・線の4D・奥ほど濃く", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false); $0.line4 = 2 }),
            ("0c8_辺の強調あり", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.ehOn = true }),
            ("0c9_線を胞の色でなじませる 80%", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.lineTint = 0.8 }),
            ("0c10_パレット（+X を黄・補色モード・軸の色を合わせる）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.pal4["px"] = 0xfacc15; $0.pal3["px"] = 0xfacc15; $0.palComp = true; $0.axisSyncOn = true }),
            ("1b_展開図・ガラスのまま（くらべる用）", { $0.progress = 0; $0.spaceMode = 2; $0.netSolid = 0 }),
            ("1c_展開図・ふつうの立体", { $0.progress = 0; $0.spaceMode = 2 }),
            ("2b_組み立て0.3・ふつうからガラスへ", { $0.progress = 0.3; $0.spaceMode = 2 }),
            ("2c_組み立て0.45・ファンタジー 0", { $0.progress = 0.45; $0.spaceMode = 2; $0.fantasy = 0 }),
            ("0c11_組み上がり・ファンタジー 0（ふつうのまま）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.fantasy = 0 }),
            ("6g_W回転・ファンタジー 0", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.fantasy = 0 }),
            ("0c12_色温度 +50%", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.warmth = 0.5 }),
            ("2d_組み立て0.25", { $0.progress = 0.25; $0.spaceMode = 2; $0.ehOn = true }),
            ("2e_組み立て0.5", { $0.progress = 0.5; $0.spaceMode = 2; $0.ehOn = true }),
            ("2f_組み立て0.75", { $0.progress = 0.75; $0.spaceMode = 2; $0.ehOn = true }),
            ("N1_展開図・塔", { $0.progress = 0; $0.spaceMode = 2; $0.net = OrigamiState.netPresets[1] }),
            ("N2_展開図・階段", { $0.progress = 0; $0.spaceMode = 2; $0.net = OrigamiState.netPresets[2] }),
            ("N3_展開図・ねじれ", { $0.progress = 0; $0.spaceMode = 2; $0.net = OrigamiState.netPresets[3] }),
            ("D1_サイコロ・24 の目（面に描く）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.35; $0.yz = -0.3; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.diceFaces = true; $0.diceEyeK = 1 }),
            ("D2_サイコロ・48 の目（面に描く）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.35; $0.yz = -0.3; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.diceFaces = true; $0.diceEyeK = 1; $0.diceMode = 48 }),
            ("D3_サイコロ・4D でころころ", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceOneShot = false; s.rollDice(fixed: (3, 2)); for _ in 0..<72 { s.tick(1.0 / 60) } }),
            ("D4_サイコロ・4D の着地", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceOneShot = false; s.rollDice(fixed: (3, 2)); for _ in 0..<155 { s.tick(1.0 / 60) } }),
            ("D5_サイコロ・飛び出す", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceOneShot = false; s.rollDice(fixed: (3, 2)); for _ in 0..<(156 + 30) { s.tick(1.0 / 60) } }),
            ("D6_サイコロ・3D でころころ", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceOneShot = false; s.rollDice(fixed: (3, 2)); for _ in 0..<(156 + 80) { s.tick(1.0 / 60) } }),
            ("D7_サイコロ・出た目（24）", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceOneShot = false; s.rollDice(fixed: (3, 2)); for _ in 0..<(156 + 138 + 30) { s.tick(1.0 / 60) } }),
            ("D8_サイコロ・出た目（48）", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceMode = 48; s.diceOneShot = false; s.rollDice(fixed: (5, 3)); for _ in 0..<(156 + 138 + 30) { s.tick(1.0 / 60) } }),
            ("D9_一発・ごろごろ", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.rollDice(fixed: (3, 2)); for _ in 0..<80 { s.tick(1.0 / 60) } }),
            ("DA_一発・止まる前", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.rollDice(fixed: (3, 2)); for _ in 0..<200 { s.tick(1.0 / 60) } }),
            ("DB_一発・出た目（24）", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.rollDice(fixed: (3, 2)); for _ in 0..<(228 + 40) { s.tick(1.0 / 60) } }),
            ("DC_一発・出た目（48）", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.diceMode = 48; s.rollDice(fixed: (5, 3)); for _ in 0..<(228 + 40) { s.tick(1.0 / 60) } }),
            ("DD_一発・出た目（−W の胞）", { s in s.progress = 1; s.spaceMode = 2; s.xz = 0.35; s.yz = -0.3; s.rollDice(fixed: (0, 5)); for _ in 0..<(228 + 40) { s.tick(1.0 / 60) } }),
            ("ME_4 段（つながり 8）・組み立て 0.3", { $0.progress = 0.3; $0.spaceMode = 2; $0.net = NetAtlas.all[250].def }),
            ("MF_4 段（つながり 8）・組み立て 0.6", { $0.progress = 0.6; $0.spaceMode = 2; $0.net = NetAtlas.all[250].def }),
            ("MG_最大 2 段（つながり 8）・組み立て 0.45", { $0.progress = 0.45; $0.spaceMode = 2; $0.net = NetAtlas.all[250].def; $0.foldMaxStages = 2 }),
            ("P1_組み上がり・頂点から × X 消失", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) } }),
            ("P2_組み立て途中・頂点から × X 消失", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.playFold(); for _ in 0..<75 { s.tick(1.0 / 60) } }),
            ("P3_展開途中・W 消失にもどす", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.unfPose = 1; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) }; s.playUnfold(); for _ in 0..<40 { s.tick(1.0 / 60) } }),
            ("P6_展開・ななめ上から", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.unfPose = 5; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) }; s.playUnfold(); for _ in 0..<240 { s.tick(1.0 / 60) } }),
            ("P7_展開・上から", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.unfPose = 3; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) }; s.playUnfold(); for _ in 0..<240 { s.tick(1.0 / 60) } }),
            ("P4_展開・そのまま開く（ゆがむ）", { s in s.progress = 0; s.unfPose = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) }; s.playUnfold(); for _ in 0..<240 { s.tick(1.0 / 60) } }),
            ("P5_展開・W 消失にもどして開いた", { s in s.progress = 0; s.spaceMode = 2; s.asmPose = 4; s.asmVanish = 0; s.unfPose = 1; s.playFold(); for _ in 0..<240 { s.tick(1.0 / 60) }; s.playUnfold(); for _ in 0..<240 { s.tick(1.0 / 60) } }),
            ("MH_一筆・0.15", { $0.progress = 0.15; $0.spaceMode = 2; $0.net = NetAtlas.all[255].def; $0.foldCourse = true }),
            ("MI_一筆・0.4", { $0.progress = 0.4; $0.spaceMode = 2; $0.net = NetAtlas.all[255].def; $0.foldCourse = true }),
            ("MJ_一筆・0.7", { $0.progress = 0.7; $0.spaceMode = 2; $0.net = NetAtlas.all[255].def; $0.foldCourse = true }),
            ("MK_ころころ・0.55", { $0.progress = 0.55; $0.spaceMode = 2; $0.net = NetAtlas.all[255].def; $0.foldCourse = true }),
            ("ML_ころころ・0.86（返し）", { $0.progress = 0.86; $0.spaceMode = 2; $0.net = NetAtlas.all[255].def; $0.foldCourse = true }),
            ("MA_組み変わり・はじめ", { s in s.progress = 0; s.spaceMode = 2; s.net = OrigamiState.netDali; s.switchNet(NetAtlas.all[150].def); for _ in 0..<12 { s.tick(1.0 / 60) } }),
            ("MB_組み変わり・途中", { s in s.progress = 0; s.spaceMode = 2; s.net = OrigamiState.netDali; s.switchNet(NetAtlas.all[150].def); for _ in 0..<50 { s.tick(1.0 / 60) } }),
            ("MC_組み変わり・おわり近く", { s in s.progress = 0; s.spaceMode = 2; s.net = OrigamiState.netDali; s.switchNet(NetAtlas.all[150].def); for _ in 0..<85 { s.tick(1.0 / 60) } }),
            ("MD_組み変わり・おわり", { s in s.progress = 0; s.spaceMode = 2; s.net = OrigamiState.netDali; s.switchNet(NetAtlas.all[150].def); for _ in 0..<120 { s.tick(1.0 / 60) } }),
            ("N4_塔・組み立て0.5", { $0.progress = 0.5; $0.spaceMode = 2; $0.net = OrigamiState.netPresets[1] }),
            ("7e_分解・回した形", { $0.progress = 1; $0.explodeRaw = 1; $0.spaceMode = 2; $0.ax = 0.9; $0.ay = 0.4; $0.xz = 1.2; $0.yz = 0.5 }),
            ("F1_表だけ", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.faceSide = 1 }),
            ("F2_裏だけ", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.faceSide = 2 }),
            ("F3_頂点から（等角図）・表だけ", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false); $0.faceSide = 1 }),
            ("F4_頂点から（等角図）・裏だけ", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false); $0.faceSide = 2 }),
            ("F5_胞から・表だけ", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false); $0.faceSide = 1 }),
            ("0d_胞から", { $0.progress = 1; $0.spaceMode = 2; $0.goView(0, animated: false) }),
            ("0e_面から（平行）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(1, animated: false) }),
            ("0f_辺から（平行）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(2, animated: false) }),
            ("0g_頂点から（等角図・平行）", { $0.progress = 1; $0.spaceMode = 2; $0.goView(3, animated: false) }),
            ("0g2_頂点から（遠近）", { $0.progress = 1; $0.spaceMode = 2; $0.viewProj = 1; $0.goView(3, animated: false) }),
            ("0e2_面から（遠近）", { $0.progress = 1; $0.spaceMode = 2; $0.viewProj = 1; $0.goView(1, animated: false) }),
            ("0h_光の道で（くらべる用）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.raster = false }),
            ("1_展開図", { $0.progress = 0 }),
            ("2_組み立て0.45", { $0.progress = 0.45 }),
            ("3_組み立て0.75", { $0.progress = 0.75 }),
            ("4_組み上がり", { $0.progress = 1 }),
            ("5_光の波", { $0.progress = 1; $0.flashT = 0.5 }),
            ("6a_W回転・奥の表現なし（くらべる用）", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.depth3 = 0; $0.mul4 = 0; $0.glow4 = 0; $0.glass4 = 0; $0.reflSelf = 0; $0.stripK = 0 }),
            ("6b_W回転・宇宙切", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2 }),
            ("6d_W回転・宇宙切・密度の乗算なし（くらべる用）", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5; $0.spaceMode = 2; $0.squash4 = 0; $0.slant3 = 0 }),
            ("6e_W 90°近く・つぶれ", { $0.progress = 1; $0.ax = 1.35; $0.ay = 0.25; $0.spaceMode = 2 }),
            ("6f_W 90°近く・密度の乗算なし（くらべる用）", { $0.progress = 1; $0.ax = 1.35; $0.ay = 0.25; $0.spaceMode = 2; $0.squash4 = 0; $0.slant3 = 0 }),
            ("6_W回転", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5 }),
            ("7_宇宙切", { $0.progress = 1; $0.spaceMode = 2 }),
            ("7b_背景も宇宙", { $0.progress = 1; $0.bgSpace = true }),
            ("7c_分解", { $0.progress = 1; $0.explodeRaw = 1 }),
            ("7d_面の網目", { $0.progress = 1; $0.meshOn = true }),
            ("8_宇宙入・展開図", { $0.progress = 0; $0.spaceMode = 1 }),
            ("9_プラケース", { $0.progress = 1; $0.look = 1 }),
        ]
        // 積分の重さ：512 個の七色の縞・ドラゴンボールで 1 コマ（形を作る＋描く）
        if ProcessInfo.processInfo.environment["OGINTPERF"] != nil {
            for (nm, col) in [("七色の縞", 2), ("ドラゴンボール", 3), ("白", 0)] {
                st.reset(); st.progress = 1; st.spaceMode = 2; st.raster = true; st.intOn = true; st.intColor = col; st.intN = 512; st.intT = 30; st.intItems = st.intUpdate()
                for _ in 0..<3 { render(r4, t4) }
                let t0 = CACurrentMediaTime(); for _ in 0..<10 { render(r4, t4) }
                print(String(format: "積分 512 個（%@・%d 段）：1 コマ %.1f ミリ秒", nm, st.intItems.count, (CACurrentMediaTime() - t0) * 100))
            }
        }
        // 環境変数 OGONLY（名前の頭）で、その場面だけ描く（確かめを速く）
        let only = ProcessInfo.processInfo.environment["OGONLY"]
        for (name, f) in scenes where only.map({ name.hasPrefix($0) }) ?? true {
            st.reset(); st.xz = 0.55; st.yz = -0.4; st.look = 0; st.spaceMode = 0; st.bgSpace = false; st.meshOn = false; st.explodeRaw = 0; st.flashT = 9; st.projBlend = 0; st.presetPar = nil; st.raster = true; st.depth3 = 1; st.depthDeep = 0; st.slantSheen = 0; st.line3W = 0; st.line3K = 0; st.mul4 = 0.6; st.glow4 = 0.3; st.glass4 = 0.8; st.reflSelf = 0.7; st.stripK = 0; st.line4 = 1; st.line4K = 1; st.lineWidthNet = 1; st.lineWidthSolid = 1; st.inSphereWireW = 1; st.inSphereDepth = 0; st.inSphereAppear = 1; st.inSphereFilm = false; st.inSphereTone = 0.75; st.line4W = -0.7; st.ehOn = false; st.squash4 = 0.6; st.slant3 = 0.4; st.lineTint = 0; st.pal3 = OrigamiState.palDef3; st.pal4 = OrigamiState.palDef4; st.palComp = false; st.palCompCenter = false; st.axisSyncOn = false; st.netSolid = 1; st.fantasy = 1; st.warmth = 0; st.netMul = 0.5; st.net = OrigamiState.netDali; st.viewProj = 0; st.faceSide = 0; st.userPts = []; st.ptLabels = true; st.ptLeft = true; st.ptSize = 0.55; st.softMul = 0.5; st.smartLine = 0.7; st.pan = [.zero, .zero]; st.secOn = false; st.secPos = 0; st.secInfo = ["", ""]; st.intOn = false; st.intItems = []; st.intLook = 0; st.intPaused = false; st.intFly = true; st.intOutOpp = false; st.intPace = 0; st.intAmount = 1; st.intAxes = 8; st.intMethod = 0; st.isPreview = false; st.showAxes = true; st.intShape = 0; st.inSphere = false; st.inSphereColor = 0; st.inSphereLayers = 10; st.inSphereGlass = true; st.inSphereLon = true; st.inSphereCone = true; st.inSphereLat = true; st.inSphere120 = false; st.inSphereTouch = true; st.inSphereDent = true; st.inSphereDentSharp = true; st.inSphereTouchCol = 0; st.dim5 = false; st.spin5 = false; st.tw5 = nil; st.net5 = OrigamiState.p5Dali; st.net5No = 1; st.lineTintMode = 1; st.intExact = true; st.waterReal = true; st.waterNS = false; st.waterSwirl = 0.3; st.waterVort = 1; st.waterSlice = 0; st.waterSlicePos = 0; st.waterSlosh = 1; st.ballR = 0.38; st.ballsAuto = false; st.ballGravMode = 2; st.ballG = 6; st.balls4.gvec = SIMD4(0, 0, 0, -6); st.balls3.gvec = SIMD4(0, 0, -6, 0); st.balls4.clear(); st.balls3.clear(); st.nsPrevM4 = nil; st.nsLagM4 = nil; st.waterShakeAcc = .zero; st.waterShakeV = .zero; st.waterGDirInit = false; st.waterFree = false; st.waterGravMode = 0; st.waterNSRes = 32; st.waterG = 9.8; st.waterPourRate = 1; st.waterLidSet = true; st.waterBottomSet = false; st.waterPourHold = false; st.intLidMode = 0; st.drainMode = 0; st.drainSize = 0.58; st.waterDrainH = nil; st.gravX = 0; st.gravY = 0; st.gravZ = 0; st.gravW = -1; st.gravGrab = false; st.gravHandleShow = true; st.holesOpenSet = false; st.waterVent = true; st.holeShow = 0; st.waterCyc = 0; st.waterDOpen = 0; st.waterVD = 0; st.holeDA = 0; st.holeVA = 0; st.holeDHL = 0; st.holeVHL = 0; st.intOnce = false; st.intView = 1; st.netMorph = nil; st.netAnim = true; st.foldMaxStages = 4; st.foldCourse = false; st.courseFromB = false; st.unf4 = 1; st.unf3 = 1; st.asm4 = 1; st.asm3 = 1; st.asmAuto = false; st.memUp = nil; st.memDown = nil; st.asmPose = 0; st.asmVanish = 3; st.unfPose = 0; st.asmLand = nil; st.asmLastP = -1; st.diceMode = 24; st.diceOneShot = true; st.diceFaces = false; st.diceEyeK = 0; st.diceDim = 0; st.diceRoll = nil; st.diceHold = nil; st.diceFlash = false; st.markNear = OrigamiState.markNearDef; st.markFar = OrigamiState.markFarDef; st.markSize = 0.65; st.markShowNear = true; st.markShowFar = true; st.markGlue = true; st.ehNearOn = true; st.ehFarOn = true; st.ehCells = [:]; st.ehWidthOther = 3; f(st); if let m = st.netMorph, m.t == 0 { st.netMorph = nil }   // 止め絵：組み変わりは、途中を指定した場面だけ
            applyOGSET(st)
            st.colorP = st.progress                                           // 確かめの絵は、色も形と同じ組み立て具合で
            let (rL, rR) = st.dim5 ? (r4L, r5) : (r3, r4)
            for _ in 0..<3 { render(rL, t3); render(rR, t4) }
            if name.hasPrefix("SW_") && ProcessInfo.processInfo.environment["OGSWEEP"] != nil {   // 組み立て途中の色の飛び：超立方体の絵の平均の色
                var prev: SIMD3<Double>? = nil, out: [String] = []
                for k in 0...100 {
                    st.progress = Double(k) / 100; st.colorP = st.progress
                    for _ in 0..<2 { render(r4, t4) }
                    var part = [UInt8](repeating: 0, count: w * h * 4)
                    t4.getBytes(&part, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    var m = SIMD3<Double>(0, 0, 0), sat = 0.0, sn = 0.0
                    for i in stride(from: 0, to: part.count, by: 4) {
                        let c = SIMD3(Double(part[i + 2]), Double(part[i + 1]), Double(part[i])); m += c
                        let mx = c.max(), mn = c.min(); if mx > 40 { sat += (mx - mn) / mx; sn += 1 }   // 暗い背景は数えない
                    }
                    m /= Double(w * h)
                    let d = prev.map { simd_length(m - $0) } ?? 0; prev = m
                    out.append(String(format: "%.2f:%.2f:%.3f", st.progress, d, sn > 0 ? sat / sn : 0))
                }
                print("組み立ての色の変わり方（前の 1% との差）：" + out.joined(separator: " "))
            }
            if name.hasPrefix("D5_6") {                                          // 5 次元の窓の重さ（形づくり＋GPU を待つまで）
                let t0 = CACurrentMediaTime(); for _ in 0..<20 { render(r5, t4) }
                let t1 = CACurrentMediaTime(); for _ in 0..<20 { render(r4L, t3) }
                print(String(format: "5 次元の窓：1 コマ %.1f ミリ秒（同じ大きさの超立方体 %.1f ミリ秒）", (t1 - t0) * 50, (CACurrentMediaTime() - t1) * 50))
            }
            if name.hasPrefix("MK") { st.markAlignNow(); for _ in 0..<2 { render(r3, t3); render(r4, t4) } }   // 目印：カメラの位置が決まってから重なる向きに合わせ直す
            if st.secOn { print("断面（\(name)）：超立方体 \(st.secInfo[1])・立方体 \(st.secInfo[0])") }
            if st.faceSide != 0 { print("見せる胞（\(name)）：立方体 \(st.sideShown[0][0]) / \(st.sideShown[0][1])・超立方体 \(st.sideShown[1][0]) / \(st.sideShown[1][1])") }
            let W = w * 2 + 4
            var px = [UInt8](repeating: 0, count: W * h * 4)
            for (k, t) in [t3, t4].enumerated() {
                var part = [UInt8](repeating: 0, count: w * h * 4)
                t.getBytes(&part, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                for y in 0..<h { for x in 0..<(w * 4) { px[y * W * 4 + k * (w + 4) * 4 + x] = part[y * w * 4 + x] } }
            }
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!, ctx = CGContext(data: &px, width: W, height: h, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            let u = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL
            if let dd = CGImageDestinationCreateWithURL(u, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd) }
            print(name, String(format: "宇宙 %.2f・光 %.2f", st.spaceK, st.spaceFlash))
        }
        // 確かめ（OGMORPH）：展開図のまま、展開図を切りかえた時（組み変わりのアニメ）に、1 コマごとの色の差を記録する
        if ProcessInfo.processInfo.environment["OGMORPH"] != nil {
            let s8 = OrigamiState(); s8.progress = 0; s8.target = 0; s8.updateMats(); applyOGSET(s8)
            if let r8 = OrigamiRenderer(n: 4, state: s8, device: d) {
                for _ in 0..<5 { s8.tick(1.0 / 60); render(r8, t4) }
                s8.switchNet(OrigamiState.netPresets[2])
                var prev: SIMD3<Double>? = nil, out: [(Double, Double)] = []
                for f in 0..<120 {
                    s8.tick(1.0 / 60); render(r8, t4)
                    var part = [UInt8](repeating: 0, count: w * h * 4)
                    t4.getBytes(&part, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    var m = SIMD3<Double>(0, 0, 0)
                    for i in stride(from: 0, to: part.count, by: 4) { m += SIMD3(Double(part[i + 2]), Double(part[i + 1]), Double(part[i])) }
                    m /= Double(w * h)
                    out.append((Double(f) / 60, prev.map { simd_length(m - $0) } ?? 0)); prev = m
                }
                let top = out.sorted { $0.1 > $1.1 }.prefix(6).map { String(format: "%.2f秒:%.2f", $0.0, $0.1) }
                print("展開図の切りかえ：1 コマの色の差の大きい所 " + top.joined(separator: "・") + String(format: "・ふつうの 1 コマ（真ん中）%.2f", out.map(\.1).sorted()[out.count / 2]))
            }
        }
        // 確かめ（OGPLAY）：はじめの状態（展開図）から C を押した時と同じに、1/60 秒ずつ時間を進めて、超立方体の絵の彩度と明るさを記録する
        if ProcessInfo.processInfo.environment["OGPLAY"] != nil {
            let s7 = OrigamiState(); s7.progress = 0; s7.target = 0; s7.updateMats(); applyOGSET(s7)
            if let r7 = OrigamiRenderer(n: 4, state: s7, device: d) {
                for _ in 0..<5 { s7.tick(1.0 / 60); render(r7, t4) }
                var out: [String] = [], prevM: SIMD3<Double>? = nil
                do {   // 押す前（進み 0）の色
                    render(r7, t4)
                    var part = [UInt8](repeating: 0, count: w * h * 4)
                    t4.getBytes(&part, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    var mm = SIMD3<Double>(0, 0, 0)
                    for i in stride(from: 0, to: part.count, by: 4) { mm += SIMD3(Double(part[i + 2]), Double(part[i + 1]), Double(part[i])) }
                    prevM = mm / Double(w * h)
                }
                s7.toggleFold()
                for f in 0..<240 {
                    s7.tick(1.0 / 60)
                    if f % 4 != 0 && f > 12 { continue }
                    render(r7, t4)
                    var part = [UInt8](repeating: 0, count: w * h * 4)
                    t4.getBytes(&part, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    var sat = 0.0, sn = 0.0, lum = 0.0, mm = SIMD3<Double>(0, 0, 0)
                    for i in stride(from: 0, to: part.count, by: 4) {
                        let c = SIMD3(Double(part[i + 2]), Double(part[i + 1]), Double(part[i])), mx = c.max(), mn = c.min(); mm += c
                        if mx > 40 { sat += (mx - mn) / mx; sn += 1; lum += mx }
                    }
                    mm /= Double(w * h); let dm = prevM.map { simd_length(mm - $0) } ?? 0; prevM = mm
                    out.append(String(format: "%.2f秒 進み%.3f 彩度%.3f 明るさ%.0f 色の差%.2f", Double(f) / 60, s7.progress, sn > 0 ? sat / sn : 0, sn > 0 ? lum / sn : 0, dm))
                }
                print("C で組み上げ：\n" + out.joined(separator: "\n"))
            }
        }
        // NDGeom（ウェブ版 nd-geom の Swift 版）と、今の次元おりがみの式が同じか（5 次元へ広げる土台）
        do {
            let s2 = OrigamiState(); s2.reset(); s2.asmAuto = false; s2.ax = 0.7; s2.ay = -0.4; s2.zw = 0.3; s2.xy = 0.2; s2.xz = 0.5; s2.yz = -0.3; s2.updateMats()
            let net = NDGeom.CubeNet(n: 4)
            let pj = NDGeom.Projector(n: 4, w: s2.camW, R: NDGeom.rotation(4, [(0, 3, s2.ax), (1, 3, s2.ay), (2, 3, s2.zw), (0, 1, s2.xy), (0, 2, s2.xz), (1, 2, s2.yz)]))
            var worst = 0.0, cnt = 0
            for f in [0.0, 0.3, 0.7, 1.0] {
                s2.progress = f
                let V = net.place(f)
                for (ci, C) in net.cells.enumerated() {
                    let oc: OrigamiState.Cell = C.kind == .center ? .center : C.kind == .cap ? .cap : .arm(C.axis, C.sign)
                    for v in 0..<net.nl {
                        let a = pj.project(V[ci * net.nl + v]).0, b = s2.place(s2.fold(oc, net.base(ci, v), 4), 4).0
                        worst = max(worst, simd_distance(a, b)); cnt += 1
                    }
                }
            }
            print(String(format: "NDGeom と次元おりがみの式のちがい（%d 点の最大）：%.2e", cnt, worst))
            let n5 = NDGeom.CubeNet(n: 5)
            print("5 次元の展開図：胞 \(n5.cells.count)・辺 \(n5.edges.count)・正方形 \(n5.squares.count)")
            // 5 次元 β：次元おりがみの fold・place5 と、NDGeom（ウェブ版 nd-geom の式）が同じか
            s2.xw5 = 0.4; s2.yw5 = -0.25; s2.zw5 = 0.6; s2.wv5 = 0.35; s2.updateMats()
            let pj5 = NDGeom.Projector(n: 5, w: s2.camW, R: NDGeom.rotation(5, [(0, 4, s2.ax), (1, 4, s2.ay), (2, 4, s2.zw), (0, 3, s2.xw5), (1, 3, s2.yw5), (2, 3, s2.zw5), (3, 4, s2.wv5), (0, 1, s2.xy), (0, 2, s2.xz), (1, 2, s2.yz)]))
            var worst5 = 0.0, cnt5 = 0, per5: [String] = []
            for f in [0.0, 0.3, 0.7, 1.0] {
                s2.progress = f; let w0 = worst5; worst5 = 0
                defer { per5.append(String(format: "%.1f→%.1e", f, worst5)); worst5 = max(w0, worst5) }
                let V = n5.place(f)
                for (ci, C) in n5.cells.enumerated() {
                    let oc: OrigamiState.Cell = C.kind == .center ? .center : C.kind == .cap ? .cap : .arm(C.axis, C.sign)
                    for v in 0..<n5.nl {
                        let a = pj5.project(V[ci * n5.nl + v]).0, b = s2.place(s2.fold(oc, n5.base(ci, v), 5), 5).0
                        worst5 = max(worst5, simd_distance(a, b)); cnt5 += 1
                    }
                }
            }
            // 組み上がると 10 個 × 16 頂点が 32 頂点に重なるか
            s2.progress = 1
            var vset = Set<[Int]>()
            for cell in OrigamiState.cells(5) {
                let (fa, fv) = OrigamiState.fixed(cell, 5), free = (0..<5).filter { $0 != fa }
                for bits in 0..<16 {
                    var p = [Double](repeating: 0, count: 5); p[fa] = fv
                    for (k, ax) in free.enumerated() { p[ax] = bits & (1 << k) != 0 ? 1 : -1 }
                    vset.insert(s2.fold(cell, p, 5).map { Int(($0 * 1000).rounded()) })
                }
            }
            print(String(format: "5 次元 β：NDGeom とのちがい（%d 点の最大）%.2e・組み上がりの頂点 %d 個（32 なら ○）", cnt5, worst5, vset.count))
            print("  折り具合ごと：" + per5.joined(separator: "・"))
            // 5 次元の内接球：接点（±e_i × 半分）が、組み上がった 10 個の胞の真ん中と同じ場所か。球面の点が全部の胞の内側（|u_i| ≤ 1）か
            do {
                s2.progress = 1; var wc = 0.0
                for (ci, c) in OrigamiRenderer.cellNormals[2].enumerated() {
                    var u = [0.0, 0, 0, 0, 0]; u[c.0] = c.1
                    let a = s2.place(s2.fold(OrigamiState.cells(5)[ci], u, 5), 5).0, b = s2.place5(u.map { $0 * OrigamiState.half }).0
                    wc = max(wc, simd_distance(a, b))
                }
                var seed: UInt64 = 7, out = 0, touch = 0
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                for _ in 0..<20000 {
                    var u = (0..<5).map { _ in rnd() * 2 - 1 }; let l = sqrt(u.reduce(0) { $0 + $1 * $1 }); u = u.map { $0 / l }
                    let m = u.map(abs).max()!; if m > 1 + 1e-12 { out += 1 }; if m > 0.999 { touch += 1 }
                }
                let vb = 8 * Double.pi * Double.pi / 15
                // 5 次元の展開図図鑑：表の数・転がして平らにした位置と、アプリの折りたたみ（進み 0）の位置が同じか・見本の番号・組み上がりが 32 頂点か
                let E = Net5Atlas.entries
                var flatErr = 0.0, asmOK = 0
                var rng = SystemRandomNumberGenerator()
                let picks = [0, E.count - 1] + (0..<40).map { _ in Int.random(in: 0..<E.count, using: &rng) }
                for i in picks {
                    let p = E[i].parent; s2.net5 = p
                    guard let F = Net5Atlas.flat(p) else { flatErr = 99; continue }
                    s2.progress = 0
                    let C = (0..<10).map { ci -> [Double] in var u = [0.0, 0, 0, 0, 0]; u[OrigamiRenderer.cellNormals[2][ci].0] = OrigamiRenderer.cellNormals[2][ci].1 * 0; return s2.fold(OrigamiState.cells(5)[ci], u, 5) }
                    for ci in 0..<10 { for d in 0..<4 { flatErr = max(flatErr, abs(C[ci][d] - C[0][d] - Double(F[ci][d]) * 2 * OrigamiState.half)) }; flatErr = max(flatErr, abs(C[ci][4] - C[0][4])) }
                    s2.progress = 1
                    var vs = Set<[Int]>()
                    for cell in OrigamiState.cells(5) {
                        let (fa, fv) = OrigamiState.fixed(cell, 5), free = (0..<5).filter { $0 != fa }
                        for bits in 0..<16 { var q = [Double](repeating: 0, count: 5); q[fa] = fv; for (kk, ax) in free.enumerated() { q[ax] = bits & (1 << kk) != 0 ? 1 : -1 }; vs.insert(s2.fold(cell, q, 5).map { Int(($0 * 1000).rounded()) }) }
                    }
                    if vs.count == 32 { asmOK += 1 }
                }
                s2.net5 = OrigamiState.p5Dali
                let pn = OrigamiState.net5Presets.map { (nm, p) in "\(nm) No.\(Net5Atlas.noOf[Net5Atlas.canon(Net5Atlas.mask(p))] ?? 0)\(Net5Atlas.flat(p) == nil ? "（重なる！）" : "")" }
                print("5 次元の展開図図鑑：\(E.count) 種類・No.1 は長さ \(E[0].longest)・くっつく数 \(E[0].maxDeg)・最後は長さ \(E[E.count - 1].longest)／" + String(format: "平らな位置のずれ（%d 種類）%.1e・組み上がり 32 頂点 %d / %d", picks.count, flatErr, asmOK, picks.count) + "／見本：" + pn.joined(separator: "・"))
                print(String(format: "5 次元の内接球：接点と胞の真ん中のずれ %.1e・球面の点 20000 個で胞の外 %d 個・壁にほぼ触れる %d 個・体積の割合 %.1f%%", wc, out, touch, vb / 32 * 100))
            }
            do {   // 積分の 1 往復：入れて取り出したら止まるか（止まった時は空・一時停止）。くり返しならそのまま次の周へ
                let s = OrigamiState(); s.reset(); s.progress = 1; s.target = 1; s.intOn = true; s.intShape = 5; s.intN = 21; s.intOnce = true; s.intT = 0
                let c = s.intCycleT
                var t = 0.0; while t < c + 3 { s.tick(1.0 / 60); t += 1.0 / 60 }
                let stopped = s.intPaused && abs(s.intT - c) < 1e-3, emptyNow = s.intUpdate().isEmpty
                let s2 = OrigamiState(); s2.reset(); s2.progress = 1; s2.target = 1; s2.intOn = true; s2.intShape = 5; s2.intN = 21; s2.intOnce = false; s2.intT = 0
                t = 0; while t < c + 3 { s2.tick(1.0 / 60); t += 1.0 / 60 }
                print(String(format: "積分の 1 往復：1 周 %.1f 秒・1 往復で止まった %@・止まった時は空 %@／くり返しは止まらず次の周へ %@", c, stopped ? "○" : "×", emptyNow ? "○" : "×", !s2.intPaused && s2.intT > c ? "○" : "×"))
            }
            do {   // 積む形の体積：輪切りの大きさを −1〜1 で数値積分したものが、式の全体の体積と合うか（右 4 次元・左 3 次元）。
                //   角から切る超立方体は、切り口の多面体の体積（凸包を面ごとに）と、公式の大きさが合うかも
                var out: [String] = []
                for (nm, sh) in [("球すい", 5), ("角から", 6), ("球のドーナツ", 7), ("キュービンダー", 8)] {
                    let r4 = OrigamiState.slInt(sh, -1, 1, left: false) / OrigamiState.slTotal(sh, left: false), r3 = OrigamiState.slInt(sh, -1, 1, left: true) / OrigamiState.slTotal(sh, left: true)
                    out.append(String(format: "%@ 右 %.4f・左 %.4f", nm, r4, r3))
                }
                var worst = 0.0
                for d in stride(from: -0.95, through: 0.95, by: 0.1) {
                    let faces = OrigamiRenderer.cornerSlice4(d)
                    let all = faces.flatMap { $0 }, c = all.reduce(SIMD3<Double>(0, 0, 0), +) / Double(max(1, all.count))
                    var v = 0.0
                    for f in faces { for i in 1..<(f.count - 1) { v += abs(simd_dot(f[0] - c, simd_cross(f[i] - c, f[i + 1] - c))) / 6 } }
                    worst = max(worst, abs(v - OrigamiState.slCubeSlice(4, 2 * d + 2)))
                }
                let f0 = OrigamiRenderer.cornerSlice4(0), f9 = OrigamiRenderer.cornerSlice4(0.9)
                print("積む形の体積（積分 ÷ 式、1 ならぴったり）：" + out.joined(separator: "・") + String(format: "／角から：切り口の多面体と公式のずれ %.1e・まんなかの面 %d 枚（八面体は 8）・はしの面 %d 枚（四面体は 4）", worst, f0.count, f9.count))
            }
            do {   // 回したまま組み立て・展開：どのモードでも、回し続けるが止まらず、角度が毎コマ動き続けるか（前は向きを動かす間、角度を上書きして止まって見えた）
                var lines: [String] = []
                for (nm, am) in [("表で決める", 0), ("おまかせ 1", 1), ("おまかせ 2", 2)] {
                    let s = OrigamiState(); s.reset(); s.autoMode = am; s.asmAuto = am != 0; s.progress = 1; s.target = 1; s.updateMats()
                    s.memUp = nil; s.memDown = [0.3, -0.2, 0.1, 0.5, 0.2, -0.4]
                    s.toggle6()
                    var still = 0, frames = 0, prev = s.cur6
                    for half in 0..<2 {
                        if half == 0 { s.playUnfold() } else { s.playFold() }
                        for _ in 0..<150 { s.tick(1.0 / 60); frames += 1; let c = s.cur6; if zip(c, prev).allSatisfy({ abs($0 - $1) < 1e-7 }) { still += 1 }; prev = c }
                    }
                    let spinOn = [s.spinX, s.spinY, s.spinZW, s.spinXY, s.spinXZ, s.spinYZ].contains(true)
                    lines.append("\(nm)：止まったコマ \(still) / \(frames)・最後も回っている \(spinOn ? "○" : "×")")
                }
                print("回したまま組み立て・展開：" + lines.joined(separator: "・"))
                // カクッ（速さが急に変わる）：あなたの設定に近い形（おまかせ 1・6 面とも回す・4D 別々・展開はまっすぐ）で、1 コマごとの角度の進み（速さ）を
                //   記録し、となりのコマとの速さの差のいちばん大きい所を、回し続ける 1 コマの進み（X-W：0.006 × 144 ／ 60）を 1 として出す
                for (nm, am) in [("おまかせ 1", 1), ("おまかせ 2", 2), ("表で決める", 0)] {
                    let s = OrigamiState(); s.reset(); s.autoMode = am; s.asmAuto = am != 0; s.sep4 = true; s.sep3 = false; s.unf4 = 2; s.progress = 1; s.target = 1; s.updateMats()
                    s.toggle6()
                    for _ in 0..<30 { s.tick(1.0 / 60) }
                    var prev = s.cur6, pv: [Double]? = nil, worst = 0.0, wAt = "", stepRef = 0.006 * 144 / 60, log: [String] = [], wI = 0
                    for half in 0..<2 {
                        if half == 0 { s.playUnfold() } else { s.playFold() }
                        for f in 0..<200 {
                            s.tick(1.0 / 60); let c = s.cur6
                            let v = (0..<6).map { OrigamiState.wrapPi(c[$0] - prev[$0]) }
                            log.append(String(format: "%@%d p%.3f 速さ[%@] 回す%@", half == 0 ? "展" : "組", f, s.progress, v.map { String(format: "%+.4f", $0) }.joined(separator: " "), [s.spinX, s.spinY, s.spinZW, s.spinXY, s.spinXZ, s.spinYZ].map { $0 ? "1" : "0" }.joined()))
                            if let pv { let j = (0..<6).map { abs(v[$0] - pv[$0]) }.max()! / stepRef; if j > worst { worst = j; wI = log.count - 1; wAt = String(format: "%@ %d コマ目・組み具合 %.2f", half == 0 ? "展開" : "組み立て", f, s.progress) } }
                            pv = v; prev = c
                        }
                    }
                    print(String(format: "カクッ（%@）：となりのコマとの速さの差のいちばん大きい所 %.2f（回し続ける 1 コマ分を 1）", nm, worst) + "・" + wAt)
                    if ProcessInfo.processInfo.environment["OGKAKU"] != nil { if ProcessInfo.processInfo.environment["OGKAKU"] == "all" && am == 1 { for i in 0..<min(log.count, 260) where i % 2 == 0 || (i > 70 && i < 90) || (i > 195 && i < 215) { print("   ", log[i]) } } else { for i in max(0, wI - 4)...min(log.count - 1, wI + 3) { print("   ", log[i]) } } }
                }
            }
            do {   // 5 次元の組み変わり：はじめは前の展開図・おわりは新しい展開図とぴったり同じか。途中の回転が回転のままか
                let s9 = OrigamiState(); s9.reset(); s9.dim5 = true; s9.progress = 0; s9.netAnim = true
                func dif(_ A: [OrigamiState.Aff], _ B: [OrigamiState.Aff]) -> Double {
                    var m = 0.0
                    for (a, b) in zip(A, B) { for i in 0..<5 { m = max(m, abs(a.t[i] - b.t[i])); for j in 0..<5 { m = max(m, abs(a.M[i][j] - b.M[i][j])) } } }
                    return m
                }
                var e0 = 0.0, e1 = 0.0, orth = 0.0, frames = 0, moved = 0
                for (_, p) in OrigamiState.net5Presets.dropFirst() + [(String(""), Net5Atlas.entries[4999].parent)] {
                    s9.netMorph = nil; s9.net5 = OrigamiState.p5Dali
                    let A = s9.rawTransforms(OrigamiState.p5Dali, 5), B = s9.rawTransforms(p, 5)
                    s9.switchNet5(p)
                    e0 = max(e0, dif(s9.netTransforms(5), A))
                    moved = max(moved, zip(A, B).filter { dif([$0], [$1]) > 1e-6 }.count)
                    while s9.netMorph != nil {
                        s9.netMorphTick(1.0 / 60); frames += 1
                        if s9.netMorph != nil { for T in s9.netTransforms(5) { for i in 0..<5 { for j in 0..<5 { var d = 0.0; for k in 0..<5 { d += T.M[i][k] * T.M[j][k] }; orth = max(orth, abs(d - (i == j ? 1 : 0))) } } } }
                        if frames > 10000 { break }
                    }
                    e1 = max(e1, dif(s9.netTransforms(5), B))
                }
                print(String(format: "5 次元の組み変わり：はじめのずれ %.1e・おわりのずれ %.1e・途中の回転のくずれ %.1e・動く胞 最大 %d 個・%d コマ（4 回）", e0, e1, orth, moved, frames))
            }
            do {   // 回転なし・遠近だけで
                let s3 = OrigamiState(); s3.reset(); s3.asmAuto = false; s3.updateMats()
                let pj0 = NDGeom.Projector(n: 5, w: s3.camW, R: nil); var wz = 0.0
                for f in [0.0, 1.0] { s3.progress = f; let V = n5.place(f)
                    for (ci, C) in n5.cells.enumerated() { let oc: OrigamiState.Cell = C.kind == .center ? .center : C.kind == .cap ? .cap : .arm(C.axis, C.sign)
                        for v in 0..<n5.nl { wz = max(wz, simd_distance(pj0.project(V[ci * n5.nl + v]).0, s3.place(s3.fold(oc, n5.base(ci, v), 5), 5).0)) } } }
                print(String(format: "  回転なし：%.2e", wz))
            }
        }
        // 細い窓（境目を動かした時）でも見切れないか：横 300・縦 860 で、組み上がりと展開図
        do {
            let s4 = OrigamiState(); s4.reset(); s4.asmAuto = false; s4.ax = 29 * .pi / 180; s4.ay = 17 * .pi / 180; s4.spaceMode = 2
            if let rn = OrigamiRenderer(n: 4, state: s4, device: d) {
                for (name, p) in [("10_細い窓・組み上がり", 1.0), ("11_細い窓・展開図", 0.0)] {
                    s4.progress = p
                    let W = 300, Hh = 860, td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: Hh, mipmapped: false)
                    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .managed
                    let t = d.makeTexture(descriptor: td)!
                    for _ in 0..<3 {
                        let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = t; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
                        let cb = rn.queue.makeCommandBuffer()!; rn.encode(cb, rpd, W, Hh, now: 12.3, dt: 0.3)
                        let bl = cb.makeBlitCommandEncoder()!; bl.synchronize(resource: t); bl.endEncoding(); cb.commit(); cb.waitUntilCompleted()
                    }
                    var px = [UInt8](repeating: 0, count: W * Hh * 4)
                    t.getBytes(&px, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, Hh), mipmapLevel: 0)
                    let cs = CGColorSpace(name: CGColorSpace.sRGB)!, ctx = CGContext(data: &px, width: W, height: Hh, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                    if let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd) }
                }
            }
        }
        // ショートカット：既定のキーに重なりがないか・キーで機能が動くか
        do {
            let defs = ShortcutStore.actions.map(\.def).filter { !$0.isEmpty }
            let dup = Dictionary(grouping: defs, by: { $0 }).filter { $0.value.count > 1 }.map(\.key)
            let s5 = OrigamiState(); s5.reset(); s5.asmAuto = false; let ks = ShortcutStore()
            ks.keys = Dictionary(uniqueKeysWithValues: ShortcutStore.actions.map { ($0.id, $0.def) })
            ks.action(for: "U")?.run(s5); let unf = s5.playing && s5.target == 0
            ks.action(for: "Enter")?.run(s5); let w3 = s5.allW
            ks.action(for: "Shift+3")?.run(s5); let tab = s5.panelTab == 2
            ks.assign("fold", "U"); let moved = ks.keys["unfold"] == "" && ks.keys["fold"] == "U"
            print("ショートカット：\(ShortcutStore.actions.count) 個・既定の重なり \(dup.isEmpty ? "なし" : dup.joined(separator: ","))・U で展開 \(unf ? "○" : "×")・Enter で W \(w3 ? "○" : "×")・⇧3 で見え方 \(tab ? "○" : "×")・付けかえで前のを外す \(moved ? "○" : "×")")
        }
        // 設定の保存の確かめ：値を変えて、保存の形（プロパティリスト）を通してから別の状態にもどす
        do {
            let a = OrigamiState(); a.pal4["px"] = 0x123456; a.palComp = true; a.zfAsm = 0.71; a.line4 = 2; a.swapViews = true; a.ehNear = SIMD3(0.1, 0.2, 0.3); a.ppEase = "turn"; a.zoom = [1.5, 2.25]
            a.addPt([0.443, -1, 0, 1], 0x56a8ff, "ためし", lock: true); a.addEdgeMids(); a.ptSize = 0.8; a.ptLeft = false
            let data = try? PropertyListSerialization.data(fromPropertyList: a.settingsSnapshot, format: .binary, options: 0)
            let back = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            let b = OrigamiState(); if let back { b.applySettings(back) }
            let ok = back != nil && b.pal4["px"] == 0x123456 && b.palComp && abs(b.zfAsm - 0.71) < 1e-9 && b.line4 == 2 && b.swapViews && abs(b.ehNear.y - 0.2) < 1e-6 && b.ppEase == "turn" && b.zoom == [1.5, 2.25]
                && b.userPts.count == 33 && b.userPts[0].label == "ためし" && b.userPts[0].lock && b.userPts[0].c == [0.443, -1, 0, 1, 0] && b.userPts[0].color == 0x56a8ff && abs(b.ptSize - 0.8) < 1e-9 && !b.ptLeft
            print("設定の保存：\(a.settingsSnapshot.count) 項目・保存の形にできる \(data != nil ? "○" : "×")・もどす \(ok ? "○" : "×")")
            // 画面の状態（角度・回し続ける面・組み立て具合・分解・往復）
            let c = OrigamiState(); c.ax = 0.7; c.zw = -1.2; c.yz = 0.33; c.spinX = true; c.spinYZ = true; c.progress = 0.4; c.explodeRaw = 0.6; c.loop = true
            let sd = (try? PropertyListSerialization.data(fromPropertyList: c.sessionSnapshot, format: .binary, options: 0)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            let e = OrigamiState(); if let sd { e.applySession(sd) }
            let ok2 = sd != nil && abs(e.ax - 0.7) < 1e-4 && abs(e.zw + 1.2) < 1e-4 && abs(e.yz - 0.33) < 1e-4 && e.spinX && e.spinYZ && !e.spinY && abs(e.progress - 0.4) < 1e-4 && abs(e.explodeRaw - 0.6) < 1e-4 && e.loop
            print("画面の状態の保存：もどす \(ok2 ? "○" : "×")")
            // 角度の往復の間も 3D で回せる：往復を始めて X-Z を回し続け、ドラッグもする → 往復は続き、見る向きが回る。止めると見た目を変えずに角度へ入る
            let g = OrigamiState(); g.reset(); g.asmAuto = false; g.ppStops = [[0, 0, 0, 0, 0, 0], [45, 35.26, 30, 0, 0, 0]]; g.startPP(g.ppStops, once: false)
            for _ in 0..<60 { g.tick(1.0 / 60) }
            g.spinXZ = true
            for _ in 0..<60 { g.tick(1.0 / 60) }
            g.drag(.r3x, 0.3)
            let running = g.pp != nil, turned = g.view3 != matrix_identity_double4x4
            let mBefore = g.m4; g.stopPP(); let mAfter = g.m4
            var diff = 0.0; for i in 0..<4 { diff = max(diff, simd_length(mBefore[i] - mAfter[i])) }
            // プリセット：前の形（lock なし）も読める・往復のプリセットを保存して始める・ロック中は消せない
            let oldJSON = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"前の","deg":[1,2,3,4,5,6]}]"#.data(using: .utf8)!
            let oldOK = (try? JSONDecoder().decode([AnglePreset].self, from: oldJSON))?.first?.locked == false
            let h = OrigamiState(); h.reset(); h.asmAuto = false; h.ppStops = [[0, 0, 0, 0, 0, 0], [30, 0, 0, 0, 0, 0], [0, 30, 0, 0, 0, 0]]; h.ppSec = 2.5; h.ppPresets = []
            h.savePPPreset(); h.ppStops = [[0, 0, 0, 0, 0, 0], [90, 0, 0, 0, 0, 0]]
            h.toggleLockPP(0); h.deletePPPreset(h.ppPresets[0]); let kept = h.ppPresets.count == 1
            h.loadPPPreset(h.ppPresets[0], start: true)
            let ppOK = h.ppStops.count == 3 && abs(h.ppSec - 2.5) < 1e-9 && h.pp != nil
            print("プリセット：前の形も読める \(oldOK ? "○" : "×")・往復を保存して始める \(ppOK ? "○" : "×")・ロック中は消せない \(kept ? "○" : "×")")
            // 展開図のかたち：見本が正しいか・でたらめが作れるか・立方体の対応・全部折ると同じ超立方体になるか
            let pv = OrigamiState.netPresets.map { "\($0.name) \(OrigamiState.validNet($0.p4, 4) && OrigamiState.validNet($0.p3, 3) ? "○" : "×")" }.joined(separator: "・")
            var rnOK = 0; for _ in 0..<20 { let r = OrigamiState.randomNet(); if r.name == "でたらめ" && OrigamiState.validNet(r.p4, 4) && OrigamiState.validNet(r.p3, 3) { rnOK += 1 } }
            var asmWorst = 0.0
            for d in OrigamiState.netPresets + [OrigamiState.randomNet(), NetAtlas.all[100].def, NetAtlas.all[260].def] {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.net = d; q.progress = 1; q.updateMats()
                let r0 = OrigamiState(); r0.reset(); r0.asmAuto = false; r0.progress = 1; r0.updateMats()
                for (ci, cell) in OrigamiState.cells(4).enumerated() {
                    let (fa, fv) = OrigamiState.fixed(cell, 4); var pp = [Double](repeating: 0.3, count: 4); pp[fa] = fv
                    let a = q.fold(cell, pp, 4), b = r0.fold(cell, pp, 4)
                    asmWorst = max(asmWorst, zip(a, b).map { abs($0 - $1) }.max() ?? 0); _ = ci
                }
            }
            print("展開図：\(pv)・でたらめ \(rnOK)/20・どれも組み上がりは同じ超立方体（ずれ \(String(format: "%.1e", asmWorst))）")
            // 展開図図鑑：木の数・種類の数・重ならないか・No.1 がダリ・見本の番号・長さごとの数・どれも正しい展開図か
            let t0 = Date(), A = NetAtlas.all, dt = Date().timeIntervalSince(t0)
            let hist = Dictionary(grouping: A, by: { $0.longest }).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.count)" }.joined(separator: " ")
            let allOK = A.allSatisfy { OrigamiState.validNet($0.def.p4, 4) && OrigamiState.validNet($0.def.p3, 3) && NetAtlas.number(of: $0.def.p4) == $0.id }
            let pn = OrigamiState.netPresets.map { "\($0.name) No.\(NetAtlas.number(of: $0.p4) ?? 0)" }.joined(separator: "・")
            // サイコロ：24 の目は 1〜24 がちょうど 2 回ずつ・向かいの和 25・48 の目は向かいの和 7・どの胞も奥へ向けられる・振ったら選んだ胞が奥に
            var c24 = [Int](repeating: 0, count: 25), opp25 = true, opp7 = true
            for c in 0..<8 { let fs = OrigamiState.diceFaces(c); for fi in 0..<6 {
                let r = OrigamiState.diceResult(c, fi, 24); c24[r.n24] += 1
                let (a, s) = OrigamiState.cellNormal(c, 4); if OrigamiState.diceSquare(a, -s, fs[fi].b, -fs[fi].t) != 25 - r.n24 { opp25 = false }
                if fi % 2 == 0 && OrigamiState.dicePips[fi] + OrigamiState.dicePips[fi + 1] != 7 { opp7 = false }
            } }
            var farOK = 0
            for c in 0..<8 {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.progress = 1; q.diceOneShot = false; q.rollDice(fixed: (c, c % 6))
                for _ in 0..<170 { q.tick(1.0 / 60) }
                let (a, s0) = OrigamiState.cellNormal(c, 4); var v = SIMD4<Double>(0, 0, 0, 0); v[a] = s0
                if (q.m4 * v).w < -0.999 && q.diceRoll?.phase == 1 { farOK += 1 }
            }
            // 一発：48 通り全部で、止まった時に選んだ胞が 4 次元の手前・選んだ面がまっすぐ手前（＋z に近い）・出た目が記録される
            var oneOK = 0, worstZ = 1.0
            for c in 0..<8 { for fi in 0..<6 {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.progress = 1; q.diceOneShot = true; q.xz = 0.35; q.yz = -0.3; q.rollDice(fixed: (c, fi))
                for _ in 0..<235 { q.tick(1.0 / 60) }
                let (a, s0) = OrigamiState.cellNormal(c, 4), f = OrigamiState.diceFaces(c)[fi]
                var v = SIMD4<Double>(0, 0, 0, 0); v[a] = s0; var e = SIMD4<Double>(0, 0, 0, 0); e[f.b] = f.t
                let fz = (q.m4 * e).z; worstZ = min(worstZ, fz)
                if (q.m4 * v).w > 0.999 && fz > 0.9 && q.diceRes?.cell == c && q.diceRes?.face == fi && q.diceRoll?.phase == 2 { oneOK += 1 }
            } }
            print("サイコロ：24 の目 2 回ずつ \(c24.dropFirst().allSatisfy { $0 == 2 } ? "○" : "×")・向かいの和 25 \(opp25 ? "○" : "×")・48 の目 向かいの和 7 \(opp7 ? "○" : "×")・奥へ向ける角度 \(OrigamiState.diceTargets.map { $0.count })・振ると選んだ胞が奥に \(farOK)/8・一発 \(oneOK)/48（手前の向き いちばん悪くて \(String(format: "%.3f", worstZ))）")
            // 組み変わり：前の展開図 → 次の展開図の変換が、はじめ・おわりでぴったり・途中も形がくずれない（直交のまま）
            var mEnd = 0.0, mOrth = 0.0, mCnt = 0
            for (k, kk) in stride(from: 0, to: 261, by: 13).enumerated() {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.progress = k % 3 == 0 ? 0.4 : 0
                let n = k % 2 == 0 ? 4 : 3, from = NetAtlas.all[(kk * 7) % 261].def, to = NetAtlas.all[kk].def
                let A = q.rawTransforms(n == 4 ? from.p4 : from.p3, n), B = q.rawTransforms(n == 4 ? to.p4 : to.p3, n)
                for i in A.indices {
                    let a0 = OrigamiState.morphAff(A[i], B[i], 0, OrigamiState.cellNormal(i, n), n), a1 = OrigamiState.morphAff(A[i], B[i], 1, OrigamiState.cellNormal(i, n), n), am = OrigamiState.morphAff(A[i], B[i], 0.5, OrigamiState.cellNormal(i, n), n)
                    for r in 0..<n {
                        mEnd = max(mEnd, abs(a0.t[r] - A[i].t[r]), abs(a1.t[r] - B[i].t[r]))
                        for c in 0..<n {
                            mEnd = max(mEnd, abs(a0.M[r][c] - A[i].M[r][c]), abs(a1.M[r][c] - B[i].M[r][c]))
                            let dot = (0..<n).reduce(0.0) { $0 + am.M[r][$1] * am.M[c][$1] }; mOrth = max(mOrth, abs(dot - (r == c ? 1 : 0)))
                        }
                    }
                    mCnt += 1
                }
            }
            // 図鑑の展開図の段の数（真ん中の胞からの深さ）を、いちばん長いつながりごとに
            var stg: [Int: [Int: Int]] = [:]
            for e in NetAtlas.all { let D = OrigamiState.depths(e.def.p4).max() ?? 0; stg[e.longest, default: [:]][D, default: 0] += 1 }
            print("段の数（長さ:深さ×数）：" + stg.keys.sorted().map { L in "\(L):" + stg[L]!.keys.sorted().map { "\($0)段×\(stg[L]![$0]!)" }.joined(separator: ",") }.joined(separator: " "))
            // 多段階：最大の段数で段がまとまるか（深さ 4 の展開図で、最大 1〜4 段のときの深さ 1〜4 の段の番号）
            let qs = OrigamiState(); qs.reset(); qs.asmAuto = false; qs.net = NetAtlas.all[250].def
            let stTxt = (1...4).map { m -> String in
                qs.foldMaxStages = m; qs.foldStagger = m > 1
                // 段の始まりで見分ける：折り角が 0 でなくなる最初の進み
                let starts = (1...4).map { d -> Double in var t = 0.0; while t < 1 { qs.progress = t; if qs.foldTheta(d, 4) > 1e-6 { break }; t += 0.01 }; return t }
                return "最大\(m)段→" + starts.map { String(format: "%.2f", $0) }.joined(separator: "/")
            }.joined(separator: "  ")
            // 一筆：どの展開図でも、全部のちょうつがいが 1 回ずつ出てくる・組み上がりは同じ超立方体・いちばん先に動くのは はしっこ
            var cOK = 0, cWorst = 0.0, cTip = 0
            for e in stride(from: 0, to: 261, by: 7).map({ NetAtlas.all[$0] }) {
                let qc = OrigamiState(); qc.reset(); qc.asmAuto = false; qc.foldCourse = true; qc.net = e.def
                let ord = qc.courseOrder(e.def.p4)
                if Set(ord) == Set(1..<8) && ord.count == 7 { cOK += 1 }
                qc.progress = 0.03; let firstMoving = (1..<8).filter { qc.courseTheta($0, ord) > 1e-9 }
                if firstMoving == [ord[0]] { cTip += 1 }
                qc.progress = 1; qc.updateMats(); let r0 = OrigamiState(); r0.reset(); r0.asmAuto = false; r0.progress = 1; r0.updateMats()
                for cell in OrigamiState.cells(4) {
                    let (fa, fv) = OrigamiState.fixed(cell, 4); var pp = [Double](repeating: 0.3, count: 4); pp[fa] = fv
                    cWorst = max(cWorst, zip(qc.fold(cell, pp, 4), r0.fold(cell, pp, 4)).map { abs($0 - $1) }.max() ?? 0)
                }
            }
            // ころころ：転がっている間はゴールの胞が床に止まったまま・転がり終わりと返し始めがつながる・最後はいつもの向き
            var rollStay = 0.0, rollJump = 0.0
            for e in stride(from: 0, to: 261, by: 13).map({ NetAtlas.all[$0] }) {
                let qc = OrigamiState(); qc.reset(); qc.asmAuto = false; qc.foldCourse = true; qc.net = e.def
                _ = qc.courseOrder(e.def.p4); let r = qc.courseRootCache[qc.courseKey(e.def.p4)] ?? 0
                qc.progress = 0; let F = qc.rawTransforms(e.def.p4, 4)[r]
                for t in [0.1, 0.3, 0.5, 0.7, 0.79] {
                    qc.progress = t; let T = qc.rawTransforms(e.def.p4, 4)[r]
                    for i in 0..<4 { rollStay = max(rollStay, abs(T.t[i] - F.t[i])); for j in 0..<4 { rollStay = max(rollStay, abs(T.M[i][j] - F.M[i][j])) } }
                }
                qc.progress = OrigamiState.COURSE_ROLL - 1e-6; let a = qc.rawTransforms(e.def.p4, 4)
                qc.progress = OrigamiState.COURSE_ROLL + 1e-6; let b = qc.rawTransforms(e.def.p4, 4)
                for (x, y) in zip(a, b) { for i in 0..<4 { rollJump = max(rollJump, abs(x.t[i] - y.t[i])); for j in 0..<4 { rollJump = max(rollJump, abs(x.M[i][j] - y.M[i][j])) } } }
            }
            print("ころころ：転がる間ゴールの胞は止まったまま（ずれ \(String(format: "%.1e", rollStay))）・転がり終わり→返しのつなぎ目 \(String(format: "%.1e", rollJump))")
            let nC = stride(from: 0, to: 261, by: 7).map { $0 }.count
            print("一筆：順がそろう \(cOK)/\(nC)・はしから動き出す \(cTip)/\(nC)・組み上がりのずれ \(String(format: "%.1e", cWorst))")
            print("多段階（深さ 1〜4 の折りはじめ）：\(stTxt)")
            // 組み上がりの向き：角度の分け直しが元にもどる・組み立てると選んだ向きに着地・展開で W 消失にもどる
            var dErr = 0.0
            for k in 0..<40 {
                let a = (0..<6).map { j in sin(Double(k * 7 + j * 3) * 1.3) * 2.5 }
                let M = OrigamiState.rot6(a), b = OrigamiState.decompose4(M, prev3: [0, 0, 0]), M2 = OrigamiState.rot6(b)
                for c in 0..<4 { for r in 0..<4 { dErr = max(dErr, abs(M[c][r] - M2[c][r])) } }
            }
            var landErr = 0.0, unW = 0.0, landN = 0, vanErr = 0.0
            for pose in [1, 2, 3, 4, 5] { for van in [3, 0, 1, 2] {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.poseMemory = false; q.progress = 0; q.asmPose = pose; q.asmVanish = van; q.asmFree = [20, -35, 50, 10, 30, -15]; q.unfPose = 1
                q.xz = 0.4; q.yz = -0.3; q.updateMats()
                guard let tg = q.asmTarget() else { continue }
                q.playFold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                let A = OrigamiState.rot6(tg.ang), B = q.m4
                for c in 0..<4 { for r in 0..<4 { landErr = max(landErr, abs(A[c][r] - B[c][r])) } }
                // 消失軸：その軸が 4D の奥（w）へ向いているか
                if van != 3 && pose == 1 { var e = SIMD4<Double>(0, 0, 0, 0); e[van] = 1; let v = q.m4 * e; vanErr = max(vanErr, 1 - abs(v.w)) }   // 胞から × 消失軸：その軸が 4D の奥へ
                q.playUnfold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                unW = max(unW, abs(q.ax), abs(q.ay), abs(q.zw)); landN += 1
            } }
            var unfErr = 0.0
            for up in 1...6 {
                let q = OrigamiState(); q.reset(); q.asmAuto = false; q.poseMemory = false; q.progress = 0; q.asmPose = 4; q.asmVanish = 1; q.unfPose = up; q.unfFree = [15, 25, -30, 40, -20, 10]
                q.xz = 0.3; q.yz = 0.2; q.updateMats(); q.playFold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                let want = q.unfTarget()!; q.playUnfold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                for (a, b) in zip(want, q.cur6) { unfErr = max(unfErr, abs(OrigamiState.wrapPi(a - b))) }
            }
            // 基本にもどす：設定が基本になり、角度が全部 0 へ
            let qb = OrigamiState(); qb.reset(); qb.asmAuto = false; qb.asmBasic = nil; qb.progress = 1; qb.asmPose = 4; qb.asmVanish = 0; qb.unfPose = 5; qb.ax = 0.7; qb.yz = 0.4; qb.xz = -0.3; qb.updateMats()
            qb.asmResetBasic(); for _ in 0..<120 { qb.tick(1.0 / 60) }
            // 自分の基本：覚えて、変えて、もどすと、設定も形の向きも覚えた所へ（確かめのあとは消す）
            let keepB = UserDefaults.standard.data(forKey: AsmBasic.key)
            let qm = OrigamiState(); qm.reset(); qm.asmAuto = false; qm.progress = 0; qm.asmPose = 3; qm.asmVanish = 2; qm.unfPose = 0; qm.ax = 0.3; qm.xz = 0.8; qm.yz = -0.2; qm.updateMats()
            qm.asmSaveBasic(); let want = qm.cur6
            qm.asmPose = 1; qm.asmVanish = 3; qm.unfPose = 2; qm.ax = -1; qm.xz = 0; qm.updateMats()
            qm.asmResetBasic(); for _ in 0..<120 { qm.tick(1.0 / 60) }
            let myOK = qm.asmPose == 3 && qm.asmVanish == 2 && qm.unfPose == 0 && qm.asmIsBasic
            let myErr = zip(want, qm.cur6).map { abs(OrigamiState.wrapPi($0 - $1)) }.max() ?? 0
            qm.asmFactoryBasic(); for _ in 0..<120 { qm.tick(1.0 / 60) }
            let facOK = qm.asmBasic == nil && qm.asmPose == 0 && qm.unfPose == 0 && (qm.cur6.map { abs(OrigamiState.wrapPi($0)) }.max() ?? 1) < 1e-9
            if !SaveGuard.off { if let keepB { UserDefaults.standard.set(keepB, forKey: AsmBasic.key) } else { UserDefaults.standard.removeObject(forKey: AsmBasic.key) } }
            // 状態のプリセット：保存した向き・展開図・組み具合にもどる。そのあとカメラで回すと、その向きのまま往復（組む・開くで回さない）。
            //   「まっすぐ」なら開いた時に 4D の角度だけ 0 に
            let qr = OrigamiState(); qr.reset(); qr.asmAuto = false; qr.poseMemory = false; qr.asmPresets = []; qr.progress = 1; qr.unfPose = 0; qr.netAnim = false
            qr.ax = 2.9; qr.ay = -0.4; qr.zw = 0.3; qr.xy = 2.8; qr.xz = 2.6; qr.yz = -2.7; qr.updateMats(); qr.net = NetAtlas.all[77].def
            let S = qr.cur6; qr.saveSnapshotPreset(); let sp = qr.asmPresets.last!
            qr.ax = 0; qr.ay = 0; qr.zw = 0; qr.xy = 0; qr.xz = 0; qr.yz = 0; qr.net = OrigamiState.netDali; qr.progress = 0; qr.updateMats()
            qr.loadAsmPreset(sp); for _ in 0..<90 { qr.tick(1.0 / 60) }
            var sErr = 0.0; for k in 0..<6 { sErr = max(sErr, abs(OrigamiState.wrapPi(S[k] - qr.cur6[k]))) }
            let sOK = qr.net.p4 == NetAtlas.all[77].def.p4 && qr.progress == 1
            qr.xz += 0.7; qr.updateMats(); let Rr = qr.cur6
            qr.playUnfold(); for _ in 0..<200 { qr.tick(1.0 / 60) }; qr.playFold(); for _ in 0..<200 { qr.tick(1.0 / 60) }
            var keepErr = 0.0; for k in 0..<6 { keepErr = max(keepErr, abs(OrigamiState.wrapPi(Rr[k] - qr.cur6[k]))) }
            qr.unf4 = 2; qr.saveSnapshotPreset(); qr.loadAsmPreset(qr.asmPresets.last!); for _ in 0..<70 { qr.tick(1.0 / 60) }
            qr.playUnfold(); for _ in 0..<200 { qr.tick(1.0 / 60) }
            let straightOK = abs(qr.ax) < 1e-9 && abs(qr.ay) < 1e-9 && abs(qr.zw) < 1e-9          // 4D 別々：開くとまっすぐ（はじめはいちばん近いまっすぐ）
            // リセット：前のプリセットの着地の設定（自由 × 自由）が残っていても、向きを保つにもどる
            let qz = OrigamiState(); qz.reset(); qz.asmAuto = false; qz.asmPose = 5; qz.asmFree = [40, 0, 0, 30, 0, 0]; qz.unfPose = 6; qz.resetAll()
            let rzOK = qz.asmPose == 0 && qz.asmVanish == 3 && qz.unfPose == 0 && qz.asmTarget() == nil && qz.unfTarget() == nil
            // 投影：W の角度 0 のいつもの形でも、平行投影を選ぶと平行に移る（前は何も変わらなかった）
            let qp = OrigamiState(); qp.reset(); qp.asmAuto = false; qp.progress = 1; qp.perspMode = false; for _ in 0..<60 { qp.tick(1.0 / 60) }
            let pOn = qp.projBlend; qp.perspMode = true; for _ in 0..<60 { qp.tick(1.0 / 60) }
            print("投影：角度 0 で平行へ \(String(format: "%.2f", pOn))（1 のはず）・遠近へもどる \(String(format: "%.2f", qp.projBlend))（0 のはず）")
            print("リセットで着地の設定も消える \(rzOK ? "○" : "×")")
            // おまかせ：いちばん近いまっすぐ。まっすぐなら動かない・ゆがんでいれば 4D は 0 で、tr(Qᵀ A) が単純に 4D を 0 にしたより大きい（近い）・往復
            var nfStill = 0.0, nfBetter = true, nfFlat = 0.0
            var rng = SystemRandomNumberGenerator()
            for t in 0..<40 {
                let a3 = (0..<3).map { _ in Double.random(in: -3...3, using: &rng) }
                let f = OrigamiState.nearestFlat([0, 0, 0] + a3)
                for k in 0..<6 { nfStill = max(nfStill, abs(OrigamiState.wrapPi(f[k] - ([0, 0, 0] + a3)[k]))) }
                let c = (0..<6).map { _ in Double.random(in: -3...3, using: &rng) } + (t == 0 ? [] : [])
                let g = OrigamiState.nearestFlat(c), M = OrigamiState.rot6(c)
                func sc(_ a: [Double]) -> Double { let F = OrigamiState.rot6(a); var s = 0.0; for i in 0..<3 { for j in 0..<3 { s += F[j][i] * M[j][i] } }; return s }
                nfFlat = max(nfFlat, abs(g[0]), abs(g[1]), abs(g[2]))
                if sc(g) < sc([0, 0, 0, c[3], c[4], c[5]]) - 1e-9 { nfBetter = false }
                for _ in 0..<20 { let r = (0..<3).map { _ in Double.random(in: -3...3, using: &rng) }; if sc(g) < sc([0, 0, 0] + r) - 1e-9 { nfBetter = false } }
            }
            let qa = OrigamiState(); qa.reset(); qa.asmAuto = true; qa.progress = 1
            qa.ax = 0.7; qa.ay = -0.4; qa.zw = 0.5; qa.xy = 0.3; qa.xz = 0.6; qa.yz = -0.2; qa.updateMats(); let D0 = qa.cur6, Df = OrigamiState.nearestFlat(D0)
            qa.playUnfold(); for _ in 0..<220 { qa.tick(1.0 / 60) }
            var aE1 = 0.0; for k in 0..<6 { aE1 = max(aE1, abs(OrigamiState.wrapPi(Df[k] - qa.cur6[k]))) }
            qa.playFold(); for _ in 0..<220 { qa.tick(1.0 / 60) }
            var aE2 = 0.0; for k in 0..<6 { aE2 = max(aE2, abs(OrigamiState.wrapPi(D0[k] - qa.cur6[k]))) }
            print("おまかせ：まっすぐなら動かない（ずれ \(String(format: "%.1e", nfStill))）・4D の残り \(String(format: "%.1e", nfFlat))・いちばん近い \(nfBetter ? "○" : "×")・開くといちばん近いまっすぐへ（ずれ \(String(format: "%.1e", aE1))）・組むと前に組んだ向きへ（ずれ \(String(format: "%.1e", aE2))）")
            // おまかせ 1：4D の回し続けるは、開くと 3D に置きかわり（止まらない・4D は 0 のまま）、組むと 4D にもどる。おまかせ 2：今の向きのまま
            let qsp = OrigamiState(); qsp.reset(); qsp.autoMode = 1; qsp.progress = 1; qsp.ax = 0.5; qsp.zw = 0.3; qsp.xz = 0.4; qsp.updateMats(); qsp.spinX = true
            qsp.playUnfold(); for _ in 0..<240 { qsp.tick(1.0 / 60) }
            let sw1 = !qsp.spinX && qsp.spinXZ, flat0 = max(abs(qsp.ax), abs(qsp.ay), abs(qsp.zw)), xzA = qsp.xz
            for _ in 0..<30 { qsp.tick(1.0 / 60) }; let moving = abs(OrigamiState.wrapPi(qsp.xz - xzA)) > 1e-3 && abs(qsp.ax) < 1e-9
            qsp.playFold(); for _ in 0..<240 { qsp.tick(1.0 / 60) }
            let sw2 = qsp.spinX && !qsp.spinXZ
            let q2 = OrigamiState(); q2.reset(); q2.autoMode = 2; q2.progress = 1; q2.ax = 0.5; q2.zw = 0.3; q2.xz = 0.4; q2.updateMats(); let Z0 = q2.cur6
            q2.playUnfold(); for _ in 0..<240 { q2.tick(1.0 / 60) }
            var z2 = 0.0; for k in 0..<6 { z2 = max(z2, abs(OrigamiState.wrapPi(Z0[k] - q2.cur6[k]))) }
            print("おまかせ 1 の回し続ける：開くと 3D に \(sw1 ? "○" : "×")・4D の残り \(String(format: "%.1e", flat0))・開いたあとも回る \(moving ? "○" : "×")・組むと 4D にもどる \(sw2 ? "○" : "×")／おまかせ 2：開いても今の向き（ずれ \(String(format: "%.1e", z2))）")
            // 右上の札（3D に出ている軸の長さ）：回し続けると変わるか
            let qk = OrigamiState(); qk.reset(); qk.asmAuto = false; qk.progress = 1; qk.updateMats()
            func card(_ q: OrigamiState) -> [Int] {
                let c = q.m4.columns, cs: [SIMD4<Double>] = [c.0, c.1, c.2, c.3]
                return cs.map { (v: SIMD4<Double>) -> Int in let l: Double = min(1.0, (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()); return Int((l * 100).rounded()) }
            }
            let cA = card(qk); qk.spinX = true; qk.spinY = true; qk.spinZW = true; qk.spinXY = true; for _ in 0..<90 { qk.tick(1.0 / 60) }; qk.updateMats(); let cB = card(qk)
            print("右上の札：回す前 \(cA)・4D と 3D を 1.5 秒回したあと \(cB)（ax \(String(format: "%.2f", qk.ax))）")
            // 積分の超球の輪切り：正確に写しただ円体の上に、輪切りの玉のふちの点（1 つずつ正確に写した点）がのっているか。近道とくらべる
            do {
                let sv = (st.m4, st.camW, st.projBlend, st.ax, st.ay, st.zw, st.xy, st.xz, st.yz)
                var eEx = 0.0, eAp = 0.0
                var rng2 = SystemRandomNumberGenerator()
                for _ in 0..<12 {
                    st.ax = Double.random(in: -1.2...1.2, using: &rng2); st.ay = Double.random(in: -1...1, using: &rng2); st.zw = Double.random(in: -1...1, using: &rng2)
                    st.xy = Double.random(in: -3...3, using: &rng2); st.xz = Double.random(in: -3...3, using: &rng2); st.yz = Double.random(in: -3...3, using: &rng2)
                    st.projBlend = 0; st.updateMats()
                    let pos = Double.random(in: -0.9...0.9, using: &rng2), R = (1 - pos * pos).squareRoot(), Hh = OrigamiState.half
                    func Pp(_ u: [Double]) -> SIMD3<Double> { st.place(u.map { $0 * Hh } + [pos * Hh], 4).0 }
                    let C0 = Pp([0, 0, 0]), E0 = [Pp([R, 0, 0]), Pp([0, R, 0]), Pp([0, 0, R])]
                    let ex = r4.exactBall(SIMD4(0, 0, 0, pos), R, approxC: C0, approxE: E0, spin: 0, alpha: 1), ap = OrigamiRenderer.ellipsoid(C0, E0, spin: 0, alpha: 1)
                    func err(_ e: IntSphere) -> Double {
                        let Mx = simd_double3x3(columns: (SIMD3<Double>(Double(e.ax.x), Double(e.ax.y), Double(e.ax.z)), SIMD3<Double>(Double(e.ay.x), Double(e.ay.y), Double(e.ay.z)), SIMD3<Double>(Double(e.az.x), Double(e.az.y), Double(e.az.z)))).inverse
                        let cc = SIMD3<Double>(Double(e.c.x), Double(e.c.y), Double(e.c.z))
                        var m = 0.0
                        for _ in 0..<40 {
                            var u = SIMD3<Double>(Double.random(in: -1...1, using: &rng2), Double.random(in: -1...1, using: &rng2), Double.random(in: -1...1, using: &rng2)); u = simd_normalize(u) * R
                            let q = Pp([u.x, u.y, u.z]), g = SIMD3<Double>(q.x, -q.z, q.y)
                            m = max(m, abs(simd_length(Mx * (g - cc)) - 1))
                        }
                        return m
                    }
                    eEx = max(eEx, err(ex)); eAp = max(eAp, err(ap))
                }
                st.ax = sv.3; st.ay = sv.4; st.zw = sv.5; st.xy = sv.6; st.xz = sv.7; st.yz = sv.8; st.camW = sv.1; st.projBlend = sv.2; st.updateMats()
                print("積分の超球の輪切り（遠近）：正確に写しただ円体からのずれ \(String(format: "%.1e", eEx))・近道（ぷよぷよ）は \(String(format: "%.2f", eAp))")
            }
            // 2 つの向き（おまかせ 1＝4D 別々・3D 共通）：4D でゆがませて組む → 開く（いちばん近いまっすぐ）→ 開いたまま 3D で回す →
            //   組むと 4D のかたむきがもどり、3D に回した分も持ちこむ → 組んだまま 4D で回す → 開くと開いた時の 4D（0）のまま →
            //   開いたまま 4D で回す → 組む → 開くと、開いた時の 4D のかたむき（回した分）にもどる
            func mErr(_ a: simd_double4x4, _ b: simd_double4x4) -> Double { var e = 0.0; for i in 0..<4 { for j in 0..<4 { e = max(e, abs(a[i][j] - b[i][j])) } }; return e }
            func run(_ q: OrigamiState, _ up: Bool) { if up { q.playFold() } else { q.playUnfold() }; for _ in 0..<240 { q.tick(1.0 / 60) } }
            let q1 = OrigamiState(); q1.reset(); q1.autoMode = 1; q1.progress = 1
            q1.ax = 0.6; q1.ay = -0.25; q1.zw = 0.35; q1.xy = 0.2; q1.xz = 0.45; q1.yz = -0.3; q1.updateMats(); let A0 = q1.cur6
            run(q1, false); let B0 = q1.cur6
            var t1 = 0.0; for k in 0..<6 { t1 = max(t1, abs(OrigamiState.wrapPi(OrigamiState.nearestFlat(A0)[k] - B0[k]))) }
            q1.xz += 0.5; q1.updateMats(); let B1 = q1.cur6
            run(q1, true)
            let expA = OrigamiState.rot3(B1) * OrigamiState.rot3(B0).transpose * OrigamiState.rot6(A0)   // 3D に回した分を掛けた、組んだ時の向き
            let t2 = mErr(OrigamiState.rot6(q1.cur6), expA), t2w = max(abs(OrigamiState.wrapPi(q1.ax - A0[0])), abs(OrigamiState.wrapPi(q1.ay - A0[1])), abs(OrigamiState.wrapPi(q1.zw - A0[2])))
            q1.ax += 0.3; q1.updateMats(); let A1 = q1.cur6
            run(q1, false)
            let t3 = max(abs(q1.ax), abs(q1.ay), abs(q1.zw)), t3b = mErr(OrigamiState.rot6(q1.cur6), OrigamiState.rot6(B1))
            q1.ay += 0.4; q1.updateMats(); let B2 = q1.cur6
            run(q1, true)
            let t4 = mErr(OrigamiState.rot6(q1.cur6), OrigamiState.rot6(A1))
            run(q1, false)
            let t5 = mErr(OrigamiState.rot6(q1.cur6), OrigamiState.rot6(B2))
            print("2 つの向き（4D 別々・3D 共通）：はじめはいちばん近いまっすぐ（ずれ \(String(format: "%.1e", t1))）・組むと 4D がもどる（\(String(format: "%.1e", t2w))）・3D に回した分も持ちこむ（\(String(format: "%.1e", t2))）・組んだまま 4D で回しても開くとまっすぐ（4D の残り \(String(format: "%.1e", t3))・開いた時の向き \(String(format: "%.1e", t3b))）・組むと組んだ時の向き（\(String(format: "%.1e", t4))）・開くと開いた時の 4D も往復（\(String(format: "%.1e", t5))）")
            // 表：3D も別々：開いたまま 3D で回しても、組むと組んだ時の向きそのもの。もう一度開くと、回した展開図の向き
            let q3 = OrigamiState(); q3.reset(); q3.autoMode = 0; q3.sep4 = true; q3.sep3 = true; q3.progress = 1
            q3.ax = 0.5; q3.zw = -0.3; q3.xy = 0.3; q3.xz = -0.4; q3.yz = 0.2; q3.updateMats(); let C0 = q3.cur6
            run(q3, false); q3.yz += 0.6; q3.updateMats(); let D1 = q3.cur6
            run(q3, true); let u1 = mErr(OrigamiState.rot6(q3.cur6), OrigamiState.rot6(C0))
            run(q3, false); let u2 = mErr(OrigamiState.rot6(q3.cur6), OrigamiState.rot6(D1))
            // 表：4D 共通・3D 共通（おまかせ 2 と同じ）＝今の向きのまま
            q3.sep4 = false; q3.sep3 = false; q3.ax = 0.4; q3.updateMats(); let E0 = q3.cur6
            run(q3, true); let u3 = mErr(OrigamiState.rot6(q3.cur6), OrigamiState.rot6(E0))
            print("表で 3D も別々：組むと組んだ時の向き（ずれ \(String(format: "%.1e", u1))）・開くと回した展開図の向き（\(String(format: "%.1e", u2))）／両方共通は今のまま（\(String(format: "%.1e", u3))）")
            // 目印の磁石：頂点から見る向き（4D でかたむけた形でも）から 1.4° ずらして手を離すと、吸いついてちょうど重なる（4D の角度は変えない）
            do {
                var mg: [String] = []
                for tilt in [[0.0, 0, 0], [0.5, -0.3, 0.25]] {
                    let q = OrigamiState(); q.reset(); q.progress = 1; q.ax = tilt[0]; q.ay = tilt[1]; q.zw = tilt[2]; q.updateMats()
                    q.markMagnet = false; q.markTick(0)                                 // まずちょうど重なる向きを作る（磁石と同じ計算を一気に）
                    let nr = q.place(q.fold(.cap, [1, 1, 1, 1], 4), 4).0, fr = q.place(q.fold(.center, [-1, -1, -1, -1], 4), 4).0, o0 = q.place([0, 0, 0, 0], 4).0
                    let ev = simd_normalize(SIMD3<Double>(q.center[1].x, q.center[1].y, q.dist[1]) - o0), av = simd_normalize(nr - fr)
                    let axv = simd_cross(av, ev), Q = simd_double4x4(simd_quatd(angle: acos(min(1, simd_dot(av, ev))), axis: simd_normalize(axv)))
                    let d = OrigamiState.decompose(Q * OrigamiState.rot3(q.cur6), [q.xy, q.xz, q.yz]); q.xy = d[0]; q.xz = d[1]; q.yz = d[2]; q.updateMats()
                    q.markTick(0); let a0 = q.markAlign
                    q.yz += 0.025; q.updateMats(); q.markTick(0); let a1 = q.markAlign
                    q.markMagnet = true; q.markFlashT = 9; q.dragging = true; for _ in 0..<30 { q.markTick(1.0 / 60) }; let held = q.markAlign
                    q.dragging = false; for _ in 0..<90 { q.markTick(1.0 / 60) }
                    let w4 = max(abs(q.ax - tilt[0]), abs(q.ay - tilt[1]), abs(q.zw - tilt[2]))
                    mg.append("4D \(tilt == [0, 0, 0] ? "なし" : "かたむけ")：始め \(String(format: "%.1e", a0))・ずらす \(String(format: "%.2f", a1 * 180 / .pi))°・つかんでいる間 \(String(format: "%.2f", held * 180 / .pi))°・離すと \(String(format: "%.1e", q.markAlign))・光 \(q.markFlashT < 2 ? "○" : "×")・4D の変化 \(String(format: "%.1e", w4))")
                }
                let far = OrigamiState(); far.reset(); far.progress = 1; far.xz = -0.7854 + 0.1; far.yz = 0.6155; far.updateMats(); let fa0 = far.cur6; for _ in 0..<60 { far.markTick(1.0 / 60) }
                print("目印の磁石：" + mg.joined(separator: "／") + "／5.7° はなれていると動かない \(far.cur6 == fa0 ? "○" : "×")")
            }
            // 内接球の回転：模様の点は球の上のまま（半径 1）・逆の回転でもどる・二重回転 1 : 1 は止まる点がない（どの点も同じだけ動く）
            do {
                let q = OrigamiState(); q.reset(); q.inSphere = true; q.inSphereT = 0.8
                var rE = 0.0, iE = 0.0, mv = (9.0, 0.0)
                for spinM in [1, 2] { q.inSphereSpin = spinM
                    for _ in 0..<200 {
                        let v = simd_normalize(SIMD4<Double>(Double.random(in: -1...1), Double.random(in: -1...1), Double.random(in: -1...1), Double.random(in: -1...1)))
                        let s1 = q.sphereSpun(v, n: 4), b = q.sphereSpun(s1, n: 4, inv: true)
                        rE = max(rE, abs(simd_length(s1) - 1)); iE = max(iE, simd_length(b - v))
                        if spinM == 2 { let dd = simd_distance(s1, v); mv = (min(mv.0, dd), max(mv.1, dd)) }
                    }
                }
                print("内接球の回転：半径のずれ \(String(format: "%.1e", rE))・逆でもどる \(String(format: "%.1e", iE))・二重回転 1 : 1 で動いた量 \(String(format: "%.4f", mv.0))〜\(String(format: "%.4f", mv.1))（みな同じ＝止まる点なし）")
            }
            print("状態のプリセット：もどった向きのずれ \(String(format: "%.1e", sErr))・展開図と組み具合 \(sOK ? "○" : "×")・回したあとの往復で向きを保つ（ずれ \(String(format: "%.1e", keepErr))）・まっすぐなら 4D だけ 0 \(straightOK ? "○" : "×")")
            print("自分の基本：設定 \(myOK ? "○" : "×")・形の向きのずれ \(String(format: "%.1e", myErr))・最初の基本にもどす \(facOK ? "○" : "×")")
            print("基本にもどす：設定 \(qb.asmIsBasic ? "○" : "×")・角度の残り \(String(format: "%.1e", qb.cur6.map { abs(OrigamiState.wrapPi($0)) }.max() ?? 0))")
            print("展開の向き：6 通り（W 消失・W 正面 Z 正面・上・横・ななめ・自由）の着地のずれ \(String(format: "%.1e", unfErr))")
            print("組み上がりの向き：分け直し \(String(format: "%.1e", dErr))・\(landN) 通り着地のずれ \(String(format: "%.1e", landErr))・消失軸が奥へ \(String(format: "%.1e", vanErr))・展開で W 消失へ（残り \(String(format: "%.1e", unW))）")
            print("組み変わり：\(mCnt) 胞・はじめとおわりのずれ \(String(format: "%.1e", mEnd))・途中の直交のずれ \(String(format: "%.1e", mOrth))")
            print("展開図図鑑：木 \(NetAtlas.built.trees) 通り・\(A.count) 種類・重ならない \(A.filter { $0.valid }.count)・No.1 \(A[0].def.p4 == OrigamiState.netDali.p4 ? "ダリ○" : "×\(A[0].def.p4)")・全部正しい \(allOK ? "○" : "×")・\(pn)・長さ \(hist)・作る時間 \(String(format: "%.0f", dt * 1000)) ms")
            print("往復の間の 3D 回転：往復は続く \(running ? "○" : "×")・見る向きが回る \(turned ? "○" : "×")・止めても見た目そのまま \(diff < 1e-6 ? "○" : "×（\(diff)）")")
        }
        // 往復・回転アニメ・どこから見るの確かめ（窓を開かずに時間だけ進める）
        do {
            let s3 = OrigamiState(); s3.reset()
            for ease in ["spring", "sine", "turn", "cradle", "bounce"] {
                s3.reset(); s3.ppEase = ease; s3.ppSec = 1; s3.ppFillViews(); s3.ppOnceFwd = true
                s3.startPP(s3.ppStops, once: false)
                var hit = [false, false, false, false]
                for _ in 0..<(60 * 8) {
                    s3.tick(1.0 / 60)
                    for (k, v) in s3.ppStops.enumerated() where zip(v, s3.angles6Deg).allSatisfy({ abs($0 - $1) < 0.6 }) { hit[k] = true }
                }
                s3.stopPP()
                print("往復（\(ease)）：A〜D を通った \(hit.map { $0 ? "○" : "×" }.joined())")
            }
            s3.reset(); s3.ppStops = [[0, 0, 0, 0, 0, 0], [90, 0, 0, 0, 0, 0]]; s3.ppOnce()
            for _ in 0..<(60 * 6) { s3.tick(1.0 / 60) }
            print(String(format: "片道 A→B：X-W %.1f°（90° のはず）・止まった %@", s3.angles6Deg[0], s3.pp == nil ? "○" : "×"))
            s3.reset(); s3.animXW = "60"; s3.animZW = "-30"; s3.playRotAnim()
            for _ in 0..<(60 * 2) { s3.tick(1.0 / 60) }
            print(String(format: "回転アニメ：X-W %.1f°・Y-W %.1f°・Z-W %.1f°（60・0・−30 のはず）", s3.angles6Deg[0], s3.angles6Deg[1], s3.angles6Deg[2]))
            // 回っている途中に次の 90° を押す：X を押して 0.4 秒後に Y、さらに 0.3 秒後に X をもう一度 → X-W 180°・Y-W 90° で止まるはず（前は途中の角度が残った）
            s3.reset(); s3.animXW = ""; s3.animZW = ""
            ShortcutStore.step90(s3, 0); for _ in 0..<24 { s3.tick(1.0 / 60) }
            ShortcutStore.step90(s3, 1); for _ in 0..<18 { s3.tick(1.0 / 60) }
            ShortcutStore.step90(s3, 0); for _ in 0..<(60 * 2) { s3.tick(1.0 / 60) }
            let dg = s3.angles6Deg
            print(String(format: "途中で 90° を重ねる：X-W %.1f°・Y-W %.1f°（180・90 のはず）%@", dg[0], dg[1], abs(abs(dg[0]) - 180) < 0.5 && abs(dg[1] - 90) < 0.5 ? "○" : "×"))
            // 同じキーの連打：Z を 0.1 秒おきに 2 回・3 回、と、Z を押してすぐ（0.02 秒）もう一度
            for (gap, times) in [(6, 2), (6, 3), (1, 2), (30, 2)] {
                s3.reset(); for _ in 0..<times { ShortcutStore.step90(s3, 2); for _ in 0..<gap { s3.tick(1.0 / 60) } }
                for _ in 0..<(60 * 3) { s3.tick(1.0 / 60) }
                let want = Double(times * 90).truncatingRemainder(dividingBy: 360), got = (s3.angles6Deg[2] + 360).truncatingRemainder(dividingBy: 360)
                print(String(format: "Z の連打（%d 回・%d コマおき）：Z-W %.1f°（%.0f のはず）%@", times, gap, s3.angles6Deg[2], want, abs(got - want) < 0.5 || abs(got - want) > 359.5 ? "○" : "×"))
            }
            // 回し続けている間に Z：X-W の回し続けるは止まらず、Z-W は 90° 回る
            s3.reset(); s3.spinX = true; ShortcutStore.step90(s3, 2); for _ in 0..<(60 * 3) { s3.tick(1.0 / 60) }
            print(String(format: "回し続けながら Z：X-W 回し続け %@・Z-W %.1f°（90 のはず）%@", s3.spinX ? "○" : "×", s3.angles6Deg[2], abs(s3.angles6Deg[2] - 90) < 0.5 ? "○" : "×"))
            s3.spinX = false
            // 「頂点から」へなめらかに移っている途中に Z：移り終わったあと Z-W が 30＋90＝120°
            s3.reset(); s3.goView(3, animated: true); for _ in 0..<20 { s3.tick(1.0 / 60) }
            ShortcutStore.step90(s3, 2); for _ in 0..<(60 * 3) { s3.tick(1.0 / 60) }
            print(String(format: "見方の移動の途中で Z：Z-W %.1f°（120 のはず）%@", s3.angles6Deg[2], abs(s3.angles6Deg[2] - 120) < 0.5 ? "○" : "×"))
            // 回っている途中に補正（S）：Z-W を回している途中で押す → Z-W 0° のまま
            s3.reset(); ShortcutStore.step90(s3, 2); for _ in 0..<20 { s3.tick(1.0 / 60) }
            s3.snap(); for _ in 0..<(60 * 2) { s3.tick(1.0 / 60) }
            print(String(format: "途中で補正：Z-W %.1f°（0 のはず）%@", s3.angles6Deg[2], abs(s3.angles6Deg[2]) < 0.5 ? "○" : "×"))
            s3.reset(); s3.goView(3, animated: true)
            for _ in 0..<(60 * 2) { s3.tick(1.0 / 60) }
            print(String(format: "頂点からへ移行：%.2f・%.2f・%.2f・投影 %.2f（45・35.26・30・1 のはず）", s3.angles6Deg[0], s3.angles6Deg[1], s3.angles6Deg[2], s3.projBlend))
        }
        if ProcessInfo.processInfo.environment["OGINSPH"] != nil {          // 確かめ：内接球の形を作る時間（CPU）と、描く時間
            for (lay, col, lon, sp) in [(6, 1, true, 0), (10, 0, true, 0), (10, 0, false, 0), (14, 0, true, 0), (10, 0, true, 1), (10, 0, true, 2), (10, 1, true, 2)] {
                st.reset(); st.progress = 1; st.inSphere = true; st.inSphereLayers = lay; st.inSphereColor = col; st.inSphereLon = lon; st.ax = 0.8; st.ay = 0.5; st.updateMats()
                st.inSphereSpin = sp; st.inSphereT = 0.7
                var rods: [TLRod] = []; let tg = CACurrentMediaTime(); var nv = 0
                for _ in 0..<20 { rods = []; nv = r4.inSphereGeometry(&rods, eye: SIMD3(0, 0, 9)).first?.verts.count ?? 0 }
                let cpu = (CACurrentMediaTime() - tg) / 20 * 1000
                let tr = CACurrentMediaTime(); for _ in 0..<30 { render(r4, t4) }
                let lab = (lon ? "・経度面" : "") + (sp == 1 ? "・3D 回転" : sp == 2 ? "・二重回転" : "")
                print(String(format: "内接球 %d 枚（%@%@）：形 %.1f ミリ秒・三角形の頂点 %d・線 %d・1 コマ全体 %.1f ミリ秒", 2 * lay - 1, col == 0 ? "アプリの色" : "レインボー", lab, cpu, nv, rods.count, (CACurrentMediaTime() - tr) / 30 * 1000))
            }
            st.inSphere = false
        }
        st.reset(); st.progress = 1; st.flashT = 9
        let t0 = CACurrentMediaTime()
        for _ in 0..<30 { render(r4, t4) }
        print(String(format: "右 %d×%d：1 コマ %.1f ミリ秒", w, h, (CACurrentMediaTime() - t0) / 30 * 1000))
        // 大きな画面（Retina の大きな窓の右半分くらい）
        let W2 = 1800, H2 = 1720, d2 = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W2, height: H2, mipmapped: false)
        d2.usage = [.renderTarget, .shaderRead]; d2.storageMode = .private
        if let big = d.makeTexture(descriptor: d2) {
            for (name, r) in [("左", r3), ("右", r4)] {
                let t1 = CACurrentMediaTime()
                for _ in 0..<20 {
                    let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = big; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
                    let cb = r.queue.makeCommandBuffer()!; r.encode(cb, rpd, W2, H2, now: 12.3, dt: 0.3); cb.commit(); cb.waitUntilCompleted()
                }
                print(String(format: "%@ %d×%d：1 コマ %.1f ミリ秒", name, W2, H2, (CACurrentMediaTime() - t1) / 20 * 1000))
            }
        }
    }
}
#endif
