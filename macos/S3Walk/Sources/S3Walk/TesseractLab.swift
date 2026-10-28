// 次元おりがみ（光で描く試作）：立方体 ↔ 超立方体を、画素ごとに光を飛ばして描く（ポリゴンを使わない）。質感は次元おりがみ（nd-solid・visual-fx）と同じ考え方。
//   見せ方「全体」：左は立方体（6 つの面）、右は超立方体（8 つの胞 × 6 つの面を 4D の遠近で 3D へ写したもの）を、透明なプラケースのような板で。
//     板：うすい色（胞の色）＋フレネル（斜めほど濃く・縁が光る）＋スタジオの映り込み（上が明るい空と、白い照明の板 3 枚＝角ばった窓の反射）。
//     照り返しが明るい所は不透明に（本物のガラスのキラッ）。キラキラ：細かい粒が照明の向きにきらめく。辺は光沢のある管、頂点は玉（遠いほど細く）。
//   見せ方「断面」：左は立方体を水平な平面 z′＝s で切った多角形（2 次元の生き物の見え方）、右は超立方体を 3D 空間 w′＝s で切った立体（私たちの見え方）。
//     断面の面は、8 つの胞（±x・±y・±z・±w）のどれの切り口かで色分け。
//   回転の対応（アナロジー）：左の X-Z ↔ 右の X-W、左の Y-Z ↔ 右の Y-W（どちらも「切る向き」へ倒す回転）、X-Y は両方。Z-W は右だけ（左には無い）。
//   面は奥から手前へ順に重ねる（光の道の上で当たった順に並べる）ので、何枚重なっても混ざり方が正しい
import SwiftUI
import MetalKit

final class TessLabState: ObservableObject {
    @Published var a = 0.55          // X-W（左は X-Z）
    @Published var b = 0.42          // Y-W（左は Y-Z）
    @Published var d = 0.0           // Z-W（右だけ）
    @Published var c = 0.3           // X-Y（両方）
    @Published var s = 0.0           // 断面の位置
    @Published var auto = false
    @Published var sweep = false
    @Published var camW = 3.0
    @Published var slice = false     // 見せ方：false 全体（プラケース）・true 断面
    @Published var look = 0          // 質感（TessLabState.looks）
    @Published var sparkle = false   // キラキラ（プラケースなどで）
    @Published var glowLines = false // 辺：false 光沢のある管・true 光る線
    var viewYaw = [0.75, 0.75], viewPitch = [0.42, 0.32], viewDist = [6.2, 7.4]   // 左・右の視点
    private var tSweep = 0.0
    func reset() { a = 0.55; b = 0.42; d = 0; c = 0.3; s = 0; viewYaw = [0.75, 0.75]; viewPitch = [0.42, 0.32]; viewDist = [6.2, 7.4] }
    func tick(_ dt: Double) {
        if auto { a += 0.5 * dt; b += 0.33 * dt; d += 0.21 * dt }
        if sweep { tSweep += dt; s = 1.9 * sin(tSweep * 0.55) }
    }
    /// 平面 (i, j) の回転
    static func rot(_ i: Int, _ j: Int, _ t: Double) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        m[i][i] = cos(t); m[j][j] = cos(t); m[i][j] = sin(t); m[j][i] = -sin(t)   // 列 i が (cos, sin) ＝ e_i → cos e_i ＋ sin e_j
        return m
    }
    /// 右：超立方体の向き（物 → 見る側）。X-W → Y-W → Z-W → X-Y の順
    var M4: simd_double4x4 { Self.rot(0, 1, c) * Self.rot(2, 3, d) * Self.rot(1, 3, b) * Self.rot(0, 3, a) }
    /// 左：立方体の向き（z が「切る向き」。X-Z → Y-Z → X-Y の順。4 番目は使わない）
    var M3: simd_double4x4 { Self.rot(0, 1, c) * Self.rot(1, 2, b) * Self.rot(0, 2, a) }

    /// 質感（nd-solid の LOOKS と同じ値。プラケースは、照明の窓がくっきり映る透明な板）
    ///   base 板 1 枚の濃さ・fresA/fresP フレネル・rim/rimK 縁の光・lumT/lumK 照り返しの所を不透明に・env 映り込み・sat/lift 色の整え方・add 加算（ホログラム）
    struct Look {
        let name: String; let base, fresA, fresP, rimK, lumT, lumK, env, sat, lift: Float; let rim: SIMD3<Float>; var add = false; var rodEnv: Float = 1
        var soft = false        // やわらかな照明（大きな照り返し＝次元おりがみのグレア）。false は角ばった照明の窓（プラケース）
        var rodK: Float = 1     // 辺の太さ（管の何倍か）
        var balls = 1           // 頂点：0 なし・1 全部の玉・2 目印の 2 つだけ（次元おりがみのマゼンタと水色）
        var flatBG = false      // 背景を次元おりがみの紺一色に
        var axes = false        // 座標軸の矢印と名前（x・y・z・w）
        var edge: Float = 1     // 板のふちの光の強さ（プラケースは白く強く、次元おりがみは面の色で控えめ）
    }
    static let looks: [Look] = [
        // 次元おりがみ：胞の色の濃いめの板・大きくやわらかな照り返し・細い辺・目印の 2 つの頂点・座標軸（ウェブ版の見た目）
        Look(name: "次元おりがみ", base: 0.30, fresA: 0.16, fresP: 2.2, rimK: 0.08, lumT: 0.9, lumK: 0.55, env: 1.0, sat: 1.5, lift: 0.0, rim: [0.88, 0.94, 1.0], rodEnv: 0.6,
             soft: true, rodK: 0.4, balls: 2, flatBG: true, axes: true, edge: 0.45),
        Look(name: "プラケース", base: 0.045, fresA: 0.32, fresP: 2.6, rimK: 0.3, lumT: 0.55, lumK: 1.6, env: 1.9, sat: 1.25, lift: 0.0, rim: [0.88, 0.94, 1.0], rodEnv: 1.4),
        Look(name: "擦りガラス", base: 0.07, fresA: 0.62, fresP: 2.4, rimK: 0.42, lumT: 0.5, lumK: 1.8, env: 1.5, sat: 0.6, lift: 0.06, rim: [0.82, 0.9, 1.0], rodEnv: 1.1),
        Look(name: "結晶", base: 0.12, fresA: 0.5, fresP: 1.8, rimK: 0.3, lumT: 0.45, lumK: 1.5, env: 1.7, sat: 1.2, lift: 0, rim: [1.0, 0.97, 0.92], rodEnv: 1.3),
        Look(name: "樹脂", base: 0.26, fresA: 0.18, fresP: 1.4, rimK: 0.12, lumT: 0.85, lumK: 0.6, env: 0.45, sat: 0.8, lift: 0.14, rim: [1, 1, 1], rodEnv: 0.5),
        Look(name: "ビビッド", base: 0.34, fresA: 0.12, fresP: 2.2, rimK: 0, lumT: 0.95, lumK: 0.4, env: 0.12, sat: 1.35, lift: 0, rim: [1, 1, 1], rodEnv: 0.6),
        Look(name: "ホログラム", base: 0.05, fresA: 0.18, fresP: 1.8, rimK: 0.3, lumT: 2, lumK: 0, env: 0, sat: 1.6, lift: 0, rim: [0.65, 0.88, 1.0], add: true, rodEnv: 0.4),
    ]
}

struct TLUni {
    var eye = SIMD4<Float>(0, 0, 0, 0), R = SIMD4<Float>(0, 0, 0, 0), U = SIMD4<Float>(0, 0, 0, 0), F = SIMD4<Float>(0, 0, 0, 0)
    var M = matrix_identity_float4x4
    var p = SIMD4<Float>(0, 0, 0, 0)      // tanF・横長・断面 s・断面の写す倍率 k
    var q = SIMD4<Float>(0, 0, 0, 0)      // 面の数・左 0 右 1・時刻・見せ方（0 全体・1 断面）
    var cnt = SIMD4<Float>(0, 0, 0, 0)    // 管の数・玉の数
    var L0 = SIMD4<Float>(0, 0, 0, 0)     // base・fresA・fresP・rimK
    var L1 = SIMD4<Float>(0, 0, 0, 0)     // lumT・lumK・env・sat
    var L2 = SIMD4<Float>(0, 0, 0, 0)     // lift・加算・キラキラ・光る線
    var rim = SIMD4<Float>(0, 0, 0, 0)    // 縁の光の色・管の映り込み
    var L3 = SIMD4<Float>(0, 0, 0, 0)     // やわらかな照明・紺一色の背景・ふちの光・three.js の光（次元おりがみ）
    var S0 = SIMD4<Float>(0, 0, 0, 0), S1 = SIMD4<Float>(0, 0, 0, 0), S2 = SIMD4<Float>(0, 0, 0, 0), S3 = SIMD4<Float>(0, 0, 0, 0)
}
struct TLQuad { var a, b, c, d, n, col: SIMD4<Float>; var m = SIMD4<Float>(0, 0, 0, 0) }   // 4 つの角・法線（w は平面の位置）・色（w はふちの光）・m.x 板の濃さ（0 なら質感の値）
struct TLRod { var a, b, col: SIMD4<Float> }             // 両はし（a.w は太さ）・色（w は明るさ）
struct TLBall { var p, col: SIMD4<Float> }               // 中心（w は半径）・色

let tlShader = """
#include <metal_stdlib>
using namespace metal;
struct U { float4 eye, R, U, F; float4x4 M; float4 p, q, cnt, L0, L1, L2, rim, L3, S0, S1, S2, S3; };   // S：次元おりがみの光（S0 照り返し・強さ・ざらつきの倍率・グレア、S1 鮮やかさ・映り込み・金属っぽさ・ざらつき、S2 主光・S3 逆光の位置）
struct Quad { float4 a, b, c, d, n, col, m; };   // m.x 板の濃さ（0 なら質感の値）
struct Rod { float4 a, b, col; };
struct Ball { float4 p, col; };
struct O { float4 pos [[position]]; float2 uv; };
vertex O tlv(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); O o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = p; return o; }
// 胞の色（visual-fx のパレット：x #f43f5e・y #10b981・z #38bdf8・w #a855f7）
constant float3 CELL[4] = { float3(0.957, 0.247, 0.369), float3(0.063, 0.725, 0.506), float3(0.220, 0.741, 0.973), float3(0.659, 0.333, 0.969) };
// ---- スタジオの映り込み（nd-solid の envMap と同じ考え：上が明るく下が暗い空 ＋ 白い照明の板 3 枚）。上は z ----
constant float3 LD[4] = { float3(-0.5361, 0.4386, 0.7212), float3(0.8833, 0.2650, 0.3864), float3(0.0526, -0.8940, 0.4207), float3(-0.30, -0.25, 0.92) };
constant float LK[4] = { 2.6, 1.6, 1.2, 1.4 };
constant float2 LS[4] = { float2(0.34, 0.24), float2(0.16, 0.42), float2(0.46, 0.12), float2(0.55, 0.06) };
inline float3 sky(float3 r) {
    float t = r.z * 0.5 + 0.5; float3 top = float3(0.55, 0.62, 0.78), mid = float3(0.12, 0.13, 0.20), bot = float3(0.015, 0.02, 0.05);
    return t > 0.5 ? mix(mid, top, pow((t - 0.5) * 2.0, 1.5)) : mix(bot, mid, t * 2.0);
}
inline float3 envSoft(float3 r) {                         // やわらかな照明：大きなぼんやりした光 2 つ（次元おりがみのグレア）
    float3 c = sky(r) * 0.55;
    c += float3(1.0, 0.98, 1.04) * 1.9 * pow(smoothstep(0.30, 0.97, dot(r, LD[0])), 1.6);
    c += float3(0.80, 0.90, 1.0) * 0.9 * pow(smoothstep(0.50, 0.98, dot(r, LD[1])), 1.6);
    return c;
}
inline float3 env(float3 r) {
    float3 c = sky(r);
    float hz = r.z;                                       // 地平線のあたりの細い光の帯（スタジオの照明の筒）
    c += float3(0.9, 0.95, 1.0) * 0.55 * exp(-pow((hz - 0.08) / 0.035, 2.0));
    for (int i = 0; i < 4; i++) {
        float3 l = LD[i]; float cz = dot(r, l); if (cz < 0.3) continue;
        float3 up = abs(l.z) < 0.9 ? float3(0, 0, 1) : float3(1, 0, 0), uu = normalize(cross(up, l)), vv = cross(l, uu);
        float a = abs(dot(r, uu) / cz), b = abs(dot(r, vv) / cz);
        float w = (1.0 - smoothstep(LS[i].x * 0.92, LS[i].x, a)) * (1.0 - smoothstep(LS[i].y * 0.92, LS[i].y, b));
        c += LK[i] * w * float3(1.0, 1.0, 1.05);
    }
    return c;
}
inline float hash3(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
// ---- 板（プラケース）：色・フレネル・縁の光・映り込み・照り返しの所を不透明に・キラキラ ----
float4 plate(float3 col, float3 n, float3 d, float3 P, float edgeK, constant U& u, float base = -1.0) {
    if (dot(n, d) > 0.0) n = -n;
    float cosv = clamp(-dot(n, d), 0.0, 1.0), F = pow(1.0 - cosv, u.L0.z);
    float Y = dot(col, float3(0.299, 0.587, 0.114));
    float3 c = clamp((Y + (col - Y) * u.L1.w) * (1.0 - u.L2.x) + u.L2.x, 0.0, 1.0);
    float3 r = reflect(d, n), e = u.L3.x > 0.5 ? envSoft(r) : env(r);
    float sch = 0.04 + 0.96 * pow(1.0 - cosv, 5.0);
    float3 refl = e * u.L1.z * (0.10 + 0.90 * sch);
    float dif = (u.L3.x > 0.5 ? 0.55 : 0.38) + 0.62 * max(0.0, dot(n, LD[0]));
    float3 rgb = c * dif + refl + u.rim.rgb * F * u.L0.w;
    float a = (base >= 0.0 ? base : u.L0.x) + F * u.L0.y;
    float lum = max(refl.r, max(refl.g, refl.b));
    a = clamp(max(a, (lum - u.L1.x) * u.L1.y), 0.0, 1.0);
    // 板のふち（アクリルの切り口）：光を集めて明るく光る
    edgeK *= u.L3.z;
    rgb += (u.L3.x > 0.5 ? c * 1.3 + e * 0.2 : u.rim.rgb * 0.8 + e * 0.5 + c * 0.6) * edgeK; a = max(a, edgeK * 0.8);   // やわらかな照明（次元おりがみ）では、ふちは面の色で
    if (u.L2.z > 0.5) {                                   // キラキラ：細かい粒（傷・ラメ）が、それぞれ少し違う向きで照明を映してきらめく
        float3 g = P * 26.0, cell = floor(g); float h = hash3(cell);
        if (h > 0.86) {
            float3 jn = normalize(n + (float3(hash3(cell + 19.19), hash3(cell + 47.47), hash3(cell + 83.3)) - 0.5) * 1.1);
            float3 rr = reflect(d, jn); float gl = 0.0;
            for (int i = 0; i < 4; i++) gl += LK[i] * pow(max(0.0, dot(rr, LD[i])), 90.0);
            float3 lc = fract(g) - 0.5; float dotm = exp(-dot(lc, lc) * 45.0);
            float tw = 0.5 + 0.5 * sin(u.q.z * 2.3 + h * 70.0);
            float sp = gl * tw * dotm * 6.0;
            rgb += float3(1.0, 0.97, 0.92) * sp; a = max(a, min(1.0, sp));
        }
    }
    return float4(rgb, a);
}
// ---- 管・玉：光沢（映り込み ＋ 光） ----
inline float3 glossy(float3 col, float3 n, float3 d, constant U& u) {
    float cosv = clamp(-dot(n, d), 0.0, 1.0); float3 e = u.L3.x > 0.5 ? envSoft(reflect(d, n)) : env(reflect(d, n));
    float sch = 0.04 + 0.96 * pow(1.0 - cosv, 5.0), dif = 0.3 + 0.7 * max(0.0, dot(n, LD[0]));
    return col * dif * 0.9 + e * (0.18 + 0.82 * sch) * u.rim.w * 0.7;
}
// ---- 次元おりがみ（ウェブ版）の光：three.js の MeshStandardMaterial と同じ式（GGX）＋ visual-fx の照り返しライト・グレア・鮮やかさ ----
//   光：環境光（白 0.9）・平行光 2 つ（空色 1.4 を右上前から、紫 0.9 を左下うしろから）。照り返しライト：主光（白 1.0、カメラから見て左右 az・上下 el）と逆光（淡い青 0.8）
inline float3 ggxSpec(float3 n, float3 v, float3 l, float3 F0, float rough) {
    float al = max(rough, 0.0525); al = al * al; float a2 = al * al;
    float3 h = normalize(l + v); float nl = saturate(dot(n, l)), nv = saturate(dot(n, v)), nh = saturate(dot(n, h)), lh = saturate(dot(l, h));
    float3 F = F0 + (1.0 - F0) * pow(1.0 - lh, 5.0);
    float gv = nl * sqrt(a2 + (1.0 - a2) * nv * nv), gl = nv * sqrt(a2 + (1.0 - a2) * nl * nl), G = 0.5 / max(gv + gl, 1e-6);
    float dd = nh * nh * (a2 - 1.0) + 1.0, D = a2 / (M_PI_F * dd * dd);
    return F * (G * D);
}
float4 stdShade(float3 C, float alpha, float3 n, float3 d, float3 P, constant U& u) {
    if (dot(n, d) > 0.0) n = -n;                              // 両面（裏から見ても表と同じに）
    float3 v = -d;
    bool shine = u.S0.x > 0.5;
    float metal = u.S1.z, rough = u.S1.w * (shine ? u.S0.z : 1.0);
    float3 diff = C * (1.0 - metal), F0 = mix(float3(0.04), C, metal);
    float3 dD = diff * (shine ? 0.8 : 0.9), dS = float3(0.0);
    const float3 L1 = float3(0.4667, -0.5600, 0.6845), L2 = float3(-0.6155, 0.6155, -0.4924);   // 平行光の向き（ウェブ版の (15, 22, 18) と (−15, −12, −15)、上は z）
    const float3 C1 = float3(0.220, 0.741, 0.973) * 1.4, C2 = float3(0.659, 0.333, 0.969) * 0.9;
    float nl = saturate(dot(n, L1)); dD += diff * C1 * nl; dS += C1 * nl * M_PI_F * ggxSpec(n, v, L1, F0, rough);
    nl = saturate(dot(n, L2)); dD += diff * C2 * nl; dS += C2 * nl * M_PI_F * ggxSpec(n, v, L2, F0, rough);
    if (shine) {
        float3 lk = normalize(u.S2.xyz - P), lr = normalize(u.S3.xyz - P), cr = float3(0.86, 0.92, 1.0) * 0.8;
        nl = saturate(dot(n, lk)); dD += diff * nl; dS += nl * M_PI_F * ggxSpec(n, v, lk, F0, rough);
        nl = saturate(dot(n, lr)); dD += diff * cr * nl; dS += cr * nl * M_PI_F * ggxSpec(n, v, lr, F0, rough);
    }
    float3 g = dD + dS; float a = alpha;
    // 映り込み：スタジオ（空と照明の板）を、斜めほど強く（フレネル）
    if (u.S1.y > 0.0) {
        float nv = saturate(dot(n, v)); float3 Fr = F0 + (1.0 - F0) * pow(1.0 - nv, 5.0);
        float3 e = envSoft(reflect(d, n)) * Fr * u.S1.y; g += e; a = clamp(a + max(e.r, max(e.g, e.b)) * 0.35, 0.0, 1.0);
    }
    float Y = dot(g, float3(0.299, 0.587, 0.114));
    if (u.S1.x > 0.0) { g = max(float3(0.0), mix(float3(Y), g, 1.0 + 1.2 * u.S1.x)); a = clamp(a * (1.0 + 0.7 * u.S1.x), 0.0, 1.0); }   // 鮮やかさ
    float gl = u.S0.w;
    if (gl > 0.0) {                                           // グレア：色を深く・ふちほど白く光る（フレネル）・画面を斜めに横切るやわらかい映り込みの帯
        Y = dot(g, float3(0.299, 0.587, 0.114));
        g = max(float3(0.0), mix(float3(Y), g, 1.0 + 0.55 * gl)) * (1.0 - 0.07 * gl);
        float gF = pow(1.0 - abs(dot(n, v)), 3.0);
        float vx = dot(v, u.R.xyz), vy = dot(v, u.U.xyz);
        float gB = exp(-pow((vx * 0.62 - vy * 0.78 - 0.10) / 0.085, 2.0));
        g += float3(gF * 0.38 + gB * 0.2) * gl; a = clamp(a + (gF * 0.28 + gB * 0.1) * gl, 0.0, 1.0);
    }
    if (shine) {                                              // 照り返しライト：照り返しは色のまま 3 倍＋白、そこは不透明に（透明な面でもキラッと見える）
        float sp = max(dS.r, max(dS.g, dS.b));
        g += u.S0.y * (dS * 3.0 + float3(sp * 2.6)); a = clamp(a + u.S0.y * sp * 3.0, 0.0, 1.0);
    }
    return float4(g, a);
}
inline float capsule(float3 ro, float3 rd, float3 pa, float3 pb, float ra) {   // 光の道と管（両はしは丸）の当たり（iq の式）
    float3 ba = pb - pa, oa = ro - pa;
    float baba = dot(ba, ba), bard = dot(ba, rd), baoa = dot(ba, oa), rdoa = dot(rd, oa), oaoa = dot(oa, oa);
    float a = baba - bard * bard, b = baba * rdoa - baoa * bard, c = baba * oaoa - baoa * baoa - ra * ra * baba, h = b * b - a * c;
    if (h >= 0.0) {
        float t = (-b - sqrt(h)) / a, y = baoa + t * bard;
        if (y > 0.0 && y < baba) return t;
        float3 oc = y <= 0.0 ? oa : ro - pb; b = dot(rd, oc); c = dot(oc, oc) - ra * ra; h = b * b - c;
        if (h > 0.0) return -b - sqrt(h);
    }
    return -1.0;
}
inline float2 segDist(float3 o, float3 d, float3 a, float3 b) {                // 光る線：光の道と線分のいちばん近い所（距離・t）
    float3 ba = b - a, oa = o - a; float bb = dot(ba, ba), bd = dot(ba, d), od = dot(oa, d), ob = dot(oa, ba);
    float den = bb - bd * bd; float h = den > 1e-6 ? clamp((ob - od * bd) / den, 0.0, 1.0) : 0.0;
    float t = max(0.0, dot(a + ba * h - o, d)); h = clamp(dot(o + d * t - a, ba) / max(bb, 1e-6), 0.0, 1.0);
    float3 q = a + ba * h; t = max(0.0, dot(q - o, d));
    return float2(length(o + d * t - q), t);
}
fragment float4 tlf(O in [[stage_in]], constant U& u [[buffer(0)]], const device Quad* Q [[buffer(1)]], const device Rod* RD [[buffer(2)]], const device Ball* BL [[buffer(3)]]) {
    float2 nn = in.uv * 2.0 - 1.0;
    float3 o = u.eye.xyz, d = normalize(u.F.xyz + u.R.xyz * nn.x * u.p.x * u.p.y + u.U.xyz * nn.y * u.p.x);
    float3 bg = mix(float3(0.010, 0.016, 0.040), float3(0.035, 0.045, 0.10), 0.5 + 0.5 * d.z);
    if (u.L3.y > 0.5) bg = mix(float3(0.020, 0.031, 0.086), float3(0.010, 0.014, 0.040), clamp(length(nn) * 0.7, 0.0, 1.0));   // 次元おりがみの紺（真ん中が少し明るい）
    bool add = u.L2.y > 0.5, lines = u.L2.w > 0.5, right = u.q.y > 0.5, slice = u.q.w > 0.5;
    float s = u.p.z;
    // ---- 1. 不透明：管と玉（いちばん手前） ----
    float tOp = 1e9; float3 opCol = float3(0.0);
    {
        int nr = lines ? 0 : int(u.cnt.x), nb = int(u.cnt.y);
        for (int i = 0; i < nr; i++) {
            float t = capsule(o, d, RD[i].a.xyz, RD[i].b.xyz, RD[i].a.w);
            if (t > 0.0 && t < tOp) {
                float3 P = o + d * t, ba = RD[i].b.xyz - RD[i].a.xyz; float h = clamp(dot(P - RD[i].a.xyz, ba) / dot(ba, ba), 0.0, 1.0);
                tOp = t; opCol = glossy(RD[i].col.rgb * RD[i].col.w, normalize(P - RD[i].a.xyz - ba * h), d, u);
            }
        }
        for (int i = 0; i < nb; i++) {
            float3 oc = o - BL[i].p.xyz; float b = dot(oc, d), c = dot(oc, oc) - BL[i].p.w * BL[i].p.w, h = b * b - c;
            if (h > 0.0) { float t = -b - sqrt(h); if (t > 0.0 && t < tOp) {
                tOp = t; float3 bn = normalize(o + d * t - BL[i].p.xyz);
                opCol = BL[i].col.w > 1.5 ? BL[i].col.rgb * (0.85 + 0.35 * max(0.0, dot(bn, LD[0]))) + 0.25 * pow(max(0.0, dot(reflect(d, bn), LD[0])), 30.0) : glossy(BL[i].col.rgb, bn, d, u);   // 目印の点は自分で光る
            } }
        }
    }
    // ---- 2. 透明な板：光の道に当たった順に並べて、手前から重ねる ----
    float th[20]; int ih[20]; int nh = 0;
    int nq = int(u.q.x);
    for (int i = 0; i < nq; i++) {
        float3 n = Q[i].n.xyz; float dn = dot(n, d); if (abs(dn) < 1e-6) continue;
        float t = (Q[i].n.w - dot(n, o)) / dn; if (t <= 1e-4 || t >= tOp) continue;
        float3 P = o + d * t;
        float s0 = dot(cross(Q[i].b.xyz - Q[i].a.xyz, P - Q[i].a.xyz), n), s1 = dot(cross(Q[i].c.xyz - Q[i].b.xyz, P - Q[i].b.xyz), n);
        float s2 = dot(cross(Q[i].d.xyz - Q[i].c.xyz, P - Q[i].c.xyz), n), s3 = dot(cross(Q[i].a.xyz - Q[i].d.xyz, P - Q[i].d.xyz), n);
        if (!((s0 >= 0 && s1 >= 0 && s2 >= 0 && s3 >= 0) || (s0 <= 0 && s1 <= 0 && s2 <= 0 && s3 <= 0))) continue;
        int k = min(nh, 19); if (nh >= 20 && t >= th[19]) continue;
        while (k > 0 && th[k - 1] > t) { th[k] = th[k - 1]; ih[k] = ih[k - 1]; k--; }
        th[k] = t; ih[k] = i; nh = min(nh + 1, 20);
    }
    float3 acc = float3(0.0); float T = 1.0;
    // ---- 断面：右は超立方体の 3D の断面（立体）、左は立方体の平面の断面（多角形）と方眼の板。手前の板と一緒に、当たった順に重ねる ----
    float tS = 1e9; float4 sCol = float4(0.0); float tS2 = 1e9; float4 sCol2 = float4(0.0);
    if (slice && right) {
        float k = u.p.w; float3 oq = o / k, dq = d / k;
        float t0 = -1e9, t1 = 1e9; int i0 = 0, i1 = 0; float s0 = 1.0, s1 = 1.0; bool miss = false;
        for (int i = 0; i < 4; i++) {
            float4 c = u.M[i]; float A = dot(c.xyz, oq) + c.w * s, B = dot(c.xyz, dq);
            if (abs(B) < 1e-7) { if (abs(A) > 1.0) miss = true; continue; }
            float ta = (-1.0 - A) / B, tb = (1.0 - A) / B, tn = min(ta, tb), tf = max(ta, tb);
            if (tn > t0) { t0 = tn; i0 = i; s0 = tn == ta ? -1.0 : 1.0; }
            if (tf < t1) { t1 = tf; i1 = i; s1 = tf == ta ? -1.0 : 1.0; }
        }
        if (!miss && t0 < t1 && t1 > 0.0 && max(t0, 0.0) < tOp) {
            t0 = max(t0, 0.0);
            float3 P0 = o + d * t0, P1 = o + d * min(t1, tOp);
            float e0 = 1e9, e1 = 1e9;
            for (int j = 0; j < 4; j++) {
                float4 c = u.M[j]; float g = max(length(c.xyz) / k, 1e-4);
                if (j != i0) e0 = min(e0, (1.0 - abs(dot(c.xyz, P0 / k) + c.w * s)) / g);
                if (j != i1) e1 = min(e1, (1.0 - abs(dot(c.xyz, P1 / k) + c.w * s)) / g);
            }
            float4 f = plate(CELL[i0] * (s0 > 0.0 ? 1.0 : 0.7), normalize(u.M[i0].xyz * s0), d, P0, 0.0, u);
            float absorb = 1.0 - exp(-(min(t1, tOp) - t0) * 1.4);
            f.a = clamp(f.a + absorb * 0.45 + (1.0 - smoothstep(0.004, 0.03, e0)) * 0.9, 0.0, 1.0);
            f.rgb += CELL[i0] * (1.0 - smoothstep(0.004, 0.03, e0)) * 1.6;
            tS = t0; sCol = f;
            if (t1 < tOp) { float4 bk = plate(CELL[i1] * (s1 > 0.0 ? 1.0 : 0.7), normalize(u.M[i1].xyz * s1), d, P1, 0.0, u); bk.a = clamp(bk.a + (1.0 - smoothstep(0.004, 0.03, e1)) * 0.6, 0.0, 1.0); tS2 = t1; sCol2 = bk; }
        }
    } else if (slice && !right) {
        float tp = abs(d.z) > 1e-6 ? (s - o.z) / d.z : -1.0;
        if (tp > 0.0 && tp < tOp) {
            float3 P = o + d * tp, X = float3(dot(u.M[0].xyz, P), dot(u.M[1].xyz, P), dot(u.M[2].xyz, P));
            float rr = length(P.xy);
            if (all(abs(X) <= 1.0)) {
                float e = 1e9; int ie = 0;
                for (int i = 0; i < 3; i++) { float g = max(length(u.M[i].xy), 1e-4), sl = (1.0 - abs(X[i])) / g; if (sl < e) { e = sl; ie = i; } }
                float edge = 1.0 - smoothstep(0.006, 0.035, e);
                float4 f = plate(float3(0.55, 0.85, 0.95), float3(0, 0, 1), d, P, 0.0, u);
                f.a = clamp(f.a + 0.45 + edge, 0.0, 1.0); f.rgb = f.rgb * 0.8 + CELL[ie] * edge * 1.8;
                tS = tp; sCol = f;
            } else if (rr < 2.7) {
                float2 g = abs(fract(P.xy * 2.0 + 0.5) - 0.5) / fwidth(P.xy * 2.0);
                float grid = (1.0 - min(min(g.x, g.y), 1.0)), fade = 1.0 - smoothstep(2.2, 2.7, rr);
                tS = tp; sCol = float4(float3(0.35, 0.55, 0.95) * (0.5 + grid), (0.06 + 0.25 * grid) * fade);
            }
        }
    }
    // 重ねる（ふつう：手前から不透明度で、ホログラム：足す）
    int k2 = 0; bool sDone = tS >= 1e8, s2Done = tS2 >= 1e8;
    for (int step = 0; step < 24; step++) {
        float tq = k2 < nh ? th[k2] : 1e9;
        float4 g;
        if (!sDone && tS <= tq && tS <= tS2) { g = sCol; sDone = true; }
        else if (!s2Done && tS2 <= tq) { g = sCol2; s2Done = true; }
        else if (k2 < nh) {
            int i = ih[k2]; float3 P = o + d * tq;
            // 板のふちまでの近さ（4 本の辺のいちばん近いもの）
            float e = 1e9; float3 C4[4] = { Q[i].a.xyz, Q[i].b.xyz, Q[i].c.xyz, Q[i].d.xyz };
            for (int j = 0; j < 4; j++) { float3 a = C4[j], b = C4[(j + 1) & 3], ba = b - a; float hh = clamp(dot(P - a, ba) / dot(ba, ba), 0.0, 1.0); e = min(e, length(P - a - ba * hh)); }
            float ek = (1.0 - smoothstep(0.012, 0.045, e)) * Q[i].col.w;
            g = u.L3.w > 0.5 ? stdShade(Q[i].col.rgb, Q[i].m.x, Q[i].n.xyz, d, P, u) : plate(Q[i].col.rgb, Q[i].n.xyz, d, P, ek, u, Q[i].m.x > 0.0 ? Q[i].m.x : -1.0); k2++;
        }
        else break;
        if (add) acc += g.rgb * g.a * 1.4; else { acc += T * g.a * g.rgb; T *= 1.0 - g.a; }
    }
    if (tOp < 1e9) acc += (add ? 1.0 : T) * opCol; else acc += (add ? 1.0 : T) * bg;
    // ---- 光る線（辺をネオンの線で。管の代わり） ----
    if (lines) {
        int nr = int(u.cnt.x); float3 glow = float3(0.0);
        for (int i = 0; i < nr; i++) {
            float2 h = segDist(o, d, RD[i].a.xyz, RD[i].b.xyz);
            float r = max(RD[i].a.w, h.y * u.cnt.z * 0.75);              // 細い線は画面で 1.5 画素ほどより細くしない（cnt.z：1 画素の角度）
            float core = 1.0 - smoothstep(r * 0.35, r, h.x), halo = exp(-h.x * h.x / (r * r * 9.0)) * u.cnt.w;
            glow += RD[i].col.rgb * RD[i].col.w * (core * 1.4 + halo);
        }
        acc += glow;
    }
    if (u.L3.w > 0.5) {                                       // 次元おりがみ：ウェブ版と同じ色のまま（明るい所だけ、白へやわらかく丸める）
        float3 k = step(float3(0.85), acc); acc = mix(acc, 0.85 + 0.15 * (1.0 - exp(-(acc - 0.85) / 0.15)), k);
        return float4(acc, 1.0);
    }
    acc = 1.0 - exp(-acc * 1.25);                                       // 明るい所をやわらかく（トーンマップ）
    return float4(pow(acc, float3(0.95)), 1.0);
}
"""

final class TessLabRenderer: NSObject, MTKViewDelegate {
    let left: Bool, st: TessLabState
    let device: MTLDevice, queue: MTLCommandQueue
    private var pipe: MTLRenderPipelineState!
    private var lastT = CACurrentMediaTime()
    /// 辺の色（座標軸のいつもの色：x #ff5d6c・y #3ddc84・z #56a8ff・w #b07cff）と、胞・面の色（パレット）
    static let axis: [SIMD3<Float>] = [[1.0, 0.365, 0.424], [0.239, 0.863, 0.518], [0.337, 0.659, 1.0], [0.690, 0.486, 1.0]]
    static let cell: [SIMD3<Float>] = [[0.957, 0.247, 0.369], [0.063, 0.725, 0.506], [0.220, 0.741, 0.973], [0.659, 0.333, 0.969]]
    static let SCALE = 1.0

    init?(left: Bool, state: TessLabState, view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        self.left = left; st = state; device = d; queue = q
        super.init()
        view.device = d; view.colorPixelFormat = .bgra8Unorm; view.preferredFramesPerSecond = 60
        let lib = try! d.makeLibrary(source: tlShader, options: nil)
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = lib.makeFunction(name: "tlv"); p.fragmentFunction = lib.makeFunction(name: "tlf"); p.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipe = try! d.makeRenderPipelineState(descriptor: p)
    }

    /// 頂点 m（ビットが ＋ の軸）の、写した 3D の位置と、見かけの大きさ（遠近の倍率）
    func vert(_ m: Int) -> (SIMD3<Float>, Double) {
        if left {
            let x = SIMD4<Double>((0..<3).map { m & (1 << $0) != 0 ? 1.0 : -1.0 } + [0]), y = st.M3 * x
            return (SIMD3<Float>(Float(y.x), Float(y.y), Float(y.z)), 1)
        }
        let x = SIMD4<Double>((0..<4).map { m & (1 << $0) != 0 ? 1.0 : -1.0 }), y = st.M4 * x, cw = st.camW
        let k = cw / max(0.4, cw - y.w) * Self.SCALE
        return (SIMD3<Float>(Float(y.x * k), Float(y.y * k), Float(y.z * k)), k)
    }
    /// 辺（管）・頂点（玉）・面（板）。右の超立方体は 8 つの胞 × 6 つの面（胞の色）、左の立方体は 6 つの面（面の軸の色）
    func geometry() -> (quads: [TLQuad], rods: [TLRod], balls: [TLBall]) {
        let dim = left ? 3 : 4, nv = 1 << dim
        let V = (0..<nv).map { vert($0) }, kMax = V.map(\.1).max() ?? 1
        func kr(_ i: Int) -> Float { Float((V[i].1 / kMax).squareRoot()) }   // 手前を 1 として、遠いほど細く
        let look = TessLabState.looks[st.look]
        let rodR: Float = st.glowLines ? 0.02 : 0.022 * look.rodK, ballR: Float = 0.042
        var rods: [TLRod] = [], balls: [TLBall] = [], quads: [TLQuad] = []
        for v in 0..<nv { for ax in 0..<dim where v & (1 << ax) == 0 {
            let w = v | (1 << ax), br: Float = left ? 1 : Float(0.55 + 0.45 * (V[v].1 + V[w].1) / (2 * kMax))
            rods.append(TLRod(a: SIMD4(V[v].0, rodR * (kr(v) + kr(w)) / 2), b: SIMD4(V[w].0, 0), col: SIMD4(Self.axis[ax], br)))
        } }
        if look.balls == 1 { for v in 0..<nv { balls.append(TLBall(p: SIMD4(V[v].0, ballR * kr(v)), col: SIMD4(0.92, 0.94, 1.0, 1))) } }
        if look.balls == 2 {                                              // 目印の 2 つの頂点（次元おりがみと同じ：全部 ＋ はマゼンタ、全部 − は水色）
            balls.append(TLBall(p: SIMD4(V[nv - 1].0, 0.05 * kr(nv - 1)), col: SIMD4(1.0, 0.267, 0.867, 2)))
            balls.append(TLBall(p: SIMD4(V[0].0, 0.05 * kr(0)), col: SIMD4(0.2, 0.898, 1.0, 2)))
        }
        // 板：fixed の軸を値 sv にした、残り 2 軸 (p, q) で張る正方形
        func quad(_ fixed: [(Int, Int)], _ p: Int, _ q: Int, _ col: SIMD3<Float>) {
            var base = 0; for (ax, sv) in fixed where sv > 0 { base |= 1 << ax }
            let idx = [base, base | (1 << p), base | (1 << p) | (1 << q), base | (1 << q)]
            let P = idx.map { V[$0].0 }
            var n = simd_cross(P[1] - P[0], P[3] - P[0]); let l = simd_length(n); if l < 1e-6 { return }; n /= l
            quads.append(TLQuad(a: SIMD4(P[0], 0), b: SIMD4(P[1], 0), c: SIMD4(P[2], 0), d: SIMD4(P[3], 0), n: SIMD4(n, simd_dot(n, P[0])), col: SIMD4(col, 1)))
        }
        if left {
            for f in 0..<3 { for sv in [-1, 1] { let o = (0..<3).filter { $0 != f }; quad([(f, sv)], o[0], o[1], Self.cell[f] * (sv > 0 ? 1 : 0.8)) } }
        } else if !st.slice {
            // 24 枚の正方形（2 つの軸 k・f を ±1 に決めたもの）。1 枚は 2 つの胞の境なので、色は 2 つの胞の色の間（同じ板を 2 回重ねると濁るので 1 回だけ）
            for k in 0..<4 { for f in (k + 1)..<4 { for sk in [-1, 1] { for sf in [-1, 1] {
                let pq = (0..<4).filter { $0 != k && $0 != f }
                quad([(k, sk), (f, sf)], pq[0], pq[1], (Self.cell[k] * (sk > 0 ? 1 : 0.8) + Self.cell[f] * (sf > 0 ? 1 : 0.8)) / 2)
            } } } }
        }
        return (quads, rods, balls)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        if left { st.tick(dt) }
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer(),
              let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let i = left ? 0 : 1, yaw = st.viewYaw[i], pit = st.viewPitch[i], dist = st.viewDist[i]
        // 視点：上は z（左の平面が水平に見えるように）
        let eye = SIMD3(cos(pit) * cos(yaw), cos(pit) * sin(yaw), sin(pit)) * dist
        let F = simd_normalize(-eye), Rr = simd_normalize(simd_cross(F, SIMD3(0, 0, 1))), Uu = simd_cross(Rr, F)
        var u = TLUni()
        u.eye = SIMD4(SIMD3<Float>(eye), 0); u.R = SIMD4(SIMD3<Float>(Rr), 0); u.U = SIMD4(SIMD3<Float>(Uu), 0); u.F = SIMD4(SIMD3<Float>(F), 0)
        let M = left ? st.M3 : st.M4
        u.M = simd_float4x4(SIMD4<Float>(M.columns.0), SIMD4<Float>(M.columns.1), SIMD4<Float>(M.columns.2), SIMD4<Float>(M.columns.3))
        let sz = view.drawableSize, k = st.camW / max(0.4, st.camW - st.s) * Self.SCALE
        u.p = SIMD4(Float(tan(22.5 * Double.pi / 180)), Float(sz.width / max(1, sz.height)), Float(st.s), Float(k))
        let (quads, rods, balls) = geometry()
        let L = TessLabState.looks[st.look]
        u.q = SIMD4(Float(quads.count), left ? 0 : 1, Float(now.truncatingRemainder(dividingBy: 1000)), st.slice ? 1 : 0)
        u.cnt = SIMD4(Float(rods.count), Float(balls.count), Float(2 * tan(22.5 * Double.pi / 180) / max(1, sz.height)), 0.35)
        u.L0 = SIMD4(L.base, L.fresA, L.fresP, L.rimK); u.L1 = SIMD4(L.lumT, L.lumK, L.env, L.sat)
        u.L2 = SIMD4(L.lift, L.add ? 1 : 0, st.sparkle ? 1 : 0, st.glowLines ? 1 : 0); u.rim = SIMD4(L.rim, L.rodEnv)
        u.L3 = SIMD4(L.soft ? 1 : 0, L.flatBG ? 1 : 0, L.edge, 0)
        var qd = quads.isEmpty ? [TLQuad(a: .zero, b: .zero, c: .zero, d: .zero, n: .zero, col: .zero)] : quads
        var rd = rods.isEmpty ? [TLRod(a: .zero, b: .zero, col: .zero)] : rods, bl = balls.isEmpty ? [TLBall(p: .zero, col: .zero)] : balls
        guard let qb = device.makeBuffer(bytes: &qd, length: MemoryLayout<TLQuad>.stride * qd.count, options: .storageModeShared),
              let rb = device.makeBuffer(bytes: &rd, length: MemoryLayout<TLRod>.stride * rd.count, options: .storageModeShared),
              let bb = device.makeBuffer(bytes: &bl, length: MemoryLayout<TLBall>.stride * bl.count, options: .storageModeShared) else { return }
        e.setRenderPipelineState(pipe)
        e.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
        e.setFragmentBuffer(qb, offset: 0, index: 1)
        e.setFragmentBuffer(rb, offset: 0, index: 2)
        e.setFragmentBuffer(bb, offset: 0, index: 3)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding(); cb.present(dr); cb.commit()
    }
}

#if os(macOS)
struct TessPane: NSViewRepresentable {
    let left: Bool; let st: TessLabState
    final class Holder { var r: TessLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = TessLabRenderer(left: left, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct TessPane: UIViewRepresentable {
    let left: Bool; let st: TessLabState
    final class Holder { var r: TessLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = TessLabRenderer(left: left, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif

struct TessLabView: View {
    @StateObject private var st = TessLabState()
    @State private var last: CGSize = .zero
    @State private var pinch0: Double? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                pane(true, st.slice ? "【2 次元の生き物】立方体を平面で切る　ドラッグで傾ける・⇧＋ドラッグで断面を上下" : "【立方体】3 次元の箱　ドラッグで傾ける")
                pane(false, st.slice ? "【私たち】超立方体を 3D 空間で切る　ドラッグで見る向き" : "【超立方体】4 次元の箱を 3D へ写す　ドラッグで見る向き")
            }
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
            controls
        }
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
        .preferredColorScheme(.dark)
    }
    func pane(_ left: Bool, _ tag: String) -> some View {
        let i = left ? 0 : 1
        return ZStack(alignment: .topLeading) {
            TessPane(left: left, st: st)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let dd = CGSize(width: g.translation.width - last.width, height: g.translation.height - last.height); last = g.translation
                    #if os(macOS)
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let shift = false
                    #endif
                    if left && shift { st.s = max(-2, min(2, st.s - Double(dd.height) * 0.01)) }
                    else if left { st.a += Double(dd.width) * 0.01; st.b += Double(dd.height) * 0.01 }
                    else { st.viewYaw[i] -= Double(dd.width) * 0.008; st.viewPitch[i] = max(-1.4, min(1.4, st.viewPitch[i] + Double(dd.height) * 0.008)) }
                }.onEnded { _ in last = .zero })
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    if pinch0 == nil { pinch0 = st.viewDist[i] }
                    st.viewDist[i] = max(2.5, min(30, pinch0! / Double(k)))
                }.onEnded { _ in pinch0 = nil })
            if TessLabState.looks[st.look].axes { TessAxes(left: left, st: st).allowsHitTesting(false) }
            Text(tag).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).allowsHitTesting(false)
            if st.slice {
                Text(left ? "断面 z′ ＝ \(String(format: "%+.2f", st.s))（2 次元の世界）" : "断面 w′ ＝ \(String(format: "%+.2f", st.s))（3 次元の世界）。面の色は、超立方体の 8 つの胞のどれの切り口か（x 赤・y 緑・z 青・w 紫、− の側は暗め）")
                    .font(.system(size: 10)).padding(6).background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8).allowsHitTesting(false)
            }
        }
    }
    var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(st.auto ? "回転を止める" : "回転") { st.auto.toggle() }
                Button("初期位置") { st.reset() }
                Picker("", selection: $st.slice) { Text("全体").tag(false); Text("断面").tag(true) }.pickerStyle(.segmented).frame(width: 120).labelsHidden()
                if st.slice { Button(st.sweep ? "断面を止める" : "断面を動かす") { st.sweep.toggle() } }
                Picker("質感", selection: $st.look) { ForEach(TessLabState.looks.indices, id: \.self) { Text(TessLabState.looks[$0].name).tag($0) } }.frame(width: 170)
                Toggle("キラキラ", isOn: $st.sparkle)
                Picker("", selection: $st.glowLines) { Text("辺：管").tag(false); Text("辺：光る線").tag(true) }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
                Spacer()
                Text("光で描く試作（画素ごとに光を飛ばして描く）").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if st.slice { slider("断面の位置", $st.s, -2, 2, "%+.2f") }
                slider("X-W（左 X-Z）", deg($st.a), -180, 180)
                slider("Y-W（左 Y-Z）", deg($st.b), -180, 180)
                slider("Z-W（右だけ）", deg($st.d), -180, 180)
                slider("X-Y", deg($st.c), -180, 180)
                slider("4D の遠近", $st.camW, 2.2, 12, "%.1f")
            }
        }
        .padding(10).background(Color(red: 0.04, green: 0.06, blue: 0.11)).controlSize(.small)
    }
    func deg(_ b: Binding<Double>) -> Binding<Double> {
        Binding(get: { var x = (b.wrappedValue * 180 / .pi + 180).truncatingRemainder(dividingBy: 360); if x < 0 { x += 360 }; return x - 180 }, set: { b.wrappedValue = $0 * .pi / 180 })
    }
    func slider(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, _ fmt: String = "%+.0f°") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.caption); Spacer(); Text(String(format: fmt, v.wrappedValue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: v, in: lo...hi)
        }
    }
}

/// 座標軸の矢印と名前（次元おりがみと同じ：細い矢印、x・y・z・w を数式の斜体で、軸の色）。景色と同じ視点で、画面の上に描く
struct TessAxes: View {
    let left: Bool; @ObservedObject var st: TessLabState
    static let names = ["x", "y", "z", "w"]
    static let cols: [Color] = [Color(red: 1.0, green: 0.365, blue: 0.424), Color(red: 0.239, green: 0.863, blue: 0.518), Color(red: 0.337, green: 0.659, blue: 1.0), Color(red: 0.690, green: 0.486, blue: 1.0)]
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let i = left ? 0 : 1, yaw = st.viewYaw[i], pit = st.viewPitch[i], dist = st.viewDist[i]
                let eye = SIMD3(cos(pit) * cos(yaw), cos(pit) * sin(yaw), sin(pit)) * dist
                let F = simd_normalize(-eye), R = simd_normalize(simd_cross(F, SIMD3(0, 0, 1))), U = simd_cross(R, F)
                let tanF = tan(22.5 * Double.pi / 180), asp = Double(size.width / max(1, size.height))
                func scr(_ p: SIMD3<Double>) -> CGPoint? {
                    let v = p - eye, z = simd_dot(v, F); guard z > 0.1 else { return nil }
                    return CGPoint(x: (simd_dot(v, R) / (z * tanF * asp) * 0.5 + 0.5) * Double(size.width), y: (0.5 - simd_dot(v, U) / (z * tanF) * 0.5) * Double(size.height))
                }
                let n = left ? 3 : 4, L = 1.75
                for ax in 0..<n {
                    var e = SIMD4<Double>(0, 0, 0, 0); e[ax] = 1
                    var tip: SIMD3<Double>
                    if left { let v = st.M3 * e; tip = SIMD3(v.x, v.y, v.z) * L }
                    else { let v = st.M4 * e, k = st.camW / max(0.4, st.camW - L * v.w); tip = SIMD3(v.x, v.y, v.z) * L * k }
                    guard let a = scr(.zero), let b = scr(tip) else { continue }
                    let col = Self.cols[ax]
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    ctx.stroke(line, with: .color(col.opacity(0.85)), lineWidth: 1.2)
                    let dx = b.x - a.x, dy = b.y - a.y, l = max(1, hypot(dx, dy)), ux = dx / l, uy = dy / l
                    var head = Path(); head.move(to: CGPoint(x: b.x + ux * 9, y: b.y + uy * 9))
                    head.addLine(to: CGPoint(x: b.x - uy * 5, y: b.y + ux * 5)); head.addLine(to: CGPoint(x: b.x + uy * 5, y: b.y - ux * 5)); head.closeSubpath()
                    ctx.fill(head, with: .color(col))
                    let label = Text(Self.names[ax]).font(.custom("KaTeX_Math-Italic", size: 26)).foregroundColor(col)
                    ctx.draw(label, at: CGPoint(x: b.x + ux * 24, y: b.y + uy * 24))
                }
            }
        }
    }
}

#if os(macOS)
/// Mac：試作の窓（超球・次元おりがみ）
enum ProtoWindows {
    static var windows: [String: NSWindow] = [:]
    static func open<V: View>(_ key: String, _ title: String, _ view: V) {
        if let w = windows[key] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: view)
        w.setFrameAutosaveName("S3WalkProto." + key); if !w.setFrameUsingName("S3WalkProto." + key) { w.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in windows[key] = nil }
        windows[key] = w; w.makeKeyAndOrderFront(nil)
    }
}
#endif
