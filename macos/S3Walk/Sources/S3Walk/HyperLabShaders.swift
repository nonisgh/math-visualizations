// 超球の窓の Metal：頂点と定数の形（シェーダーの V・U・HR と同じ並び）とシェーダー
import SwiftUI
import MetalKit
import CoreVideo

/// 描く頂点：位置・法線・色（w は透明度）
struct HLVert { var p: SIMD4<Float>; var n: SIMD4<Float>; var c: SIMD4<Float> }
/// 描く時の定数：key・rim は照り返しライトの向き（カメラについて回る）、camR・camU はカメラの右・上（グレアの帯）、g は（光沢・グレア・光を当てる・未使用）
/// 右の殻の毎コマの定数（シェーダーの HR）
struct HLRight { var m4 = matrix_identity_float4x4; var q = SIMD4<Float>(1, 1, 3.8, 1.55); var r = SIMD4<Float>(1.35, 48, 0, 0); var d = SIMD4<Float>(0.6, 0, 0, 0); var e = SIMD4<Float>(0, 0, 0, 0); var s = SIMD4<Float>(0, 0, 0, 0); var t = SIMD4<Float>(0, 0, 0, 0); var f = SIMD4<Float>(0, 0, 0, 0)
    var a0 = SIMD4<Float>(0, 0, 0, 0), a1 = SIMD4<Float>(0, 0, 0, 0), a2 = SIMD4<Float>(0, 0, 0, 0), a3 = SIMD4<Float>(0, 0, 0, 0), n = SIMD4<Float>(0, 0, 0, 0), v = SIMD4<Float>(0, 0, 0, 0), ey = SIMD4<Float>(0, 0, 1, 0), fd = SIMD4<Float>(0, 0, 0, 0), ms = SIMD4<Float>(1, 0, 0, 0), cz = SIMD4<Float>(0, 0, 0, 0) }   // a0〜a3：予定の道の矢印の明かり（S³ の点。強さは t.w）   // f：進む向き（S³ の接する向き。ヘッドライト）   // s：自分のいる所（S³ の点）、t.x：その近くを濃くする強さ（下の HR と同じ）
/// 名前の札の頂点（位置・文字の絵の座標）
struct HLLabelVert { var p: SIMD4<Float>; var uv: SIMD4<Float> }
struct HLCometVert { var p: SIMD4<Float>; var q: SIMD4<Float>; var c = SIMD4<Float>(1, 1, 1, 1) }
/// 左の輪 1 本（シェーダーの RI）
struct HLRing { var a: SIMD4<Float>; var c: SIMD4<Float> }
struct HLUni {
    var mvp = matrix_identity_float4x4; var model = matrix_identity_float4x4
    var eye = SIMD4<Float>(0, 0, 5, 1), key = SIMD4<Float>(0, 0, 1, 0), rim = SIMD4<Float>(0, 0, -1, 0)
    var camR = SIMD4<Float>(1, 0, 0, 0), camU = SIMD4<Float>(0, 1, 0, 0), g = SIMD4<Float>(1, 1, 1, 0)
    var cut = SIMD4<Float>(0, 0, 0, 0)                                // 断面カット：（0 なし・1 画面に固定・2 物体に固定・3 平面、中心の角、開きの半分）
    var cutN = SIMD4<Float>(0, 0, 1, 0)                               // 平面で切る：平面の向き（xyz）と位置（w）。向きの側（手前）を消す
    var halo = SIMD4<Float>(0, 0, 0, 0)                               // 地図のカーソルのまわりを薄くする（画素の位置 xy・半径 z・強さ w）
    var hv = SIMD4<Float>(0, 0, 0, 0)                                 // ヘビーモードの殻：x 入り切り・y 斜めの濃さ（h.t.z）・z ふち（h.r.z）を画素ごとに。w：ダイブ画面の地平線の陰影の強さ
    var sa = SIMD4<Float>(0, 0, 0, 0), sb = SIMD4<Float>(0, 0, 0, 0), sd = SIMD4<Float>(0, 0, 0, 0)   // 赤星・紫星までの視線を開ける（画素の位置 xy・半径 z・強さ w）、sd：カメラから星までの距離
    var hb = SIMD4<Float>(0, 0, 0, 0)                                 // 殻の半分だけ描く：xyz 殻の中心、w 0 全部・1 奥の半分だけ・2 手前の半分だけ（切り口がこちらを向いている時の重ね順）
}

let hlShader = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 p; float4 n; float4 c; };
struct U { float4x4 mvp; float4x4 model; float4 eye; float4 key; float4 rim; float4 camR; float4 camU; float4 g; float4 cut; float4 cutN; float4 halo; float4 hv; float4 sa; float4 sb; float4 sd; float4 hb; };
// 地図のカーソルのまわり（u.halo：画素の位置 xy・半径 z・強さ w）：殻と網目だけをやわらかく薄くする（黒く塗らないので、奥の星や空間は見える）
// 赤星・紫星までの視線を開ける：星のまわりの画面で、星より手前の殻と網目を薄くする（星の奥はそのまま）
inline float sightK(float2 px, float3 wp, constant U& u) {
    float k = 1.0, d = distance(wp, u.eye.xyz);
    if (u.sd.z > 0.0) k *= smoothstep(u.sd.z * 0.15, u.sd.z, d);        // カメラが通り抜ける殻は、手前で溶かす（通る瞬間に画面全体の色が飛ばない）
    if (u.sa.w > 0.0 && d < u.sd.x) k *= 1.0 - u.sa.w * (1.0 - smoothstep(u.sa.z * 0.35, u.sa.z, distance(px, u.sa.xy)));
    if (u.sb.w > 0.0 && d < u.sd.y) k *= 1.0 - u.sb.w * (1.0 - smoothstep(u.sb.z * 0.35, u.sb.z, distance(px, u.sb.xy)));
    return k;
}
// ポリゴンカット：超球の上の点（物体の 4D の座標）を押した時の向き・遠近で写して、押した時のくさびの中か（画素ごとに切るので、どの向きでもふちがまっすぐ）
// 殻の半分だけ描く（u.hb）：中心から見てカメラの側（手前）か、その反対（奥）か（線用。面は法線で本当の輪郭で分ける halfCutN）
inline bool halfCut(float3 wp, constant U& u) {
    if (u.hb.w < 0.5) return false;
    bool front = dot(wp - u.hb.xyz, u.eye.xyz - wp) > 0.0;
    return u.hb.w < 1.5 ? front : !front;
}
inline bool halfCutN(float3 wp, float3 n, constant U& u) {
    if (u.hb.w < 0.5) return false;
    float3 out = wp - u.hb.xyz; if (dot(n, n) < 1e-12) n = out;
    float sg = dot(n, out) >= 0.0 ? 1.0 : -1.0;                       // 法線を外向きにそろえる（4D で回した殻でも、網目の向きは殻ごとに一定）
    bool front = sg * dot(n, u.eye.xyz - wp) > 0.0;
    return u.hb.w < 1.5 ? front : !front;
}
inline float haloK(float2 px, constant U& u) {
    if (u.halo.w <= 0.0) return 1.0;
    return 1.0 - u.halo.w * (1.0 - smoothstep(u.halo.z * 0.45, u.halo.z, distance(px, u.halo.xy)));
}
struct O { float4 pos [[position]]; float3 n; float3 wp; float4 c; float ph; float hole [[flat]]; };   // ph：殻の経度（物体に固定の断面カット）、hole：このポリゴンを抜く
vertex O hlv(uint vid [[vertex_id]], constant V* vs [[buffer(0)]], constant U& u [[buffer(1)]]) {
    V v = vs[vid]; O o; o.hole = 0.0; float4 w = u.model * float4(v.p.xyz, 1.0);
    o.pos = u.mvp * w; o.wp = w.xyz; o.n = (u.model * float4(v.n.xyz, 0.0)).xyz; o.c = v.c; o.ph = 0.0; return o;
}
float4 lightHL(float3 nIn, float3 wp, float4 c, float roughAdd, constant U& u);
// 左の輪（細い管）：1 本の型（cos u, sin u, cos v, sin v）を、輪ごとの半径 ρ・高さ h・管の太さで GPU が組み立てる（Z-W を動かしても CPU で作り直さない）
struct RI { float4 a; float4 c; };                            // a：ρ・h・管の太さ、c：色
vertex O ringv(uint vid [[vertex_id]], uint iid [[instance_id]], const device float4* m [[buffer(0)]], constant U& u [[buffer(1)]], const device RI* ri [[buffer(2)]]) {
    float4 q = m[vid]; RI r = ri[iid];
    float3 n = float3(q.z * q.x, q.z * q.y, q.w), p = float3(r.a.x * q.x, r.a.x * q.y, r.a.y) + n * r.a.z;
    if (r.a.w > 1.5) { p = p.xzy; n = n.xzy; } else if (r.a.w > 0.5) { p = p.zxy; n = n.zxy; }   // 4 方向・軸の色：y・x の軸のまわりの輪
    O o; o.hole = 0.0; float4 w = u.model * float4(p, 1.0); o.pos = u.mvp * w; o.wp = w.xyz; o.n = (u.model * float4(n, 0.0)).xyz; o.c = r.c; o.ph = 0.0; return o;
}
// 右の殻（GPU で 4D の回転・遠近）：元の点（層ごとに緯度 × 経度の 4D の点）は 1 度だけ送り、回す行列だけを毎コマ渡す。
//   法線はとなりの点を同じように写して求める。4D の裏側（4D の視点から見て奥の半分）は暗く・くすませる（ウェブ版の「裏側を暗く」）
struct HR { float4x4 m4; float4 q; float4 r; float4 d; float4 e; float4 s; float4 t; float4 f; float4 a0; float4 a1; float4 a2; float4 a3; float4 n; float4 v; float4 ey; float4 fd; float4 ms; float4 cz; };   // v：地図の殻の立体感（x 強さ・yzw 光の向き）、ey：xyz は地図ではカメラの向き・ダイブではカメラの場所、w は升の大きさ。fd：遠くの線と殻を消す（x 強さ・y 始まり・z 終わりの距離）   // a0〜a3：矢印の明かり   // f：進む向き（ヘッドライト）   // s：自分のいる所（S³ の点）、t.x：その近くの殻・網目を濃くする強さ（selfK）
// 自分のいる所の近さ（0〜1）：S³ の上の角度で 0.15 以内は 1、0.6 で 0 へ（殻が自分のそばを通り過ぎる時に浮かぶ）
// ヘッドライト（h.t.y）：自分のいる所から S³ の上で遠いほど暗く（0.35 で 1、1.6 で 0.4 倍）。ダイブの景色の時だけ
inline float headK(float4 b, constant HR& h) {
    if (h.t.y <= 0.0) return 1.0;
    float4 p = b / h.r.x; float cs = clamp(dot(p, h.s), -1.0, 1.0), a = acos(cs);
    // 夜道のヘッドライト：まわりはぼんやり、進む向きの前の方は遠くまで照らす（光のすじ）。横と後ろは暗く
    float4 t = p - h.s * cs; float tl = length(t), ahead = tl > 1e-5 ? dot(t / tl, h.f) : 1.0;
    float around = 1.0 - smoothstep(0.3, 1.1, a);
    float beam = smoothstep(0.55, 0.92, ahead) * (1.0 - smoothstep(0.9, 2.4, a));
    return mix(1.0, 0.42 + 0.58 * max(around, beam), h.t.y);
}
// 矢印の明かり（h.t.w）：予定の道の矢印のそば（S³ の上で 0.16 以内）の殻・網目をほんのり明るく（矢印が道を照らす）
inline float arrowK(float4 b, constant HR& h) {
    if (h.t.w <= 0.0) return 0.0; float4 p = b / h.r.x; float k = 0.0;
    float4 a[4] = { h.a0, h.a1, h.a2, h.a3 };
    for (int i = 0; i < 4; i++) { if (dot(a[i], a[i]) < 0.5) continue; float g = acos(clamp(dot(p, a[i]), -1.0, 1.0)); k = max(k, 1.0 - smoothstep(0.03, 0.16, g)); }
    return k * h.t.w;
}
inline float selfK(float4 b, constant HR& h) { if (h.t.x <= 0.0) return 0.0; float a = acos(clamp(dot(b / h.r.x, h.s), -1.0, 1.0)); return h.t.x * (1.0 - smoothstep(0.15, 0.6, a)); }   // e：4D の遠近（x かすみ・y ぼかし の強さ）    // q：色の倍率・透明度・camW・SCALE、r：R・網目の細かさ M、d.x：遠近の下限（ふだん 0.6、ダイブで近づく時は小さく）
// 4D の奥行き：見る人の 4 次元の視線（w′）に沿って、手前（＋R）0 〜 奥（−R）1。物体の w 軸ではなく、回したあとの w′（見る向き）で測る
inline float dep4(float vw, constant HR& h) { return clamp((h.r.x - vw) / (2.0 * h.r.x), 0.0, 1.0); }
// 赤玉・紫玉の間を透かす（h.e.w）：軸（h.d.w。0 x・1 y・2 z・3 w）の両端のまわりだけ残して、間の殻を透明に
inline float ballK(float4 b, constant HR& h) { if (h.e.w <= 0.0) return 1.0; return mix(1.0, max(0.07, smoothstep(0.80, 0.96, abs(b[int(h.d.w)]) / h.r.x) * (1.0 + 0.9 * h.e.w)), h.e.w); }   // 間の殻も消しきらず、うっすら残す（表と裏が入れかわる所が見える）
// 赤と紫が重なる所（h.fd.y）：いちばん内側の殻の面は重なって平らな桃色の円盤になるので、面だけ透明に（線の立体は残す。中が見える）
inline float coreK(float4 b, constant HR& h) { return h.fd.x > 0.0 || h.fd.y <= 0.0 ? 1.0 : 1.0 - h.fd.y * 0.94 * smoothstep(0.78, 0.92, abs(b.w) / h.r.x); }
// 赤玉・紫玉のまわりの殻：遠くても消さない（暗くすると、黒い穴に見える）
inline float poleKeep(float4 b, constant HR& h) { return smoothstep(0.62, 0.86, abs(b.w) / h.r.x); }
inline float3 hproj(float4 b, constant HR& h) { float4 v = h.m4 * (b * (1.0 - h.ms.w)); return v.xyz * (h.q.z / max(h.d.x, h.q.z - v.w) * h.q.w); }   // ms.w：超球の内側の殻（半径を 1 − ms.w 倍）
// 内核の演出（h.cz：x 強さ 0〜1・y 時刻・z 脈の速さ（回／秒）・w ゆらぎの大きさ）：R が小さい殻ほど、焼けた鉄の色・かげろうのようにゆらぐ網目・脈打つ明るさ
inline float chaosN(float4 b, constant HR& h) { float t = h.cz.y; return sin(dot(b.xyz, float3(7.1, 5.3, 6.7)) * 2.6 + t * 5.5) * sin(dot(b.yzw, float3(4.3, 6.1, 5.2)) * 2.2 - t * 3.7); }
inline float3 hprojC(float4 b, constant HR& h) { float3 P = hproj(b, h); return h.cz.w > 0.0 ? P * (1.0 + h.cz.w * chaosN(b, h)) : P; }
inline float3 heatCol(float t) {                                       // 0 暗い赤 → だいだい → 1 黄色（地球のマントル → 外核 → 内核）
    float3 a = float3(0.59, 0.08, 0.04), b = float3(0.9, 0.27, 0.08), c = float3(1.0, 0.59, 0.16), d = float3(1.0, 0.84, 0.47);
    float s = clamp(t, 0.0, 1.0) * 3.0; return s < 1.0 ? mix(a, b, s) : s < 2.0 ? mix(b, c, s - 1.0) : mix(c, d, s - 2.0);
}
inline float3 chaosCol(float3 col, constant HR& h) {                    // 明るさはそのまま色だけ熱く（まぶしくして網目が見えなくならないように）、明るさを脈打たせる
    if (h.cz.x <= 0.0) return col;
    float k = h.cz.x, L = dot(col, float3(0.299, 0.587, 0.114));
    float3 hc = heatCol(min(1.0, k * 1.15)); hc *= L / max(1e-3, dot(hc, float3(0.299, 0.587, 0.114)));
    float pulse = 0.5 + 0.5 * sin(h.cz.y * 6.2832 * h.cz.z);
    return mix(col, min(hc, float3(1.0)), min(1.0, k * 1.4)) * (1.0 + 0.35 * k * pulse);
}
// 自分のまわりの穴（h.n.w。xyz はカメラの向き、h.fd.w はカメラの距離）：ポインタのまわりの画面の円の中に、4 つの角が全部収まる升だけを、奥行きの全部にわたって抜く
inline float holeRad(float3 P, constant HR& h) { float al = dot(P, h.n.xyz); return length(P - h.n.xyz * al) * h.fd.w / max(0.1, h.fd.w - al) / (h.r.x * h.q.w); }
inline bool cellIn(const device float4* base, uint o0, uint ci, uint cj, uint S, uint M1, constant HR& h) {
    float lim = 0.42 * h.n.w;
    return holeRad(hproj(base[o0 + ci * M1 + cj], h), h) < lim && holeRad(hproj(base[o0 + (ci + S) * M1 + cj], h), h) < lim
        && holeRad(hproj(base[o0 + ci * M1 + cj + S], h), h) < lim && holeRad(hproj(base[o0 + (ci + S) * M1 + cj + S], h), h) < lim;
}
vertex O hrv(uint vid [[vertex_id]], const device float4* base [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]], const device float4* lc [[buffer(3)]]) {
    uint M = uint(h.r.y), M1 = M + 1, per = M1 * M1, L = vid / per, k = vid % per, i = k / M1, j = k % M1, o0 = L * per;
    float4 b = base[vid], v = h.m4 * b; float3 P = hprojC(b, h);
    float3 a = hproj(base[o0 + min(M, i + 1) * M1 + j], h) - hproj(base[o0 + (i > 0 ? i - 1 : 0) * M1 + j], h);
    float3 c = hproj(base[o0 + i * M1 + (j + 1) % M1], h) - hproj(base[o0 + i * M1 + (j + M - 1) % M], h);
    float3 n = cross(a, c); if (length(n) < 1e-7) n = P;
    float R = h.r.x, face = (v.w - R * R / h.q.z) / R, bk = 0.6 * (1.0 - smoothstep(-0.1, 0.05, face));
    float3 col = chaosCol(lc[L].rgb * h.q.x, h); float gray = dot(col, float3(0.299, 0.587, 0.114));
    O o; o.pos = u.mvp * float4(P, 1.0); o.wp = P; o.n = n; float hz = h.e.x * pow(dep4(v.w, h), 1.3);                          // 4D のかすみ：奥ほど背景の色へ溶けて淡く
    col = mix(col, float3(0.012, 0.027, 0.07), hz * 0.85);
    o.c = float4((col + (gray - col) * (0.4 * bk)) * (1.0 - 0.5 * bk), h.q.y * lc[L].a * (1.0 - 0.55 * hz)); o.ph = float(j) / float(M) * 2.0 * M_PI_F;
    // 殻（g.z ＝ 2）：光は頂点ごとに計算して面の上でなめらかにつなぐ（21 枚の半透明の殻を全部の画素で計算すると、とても重い。殻はなめらかな球なので頂点で十分）
    // 4 方向レインボー（h.r.z）：殻が何枚も重なるので、表面をざらっと（てかりがぼんやり広がる。殻ごとの小さなてかりが点々と並んで白い筋にならない）
    if (u.g.z > 1.5) o.c = lightHL(n, P, o.c, h.r.z > 0.0 ? 0.6 : 0.0, u);
    // 自分の近くの殻：少し濃く・明るく（離れるほど元に）
    { float sk = selfK(b, h), ak = arrowK(b, h); o.c.a *= 1.0 + 1.6 * sk + 0.9 * ak; o.c.rgb *= (1.0 + 0.35 * sk) * max(headK(b, h), 0.7 + 0.3 * ak) + float3(1.0, 0.78, 0.35) * 0.12 * ak; }
    // 斜めから見た殻は濃く（薄い膜を斜めに通る光は、膜の中を長く通る：1 −（1 − a）^(1／cos)）。ふつうのレインボー（h.t.z）。
    //   4 方向・4 軸は下の「殻のふち」で同じ見え方を作っているので、ここでは足さない
    if (h.t.z > 0.0 && u.hv.x < 0.5) { float cv = max(0.25, abs(dot(normalize(n), normalize(u.eye.xyz - P)))); float a0 = clamp(o.c.a, 0.0, 0.95); o.c.a = mix(o.c.a, 1.0 - pow(1.0 - a0, 1.0 / cv), h.t.z); }
    // 殻のふち（h.r.z。4 方向レインボー）：横から見ている所ほど少し濃く・明るく（ガラスの球のように形と奥行きが浮かぶ）
    if (h.r.z > 0.0 && u.hv.x < 0.5) { float rim = 1.0 - abs(dot(normalize(n), normalize(u.eye.xyz - P))); float rk = pow(rim, 3.0) * h.r.z; o.c.a *= 1.0 + 1.8 * rk; o.c.rgb *= 1.0 + 0.5 * rk; }
    // 地図の殻の立体感：外向きの面を上からの明かりで照らして（上の面は明るく、下の面は暗く）、地図の手前ほど明るく・濃く、奥ほど暗く・淡く
    if (h.v.x > 0.0) {
        float3 C = hproj(0.5 * (base[o0] + base[o0 + M * M1]), h), N = normalize(n); if (dot(N, P - C) < 0.0) N = -N;
        float sky = 0.5 + 0.5 * dot(N, h.v.yzw), near = clamp(dot(P, h.ey.xyz) / (h.r.x * h.q.w), -1.0, 1.0);
        o.c.rgb *= mix(1.0, (0.4 + 0.9 * sky) * (0.85 + 0.3 * near), h.v.x); o.c.a *= mix(1.0, 0.9 + 0.3 * near, h.v.x);
    }
    // ダイブ画面の遠くの殻：線の役目を色に渡して、暗く青く溶かす（空間の広さが見える）
    if (h.fd.x > 0.0) { float far = smoothstep(h.fd.y * 1.5, h.fd.z * 1.4, distance(P, h.ey.xyz)) * (1.0 - poleKeep(b, h)); o.c.rgb = mix(o.c.rgb * (1.0 + 0.25 * h.fd.x * (1.0 - far)), float3(0.012, 0.03, 0.09), 0.45 * h.fd.x * far); }
    // 面の 1 組目の頂点（k）が、その升の値を決める（flat）。線で囲まれた升ごとに抜くかどうか決める
    o.hole = 0.0;
    if (h.n.w > 0.0 && holeRad(P, h) < 0.42 * h.n.w + 0.35) { uint S = uint(h.ey.w), ci = min(i - i % S, M - S), cj = min(j - j % S, M - S); if (cellIn(base, o0, ci, cj, S, M1, h)) o.hole = 1.0; }
    // W 消失地図の演出：h.ms.x は殻ごとの濃さ（玉ねぎ）、h.ms.y は升をばらばらに抜く割合（ポリゴン）、h.ms.z は抜き方の種
    if (h.ms.y > 0.0) { uint S = max(1u, M / 10), ci = i - i % S, cj = j - j % S; if (fract(sin(dot(float2(ci, cj) + h.ms.z, float2(12.9898, 78.233))) * 43758.5453) < h.ms.y) o.hole = 1.0; }
    o.c.a *= h.ms.x;
    o.c.a *= ballK(b, h) * coreK(b, h);                                                           // 反射・斜めの濃さ・ふちも一緒に透かす（どれも不透明さを足すので、いちばんあとで。ふちだけ残らない）
    return o;
}
// ---- 太さのある線（ワイヤー）：1 画素の線（.line）は Retina では髪の毛ほど細く、色が薄く見えるので、線分ごとに画面の上で帯に広げる ----
//   ふちは 1 画素ぶんやわらかく。k：（画面の幅・高さ（画素）・線の太さの半分（画素）・未使用）
//   blA・blB：4D のぼかし（端ごと。太さを最大 6 倍、ふちのやわらかさを太さぶんまで）
struct WO { float4 pos [[position]]; float4 c; float3 wp; float ph; float side; float hw; float sf; };
inline WO wideLine(float4 ca, float4 cb, float4 colA, float4 colB, float3 wa, float3 wb, float pha, float phb, uint vid, float4 k, float blA, float blB) {
    float2 ha = k.xy * 0.5;
    WO o;
    if (ca.w <= 1e-4 || cb.w <= 1e-4) { o.pos = float4(0, 0, -2, 1); o.c = 0; o.wp = 0; o.ph = 0; o.side = 0; o.hw = 1; o.sf = 0; return o; }
    float2 sa = ca.xy / ca.w * ha, sb = cb.xy / cb.w * ha, d = sb - sa; float L = length(d); d = L > 1e-4 ? d / L : float2(1, 0);
    float2 n = float2(-d.y, d.x);
    int corner = vid == 0 ? 0 : vid == 1 ? 1 : vid == 2 ? 2 : vid == 3 ? 2 : vid == 4 ? 1 : 3;
    bool atB = corner >= 2; float side = (corner == 1 || corner == 3) ? 1.0 : -1.0;
    float bl = atB ? blB : blA, w0 = k.z * (1.0 + 5.0 * bl), sf = (k.z + 1.5) * 3.0 * bl;
    float hw = w0 + 0.5 + sf * 0.5;
    float4 p = atB ? cb : ca;
    float2 off = n * side * hw + d * (atB ? 0.5 : -0.5);
    p.xy += off / ha * p.w;
    o.pos = p; o.c = atB ? colB : colA; o.wp = atB ? wb : wa; o.ph = atB ? phb : pha; o.side = side * hw; o.hw = w0; o.sf = sf;
    return o;
}
// 右の網目：線分 iid の両はしの番号は idx[2 iid]・idx[2 iid ＋ 1]（殻と同じ写し方・色）
inline void hshade(uint vid, const device float4* base, constant HR& h, const device float4* lc, thread float3& P, thread float4& c, thread float& ph, thread float& bl) {
    uint M = uint(h.r.y), M1 = M + 1, per = M1 * M1, L = vid / per, kk = vid % per, j = kk % M1;
    float4 b = base[vid], v = h.m4 * b; P = hprojC(b, h);
    float R = h.r.x, face = (v.w - R * R / h.q.z) / R, bk = 0.6 * (1.0 - smoothstep(-0.1, 0.05, face));
    float3 col = lc[L].rgb * h.q.x;
    // 4 方向レインボー：光の線にするので、暗い色（紫・青）は明るさをそろえて光らせる（色合いはそのまま）
    if (h.r.z > 0.0) { float mx = max(max(col.r, col.g), col.b); col = col / max(mx, 0.05) * mix(0.75, mx, 0.4); }
    col = chaosCol(col, h);
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    float dp = dep4(v.w, h), hz = h.e.x * pow(dp, 1.3);
    col = mix(col, float3(0.012, 0.027, 0.07), hz * 0.85);
    bl = h.e.y * pow(dp, 1.25);                                         // 4D のぼかし：奥ほど太く・やわらかく・淡く（ぼけた線の見え方）
    float la = h.r.z > 0.0 ? min(lc[L].a, h.r.z) : lc[L].a;              // 網目の濃さの上限（4 方向レインボー）
    float sk = selfK(b, h), ak = arrowK(b, h); la *= 1.0 + 1.3 * sk + 0.8 * ak; col = col * (1.0 + 0.4 * sk) * max(headK(b, h), 0.7 + 0.3 * ak) + float3(1.0, 0.78, 0.35) * 0.18 * ak;   // 自分の近くの網目：少し強く（離れるほど元に）。遠くはヘッドライトで暗く
    c = float4((col + (gray - col) * (h.d.y * bk)) * (1.0 - h.d.z * bk), h.q.y * la * (1.0 - 0.5 * hz) / (1.0 + 3.5 * bl) * ballK(base[vid], h)); ph = float(j) / float(M) * 2.0 * M_PI_F;   // 網目の裏側：灰色へ寄せる割合 d.y・暗くする割合 d.z
    if (h.v.x > 0.0) { float near = clamp(dot(P, h.ey.xyz) / (h.r.x * h.q.w), -1.0, 1.0); c.rgb *= mix(1.0, 0.8 + 0.3 * near, h.v.x); c.a *= mix(1.0, 0.7 + 0.45 * near, h.v.x); }   // 地図の網目も、手前ほど明るく・濃く
    c.a *= h.ms.x;
    if (h.fd.x > 0.0) c.a *= 1.0 - h.fd.x * smoothstep(h.fd.y, h.fd.z, distance(P, h.ey.xyz)) * (1.0 - poleKeep(base[vid], h));   // ダイブ画面の網目は近くだけ残す（遠くの線が重なると奥行きがわからなくなる）
}
vertex WO hrwv(uint vid [[vertex_id]], uint iid [[instance_id]], const device float4* base [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]],
               const device float4* lc [[buffer(3)]], const device uint* idx [[buffer(4)]], constant float4& k [[buffer(5)]]) {
    float3 Pa, Pb; float4 cA, cB; float pa, pb, ba, bb;
    uint ia = idx[iid * 2], ib = idx[iid * 2 + 1];
    hshade(ia, base, h, lc, Pa, cA, pa, ba); hshade(ib, base, h, lc, Pb, cB, pb, bb);
    if (h.n.w > 0.0 && holeRad(Pa, h) < 0.42 * h.n.w + 0.35) {           // 自分のまわりの穴：両側の升が抜ける線だけを抜く（穴のふちの線は残る）
        uint M = uint(h.r.y), M1 = M + 1, per = M1 * M1, S = uint(h.ey.w), o0 = (ia / per) * per, a = ia % per, c = ib % per, i0 = a / M1, j0 = a % M1, i1 = c / M1, j1 = c % M1;
        uint ci = min(min(i0, i1) - min(i0, i1) % S, M - S), cj = min(min(j0, j1) - min(j0, j1) % S, M - S);
        bool gone;
        if (i0 == i1) gone = (i0 == 0 || cellIn(base, o0, i0 - S, cj, S, M1, h)) && (i0 >= M || cellIn(base, o0, i0, cj, S, M1, h));   // 緯線
        else if (j0 == j1) gone = cellIn(base, o0, ci, j0 == 0 ? M - S : j0 - S, S, M1, h) && cellIn(base, o0, ci, min(j0, M - S), S, M1, h);   // 経線
        else gone = cellIn(base, o0, ci, cj, S, M1, h);                 // 升の斜めの線
        if (gone) return wideLine(float4(0), float4(0), cA, cB, Pa, Pb, pa, pb, vid, k, ba, bb);
    }
    float4 ca = u.mvp * float4(Pa, 1), cb = u.mvp * float4(Pb, 1);
    // 線の自動整理（h.fd.w）：線で囲まれた升が画面の上で小さい所は、線が密で奥行きがつぶれるので薄くする
    if (h.fd.x > 0.0 && h.fd.w > 0.5 && ca.w > 1e-4 && cb.w > 1e-4) {
        float cell = length((ca.xy / ca.w - cb.xy / cb.w) * 0.5) * h.ey.w, dense = mix(0.2 + 0.8 * smoothstep(0.03, 0.14, cell), 1.0, poleKeep(base[ia], h));
        cA.a *= dense; cB.a *= dense;
    }
    return wideLine(ca, cb, cA, cB, Pa, Pb, pa, pb, vid, k, ba, bb);
}
// 左など：線分 iid ＝ 頂点 2 iid と 2 iid ＋ 1（HLVert の並び）
vertex WO segwv(uint vid [[vertex_id]], uint iid [[instance_id]], constant V* vs [[buffer(0)]], constant U& u [[buffer(1)]], constant float4& k [[buffer(5)]]) {
    V a = vs[iid * 2], b = vs[iid * 2 + 1];
    float4 wa = u.model * float4(a.p.xyz, 1), wb = u.model * float4(b.p.xyz, 1);
    return wideLine(u.mvp * wa, u.mvp * wb, a.c, b.c, wa.xyz, wb.xyz, 0, 0, vid, k, 0, 0);
}
fragment float4 wlf(WO in [[stage_in]], constant U& u [[buffer(1)]]) {
    if (halfCut(in.wp, u)) discard_fragment();
    if (u.cut.x > 3.5) { if (dot(in.wp, u.cutN.xyz) > 0.0 && dot(in.wp, u.cut.yzw) > 0.0) discard_fragment(); }   // 2 枚の面の両方の側（地球の断面図のくさび）
    else if (u.cut.x > 2.5) { if (dot(in.wp, u.cutN.xyz) > u.cutN.w) discard_fragment(); }
    else if (u.cut.x > 0.5) {
        float a = (u.cut.x < 1.5 ? atan2(dot(in.wp, u.camR.xyz), dot(in.wp, cross(u.camR.xyz, u.camU.xyz))) : in.ph) - u.cut.y;
        a -= 2.0 * M_PI_F * floor((a + M_PI_F) / (2.0 * M_PI_F));
        if (abs(a) < u.cut.z) discard_fragment();
    }
    float a = clamp((in.hw + 0.5 + in.sf * 0.5 - abs(in.side)) / (1.0 + in.sf), 0.0, 1.0);   // ふちは 1 画素（ぼかしの時は、そのぶん広く）やわらかく
    if (in.sf > 0.01) a = a * a * (3.0 - 2.0 * a);
    if (a <= 0.0) discard_fragment();
    return float4(in.c.rgb, in.c.a * a * haloK(in.pos.xy, u) * sightK(in.pos.xy, in.wp, u));
}
// 名前の札：文字の絵（色・ふちどり済み、アルファを掛けてある）を、いつも画面に向く板に貼る。奥行きは見ない（いつも見える）
struct LVert { float4 p; float4 uv; };
struct LO { float4 pos [[position]]; float2 uv; };
vertex LO lbv(uint vid [[vertex_id]], constant LVert* vs [[buffer(0)]], constant U& u [[buffer(1)]]) { LO o; o.pos = u.mvp * float4(vs[vid].p.xyz, 1.0); o.uv = vs[vid].uv.xy; return o; }
fragment float4 lbf(LO in [[stage_in]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear, address::clamp_to_edge); return t.sample(s, in.uv); }
// 光の彗星：頭（コマ）と尾を、画面に向く板に光の式で描く（足し合わせ）。q.xy：板の上の位置（頭は −1〜1 の丸、尾は x が頭からの割合 0〜1・y が横 −1〜1）、q.z：0 頭・1 尾、q.w：濃さ
//   q.z：4 通った極・目印（色の光と十字のきらめき）・5 まだの極・目印（色の光の輪）。c：その色
struct CV { float4 p; float4 q; float4 c; };
struct CMO { float4 pos [[position]]; float4 q; float4 c; };
vertex CMO cmv(uint vid [[vertex_id]], constant CV* vs [[buffer(0)]], constant U& u [[buffer(1)]]) { CMO o; o.pos = u.mvp * float4(vs[vid].p.xyz, 1.0); o.q = vs[vid].q; o.c = vs[vid].c; return o; }
// 尾の帯の角を丸く：横のふちは 0 へなめらかに消し、頭の側の端は丸いふた（カプセルの端のように）。s：頭からの割合、v：横（−1〜1）
inline float tailWin(float s, float v) {
    float cap = max(0.0, 1.0 - s / 0.07), av = abs(v);
    return 1.0 - smoothstep(0.5, 1.0, length(float2(av, cap * av)));   // 真ん中（v ＝ 0）は頭までつながる。角だけ丸く
}
fragment float4 cmf(CMO in [[stage_in]], constant float4& tm [[buffer(2)]]) {
    float sp = clamp(tm.y, 0.0, 1.0), t = tm.x * (1.0 + 2.5 * sp), glow = 1.0 + 0.7 * sp;   // 速いほど、すじが速く流れて明るく（派手に）
    float3 col;
    if (in.q.z > 16.5) {
        // 立体の矢印の面（kind 17）：q.x は面の明るさ（光の当たり方）
        return float4(in.c.rgb * in.q.x, in.q.w);
    }
    if (in.q.z > 15.5) {
        // 小さな金平糖（kind 16）：まるい玉のふちに 11 個のまるいでこぼこ。でこぼこの先がきらっと光り、まん中ほど明るい。
        //   左上に小さなつや（粒が回ると、つやも回る）。まわりにうっすらにじむ光
        float2 p = in.q.xy; float r = length(p), th = atan2(p.y, p.x);
        float bump = pow(0.5 + 0.5 * cos(th * 11.0), 1.5), R = 0.78 + 0.2 * bump, fw = max(fwidth(r), 1e-4);
        float core = 1.0 - smoothstep(R - 0.05 - fw, R + fw, r), sh = sqrt(max(0.0, 1.0 - (r / R) * (r / R)));
        float tip = core * smoothstep(0.6, 0.95, r / R) * bump;
        float halo = exp(-max(r - R, 0.0) * max(r - R, 0.0) * 8.0) * (1.0 - core);
        float2 g = p - float2(-0.25, 0.25); float hot = exp(-dot(g, g) * 8.0);
        return float4(in.c.rgb * (core * (0.3 + 0.55 * sh) + tip * 0.4 + halo * 0.3) + float3(1.0) * hot * core * 0.35, in.q.w);
    }
    if (in.q.z > 14.5) {
        // 光のビーズ（kind 15）：q.xy はビーズの半径を 1 とした位置（楕円は頂点の側で引きのばす）。
        //   玉はふちがはっきりして（ふちに少し明るい輪）、まん中ほど明るい（光る玉）。まわりにうっすらにじむ光
        float2 p = in.q.xy; float r = length(p), fw = max(fwidth(r), 1e-4);
        float core = 1.0 - smoothstep(0.95 - fw, 1.0 + fw, r), rim = core * smoothstep(0.7, 0.95, r);
        float sh = sqrt(max(0.0, 1.0 - r * r));
        float halo = exp(-max(r - 0.9, 0.0) * max(r - 0.9, 0.0) * 5.0) * (1.0 - core);
        float hot = exp(-r * r * 6.0);
        return float4(in.c.rgb * (core * (0.3 + 0.6 * sh) + rim * 0.45 + halo * 0.3) + float3(1.0) * hot * core * 0.35, in.q.w);
    }
    if (in.q.z > 11.5) {
        // 「»」の 1 つを初心者マークのように前後に引きのばした矢印（kind 12）：太い腕の「＞」、先はとがり（約 60°）、腕のはしは上下に水平に切る。角はほんの少しだけ丸い。
        //   6 つの角の多角形（先・外の上・内の上・内の切りこみ・内の下・外の下）の本当の距離を測り、0.08 だけふくらませて角を丸める（やさしく、腕は細め）
        //   （多角形はそのぶん小さめに作る。内の切りこみの角はとがったまま）
        float2 p = in.q.xy;
        float2 v[6] = { float2(0.52, 0.0), float2(-0.04, 0.33), float2(-0.24, 0.33), float2(0.32, 0.0), float2(-0.24, -0.33), float2(-0.04, -0.33) };
        float dd = dot(p - v[0], p - v[0]), sg = 1.0;
        for (int i = 0, j = 5; i < 6; j = i, i++) {
            float2 e = v[j] - v[i], w = p - v[i], b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
            dd = min(dd, dot(b, b));
            bool c0 = p.y >= v[i].y, c1 = p.y < v[j].y, c2 = e.x * w.y > e.y * w.x;
            if ((c0 && c1 && c2) || (!c0 && !c1 && !c2)) sg = -sg;
        }
        float d = sg * sqrt(dd) - 0.08;
        float fw = max(fwidth(d), 1e-4), core = 1.0 - smoothstep(-fw, fw, d);
        float halo = exp(-max(d, 0.0) * max(d, 0.0) / 0.006) * (1.0 - core);
        //   陰影：上の腕は 1、下の腕は c.w の明るさ（折り紙のように少し折った腕に光が当たる）。境目はなめらかに。うしろほど少し暗く
        float shade = mix(in.c.w, 1.0, smoothstep(-0.04, 0.04, p.y)) * (0.82 + 0.18 * smoothstep(-0.3, 0.5, p.x));
        return float4((mix(in.c.rgb, float3(1.0), 0.25) * core * 1.05 + in.c.rgb * halo * 0.8) * shade, in.q.w);
    }
    if (in.q.z > 10.5) {
        // 矢印のポリゴンのまわりの光（kind 11）：帯の真ん中ほど明るく、ふちで 0 へ（q.y：帯の横 −1〜1）
        float x = in.q.x, dx = max(0.0, -x) + max(0.0, x - in.c.w), d = length(float2(dx, in.q.y));   // 丸いカプセルの中の距離
        float g = exp(-d * d * 3.5) * (1.0 - smoothstep(0.7, 1.0, d));
        return float4(in.c.rgb * g * 0.7, in.q.w);
    }
    if (in.q.z > 9.5) {
        // 矢印のポリゴンの芯（kind 10）：くっきりした光の帯（ふちは 1 画素ぶんやわらかく）
        float x = in.q.x, dx = max(0.0, -x) + max(0.0, x - in.c.w), d = length(float2(dx, in.q.y));   // 丸いカプセル（はしも先も丸く）
        float core = 1.0 - smoothstep(0.45, 1.0, d), w = fwidth(d);
        core = max(core, 1.0 - smoothstep(0.45, 0.45 + 1.5 * w, d)) * (1.0 - smoothstep(1.0 - w, 1.0, d));   // ふちは画素の大きさでやわらかく（ギザギザしない）
        return float4(mix(in.c.rgb, float3(1.0), 0.45) * core * 1.8, in.q.w);
    }
    if (in.q.z > 8.5) {
        // レンズフレアの横の筋（kind 9）：細く横に伸びる光（真ん中ほど明るい）
        float2 p = in.q.xy; float g = exp(-p.y * p.y * 4.0) * pow(max(0.0, 1.0 - abs(p.x)), 2.5);
        return float4(in.c.rgb * g, in.q.w);
    }
    if (in.q.z > 7.5) {
        // レンズフレアの光の輪（kind 8）：やわらかい円盤にうすい縁（レンズの中で反射した光のゴースト）
        float r = length(in.q.xy);
        float disc = exp(-r * r * 3.0) * 0.6 + exp(-pow((r - 0.82) / 0.08, 2.0)) * 0.5;
        return float4(in.c.rgb * disc * (1.0 - smoothstep(0.92, 1.0, r)), in.q.w);
    }
    if (in.q.z > 6.5) {
        // 予定の道の光の矢印（kind 7）：進む向き（板の x）を指す「＞」の形の光。白い芯と、まわりの色の光（c）。q.w：濃さ
        float2 p = in.q.xy; float r = length(p);
        float2 tip = float2(0.42, 0.0);
        float2 a0 = float2(-0.3, 0.5) - tip, a1 = float2(-0.3, -0.5) - tip, pa = p - tip;
        float d0 = length(pa - a0 * clamp(dot(pa, a0) / dot(a0, a0), 0.0, 1.0)), d1 = length(pa - a1 * clamp(dot(pa, a1) / dot(a1, a1), 0.0, 1.0));
        float d = min(d0, d1);
        float core = exp(-d * d / 0.006), halo = exp(-d * d / 0.04);
        col = (mix(in.c.rgb, float3(1.0), 0.5) * core * 2.0 + in.c.rgb * halo * 0.8) * (1.0 - smoothstep(0.8, 1.0, r));
        return float4(col, in.q.w);
    }
    if (in.q.z > 5.5) {
        // 当たった瞬間（kind 6、q.w が光の強さ 1 → 0）：星の色の混じった光が弾けて、輪が広がる・十字の長い光
        float2 p = in.q.xy; float r = length(p), fl = in.q.w;
        float3 c = in.c.rgb, cw = mix(c, float3(1.0), 0.55);
        float ringR = 0.22 + 0.62 * (1.0 - fl), ring = exp(-pow((r - ringR) / 0.05, 2.0)) * fl;
        float burst = exp(-r * r / 0.035) * fl * fl * 2.2;
        float sp = (exp(-abs(p.x) * 30.0) * exp(-abs(p.y) * 1.6) + exp(-abs(p.y) * 30.0) * exp(-abs(p.x) * 1.6)) * fl * 1.3;
        col = (cw * burst + c * ring * 1.3 + cw * sp) * (1.0 - smoothstep(0.85, 1.0, r));
        return float4(col, 1.0);
    }
    if (in.q.z > 3.5) {
        float2 p = in.q.xy; float r = length(p), fade = 1.0 - smoothstep(0.7, 1.0, r);
        float3 c = in.c.rgb, cw = mix(c, float3(1.0), 0.55);
        float ph = in.c.r * 7.0 + in.c.g * 13.0 + in.c.b * 3.0, tw = 0.82 + 0.18 * sin(t * 2.6 + ph) * sin(t * 1.3 + ph * 0.7);   // またたき（色ごとにずれる）
        if (in.q.z < 4.5) {
            // 通った：白い芯・色の光・ぼんやりした外の光・十字のきらめき（細い斜めの十字も少し）
            float core = exp(-r * r / 0.004), halo = exp(-r * r / 0.03), outer = exp(-r / 0.2);
            float2 d = float2(p.x + p.y, p.x - p.y) * 0.7071;
            float sp = exp(-abs(p.x) * 38.0) * exp(-abs(p.y) * 3.2) + exp(-abs(p.y) * 38.0) * exp(-abs(p.x) * 3.2);
            float sd = exp(-abs(d.x) * 45.0) * exp(-abs(d.y) * 6.0) + exp(-abs(d.y) * 45.0) * exp(-abs(d.x) * 6.0);
            col = (float3(1.0) * core * 1.8 + c * (halo * 1.1 + outer * 0.35) + cw * (sp * 0.75 + sd * 0.25) * tw) * fade;   // 白く光る星に、極の色がほんのり
        } else {
            // まだ：色の光の輪（中はうすく）
            float ring = exp(-pow((r - 0.3) / 0.055, 2.0)), inner = exp(-r * r / 0.03);
            col = (c * ring * 1.0 + c * inner * 0.22 + cw * exp(-r * r / 0.002) * 0.35) * fade * (0.9 + 0.1 * tw);
        }
        return float4(col, in.q.w);
    }
    if (in.q.z < 0.5) {
        // 頭：白く飛んだ核・青白い内側の光・青緑のコマ（ぼんやり広がる）
        float r = length(in.q.xy), fade = 1.0 - smoothstep(0.55, 0.98, r);
        // カーブの時のゆがみ（c.xy：曲がる向き・強さ）：核は曲がる側へ少し出て、コマは反対（外側・後ろ）へ引きずられて伸びる
        float2 wv = in.c.xy; float wm = min(1.0, length(wv));
        if (wm > 1e-3) {
            float2 u = wv / length(wv), p = in.q.xy; float a = dot(p, u) - 0.05 * wm, b = dot(p, float2(-u.y, u.x));
            a = a < 0.0 ? a / (1.0 + 1.1 * wm) : a * (1.0 + 0.4 * wm); b *= 1.0 + 0.3 * wm;
            r = length(float2(a, b));
        }
        // 巨大彗星（c.z：大きさの割合 0〜1）：芯と内側の光を太く、コマを明るく（引きの絵でも、ひと目でわかる光の玉に）
        float gb = in.c.z;
        //   白い芯は出さず、真ん中を少し暗くした光の玉にする（足し合わせで真っ白に飛ぶと、中のふつうの彗星が見えない）
        float core = exp(-r * r / 0.0035) * (1.0 - gb), inner = exp(-r * r / (0.03 * (1.0 + 2.0 * gb))) * (1.0 - 0.55 * gb), coma = exp(-r / (0.22 * (1.0 + 0.3 * gb))) * (1.0 + 1.2 * gb);
        float hollow = 1.0 - gb * 0.8 * (1.0 - smoothstep(0.03, 0.28, r));
        float tw = 0.93 + (0.07 + 0.12 * sp) * sin(t * 2.3) * sin(t * 1.7 + 1.0);      // ゆらめく（速いほど強く）
        col = (float3(1.0) * core * 2.2 * glow + float3(0.85, 0.95, 1.0) * inner * 0.9 * glow + float3(0.45, 0.95, 0.85) * coma * (0.45 + 0.35 * sp)) * fade * tw * hollow;
    } else if (in.q.z > 2.5) {
        // イオンの尾（寄った時）：細めの青い光。まっすぐ長く、縦のすじ（磁力線に沿うガス）が入って、ゆっくり流れる
        float s = clamp(in.q.x, 0.0, 1.0), v = in.q.y;
        float g = exp(-v * v * 5.0), fil = 0.62 + 0.38 * (0.5 + 0.5 * sin(v * 23.0 + s * 4.0 - t * 0.6)) * (0.6 + 0.4 * sin(v * 9.0 - s * 7.0 + t * 0.4));
        float fall = pow(1.0 - s, 1.1) * smoothstep(0.0, 0.06, s);
        col = mix(float3(0.55, 0.78, 1.0), float3(0.25, 0.45, 1.0), s) * g * fil * fall * 0.9 * glow * tailWin(s, v);
    } else if (in.q.z > 1.5) {
        // ちりの尾（寄った時）：頭の所は白く、先へ行くほど扇のように広がって淡く（形はハレ・ボップ彗星の写真のように）
        float s = clamp(in.q.x, 0.0, 1.0), v = in.q.y;
        float g = exp(-v * v * 2.2) + 0.25 * exp(-(v - 0.6) * (v - 0.6) * 10.0);        // 片方のふちが少し明るい
        //   明るさは白く飛ばない所まで（足し合わせで 1 を超えると、白く飛んだ所のふちが尾を横切るまっすぐな線＝四角い切れ目に見える）
        float fall = pow(1.0 - s, 2.2) * 0.42 + exp(-s * 5.0) * 0.2;
        col = mix(float3(1.0, 0.97, 0.9), float3(0.55, 0.75, 1.0), smoothstep(0.0, 0.7, s)) * g * fall * glow * tailWin(s, v);   // 色はふつうの尾と同じ（白 → 青白）
    } else {
        // 尾：ふちはぼかし（ガウス）、真ん中に細い光のすじ（イオンの尾）、流れるすじ模様。先へ行くほど淡く・青く
        float s = clamp(in.q.x, 0.0, 1.0), v = in.q.y;
        float g = exp(-v * v * 4.0), core = exp(-v * v * 36.0), ion = exp(-v * v * 12.0);
        float stri = 0.78 + 0.22 * sin(v * 17.0 + s * 11.0 - t * 1.7) * sin(v * 7.0 - s * 5.0 + t * 0.9);
        float fall = pow(1.0 - s, 1.5);
        float3 dust = mix(float3(1.0, 0.97, 0.9), float3(0.55, 0.75, 1.0), s);
        col = (dust * g * 0.5 + float3(0.9, 0.97, 1.0) * core * 0.85 + float3(0.45, 0.7, 1.0) * ion * 0.35) * fall * stri * tailWin(s, v);
    }
    return float4(col, in.q.w);
}
struct QO { float4 pos [[position]]; float2 uv; };   // 画面いっぱいの三角形（背景・縮める）
// 宇宙モードの星（球面さんぽと同じ S³ の星）：右は超球の上を殻と同じ 4D の回転・遠近で、左は 4 つ目を落とした影 (x, y, w)（球の中に詰まる）。
//   カメラに向いた小さな板に、光の点（芯とにじみ）を足し合わせて描く。明るい星ほど大きく。右の超球の奥（4D の裏）の星は少し暗く
struct Star { float4 p; float4 c; };
struct SO { float4 pos [[position]]; float4 c; float2 q; float ph; float sp; };   // ph：またたきの位相、sp：ぼかしの量（ズーム時の遠い星）
vertex SO stv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Star* st [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]], constant float4& k [[buffer(3)]], constant float4& tz [[buffer(4)]]) {
    // tz：時刻・またたきの強さ・遠近の強さ（ズームで寄るほど。遠い星を透明に・ぼかす）・引きの絵の遠近の強さ（超球の向こう側ほど）
    Star s = st[iid * uint(k.z)];                                       // k：大きさ・左右（0 右・1 左）・間引き・明るさ
    float R = h.r.x; float3 P; float vis = 1.0, sblur = 0.0;
    if (k.y < 0.5) {
        float4 v = h.m4 * (s.p * R); P = v.xyz * (h.q.z / max(h.d.x, h.q.z - v.w) * h.q.w);
        vis = 0.45 + 0.55 * smoothstep(-0.1, 0.05, (v.w - R * R / h.q.z) / R);
        float dp = dep4(v.w, h), bl = h.e.y * pow(dp, 1.5);
        vis *= (1.0 - 0.6 * h.e.x * pow(dp, 1.3)) / (1.0 + 3.0 * bl); sblur = bl;
    } else if (k.y > 1.5) {                                             // 4D で切る：超平面（法線 h.r.w の軸）＝ h.r.z のすぐそばの星だけ（切り口の 3D の中に、遠近なしで。切った軸の所に w を置く）
        float4 v = h.m4 * (s.p * R); int ax = int(h.r.w); float vk = v[ax];
        float3 q = v.xyz; if (ax < 3) q[ax] = v.w; P = q * h.q.w;
        float dw = (vk - h.r.z) / 0.07; vis = exp(-dw * dw);
    } else { P = (u.model * float4(float3(s.p.x, s.p.y, s.p.w) * R, 1.0)).xyz; }
    float2 q = float2((vid == 1 || vid == 2 || vid == 4) ? 1.0 : -1.0, (vid == 2 || vid == 4 || vid == 5) ? 1.0 : -1.0);
    float b = s.c.w;
    // ズーム時の遠近（tz.z ＝ 寄った割合）：自分から遠い星ほど透明に・大きくぼかす（近くの星だけくっきり。画面がうるさくならない）
    // 天の川の帯（さんぽと同じ y・z の円のまわり：S³ の x・w が小さい所）の星：遠くても消さない（星が密に集まって、天の川に見える）
    float band = exp(-(s.p.x * s.p.x + s.p.w * s.p.w) / 0.04);
    float ed = length(u.eye.xyz - P), far = tz.z * smoothstep(0.25, 2.2, ed) * (1.0 - 0.85 * band);
    // 引きの絵：超球の真ん中より奥（向こう側）の星ほど（右の画面だけ）
    if (k.y < 0.5) { float rel = (ed - length(u.eye.xyz)) / max(0.1, h.r.x * h.q.w); far = max(far, tz.w * smoothstep(-0.5, 0.9, rel)); }
    vis *= 1.0 - 0.9 * far;
    // 遠近の星（h.e.z。4 方向レインボー）：遠い星ほど淡く（近い星がくっきり浮かんで、空間の奥行きがわかる）
    float pz = h.e.z;
    vis *= mix(1.0, clamp(pow(2.0 / max(ed, 0.05), 0.6), 0.2, 1.0), pz);
    // 寄った時：帯から外れた星は少し暗く（まぶしくない）、帯の星はそのまま（天の川が浮かぶ）
    if (k.y < 0.5 && tz.z > 0.0) { vis *= 1.0 - 0.35 * tz.z * (1.0 - band); }
    // 寄った時の帯の星は、少し大きくやわらかい光の粒に（星が密な所ほど重なって、天の川が白っぽく浮かぶ。まばらな所は暗いまま）
    float bz = (k.y < 0.5) ? band * tz.z : 0.0;
    //   遠近の星は、画面の上の大きさも距離で変える（近いほど大きく・遠いほど小さく）。遠い星を大きくぼかさない（牡丹雪のようにならない）
    float pf = mix(1.0, clamp(pow(1.6 / max(ed, 0.05), 0.65), 0.3, 1.8), pz);
    float r = k.x * (0.55 + 0.45 * sqrt(b)) * clamp(ed / 7.5, 0.02, 1.0) * (1.0 + 1.6 * sblur) * mix(1.0 + 1.8 * far, 1.0, pz) * (1.0 + 2.2 * bz) * pf;   // 4D のぼかし：奥の星は大きくぼんやり。カメラに近い星も、画面の上の大きさは同じくらいに（ダイブ）
    P += (u.camR.xyz * q.x + u.camU.xyz * q.y) * r;
    SO o; o.pos = u.mvp * float4(P, 1.0); o.c = float4(s.c.rgb, min(2.2, 0.45 + 0.7 * b) * vis * k.w); o.q = q;
    o.ph = fract(float(iid) * 0.6180339) * 6.2832; o.sp = max(far * (1.0 - pz), 0.7 * bz); return o;
}
fragment float4 stf(SO in [[stage_in]], constant float4& tz [[buffer(4)]]) {
    float d2 = dot(in.q, in.q); if (d2 > 1.0) discard_fragment();
    // ぼかし（遠い星）：芯をやわらかく広げる
    float dd = d2, soft = 1.0 + 4.0 * in.sp;
    float a = in.c.a * (exp(-dd * 9.0 / soft) + 0.18 * exp(-dd * 2.5)) / (1.0 + 1.5 * in.sp);   // 元の光り方（ぼかしの時だけ芯をやわらかく）
    // またたき：星ごとに速さと位相をずらして、明るさがゆらぐ
    float w = 1.0 + tz.y * (0.55 * sin(tz.x * (1.7 + 2.3 * fract(in.ph * 0.37)) + in.ph) + 0.25 * sin(tz.x * 5.3 + in.ph * 2.1));
    return float4(in.c.rgb, max(0.0, a * w));                          // 足し合わせ（色 × a を足す）
}
// 宇宙の背景：深い紺に、うすい星雲（紫・青・桃）と、小さな遠い星
inline float hh(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
inline float vn(float2 p) { float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hh(i), hh(i + float2(1, 0)), f.x), mix(hh(i + float2(0, 1)), hh(i + float2(1, 1)), f.x), f.y); }
inline float fbm(float2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + float2(1.7, 9.2); a *= 0.5; } return s; }
vertex QO bgv(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); QO o; o.pos = float4(p * 2.0 - 1.0, 1.0, 1.0); o.uv = p; return o; }
fragment float4 bgf(QO in [[stage_in]], constant float4& k [[buffer(0)]]) {
    float2 uv = in.uv * float2(k.x, 1.0);                               // k.x：横÷縦
    float3 c = mix(float3(0.006, 0.010, 0.030), float3(0.020, 0.028, 0.075), smoothstep(1.3, 0.0, length(in.uv - 0.5) * 1.6));
    float n1 = fbm(uv * 2.2 + float2(3.1, 1.3)), n2 = fbm(uv * 3.7 + float2(8.4, 2.2));
    c += float3(0.30, 0.14, 0.42) * pow(smoothstep(0.45, 0.95, n1), 2.0) * 0.55 + float3(0.10, 0.22, 0.45) * pow(smoothstep(0.5, 1.0, n2), 2.0) * 0.5;
    float2 g = floor(in.uv * float2(k.x, 1.0) * 260.0); float r = hh(g);
    if (r > 0.9965) { float2 f = fract(in.uv * float2(k.x, 1.0) * 260.0) - 0.5; c += float3(0.8, 0.85, 1.0) * (r - 0.9965) * 250.0 * exp(-dot(f, f) * 30.0); }
    return float4(c, 1.0);
}
// 作っておいた背景の絵を、そのまま貼る
fragment float4 cpf(QO in [[stage_in]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear, address::clamp_to_edge); return t.sample(s, in.uv); }
// 縮める（左の輪：2 倍の大きさで描いた絵を、4 点を混ぜて縮める）
vertex QO dsv(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); QO o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(p.x, 1.0 - p.y); return o; }
// ダイブの鏡：外から見た超球と、中から見た景色は左右が逆（天球儀と夜空のように）。鏡は回転では作れないので、
//   描いた絵の鏡を、画面の真ん中の縦の線から左右へなめらかに広げる（真ん中＝自分のいる所は、元の絵と鏡の絵がちょうど重なる）。k.x：広がった幅（0〜0.5 で画面の端）
fragment float4 mirf(QO in [[stage_in]], texture2d<float> t [[texture(0)]], constant float4& k [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float d = abs(in.uv.x - 0.5), m = 1.0 - smoothstep(k.x - 0.08, k.x + 0.08, d);
    float4 col = mix(t.sample(s, in.uv), t.sample(s, float2(1.0 - in.uv.x, in.uv.y)), m);
    // ダイブの景色の仕上げ（k.y）：黒をより黒く・暗い所を沈めてコントラストを上げ、画面の端ほど暗く（周辺減光。真ん中の彗星へ目が行く）
    if (k.y > 0.0) {
        float sy = k.y; float2 p = (in.uv - 0.5) * float2(k.z, 1.0); float r = length(p) / length(float2(k.z, 1.0) * 0.5);
        float3 c = max(col.rgb - 0.01 * sy, 0.0) / (1.0 - 0.01 * sy);
        c = pow(c, float3(1.0 + 0.1 * sy));
        col.rgb = c * (1.0 - 0.35 * sy * smoothstep(0.55, 1.1, r));
    }
    col.rgb *= k.w;                                                     // 明るさ（シースルーを暗く見せる）
    return col;
}
fragment float4 dsf(QO in [[stage_in]], texture2d<float> t [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 px = 1.0 / float2(t.get_width(), t.get_height()) * 0.0;   // 縦横ちょうど 2 倍：出す画素の真ん中は 2×2 の画素のかど＝ 1 回の線形の読みで 2×2 の平均（広げると線がにじんで、色が薄く見える）
    return 0.25 * (t.sample(s, in.uv + float2(-px.x, -px.y)) + t.sample(s, in.uv + float2(px.x, -px.y)) + t.sample(s, in.uv + float2(-px.x, px.y)) + t.sample(s, in.uv + float2(px.x, px.y)));
}
// 鏡のような照り返し（three.js の MeshStandardMaterial と同じ GGX）
inline float3 ggxSpec(float3 n, float3 v, float3 l, float3 F0, float rough) {
    float al = max(rough, 0.0525); al = al * al; float a2 = al * al;
    float3 h = normalize(l + v); float nl = saturate(dot(n, l)), nv = saturate(dot(n, v)), nh = saturate(dot(n, h)), lh = saturate(dot(l, h));
    float3 F = F0 + (1.0 - F0) * pow(1.0 - lh, 5.0);
    float gv = nl * sqrt(a2 + (1.0 - a2) * nv * nv), gl = nv * sqrt(a2 + (1.0 - a2) * nl * nl), G = 0.5 / max(gv + gl, 1e-6);
    float dd = nh * nh * (a2 - 1.0) + 1.0, D = a2 / (M_PI_F * dd * dd);
    return F * (G * D);
}
// 映り込むスタジオ：紺の空（上ほど明るい）と、照り返しライトの大きなやわらかい光 2 つ（次元おりがみのグレアと同じ）
inline float3 studio(float3 r, constant U& u) {
    float3 c = mix(float3(0.020, 0.030, 0.070), float3(0.10, 0.13, 0.22), 0.5 + 0.5 * r.y);
    c += float3(1.0, 0.98, 1.04) * 1.7 * pow(smoothstep(0.30, 0.97, dot(r, u.key.xyz)), 1.6);
    c += float3(0.80, 0.90, 1.0) * 0.8 * pow(smoothstep(0.50, 0.98, dot(r, u.rim.xyz)), 1.6);
    return c;
}
// 明るさ：ウェブ版（three.js r128 の MeshStandardMaterial）と同じ式。環境光（白 0.95）＋平行光 2 つ（白 1.2 を右上前 (5, 12, 8) から、水色 0.8 を左下奥 (−8, −5, −6) から）。
//   左の輪（g.w＝1）：金属 0.35・粗さ 0.15・自分の光 0.4。右の殻：金属 0.3・粗さ 0.2・両面。粗さには面の曲がり具合を足す（細い管がチラつかない。three.js と同じ）。
//   左の輪は、球の奥の半分を暗く・くすませる（ウェブ版の「裏側を暗く」0.6。どちらが手前かが分かる）。
//   光沢（g.x）はこの上に足す：照り返しライト（主光は左上前・逆光は右うしろ、カメラについて回る）のキラッとした照り返しと、スタジオの映り込み（斜めほど強く）。
//   照り返した所は不透明に（半透明の殻でもキラッと見える）。グレア（g.y）：色を深く・ふちほど白く光る・画面を斜めに横切るやわらかい帯
// 光の計算（画素ごと＝左の輪・座標軸、頂点ごと＝右の殻）。roughAdd：面の曲がり具合（画素ごとの時だけ）
float4 lightHL(float3 nIn, float3 wp, float4 c, float roughAdd, constant U& u) {
    float3 n = normalize(nIn), v = normalize(u.eye.xyz - wp);
    if (dot(n, v) < 0.0) n = -n;
    bool tube = u.g.w > 0.5;
    float3 C = c.rgb; float a = c.a, gl = u.g.x;
    float metal = tube ? 0.35 : 0.3;
    float rough = min(max(tube ? 0.15 : 0.2, 0.0525) + roughAdd, 1.0);
    float3 diff = C * (1.0 - metal), F0 = mix(float3(0.04), C, metal);
    const float3 L1 = normalize(float3(5, 12, 8)), L2 = normalize(float3(-8, -5, -6));
    const float3 C1 = float3(1.2), C2 = float3(0.220, 0.741, 0.973) * 0.8;
    float3 dD = diff * 0.95, dS = float3(0.0);
    float nl = saturate(dot(n, L1)); dD += diff * C1 * nl; dS += C1 * nl * M_PI_F * ggxSpec(n, v, L1, F0, rough);
    nl = saturate(dot(n, L2)); dD += diff * C2 * nl; dS += C2 * nl * M_PI_F * ggxSpec(n, v, L2, F0, rough);
    float3 col = dD + dS * (tube ? 1.0 : u.eye.w) + (tube ? C * 0.4 : float3(0.0));   // eye.w：強い照り返しのよけ（殻の固定の光の照り返しも弱める）
    if (gl > 0.0) {
        // 殻は何枚も重なるので、ひかえめに。透明さも変えない（重なって白く曇り、ウェブ版のような織物の線が埋もれないよう）
        gl *= tube ? 1.0 : 0.35; float aK = tube ? 1.0 : 0.0;
        float nv = saturate(dot(n, v));
        float3 lk = u.key.xyz, lr = u.rim.xyz, cr = float3(0.86, 0.92, 1.0) * 0.8;
        float nk = saturate(dot(n, lk)), nr = saturate(dot(n, lr));
        float3 sS = nk * M_PI_F * ggxSpec(n, v, lk, F0, rough) + cr * nr * M_PI_F * ggxSpec(n, v, lr, F0, rough);
        float Fr = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
        float3 e = studio(reflect(-v, n), u) * (0.10 + 0.90 * Fr) * gl;
        col += e; a = clamp(a + max(e.r, max(e.g, e.b)) * 0.35 * aK, 0.0, 1.0);
        float gr = u.g.y;
        if (gr > 0.0) {
            float Y = dot(col, float3(0.299, 0.587, 0.114));
            col = max(float3(0.0), mix(float3(Y), col, 1.0 + 0.4 * gr));
            float gF = pow(1.0 - nv, 3.0);
            float vx = dot(-v, u.camR.xyz), vy = dot(-v, u.camU.xyz);
            float gB = exp(-pow((vx * 0.62 - vy * 0.78 - 0.10) / 0.085, 2.0));
            col += float3(gF * 0.25 + gB * 0.14) * gr * (tube ? 1.0 : 0.4); a = clamp(a + (gF * 0.2 + gB * 0.08) * gr * aK, 0.0, 1.0);
        }
        float sp = max(sS.r, max(sS.g, sS.b));
        col += gl * (sS * 2.0 + float3(sp * 1.6)); a = clamp(a + gl * sp * (tube ? 3.0 : 0.8), 0.0, 1.0);
    }
    if (tube) {                                               // 球の奥の半分の輪を暗く・くすませる（球の中心は原点）
        float face = dot(normalize(wp), v);
        float bk = (1.0 - smoothstep(-0.1, 0.05, face)) * 0.6;
        float Y = dot(col, float3(0.299, 0.587, 0.114));
        col = mix(col, float3(Y), 0.4 * bk) * (1.0 - 0.5 * bk);
    }
    return float4(col, a);
}
fragment float4 hlf(O in [[stage_in]], constant U& u [[buffer(1)]]) {
    if (in.hole > 0.5 || halfCutN(in.wp, in.n, u)) discard_fragment();
    // 断面カット（ウェブ版と同じ）：画面に固定は、画面から見た向き（0 ＝ 手前・右回りに 90° ＝ 右）、物体に固定は殻の経度。くさびの中は描かない
    if (u.cut.x > 3.5) { if (dot(in.wp, u.cutN.xyz) > 0.0 && dot(in.wp, u.cut.yzw) > 0.0) discard_fragment(); }   // 2 枚の面の両方の側（地球の断面図のくさび）
    else if (u.cut.x > 2.5) { if (dot(in.wp, u.cutN.xyz) > u.cutN.w) discard_fragment(); }   // 平面で切る：向きの側（手前）を消す
    else if (u.cut.x > 0.5) {
        float a = (u.cut.x < 1.5 ? atan2(dot(in.wp, u.camR.xyz), dot(in.wp, cross(u.camR.xyz, u.camU.xyz))) : in.ph) - u.cut.y;
        a -= 2.0 * M_PI_F * floor((a + M_PI_F) / (2.0 * M_PI_F));
        if (abs(a) < u.cut.z) discard_fragment();
    }
    if (u.g.z < 0.5 || u.g.z > 1.5) {                                   // 光なし（線・札）か、頂点で光を計算済み（右の殻）
        float4 c0 = in.c;
        if (u.hv.x > 0.5 || u.hv.w > 0.0) {
            float cs = abs(dot(normalize(in.n), normalize(u.eye.xyz - in.wp)));
            if (u.hv.x > 0.5) {                                         // ヘビーモードの殻：色と光はふつうのまま、斜めの濃さとふちだけ画素ごとに（地平線の線がなめらかに）
                if (u.hv.y > 0.0) { float cv = max(0.25, cs), a0 = clamp(c0.a, 0.0, 0.95); c0.a = mix(c0.a, 1.0 - pow(1.0 - a0, 1.0 / cv), u.hv.y); }
                if (u.hv.z > 0.0) { float rk = pow(1.0 - cs, 3.0) * u.hv.z; c0.a *= 1.0 + 1.8 * rk; c0.rgb *= 1.0 + 0.5 * rk; }
            }
            c0.rgb *= 1.0 - u.hv.w * (1.0 - smoothstep(0.0, 0.5, cs));  // ダイブ画面の殻の地平線の陰影：面が視線と平行になる所へ向かって暗く（丸みが見える）
            if (u.hv.w > 0.0) { float edge = 1.0 - smoothstep(0.0, 0.1, cs); c0.rgb += in.c.rgb * 1.2 * edge * u.hv.w; c0.a = min(1.0, c0.a * (1.0 + 2.5 * edge * u.hv.w)); }   // 地平線のいちばん外に細い光のふち（線が減っても球だとわかる）
        }
        return float4(c0.rgb, c0.a * haloK(in.pos.xy, u) * sightK(in.pos.xy, in.wp, u));
    }
    float3 nn = normalize(in.n), dxy = max(abs(dfdx(nn)), abs(dfdy(nn)));   // 粗さに面の曲がり具合を足す（細い管がチラつかない。three.js と同じ）
    return lightHL(in.n, in.wp, in.c, max(max(dxy.x, dxy.y), dxy.z), u);
}
"""
