// 中の景色の光線追跡（ウェブ版 s3walk.html の RAY_FRAG を Metal へ）。起動の時にこの文字列から作る（Xcode が無くても動くように）
//   移したもの：光の道（大円）・目印の玉（markersTop、手前から 4 つ）・球層（shellsAll／shellsBetween、レインボー・ふつう／立体）・
//   赤道の膜・もや（uFog）と透け（uFade）・層を手前から重ねる合成。まだ移していない：軽い線・管（経線・部屋）・絵・空の色の地図・魚眼・ダイソン球
let shaderSource = #"""
#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265;

struct Uni {
    float4 P, R, U, F;                       // 位置と、画面の右・上・前（4 次元の正規直交の組）
    float4 L0;                               // 立体の殻を照らす光の向き：normalize(−0.45R + 0.75U − 0.5F)
    float2 res; float tanF; float maxD;
    float fog, fade, uni, depth;
    float shellOp, shellBack, shellRange, shMin;
    float shellLum, gridSt; int shellN; int shell;
    int shellSolid, shellBare, eq, nm;
    int passes, orient, lite, webTies;      // webTies：確かめ用。ウェブ版と同じく、同じ道のりの層の片方を落とす
    float glow, edr, band, gpad1;           // band：宇宙の時の天の川の明るさ。光る線：glow（0〜1）＝にじみの強さ、edr＝線の芯の明るさの倍率（EDR の画面で 1 より大きく）
    int pic, ghostBack, lens, upad0;         // pic：目印 0 玉・1 絵・2 色の点、ghostBack：遠回りの像を絵の裏から、lens：0 ふつう・1 魚眼・2 360°
    float fovY, picLine, upad1, upad2;       // fovY：縦の視野（ラジアン）、picLine：絵・色の点の時の線の濃さ
    int circ, room, space, tpad1;            // 管：circ＝経線（x・y・z と w の大円）と赤道の輪、room＝120 胞体の部屋の辺。space：背景 0 深海（もや）・1 宇宙
    float tube, pixAng, lineW, solidWire;    // tube：管の太さ（角度）、pixAng：1 画素の角度、lineW：網目の線の太さ（画素。0 でウェブ版と同じ角度の太さ）、solidWire：立体の殻の網目の濃さ（ウェブ版は 0.35）
};
struct Mk { float4 c; float4 col; float4 info; };   // c：中心（S³ の点）、col.xyz：色、col.w：半径（角度）、info.x：絵の表のます目（−1 で絵なし）

struct VOut { float4 pos [[position]]; };
vertex VOut vmain(uint vid [[vertex_id]]) {  // 画面いっぱいの三角形 1 枚
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); return o;
}

// GLSL と同じ mod・smoothstep（Metal の fmod は負の数で GLSL とちがう。smoothstep は端が逆向きでも同じ式で）
inline float gmod(float x, float y) { return x - y * floor(x / y); }
inline float3 gmod3(float3 x, float y) { return x - y * floor(x / y); }
inline float ss(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

inline float3 bgc(float3 d, int sp) {
    if (sp == 1) return mix(float3(0.002, 0.003, 0.008), float3(0.006, 0.005, 0.014), 0.5 + 0.5 * d.y);   // 宇宙：ほとんど黒
    return mix(float3(0.012, 0.02, 0.05), float3(0.05, 0.04, 0.12), 0.5 + 0.5 * d.y);
}
// 空気のもや（散乱光）の色。宇宙の時は、遠くのものが暗闇に溶ける（青みのほんのり残る黒）
inline float3 haze(float3 d, int sp) {
    if (sp == 1) return mix(float3(0.010, 0.013, 0.030), float3(0.016, 0.016, 0.038), 0.5 + 0.5 * d.y);
    return mix(float3(0.16, 0.19, 0.30), float3(0.22, 0.24, 0.36), 0.5 + 0.5 * d.y);
}
// 天の川（宇宙の時）：大円 C（a1・a2 の張る平面）のまわりに集まった、ひとつずつは見分けられない星の淡い光。
//   光の道 p(t) と C との距離は sin²＝f(t)＝1 − (p·a1)² − (p·a2)²。f は cos t・sin t の 2 次の式なので、いちばん近い所 λmin と広がり λmax が 2×2 の固有値で出る
inline float bandGlow(float4 p0, float4 v, float4 a1, float4 a2, float sig) {
    float pa = dot(p0, a1), pb = dot(p0, a2), va = dot(v, a1), vb = dot(v, a2);
    float a = 1.0 - pa * pa - pb * pb, c = 1.0 - va * va - vb * vb, b = -(pa * va + pb * vb);
    float m = 0.5 * (a + c), r = sqrt(max(0.0, 0.25 * (a - c) * (a - c) + b * b));
    float lmin = max(0.0, m - r), lmax = m + r, s2 = sig * sig;
    return exp(-lmin / s2) * sqrt(s2 / (s2 + lmax - lmin));
}
// 線の遠近感：近いほど明るく、遠いほど暗く（距離は宇宙の大きさ込み）
inline float depthMul(float t, constant Uni& u) { float d = t * u.uni; return mix(1.0, min(1.35, 1.6 * exp(-0.35 * d) + 0.12), u.depth); }

// 軽い線の太さの遠近感：近いほど太く、遠いほど細く
inline float depthW(float t, constant Uni& u) { float d = t * u.uni; return mix(1.0, 0.55 + 1.6 * exp(-0.9 * d), u.depth); }
// 網目の線の濃さ（x：線の芯、y：光のにじみ）。da・db：緯線・経線までの角度、lw：線の太さ（殻の上の角度）、fp：1 画素が殻の上で占める角度。
//   lineW > 0：芯の太さを画面で lineW 画素までにする。殻の上で決まった角度の太さのままだと、すぐそばの殻の線が画面いっぱいの太い帯になってぼやけるので。
//   1 画素より細い線は、そのぶん薄く。lineW ＝ 0：ウェブ版の前の見え方（殻の上の角度の太さ、やわらかいふち）
inline float2 lineProfile(float da, float db, float lw, float fp, constant Uni& u) {
    float d = min(da, db);
    if (u.lineW <= 0.0 || fp <= 0.0) {
        float h = 1.0 - ss(lw * 0.5, lw * 3.0, d);
        return float2(max(ss(lw, 0.0, da), ss(lw, 0.0, db)), h * h * h);
    }
    float w = min(0.5 * lw, 0.5 * u.lineW * fp);                    // 芯の半分の太さ
    float cov = min(1.0, 2.0 * w / fp);
    float core = clamp((w - d) / fp + 0.5, 0.0, 1.0) * cov;        // ふちは 1 画素ぶんだけなめらかに
    float h = 1.0 - ss(w, w + 3.0 * max(w, fp), d);
    return float2(core, h * h * h);
}
// 1 画素が、道のり t の所の面の上で占める角度（面の半径 sinR、光が面に当たる角の cos を ci。かすめる所は 4 倍まで）
inline float pixFoot(float t, float ci, float sinR, constant Uni& u) { return abs(sin(t)) * u.pixAng / max(abs(ci), 0.25) / max(sinR, 1e-3); }
// 間隔 st の緯度・経度の線（線の太さも間隔に比例。wm＝遠近の太さ）
inline float2 gridLineS(float lat, float lon, float coslat, float st, float wm, float fp, constant Uni& u) {
    float lw = 0.03 * st / (PI / 6.0) / sqrt(u.uni) * wm;
    float da = abs(fract(lat / st + 0.5) - 0.5) * st, db = abs(fract(lon / st + 0.5) - 0.5) * st * coslat;
    return lineProfile(da, db, lw, fp, u);                          // x：線の芯、y：光のにじみ
}

// 目印の玉の色（当たった点 q・そこでの光の向き vt）。orient＝1：玉の右上に赤い点（像の向きを確かめる印。見る人を向いた絵と同じ貼り方）
//   pic＝1：見る人の方を向いた絵を貼る（ウェブ版と同じ。back＝1 なら遠回りの像を絵の裏から見た形＝左右を鏡に）、pic＝2：平らな色の点
float3 markerShade(float3 base, float cellT, float4 c, float4 q, float4 vt, float back, constant Uni& u, texture2d<float> atlas) {
    float4 n = normalize(q - c * dot(q, c)); float li = 0.3 + 0.7 * max(0.0, -dot(n, vt));
    if (u.pic == 2) return base * (0.75 + 0.25 * li);
    if (u.pic == 1 && cellT >= 0.0) {
        constexpr sampler smp(filter::linear, mip_filter::linear, address::clamp_to_edge);
        float4 Rp = normalize(u.R - c * dot(u.R, c));
        float4 Up = u.U - c * dot(u.U, c); Up = normalize(Up - Rp * dot(Up, Rp));
        float2 xy = float2(dot(n, Rp), dot(n, Up)) * 0.8;          // ふち（|xy| = 1）が絵のます目のふちに来るように
        if (back > 0.5) xy.x = -xy.x;
        float cx = gmod(cellT, 8.0), cy = floor(cellT / 8.0);
        float2 uv = clamp(0.5 + 0.5 * xy, 0.02, 0.98);
        float4 tx = atlas.sample(smp, float2((cx + uv.x) / 8.0, (cy + 1.0 - uv.y) / 8.0));
        return mix(mix(float3(0.97), base, 0.25), tx.rgb, tx.a) * (0.55 + 0.45 * li);
    }
    if (u.orient == 1) {
        float4 Rp = normalize(u.R - c * dot(u.R, c));
        float4 Up = u.U - c * dot(u.U, c); Up = normalize(Up - Rp * dot(Up, Rp));
        float2 xy = float2(dot(n, Rp), dot(n, Up)) * 0.8;
        if (length(xy - float2(0.42, 0.42)) < 0.17) return float3(1.0, 0.12, 0.12) * (0.55 + 0.45 * li);
    }
    float str = 0.85 + 0.15 * sin(12.0 * atan2(dot(n, u.U), dot(n, u.R)));
    return base * li * str;
}
// 重ねる層（目印・赤道の膜・軽い線）：当たる道のり t だけを覚えておき、色は重ねる時にその場で計算する
//   （ウェブ版は 17 の層の色を配列にためるが、Metal ではレジスタが足りなくなって全体が遅くなるので）
struct Layers {
    float mt0, mt1, mt2, mt3; int mi0, mi1, mi2, mi3;   // 目印：手前から 4 つまでの t と、目印の番号
    float te;                                            // 赤道の膜：1 回目に通る t（2 回目は te + π）
    float lt[10];                                        // 軽い線：5 枚の殻 × 2 回
    float k0, dlt;                                       // 軽い線：いちばん内側の殻の番号と、殻の間隔
    float tt; float3 tc; float ta;                       // 管：当たる道のり・色・不透明度（少しずつ進めて探すので、その場で色も決める）
};
// 手前から 4 つまでの当たりを並べて入れる（添字を決まった数にして、レジスタに乗るように）
inline void ins4(float t, int i, thread Layers& L) {
    if (t >= L.mt3) return;
    if (t < L.mt2) { L.mt3 = L.mt2; L.mi3 = L.mi2; } else { L.mt3 = t; L.mi3 = i; return; }
    if (t < L.mt1) { L.mt2 = L.mt1; L.mi2 = L.mi1; } else { L.mt2 = t; L.mi2 = i; return; }
    if (t < L.mt0) { L.mt1 = L.mt0; L.mi1 = L.mi0; } else { L.mt1 = t; L.mi1 = i; return; }
    L.mt0 = t; L.mi0 = i;
}
// 目印の玉：光の道 cos t·p₀ + sin t·v と、玉（中心 c・半径 r：c との内積 ≥ cos r）の交わりを式で。1 周先（t + 2π）も見る
void markersTop(float4 p0, float4 v, thread Layers& L, constant Mk* mk, constant Uni& u) {
    L.mt0 = L.mt1 = L.mt2 = L.mt3 = 1e9; L.mi0 = L.mi1 = L.mi2 = L.mi3 = 0;
    int np = clamp(u.passes, 1, 4);
    for (int i = 0; i < u.nm; i++) {
        float4 c = mk[i].c; float cr = cos(mk[i].col.w);
        float Aa = dot(p0, c), Bb = dot(v, c); float amp = sqrt(Aa * Aa + Bb * Bb);
        if (amp < cr) continue;
        float phi = atan2(Bb, Aa); float dt = acos(clamp(cr / amp, -1.0, 1.0));
        float t = gmod(phi - dt, 2.0 * PI);
        for (int k = 0; k < 2; k++) {
            float tcut = np >= 4 ? L.mt3 : np == 3 ? L.mt2 : np == 2 ? L.mt1 : L.mt0;   // 要る数より奥の当たりは入れない
            if (t > 1e-4 && t < u.maxD && t < tcut) ins4(t, i, L);
            t += 2.0 * PI;
        }
    }
    if (np < 4) L.mt3 = 1e9; if (np < 3) L.mt2 = 1e9; if (np < 2) L.mt1 = 1e9;
}
// ---- 管（経線・赤道の輪・部屋の辺）：光を少しずつ進めて、管にいちばん近づいた所を探す（ウェブ版と同じ）----
inline float circDist(float4 p, int i, int j) { float a = p[i], b = p[j]; return acos(clamp(sqrt(a * a + b * b), 0.0, 1.0)); }
inline float pixW(float t, constant Uni& u) { return min(abs(sin(t)) * u.pixAng * 1.6, 0.3); }
void tubes(float4 p0, float4 v, thread Layers& L, constant Uni& u, constant float4* uN) {
    float tube = u.pic >= 1 ? u.tube * 0.5 : u.tube;                // 絵・色の点のモードでは細く
    float4 p = p0, vv = v, pf = p0, vf = v; float t = 0.0;
    for (int i = 0; i < 160; i++) {
        float d = 1e9; float3 cc = float3(1.0); float li = 1.0;
        if (u.circ == 1) {
            float dx = circDist(p, 0, 3), dy = circDist(p, 1, 3), dz = circDist(p, 2, 3);
            float e1 = circDist(p, 0, 1), e2 = circDist(p, 1, 2), e3 = circDist(p, 2, 0);
            float4 n;
            d = dx; cc = float3(1.0, 0.36, 0.42); n = float4(0.0, p.y, p.z, 0.0);
            if (dy < d) { d = dy; cc = float3(0.24, 0.86, 0.52); n = float4(p.x, 0.0, p.z, 0.0); }
            if (dz < d) { d = dz; cc = float3(0.34, 0.66, 1.0); n = float4(p.x, p.y, 0.0, 0.0); }
            if (e1 < d) { d = e1; cc = float3(0.85, 0.86, 0.95); n = float4(0.0, 0.0, p.z, p.w); }
            if (e2 < d) { d = e2; cc = float3(0.85, 0.86, 0.95); n = float4(p.x, 0.0, 0.0, p.w); }
            if (e3 < d) { d = e3; cc = float3(0.85, 0.86, 0.95); n = float4(0.0, p.y, 0.0, p.w); }
            li = 0.55 + 0.45 * dot(normalize(n + 1e-6), u.U);
        }
        if (u.room == 1) {
            // 120 胞体の基本の部屋の中へ、面で折り返す（光の向きもいっしょに）
            for (int pass = 0; pass < 4; pass++) { bool any = false; for (int f = 0; f < 12; f++) { float s = dot(pf, uN[f]); if (s > 1e-7) { pf -= 2.0 * s * uN[f]; vf -= 2.0 * dot(vf, uN[f]) * uN[f]; any = true; } } if (!any) break; }
            float e1 = -1e9, e2 = -1e9;
            for (int f = 0; f < 12; f++) { float s = asin(clamp(dot(pf, uN[f]), -1.0, 1.0)); if (s > e1) { e2 = e1; e1 = s; } else if (s > e2) { e2 = s; } }
            float dr = sqrt(e1 * e1 + e2 * e2);                         // いちばん近い 2 枚の面の交わり＝部屋の辺
            if (dr < d) { d = dr; cc = float3(0.62, 0.5, 0.95); li = 0.5 + 0.5 * cos(2.0 * atan2(-e2, -e1) - 0.7); }
        }
        float wpx = pixW(t, u); float sd = d - tube - wpx;
        float st;
        if (sd < 0.0015) {
            if (t > 0.1) { if (t < u.maxD) { float cover = tube / (tube + wpx); L.tt = t; L.tc = cc * 1.15 * li; L.ta = (u.pic >= 1 ? u.picLine : 0.92) * cover; } break; }
            st = 0.012;                                                 // 出発点のすぐそば（管の中）は通りぬける
        } else st = max(sd * 0.9, 0.003);
        float c = cos(st), s = sin(st);
        float4 np = c * p + s * vv; vv = -s * p + c * vv; p = np;
        float4 npf = c * pf + s * vf; vf = -s * pf + c * vf; pf = npf;
        t += st; if (t > u.maxD) break;
    }
}

// (last, lastId) より奥で、いちばん手前の層（kind：1 目印・2 赤道の膜・3 軽い線、idx：その中の番号、id：通し番号 0〜15）。
//   同じ道のりの層（赤道の膜と、赤道の軽い線は w ＝ 0 で同じ所）は、通し番号の順に両方重ねる
//   （ウェブ版は「t が前より大きい」だけで選ぶので、t がちょうど同じだと片方が抜ける。抜けるかどうかは丸めしだい）
inline bool after(float t, int id, float last, int lastId, int webTies) { return t > last || (webTies == 0 && t == last && id > lastId); }
inline float nextLayer(thread const Layers& L, float last, int lastId, thread int& kind, thread int& idx, thread int& id, constant Uni& u) {
    float best = 1e9; kind = 0; idx = 0; id = 99;
    if (after(L.mt0, 0, last, lastId, u.webTies) && L.mt0 < best) { best = L.mt0; kind = 1; idx = 0; id = 0; }
    if (after(L.mt1, 1, last, lastId, u.webTies) && L.mt1 < best) { best = L.mt1; kind = 1; idx = 1; id = 1; }
    if (after(L.mt2, 2, last, lastId, u.webTies) && L.mt2 < best) { best = L.mt2; kind = 1; idx = 2; id = 2; }
    if (after(L.mt3, 3, last, lastId, u.webTies) && L.mt3 < best) { best = L.mt3; kind = 1; idx = 3; id = 3; }
    for (int k = 0; k < 2; k++) {
        float te = L.te + float(k) * PI;
        if (te > 0.002 && te < u.maxD && after(te, 4 + k, last, lastId, u.webTies) && te < best) { best = te; kind = 2; idx = k; id = 4 + k; }
    }
    if (u.lite == 1) {
        for (int j = 0; j < 10; j++) { float t = L.lt[j]; if (after(t, 6 + j, last, lastId, u.webTies) && t < best) { best = t; kind = 3; idx = j; id = 6 + j; } }
    }
    if (after(L.tt, 16, last, lastId, u.webTies) && L.tt < best) { best = L.tt; kind = 4; idx = 0; id = 16; }
    return best;
}
// 層の色 lc と不透明度 la（ウェブ版で配列に入れていた値と同じ）
void shadeLayer(int kind, int idx, float t, float4 p0, float4 v, thread const Layers& L, constant Mk* mk, constant Uni& u, thread float3& lc, thread float& la, thread float3& em, texture2d<float> atlas) {
    em = float3(0.0);
    if (kind == 4) { lc = L.tc; la = L.ta; return; }
    float4 q = cos(t) * p0 + sin(t) * v;
    if (kind == 1) {
        int i = idx == 0 ? L.mi0 : idx == 1 ? L.mi1 : idx == 2 ? L.mi2 : L.mi3;
        float4 c = mk[i].c; float4 mc = mk[i].col; float cr = cos(mc.w);
        float Aa = dot(p0, c), Bb = dot(v, c); float amp = sqrt(Aa * Aa + Bb * Bb);
        float4 vt = -sin(t) * p0 + cos(t) * v;
        float back = (u.ghostBack == 1 && gmod(atan2(Bb, Aa), 2.0 * PI) > PI) ? 1.0 : 0.0;   // 目印の真ん中が π より先＝遠回りの像
        lc = markerShade(mc.xyz, mk[i].info.x, c, q, vt, back, u, atlas);
        if (u.lineW > 0.0) la = clamp((mc.w - acos(min(amp, 1.0))) / max(abs(sin(t)) * u.pixAng, 1e-6), 0.0, 1.0);   // くっきり：ふちは 1 画素ぶんだけなめらかに（玉の中への深さ ÷ 1 画素の大きさ）
        else la = ss(0.0, 0.25, (amp - cr) / max(1.0 - cr, 1e-4));  // ふちはやわらかく（ウェブ版の前の見え方）
    } else if (kind == 2) {
        float lat = asin(clamp(q.z, -1.0, 1.0)), lon = atan2(q.y, q.x);
        float vtw = -sin(t) * p0.w + cos(t) * v.w;                      // 光の向きの w 成分＝赤道の膜（w ＝ 0）に当たる角の cos
        float g = lineProfile(abs(fract(lat / (PI / 6.0) + 0.5) - 0.5) * (PI / 6.0), abs(fract(lon / (PI / 6.0) + 0.5) - 0.5) * (PI / 6.0) * cos(lat), 0.06, pixFoot(t, vtw, 1.0, u), u).x;
        lc = mix(float3(0.3, 0.45, 0.9), float3(0.8, 0.9, 1.0), g); la = (0.08 + 0.4 * g) * (u.pic >= 1 ? u.picLine : 1.0);   // 絵・色の点の時は薄く
    } else {
        float thk = (L.k0 + float(idx / 2)) * L.dlt, wc = cos(thk), st = min(PI / 6.0, L.dlt / max(sin(thk), 1e-3));   // 殻が小さいほど角度で広く（距離で同じに）
        float3 sp = normalize(q.xyz);
        float vtw = -sin(t) * p0.w + cos(t) * v.w;
        float2 gg = gridLineS(asin(clamp(sp.z, -1.0, 1.0)), atan2(sp.y, sp.x), length(sp.xy), st, depthW(t, u), pixFoot(t, vtw / max(sin(thk), 1e-3), sin(thk), u), u);
        float g = gg.x;
        float uu = (wc + 1.0) * 0.5;                                    // アナ（w が＋）は赤紫、カタ（w が−）は水色、赤道は白っぽく
        lc = mix(float3(0.45, 0.85, 1.0), float3(1.0, 0.55, 0.85), uu); if (abs(thk - PI / 2.0) < L.dlt * 0.5) lc = float3(0.85, 0.9, 1.0);
        la = g > 0.01 ? min(0.95, (u.pic >= 1 ? max(u.picLine, 0.0) * 1.2 : 0.55) * g * depthMul(t, u)) : 0.0;
        em = lc * (gg.y * u.glow * 0.05 * min(1.0, depthMul(t, u)) * u.edr);   // 線のまわりの光
        lc *= u.edr;                                                    // 線の芯（EDR の画面では明るく）
    }
}

// ---- 球層（超球アプリの「球殻積層」と同じ見た目）：アナ・カタそれぞれ n 枚の w = ±cos θ の球殻（赤道は共通）----
// 殻の表（Swift の Renderer.shellTable で作る。1 枚ごとに x＝w の値 ±cos θ、yzw＝色：アナ極 赤 → 赤道 水色 → カタ極 紫）
// 球層の網目（ふだんは 15° ごと、壮大モードでは 5° ごと）
//   戻り値 x：線の芯（ウェブ版と同じ）、y：線のまわりの光のにじみ（芯の 3 倍の幅で、なだらかに消える）
inline float2 gridLine15(float lat, float lon, float coslat, float fp, constant Uni& u) {
    float st = u.gridSt, lw = 0.025 * st / (PI / 12.0);
    float da = abs(fract(lat / st + 0.5) - 0.5) * st, db = abs(fract(lon / st + 0.5) - 0.5) * st * coslat;
    return lineProfile(da, db, lw, fp, u);
}
// 1 枚の殻との当たり（道のり t、殻の番号 i）の色 cc と不透明度 al（ウェブ版の shellsBetween の中身、レインボー・w 軸の場合）
//   q・vt：当たった点と、そこでの光の向き（呼ぶ側で三角関数なしに求める）。fadeR：遠さで薄める割合。
//   wc：この殻の w（q.w ＝ wc）、vw：光の向きの w 成分（vt.w）、hz：もやの色
//   殻の面に直交する向き nP ＝ ±(e_w − q·wc)／√(1 − wc²) なので、cv ＝ vt·nP ＝ ±vt.w／√(1 − wc²)、q の xyz の長さも √(1 − wc²)（正規化が要らない）
//   em：光る線のにじみ（後ろを隠さずに足す光）
void shadeShell(float t, float fadeR, int i, int n, float4 q, float4 vt, float wc, float vw, float3 hz, constant Uni& u, constant float4* sh, thread float3& cc, thread float& al, thread float3& em) {
    float faceK = min(1.0, 1.5 / u.shellRange);
    float spF = u.space == 1 ? 0.3 : 1.0;                            // 宇宙の時は殻の面を薄く（網目の線は残す）。奥の星が透けて見えるように
    float sg = i < n ? 1.0 : -1.0;                                  // この殻が囲む極（アナ ＋、カタ −）
    float iS = rsqrt(max(1.0 - wc * wc, 1e-8));
    float cv = sg * vw * iS;
    float3 c0 = sh[i].yzw, c = c0;
    float rimK = clamp(1.0 - abs(cv), 0.0, 1.0);
    float3 sp = q.xyz * iS;
    float2 gg = u.shellBare == 1 ? float2(0.0) : gridLine15(asin(clamp(sp.z, -1.0, 1.0)), atan2(sp.y, sp.x), length(sp.xy), pixFoot(t, cv, 1.0 / iS, u), u);   // 網目（cos 緯度 ＝ xy の長さ）
    float g = gg.x;
    float3 core = c0 * u.edr;                                       // 線の芯の色（EDR の画面では 1 より明るく）
    if (u.shellSolid == 1) {   // 立体版：面に光（左上・手前から）、つや、ふちは暗い輪郭
        float4 nP = sg * (float4(0.0, 0.0, 0.0, 1.0) - q * wc) * iS;
        float4 nn = cv < 0.0 ? -nP : nP;
        float4 Lg = normalize(u.L0 - q * dot(u.L0, q));               // 光の向き（左上・手前から。L0 は Swift で 1 コマに 1 回）
        float dif = 0.4 + 0.6 * max(0.0, dot(nn, Lg));
        float4 h = normalize(Lg - vt); float spec = pow(max(0.0, dot(nn, h)), 28.0) * 0.55;
        c = c * dif + float3(spec);
        if (cv < 0.0) c *= 1.0 - u.shellBack * 0.5;
        float edge = ss(0.80, 0.97, rimK) * ss(0.08, 0.45, t);
        g *= u.solidWire;                                           // 網目の濃さ（ウェブ版は 0.35＝ごく薄く。強めると線も少し明るく）
        cc = mix(mix(c, core * (1.3 + 0.8 * max(0.0, u.solidWire - 0.35)), g), c * 0.2, edge);
        al = min(0.9, (u.shellOp * 1.8 * faceK * spF + 0.25 * g) * (0.12 + 0.88 * abs(cv)) + 0.3 * edge * faceK);
    } else {
        c *= 1.0 - 0.5 * pow(rimK, 1.6);                              // ふちほど暗く（リム影）
        if (cv < 0.0) c *= 1.0 - u.shellBack * 0.6;                   // 極の側から見た面は暗く
        cc = mix(c, core * 1.4, g * 0.8);
        al = min(0.9, (u.shellOp * faceK * spF + 0.62 * g) * (0.25 + 0.75 * abs(cv)));
    }
    float dm = min(1.0, depthMul(t, u)), fg = exp(-t * u.fog);
    if (u.lineW > 0.0) al *= mix(0.25 + 0.75 * g, 1.0, ss(0.02, 0.3, t));   // くっきりの時：すぐそばの殻は面を薄く（線は残す）。画面いっぱいに殻の色がかからないように
    al = min(0.95, al * fadeR * dm);
    cc = mix(cc, hz, 1.0 - fg);
    em = c0 * (gg.y * u.glow * 0.07 * fadeR * dm * fg * (0.25 + 0.75 * abs(cv)) * u.edr);   // 線のまわりの光（遠いほど・もやの中ほど弱く）
}

fragment float4 fmain(VOut in [[stage_in]], constant Uni& u [[buffer(0)]], constant Mk* mk [[buffer(1)]], constant float4* sh [[buffer(2)]], constant float4* uN [[buffer(3)]], texture2d<float> atlas [[texture(0)]]) {
    float2 uv = in.pos.xy / u.res * 2.0 - 1.0; uv.y = -uv.y;          // Metal の画素は上から下へ
    float asp = u.res.x / u.res.y;
    float3 dir;
    if (u.lens == 0) { dir = normalize(float3(uv.x * u.tanF * asp, uv.y * u.tanF, -1.0)); }   // ふつう（ピンホール）
    else if (u.lens == 1) {                                             // 魚眼（等距離射影）：縦の半径 1 ↔ 視野の半分
        float2 sc = float2(uv.x * asp, uv.y); float r = length(sc); float ang = r * u.fovY * 0.5;
        if (ang > PI) return float4(0.01, 0.015, 0.03, 1.0);
        float2 d2 = r > 1e-6 ? sc / r : float2(0.0); dir = float3(sin(ang) * d2, -cos(ang));
    } else {                                                            // 360°（正距円筒）：横 360°・縦 180°
        float lon = uv.x * PI, lat = uv.y * PI * 0.5; dir = float3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon));
    }
    float4 p0 = u.P; float4 v = normalize(dir.x * u.R + dir.y * u.U - dir.z * u.F);
    // ---- 重ねる層の t を集める ----
    Layers L;
    markersTop(p0, v, L, mk, u);
    L.te = 1e9;
    if (u.eq == 1 && (u.pic == 0 || u.picLine > 0.0)) { float te = atan2(-p0.w, v.w); if (te < 0.0) te += PI; L.te = te; }   // 赤道の膜 S²（w = 0）
    for (int j = 0; j < 10; j++) L.lt[j] = 1e9;
    L.k0 = 0.0; L.dlt = 1.0;
    L.tt = 1e9; L.tc = float3(0.0); L.ta = 0.0;
    if ((u.pic == 0 || u.picLine > 0.0) && (u.circ == 1 || u.room == 1)) tubes(p0, v, L, u, uN);
    // 光の道を φ だけ回した組 E1・E2：p(t) = cos(t−φ)·E1 + sin(t−φ)·E2、w(t) = amp·cos(t−φ)。
    //   w ＝ wc の殻との当たりでは cos(t−φ) ＝ wc／amp、sin(t−φ) ＝ ±√(1 − (wc／amp)²) なので、cos t・sin t が要らない
    float Aw = p0.w, Bw = v.w; float amp = sqrt(Aw * Aw + Bw * Bw); float phiW = atan2(Bw, Aw);
    float ia = 1.0 / max(amp, 1e-5);
    float4 E1 = (Aw * p0 + Bw * v) * ia, E2 = (-Bw * p0 + Aw * v) * ia;
    // 軽い線：アナ極のまわりの w = 一定の殻（どれも球面 S²）のうち、自分のまわりの 5 枚。殻の間は「決まった距離」（R＝1 の時の 30°）。
    //   線（網目）にかかる当たりだけを覚える（ウェブ版と同じ）
    if (u.lite == 1) {
        float dlt = PI / 6.0 / u.uni, kMax = floor(PI / dlt + 0.5) - 1.0;
        float k0 = max(1.0, min(floor(acos(clamp(p0.w, -1.0, 1.0)) / dlt + 0.5) - 2.0, kMax - 4.0));
        L.k0 = k0; L.dlt = dlt;
        for (int s = 0; s < 5; s++) {
            float kk = k0 + float(s); if (kk > kMax + 0.5) break;
            float thk = kk * dlt, wc = cos(thk), st = min(PI / 6.0, dlt / max(sin(thk), 1e-3));
            if (amp < abs(wc) + 1e-6) continue;
            float cs = clamp(wc * ia, -1.0, 1.0), dt = acos(cs), sd = sqrt(max(0.0, 1.0 - cs * cs));
            for (int k = 0; k < 2; k++) {
                float t = gmod(k == 0 ? phiW - dt : phiW + dt, 2.0 * PI);
                if (t > 0.002 && t < u.maxD) {
                    float4 q = cs * E1 + (k == 0 ? -sd : sd) * E2; float3 sp = normalize(q.xyz);
                    float sk = sin(thk);
                    float2 g = gridLineS(asin(clamp(sp.z, -1.0, 1.0)), atan2(sp.y, sp.x), length(sp.xy), st, depthW(t, u), pixFoot(t, sd * amp / max(sk, 1e-3), sk, u), u);
                    if (g.x > 0.01 || (u.glow > 0.0 && g.y > 0.02)) L.lt[s * 2 + k] = t;   // 線（か、そのまわりの光）にかかる時だけ
                }
            }
        }
    }
    // ---- 手前から重ねる：遠いほど透け（fade）、遠いほどもやに溶ける（fog）----
    //   殻を手前から 1 回だけたどり、その手前にある層を先に重ねる（ウェブ版と重なる順は同じ）。
    //   殻：w(t) = amp·cos(t − φ) なので、減る半周・増える半周ごとに殻を順にたどれば、t の順に並ぶ
    float3 col = float3(0.0); float T = 1.0; bool done = false; float3 hz = haze(dir, u.space);
    int kind, idx, lid; float nt = nextLayer(L, -1.0, -1, kind, idx, lid, u);
    if (u.shell == 1) {
        int n = u.shellN; int nTot = 2 * n - 1;
        float s0 = gmod(-phiW, 2.0 * PI); if (s0 > 2.0 * PI - 1e-4) s0 -= 2.0 * PI;
        int m0 = int(floor(s0 / PI));
        bool end = amp < 1e-5;
        for (int ph = 0; ph < 11 && !end && !done; ph++) {
            int m = m0 + ph; bool dec = gmod(float(m), 2.0) < 0.5;
            if (float(m) * PI - s0 > u.shellRange) break;
            for (int k = 0; k < 41; k++) {
                if (k >= nTot) break;
                int i = dec ? k : nTot - 1 - k;
                float wc = sh[i].x;
                if (dec ? wc > amp : wc < -amp) continue;                   // この半周ではまだ届かない殻
                if (abs(wc) > amp) break;                                   // ここから先の殻には届かない
                float a = acos(clamp(wc * ia, -1.0, 1.0));
                float t = (dec ? float(m) * PI + a : float(m + 1) * PI - a) - s0;   // 半周の中では k とともに増える
                if (t < 0.002) continue;
                if (t >= u.shellRange) { end = true; break; }
                while (nt <= t) {                                           // この殻より手前の層を先に
                    float3 lc, le; float la; shadeLayer(kind, idx, nt, p0, v, L, mk, u, lc, la, le, atlas);
                    float aL = la * exp(-nt * u.fade), fgL = exp(-nt * u.fog);
                    col += T * (aL * mix(lc, hz, 1.0 - fgL) + le * fgL * exp(-nt * u.fade)); T *= (1.0 - aL);
                    nt = nextLayer(L, nt, lid, kind, idx, lid, u);
                    if (T < 0.003) { done = true; break; }
                }
                if (done) break;
                float fadeR = clamp(1.0 - t / u.shellRange, 0.0, 1.0); fadeR *= fadeR * (3.0 - 2.0 * fadeR);   // 遠い殻ほど薄く、見える距離で 0
                fadeR *= ss(0.004, 0.04, t);                                // ちょうど殻の上にいる時は消す
                if (T * fadeR < 0.003) continue;                            // 目に見えないほど薄い殻（1/255 未満）は、色を計算しない
                float cs = wc * ia, sn = sqrt(max(0.0, 1.0 - cs * cs)); if (!dec) sn = -sn;
                float4 q = cs * E1 + sn * E2, vt = -sn * E1 + cs * E2;
                float3 cc, em; float al; shadeShell(t, fadeR, i, n, q, vt, wc, -sn * amp, hz, u, sh, cc, al, em);
                col += T * (al * cc + em); T *= (1.0 - al);
                if (T < 0.01) { done = true; break; }
            }
        }
    }
    while (!done && nt < 1e8) {                                             // 残りの層
        float3 lc, le; float la; shadeLayer(kind, idx, nt, p0, v, L, mk, u, lc, la, le, atlas);
        float aL = la * exp(-nt * u.fade), fgL = exp(-nt * u.fog);
        col += T * (aL * mix(lc, hz, 1.0 - fgL) + le * fgL * exp(-nt * u.fade)); T *= (1.0 - aL);
        nt = nextLayer(L, nt, lid, kind, idx, lid, u);
        if (T < 0.003) break;
    }
    float3 bg = bgc(dir, u.space);
    if (u.space == 1 && u.band > 0.0) {                                     // 天の川（青白）と、淡い星雲（赤紫）
        float g1 = bandGlow(p0, v, float4(0.0, 1.0, 0.0, 0.0), float4(0.0, 0.0, 1.0, 0.0), 0.16);
        float g2 = bandGlow(p0, v, float4(0.7071, 0.7071, 0.0, 0.0), float4(0.0, 0.0, 0.7071, -0.7071), 0.3);
        bg += u.band * (g1 * float3(0.42, 0.46, 0.62) + g2 * float3(0.30, 0.08, 0.26));
    }
    col += T * mix(bg, hz, 1.0 - exp(-u.maxD * u.fog * 0.6));
    // 宇宙の時は、透けて残った割合 T をアルファに書く（あとで星を、その割合だけ足す）
    return float4(pow(max(col, 0.0), float3(0.9)), u.space == 1 ? T : 1.0);
}

// ---- 星（宇宙の時）：S³ の決まった点。自分から見える向きは 2 つ（近回り d と、反対向きの遠回り 2π − d）----
struct StarU { float4 P, R, U, F; float2 res; float tanF; float fovY; int lens; float fog; float lum; float maxD; float edr; float px; float spad0; float spad1; };
struct Star { float4 p; float4 c; };                                   // p：S³ の点、c.rgb：色、c.w：明るさ
struct SOut { float4 pos [[position]]; float sz [[point_size]]; float3 col; };
vertex SOut vstar(uint vid [[vertex_id]], constant Star* st [[buffer(0)]], constant StarU& u [[buffer(1)]]) {
    SOut o; o.pos = float4(3.0, 3.0, 0.0, 1.0); o.sz = 1.0; o.col = float3(0.0);   // 写らない時は画面の外へ
    Star s = st[vid >> 1];
    float c = clamp(dot(s.p, u.P), -1.0, 1.0); float4 w = s.p - c * u.P; float l = length(w);
    if (l < 1e-5) return o;
    w /= l; float d = acos(c);
    if ((vid & 1u) == 1u) { w = -w; d = 2.0 * PI - d; }
    if (d > u.maxD) return o;
    float3 dir = float3(dot(w, u.R), dot(w, u.U), -dot(w, u.F));
    float asp = u.res.x / u.res.y; float2 uv;
    if (u.lens == 0) { if (dir.z > -1e-3) return o; uv = float2(dir.x / (-dir.z) / (u.tanF * asp), dir.y / (-dir.z) / u.tanF); }
    else if (u.lens == 1) {
        float ang = acos(clamp(-dir.z, -1.0, 1.0)), r2 = length(dir.xy), rr = ang / (u.fovY * 0.5);
        float2 d2 = r2 > 1e-6 ? dir.xy / r2 : float2(0.0); uv = float2(d2.x * rr / asp, d2.y * rr);
    } else { uv = float2(atan2(dir.x, -dir.z) / PI, asin(clamp(dir.y, -1.0, 1.0)) / (PI * 0.5)); }
    if (abs(uv.x) > 1.05 || abs(uv.y) > 1.05) return o;
    // 明るさ：S³ では星の光が広がる球面の広さが 4π·sin²d。反対側（d ≈ π）でまた集まって明るくなる（上限つき）。遠いほどもやで少し暗く
    float sn = sin(d), b = s.c.w * min(8.0, 0.8 / max(sn * sn, 0.02)) * exp(-d * u.fog * 0.35) * u.lum;
    o.pos = float4(uv, 0.0, 1.0);
    o.sz = clamp((1.6 + 2.4 * sqrt(b)) * u.px, 1.5, 28.0);
    o.col = s.c.rgb * b;
    return o;
}
fragment float4 fstar(SOut in [[stage_in]], float2 pc [[point_coord]], constant StarU& u [[buffer(0)]]) {
    float r2 = dot(pc - 0.5, pc - 0.5) * 4.0;                           // 0 真ん中 〜 1 ふち
    float3 c = in.col * (exp(-r2 * 10.0) + 0.18 * exp(-r2 * 3.0)) * (1.0 - ss(0.7, 1.0, r2));
    return float4(min(c, float3(u.edr)), 0.0);                          // 明るい星は EDR の画面で 1 より明るく
}
"""#
