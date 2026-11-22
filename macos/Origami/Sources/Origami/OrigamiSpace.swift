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
    /// 確かめの絵（--ogpng 出力先）：左の立方体と右の超立方体を並べた 1 枚を、組み立て具合ごとに
    static func png(_ dir: String) {
        guard let d = MTLCreateSystemDefaultDevice() else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let st = OrigamiState()
        guard let r3 = OrigamiRenderer(n: 3, state: st, device: d), let r4 = OrigamiRenderer(n: 4, state: st, device: d) else { print("組み立てに失敗"); return }
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
        let scenes: [(String, (OrigamiState) -> Void)] = [
            ("H1_内接球・正面", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.inSphere = true }),
            ("H2_内接球・W 回転", { $0.progress = 1; $0.spaceMode = 2; $0.ax = 0.8; $0.ay = 0.5; $0.inSphere = true }),
            ("Y9_球柱・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intShape = 1; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("YA_内接超球・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intShape = 4; $0.intN = 41; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
            ("YB_レインボーボール・X-W を回した（つぶれ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0.25; $0.yz = -0.2; $0.ax = 1.25; $0.ay = 0.2; $0.intOn = true; $0.intColor = 5; $0.intN = 9; $0.intT = $0.intFilledT; $0.intBallSpin = false; $0.intItems = $0.intUpdate() }),
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
            ("W2_水・いっぱい（揺れ）", { $0.progress = 1; $0.spaceMode = 2; $0.xz = 0; $0.yz = 0; $0.ax = 29 * .pi / 180; $0.ay = 17 * .pi / 180; $0.intOn = true; $0.intMethod = 1; $0.waterT = 0; $0.swe.reset(); for _ in 0..<Int(11.5 * 60) { $0.waterTick(1.0 / 60) } }),
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
            st.reset(); st.xz = 0.55; st.yz = -0.4; st.look = 0; st.spaceMode = 0; st.bgSpace = false; st.meshOn = false; st.explodeRaw = 0; st.flashT = 9; st.projBlend = 0; st.presetPar = nil; st.raster = true; st.depth3 = 1; st.mul4 = 0.6; st.glow4 = 0.3; st.glass4 = 0.8; st.reflSelf = 0.7; st.stripK = 0; st.line4 = 1; st.line4K = 1; st.ehOn = false; st.squash4 = 0.6; st.slant3 = 0.4; st.lineTint = 0; st.pal3 = OrigamiState.palDef3; st.pal4 = OrigamiState.palDef4; st.palComp = false; st.palCompCenter = false; st.axisSyncOn = false; st.netSolid = 1; st.fantasy = 1; st.warmth = 0; st.netMul = 0.5; st.net = OrigamiState.netDali; st.viewProj = 0; st.faceSide = 0; st.userPts = []; st.ptLabels = true; st.ptLeft = true; st.ptSize = 0.55; st.softMul = 0.5; st.smartLine = 0.7; st.pan = [.zero, .zero]; st.secOn = false; st.secPos = 0; st.secInfo = ["", ""]; st.intOn = false; st.intItems = []; st.intLook = 0; st.intPaused = false; st.intFly = true; st.intOutOpp = false; st.intPace = 0; st.intAmount = 1; st.intAxes = 8; st.intMethod = 0; st.isPreview = false; st.showAxes = true; st.intShape = 0; st.inSphere = false; st.netMorph = nil; st.netAnim = true; st.foldMaxStages = 4; st.foldCourse = false; st.courseFromB = false; st.asmPose = 0; st.asmVanish = 3; st.unfPose = 0; st.asmLand = nil; st.asmLastP = -1; st.diceMode = 24; st.diceOneShot = true; st.diceFaces = false; st.diceEyeK = 0; st.diceDim = 0; st.diceRoll = nil; st.diceHold = nil; st.diceFlash = false; f(st)
            for _ in 0..<3 { render(r3, t3); render(r4, t4) }
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
        // NDGeom（ウェブ版 nd-geom の Swift 版）と、今の次元おりがみの式が同じか（5 次元へ広げる土台）
        do {
            let s2 = OrigamiState(); s2.reset(); s2.ax = 0.7; s2.ay = -0.4; s2.zw = 0.3; s2.xy = 0.2; s2.xz = 0.5; s2.yz = -0.3; s2.updateMats()
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
        }
        // 細い窓（境目を動かした時）でも見切れないか：横 300・縦 860 で、組み上がりと展開図
        do {
            let s4 = OrigamiState(); s4.reset(); s4.ax = 29 * .pi / 180; s4.ay = 17 * .pi / 180; s4.spaceMode = 2
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
            let s5 = OrigamiState(); s5.reset(); let ks = ShortcutStore()
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
            let g = OrigamiState(); g.reset(); g.ppStops = [[0, 0, 0, 0, 0, 0], [45, 35.26, 30, 0, 0, 0]]; g.startPP(g.ppStops, once: false)
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
            let h = OrigamiState(); h.reset(); h.ppStops = [[0, 0, 0, 0, 0, 0], [30, 0, 0, 0, 0, 0], [0, 30, 0, 0, 0, 0]]; h.ppSec = 2.5; h.ppPresets = []
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
                let q = OrigamiState(); q.reset(); q.net = d; q.progress = 1; q.updateMats()
                let r0 = OrigamiState(); r0.reset(); r0.progress = 1; r0.updateMats()
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
                let q = OrigamiState(); q.reset(); q.progress = 1; q.diceOneShot = false; q.rollDice(fixed: (c, c % 6))
                for _ in 0..<170 { q.tick(1.0 / 60) }
                let (a, s0) = OrigamiState.cellNormal(c, 4); var v = SIMD4<Double>(0, 0, 0, 0); v[a] = s0
                if (q.m4 * v).w < -0.999 && q.diceRoll?.phase == 1 { farOK += 1 }
            }
            // 一発：48 通り全部で、止まった時に選んだ胞が 4 次元の手前・選んだ面がまっすぐ手前（＋z に近い）・出た目が記録される
            var oneOK = 0, worstZ = 1.0
            for c in 0..<8 { for fi in 0..<6 {
                let q = OrigamiState(); q.reset(); q.progress = 1; q.diceOneShot = true; q.xz = 0.35; q.yz = -0.3; q.rollDice(fixed: (c, fi))
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
                let q = OrigamiState(); q.reset(); q.progress = k % 3 == 0 ? 0.4 : 0
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
            let qs = OrigamiState(); qs.reset(); qs.net = NetAtlas.all[250].def
            let stTxt = (1...4).map { m -> String in
                qs.foldMaxStages = m; qs.foldStagger = m > 1
                // 段の始まりで見分ける：折り角が 0 でなくなる最初の進み
                let starts = (1...4).map { d -> Double in var t = 0.0; while t < 1 { qs.progress = t; if qs.foldTheta(d, 4) > 1e-6 { break }; t += 0.01 }; return t }
                return "最大\(m)段→" + starts.map { String(format: "%.2f", $0) }.joined(separator: "/")
            }.joined(separator: "  ")
            // 一筆：どの展開図でも、全部のちょうつがいが 1 回ずつ出てくる・組み上がりは同じ超立方体・いちばん先に動くのは はしっこ
            var cOK = 0, cWorst = 0.0, cTip = 0
            for e in stride(from: 0, to: 261, by: 7).map({ NetAtlas.all[$0] }) {
                let qc = OrigamiState(); qc.reset(); qc.foldCourse = true; qc.net = e.def
                let ord = qc.courseOrder(e.def.p4)
                if Set(ord) == Set(1..<8) && ord.count == 7 { cOK += 1 }
                qc.progress = 0.03; let firstMoving = (1..<8).filter { qc.courseTheta($0, ord) > 1e-9 }
                if firstMoving == [ord[0]] { cTip += 1 }
                qc.progress = 1; qc.updateMats(); let r0 = OrigamiState(); r0.reset(); r0.progress = 1; r0.updateMats()
                for cell in OrigamiState.cells(4) {
                    let (fa, fv) = OrigamiState.fixed(cell, 4); var pp = [Double](repeating: 0.3, count: 4); pp[fa] = fv
                    cWorst = max(cWorst, zip(qc.fold(cell, pp, 4), r0.fold(cell, pp, 4)).map { abs($0 - $1) }.max() ?? 0)
                }
            }
            // ころころ：転がっている間はゴールの胞が床に止まったまま・転がり終わりと返し始めがつながる・最後はいつもの向き
            var rollStay = 0.0, rollJump = 0.0
            for e in stride(from: 0, to: 261, by: 13).map({ NetAtlas.all[$0] }) {
                let qc = OrigamiState(); qc.reset(); qc.foldCourse = true; qc.net = e.def
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
                let q = OrigamiState(); q.reset(); q.progress = 0; q.asmPose = pose; q.asmVanish = van; q.asmFree = [20, -35, 50, 10, 30, -15]; q.unfPose = 1
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
                let q = OrigamiState(); q.reset(); q.progress = 0; q.asmPose = 4; q.asmVanish = 1; q.unfPose = up; q.unfFree = [15, 25, -30, 40, -20, 10]
                q.xz = 0.3; q.yz = 0.2; q.updateMats(); q.playFold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                let want = q.unfTarget()!; q.playUnfold(); for _ in 0..<300 { q.tick(1.0 / 60) }
                for (a, b) in zip(want, q.cur6) { unfErr = max(unfErr, abs(OrigamiState.wrapPi(a - b))) }
            }
            // 基本にもどす：設定が基本になり、角度が全部 0 へ
            let qb = OrigamiState(); qb.reset(); qb.asmBasic = nil; qb.progress = 1; qb.asmPose = 4; qb.asmVanish = 0; qb.unfPose = 5; qb.ax = 0.7; qb.yz = 0.4; qb.xz = -0.3; qb.updateMats()
            qb.asmResetBasic(); for _ in 0..<120 { qb.tick(1.0 / 60) }
            // 自分の基本：覚えて、変えて、もどすと、設定も形の向きも覚えた所へ（確かめのあとは消す）
            let keepB = UserDefaults.standard.data(forKey: AsmBasic.key)
            let qm = OrigamiState(); qm.reset(); qm.progress = 0; qm.asmPose = 3; qm.asmVanish = 2; qm.unfPose = 0; qm.ax = 0.3; qm.xz = 0.8; qm.yz = -0.2; qm.updateMats()
            qm.asmSaveBasic(); let want = qm.cur6
            qm.asmPose = 1; qm.asmVanish = 3; qm.unfPose = 2; qm.ax = -1; qm.xz = 0; qm.updateMats()
            qm.asmResetBasic(); for _ in 0..<120 { qm.tick(1.0 / 60) }
            let myOK = qm.asmPose == 3 && qm.asmVanish == 2 && qm.unfPose == 0 && qm.asmIsBasic
            let myErr = zip(want, qm.cur6).map { abs(OrigamiState.wrapPi($0 - $1)) }.max() ?? 0
            qm.asmFactoryBasic(); for _ in 0..<120 { qm.tick(1.0 / 60) }
            let facOK = qm.asmBasic == nil && qm.asmPose == 0 && qm.unfPose == 0 && (qm.cur6.map { abs(OrigamiState.wrapPi($0)) }.max() ?? 1) < 1e-9
            if let keepB { UserDefaults.standard.set(keepB, forKey: AsmBasic.key) } else { UserDefaults.standard.removeObject(forKey: AsmBasic.key) }
            // 状態のプリセット：保存した向き・展開図・組み具合にもどる。そのあとカメラで回すと、その向きのまま往復（組む・開くで回さない）。
            //   「まっすぐ」なら開いた時に 4D の角度だけ 0 に
            let qr = OrigamiState(); qr.reset(); qr.asmPresets = []; qr.progress = 1; qr.unfPose = 0; qr.netAnim = false
            qr.ax = 2.9; qr.ay = -0.4; qr.zw = 0.3; qr.xy = 2.8; qr.xz = 2.6; qr.yz = -2.7; qr.updateMats(); qr.net = NetAtlas.all[77].def
            let S = qr.cur6; qr.saveSnapshotPreset(); let sp = qr.asmPresets.last!
            qr.ax = 0; qr.ay = 0; qr.zw = 0; qr.xy = 0; qr.xz = 0; qr.yz = 0; qr.net = OrigamiState.netDali; qr.progress = 0; qr.updateMats()
            qr.loadAsmPreset(sp); for _ in 0..<90 { qr.tick(1.0 / 60) }
            var sErr = 0.0; for k in 0..<6 { sErr = max(sErr, abs(OrigamiState.wrapPi(S[k] - qr.cur6[k]))) }
            let sOK = qr.net.p4 == NetAtlas.all[77].def.p4 && qr.progress == 1
            qr.xz += 0.7; qr.updateMats(); let Rr = qr.cur6
            qr.playUnfold(); for _ in 0..<200 { qr.tick(1.0 / 60) }; qr.playFold(); for _ in 0..<200 { qr.tick(1.0 / 60) }
            var keepErr = 0.0; for k in 0..<6 { keepErr = max(keepErr, abs(OrigamiState.wrapPi(Rr[k] - qr.cur6[k]))) }
            qr.unfPose = 1; qr.saveSnapshotPreset(); qr.loadAsmPreset(qr.asmPresets.last!); for _ in 0..<70 { qr.tick(1.0 / 60) }
            qr.playUnfold(); for _ in 0..<200 { qr.tick(1.0 / 60) }
            let straightOK = abs(qr.ax) < 1e-9 && abs(qr.ay) < 1e-9 && abs(qr.zw) < 1e-9 && abs(OrigamiState.wrapPi(qr.xz - Rr[4])) < 1e-9
            // リセット：前のプリセットの着地の設定（自由 × 自由）が残っていても、向きを保つにもどる
            let qz = OrigamiState(); qz.reset(); qz.asmPose = 5; qz.asmFree = [40, 0, 0, 30, 0, 0]; qz.unfPose = 6; qz.resetAll()
            let rzOK = qz.asmPose == 0 && qz.asmVanish == 3 && qz.unfPose == 0 && qz.asmTarget() == nil && qz.unfTarget() == nil
            print("リセットで着地の設定も消える \(rzOK ? "○" : "×")")
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
