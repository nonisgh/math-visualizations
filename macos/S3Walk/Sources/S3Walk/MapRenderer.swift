// S³ の地図（ウェブ版の真ん中の窓・buildB）：4 次元の点を回して（x-w・y-w・z-w）、遠近 k ＝ D／(D − w) で 3 次元へ写し、
//   ぐるっと回せる 3 次元の模型として描く。線は太さのある帯（画面の点で太さを決める）、玉は画面に向いた板に球の陰影、名前は文字の層
import Foundation
import Metal
import MetalKit
import QuartzCore
import AppKit
import simd

let RS = 1.8                     // 模型の半径（ウェブ版・次元おりがみと同じ）
let AXL = 2.7                    // 軸の長さ
let AXIS_RGB: [SIMD3<Float>] = [hexRGB(0xff5d6c), hexRGB(0x3ddc84), hexRGB(0x56a8ff), hexRGB(0xb07cff)]   // x・y・z・w

func f4(_ m: simd_double4x4) -> simd_float4x4 {
    simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
}
func hslF(_ hDeg: Double, _ s: Double, _ l: Double) -> SIMD3<Float> {
    let h = ((hDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    func f(_ t0: Double) -> Double {
        var t = t0.truncatingRemainder(dividingBy: 1); if t < 0 { t += 1 }
        return t < 1.0 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2.0 / 3 ? p + (q - p) * (2.0 / 3 - t) * 6 : p
    }
    return SIMD3(Float(f(h + 1.0 / 3)), Float(f(h)), Float(f(h - 1.0 / 3)))
}
/// 奥行きの色（ウェブ版の depthColor）：手前（d ＝ +1）は明るい紫、奥は暗い水色
func depthColor(_ d: Double, _ k: Double) -> SIMD3<Float> {
    let u = max(0, min(1, (d + 1) / 2))
    return hslF(195 + 115 * u, 0.85, 0.5) * Float(k * (0.1 + 0.9 * pow(u, 2.2)))
}

/// 線分 1 本：両はしの位置と色（GPU の並びと同じ 64 バイト）
struct Seg { var a: SIMD4<Float>; var ca: SIMD4<Float>; var b: SIMD4<Float>; var cb: SIMD4<Float> }
/// 玉 1 つ：中心・半径・色・不透明度
struct Ball { var c: SIMD4<Float>; var col: SIMD4<Float> }
struct MV { var p: SIMD4<Float>; var col: SIMD4<Float> }
/// 地図ごとの写し方：自分を真ん中に・殻の出し方・4 次元の向き
struct MapConfig { var follow: Bool; var range: Int; var xw: Double; var yw: Double; var zw: Double }
struct MapUni { var view = matrix_identity_float4x4; var proj = matrix_identity_float4x4; var res = SIMD2<Float>(1, 1); var width: Float = 1; var feather: Float = 1; var light = SIMD4<Float>(0, 0, 1, 0); var cmul: Float = 1; var amul: Float = 1; var pad0: Float = 0; var pad1: Float = 0 }
/// 名前の札：3 次元の位置・文字・色
struct MapLabel { var pos: SIMD3<Float>; var text: String; var col: SIMD3<Float>; var size: CGFloat; var bg = false; var dot = false; var dim = false }   // bg：白い丸の上の絵文字（絵のモード）、dot：極の点と名前（ウェブ版の mapDots）、dim：球の奥の側（薄く）

let mapShaderSource = #"""
#include <metal_stdlib>
using namespace metal;
struct Seg { float4 a; float4 ca; float4 b; float4 cb; };
struct Ball { float4 c; float4 col; };
struct MapUni { float4x4 view; float4x4 proj; float2 res; float width; float feather; float4 light; float cmul; float amul; float pad0; float pad1; };   // cmul：線の色の倍率（EDR）、amul：線の不透明度の倍率（にじみ）

// ---- 線：線分ごとに 6 つの頂点（板 2 枚）。両はしを画面へ写してから、画面の上で太さぶん横に広げる ----
struct LOut { float4 pos [[position]]; float4 col; float side; float halfW; };
vertex LOut lineV(uint vid [[vertex_id]], uint iid [[instance_id]], constant Seg* segs [[buffer(0)]], constant MapUni& u [[buffer(1)]]) {
    Seg s = segs[iid];
    float4 pa = u.proj * (u.view * float4(s.a.xyz, 1.0)), pb = u.proj * (u.view * float4(s.b.xyz, 1.0));
    LOut o;
    if (pa.w <= 0.001 || pb.w <= 0.001) { o.pos = float4(0.0, 0.0, -2.0, 1.0); o.col = 0.0; o.side = 0.0; o.halfW = 1.0; return o; }   // カメラの後ろは描かない
    float2 ha = u.res * 0.5;
    float2 sa = pa.xy / pa.w * ha, sb = pb.xy / pb.w * ha;
    float2 d = sb - sa; float L = length(d); d = L > 1e-4 ? d / L : float2(1.0, 0.0);
    float2 n = float2(-d.y, d.x);
    int corner = vid == 0 ? 0 : vid == 1 ? 1 : vid == 2 ? 2 : vid == 3 ? 2 : vid == 4 ? 1 : 3;
    bool atB = corner >= 2; float side = (corner == 1 || corner == 3) ? 1.0 : -1.0;
    float hw = u.width * 0.5 + u.feather;                     // ふちをやわらかくする分だけ広く
    float4 p = atB ? pb : pa;
    float2 off = (n * side * hw + d * (atB ? 1.0 : -1.0) * u.feather * 0.5) / ha;
    p.xy += off * p.w;
    o.pos = p; o.col = atB ? s.cb : s.ca; o.side = side * hw; o.halfW = u.width * 0.5;
    return o;
}
fragment float4 lineF(LOut in [[stage_in]], constant MapUni& u [[buffer(1)]]) {
    float a = clamp((in.halfW + u.feather * 0.5 - abs(in.side)) / u.feather, 0.0, 1.0);   // ふちは 1 点ぶんやわらかく
    return float4(in.col.rgb * u.cmul, in.col.a * a * u.amul);
}

// ---- 色だけの三角形（軸の矢印の円すい。ウェブ版も光を当てない色）----
struct MV { float4 p; float4 col; };
struct MOut { float4 pos [[position]]; float4 col; };
vertex MOut meshV(uint vid [[vertex_id]], constant MV* vs [[buffer(0)]], constant MapUni& u [[buffer(1)]]) {
    MOut o; o.pos = u.proj * (u.view * float4(vs[vid].p.xyz, 1.0)); o.col = vs[vid].col; return o;
}
fragment float4 meshF(MOut in [[stage_in]]) { return in.col; }

// ---- 玉：画面に向いた板に、球の陰影（ウェブ版の Phong：まわりの光 0.6・向きのある光 0.75・自分の光 0.35・つや 80）----
struct BOut { float4 pos [[position]]; float2 uv; float4 col; float3 cv; float r; };
vertex BOut ballV(uint vid [[vertex_id]], uint iid [[instance_id]], constant Ball* balls [[buffer(0)]], constant MapUni& u [[buffer(1)]]) {
    Ball b = balls[iid];
    float2 cs[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
    float2 c = cs[vid];
    float4 vc = u.view * float4(b.c.xyz, 1.0);
    float r = b.c.w;
    float4 vp = vc + float4(c * r * 1.08, 0.0, 0.0);
    BOut o; o.pos = u.proj * vp; o.uv = c * 1.08; o.col = b.col; o.cv = vc.xyz; o.r = r;
    return o;
}
struct BFrag { float4 col [[color(0)]]; float depth [[depth(any)]]; };
fragment BFrag ballF(BOut in [[stage_in]], constant MapUni& u [[buffer(1)]]) {
    float q = dot(in.uv, in.uv);
    if (q > 1.0) discard_fragment();
    float3 n = float3(in.uv, sqrt(1.0 - q));                  // 見る人の側の半球（目の空間）
    float3 L = normalize(u.light.xyz);
    float dif = max(0.0, dot(n, L));
    float3 h = normalize(L + float3(0.0, 0.0, 1.0));
    float spec = pow(max(0.0, dot(n, h)), 80.0) * 0.4;
    float3 col = in.col.rgb * (0.6 * 0.55 + 0.75 * dif * 0.55 + 0.35) + spec;
    float edge = smoothstep(1.0, 0.92, q);                     // ふちを少しやわらかく
    float4 vp = float4(in.cv + n * in.r, 1.0);
    float4 cp = u.proj * vp;
    BFrag o; o.col = float4(col, in.col.a * edge); o.depth = cp.z / cp.w;
    return o;
}
"""#

final class MapRenderer: NSObject, MTKViewDelegate {
    unowned let world: Renderer
    let slot: Int                // 0：1 枚目の地図、1：2 枚目の地図（ウェブ版の左上）、2：S² の仲間（ウェブ版の左）
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var lineAdd: MTLRenderPipelineState!, lineAlpha: MTLRenderPipelineState!, ballPipe: MTLRenderPipelineState!, ballSoft: MTLRenderPipelineState!, meshPipe: MTLRenderPipelineState!
    private var depthOn: MTLDepthStencilState!, depthRead: MTLDepthStencilState!, depthOff: MTLDepthStencilState!
    private var builtFmt: MTLPixelFormat = .invalid, builtSamples = 0

    // 回して見るカメラ（ウェブ版の OrbitControls：上は +z、視野 36°）
    var yaw = 0.0, pitch = 0.0, dist = 9.6
    var target = SIMD3<Double>(0, 0, 0)
    var onLabels: (([(CGPoint, MapLabel, Bool)]) -> Void)?
    var backingScale: CGFloat = 2
    var lastCPU = 0.0, lastGPU = 0.0            // 確かめ用：最後に画面の外へ描いた時の CPU・GPU の時間（ミリ秒）

    // 動かない線（網目・殻）は、写し方が変わった時だけ作り直す
    private var staticKey = "", staticAdd: [Seg] = [], staticBuf: MTLBuffer?, staticCount = 0
    private var s2Buf: MTLBuffer?, s2Count = 0
    /// 極の名前（ウェブ版の poleName）：アナ極・カタ極・東極・西極・北極・南極・天極・地極
    static func poleName(_ m: Marker) -> String { m.label == "N" ? "アナ極" : m.label == "S" ? "カタ極" : (m.label.split(separator: " ").first.map(String.init) ?? m.label) + "極" }
    /// 極の点の色（ウェブ版の dotCss）：アナ極は赤（いちばん内側の殻の色）、カタ極は紫、ほかは目印の色
    static func poleDotCol(_ k: Int) -> SIMD3<Float> { k == 0 ? hexRGB(0xef4444) : k == 1 ? hexRGB(0xa855f7) : FIXED[k].col }
    /// S² の仲間での 8 つの極（ウェブ版の FIXED の p2。天・地 ±z は S² に無い）
    static let s2Pole: [SIMD3<Double>?] = [[0, 0, 1], [0, 0, -1], [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], nil, nil]

    init(world: Renderer, slot: Int = 0) {
        self.world = world; self.slot = slot; device = world.device; queue = device.makeCommandQueue()!
        super.init()
        home()
    }
    /// ウェブ版の homeView(v, 9.6)：カメラを (0.55, −0.72, 0.42)·9.6 に
    func home() {
        let p = SIMD3<Double>(0.55, -0.72, 0.42) * 9.6
        dist = simd_length(p); yaw = atan2(p.y, p.x); pitch = asin(p.z / dist); target = .zero
    }

    private func build(_ fmt: MTLPixelFormat, _ samples: Int) {
        guard fmt != builtFmt || samples != builtSamples else { return }
        builtFmt = fmt; builtSamples = samples
        let lib = try! device.makeLibrary(source: mapShaderSource, options: nil)
        func pipe(_ v: String, _ f: String, additive: Bool) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: v); d.fragmentFunction = lib.makeFunction(name: f)
            d.colorAttachments[0].pixelFormat = fmt; d.depthAttachmentPixelFormat = .depth32Float; d.rasterSampleCount = samples
            let c = d.colorAttachments[0]!
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        lineAdd = pipe("lineV", "lineF", additive: true)
        lineAlpha = pipe("lineV", "lineF", additive: false)
        ballPipe = pipe("ballV", "ballF", additive: false)
        meshPipe = pipe("meshV", "meshF", additive: false)
        ballSoft = ballPipe
        func ds(_ test: Bool, _ write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = test ? .lessEqual : .always; d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthOn = ds(true, true); depthRead = ds(true, false); depthOff = ds(false, false)
    }

    // ---- 写し方 ----
    /// 4×4 の回し方（行ごと）。自分を真ん中に：体の枠（右・上・前・p）を (x, y, z, w) へ
    var config: MapConfig {
        let s = world.set
        return slot == 0 ? MapConfig(follow: s.mapFollow, range: s.mapRange, xw: s.mapXW, yw: s.mapYW, zw: s.mapZW)
                         : MapConfig(follow: s.map2Follow, range: s.map2Range, xw: s.map2XW, yw: s.map2YW, zw: s.map2ZW)
    }
    func rot4() -> [V4] {
        let c = config
        if c.follow { let F = world.cam.lookFrame(); return [F.R, F.U, F.L, world.cam.w.p] }
        var R: [V4] = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        func rot(_ i: Int, _ j: Int, _ deg: Double) {   // NDGeom.rotatePlane と同じ：行 i・j を回す（左からかける）
            guard deg != 0 else { return }
            let c = cos(deg * d2r), sn = sin(deg * d2r)
            for col in 0..<4 { let p = R[i][col], q = R[j][col]; R[i][col] = c * p - sn * q; R[j][col] = sn * p + c * q }
        }
        rot(0, 3, c.xw); rot(1, 3, c.yw); rot(2, 3, c.zw)
        return R
    }
    /// 軸 x・y・z・w が地図の 3 次元に写る長さの割合（ウェブ版の右上の「x 68%　y 91% …」）。
    ///   自分中心では、軸 e_i の長さ ＝ √(1 − p_i²)：今いる所の向きの軸ほど奥行き（自分の方）を向いて短くなる
    func axisLengths() -> [Double] {
        let R = rot4()
        return (0..<4).map { i -> Double in let v = SIMD3<Double>(R[0][i], R[1][i], R[2][i]); return simd_length(v) }
    }
    /// 4 次元の点 → 地図の 3 次元の点と、奥行き w'（−1 奥 〜 +1 手前）。写せない所（k が大きすぎる）は nil
    @inline(__always) func map(_ p: V4, _ R: [V4]) -> (SIMD3<Float>, Double)? {
        let q = V4(dot4(R[0], p), dot4(R[1], p), dot4(R[2], p), dot4(R[3], p))
        let D = world.set.mapD, k = D / (D - q.w)
        guard k > 0 && k < 14 else { return nil }
        return (SIMD3<Float>(Float(q.x * k * RS), Float(q.y * k * RS), Float(q.z * k * RS)), q.w)
    }
    func kOf(_ p: V4, _ R: [V4]) -> Double { let D = world.set.mapD; return D / (D - dot4(R[3], p)) }

    // ---- 網目：赤道の球面 S²（w = 0）の緯線 5 本（36 区切り）・経線 12 本（半円 18 区切り）（ウェブ版の eqPairs）----
    static let eqPairs: [(SIMD3<Double>, SIMD3<Double>)] = {
        var out: [(SIMD3<Double>, SIMD3<Double>)] = []
        let nlat = 5, nlon = 12, seg = 36, TAU = 2 * Double.pi
        for i in 1...nlat {
            let th = Double.pi * Double(i) / Double(nlat + 1), z = cos(th), rr = sin(th)
            for s in 0..<seg { let a = TAU * Double(s) / Double(seg), b = TAU * Double(s + 1) / Double(seg); out.append(([rr * cos(a), rr * sin(a), z], [rr * cos(b), rr * sin(b), z])) }
        }
        for j in 0..<nlon {
            let a = TAU * Double(j) / Double(nlon)
            for s in 0..<(seg / 2) {
                let t1 = Double.pi * Double(s) / Double(seg / 2), t2 = Double.pi * Double(s + 1) / Double(seg / 2)
                out.append(([sin(t1) * cos(a), sin(t1) * sin(a), cos(t1)], [sin(t2) * cos(a), sin(t2) * sin(a), cos(t2)]))
            }
        }
        return out
    }()

    /// 4 次元の線分の組を写して、線分にする（写せない・長すぎる（3 より）線は飛ばす）
    private func addPairs(_ out: inout [Seg], _ pairs: [(V4, V4)], _ R: [V4], maxLen: Float = 3, color: (Double, Int, Int) -> SIMD3<Float>) {
        out.reserveCapacity(out.count + pairs.count)
        for (i, (A, B)) in pairs.enumerated() {
            guard let (a, da) = map(A, R), let (b, db) = map(B, R), simd_length(a - b) <= maxLen else { continue }
            let ca = color(da, i, 0), cb = color(db, i, 1)
            out.append(Seg(a: SIMD4(a, 0), ca: SIMD4(ca, 1), b: SIMD4(b, 0), cb: SIMD4(cb, 1)))
        }
    }
    /// 経線・赤道の輪（ウェブ版の circ：大円 6 本 × 96 区切り）
    static let circPairs: [(V4, V4, SIMD3<Float>)] = {
        var out: [(V4, V4, SIMD3<Float>)] = []; let CN = 96, TAU = 2 * Double.pi
        for (i, j, col) in [(0, 3, AXIS_RGB[0]), (1, 3, AXIS_RGB[1]), (2, 3, AXIS_RGB[2]), (0, 1, hexRGB(0xd8dcf0)), (1, 2, hexRGB(0xd8dcf0)), (2, 0, hexRGB(0xd8dcf0))] {
            for s in 0..<CN {
                let a = TAU * Double(s) / Double(CN), b = TAU * Double(s + 1) / Double(CN)
                var A = V4(0, 0, 0, 0), B = V4(0, 0, 0, 0); A[i] = cos(a); A[j] = sin(a); B[i] = cos(b); B[j] = sin(b)
                out.append((A, B, col))
            }
        }
        return out
    }()
    /// 120 胞体の辺を 3 つに分けた線分（ウェブ版の roomPairs）
    static let roomPairs: [(V4, V4)] = {
        func slerp(_ A: V4, _ B: V4, _ t: Double) -> V4 { nrm(A * (1 - t) + B * t) }
        return Cell120.shared.edges.flatMap { (A, B) in (0..<3).map { (slerp(A, B, Double($0) / 3), slerp(A, B, Double($0 + 1) / 3)) } }
    }()
    /// 球の網目を w ＝ wc・半径 sn の殻へ
    static func shellPairs(_ wc: Double, _ sn: Double) -> [(V4, V4)] {
        eqPairs.map { (A, B) in (V4(A.x * sn, A.y * sn, A.z * sn, wc), V4(B.x * sn, B.y * sn, B.z * sn, wc)) }
    }

    /// 景色で、もやの向こうに消えるまでの角度（光が e^−3 ≈ 5% になる所）。宇宙の大きさ R 倍でもやも R 倍なので、角度では 1/R に
    static func visAngle(_ s: Settings) -> Double {
        let f = s.fog * (s.grand ? 1.6 : 1) * s.uniR
        return f > 1e-6 ? 3 / f : 10
    }
    /// 照らす範囲が小さい時は、殻の線分（1 本 10° ほど）を範囲の 1/4 の長さに分ける（範囲の中の線が消えないように）
    static func fine(_ ps: [(V4, V4, SIMD3<Float>, Double, Int)], _ rng: Double) -> [(V4, V4, SIMD3<Float>, Double, Int)] {
        guard rng < 0.7 else { return ps }
        var out: [(V4, V4, SIMD3<Float>, Double, Int)] = []
        for P in ps {
            let ang = acos(max(-1, min(1, dot4(P.0, P.1)))), k = max(1, min(96, Int(ceil(ang / (rng / 4)))))
            if k == 1 || ang < 1e-9 { out.append(P); continue }
            let sa = sin(ang)
            func at(_ t: Double) -> V4 { (P.0 * sin((1 - t) * ang) + P.1 * sin(t * ang)) / sa }
            var a = P.0
            for j in 1...k { let b = at(Double(j) / Double(k)); out.append((a, b, P.2, P.3, P.4)); a = b }
        }
        return out
    }
    /// 足し合わせの線で暗い色（紫など）が沈まないよう、いちばん強い成分を 1 にそろえてから明るさ k をかける（ウェブ版の vivid）
    static func vivid(_ c: SIMD3<Float>, _ k: Double) -> SIMD3<Float> {
        let m = max(c.x, c.y, c.z, 1e-3), q = Float(min(1, k)); return (c / m * 0.92 + SIMD3(repeating: 0.08)) * q
    }
    /// 点 q が中の景色の画面に写る向きにあるか（ウェブ版の inView、ふつうのレンズ）
    func inView(_ q: V4, _ F: Look) -> Bool {
        let p = world.cam.w.p, t = q - p * dot4(q, p), r = dot4(t, F.R), u = dot4(t, F.U), f = dot4(t, F.L)
        let asp = Double(world.drawSize.width / max(1, world.drawSize.height)), tf = tan(min(150, world.set.fov) * Double.pi / 360)
        return f > 1e-6 && abs(r / f) <= tf * asp && abs(u / f) <= tf
    }
    /// 球層の殻の組（ウェブ版の shFams）：レインボーは w だけ、軸の色は選んだ軸（x・y・z・w の順）
    var shellFams: [Int] {
        let s = world.set
        guard s.shAxis else { return [3] }
        let f = [(0, s.shAxX), (1, s.shAxY), (2, s.shAxZ), (3, s.shAxW)].filter { $0.1 }.map { $0.0 }
        return f.isEmpty ? [3] : f
    }
    /// 軸色の殻の色（ウェブ版の axisShellRGB）：＋の極のそばは明るく、−の極のそばは少し暗く、赤道へ行くほど落ち着いた色
    static func axisShellRGB(_ ax: Int, _ i: Int, _ n: Int) -> SIMD3<Float> {
        let ac = AXIS_RGB[ax], j = i < n ? i : 2 * n - 2 - i, t = Float(j) / Float(max(1, n - 1))
        func mx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ k: Float) -> SIMD3<Float> { a + (b - a) * k }
        return i < n ? mx(mx(ac, [1, 1, 1], 0.35), ac, t) : mx(ac * 0.62, ac * 0.9, t)
    }
    /// アナ極・カタ極の殻の点を、軸 ax の極を囲む殻へ（成分を入れかえる。ウェブ版の axSwap）
    static func axSwap(_ p: V4, _ ax: Int) -> V4 { guard ax != 3 else { return p }; var q = p; q[ax] = p[3]; q[3] = p[ax]; return q }
    /// 球層の殻の線分（4 次元）と色・θ・どの軸の殻か（ウェブ版の shellSet）
    private var shellCache: (String, [(V4, V4, SIMD3<Float>, Double, Int)]) = ("", [])
    /// 宇宙の大きさの段（×1・×10・×100・×1000 → 0〜3）。地図を拡大したりゆがめたりせず、段ごとに殻を間引いて線を細くし、景色の広さとつながって見えるように
    static func uniLevel(_ s: Settings) -> Int { min(3, max(0, Int(floor(s.uniL + 1e-6)))) }
    static let levelStride = [1, 2, 3, 5], levelWidth: [Float] = [1, 0.75, 0.55, 0.42], levelBright = [1.0, 0.9, 0.8, 0.72]
    func shellSet(_ n: Int) -> [(V4, V4, SIMD3<Float>, Double, Int)] {
        let lv = MapRenderer.uniLevel(world.set), kst = MapRenderer.levelStride[lv]
        let fams = shellFams, axis = world.set.shAxis, key = "\(n)|\(world.shellMinTheta)|\(axis)|\(fams)|\(kst)"
        if shellCache.0 == key { return shellCache.1 }
        let m0 = world.shellMinTheta
        var out: [(V4, V4, SIMD3<Float>, Double, Int)] = []
        for ax in fams {
            for i in 0..<(2 * n - 1) {
                let j = i < n ? i : 2 * n - 2 - i, t = Double(j) / Double(max(1, n - 1))
                if (n - 1 - j) % kst != 0 { continue }                    // 宇宙が大きい段では殻を間引く（赤道の殻はいつも残す）
                let th = m0 + t * (Double.pi / 2 - m0), wc = (i < n ? 1 : -1) * cos(th)
                let col = axis ? MapRenderer.axisShellRGB(ax, i, n) : hslF((i < n ? t * 0.5 : 0.8 - t * 0.3) * 360, 0.95, 0.52)
                for (A, B) in MapRenderer.shellPairs(wc, sin(th)) { out.append((MapRenderer.axSwap(A, ax), MapRenderer.axSwap(B, ax), col, i < n ? th : Double.pi - th, ax)) }
            }
        }
        shellCache = (key, out); return out
    }
    /// 軸色で殻の組が多い時は、足し合わせで白くならないよう 1 本ずつ暗く（ウェブ版の fk）
    var shellFk: Double { world.set.shAxis ? 0.75 / Double(shellFams.count) : 1 }
    /// 加え合わせで描く線：球層の殻・赤道の網目・軽い線。全体の時は写し方が変わった時だけ作り直す
    private func staticLines(_ R: [V4]) -> [Seg] {
        let s = world.set, c = config
        let n = max(2, min(21, s.shellN))
        var out: [Seg] = []
        if s.shell && c.range != 0 {                              // 今いる所・写る所：歩くたびに作り直す
            let W = world.cam.w.p, shells = shellSet(n), sfk = shellFk.squareRoot()
            if c.range == 1 {
                // 自分がいる層は殻の軸ごと（その軸の成分の角度）
                //   照らす範囲は、景色でもやの向こうに消えるまでの距離（宇宙が大きいほど角度では小さい。サーチライトのように）
                let m0 = world.shellMinTheta, gap = (Double.pi / 2 - m0) / Double(max(1, n - 1)) * Double(MapRenderer.levelStride[MapRenderer.uniLevel(s)]), Rf = min(0.9, MapRenderer.visAngle(s)), cR = cos(Rf)
                let thAx = (0..<4).map { acos(max(-1, min(1, W[$0]))) }, cW = cos(min(Double.pi, Rf + 0.2))
                let cand = shells.filter { abs($0.3 - thAx[$0.4]) < 2.2 * gap && (dot4($0.0, W) > cW || dot4($0.1, W) > cW) }
                let sub = MapRenderer.fine(cand, Rf).filter { dot4($0.0, W) > cR || dot4($0.1, W) > cR }
                addPairs(&out, sub.map { ($0.0, $0.1) }, R) { d, i, e in
                    let P = sub[i], lay = max(0, 1 - abs(P.3 - thAx[P.4]) / (2.2 * gap)), q = e == 0 ? P.0 : P.1
                    let dg = acos(max(-1, min(1, dot4(q, W)))), near = 1 - min(1, max(0, (dg - 0.6 * Rf) / (0.4 * Rf)))
                    return MapRenderer.vivid(P.2, (0.35 + 0.65 * lay * lay) * near * (0.75 + 0.25 * (d + 1) / 2) * 1.3 * sfk)
                }
            } else {
                let F = world.cam.viewFrame(), Rl = min(s.shellRange, s.maxD, Double.pi, MapRenderer.visAngle(s)), cl = cos(Rl), cW = cos(min(Double.pi, Rl + 0.2))
                func vis(_ q: V4) -> Bool { inView(q, F) && dot4(q, W) >= cl }
                let cand = shells.filter { dot4($0.0, W) > cW || dot4($0.1, W) > cW }
                let lit = MapRenderer.fine(cand, Rl).filter { vis($0.0) || vis($0.1) }
                addPairs(&out, lit.map { ($0.0, $0.1) }, R) { d, i, e in
                    let q = e == 0 ? lit[i].0 : lit[i].1, dg = acos(max(-1, min(1, dot4(q, W))))
                    let k = vis(q) ? (1 - min(1, max(0, (dg - 0.6 * Rl) / (0.4 * Rl)))) * (0.75 + 0.25 * (d + 1) / 2) * 1.3 : 0
                    return MapRenderer.vivid(lit[i].2, k * sfk)
                }
            }
            staticKey = ""
            return out
        }
        let key = R.map { "\($0)" }.joined() + "|\(s.mapD)|\(s.shell)|\(n)|\(s.eq)|\(s.lite)|\(s.mk)|\(s.circ)|\(s.room)|\(s.shAxis)|\(shellFams)|\(MapRenderer.uniLevel(s))"
        if key == staticKey { return staticAdd }
        staticKey = key
        let only = s.shell                                       // 球層の時は、地図は球殻だけ（ウェブ版の shOnly）
        if s.shell {
            let sh = shellSet(n), fk = shellFk * MapRenderer.levelBright[MapRenderer.uniLevel(s)]
            addPairs(&out, sh.map { ($0.0, $0.1) }, R) { d, i, _ in sh[i].2 * Float(fk * (0.35 + 0.65 * pow((d + 1) / 2, 1.2))) }
        }
        if s.eq && !only { addPairs(&out, MapRenderer.shellPairs(0, 1), R) { d, _, _ in depthColor(d, 0.8) } }
        if s.lite && !only {
            for k in [1, 2, 4, 5] { let th = Double(k) * Double.pi / 6; addPairs(&out, MapRenderer.shellPairs(cos(th), sin(th)), R) { d, _, _ in depthColor(d, 0.45) } }
        }
        if s.circ && !only {                                    // 経線（x・y・z と w の大円、軸の色）と赤道の輪（白っぽい）
            let C = MapRenderer.circPairs
            addPairs(&out, C.map { ($0.0, $0.1) }, R) { d, i, _ in C[i].2 * Float(0.25 + 0.75 * pow((d + 1) / 2, 1.5)) }
        }
        if s.room && !only {                                    // 120 胞体の部屋の辺（1 本を 3 つに分けて大円に沿わせる）
            addPairs(&out, MapRenderer.roomPairs, R, maxLen: 2.5) { d, _, _ in depthColor(d, 0.32) }
        }
        staticAdd = out
        return out
    }

    // ---- カメラ ----
    func viewMatrix() -> simd_float4x4 {
        let eye = target + SIMD3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch)) * dist
        let f = simd_normalize(target - eye), up = SIMD3<Double>(0, 0, 1)
        var r = simd_cross(f, up); if simd_length(r) < 1e-6 { r = [1, 0, 0] }; r = simd_normalize(r)
        let u = simd_cross(r, f)
        let m = simd_double4x4(rows: [SIMD4(r, -simd_dot(r, eye)), SIMD4(u, -simd_dot(u, eye)), SIMD4(-f, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        return f4(m)
    }
    func projMatrix(_ w: Double, _ h: Double) -> simd_float4x4 {
        let asp = w / max(1, h)
        let fovY = asp >= 1 ? 36 * d2r : 2 * atan(tan(18 * d2r) / asp)
        let n = 0.02, f = 400.0, ys = 1 / tan(fovY / 2), xs = ys / asp
        return f4(simd_double4x4(rows: [[xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, f / (n - f), f * n / (n - f)], [0, 0, -1, 0]]))
    }

    // ---- MTKViewDelegate ----
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        let placed = encode(cb, rpd, view.colorPixelFormat, view.sampleCount, Double(view.drawableSize.width), Double(view.drawableSize.height))
        cb.present(drawable); cb.commit()
        onLabels?(placed)
    }
    /// 画面の外に描く（確かめ用）。戻り値は RGBA 8 ビットと、名前の札の位置
    func renderOffscreen(width: Int, height: Int) -> ([UInt8], [(CGPoint, MapLabel, Bool)]) {
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        cd.usage = [.renderTarget]; cd.storageMode = .shared
        let col = device.makeTexture(descriptor: cd)!
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dd.usage = [.renderTarget]; dd.storageMode = .private
        let dep = device.makeTexture(descriptor: dd)!
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = col; rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0x03 / 255.0, green: 0x07 / 255.0, blue: 0x12 / 255.0, alpha: 1)
        rpd.depthAttachment.texture = dep; rpd.depthAttachment.loadAction = .clear; rpd.depthAttachment.clearDepth = 1; rpd.depthAttachment.storeAction = .dontCare
        let cb = queue.makeCommandBuffer()!
        let t0 = CACurrentMediaTime()
        let placed = encode(cb, rpd, .bgra8Unorm, 1, Double(width), Double(height))
        lastCPU = (CACurrentMediaTime() - t0) * 1000
        cb.commit(); cb.waitUntilCompleted()
        lastGPU = (cb.gpuEndTime - cb.gpuStartTime) * 1000
        var px = [UInt8](repeating: 0, count: width * height * 4)
        col.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        for i in stride(from: 0, to: px.count, by: 4) { px.swapAt(i, i + 2) }   // BGRA → RGBA
        return (px, placed)
    }
    func encode(_ cb: MTLCommandBuffer, _ rpd: MTLRenderPassDescriptor, _ fmt: MTLPixelFormat, _ samples: Int, _ W: Double, _ H: Double) -> [(CGPoint, MapLabel, Bool)] {
        build(fmt, samples)
        var u = MapUni(); u.view = viewMatrix(); u.proj = projMatrix(W, H); u.res = SIMD2(Float(W), Float(H)); u.feather = Float(backingScale)
        // 光の向き（ウェブ版の (3, −4, 6)）を目の空間へ
        let lw = simd_normalize(SIMD3<Float>(3, -4, 6)), lv = u.view * SIMD4(lw, 0); u.light = SIMD4(simd_normalize(SIMD3(lv.x, lv.y, lv.z)), 0)
        let R = rot4()
        let px = Float(backingScale)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return [] }
        /// GPU に置いたままの線を描く（動かない線は作り直した時だけ送る）
        func linesBuf(_ buf: MTLBuffer, _ count: Int, _ width: Float, additive: Bool, depth: MTLDepthStencilState, cmul: Float, amul: Float) {
            guard count > 0 else { return }
            u.width = width * px; u.cmul = cmul; u.amul = amul
            enc.setRenderPipelineState(additive ? lineAdd : lineAlpha); enc.setDepthStencilState(depth)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1); enc.setFragmentBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            u.cmul = 1; u.amul = 1
        }
        func lines(_ segs: [Seg], _ width: Float, additive: Bool, depth: MTLDepthStencilState) {
            guard !segs.isEmpty else { return }
            u.width = width * px
            enc.setRenderPipelineState(additive ? lineAdd : lineAlpha); enc.setDepthStencilState(depth)
            segs.withUnsafeBytes { b in
                if b.count <= 4096 { enc.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { enc.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            enc.setVertexBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1); enc.setFragmentBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: segs.count)
        }
        func balls(_ bs: [Ball], depth: MTLDepthStencilState) {
            guard !bs.isEmpty else { return }
            enc.setRenderPipelineState(ballPipe); enc.setDepthStencilState(depth)
            bs.withUnsafeBytes { b in
                if b.count <= 4096 { enc.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { enc.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            enc.setVertexBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1); enc.setFragmentBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: bs.count)
        }

        let s = world.set, j = world.journey, cam = world.cam
        var labels: [MapLabel] = []
        /// 円すい（ウェブ版の ConeGeometry と同じ：真ん中 c、先は向き t へ高さの半分、底は半分うしろ）。横は色そのまま、底は少し暗く
        func cone(_ c: SIMD3<Float>, _ t: SIMD3<Float>, _ r: Float, _ h: Float, _ col: SIMD4<Float>, _ N: Int = 16) -> [MV] {
            var e1 = simd_cross(t, SIMD3<Float>(0, 0, 1)); if simd_length(e1) < 1e-3 { e1 = simd_cross(t, SIMD3<Float>(1, 0, 0)) }; e1 = simd_normalize(e1)
            let e2 = simd_cross(t, e1), tip = c + t * (h / 2), base = c - t * (h / 2), dark = col * SIMD4(0.6, 0.6, 0.6, 1)
            var tri: [MV] = []
            for k in 0..<N {
                let a0 = Float(k) / Float(N) * 2 * .pi, a1 = Float(k + 1) / Float(N) * 2 * .pi
                let p0 = base + (e1 * cos(a0) + e2 * sin(a0)) * r, p1 = base + (e1 * cos(a1) + e2 * sin(a1)) * r
                tri += [MV(p: SIMD4(tip, 1), col: col), MV(p: SIMD4(p0, 1), col: col), MV(p: SIMD4(p1, 1), col: col),
                        MV(p: SIMD4(base, 1), col: dark), MV(p: SIMD4(p1, 1), col: dark), MV(p: SIMD4(p0, 1), col: dark)]
            }
            return tri
        }
        func mesh(_ tri: [MV]) {
            guard !tri.isEmpty else { return }
            enc.setRenderPipelineState(meshPipe); enc.setDepthStencilState(depthOn)
            tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { enc.setVertexBuffer(buf, offset: 0, index: 0) } }
            enc.setVertexBytes(&u, length: MemoryLayout<MapUni>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        }
        /// 軸の矢印（ウェブ版の makeAxes）：原点から線、先に円すい（半径 0.055・高さ 0.18）、名前は先の少し外（0.22）
        func axes(_ dirs: [SIMD3<Float>]) {
            var ax: [Seg] = [], tri: [MV] = []
            for (i, d) in dirs.enumerated() {
                let len = simd_length(d), col = SIMD4(AXIS_RGB[i], 1)
                ax.append(Seg(a: SIMD4(0, 0, 0, 0), ca: col, b: SIMD4(d, 0), cb: col))
                guard len > 0.08 else { continue }
                let t = d / len
                tri += cone(d, t, 0.055, 0.18, col)
                if len > 0.15 { labels.append(MapLabel(pos: d + t * 0.22, text: ["x", "y", "z", "w"][i], col: AXIS_RGB[i], size: 14)) }
            }
            lines(ax, 2.2, additive: false, depth: depthRead)
            mesh(tri)
        }
        /// S² の仲間（ウェブ版の左の窓・buildA）：同じ操作を、ふつうの球面 S² の上でした場合
        func s2Content() {
            let picMode = s.mk == 1, none = s.mk == 3, R2 = Float(RS)
            balls([Ball(c: SIMD4(0, 0, 0, R2 * 0.995), col: SIMD4(hexRGB(0x1e3a8a), 0.18))], depth: depthOff)   // うっすら青い球
            var bs: [Ball] = []
            func ball(_ p: SIMD3<Double>, _ r: Double, _ col: SIMD3<Float>, pic: String?) {
                let a = SIMD3<Float>(p) * R2
                if picMode, let pic { labels.append(MapLabel(pos: a, text: pic, col: [1, 1, 1], size: 18, bg: true)); return }
                bs.append(Ball(c: SIMD4(a, Float(r)), col: SIMD4(col, 1)))
            }
            if s.poles {   // 見せ方が「なし」でも、極の点と名前は出す（ウェブ版と同じ）
                for (k, m) in FIXED.enumerated() {
                    guard let p2 = MapRenderer.s2Pole[k] else { continue }   // ±z（天・地）は S² には無い
                    // ウェブ版と同じ：玉ではなく、画面の上の平らな点と名前（絵のモードでは絵）
                    if picMode { ball(p2, m.r * 1.1, m.col, pic: PIC.poles[k]) }
                    else { labels.append(MapLabel(pos: SIMD3<Float>(p2) * R2, text: MapRenderer.poleName(m), col: world.poleCol(k), size: 10, dot: true)) }
                }
            }
            if s.foot { for p in j.foot2 { ball(p, 0.035, [0.8, 0.85, 1], pic: PIC.foot) } }
            if s.marksOn && !none {
                for (i, p) in j.marks2.enumerated() {
                    ball(p, 0.08, Journey.markColor(i), pic: PIC.mark(i))
                    if !picMode { labels.append(MapLabel(pos: SIMD3<Float>(p) * R2 * 1.1, text: "\(i + 1)", col: [1, 1, 1], size: 11)) }
                }
            }
            ball(j.w2.p, 0.09, [1, 1, 1], pic: PIC.selfPic)
            balls(bs, depth: depthOn)
            // 緯線・経線（動かないので 1 回だけ作って使い回す）
            if s2Buf == nil {
                var g: [Seg] = []; let nlat = 5, nlon = 12, seg = 48, TAU = Float.pi * 2, c = SIMD4<Float>(0.25, 0.3, 0.5, 1), ce = SIMD4<Float>(0.6, 0.65, 0.9, 1)
                func P(_ v: SIMD3<Float>) -> SIMD4<Float> { SIMD4(v * R2, 0) }
                for i in 1...nlat { let th = Float.pi * Float(i) / Float(nlat + 1), z = cos(th), rr = sin(th)
                    for k in 0..<seg { let a = TAU * Float(k) / Float(seg), b = TAU * Float(k + 1) / Float(seg); g.append(Seg(a: P([rr * cos(a), rr * sin(a), z]), ca: c, b: P([rr * cos(b), rr * sin(b), z]), cb: c)) } }
                for jj in 0..<nlon { let a = TAU * Float(jj) / Float(nlon)
                    for k in 0..<(seg / 2) { let t1 = Float.pi * Float(k) / Float(seg / 2), t2 = Float.pi * Float(k + 1) / Float(seg / 2)
                        g.append(Seg(a: P([sin(t1) * cos(a), sin(t1) * sin(a), cos(t1)]), ca: c, b: P([sin(t2) * cos(a), sin(t2) * sin(a), cos(t2)]), cb: c)) } }
                for k in 0..<seg { let a = TAU * Float(k) / Float(seg), b = TAU * Float(k + 1) / Float(seg); g.append(Seg(a: P([cos(a), sin(a), 0]), ca: ce, b: P([cos(b), sin(b), 0]), cb: ce)) }   // 赤道
                s2Count = g.count; s2Buf = g.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            }
            if let buf = s2Buf { linesBuf(buf, s2Count, 1.0, additive: true, depth: depthRead, cmul: Float(world.edrBoost), amul: 1) }
            // 歩いた跡（虹色、古いほど暗く）
            if s.mapTrail && j.trail2.count > 1 {
                var tr: [Seg] = []; let N = Double(j.trail2.count)
                for i in 1..<j.trail2.count {
                    let f = Float(0.3 + 0.7 * Double(i) / N), c = SIMD4(hslF(200 + 160 * Double(i) / N, 0.9, 0.6) * f, 1)
                    tr.append(Seg(a: SIMD4(SIMD3<Float>(j.trail2[i - 1]) * R2, 0), ca: c, b: SIMD4(SIMD3<Float>(j.trail2[i]) * R2, 0), cb: c))
                }
                lines(tr, 2.4, additive: true, depth: depthRead)
            }
            // 進む向き（黄色の円すい。ウェブ版と同じ：半径 0.06・高さ 0.3、真ん中は玉から 0.25）
            let L2 = j.w2.f * cos(cam.az * d2r) + j.w2.r * sin(cam.az * d2r), P0 = SIMD3<Float>(j.w2.p) * R2, dv = simd_normalize(SIMD3<Float>(L2))
            mesh(cone(P0 + dv * 0.25, dv, 0.06, 0.3, SIMD4(hexRGB(0xfde047), 1)))
            if s.mapAxes { axes([[Float(AXL), 0, 0], [0, Float(AXL), 0], [0, 0, Float(AXL)]]) }
        }
        if slot == 2 { s2Content() } else {
        // 1. 玉（奥行きを書く）：8 つの極・足あと・置いた目印・自分
        var bs: [Ball] = []
        let picMode = s.mk == 1, none = s.mk == 3
        let mk = max(0.3, pow(s.uniR, -0.35))                    // 宇宙が大きい時、地図の玉は見えなくならないよう 1/R ではなく R^−0.35 で小さく（下限 0.3。ウェブ版の mapK）
        func ball(_ p: V4, _ r: Double, _ col: SIMD3<Float>, cap: Double = 2.5, pic: String? = nil) -> SIMD3<Float>? {
            guard let (a, _) = map(p, R) else { return nil }
            let k = min(cap, kOf(p, R))
            if picMode, let pic { labels.append(MapLabel(pos: a, text: pic, col: [1, 1, 1], size: CGFloat(18 * k), bg: true)); return a }   // 絵のモード：玉の代わりに絵文字（遠近で大きさも）
            bs.append(Ball(c: SIMD4(a, Float(r * k * mk)), col: SIMD4(col, 1))); return a
        }
        if s.poles {   // 見せ方が「なし」でも、極の点と名前は出す（ウェブ版と同じ）
            for (j, m) in FIXED.enumerated() {
                if s.hidePair && m.pole && (0..<4).contains(where: { m.c[$0] < -0.5 }) { continue }
                // ウェブ版と同じ：玉ではなく、画面の上の平らな点と名前（遠近で大きさが変わったりゆがんだりしない）。絵のモードでは絵
                if picMode { _ = ball(m.c, m.r, m.col, pic: PIC.poles[j]) }
                else if let (a, _) = map(m.c, R) { labels.append(MapLabel(pos: a, text: MapRenderer.poleName(m), col: world.poleCol(j), size: 10, dot: true)) }
            }
        }
        if s.foot { for p in j.foot { _ = ball(p, 0.04, [0.8, 0.85, 1], pic: PIC.foot) } }
        if s.marksOn && !none {
            for (i, p) in j.marks.enumerated() {
                if let a = ball(p, 0.085, Journey.markColor(i), pic: PIC.mark(i)), !picMode { labels.append(MapLabel(pos: a + SIMD3(0, 0, 0.18), text: "\(i + 1)", col: [1, 1, 1], size: 11)) }
            }
        }
        let meA = ball(cam.w.p, 0.1, [1, 1, 1], cap: 1.4, pic: PIC.selfPic)
        balls(bs, depth: depthOn)

        // 2. 動かない線（加え合わせ）：球層の殻・赤道の網目・軽い線
        // 光る線：先に太く薄いにじみ、その上に芯（EDR の画面では芯を明るく）
        let before = staticKey
        let st = staticLines(R)
        if staticBuf == nil || staticKey.isEmpty || staticKey != before || staticCount != st.count {   // 作り直した時だけ GPU へ送る
            staticCount = st.count
            staticBuf = st.isEmpty ? nil : st.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        if let buf = staticBuf {
            // EDR で光らせるのは、照らす所だけの時（サーチライト）。全体の時はウェブ版と同じ明るさ（ギラギラしないように）
            let boost = config.range != 0 ? Float(world.edrBoost) : 1
            let mood: Float = s.space && !s.shAxis ? 0.6 : 1                  // 宇宙の時は、レインボーの殻を少し暗く（雰囲気。軸色はそのまま）
            linesBuf(buf, staticCount, MapRenderer.levelWidth[MapRenderer.uniLevel(s)], additive: true, depth: depthRead, cmul: boost * mood, amul: 1)   // 宇宙が大きい段ほど細い線
        }

        // 3. 軌跡（虹色、古いほど暗く）・進む向き・見ている向き・軸
        var tr: [Seg] = []
        if s.mapTrail && j.trail.count > 1 {
            let N = Double(j.trail.count)
            var prev = map(j.trail[0], R)
            for i in 1..<j.trail.count {
                let cur = map(j.trail[i], R)
                if let (a, _) = prev, let (b, _) = cur, simd_length(a - b) <= 1.5 {
                    let f = Float(0.45 + 0.55 * Double(i) / N)
                    let c = hslF(200 + 160 * Double(i) / N, 0.95, 0.62) * f
                    tr.append(Seg(a: SIMD4(a, 0), ca: SIMD4(c, 1), b: SIMD4(b, 0), cb: SIMD4(c, 1)))
                }
                prev = cur
            }
        }
        lines(tr, 3.4, additive: false, depth: depthRead)
        if let a = meA {
            // 自分の玉から出る円すい（ウェブ版と同じ大きさ・位置。遠近で大きくなるのは 1.4 倍まで）
            let k = Float(min(1.4, kOf(cam.w.p, R)))
            func arrow(_ dir: V4, _ r: Float, _ h: Float, _ off: Float, _ col: SIMD3<Float>) {
                let q = nrm(cam.w.p * cos(0.12) + dir * sin(0.12))
                guard let (b, _) = map(q, R) else { return }
                let t = b - a; guard simd_length(t) > 1e-6 else { return }
                let tn = simd_normalize(t)
                mesh(cone(a + tn * off, tn, r * k, h * k, SIMD4(col, 1)))
            }
            // 進む向き（黄）：歩いている間は実際に歩いている向き、止まっている時は進む向き
            let dv = world.lastDir.flatMap { CACurrentMediaTime() - world.lastDirT < 0.4 ? $0 : nil } ?? cam.lookFrame().L
            arrow(dv, 0.06, 0.3, 0.28, hexRGB(0xfde047))
            if abs(cam.hy) > 0.5 || abs(cam.hp) > 0.5 { arrow(cam.viewFrame().L, 0.04, 0.26, 0.26, hexRGB(0x7dd3fc)) }   // 見ている向き（水色、細め）
        }
        if s.mapAxes { axes((0..<4).map { i in SIMD3<Float>(Float(R[0][i]), Float(R[1][i]), Float(R[2][i])) * Float(AXL) }) }   // 軸 e_i を回した向き（遠近はかけない）
        // 4. 模型の球（半径 RS）を、うっすら青く（ウェブ版の不透明度 0.05）
        balls([Ball(c: SIMD4(0, 0, 0, Float(RS)), col: SIMD4(hexRGB(0x1e3a8a), 0.05))], depth: depthOff)
        }
        enc.endEncoding()

        // 名前の札を画面の位置へ（手前を向いていない所は隠す）
        let vp = u.proj * u.view, zc = (u.view * SIMD4<Float>(0, 0, 0, 1)).z   // 球の真ん中の奥行き
        let placed: [(CGPoint, MapLabel, Bool)] = labels.map { l0 in
            var l = l0
            if l.dot { l.dim = (u.view * SIMD4(l.pos, 1)).z < zc }       // 球の奥の側の極は薄く（ウェブ版と同じ）
            let c = vp * SIMD4(l.pos, 1)
            guard c.w > 0.01 else { return (.zero, l, false) }
            let x = (c.x / c.w * 0.5 + 0.5) * Float(W) / Float(backingScale), y = (1 - (c.y / c.w * 0.5 + 0.5)) * Float(H) / Float(backingScale)
            return (CGPoint(x: CGFloat(x), y: CGFloat(y)), l, true)
        }
        return placed
    }
}
