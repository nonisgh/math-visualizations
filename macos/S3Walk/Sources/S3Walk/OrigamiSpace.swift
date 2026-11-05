// 次元おりがみ（ネイティブ版）の宇宙：展開図を組み立てていくと、紺の背景がだんだん星空になる。組み上がった瞬間に光の波が広がる。
//   星は「大きな超立方体（左は大きな立方体）の表面」に散らばった点。形と同じ回転で回すので、W 回転すると星空も 4 次元に回る。
//     見える向き：回したあとの xyz の向き（遠い空）。超立方体の星は w の手前（＋）ほど明るく大きく、奥（−）ほど暗く小さい。
//     天の川：大きな超立方体の 32 本の辺（立方体は 12 本）のまわりの細かい星くず。組み立ての最後のほうで灯る。
//   背景は星雲（深い紺に、右は紫・青、左は青・桃のうすい雲）。星は組み立て具合に合わせて 1 つずつ灯る（星ごとのしきい値）。
//   ほかの窓（超球の窓・さんぽ）には頼らない（いずれ別のアプリに分けられるように、ここだけで完結）。
import SwiftUI
import MetalKit

struct OGStar { var p, c, k: SIMD4<Float> }               // p：4D の位置、c：色・明るさ、k：灯るしきい値・種類（0 星・1 星くず・2 淡い光の雲）・またたきの位相
struct OGSkyU {
    var M = matrix_identity_float4x4                        // 星の回転（形と同じ）
    var a = SIMD4<Float>(0, 0, 0, 0)                        // 空の tan（縦の半分）・横÷縦・宇宙の量・時刻
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
    /// 星の回転（形と同じ順。左は X-Z → Y-Z → X-Y、右は X-W → Y-W → Z-W → X-Y → X-Z → Y-Z。遠近は使わない）
    func skyRot(_ n: Int) -> simd_float4x4 {
        let rs: [(Int, Int, Double)] = n == 4 ? [(0, 3, ax), (1, 3, ay), (2, 3, zw), (0, 1, xy), (0, 2, xz), (1, 2, yz)] : [(0, 2, ax), (1, 2, ay), (0, 1, xy)]
        var cols: [SIMD4<Float>] = []
        for i in 0..<4 {
            var v = [0.0, 0, 0, 0]; v[i] = 1
            if i < n { for (a, b, t) in rs { Self.rot(&v, a, b, t) } }
            cols.append(SIMD4(Float(v[0]), Float(v[1]), Float(v[2]), Float(v[3])))
        }
        return simd_float4x4(cols[0], cols[1], cols[2], cols[3])
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
    private let nebPipe, copyPipe, starPipe, flashPipe: MTLRenderPipelineState
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
        guard let a = pipe("ogq", "ogneb", add: false), let b = pipe("ogq", "ogcp", add: false), let c = pipe("skv", "skf", add: true), let e = pipe("ogq", "ogfl", add: true) else { return nil }
        nebPipe = a; copyPipe = b; starPipe = c; flashPipe = e
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
            ("1_展開図", { $0.progress = 0 }),
            ("2_組み立て0.45", { $0.progress = 0.45 }),
            ("3_組み立て0.75", { $0.progress = 0.75 }),
            ("4_組み上がり", { $0.progress = 1 }),
            ("5_光の波", { $0.progress = 1; $0.flashT = 0.5 }),
            ("6_W回転", { $0.progress = 1; $0.ax = 0.8; $0.ay = 0.5 }),
            ("7_宇宙切", { $0.progress = 1; $0.spaceMode = 2 }),
            ("8_宇宙入・展開図", { $0.progress = 0; $0.spaceMode = 1 }),
            ("9_プラケース", { $0.progress = 1; $0.look = 1 }),
        ]
        for (name, f) in scenes {
            st.reset(); st.xz = 0.55; st.yz = -0.4; st.look = 0; st.spaceMode = 0; st.flashT = 9; f(st)
            for _ in 0..<3 { render(r3, t3); render(r4, t4) }
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
        st.reset(); st.progress = 1; st.flashT = 9
        let t0 = CACurrentMediaTime()
        for _ in 0..<30 { render(r4, t4) }
        print(String(format: "右 %d×%d：1 コマ %.1f ミリ秒", w, h, (CACurrentMediaTime() - t0) / 30 * 1000))
    }
}
#endif
