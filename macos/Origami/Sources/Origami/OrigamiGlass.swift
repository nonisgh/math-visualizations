// 光で描く部分（次元おりがみの面・辺・頂点を、画素ごとに光を飛ばして描く）。球面さんぽの TesseractLab.swift から写したもの：
//   質感（Glass.looks）・座標軸の名前と色・形の入れ物（TLUni・TLQuad・TLRod・TLBall）・シェーダー（tlShader）
import SwiftUI
import simd

enum Glass {
    /// 座標軸の名前と色（x・y・z・w）
    static let axisNames = ["x", "y", "z", "w"]
    static let axisCols: [Color] = [Color(red: 1.0, green: 0.365, blue: 0.424), Color(red: 0.239, green: 0.863, blue: 0.518), Color(red: 0.337, green: 0.659, blue: 1.0), Color(red: 0.690, green: 0.486, blue: 1.0)]
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
    var X = SIMD4<Float>(0, 0, 0, 0)     // 宇宙（次元おりがみのネイティブ版）：x 背景に混ぜる量（0 なら使わない。背景の絵は texture(0)）・y 光の波・z 面の光の網目の強さ・w 網目の升の数
    var B0 = SIMD4<Float>(0, 0, 0, 0), B1 = SIMD4<Float>(0, 0, 0, 0)   // 形ぜんぶを囲む箱（最小・最大。B1.w が 1 の時だけ使う）：箱に当たらない画素は面と辺を調べない
    var T0 = SIMD4<Float>(0, 0, 0, 0)     // 升の一覧（buffer 4 面・5 辺）：升の大きさ（画素）・横の升の数・1 升の一覧の長さ・使うなら 1
}
struct TLQuad { var a, b, c, d, n, col: SIMD4<Float>; var m = SIMD4<Float>(0, 0, 0, 0) }   // 4 つの角・法線（w は平面の位置）・色（w はふちの光）・m.x 板の濃さ（0 なら質感の値）
struct TLRod { var a, b, col: SIMD4<Float> }             // 両はし（a.w は太さ）・色（w は明るさ）
struct TLBall { var p, col: SIMD4<Float> }               // 中心（w は半径）・色
struct TLCone { var a, b, col: SIMD4<Float> }            // 座標軸の先の矢印（円すい）：先・底の真ん中（w は底の半径）・色

let tlShader = """
#include <metal_stdlib>
using namespace metal;
struct U { float4 eye, R, U, F; float4x4 M; float4 p, q, cnt, L0, L1, L2, rim, L3, S0, S1, S2, S3, X, B0, B1, T0; };   // S：次元おりがみの光（S0 照り返し・強さ・ざらつきの倍率・グレア、S1 鮮やかさ・映り込み・金属っぽさ・ざらつき、S2 主光・S3 逆光の位置）
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
inline float cr2(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }
// 四角形 a・b・c・d（平面の上の 2D）の中の点 p の位置（u・v は 0〜1。台形にゆがんだ面でも、辺に沿った升になる）
inline float2 invBilinear(float2 p, float2 a, float2 b, float2 c, float2 d) {
    float2 e = b - a, f = d - a, g = a - b + c - d, h = p - a;
    float k2 = cr2(g, f), k1 = cr2(e, f) + cr2(h, g), k0 = cr2(h, e);
    float v;
    if (abs(k2) < 1e-5) v = -k0 / k1;
    else {
        float w = k1 * k1 - 4.0 * k0 * k2; if (w < 0.0) return float2(-1.0);
        w = sqrt(w); v = (-k1 - w) * 0.5 / k2;
        if (v < -0.01 || v > 1.01) v = (-k1 + w) * 0.5 / k2;
    }
    float2 q = e + g * v; float u = abs(q.x) > abs(q.y) ? (h.x - f.x * v) / q.x : (h.y - f.y * v) / q.y;
    return float2(u, v);
}
inline float2 segDist(float3 o, float3 d, float3 a, float3 b) {                // 光る線：光の道と線分のいちばん近い所（距離・t）
    float3 ba = b - a, oa = o - a; float bb = dot(ba, ba), bd = dot(ba, d), od = dot(oa, d), ob = dot(oa, ba);
    float den = bb - bd * bd; float h = den > 1e-6 ? clamp((ob - od * bd) / den, 0.0, 1.0) : 0.0;
    float t = max(0.0, dot(a + ba * h - o, d)); h = clamp(dot(o + d * t - a, ba) / max(bb, 1e-6), 0.0, 1.0);
    float3 q = a + ba * h; t = max(0.0, dot(q - o, d));
    return float2(length(o + d * t - q), t);
}
fragment float4 tlf(O in [[stage_in]], constant U& u [[buffer(0)]], const device Quad* Q [[buffer(1)]], const device Rod* RD [[buffer(2)]], const device Ball* BL [[buffer(3)]], const device ushort* QL [[buffer(4)]], const device ushort* RL [[buffer(5)]], texture2d<float> spt [[texture(0)]]) {
    // 升の一覧：この画素の升にかかる面・辺の番号だけを調べる（一覧の先頭が数）
    bool tiled = u.T0.w > 0.5; int tbase = 0;
    if (tiled) { int tx = int(in.pos.x / u.T0.x), ty = int(in.pos.y / u.T0.x); tbase = (ty * int(u.T0.y) + tx) * (int(u.T0.z) + 1); }
    float2 nn = in.uv * 2.0 - 1.0;
    float3 o = u.eye.xyz, d = normalize(u.F.xyz + u.R.xyz * nn.x * u.p.x * u.p.y + u.U.xyz * nn.y * u.p.x);
    float3 bg = mix(float3(0.010, 0.016, 0.040), float3(0.035, 0.045, 0.10), 0.5 + 0.5 * d.z);
    if (u.L3.y > 0.5) bg = mix(float3(0.020, 0.031, 0.086), float3(0.010, 0.014, 0.040), clamp(length(nn) * 0.7, 0.0, 1.0));   // 次元おりがみの紺（真ん中が少し明るい）
    // 宇宙の背景（星雲と星。別に描いておいた絵）を、組み立て具合などに合わせて混ぜる
    if (u.X.x > 0.001) { constexpr sampler sm(filter::linear, address::clamp_to_edge); bg = mix(bg, spt.sample(sm, float2(in.uv.x, 1.0 - in.uv.y)).rgb, u.X.x); }
    bool add = u.L2.y > 0.5, lines = u.L2.w > 0.5, right = u.q.y > 0.5, slice = u.q.w > 0.5;
    // 形ぜんぶを囲む箱に光の道が当たらなければ、面・辺・玉は調べない（背景だけ）
    bool inBox = true;
    if (u.B1.w > 0.5) {
        float3 iv = 1.0 / d, t0 = (u.B0.xyz - o) * iv, t1 = (u.B1.xyz - o) * iv, tn = min(t0, t1), tf = max(t0, t1);
        inBox = min(min(tf.x, tf.y), tf.z) >= max(max(max(tn.x, tn.y), tn.z), 0.0);
    }
    float s = u.p.z;
    // ---- 1. 不透明：管と玉（いちばん手前） ----
    float tOp = 1e9; float3 opCol = float3(0.0);
    {
        int nr = lines || !inBox ? 0 : int(u.cnt.x), nb = inBox ? int(u.cnt.y) : 0;
        for (int i = 0; i < nr; i++) {
            float t = capsule(o, d, RD[i].a.xyz, RD[i].b.xyz, max(RD[i].a.w, 0.0));   // a.w が負＝三角形で描く時の印（つなぎ目）。太さは 0
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
    int nq = !inBox ? 0 : tiled ? int(QL[tbase]) : int(u.q.x);
    for (int ii = 0; ii < nq; ii++) {
        int i = tiled ? int(QL[tbase + 1 + ii]) : ii;
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
            // 宇宙：面に光の網目（超球の窓の球殻の網目と同じ雰囲気）。升は面の辺に沿って、斜めから見るところほど濃く
            if (u.X.z > 0.001 && !add) {
                float3 ex = normalize(C4[1] - C4[0]), ey = cross(Q[i].n.xyz, ex);
                float2 a2 = float2(0.0), b2 = float2(dot(C4[1] - C4[0], ex), dot(C4[1] - C4[0], ey)), c2 = float2(dot(C4[2] - C4[0], ex), dot(C4[2] - C4[0], ey)), d2 = float2(dot(C4[3] - C4[0], ex), dot(C4[3] - C4[0], ey)), p2 = float2(dot(P - C4[0], ex), dot(P - C4[0], ey));
                float2 uv = invBilinear(p2, a2, b2, c2, d2);
                if (all(uv >= -0.01) && all(uv <= 1.01)) {
                    float N = u.X.w, side = max(length(b2), length(d2)) / N;                 // 升の 1 辺（だいたい）
                    float wd = max(u.cnt.z * tq * 0.8, 0.004) / max(side, 1e-4);           // 線の太さ（升に対して。1 画素ほど）
                    float2 gq = abs(fract(uv * N + 0.5) - 0.5);
                    float ln = 1.0 - smoothstep(wd * 0.5, wd * 1.6, min(gq.x, gq.y));
                    float glow = exp(-min(gq.x, gq.y) * min(gq.x, gq.y) / (wd * wd * 9.0)) * 0.25;
                    float slant = 0.45 + 0.9 * (1.0 - abs(dot(Q[i].n.xyz, d)));
                    acc += T * mix(Q[i].col.rgb * 1.5, float3(0.85, 0.92, 1.0), 0.4) * (ln + glow) * slant * u.X.z * 0.55;
                }
            }
        }
        else break;
        if (add) acc += g.rgb * g.a * 1.4; else { acc += T * g.a * g.rgb; T *= 1.0 - g.a; }
    }
    if (tOp < 1e9) acc += (add ? 1.0 : T) * opCol; else acc += (add ? 1.0 : T) * bg;
    // ---- 光る線（辺をネオンの線で。管の代わり） ----
    if (lines) {
        int nr = !inBox ? 0 : tiled ? int(RL[tbase]) : int(u.cnt.x); float3 glow = float3(0.0);
        for (int ii = 0; ii < nr; ii++) {
            int i = tiled ? int(RL[tbase + 1 + ii]) : ii;
            float2 h = segDist(o, d, RD[i].a.xyz, RD[i].b.xyz);
            float r = max(RD[i].a.w, h.y * u.cnt.z * 0.75 * max(1.0, RD[i].b.w));   // 細い線は画面で 1.5 画素ほどより細くしない（cnt.z：1 画素の角度。b.w：その何倍の太さか＝強調の辺）
            float pw = max(h.y * u.cnt.z, 1e-6);                         // その奥行きでの 1 画素の幅
            float core = clamp((r - h.x) / pw + 0.5, 0.0, 1.0) / 1.4, halo = exp(-h.x * h.x / (r * r * 9.0)) * u.cnt.w;   // ふちを 1 画素ぶんなめらかに（動いた時に、ギザギザがちらつかない）。太く見える分だけ明るさを下げる
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
