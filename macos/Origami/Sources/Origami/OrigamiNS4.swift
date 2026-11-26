// 4 次元のナビエ–ストークス（本物の 4D の水）：32⁴ のマスを GPU（Metal の計算シェーダー）で解く。
//   速さはマスの壁ごと（MAC 格子：x・y・z・w の 4 つの成分を、それぞれの向きの壁の真ん中に置く）、圧力と水面はマスの真ん中。
//   1 歩：速さを流れで運ぶ（セミラグランジュ：流れを逆にたどって、前の値を 16 点で補間）→ 水面までの距離 φ を運ぶ → 注ぐ水 → 重力 →
//         水が縮まないように圧力を解く（赤黒の SOR、前の圧力から始める。水面は圧力 0、水面までの距離で位置を細かく：ゴースト流体）→ 圧力の坂で速さを直す →
//         空気側へ速さをのばす（次の歩で水面を運ぶため）。
//   水の量：体積は積分 V で決まっているので、φ を少しずらして毎回合わせ直す（運ぶ計算で少しずつ減るのを防ぐ）。
//   粘りは小さい水なので、運ぶ計算のなまり（数値粘性）にまかせる＝オイラー方程式に近い。底の排水口・底の全開は、そこだけ外の圧力 0（水が出ていける）。
//   長さはマス 1 つ ＝ 1（格子の単位）、速さと重力は世界の単位（箱の半分 H、g）。インデックスは ((l·M ＋ k)·M ＋ j)·M ＋ i（l が w）、M ＝ N＋1
import Foundation
import Metal
import simd

struct NS4Params {
    var jetC = SIMD4<Float>(0, 0, 0, 0)                               // 注ぐ水の筋の真ん中（x・y・z、格子の単位）
    var N: Int32 = 32, M: Int32 = 33, c: Int32 = 0, par: Int32 = 0
    var open: Int32 = 0, jetOn: Int32 = 0, swirlOn: Int32 = 0, topOpen: Int32 = 0   // topOpen：上（+W）の面を開ける（遊ぶモードでふたを開けた時、外の圧力 0）
    var dx: Float = 0, dt: Float = 0, g: Float = 2.7, hole: Float = 0   // dx：マス 1 つの世界の長さ、hole：排水口の半分の幅（格子の単位、0 で無し）
    var omega: Float = 1.7, jetR: Float = 0, jetV: Float = 0, shift: Float = 0
    var nu: Float = 0.012, smooth: Float = 0.12, pad2: Float = 0, vort: Float = 0   // 粘り（動粘性、世界の単位）・水面をならす強さ（表面張力のかわり）・渦の強調（渦度の閉じこめ ε）
    var gvec = SIMD4<Float>(0, 0, 0, -2.7)                            // 重力（箱の x・y・z・w の向き、世界の単位）。積分の時は −w、遊ぶモードは画面の下
    var jetD = SIMD4<Float>(0, 0, 0, -1)                              // 注ぐ水の向き（積分の時は −w、遊ぶモードは重力の向き＝画面の上から）
    var ex2 = SIMD4<Float>(0.8, 0, 0, 0)                              // w：床の傾きの強さ（排水口へ向かう加速度、世界の単位。0 で平ら）。z：通気口の半分の幅（格子の単位、0 で無し。上 +W の面の (x,y,z) ＝ (¼, ¾, ¼) のマス）。x：波のブレーキ（1 秒あたりの弱まり γ。壁とのこすれのかわり：ちゃぷちゃぷが数秒で静まる）
    var kick = simd_float4x4(0)                                       // 箱を回した時の、回る速さの変わり（箱から見た 4D の回転の生成子の差 ΔW）。水には −ΔW r の速さ（オイラーの力：水はその場に残ろうとする）
    var Nw: Int32 = 0, Mw: Int32 = 0, wF: Int32 = -1, wL: Int32 = -1   // 上下にのばした時：w のマスの数・その＋1・床の壁の層・ふたの壁の層（−1 で無し）
}

let ns4Shader = """
#include <metal_stdlib>
using namespace metal;
struct P { float4 jetC; int N; int M; int c; int par; int open; int jetOn; int swirlOn; int topOpen; float dx; float dt; float g; float hole; float omega; float jetR; float jetV; float shift; float nu; float smooth; float pad2; float vort; float4 gvec; float4 jetD; float4 ex2; float4x4 kick; int Nw; int Mw; int wF; int wL; };
inline int4 dec(uint id, int M) { int i = int(id) % M; int j = (int(id) / M) % M; int k = (int(id) / (M * M)) % M; int l = int(id) / (M * M * M); return int4(i, j, k, l); }
inline int enc(int4 q, int M) { return ((q.w * M + q.z) * M + q.y) * M + q.x; }
inline int4 ax(int c) { return int4(c == 0, c == 1, c == 2, c == 3); }
inline bool inCell(int4 q, int N) { return all(q >= 0) && all(q < N); }
inline bool inFace(int4 q, int c, int N) { int4 hi = int4(N - 1); hi[c] = N; return all(q >= 0) && all(q <= hi); }
// ---- 上下にのばした計算の箱（2026-11-27）：w の向きに「下の空間・床の壁（wF）・超立方体・ふたの壁（wL）・上の空間」。wF・wL ＜ 0 なら、のばさない（前と同じ） ----
inline int NcOf(int c, constant P& p) { return c == 3 ? p.Nw : p.N; }
inline int boxLo(constant P& p) { return p.wF >= 0 ? p.wF + 1 : 0; }
// 排水口（超立方体の床の、真ん中の穴。全開なら床ぜんぶ）
inline bool holeAt(int4 q, constant P& p) {
    if (p.open == 1) return true;
    if (p.hole <= 0.0) return false;
    float3 r = abs(float3(q.xyz) + 0.5 - float(p.N) * 0.5);
    return r.x < p.hole && r.y < p.hole && r.z < p.hole;
}
// 通気口（ふた +W の (x,y,z) ＝ (¼, ¾, ¼) のマス）
inline bool ventAt(int4 q, constant P& p) {
    if (p.ex2.z <= 0.0) return false;
    float c0 = floor(float(p.N) * 0.25) + 0.5, c1 = floor(float(p.N) * 0.75) + 0.5;
    float3 r = abs(float3(q.xyz) + 0.5 - float3(c0, c1, c0));
    return r.x < p.ex2.z && r.y < p.ex2.z && r.z < p.ex2.z;
}
// 注ぎ口（ふたの穴：注ぐ筋の太さより 1 マス広く）
inline bool spoutAt(int4 q, constant P& p) { return length(float3(q.xyz) + 0.5 - p.jetC.xyz) < p.jetR + 1.0; }
inline bool lidHole(int4 q, constant P& p) { return p.topOpen != 0 || ventAt(q, p) || spoutAt(q, p); }
// 壁のマス（床とふたの層の、穴でない所）
inline bool solidAt(int4 q, constant P& p) { return (p.wF >= 0 && q.w == p.wF && !holeAt(q, p)) || (p.wL >= 0 && q.w == p.wL && !lidHole(q, p)); }
inline bool inCellP(int4 q, constant P& p) { return all(q >= 0) && q.x < p.N && q.y < p.N && q.z < p.N && q.w < p.Nw && !solidAt(q, p); }
inline bool inFaceP(int4 q, int c, constant P& p) { int4 hi = int4(p.N - 1, p.N - 1, p.N - 1, p.Nw - 1); hi[c] = NcOf(c, p); return all(q >= 0) && all(q <= hi); }
// 速さが決まっている壁（箱の外の端・壁のマスに触れる所）
inline bool wallF(int4 q, int c, constant P& p) { return q[c] == 0 || q[c] == NcOf(c, p) || solidAt(q, p) || solidAt(q - ax(c), p); }
inline bool inJet(int4 q, constant P& p) { return p.jetOn != 0 && p.topOpen == 0 && int(p.jetC.w) >= p.Nw - 3 && length(float3(q.xyz) + 0.5 - p.jetC.xyz) < p.jetR; }   // 天井から入れる時だけ、天井の壁を開ける
// 箱のいちばん上（w の上の端）が開いているか（ふたを全部開けた時、または通気口）。のばした時は、ふたは中の壁の層なので、上の端は閉じている
inline bool topOpenAt(int4 q, constant P& p) { if (p.wL >= 0) return false; return p.topOpen != 0 || ventAt(q, p); }
// 箱のいちばん下（w ＝ 0）が開いているか。のばした時は、下の空間の底はぜんぶ開いている（落ちた水は外へ）
inline bool openAt(int4 q, constant P& p) { return p.wF >= 0 ? true : holeAt(q, p); }
// 運ぶ元を探す時、壁の層を通りぬけないように：同じ部屋（下の空間・超立方体・上の空間）の中におさえる。穴のある所は通りぬけてよい
inline float4 regClamp(float4 xb, int4 q, int c, constant P& p) {
    if (p.wF < 0) return xb;
    int lw = q.w, lo, hi;
    if (lw < p.wF) { lo = 0; hi = p.wF - 1; } else if (lw == p.wF) return xb; else if (lw < p.wL) { lo = p.wF + 1; hi = p.wL - 1; } else if (lw == p.wL) return xb; else { lo = p.wL + 1; hi = p.Nw - 1; }
    float mn = float(lo) + (c == 3 ? 0.0 : 0.5), mx = float(hi) + (c == 3 ? 1.0 : 0.5);
    int4 qb = int4(int3(floor(clamp(xb.xyz, float3(0.0), float3(float(p.N) - 0.01)))), 0);
    if (xb.w < mn) {
        bool th = lo == 0 ? true : lo == p.wF + 1 ? (holeAt(q, p) || holeAt(qb, p)) : (lidHole(q, p) || lidHole(qb, p));
        if (!th) xb.w = mn;
    }
    if (xb.w > mx) {
        bool th = hi == p.Nw - 1 ? true : hi == p.wF - 1 ? (holeAt(q, p) || holeAt(qb, p)) : (lidHole(q, p) || lidHole(qb, p));
        if (!th) xb.w = mx;
    }
    return xb;
}
// 箱の壁の速さを、proj と同じ決まりで読む（閉じた壁は 0、開いた底・ふたはそのまま、注ぐ口は注ぐ速さ）
inline float faceVal(device const float* U, int4 q, int c, constant P& p, int MM) {
    if (solidAt(q, p) || solidAt(q - ax(c), p)) return 0.0;
    float u = U[c * MM + enc(q, p.M)];
    if (q[c] == NcOf(c, p)) return (c == 3 && topOpenAt(q, p)) ? u : (c == 3 && inJet(q, p)) ? p.jetD.w * p.jetV : 0.0;
    if (q[c] == 0) return (c == 3 && openAt(q, p)) ? u : 0.0;
    return u;
}
// 成分 c の速さを、格子の点 x（マスの真ん中が i＋0.5）で 16 点の補間
float sampleF(device const float* U, int c, float4 x, constant P& p) {
    float4 q = x - 0.5; q[c] = x[c];
    float4 hi = float4(float(p.N - 1), float(p.N - 1), float(p.N - 1), float(p.Nw - 1)); hi[c] = float(NcOf(c, p));
    q = clamp(q, float4(0.0), hi);
    int4 i0 = int4(floor(q)); i0 = clamp(i0, int4(0), int4(hi) - 1);
    float4 f = q - float4(i0);
    float s = 0.0;
    for (int b = 0; b < 16; b++) {
        int4 o = int4(b & 1, (b >> 1) & 1, (b >> 2) & 1, (b >> 3) & 1);
        float4 wv = select(1.0 - f, f, o != 0);
        s += wv.x * wv.y * wv.z * wv.w * U[enc(i0 + o, p.M)];
    }
    return s;
}
float sampleC(device const float* A, float4 x, constant P& p) {
    float4 hiC = float4(float(p.N - 1), float(p.N - 1), float(p.N - 1), float(p.Nw - 1));
    float4 q = clamp(x - 0.5, float4(0.0), hiC);
    int4 i0 = clamp(int4(floor(q)), int4(0), int4(hiC) - 1);
    float4 f = q - float4(i0);
    float s = 0.0;
    for (int b = 0; b < 16; b++) {
        int4 o = int4(b & 1, (b >> 1) & 1, (b >> 2) & 1, (b >> 3) & 1);
        float4 wv = select(1.0 - f, f, o != 0);
        s += wv.x * wv.y * wv.z * wv.w * A[enc(i0 + o, p.M)];
    }
    return s;
}
float4 velAt(device const float* U, float4 x, constant P& p) {
    int MM = p.M * p.M * p.M * p.Mw;
    return float4(sampleF(U, 0, x, p), sampleF(U + MM, 1, x, p), sampleF(U + 2 * MM, 2, x, p), sampleF(U + 3 * MM, 3, x, p));
}
// 速さを運ぶ（成分 c）
kernel void advU(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); int c = p.c;
    if (!inFaceP(q, c, p)) { UT[c * MM + id] = 0.0; return; }
    float4 x = float4(q) + 0.5; x[c] = float(q[c]);
    bool wall = wallF(q, c, p);
    if (c == 3 && q.w == p.Nw && inJet(q, p)) { UT[c * MM + id] = p.jetD.w * p.jetV; return; }   // 上から注ぐ所は、入ってくる速さ
    if (wall && !(c == 3 && q.w == 0 && openAt(q, p)) && !(c == 3 && q.w == p.Nw && topOpenAt(q, p))) { UT[c * MM + id] = 0.0; return; }
    float4 v = velAt(U, x, p);
    float4 xb = regClamp(x - p.dt * v / p.dx, q, c, p);
    UT[c * MM + id] = sampleF(U + c * MM, c, xb, p);
}
// MacCormack：運んだ速さ（UF）を、こんどは逆向きに運び戻して、もとの値とのずれの半分を足し戻す。
//   半ラグランジュ（1 回だけ運ぶ）は、マスの間を直線でならすので、それだけで粘りがあるように なまる（マスが粗いほど強い）。これでその分を減らす。
//   行き過ぎて暴れないように、運んだ元の場所のまわり 16 点の最小・最大の間におさえる
kernel void macU(device const float* U [[buffer(0)]], device const float* UF [[buffer(1)]], device float* UC [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); int c = p.c; int fi = c * MM + int(id);
    float f = UF[fi]; UC[fi] = f;
    if (!inFaceP(q, c, p) || wallF(q, c, p)) return;
    float4 x = float4(q) + 0.5; x[c] = float(q[c]);
    float4 v = velAt(U, x, p);
    float4 xb = regClamp(x - p.dt * v / p.dx, q, c, p), xf = regClamp(x + p.dt * v / p.dx, q, c, p);
    float back = sampleF(UF + c * MM, c, xf, p);
    float cor = f + 0.5 * (U[fi] - back);
    float4 qq = xb - 0.5; qq[c] = xb[c];
    float4 hi = float4(float(p.N - 1), float(p.N - 1), float(p.N - 1), float(p.Nw - 1)); hi[c] = float(NcOf(c, p));
    qq = clamp(qq, float4(0.0), hi);
    int4 i0 = int4(floor(qq)); i0 = clamp(i0, int4(0), int4(hi) - 1);
    float lo = 1e9, up = -1e9;
    for (int b = 0; b < 16; b++) {
        int4 o = int4(b & 1, (b >> 1) & 1, (b >> 2) & 1, (b >> 3) & 1);
        float u0 = U[c * MM + enc(i0 + o, p.M)]; lo = min(lo, u0); up = max(up, u0);
    }
    UC[fi] = clamp(cor, lo, up);
}
// 水面までの距離 φ を運ぶ（体積を合わせるずれ shift もここで足す）
kernel void advPhi(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* phiT [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); if (!inCellP(q, p)) { phiT[id] = solidAt(q, p) ? p.dx : 1.0; return; }   // 壁のマスは、すぐそばの空気（遠い空気にすると、まわりのなめらかなつなぎで水がけずれる）
    float4 x = float4(q) + 0.5;
    float4 v = velAt(U, x, p);
    float4 xb = regClamp(x - p.dt * v / p.dx, q, 0, p);
    // 開いた口（ふた +W）・開いた底の外は空気（外から流れこむ所は空気が入る。箱の端と同じ水にすると、満タンの時に空気が入れ替われず抜けない）
    if ((xb.w > float(p.Nw) && topOpenAt(q, p)) || (xb.w < 0.0 && openAt(q, p))) { phiT[id] = p.dx; return; }
    float f = sampleC(phi, xb, p);
    // 開いた口（ふた・通気口）のすぐ下のマス：外のマス（空気 φ ＝ dx）との間をつないで運ぶ。粗い格子（8⁴）では 1 歩で動く距離がマスの半分に届かず、
    //   外の空気を取ってこられなかった（満タンのまま抜けない）
    if (q.w == p.Nw - 1 && xb.w > float(p.Nw) - 0.5 && topOpenAt(q, p)) f = mix(f, p.dx, clamp(xb.w - (float(p.Nw) - 0.5), 0.0, 1.0));
    // 抜いている間（排水口が開いている）は、通気口のすぐ下のマスは外の空気とつながった空気のマス：粗い格子では、入ってきた小さな泡が
    //   水面をならす計算で消されて、満タンのまま抜けなかった。泡の 1 マス分は、全体の 1/N⁴ なので量はほとんど変わらない
    float fo = f + (abs(f) < 3.0 * p.dx && q.w >= boxLo(p) && q.w < boxLo(p) + p.N ? p.shift : 0.0);   // 体積の合わせ直しは超立方体の中だけ（上と下の筋の太さは変えない）
    //   （体積を合わせるずれ shift のあとで：先にすると、減った分を戻そうとする shift がこのマスをまた水にしてしまう）
    if (q.w == p.Nw - 1 && p.topOpen == 0 && p.hole > 0.0 && topOpenAt(q, p)) fo = max(fo, 0.5 * p.dx);
    // かべのうすいまく：かべにいちばん近いマスだけが水で、すぐ内側が空気なら、1 マスの厚さのまく。粗いマスでは中の流れが計算できず、
    //   なかなか流れ落ちずに残っていた（胞にからみつく水）。空気にもどす（減った水は、体積の合わせ直しで まん中の水に返る）。
    //   床（重力がかべへ向いている面）は、うすく残った最後の水なので消さない（2026-11-26）
    if (fo < 0.0 && p.ex2.y > -0.5) {
        float gl = length(p.gvec);
        for (int a = 0; a < 4; a++) {
            int side = q[a] == 0 ? -1 : (q[a] == NcOf(a, p) - 1 ? 1 : 0);
            if (side == 0) continue;
            if (p.gvec[a] * float(side) > 0.5 * gl) continue;
            int4 n1 = q - side * ax(a), n2 = q - 2 * side * ax(a);
            if (phi[enc(n1, p.M)] > 0.3 * p.dx && (!inCellP(n2, p) || phi[enc(n2, p.M)] > 0.0)) { fo = 0.5 * p.dx; break; }
        }
    }
    phiT[id] = fo;   // 体積を合わせるずれは水面の近くだけ（遠くの空気に水がわかないように）
}
// ---- 水面だけ細かく（2 倍の格子の φ、2026-11-26）----
//   流れ（速さ・圧力）は粗い格子のまま。細かい φ を同じ流れで運んで、粗い格子ではなまって消える細かい形（しぶき・波の山・細い筋）だけを、粗い φ に足して持つ。
//   大きな形（体積・注ぐ・抜く・満タン）は粗い φ が決める
float sampleN(device const float* A, float4 x, int N) {
    float4 q = clamp(x - 0.5, float4(0.0), float4(float(N - 1)));
    int4 i0 = clamp(int4(floor(q)), int4(0), int4(N - 2));
    float4 f = q - float4(i0);
    float s = 0.0;
    for (int b = 0; b < 16; b++) {
        int4 o = int4(b & 1, (b >> 1) & 1, (b >> 2) & 1, (b >> 3) & 1);
        float4 wv = select(1.0 - f, f, o != 0);
        s += wv.x * wv.y * wv.z * wv.w * A[enc(i0 + o, N + 1)];
    }
    return s;
}
// 細かい φ を運ぶ（細かいマス q の真ん中 ＝ 粗い格子の座標で (q ＋ ½)／2）
kernel void advPhiF(device const float* U [[buffer(0)]], device const float* phiF [[buffer(1)]], device float* phiFT [[buffer(2)]], constant P& p [[buffer(3)]], constant int2& fz [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int NF = fz.x, MF = NF + 1; if (int(id) >= MF * MF * MF * MF) return;
    int4 q = dec(id, MF); if (!inCell(q, NF)) { phiFT[id] = 1.0; return; }
    float4 xc = (float4(q) + 0.5) * 0.5;
    float4 xb = xc - p.dt * velAt(U, xc, p) / p.dx;
    phiFT[id] = sampleN(phiF, xb * 2.0, NF);
}
// 運んだ細かい φ の、粗いマスごとの平均（16 個の子の平均）：細かい φ の「大きな形」
kernel void downF(device const float* phiFT [[buffer(0)]], device float* dn [[buffer(1)]], constant P& p [[buffer(2)]], constant int2& fz [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    if (int(id) >= p.M * p.M * p.M * p.Mw) return;
    int4 q = dec(id, p.M); if (!inCellP(q, p)) { dn[id] = 1.0; return; }
    int MF = fz.x + 1; float s = 0.0;
    for (int b = 0; b < 16; b++) { int4 o = int4(b & 1, (b >> 1) & 1, (b >> 2) & 1, (b >> 3) & 1); s += phiFT[enc(2 * q + o, MF)]; }
    dn[id] = s / 16.0;
}
// 細かい φ ＝ 粗い φ（新しい）＋ 細かい形（運んだ細かい φ − その大きな形）。細かい形は水面の近くだけ、粗いマス 1 つ分までにおさえて、少しずつ弱める（1 歩で 0.5%）
//   （fz.y ＝ 1：はじめ・作り直した時は、粗い φ をなめらかにつないだだけ）
kernel void combF(device const float* phiFT [[buffer(0)]], device const float* dn [[buffer(1)]], device const float* phi [[buffer(2)]], device float* phiF [[buffer(3)]], constant P& p [[buffer(4)]], constant int2& fz [[buffer(5)]], uint id [[thread_position_in_grid]]) {
    int NF = fz.x, MF = NF + 1; if (int(id) >= MF * MF * MF * MF) return;
    int4 q = dec(id, MF); if (!inCell(q, NF)) { phiF[id] = 1.0; return; }
    float4 xc = (float4(q) + 0.5) * 0.5;
    float base = sampleC(phi, xc, p), d = 0.0;
    if (fz.y == 0 && abs(base) < 2.0 * p.dx) d = clamp(phiFT[id] - sampleC(dn, xc, p), -p.dx, p.dx) * 0.995;
    phiF[id] = base + d;
}
// 注ぐ水：上（w の上の端）の、筋の真ん中のまわりのマスを水にして、下向きの速さを入れる
kernel void jet(device float* U [[buffer(0)]], device float* phi [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM || p.jetOn == 0) return;
    int4 q = dec(id, p.M); if (!inCellP(q, p)) return;
    float r;
    if (p.pad2 > 0.5) {                                                // 遊ぶモード：入れる所は 4 次元の玉（箱のいちばん上の面の近く、どの向きでも）
        r = length(float4(q) + 0.5 - p.jetC);
    } else {                                                           // 積分：水面のすぐ上の 3 マス（落ちる高さを小さく＝おだやかに）
        int l0 = int(p.jetC.w);
        if (q.w < l0 || q.w >= l0 + 3) return;
        r = length(float3(q.xyz) + 0.5 - p.jetC.xyz);
    }
    if (r >= p.jetR) return;
    if (q.w == p.Nw - 1 && p.topOpen == 0) U[3 * MM + enc(q + int4(0, 0, 0, 1), p.M)] = p.jetD.w * p.jetV;
    phi[id] = min(phi[id], (r - p.jetR) * p.dx);
    for (int c = 0; c < 4; c++) U[c * MM + id] = p.jetD[c] * p.jetV;   // 注ぐ水の向き（遊ぶモードでは、画面の上から＝重力の向き）
}
// 重力（w の下向き）。swirlOn：はじめのゆらぎ（x‐y の面で少し回す。お風呂の水に残っている小さな回転）
kernel void force(device float* U [[buffer(0)]], constant P& p [[buffer(1)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    float dmp = exp(-p.ex2.x * p.dt);                                   // 波のブレーキ（だんだん静かに）
    for (int c = 0; c < 4; c++) if (inFaceP(q, c, p)) U[c * MM + id] = U[c * MM + id] * dmp + p.gvec[c] * p.dt;   // 重力（どの向きでも）
    // 床の傾き（ex2.w ＞ 0、排水口で抜く間）：床の近く（下から 2 マス）の水を、排水口（床の真ん中）へ向かわせる。
    //   お風呂の床は排水口へほんの少し傾けてあるので、最後の水は口へ集まって吸いこまれる（平らな床だと、うすく残ったままになる）
    if (p.ex2.w > 0.0 && q.w >= boxLo(p) && q.w <= boxLo(p) + 1) {
        float3 ctr = float3(float(p.N) * 0.5);
        for (int c = 0; c < 3; c++) if (inFaceP(q, c, p)) {
            float3 xf = float3(q.xyz) + 0.5; xf[c] = float(q[c]);         // この速さの置き場所（マスの面の真ん中）
            float3 d = ctr - xf; float l = length(d);
            if (l > 0.5) U[c * MM + id] += p.ex2.w * d[c] / l * p.dt;
        }
    }
    // 箱を回した時：水はその場に残ろうとするので、箱から見ると回る速さの変わりの逆に動く（壁の真ん中の位置 r で −ΔW r）
    if (p.pad2 < 0.5 || true) {
        float4 h = float4(float(p.N) * 0.5, float(p.N) * 0.5, float(p.N) * 0.5, float(boxLo(p)) + float(p.N) * 0.5);   // 超立方体の真ん中
        for (int c = 0; c < 4; c++) {
            if (!inFaceP(q, c, p)) continue;
            float4 r = (float4(q) + 0.5 - h) * p.dx; r[c] = (float(q[c]) - h[c]) * p.dx;
            float4 dv = p.kick * r;
            U[c * MM + id] -= dv[c];
        }
    }
    if (p.swirlOn != 0) {
        float h = float(p.N) * 0.5;
        if (inFaceP(q, 0, p)) { float y = float(q.y) + 0.5 - h; U[id] += -p.shift * y / h; }
        if (inFaceP(q, 1, p)) { float x = float(q.x) + 0.5 - h; U[MM + id] += p.shift * x / h; }
    }
}
// 粘り：水に触れている壁の速さを、まわりの同じ成分とならす（ν Δu。マス 1 つ分の時間なら、この大きさの ν で安定）
kernel void visc(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], device const float* phi [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    float k = min(0.1, p.nu * p.dt / (p.dx * p.dx));
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id); UT[fi] = U[fi];
        if (!inFaceP(q, c, p) || wallF(q, c, p)) continue;
        if (!(phi[enc(q - ax(c), p.M)] < 0.0 || phi[id] < 0.0)) continue;
        float s = 0.0, n = 0.0;
        for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) { int4 nb = q + sg * ax(d); if (inFaceP(nb, c, p)) { s += U[c * MM + enc(nb, p.M)]; n += 1.0; } }
        UT[fi] = U[fi] + k * (s - n * U[fi]);
    }
}
// 粘り（陰解法・はちみつ用）：(1 − αΔ) u ＝ u₀ をヤコビ法で解く 1 回分。α がどんなに大きくてもこわれない（くり返すほど正確）。
//   vx.x ＝ α（ν dt／dx²）、vx.y ＝ 壁にくっつく強さ（0 すべる 〜 1 くっつく：壁の外の速さを 0 として数える）
kernel void viscJ(device const float* U0 [[buffer(0)]], device const float* Uc [[buffer(1)]], device float* UT [[buffer(2)]], device const float* phi [[buffer(3)]], constant P& p [[buffer(4)]], constant float4& vx [[buffer(5)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id); UT[fi] = Uc[fi];
        if (!inFaceP(q, c, p) || wallF(q, c, p)) continue;
        if (!(phi[enc(q - ax(c), p.M)] < 0.0 || phi[id] < 0.0)) continue;
        float s = 0.0, n = 0.0;
        for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) {
            int4 nb = q + sg * ax(d);
            if (inFaceP(nb, c, p)) { s += Uc[c * MM + enc(nb, p.M)]; n += 1.0; }
            else if (d != c) n += vx.y;                                    // 横の壁：くっつく分だけ、速さ 0 の となりとして数える
        }
        UT[fi] = (U0[fi] + vx.x * s) / (1.0 + vx.x * n);
    }
}
// ---- ねばる液体の粘り（Batty と Bridson 2008 の形、4 次元）：(u − u*) の重みつきの大きさ ＋ Δt ν × 2D:D の重みつきの和 を いちばん小さくする u ----
//   重みは、そこが水である割合（マスの φ から）。空気の所の重みは 0 なので、水面では引っぱりの力が自然に 0（自由表面）。
//   D は ひずみの速さ（対角はマスの真ん中、ずれ ∂ᵢuⱼ＋∂ⱼuᵢ は 2 つの向きの角）。式は対称で正なので、共役勾配法で解く。壁の速さは 0
inline float vfr(device const float* fr, int4 q, constant P& p) { return inCellP(q, p) ? fr[enc(q, p.M)] : 0.0; }
inline float vxv(device const float* X, int c, int4 q, constant P& p, int MM) { return (inFaceP(q, c, p) && !wallF(q, c, p)) ? X[c * MM + enc(q, p.M)] : 0.0; }
// 壁の速さも入れて読む（はじめの残り r₀ ＝ b − A x₀ の時だけ）：注ぐ口の天井は、出てくる速さ（ここを 0 にすると、はちみつが止まった天井にくっついて伸びなかった）
inline float vxvD(device const float* X, int c, int4 q, constant P& p, int MM) {
    if (c == 3 && q.w == p.Nw && inFaceP(q, c, p) && inJet(q, p)) return p.jetD.w * p.jetV;
    return vxv(X, c, q, p, MM);
}
// 速さの置き場所 (c, q) の重み。−1：解かない所（壁・水から遠い空気）
inline float vActW(device const float* fr, int c, int4 q, constant P& p) {
    if (!inFaceP(q, c, p) || wallF(q, c, p)) return -1.0;
    float wf = 0.5 * (vfr(fr, q, p) + vfr(fr, q - ax(c), p)), near = wf;
    for (int j = 0; j < 4; j++) { if (j == c) continue; near += vfr(fr, q - ax(j), p) + vfr(fr, q - ax(c) - ax(j), p) + vfr(fr, q + ax(j), p) + vfr(fr, q - ax(c) + ax(j), p); }
    return near > 0.0 ? max(wf, 0.02) : -1.0;
}
kernel void vFrac(device const float* phi [[buffer(0)]], device float* fr [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); fr[id] = inCellP(q, p) ? clamp(0.5 - phi[id] / p.dx, 0.0, 1.0) : 0.0;
}
// Y ＝ A X（解かない所は 0）。vx.x ＝ α ＝ ν Δt／dx²
kernel void vApply(device const float* X [[buffer(0)]], device float* Y [[buffer(1)]], device const float* fr [[buffer(2)]], constant P& p [[buffer(3)]], constant float4& vx [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); int N = p.N, M = p.M; float al = vx.x; bool dir = vx.y > 0.5;
    #define XV(cc, qq) (dir ? vxvD(X, cc, qq, p, MM) : vxv(X, cc, qq, p, MM))
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id);
        float w = vActW(fr, c, q, p); if (w < 0.0) { Y[fi] = 0.0; continue; }
        float y = w * X[fi];
        int4 qm = q - ax(c);
        float e0 = XV(c, q) - XV(c, qm), e1 = XV(c, q + ax(c)) - XV(c, q);
        y += 2.0 * al * (vfr(fr, qm, p) * e0 - vfr(fr, q, p) * e1);
        for (int j = 0; j < 4; j++) {
            if (j == c) continue;
            int4 n1 = q + ax(j);
            float w0 = 0.25 * (vfr(fr, q, p) + vfr(fr, q - ax(c), p) + vfr(fr, q - ax(j), p) + vfr(fr, q - ax(c) - ax(j), p));
            float w1 = 0.25 * (vfr(fr, n1, p) + vfr(fr, n1 - ax(c), p) + vfr(fr, n1 - ax(j), p) + vfr(fr, n1 - ax(c) - ax(j), p));
            float s0 = (XV(j, q) - XV(j, q - ax(c))) + (XV(c, q) - XV(c, q - ax(j)));
            float s1 = (XV(j, n1) - XV(j, n1 - ax(c))) + (XV(c, n1) - XV(c, n1 - ax(j)));
            y += al * (w0 * s0 - w1 * s1);
        }
        Y[fi] = y;
    }
}
#undef XV
// はじめ：r ＝ b − A x₀（b ＝ 重み × u*）、p ＝ r
kernel void vInit(device const float* U [[buffer(0)]], device const float* Y [[buffer(1)]], device float* R [[buffer(2)]], device float* Pv [[buffer(3)]], device const float* fr [[buffer(4)]], constant P& p [[buffer(5)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id); float w = vActW(fr, c, q, p);
        float r = w < 0.0 ? 0.0 : w * U[fi] - Y[fi]; R[fi] = r; Pv[fi] = r;
    }
}
// 内積の部分和（1 つの組ごと）。fz.x ＝ 数
kernel void dotPart(device const float* A [[buffer(0)]], device const float* B [[buffer(1)]], device float* part [[buffer(2)]], constant P& p [[buffer(3)]], constant int2& fz [[buffer(4)]],
                    uint id [[thread_position_in_grid]], uint tid [[thread_index_in_threadgroup]], uint gid [[threadgroup_position_in_grid]], uint sl [[thread_index_in_simdgroup]], uint sg [[simdgroup_index_in_threadgroup]], uint ns [[simdgroups_per_threadgroup]]) {
    threadgroup float sh[32];
    float v = int(id) < fz.x ? A[id] * B[id] : 0.0;
    v = simd_sum(v); if (sl == 0) sh[sg] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (sg == 0) { float w = sl < ns ? sh[sl] : 0.0; w = simd_sum(w); if (sl == 0) part[gid] = w; }
}
// 部分和をまとめて S[fz.y] に（1 つの組で）。fz.x ＝ 部分和の数
kernel void dotFin(device const float* part [[buffer(0)]], device float* S [[buffer(1)]], constant P& p [[buffer(2)]], constant int2& fz [[buffer(3)]],
                   uint tid [[thread_index_in_threadgroup]], uint nt [[threads_per_threadgroup]], uint sl [[thread_index_in_simdgroup]], uint sg [[simdgroup_index_in_threadgroup]], uint ns [[simdgroups_per_threadgroup]]) {
    threadgroup float sh[32];
    float v = 0.0; for (int i = int(tid); i < fz.x; i += int(nt)) v += part[i];
    v = simd_sum(v); if (sl == 0) sh[sg] = v;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (sg == 0) { float w = sl < ns ? sh[sl] : 0.0; w = simd_sum(w); if (sl == 0) S[fz.y] = w; }
}
// x ＋＝ a p、r −＝ a Ap（a ＝ S0／S1）
kernel void cgXR(device float* X [[buffer(0)]], device float* R [[buffer(1)]], device const float* Pv [[buffer(2)]], device const float* AP [[buffer(3)]], device const float* S [[buffer(4)]], constant P& p [[buffer(5)]], uint id [[thread_position_in_grid]]) {
    int n = 4 * p.M * p.M * p.M * p.Mw; if (int(id) >= n) return;
    float a = S[1] > 1e-30 ? S[0] / S[1] : 0.0;
    X[id] += a * Pv[id]; R[id] -= a * AP[id];
}
// p ＝ r ＋ β p（β ＝ S2／S0）
kernel void cgP(device const float* R [[buffer(0)]], device float* Pv [[buffer(1)]], device const float* S [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int n = 4 * p.M * p.M * p.M * p.Mw; if (int(id) >= n) return;
    float b = S[0] > 1e-30 ? S[2] / S[0] : 0.0;
    Pv[id] = R[id] + b * Pv[id];
}
kernel void cgS(device float* S [[buffer(0)]], constant P& p [[buffer(1)]], uint id [[thread_position_in_grid]]) { if (id == 0) { S[3] = max(S[3], S[0]); S[0] = S[2]; } }
// 水面をならす（水面の近くだけ、となりの平均へ少し寄せる＝曲がった所ほど平らに：表面張力のかわり。小さな粒・うすい膜は消えていく）
kernel void smoothPhi(device const float* phi [[buffer(0)]], device float* phiT [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); float f = phi[id];
    if (!inCellP(q, p) || abs(f) > 3.0 * p.dx) { phiT[id] = f; return; }
    float s = 0.0, n = 0.0;
    for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) { int4 nb = q + sg * ax(d); if (inCellP(nb, p)) { s += phi[enc(nb, p.M)]; n += 1.0; } }
    phiT[id] = f + p.smooth * (s / n - f);
}
// ---- 渦の強調（渦度の閉じこめ）：粗いマスでならされて消える細い渦を、少し足し戻す ----
//   4 次元の渦度は「回る面」の 6 成分 Ω_ij ＝ ∂_i u_j − ∂_j u_i（3 次元の渦の軸 ω のかわり）。強さ |Ω| ＝ √(Σ_{i<j} Ω_ij²)。
//   N ＝ ∇|Ω|／|∇|Ω||（渦の強い所へ向かう向き）。力 f_i ＝ ε·dx·Σ_j Ω_ij N_j（3 次元の ε·h·(N × ω) と同じ形：N × ω の i 成分 ＝ Σ_j Ω_ij N_j）
inline float ucell(device const float* U, int4 q, int j, constant P& p) {   // マスの真ん中の速さ（成分 j：両側の壁の平均）
    int MM = p.M * p.M * p.M * p.Mw;
    return 0.5 * (U[j * MM + enc(q, p.M)] + U[j * MM + enc(q + ax(j), p.M)]);
}
inline float dU(device const float* U, int4 q, int i, int j, constant P& p) {   // ∂_i u_j（マスの真ん中で、となりのマスとの差。端は片側）
    int4 a = q - ax(i), b = q + ax(i); float span = 2.0;
    if (!inCellP(a, p)) { a = q; span = 1.0; }
    if (!inCellP(b, p)) { b = q; span = span - 1.0; }
    if (span <= 0.0) return 0.0;
    return (ucell(U, b, j, p) - ucell(U, a, j, p)) / (span * p.dx);
}
kernel void vortW(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* W [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCellP(q, p) || phi[id] >= 0.0) { W[id] = 0.0; return; }
    float s = 0.0;
    for (int i = 0; i < 4; i++) for (int j = i + 1; j < 4; j++) { float o = dU(U, q, i, j, p) - dU(U, q, j, i, p); s += o * o; }
    W[id] = sqrt(s);
}
kernel void vortF(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device const float* W [[buffer(2)]], device float* Fv [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) Fv[c * MM + id] = 0.0;
    if (!inCellP(q, p) || phi[id] >= 0.0) return;
    float4 g = float4(0.0);
    for (int i = 0; i < 4; i++) {
        int4 a = q - ax(i), b = q + ax(i); float span = 2.0;
        if (!inCellP(a, p)) { a = q; span = 1.0; }
        if (!inCellP(b, p)) { b = q; span = span - 1.0; }
        if (span > 0.0) g[i] = (W[enc(b, p.M)] - W[enc(a, p.M)]) / (span * p.dx);
    }
    float gl = length(g); if (gl < 1e-5) return;
    float4 Nv = g / gl;
    for (int i = 0; i < 4; i++) {
        float f = 0.0;
        for (int j = 0; j < 4; j++) if (j != i) f += (dU(U, q, i, j, p) - dU(U, q, j, i, p)) * Nv[j];
        Fv[i * MM + id] = p.vort * p.dx * f;
    }
}
kernel void vortAdd(device float* U [[buffer(0)]], device const float* Fv [[buffer(1)]], device const float* phi [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        if (!inFaceP(q, c, p) || wallF(q, c, p)) continue;
        int ia = enc(q - ax(c), p.M);
        if (!(phi[ia] < 0.0 && phi[id] < 0.0)) continue;               // 水の中だけ（水面のそばはさわらない）
        U[c * MM + id] += p.dt * 0.5 * (Fv[c * MM + ia] + Fv[c * MM + id]);
    }
}
// 圧力の式の右辺：−（流れの湧き出し）× dx² ／ dt
kernel void rhs(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* R [[buffer(2)]], device float* Pr [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCellP(q, p) || phi[id] >= 0.0) { R[id] = 0.0; Pr[id] = 0.0; return; }
    // 箱の壁の速さは、proj と同じ決まりで読む（閉じた壁は 0、開いた底・ふたはそのまま、注ぐ口は注ぐ速さ）。
    //   前は、重力が毎コマ足された壁の速さ（−g dt）をそのまま読んでいて、「床から水が出ていく」と数えていた。
    //   proj で壁を 0 にもどした分だけ毎コマ水が消えて、水面が g dt の速さで沈んでいた（体積の合わせ直しが、こっそり埋めていた。2026-11-26）
    float dv = 0.0;
    for (int c = 0; c < 4; c++) {
        dv += faceVal(U, q + ax(c), c, p, MM) - faceVal(U, q, c, p, MM);
    }
    R[id] = -dv * p.dx / p.dt;   // （dv／dx）× dx² ／ dt
}
// 赤黒の SOR：水のマスだけ。となりが水ならその圧力、空気なら 0（水面までの距離の割合 θ で近さを入れる）、壁なら入れない（流れが通らない）
kernel void press(device float* Pr [[buffer(0)]], device const float* phi [[buffer(1)]], device const float* R [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCellP(q, p) || ((q.x + q.y + q.z + q.w) & 1) != p.par) return;
    float pc = phi[id]; if (pc >= 0.0) { Pr[id] = 0.0; return; }
    float diag = 0.0, s = 0.0;
    for (int c = 0; c < 4; c++) {
        for (int sg = -1; sg <= 1; sg += 2) {
            int4 nb = q + sg * ax(c);
            if (!inCellP(nb, p)) {
                if (c == 3 && sg < 0 && q.w == 0 && openAt(q, p)) diag += 1.0;   // 開いた底：外は圧力 0
                if (c == 3 && sg > 0 && q.w == p.Nw - 1 && topOpenAt(q, p)) diag += 1.0;   // 開いたふた・通気口：外は圧力 0
                continue;
            }
            int ni = enc(nb, p.M); float pn = phi[ni];
            if (pn < 0.0) { diag += 1.0; s += Pr[ni]; }
            else { float th = clamp(pc / (pc - pn), 0.08, 1.0); diag += 1.0 / th; }
        }
    }
    if (diag <= 0.0) { Pr[id] = 0.0; return; }
    float pn = (s + R[id]) / diag;
    Pr[id] = Pr[id] + p.omega * (pn - Pr[id]);
}
// 圧力の坂で速さを直す（壁は 0、開いた底は外の圧力 0）
kernel void proj(device float* U [[buffer(0)]], device const float* Pr [[buffer(1)]], device const float* phi [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        if (!inFaceP(q, c, p)) continue;
        int fi = c * MM + int(id);
        if (solidAt(q, p) || solidAt(q - ax(c), p)) { U[fi] = 0.0; continue; }   // 中の壁（床・ふたの層）
        if (q[c] == NcOf(c, p)) {
            if (c == 3 && topOpenAt(q, p)) { int ib = enc(q - ax(c), p.M); if (phi[ib] < 0.0) U[fi] -= p.dt / p.dx * (0.0 - Pr[ib]); continue; }   // 開いたふた：水は外へ出ていける
            U[fi] = (c == 3 && inJet(q, p)) ? p.jetD.w * p.jetV : 0.0; continue;
        }
        if (q[c] == 0) {
            if (c == 3 && openAt(q, p) && phi[id] < 0.0) U[fi] -= p.dt / p.dx * Pr[id];
            else if (!(c == 3 && openAt(q, p))) U[fi] = 0.0;
            continue;
        }
        int4 a = q - ax(c); int ia = enc(a, p.M);
        float fa = phi[ia], fb = phi[id];
        if (fa >= 0.0 && fb >= 0.0) continue;
        float pa = Pr[ia], pb = Pr[id], th = 1.0;
        if (fa >= 0.0) { th = clamp(fb / (fb - fa), 0.08, 1.0); pa = 0.0; }
        if (fb >= 0.0) { th = clamp(fa / (fa - fb), 0.08, 1.0); pb = 0.0; }
        U[fi] -= p.dt / p.dx * (pb - pa) / th;
        U[fi] = clamp(U[fi], -12.0, 12.0);   // 念のため：計算がゆらいだ時に暴れないように（9.8 で 1.8 m 落ちても 6 m/s ほど）
    }
}
// 速さが決まっている壁（水に触れている壁、ふつうの壁）の印
kernel void valid(device const float* phi [[buffer(0)]], device float* V [[buffer(1)]], device float* U [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id);
        if (!inFaceP(q, c, p)) { V[fi] = 0.0; continue; }
        if (solidAt(q, p) || solidAt(q - ax(c), p)) { V[fi] = 1.0; U[fi] = 0.0; continue; }
        if (q[c] == 0 || q[c] == NcOf(c, p)) {
            // 開いた口・底：水に触れていない所の速さは 0 に（重力が毎コマ足されて、そこだけ速くなり続け、口のまわりの水面を暴れさせていた）
            if (c == 3 && q[c] == 0 && openAt(q, p)) { V[fi] = phi[id] < 0.0 ? 1.0 : 0.0; if (V[fi] < 0.5) U[fi] = 0.0; continue; }
            if (c == 3 && q[c] == p.Nw && topOpenAt(q, p)) { V[fi] = phi[enc(q - ax(c), p.M)] < 0.0 ? 1.0 : 0.0; if (V[fi] < 0.5) U[fi] = 0.0; continue; }
            V[fi] = 1.0; continue;
        }
        int ia = enc(q - ax(c), p.M);
        V[fi] = (phi[ia] < 0.0 || phi[id] < 0.0) ? 1.0 : 0.0;
        if (V[fi] < 0.5) U[fi] = 0.0;   // 水から離れた空気の速さは 0 に（重力で速くなり続けて、水面を変な所から運んでこないように）
    }
}
// 空気側へ速さをのばす：決まっていない壁は、まわりの決まっている壁の平均に
kernel void extrap(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], device const float* V [[buffer(2)]], device float* VT [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id);
        UT[fi] = U[fi]; VT[fi] = V[fi];
        if (V[fi] > 0.5 || !inFaceP(q, c, p) || wallF(q, c, p)) continue;
        float s = 0.0, n = 0.0;
        for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) {
            int4 nb = q + sg * ax(d);
            if (!inFaceP(nb, c, p)) continue;
            int ni = c * MM + enc(nb, p.M);
            if (V[ni] > 0.5) { s += U[ni]; n += 1.0; }
        }
        if (n > 0.0) { UT[fi] = s / n; VT[fi] = 1.0; }
    }
}
// 水面までの距離を、ほんとうの距離に近づける（形は変えずに、坂を 1 にそろえる。数回だけ）
kernel void redist(device const float* phi [[buffer(0)]], device const float* phi0 [[buffer(1)]], device float* phiT [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.Mw; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); if (!inCellP(q, p)) { phiT[id] = phi[id]; return; }
    float f = phi[id], s0 = phi0[id] / sqrt(phi0[id] * phi0[id] + p.dx * p.dx), g2 = 0.0;
    for (int c = 0; c < 4; c++) {
        int4 lo = q - ax(c), hi = q + ax(c);
        float fl = inCellP(lo, p) ? phi[enc(lo, p.M)] : f, fh = inCellP(hi, p) ? phi[enc(hi, p.M)] : f;
        float a = (f - fl) / p.dx, b = (fh - f) / p.dx;
        if (s0 > 0.0) { float ap = max(a, 0.0), bm = min(b, 0.0); g2 += max(ap * ap, bm * bm); }
        else { float am = min(a, 0.0), bp = max(b, 0.0); g2 += max(am * am, bp * bp); }
    }
    // 水面のすぐそば（となりと φ₀ の符号がちがうマス）：水面の場所を動かさない直し方（Russo と Smereka 2000）。
    //   ふつうの式のままだと、とがった所（細い糸の先・しずく）が毎回少しずつ丸く削られて、はちみつの糸の先が流れる速さの 1/6 しか進まなかった（2026-11-27）
    float f0 = phi0[id], gg = 0.0; bool near = false;
    for (int c = 0; c < 4; c++) {
        int4 lo = q - ax(c), hi = q + ax(c);
        float l0 = inCellP(lo, p) ? phi0[enc(lo, p.M)] : f0, h0 = inCellP(hi, p) ? phi0[enc(hi, p.M)] : f0;
        if (l0 * f0 < 0.0 || h0 * f0 < 0.0) near = true;
        float m = max(max(abs(h0 - l0) * 0.5, abs(h0 - f0)), max(abs(f0 - l0), 1e-6 * p.dx));
        gg += m * m;
    }
    if (near) { float D = f0 * p.dx / sqrt(gg); phiT[id] = f - 0.3 * (sign(f0) * abs(f) - D); return; }
    phiT[id] = f - 0.3 * p.dx * s0 * (sqrt(g2) - 1.0);
}
"""

final class NS4 {
    static let wallLayers = 3                                         // 胞の水を描く時に平均する、かべから内への層の数
    /// かべから内への層の重み：横のかべは wallLayers 層の平均（かべにくっついたまくを描かない）。
    ///   重力の向きのかべ（ふた・床）は、いちばん外の 2 層から かべの所まで のばした値（φ₀ ＋ (φ₀ − φ₁)／2）：水面の高さの向きなので、平均するとずれる
    func layerWeights(_ a: Int, _ n: Int, _ ls: Int = 1) -> [Float] {
        let g = par.gvec, gl = simd_length(g)
        if gl > 1e-6 && abs(g[a]) > 0.5 * gl && n >= 2 { return [1.5, -0.5] }
        let nL = min(Self.wallLayers * ls, n); return [Float](repeating: 1 / Float(nL), count: nL)
    }
    static let noUpsample = ProcessInfo.processInfo.environment["NSNOUP"] != nil   // 確かめ：水面を細かくしない（前の見た目とくらべる）
    static var shared: (MTLDevice, MTLCommandQueue, [String: MTLComputePipelineState])? = nil   // 組み立てたシェーダー（みんなで使う）
    static var syncAll = false                                        // 確かめの絵：1 コマごとに計算の終わりを待つ（ちょうどその時刻の水に）
    let N: Int, M: Int, MM: Int, dev: MTLDevice, queue: MTLCommandQueue
    /// 上下にのばした計算の箱（2026-11-27）：w のマス Nw ＝ 下の空間 below ＋ 床の壁 1 ＋ 超立方体 N ＋ ふたの壁 1 ＋ 上の空間 above。
    ///   MM は超立方体の部分（M⁴、今までの描き方・体積はこれを使う）、MG は GPU の全部（M³·Mw）。boxLo：超立方体のいちばん下の層、boxOff：その GPU での始まり
    let Nw: Int, Mw: Int, MG: Int, boxLo: Int, boxOff: Int, below: Int, above: Int
    var extended: Bool { below > 0 || above > 0 }
    var upperStream: [NS4StreamLayer] = [], lowerStream: [NS4StreamLayer] = []
    private var ps: [String: MTLComputePipelineState] = [:]
    var U, UT, V, VT, phi, phiT, phi0, pr, rh, vW, vF: MTLBuffer
    var par = NS4Params()
    let H: Float
    var stepMs = 0.0                                                  // 1 歩の時間（ミリ秒、GPU）
    let lock = NSLock(); var inFlight = false, pendDt = 0.0, stepCount = 0
    var sliceKey = -1, sliceCache = NS4Mesh()
    var lastOutflow = 0.0                                             // 穴から出ていく量（世界の単位：1 秒あたりの 4 次元の体積）
    /// 水面だけ細かい φ（2 倍の格子、粗い格子が 16⁴ 以下の時だけ）：NF ＝ 2N、MF ＝ NF ＋ 1。fineFresh：次の 1 歩で粗い φ から作り直す
    static let noFine = ProcessInfo.processInfo.environment["NSFINE"] == nil   // 細かい水面は今は使わない（2026-11-26 にユーザーが「リアルすぎ・重い」で元に戻した）。NSFINE で試せる
    var phiF: MTLBuffer? = nil, phiFT: MTLBuffer? = nil, dnF: MTLBuffer? = nil, NF = 0, MF = 0, MMF = 0, fineFresh = true
    var phiFCPU: [Float] = [], phiFDisp: [Float] = []
    /// ブラックホールの井戸（見せる形、2026-11-26）：x 深さ D₀（世界の単位）・y 芯の太さ・z らせんの角度・w z の向きの のび。
    ///   描く φ（phiShow）＝ phiDisp ＋ D（柱ごと）：水面が D だけ下がる。D が水の深さより大きい所は、床まで空気（排水口まで届く空気の芯）
    var well = SIMD4<Float>(0, 0, 0, 1), phiShow: [Float] = []
    var cgIters = 0, cgSBuf: MTLBuffer? = nil, cgPartBuf: MTLBuffer? = nil    // 粘りの共役勾配法：くり返しの数（0 ならおまかせ）・小さな値の入れ物（S0 rr・S1 pAp・S2 新しい rr・S3 途中のいちばん大きい rr・S4 はじめの rr）・部分和
    func cgS() -> MTLBuffer? { if cgSBuf == nil { cgSBuf = dev.makeBuffer(length: 32, options: .storageModeShared) }; return cgSBuf }
    func cgPart() -> MTLBuffer? { if cgPartBuf == nil { cgPartBuf = dev.makeBuffer(length: (4 * MG / 32 + 64) * 4, options: .storageModeShared) }; return cgPartBuf }
    var viscStick: Float = 0                                               // ねばる液体が壁にくっつく強さ（0〜1。陰解法の粘りの時だけ使う）
    var phiCPU: [Float] = [], phiDisp: [Float] = [], lastVol = 0.0, resultID = 0, meshID = -1, meshCache = NS4Mesh(), meshBusy = false
    init?(N: Int = 32, H: Float = Float(OrigamiState.half), below: Int = 0, above: Int = 0) {
        // シェーダーと計算の組み立ては 1 回だけ（作り直すたびに組み立てると 1 回に何百ミリ秒もかかり、マス目の VBR の切りかえで絵が止まっていた）
        if Self.shared == nil {
            guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
            let lib: MTLLibrary
            do { lib = try d.makeLibrary(source: ns4Shader, options: nil) } catch { print("4D の水のシェーダーを作れなかった：", error); return nil }
            var pp: [String: MTLComputePipelineState] = [:]
            for n in ["advU", "macU", "advPhi", "jet", "force", "visc", "viscJ", "vFrac", "vApply", "vInit", "dotPart", "dotFin", "cgXR", "cgP", "cgS", "smoothPhi", "vortW", "vortF", "vortAdd", "rhs", "press", "proj", "valid", "extrap", "redist", "advPhiF", "downF", "combF"] {
                guard let f = lib.makeFunction(name: n), let p = try? d.makeComputePipelineState(function: f) else { print("4D の水の計算を作れなかった：", n); return nil }
                pp[n] = p
            }
            Self.shared = (d, q, pp)
        }
        guard let sh = Self.shared else { return nil }
        let d = sh.0; dev = d; queue = sh.1; ps = sh.2; self.N = N; M = N + 1; MM = M * M * M * M; self.H = H
        let ext = below > 0 || above > 0
        self.below = ext ? max(1, below) : 0; self.above = ext ? max(1, above) : 0
        Nw = ext ? self.below + N + 2 + self.above : N; Mw = Nw + 1; MG = M * M * M * Mw
        boxLo = ext ? self.below + 1 : 0; boxOff = boxLo * M * M * M
        par.Nw = Int32(Nw); par.Mw = Int32(Mw); par.wF = ext ? Int32(self.below) : -1; par.wL = ext ? Int32(self.below + 1 + N) : -1
        let MG = self.MG
        func buf(_ n: Int) -> MTLBuffer? { d.makeBuffer(length: n * 4, options: .storageModeShared) }
        guard let u = buf(4 * MG), let ut = buf(4 * MG), let v = buf(4 * MG), let vt = buf(4 * MG), let f = buf(MG), let ft = buf(MG), let f0 = buf(MG), let p = buf(MG), let r = buf(MG), let w = buf(MG), let fv = buf(4 * MG) else { return nil }
        vW = w; vF = fv
        U = u; UT = ut; V = v; VT = vt; phi = f; phiT = ft; phi0 = f0; pr = p; rh = r
        par.N = Int32(N); par.M = Int32(M); par.dx = 2 * H / Float(N)
        phiCPU = [Float](repeating: 1, count: MM)
        if N <= 16 && !Self.noFine && !ext {
            let nf = 2 * N, mf = nf + 1, mmf = mf * mf * mf * mf
            if let a = buf(mmf), let b = buf(mmf), let c = buf(MM) { phiF = a; phiFT = b; dnF = c; NF = nf; MF = mf; MMF = mmf }
        }
    }
    /// 水位 h（−1 空 〜 1 いっぱい）の静かな水に
    /// ほかの細かさの水を写しかえる（マス目の VBR）：水面までの距離 φ と流れの速さを、4 次元のなめらかなつなぎ（16 点）で読む。圧力は 0 から
    func copyResampled(from o: NS4) {
        o.lock.lock(); let busy = o.inFlight; o.lock.unlock()
        if busy { o.queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() } }
        reset(level: -1)
        let of = o.phi.contents().bindMemory(to: Float.self, capacity: o.MG) + o.boxOff, ou0 = o.U.contents().bindMemory(to: Float.self, capacity: 4 * o.MG)
        let f = phi.contents().bindMemory(to: Float.self, capacity: MG) + boxOff, u0 = U.contents().bindMemory(to: Float.self, capacity: 4 * MG)
        let r = o.par.dx / par.dx, oN = o.N, oM = o.M
        // 古いマス目の値を、古い格子の座標 g（マスの真ん中が整数）で 16 点のつなぎ。hi：その向きの上の端（φ は N−1、速さの成分 c の向きは N）
        func sample(_ base: UnsafeMutablePointer<Float>, _ g: SIMD4<Float>, _ hi: SIMD4<Int>) -> Float {
            var i0 = SIMD4<Int>(0, 0, 0, 0), fr = SIMD4<Float>(0, 0, 0, 0)
            for a in 0..<4 { let x = max(0, min(Float(hi[a]), g[a])), b = min(hi[a] - 1, max(0, Int(x.rounded(.down)))); i0[a] = b; fr[a] = x - Float(b) }
            var s: Float = 0
            for b in 0..<16 {
                var w: Float = 1; var q = i0
                for a in 0..<4 { let on = (b >> a) & 1 == 1; w *= on ? fr[a] : 1 - fr[a]; if on { q[a] += 1 } }
                if w > 0 { s += w * base[((q.w * oM + q.z) * oM + q.y) * oM + q.x] }
            }
            return s
        }
        for l in 0..<N { for k in 0..<N { for j in 0..<N { for i in 0..<N {
            let g = (SIMD4<Float>(Float(i), Float(j), Float(k), Float(l)) + 0.5) / r - 0.5
            f[((l * M + k) * M + j) * M + i] = sample(of, g, SIMD4(repeating: oN - 1))
        } } } }
        for c in 0..<4 {
            for l in 0..<M { for k in 0..<M { for j in 0..<M { for i in 0..<M {
                var q = SIMD4<Int>(i, j, k, l); var ok = true
                for a in 0..<4 { if a == c { if q[a] > N { ok = false } } else if q[a] >= N { ok = false } }
                if !ok { continue }
                var g = (SIMD4<Float>(Float(i), Float(j), Float(k), Float(l)) + 0.5) / r - 0.5
                g[c] = Float(q[c]) / r                                         // 速さの成分 c は、その向きの壁の上（マスの真ん中ではない）
                var hi = SIMD4<Int>(repeating: oN - 1); hi[c] = oN
                u0[c * MG + boxOff + ((l * M + k) * M + j) * M + i] = sample(ou0 + c * o.MG + o.boxOff, g, hi)
                q = .zero
            } } } }
        }
        phiCPU = Array(UnsafeBufferPointer(start: f, count: MM)); phiDisp = phiCPU; phiShow = []; fineFresh = true; phiFCPU = []; phiFDisp = []; lastVol = volumeOf(phiCPU).0; resultID += 1
    }
    func reset(level h: Float) {
        lock.lock(); let busy = inFlight; lock.unlock()
        if busy { queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() } }
        let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MG); for i in 0..<(4 * MG) { u[i] = 0 }
        let p = pr.contents().bindMemory(to: Float.self, capacity: MG); for i in 0..<MG { p[i] = 0 }
        let fg = phi.contents().bindMemory(to: Float.self, capacity: MG)
        let lev = (h + 1) * 0.5 * Float(N)                              // 水面の高さ（格子の単位、超立方体の下の端から）
        for L in 0..<Mw { for k in 0..<M { for j in 0..<M { for i in 0..<M {
            let l = L - boxLo, inBox = l >= 0 && l < N
            let wall = extended && (L == Int(par.wF) || L == Int(par.wL))
            fg[((L * M + k) * M + j) * M + i] = wall ? par.dx : (h <= -1 || (extended && !inBox && L < Nw)) ? 2 * H : (Float(l) + 0.5 - lev) * par.dx   // 空：どこも遠く離れた空気。上と下の空間も空気
        } } } }
        let f = fg + boxOff
        phiCPU = Array(UnsafeBufferPointer(start: f, count: MM)); phiDisp = phiCPU; phiShow = []; fineFresh = true; phiFCPU = []; phiFDisp = []; lastVol = h <= -1 ? 0 : volumeOf(phiCPU).0; resultID += 1
    }
    @inline(__always) func at(_ i: Int, _ j: Int, _ k: Int, _ l: Int) -> Int { ((l * M + k) * M + j) * M + i }
    /// 水の 4 次元の体積（世界の単位）と、水面の大きさ（体積を合わせる時に使う）
    func volume() -> (Double, Double) {
        let f = phi.contents().bindMemory(to: Float.self, capacity: MG) + boxOff, e = Double(par.dx) * 1.5
        let dv = pow(Double(par.dx), 4)
        var vol = 0.0, area = 0.0
        for l in 0..<N { for k in 0..<N { for j in 0..<N { let b = at(0, j, k, l); for i in 0..<N {
            let x = Double(f[b + i])
            if x < -e { vol += 1 } else if x < e { vol += 0.5 - 0.5 * x / e - sin(.pi * x / e) / (2 * .pi); area += (1 + cos(.pi * x / e)) / (2 * e) }
        } } } }
        return (vol * dv, area * dv)
    }
    /// 1 歩すすめる。target：水の体積（世界の単位）を合わせる値（nil なら合わせない）
    func step(dt: Float, iters: Int = 60, target: Double? = nil, redistEvery: Int = 0) {
        let lim = 0.1 * Double(par.dx)
        if let t = target { let (v, a) = volume(); par.shift = a > 1e-6 ? Float(max(-lim, min(lim, 0.5 * (v - t) / a))) : 0 } else { par.shift = 0 }
        encode(dt: dt, iters: iters, redistEvery: redistEvery, wait: true)
    }
    func encode(dt: Float, iters: Int, redistEvery: Int, wait: Bool) {
        par.dt = dt
        guard let cb = queue.makeCommandBuffer() else { return }
        func run(_ name: String, _ bufs: [MTLBuffer], _ p0: NS4Params? = nil, count: Int? = nil, fz: SIMD2<Int32>? = nil, ex: SIMD4<Float>? = nil, tg: Int? = nil) {
            guard let e = cb.makeComputeCommandEncoder(), let pp = ps[name] else { return }
            e.setComputePipelineState(pp)
            for (i, b) in bufs.enumerated() { e.setBuffer(b, offset: 0, index: i) }
            var p = p0 ?? par; e.setBytes(&p, length: MemoryLayout<NS4Params>.stride, index: bufs.count)
            if var z = fz { e.setBytes(&z, length: MemoryLayout<SIMD2<Int32>>.stride, index: bufs.count + 1) }
            if var z = ex { e.setBytes(&z, length: MemoryLayout<SIMD4<Float>>.stride, index: bufs.count + 1) }
            e.dispatchThreads(MTLSize(width: count ?? MG, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: tg ?? min(256, pp.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
            e.endEncoding()
        }
        for c in 0..<4 { var p = par; p.c = Int32(c); run("advU", [U, UT], p) }
        let mac = par.ex2.y > 0.5                                           // MacCormack（見かけの粘りを減らす）：結果は vF に（このあと渦の強調が上書きするので、借りても大丈夫）
        if mac { for c in 0..<4 { var p = par; p.c = Int32(c); run("macU", [U, UT, vF], p) } }
        let fine = phiF != nil, fz = SIMD2<Int32>(Int32(NF), fineFresh ? 1 : 0)
        if fine, let a = phiF, let b = phiFT, !fineFresh { run("advPhiF", [U, a, b], count: MMF, fz: fz) }   // 細かい φ も、粗い φ と同じ流れで運ぶ
        run("advPhi", [U, phi, phiT]); swap(&phi, &phiT)
        if mac { swap(&U, &vF) } else { swap(&U, &UT) }
        run("jet", [U, phi])
        var pf = par; pf.shift = 0; pf.swirlOn = 0; run("force", [U], pf)
        let alpha = par.nu * dt / (par.dx * par.dx)
        if alpha > 0.1, let sb = cgS(), let pb = cgPart() {
            // ねばる液体（はちみつなど）：Batty 式の粘りを共役勾配法で（はじめの値は u*）。借りる入れ物：重み rh・x UT・r vF・p V・Ap VT（どれも このあと上書きされる）
            //   前のヤコビ法（くり返し 40 回まで）は、短いでこぼこにしか効かず、長い糸ではほとんど ねばらなかった（はちみつの糸が自由落下に近い速さで落ちた。2026-11-27）
            let nIt = cgIters > 0 ? cgIters : min(120, 16 + Int((8 * alpha.squareRoot()).rounded(.up))), vx = SIMD4<Float>(alpha, 0, 0, 0)
            let n4 = 4 * MG, tg = min(256, ps["dotPart"]?.maxTotalThreadsPerThreadgroup ?? 256), nP = (n4 + tg - 1) / tg
            let fin = min(1024, ps["dotFin"]?.maxTotalThreadsPerThreadgroup ?? 256)
            if let bl = cb.makeBlitCommandEncoder() { bl.copy(from: U, sourceOffset: 0, to: UT, destinationOffset: 0, size: n4 * 4); bl.fill(buffer: sb, range: 0..<32, value: 0); bl.endEncoding() }
            func dot(_ a: MTLBuffer, _ b: MTLBuffer, _ slot: Int32) {
                run("dotPart", [a, b, pb], count: n4, fz: SIMD2<Int32>(Int32(n4), 0), tg: tg)
                run("dotFin", [pb, sb], count: fin, fz: SIMD2<Int32>(Int32(nP), slot), tg: fin)
            }
            run("vFrac", [phi, rh])
            run("vApply", [UT, VT, rh], ex: SIMD4<Float>(alpha, 1, 0, 0)); run("vInit", [U, VT, vF, V, rh])
            dot(vF, vF, 0); dot(vF, vF, 4)                                         // S4：はじめの残り（確かめ用）
            for _ in 0..<nIt {
                run("vApply", [V, VT, rh], ex: vx); dot(V, VT, 1)
                run("cgXR", [UT, vF, V, VT, sb], count: n4); dot(vF, vF, 2)
                run("cgP", [vF, V, sb], count: n4); run("cgS", [sb], count: 1)
            }
            swap(&U, &UT)
        } else if par.nu > 0 { run("visc", [U, UT, phi]); swap(&U, &UT) }
        if par.vort > 0 { run("vortW", [U, phi, vW]); run("vortF", [U, phi, vW, vF]); run("vortAdd", [U, vF, phi]) }
        if par.smooth > 0 { run("smoothPhi", [phi, phiT]); swap(&phi, &phiT) }
        run("rhs", [U, phi, rh, pr])
        for it in 0..<iters { var p = par; p.par = Int32(it & 1); run("press", [pr, phi, rh], p) }
        run("proj", [U, pr, phi])
        run("valid", [phi, V, U])
        for _ in 0..<3 { run("extrap", [U, UT, V, VT]); swap(&U, &UT); swap(&V, &VT) }
        if redistEvery > 0 {
            if let bl = cb.makeBlitCommandEncoder() { bl.copy(from: phi, sourceOffset: 0, to: phi0, destinationOffset: 0, size: MG * 4); bl.endEncoding() }
            for _ in 0..<redistEvery { run("redist", [phi, phi0, phiT]); swap(&phi, &phiT) }
        }
        if fine, let a = phiF, let b = phiFT, let c = dnF {
            if !fineFresh { run("downF", [b, c], fz: fz) }
            run("combF", [b, c, phi, a], count: MMF, fz: fz); fineFresh = false
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        if wait { cb.commit(); cb.waitUntilCompleted(); stepMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000; return }
        lock.lock(); inFlight = true; lock.unlock()
        cb.addCompletedHandler { [weak self] c in
            guard let self else { return }
            self.lock.lock(); self.inFlight = false; self.stepMs = (c.gpuEndTime - c.gpuStartTime) * 1000; self.lock.unlock()
        }
        cb.commit()
    }
    /// 確かめ：細かい水面の、細かい形の大きさ。水面の近く（|φ| < 粗いマス 1 つ）で、細かい φ と、粗い φ をつないだ値との差の RMS（粗いマスの単位）
    func fineDetailStats() -> String {
        guard MF > 0, phiFCPU.count == MMF else { return String(format: "細かい水面なし・1 歩 %.2f ミリ秒", stepMs) }
        var sq = 0.0, cnt = 0.0, mx: Float = 0
        let dx = par.dx
        func coarse(_ g: SIMD4<Float>) -> Float {
            let b0 = SIMD4<Float>(g.x.rounded(.down), g.y.rounded(.down), g.z.rounded(.down), g.w.rounded(.down)), fr = g - b0
            var c: Float = 0
            for o in 0..<16 {
                var w: Float = 1; var q = [0, 0, 0, 0]
                for a in 0..<4 { let on = (o >> a) & 1 == 1; w *= on ? fr[a] : 1 - fr[a]; q[a] = max(0, min(N - 1, Int(b0[a]) + (on ? 1 : 0))) }
                c += w * phiCPU[at(q[0], q[1], q[2], q[3])]
            }
            return c
        }
        for l in 1..<(NF - 1) { for k in 1..<(NF - 1) { for j in 1..<(NF - 1) { for i in 1..<(NF - 1) {
            let v = phiFCPU[((l * MF + k) * MF + j) * MF + i]; if abs(v) > dx { continue }
            let g = SIMD4<Float>(Float(i), Float(j), Float(k), Float(l)) * 0.5 - 0.25
            let d = (v - coarse(g)) / dx; sq += Double(d * d); cnt += 1; mx = max(mx, abs(d))
        } } } }
        return String(format: "細かい形：RMS %.3f・いちばん大きい %.2f（粗いマスの単位）・1 歩 %.2f ミリ秒", (sq / max(1, cnt)).squareRoot(), mx, stepMs)
    }
    /// ブラックホールの井戸を、描く φ に足す。深さ D(r) ＝ D₀／(1 ＋ r²／r_c²) × らせん（r：排水口の真上の線からの 3 次元のきょり。z の向きには のばす）。
    ///   4D の水面は 3 次元なので、x‐y の面で回る渦の芯は z の向きの線（とい）になり、吸いこむ流れは x・y・z の 3 方向から 1 点に集まる。
    ///   その 2 つを合わせて、排水口の真上がいちばん深い、z に少し細長い井戸。らせん（腕 2 本の対数らせん）は x‐y の面で回る
    func makeShow() {
        guard well.x > 1e-4, phiDisp.count == MM else { if !phiShow.isEmpty { phiShow = [] }; return }
        let D0 = well.x, rc = max(1e-3, well.y), ph = well.z, ez = max(1, well.w), dx = par.dx
        var Dc = [Float](repeating: 0, count: N * N * N)
        for k in 0..<N { for j in 0..<N { for i in 0..<N {
            let x = -H + (Float(i) + 0.5) * dx, y = -H + (Float(j) + 0.5) * dx, z = (-H + (Float(k) + 0.5) * dx) / ez
            let r2 = x * x + y * y + z * z, r = r2.squareRoot()
            let sp = 1 + 0.4 * sin(2 * atan2(y, x) + 2.6 * log(r / rc + 0.15) - 3.2 * ph)
            Dc[(k * N + j) * N + i] = D0 / (1 + r2 / (rc * rc)) * sp
        } } }
        phiShow = phiDisp
        phiShow.withUnsafeMutableBufferPointer { F in
            for l in 0..<N { for k in 0..<N { for j in 0..<N { let b = at(0, j, k, l), c = (k * N + j) * N; for i in 0..<N { F[b + i] += Dc[c + i] } } } }
        }
    }
    /// x‐y の面で回す小さなゆらぎ（いちどだけ）
    func addSwirl(_ s: Float) {
        guard let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder(), let pp = ps["force"] else { return }
        var p = par; p.g = 0; p.dt = 0; p.swirlOn = 1; p.shift = s
        e.setComputePipelineState(pp); e.setBuffer(U, offset: 0, index: 0); e.setBytes(&p, length: MemoryLayout<NS4Params>.stride, index: 1)
        e.dispatchThreads(MTLSize(width: MG, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)); e.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
    }
    /// 速さのいちばん大きい値（世界の単位）
    var capVolCompat: Double { pow(2 * Double(H), 4) }
    /// 水の厚み（マスごと）：向き a の 1 本の列で、水のマスが続く長さ（世界の長さ）。結果が変わった時だけ作り直す（1 回 N⁴）。
    ///   前は描くたびに点ごとに列をたどっていて、24⁴・32⁴ では 1 コマに何秒もかかって止まって見えた（2026-11-26）
    private var thickKey = -1, thickAxis = -1, thickField: [Float] = []
    func thicknessField(axis a: Int) -> [Float] {
        let NN = N * N * N * N
        if thickKey == resultID && thickAxis == a && thickField.count == NN { return thickField }
        var out = [Float](repeating: 0, count: NN)
        if phiCPU.count == MM {
            let cs = [1, N, N * N, N * N * N], oth = (0..<4).filter { $0 != a }
            phiCPU.withUnsafeBufferPointer { F in
                for x in 0..<N { for y in 0..<N { for z in 0..<N {
                    var q = SIMD4<Int>(0, 0, 0, 0); q[oth[0]] = x; q[oth[1]] = y; q[oth[2]] = z
                    var run = 0
                    for t in 0...N {
                        var wet = false
                        if t < N { q[a] = t; wet = F[((q.w * M + q.z) * M + q.y) * M + q.x] < 0 }
                        if wet { run += 1; continue }
                        if run > 0 {
                            let L = Float(run) * par.dx
                            for s in (t - run)..<t { q[a] = s; out[q.x * cs[0] + q.y * cs[1] + q.z * cs[2] + q.w * cs[3]] = L }
                        }
                        run = 0
                    }
                } } }
            }
        }
        thickField = out; thickKey = resultID; thickAxis = a
        return out
    }
    func maxSpeed() -> Float {
        let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MG), f = phi.contents().bindMemory(to: Float.self, capacity: MG)
        var m: Float = 0
        for i in 0..<MG where f[i] < 0 { for c in 0..<4 { m = max(m, abs(u[c * MG + i])) } }
        return m
    }
    /// 水面の高さ（w、格子の単位）：x・y・z のマス (i, j, k) の柱で、水から空気に変わる所
    func surfaceW(_ i: Int, _ j: Int, _ k: Int) -> Float {
        let f = phi.contents().bindMemory(to: Float.self, capacity: MG) + boxOff
        for l in 0..<(N - 1) {
            let a = f[at(i, j, k, l)], b = f[at(i, j, k, l + 1)]
            if a < 0 && b >= 0 { return Float(l) + 0.5 + a / (a - b) }
        }
        return f[at(i, j, k, 0)] >= 0 ? 0 : Float(N)
    }
    /// 確かめ（--ns4test）：静かな水・体積・排水口の渦
    static func selfTest() {
        guard let s = NS4() else { print("作れなかった"); return }
        let N = s.N, h = N / 2
        s.reset(level: 0)
        let (v0, _) = s.volume()
        print(String(format: "はじめの体積 %.4f（本当は 8H⁴ ＝ %.4f）", v0, 8 * pow(Double(s.H), 4)))
        for n in 0..<120 { s.step(dt: 1.0 / 60, target: v0, redistEvery: n % 4 == 0 ? 2 : 0) }
        let (v1, _) = s.volume()
        print(String(format: "静かな水 2 秒：体積 %.4f（%+.2f%%）・いちばん速い %.4f・1 歩 %.2f ミリ秒", v1, (v1 / v0 - 1) * 100, s.maxSpeed(), s.stepMs))
        print(String(format: "  水面の高さ 真ん中 %.3f・角 %.3f（格子の単位、平らなら %d）", s.surfaceW(h, h, h), s.surfaceW(1, 1, 1), h))
        // 排水口（半分の幅 0.58×H ＝ 格子で 0.58×N/2）を開けて、x‐y の小さな回転を入れて抜く
        s.addSwirl(0.15)
        s.par.hole = 0.58 * Float(N) / 2 * 0.5
        var t = 0.0, tgt = v1
        for n in 0..<600 {
            let (v, _) = s.volume()
            tgt = min(tgt, v)
            s.step(dt: 1.0 / 60, target: tgt, redistEvery: n % 4 == 0 ? 2 : 0); t += 1.0 / 60
            if n % 60 == 59 {
                let (vv, _) = s.volume()
                print(String(format: "排水口 %.0f 秒：体積 %.3f・いちばん速い %.3f・水面 真ん中 %.2f・まわり %.2f・角 %.2f・1 歩 %.2f ミリ秒", t, vv, s.maxSpeed(), s.surfaceW(h, h, h), s.surfaceW(h + 4, h, h), s.surfaceW(1, 1, 1), s.stepMs))
            }
        }
    }
}

/// 上と下の空間の水の筋（層ごと）：w（世界の単位、層の真ん中）・x‐y‐z の真ん中・同じ量の 3 次元の玉の半径
struct NS4StreamLayer { var w: Float; var c: SIMD3<Float>; var r: Float }
// ---- 画面で動かす：計算は裏で（GPU が終わったら次を出す）、描くのは終わった分のうつし ----
extension NS4 {
    /// 上と下の空間（と、ふた・床の穴の層）の水を、層ごとの「筋の真ん中と太さ」にまとめる（描く用。4 次元の筋は切り口が 3 次元の玉なので、玉の半径で）
    func readStreams(_ fg: UnsafeMutablePointer<Float>) {
        let dx = par.dx, dx3 = dx * dx * dx, M3 = M * M * M
        var lastN: Float = 0
        func layer(_ L: Int) -> NS4StreamLayer? {
            var n: Float = 0, sx = SIMD3<Float>(0, 0, 0)
            defer { lastN = n }
            let b = L * M3
            for k in 0..<N { for j in 0..<N { let r = b + (k * M + j) * M; for i in 0..<N {
                let f = fg[r + i]; if f >= 0.5 * dx { continue }
                let a = min(1, 0.5 - f / dx); n += a; sx += a * SIMD3<Float>(Float(i), Float(j), Float(k))
            } } }
            if n < 0.3 { return nil }
            let c = (sx / n + 0.5) * dx - H
            return NS4StreamLayer(w: -H + (Float(L - boxLo) + 0.5) * dx, c: c, r: pow(3 * n * dx3 / (4 * .pi), 1.0 / 3.0))
        }
        var up: [NS4StreamLayer] = [], dn: [NS4StreamLayer] = []
        // 上：天井から下へ。ふたの穴を通って、超立方体の中も、水面（その層の水が多くなる所）の手前まで（筋のまま落ちている所）
        //   箱の中は、ふたの穴からつながっている所だけ（上の層の筋のすぐ下で、真ん中が近い）。水面の上に残った しずくは筋にしない
        var lastL = -9, lastC = SIMD3<Float>(0, 0, 0)
        for L in stride(from: Nw - 1, through: Int(par.wL), by: -1) { if let s = layer(L) { up.append(s); lastL = L; lastC = s.c } }
        let big = 0.15 * Float(N * N * N)
        if lastL == Int(par.wL) {
            for L in stride(from: Int(par.wL) - 1, through: boxLo, by: -1) {
                guard let s = layer(L), lastN <= big, simd_length(s.c - lastC) < 3 * dx else { break }
                up.append(s); lastC = s.c
            }
        }
        // 下：床の穴から下へ
        for L in stride(from: Int(par.wF), through: 0, by: -1) { if let s = layer(L) { dn.append(s) } }
        upperStream = up; lowerStream = dn
    }
    /// 1 コマ分：前の歩が終わっていれば、結果を写して（体積も数えて）次の歩を出す。終わっていなければ時間をためておく
    func tick(_ dt: Double, target: Double?, keepAir: Bool = false) {   // keepAir：空気が少ない時（86% 以上）は水を足す向きに合わせない（遊ぶモード：開いた口の下のうすい空気の層を守る）
        if Self.syncAll { queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() }; lock.lock(); inFlight = false; lock.unlock() }
        lock.lock(); let busy = inFlight; lock.unlock()
        pendDt += dt
        if busy { return }
        // 終わった結果を写す（描く用）
        let fg = phi.contents().bindMemory(to: Float.self, capacity: MG), f = fg + boxOff
        phiCPU.withUnsafeMutableBufferPointer { b in _ = memcpy(b.baseAddress!, f, MM * 4) }
        if extended { readStreams(fg) }
        let (v, a) = volumeOf(phiCPU)
        lastVol = v; resultID += 1
        // 穴（排水口・底の全開）から出ていく量：底の壁（w の下の端）の、開いている所の下向きの速さ × 面の広さ（4D では 3 次元の体積 dx³）
        do {
            let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MG) + boxOff, h = Float(N) * 0.5, dx3 = Double(par.dx * par.dx * par.dx)
            var q = 0.0
            if par.open != 0 || par.hole > 0 {
                for k in 0..<N { for j in 0..<N { for i in 0..<N {
                    if par.open == 0 { if abs(Float(i) + 0.5 - h) >= par.hole || abs(Float(j) + 0.5 - h) >= par.hole || abs(Float(k) + 0.5 - h) >= par.hole { continue } }
                    let id = at(i, j, k, 0)
                    if phiCPU[id] < 0 { q += Double(max(0, -u[3 * MG + id])) * dx3 }
                } } }
            }
            lastOutflow += (q - lastOutflow) * 0.3                         // 少しなめらかに
        }
        // 描く水面：前の結果と半分ずつまぜて、ゆるやかに（細かい粒がちらちら出たり消えたりしないように）
        if phiDisp.count != MM { phiDisp = phiCPU } else { phiCPU.withUnsafeBufferPointer { s in phiDisp.withUnsafeMutableBufferPointer { d in for i in 0..<MM { d[i] = 0.5 * d[i] + 0.5 * s[i] } } } }
        if let pf = phiF, !fineFresh {                                      // 細かい φ も写す（描く用）
            if phiFCPU.count != MMF { phiFCPU = [Float](repeating: 1, count: MMF) }
            let src = pf.contents().bindMemory(to: Float.self, capacity: MMF)
            phiFCPU.withUnsafeMutableBufferPointer { b in _ = memcpy(b.baseAddress!, src, MMF * 4) }
            if phiFDisp.count != MMF { phiFDisp = phiFCPU } else { phiFCPU.withUnsafeBufferPointer { s in phiFDisp.withUnsafeMutableBufferPointer { d in for i in 0..<MMF { d[i] = 0.5 * d[i] + 0.5 * s[i] } } } }
        } else { phiFDisp = [] }
        makeShow()
        let d = Float(min(1.0 / 30, pendDt)); pendDt = 0
        // 体積を合わせるずれ：1 歩でマスの 1/10 まで（水面が小さい時に大きくずらすと、空気と水がぐちゃぐちゃになる）
        // 差が小さい時（箱の 0.4% 以内）は合わせない。空気が少ない時（86% 以上）は水を足す向きに合わせない
        //   （うすい空気の層はまるごと水面の近くに入るので、少しずつ足し続けると空気の層が消えて、箱が 100% 水になり、もう抜けなくなる）
        let lim = 0.1 * Double(par.dx), box = pow(2 * Double(H), 4)
        if let t = target, a > 1e-6, abs(v - t) > 0.004 * box, !(keepAir && v < t && v > 0.86 * box) { par.shift = Float(max(-lim, min(lim, 0.5 * (v - t) / a))) } else { par.shift = 0 }
        stepCount += 1
        encode(dt: d, iters: N <= 24 ? 70 : 40, redistEvery: stepCount % 2 == 0 ? 2 : 0, wait: false)
    }
    /// 体積（世界の単位）と水面の大きさ（写した φ から）
    func volumeOf(_ f: [Float]) -> (Double, Double) {
        let e = Double(par.dx) * 1.5, dv = pow(Double(par.dx), 4)
        var vol = 0.0, area = 0.0
        f.withUnsafeBufferPointer { p in
            for l in 0..<N { for k in 0..<N { for j in 0..<N { let b = at(0, j, k, l); for i in 0..<N {
                let x = Double(p[b + i])
                if x < -e { vol += 1 } else if x < e { vol += 0.5 - 0.5 * x / e - sin(.pi * x / e) / (2 * .pi); area += (1 + cos(.pi * x / e)) / (2 * e) }
            } } } }
        }
        return (vol * dv, area * dv)
    }
    /// 写した φ の、4D のマス (i, j, k, l) の値（外は空気）
    @inline(__always) func phiAt(_ i: Int, _ j: Int, _ k: Int, _ l: Int) -> Float {
        guard i >= 0, j >= 0, k >= 0, l >= 0, i < N, j < N, k < N, l < N else { return par.dx }
        return phiCPU[at(i, j, k, l)]
    }
    /// 水面の高さ（w、世界の単位）：x・y・z の点 u（−1〜1）の柱で、水から空気に変わる所
    func surfaceWorld(_ u: SIMD3<Double>) -> Double {
        let n = Double(N), i = max(0, min(N - 1, Int((u.x + 1) / 2 * n))), j = max(0, min(N - 1, Int((u.y + 1) / 2 * n))), k = max(0, min(N - 1, Int((u.z + 1) / 2 * n)))
        // 下から見て、はじめて水から空気に変わる所（宙に浮いた水＝入れたばかりの水やしぶきは数えない。上の水を数えると、入れる所が上へのぼっていく）
        if phiAt(i, j, k, 0) >= 0 { return -Double(H) }
        for l in 0..<(N - 1) {
            let a = phiAt(i, j, k, l), b = phiAt(i, j, k, l + 1)
            if a < 0 && b >= 0 { return -Double(H) + (Double(l) + 0.5 + Double(a / (a - b))) * Double(par.dx) }
        }
        return Double(H)
    }
}

/// 水の皮の三角形（4D の点のまま。描く時に今の向きで写す）：3 点ずつ並べた点と、三角形ごとの種類（1 水面・0 壁に触れている面）
struct NS4Mesh { var p: [SIMD4<Float>] = []; var t1: [SIMD4<Float>] = []; var t2: [SIMD4<Float>] = []; var kind: [Float] = []
    var idx: [Int32] = [], up: [SIMD4<Float>] = [], ut1: [SIMD4<Float>] = [], ut2: [SIMD4<Float>] = []   // まとめた点（idx：三角形の角 → 点の番号）
}
struct NS4VKey: Hashable { var x, y, z, w: Int32; var s: Bool }   // t1・t2：点ごとの、水面に沿った 2 つの向き（4D。なめらかな面の向きを出す。0 なら三角形の向き）

extension NS4 {
    /// 水の皮：今の結果のものがあればそれを、なければ裏で作り始めて、前のものを返す（確かめの絵の時は、その場で作る）
    func wallMesh() -> NS4Mesh {
        lock.lock(); let have = meshCache, hid = meshID, busy = meshBusy, rid = resultID; lock.unlock()
        if hid == rid { return have }
        if Self.syncAll { let m = buildMesh(phiShow.count == MM ? phiShow : phiDisp.count == MM ? phiDisp : phiCPU, fine: phiFDisp.count == MMF && MMF > 0 ? phiFDisp : nil); lock.lock(); meshCache = m; meshID = rid; lock.unlock(); return m }
        if !busy {
            lock.lock(); meshBusy = true; lock.unlock()
            let snap = phiShow.count == MM ? phiShow : phiDisp.count == MM ? phiDisp : phiCPU   // 写しを持っておく（次の結果は別の配列に書かれる）
            let snapF: [Float]? = phiFDisp.count == MMF && MMF > 0 ? phiFDisp : nil
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let m = self.buildMesh(snap, fine: snapF)
                self.lock.lock(); self.meshCache = m; self.meshID = rid; self.meshBusy = false; self.lock.unlock()
            }
        }
        return have
    }
    /// 四面体 1 つの水面：内側（水）の印 mask（4 ビット）ごとの、辺（四面体の点の番号の組、はじめが水）
    static let tetCases: [[(Int, Int)]] = (0..<16).map { m in
        let ins = (0..<4).filter { m & (1 << $0) != 0 }, outs = (0..<4).filter { m & (1 << $0) == 0 }
        if ins.isEmpty || outs.isEmpty { return [] }
        if ins.count == 1 { return [(ins[0], outs[0]), (ins[0], outs[1]), (ins[0], outs[2])] }
        if outs.count == 1 { return [(ins[0], outs[0]), (ins[1], outs[0]), (ins[2], outs[0])] }
        return [(ins[0], outs[0]), (ins[0], outs[1]), (ins[1], outs[1]), (ins[0], outs[0]), (ins[1], outs[1]), (ins[1], outs[0])]
    }
    /// 水の皮：(1) 8 つの壁の胞（±x・±y・±z・±w の立方体）の中の水面（φ ＝ 0）を四面体で取り出す（胞の縁では外を同じ値にして、水面を縁まで届かせる）。
    ///   (2) 超立方体の 24 枚の正方形の面の、水に触れている所を、行ごとにまとめた四角で（細かい三角形にしない）
    /// fine：水面だけ細かい φ（2 倍の格子）があれば、そちらから水面を取り出す（なめらかにつなぐ 2 倍の細かさのかわりに、本当に細かい値）
    func buildMesh(_ phiSnap: [Float], fine: [Float]? = nil) -> NS4Mesh {
        if let f = fine, MF > 0 { return buildMeshOn(f, n: NF, M: MF, dx: par.dx / 2, ls: 2) }
        return buildMeshOn(phiSnap, n: N, M: M, dx: par.dx, ls: 1)
    }
    /// ls：粗いマス 1 つが何マスか（かべから内へ平均する層の数を、粗いマスで同じ深さにそろえる）
    func buildMeshOn(_ phiSnap: [Float], n: Int, M: Int, dx: Float, ls: Int) -> NS4Mesh {
        var out = NS4Mesh()
        out.p.reserveCapacity(120_000); out.kind.reserveCapacity(40_000)
        let Hf = H
        @inline(__always) func coord(_ i: Int) -> Float { i < 0 ? -Hf : i >= n ? Hf : -Hf + (Float(i) + 0.5) * dx }
        let tetF: [Int] = [0, 1, 3, 7, 0, 3, 2, 7, 0, 2, 6, 7, 0, 6, 4, 7, 0, 4, 5, 7, 0, 5, 1, 7]
        let cases = Self.tetCases
        phiSnap.withUnsafeBufferPointer { F in
            let M1 = M, M2 = M * M, M3 = M * M * M
            var c = [Float](repeating: 0, count: 8), cpv = [SIMD3<Float>](repeating: .zero, count: 8), cg = [SIMD3<Float>](repeating: .zero, count: 8)
            // (1) 水面
            for a in 0..<4 { for s in [-1, 1] {
                let oth = (0..<4).filter { $0 != a }, fixedIdx = s < 0 ? 0 : n - 1
                let strides = [1, M1, M2, M3], base = fixedIdx * strides[a], s0 = strides[oth[0]], s1 = strides[oth[1]], s2 = strides[oth[2]]
                let ia = a, io0 = oth[0], io1 = oth[1], io2 = oth[2], fw = Float(s) * Hf
                @inline(__always) func pos4(_ q: SIMD3<Float>) -> SIMD4<Float> { var r = SIMD4<Float>(0, 0, 0, 0); r[ia] = fw; r[io0] = q.x; r[io1] = q.y; r[io2] = q.z; return r }
                @inline(__always) func dir4(_ q: SIMD3<Float>) -> SIMD4<Float> { var r = SIMD4<Float>(0, 0, 0, 0); r[io0] = q.x; r[io1] = q.y; r[io2] = q.z; return r }
                // 水面をなめらかに：胞のマスの値（水面までの距離 φ）を、なめらかな曲線（キャットマル–ロム）でつないで 2 倍細かくしてから水面を取り出す。
                //   粗いマス（12⁴・16⁴）のままだと、水面のふちや波の山が角ばった三角形に見えていた（2026-11-26）。24⁴ 以上はそのまま
                let up = ls == 1 && n <= 16 && !Self.noUpsample, mf = up ? 2 * n - 1 : n   // 24⁴ 以上は細かくしない（もともと細かい。三角形が増えすぎて重くなる）
                // かべから内へ wallLayers 層の平均で描く：かべにいちばん近い 1 層だけだと、計算でかべにくっついて残るうすい水のまくまで描いて、
                //   まん中の水より遅れて引き、はがれた時に一気に下がって見えていた（2026-11-26）。平らな水面なら、どの層も同じ高さなので平均しても変わらない
                //   ただし ふた・床（内への向きが重力の向き）では平均しない：水面の高さの向きに平均すると、1 層ぶん水の側にずれて、
                //   水面がふたに届く前に、ふたの胞がまるごと水で埋まって見えた（2026-11-26）。そこは、かべの所まで のばした値（外挿）で
                let inward = (s < 0 ? 1 : -1) * strides[a], lw = layerWeights(a, n, ls)
                @inline(__always) func orig(_ u: Int, _ v: Int, _ t: Int) -> Float {
                    let o = max(0, min(n - 1, u)) * s0 + max(0, min(n - 1, v)) * s1 + max(0, min(n - 1, t)) * s2
                    var sum: Float = 0; for L in 0..<lw.count { sum += lw[L] * F[base + L * inward + o] }
                    return sum
                }
                var G = [Float](repeating: 0, count: mf * mf * mf)
                if up {
                    @inline(__always) func cr(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float) -> Float { (-p0 + 9 * p1 + 9 * p2 - p3) / 16 }   // まんなか（f ＝ 0.5）のキャットマル–ロム
                    var A = [Float](repeating: 0, count: n * n * mf)                // u の向きに細かく
                    for t in 0..<n { for v in 0..<n { for j in 0..<mf { let i = j / 2; A[(t * n + v) * mf + j] = j % 2 == 0 ? orig(i, v, t) : cr(orig(i - 1, v, t), orig(i, v, t), orig(i + 1, v, t), orig(i + 2, v, t)) } } }
                    @inline(__always) func a(_ j: Int, _ v: Int, _ t: Int) -> Float { A[(max(0, min(n - 1, t)) * n + max(0, min(n - 1, v))) * mf + j] }
                    var B = [Float](repeating: 0, count: n * mf * mf)               // v の向きにも
                    for t in 0..<n { for jv in 0..<mf { let i = jv / 2; for j in 0..<mf { B[(t * mf + jv) * mf + j] = jv % 2 == 0 ? a(j, i, t) : cr(a(j, i - 1, t), a(j, i, t), a(j, i + 1, t), a(j, i + 2, t)) } } }
                    @inline(__always) func b(_ j: Int, _ jv: Int, _ t: Int) -> Float { B[(max(0, min(n - 1, t)) * mf + jv) * mf + j] }
                    for jt in 0..<mf { let i = jt / 2; for jv in 0..<mf { for j in 0..<mf { G[(jt * mf + jv) * mf + j] = jt % 2 == 0 ? b(j, jv, i) : cr(b(j, jv, i - 1), b(j, jv, i), b(j, jv, i + 1), b(j, jv, i + 2)) } } }
                } else {
                    for t in 0..<n { for v in 0..<n { for u in 0..<n { G[(t * mf + v) * mf + u] = orig(u, v, t) } } }
                }
                @inline(__always) func gv(_ u: Int, _ v: Int, _ t: Int) -> Float { G[(max(0, min(mf - 1, t)) * mf + max(0, min(mf - 1, v))) * mf + max(0, min(mf - 1, u))] }
                @inline(__always) func vv(_ u: Int, _ v: Int, _ t: Int) -> Float { gv(u, v, t) }
                @inline(__always) func coordF(_ j: Int) -> Float { j < 0 ? -Hf : j >= mf ? Hf : (up ? -Hf + (Float(j) / 2 + 0.5) * dx : -Hf + (Float(j) + 0.5) * dx) }
                // 点の水面の向き（φ の坂）から、水面に沿った 2 つの向き
                @inline(__always) func tang(_ g: SIMD3<Float>) -> (SIMD4<Float>, SIMD4<Float>) {
                    let l = simd_length(g); if l < 1e-9 { return (.zero, .zero) }
                    let gn = g / l, h: SIMD3<Float> = abs(gn.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
                    let a1 = simd_normalize(simd_cross(gn, h)), a2 = simd_cross(gn, a1)
                    return (dir4(a1), dir4(a2))
                }
                for t in -1..<mf { let t0 = max(0, t), t1 = min(mf - 1, t + 1)
                for v in -1..<mf { let v0 = max(0, v), v1 = min(mf - 1, v + 1)
                    // この行（u の向き）に水面が無ければ、まとめて飛ばす
                    var anyNeg = false, anyPos = false
                    for tt in [t0, t1] { for vq in [v0, v1] { let rb = (tt * mf + vq) * mf; for u in 0..<mf { if G[rb + u] < 0 { anyNeg = true } else { anyPos = true }; if anyNeg && anyPos { break } } } }
                    if !(anyNeg && anyPos) { continue }
                for u in -1..<mf {
                    let u0 = max(0, u), u1 = min(mf - 1, u + 1)
                    var neg = 0
                    for b in 0..<8 {
                        let x = G[(((b & 4) != 0 ? t1 : t0) * mf + ((b & 2) != 0 ? v1 : v0)) * mf + ((b & 1) != 0 ? u1 : u0)]
                        c[b] = x; if x < 0 { neg += 1 }
                    }
                    if neg == 0 || neg == 8 { continue }
                    for b in 0..<8 {
                        let uu = u + (b & 1), vq = v + ((b >> 1) & 1), tq = t + ((b >> 2) & 1)
                        cpv[b] = SIMD3(coordF(uu), coordF(vq), coordF(tq))
                        cg[b] = SIMD3(vv(uu + 1, vq, tq) - vv(uu - 1, vq, tq), vv(uu, vq + 1, tq) - vv(uu, vq - 1, tq), vv(uu, vq, tq + 1) - vv(uu, vq, tq - 1))
                    }
                    for k in 0..<6 {
                        var m = 0
                        for j in 0..<4 where c[tetF[4 * k + j]] < 0 { m |= 1 << j }
                        if m == 0 || m == 15 { continue }
                        let es = cases[m]
                        // 水から空気への向き（四面体の中で）
                        var wc = SIMD3<Float>.zero, ac = SIMD3<Float>.zero, ni: Float = 0, no: Float = 0
                        for j in 0..<4 { let pj = cpv[tetF[4 * k + j]]; if m & (1 << j) != 0 { wc += pj; ni += 1 } else { ac += pj; no += 1 } }
                        let outDir = ac / no - wc / ni
                        @inline(__always) func ep(_ e: Int) -> (SIMD3<Float>, SIMD3<Float>) {
                            let (i, o) = es[e], qi = tetF[4 * k + i], qo = tetF[4 * k + o], ci = c[qi], co = c[qo], tt = ci / (ci - co)
                            return (cpv[qi] + (cpv[qo] - cpv[qi]) * tt, cg[qi] + (cg[qo] - cg[qi]) * tt)
                        }
                        var tri = 0
                        while tri * 3 < es.count {
                            let p0 = ep(tri * 3); var p1 = ep(tri * 3 + 1), p2 = ep(tri * 3 + 2)
                            tri += 1
                            let nrm = simd_cross(p1.0 - p0.0, p2.0 - p0.0)
                            if simd_length_squared(nrm) < 1e-14 { continue }
                            if simd_dot(nrm, outDir) < 0 { swap(&p1, &p2) }
                            for q in [p0, p1, p2] { out.p.append(pos4(q.0)); let (a1, a2) = tang(q.1); out.t1.append(a1); out.t2.append(a2) }
                            out.kind.append(1)
                        }
                    }
                } } }
            } }
            // (2) 24 枚の正方形：軸 a・b が張る面（ほかの 2 つの軸は ±H）。行（b の 1 マス）ごとに、水の続いている所を 1 つの四角に（両端は水面の所まで補間）
            for a in 0..<4 { for b in (a + 1)..<4 {
                let o = (0..<4).filter { $0 != a && $0 != b }
                for so in 0..<4 {
                    let i0 = (so & 1) == 0 ? 0 : n - 1, i1 = (so & 2) == 0 ? 0 : n - 1
                    let strides = [1, M1, M2, M3], base = i0 * strides[o[0]] + i1 * strides[o[1]], sa = strides[a], sb = strides[b]
                    // 胞の水と同じく、かべから内へ wallLayers 層ずつ（2 つの向きで、層 × 層）の平均で（かべにくっついたまくを描かない）
                    let in0 = (i0 == 0 ? 1 : -1) * strides[o[0]], in1 = (i1 == 0 ? 1 : -1) * strides[o[1]], w0 = layerWeights(o[0], n, ls), w1 = layerWeights(o[1], n, ls)
                    @inline(__always) func fq(_ off: Int) -> Float { var sum: Float = 0; for p in 0..<w0.count { for q in 0..<w1.count { sum += w0[p] * w1[q] * F[base + p * in0 + q * in1 + off] } }; return sum }
                    let f0 = Float(i0 == 0 ? -1 : 1) * Hf, f1 = Float(i1 == 0 ? -1 : 1) * Hf
                    @inline(__always) func P(_ x: Float, _ y: Float) -> SIMD4<Float> { var r = SIMD4<Float>(0, 0, 0, 0); r[a] = x; r[b] = y; r[o[0]] = f0; r[o[1]] = f1; return r }
                    // 行 j の水の範囲（a の向き）：はじめの続き 1 つ（なければ nil）
                    func span(_ j: Int) -> (Float, Float)? {
                        var lo = -1, hi = -1
                        for i in 0..<n where fq(i * sa + j * sb) < 0 { if lo < 0 { lo = i }; hi = i } 
                        if lo < 0 { return nil }
                        func cross(_ i: Int, _ k: Int) -> Float {   // マス i（水）と k（空気）のあいだの水面
                            let x = fq(i * sa + j * sb), y = fq(k * sa + j * sb); return coord(i) + (coord(k) - coord(i)) * x / (x - y)
                        }
                        let L = lo == 0 ? -Hf : cross(lo, lo - 1), R = hi == n - 1 ? Hf : cross(hi, hi + 1)
                        return (L, R)
                    }
                    // 行の w（b の向き）の上下の端：b の端の行は縁まで、それ以外はマスの真ん中どうし
                    var prev: (Float, Float)? = nil, prevY: Float = -Hf
                    for j in 0..<n {
                        let sp = span(j), y = coord(j)
                        if let s1 = sp, let s0 = prev {
                            out.p += [P(s0.0, prevY), P(s0.1, prevY), P(s1.1, y), P(s0.0, prevY), P(s1.1, y), P(s1.0, y)]; out.kind += [0, 0]; out.t1 += Array(repeating: .zero, count: 6); out.t2 += Array(repeating: .zero, count: 6)
                        } else if let s1 = sp, j == 0 {
                            out.p += [P(s1.0, -Hf), P(s1.1, -Hf), P(s1.1, y), P(s1.0, -Hf), P(s1.1, y), P(s1.0, y)]; out.kind += [0, 0]; out.t1 += Array(repeating: .zero, count: 6); out.t2 += Array(repeating: .zero, count: 6)
                        }
                        if let s1 = sp, j == n - 1 {
                            out.p += [P(s1.0, y), P(s1.1, y), P(s1.1, Hf), P(s1.0, y), P(s1.1, Hf), P(s1.0, Hf)]; out.kind += [0, 0]; out.t1 += Array(repeating: .zero, count: 6); out.t2 += Array(repeating: .zero, count: 6)
                        }
                        prev = sp; prevY = y
                    }
                }
            } }
        }
        // 同じ点をまとめる（三角形どうしで共有する点を 1 つに）：描く時に、写す・面の向き・厚みを点ごとに 1 回だけ計算できる（前は 1 つの点を 6 回くらい計算していた）
        var map: [NS4VKey: Int32] = [:]; map.reserveCapacity(out.p.count / 3)
        out.idx.reserveCapacity(out.p.count)
        let hasT = out.t1.count == out.p.count
        for i in 0..<out.p.count {
            let q = out.p[i], kd = out.kind[i / 3] > 0.5
            let key = NS4VKey(x: Int32((q.x * 2e4).rounded()), y: Int32((q.y * 2e4).rounded()), z: Int32((q.z * 2e4).rounded()), w: Int32((q.w * 2e4).rounded()), s: kd)
            if let j = map[key] { out.idx.append(j); continue }
            let j = Int32(out.up.count); map[key] = j; out.idx.append(j)
            out.up.append(q); out.ut1.append(hasT ? out.t1[i] : .zero); out.ut2.append(hasT ? out.t2[i] : .zero)
        }
        return out
    }
}

// ---- 輪切り：4D の水を 1 枚切って（軸 a ＝ 一定）、残りの 3 つの向きの 3D の水を取り出す（まわりは空気として閉じる：水面も壁に触れている所も）----
extension NS4 {
    func sliceMesh(axis a: Int, index k: Int) -> NS4Mesh {
        let key = (resultID * 8 + a) * 64 + k
        if key == sliceKey { return sliceCache }
        var out = NS4Mesh()
        let n = N, Hf = H, dx = par.dx, F = phiShow.count == MM ? phiShow : phiDisp.count == MM ? phiDisp : phiCPU
        @inline(__always) func coord(_ i: Int) -> Float { i < 0 ? -Hf : i >= n ? Hf : -Hf + (Float(i) + 0.5) * dx }
        let oth = (0..<4).filter { $0 != a }, strides = [1, M, M * M, M * M * M]
        let base = k * strides[a], s0 = strides[oth[0]], s1 = strides[oth[1]], s2 = strides[oth[2]], fa = coord(k)
        @inline(__always) func val(_ u: Int, _ v: Int, _ t: Int) -> Float {
            if u < 0 || v < 0 || t < 0 || u >= n || v >= n || t >= n { return dx }   // 箱の外は空気（壁に触れている所も面になる）
            return F[base + u * s0 + v * s1 + t * s2]
        }
        @inline(__always) func pos4(_ q: SIMD3<Float>) -> SIMD4<Float> { var r = SIMD4<Float>(0, 0, 0, 0); r[a] = fa; r[oth[0]] = q.x; r[oth[1]] = q.y; r[oth[2]] = q.z; return r }
        let tetF: [Int] = [0, 1, 3, 7, 0, 3, 2, 7, 0, 2, 6, 7, 0, 6, 4, 7, 0, 4, 5, 7, 0, 5, 1, 7], cases = Self.tetCases
        var c = [Float](repeating: 0, count: 8), cp = [SIMD3<Float>](repeating: .zero, count: 8), pad = [Bool](repeating: false, count: 8)
        for t in -1..<n { for v in -1..<n { for u in -1..<n {
            var neg = 0
            for b in 0..<8 {
                let uu = u + (b & 1), vq = v + ((b >> 1) & 1), tq = t + ((b >> 2) & 1)
                c[b] = val(uu, vq, tq); if c[b] < 0 { neg += 1 }
                cp[b] = SIMD3(coord(uu), coord(vq), coord(tq)); pad[b] = uu < 0 || vq < 0 || tq < 0 || uu >= n || vq >= n || tq >= n
            }
            if neg == 0 || neg == 8 { continue }
            for kk in 0..<6 {
                var m = 0
                for j in 0..<4 where c[tetF[4 * kk + j]] < 0 { m |= 1 << j }
                if m == 0 || m == 15 { continue }
                let es = cases[m]
                var wc = SIMD3<Float>.zero, ac = SIMD3<Float>.zero, ni: Float = 0, no: Float = 0
                for j in 0..<4 { let pj = cp[tetF[4 * kk + j]]; if m & (1 << j) != 0 { wc += pj; ni += 1 } else { ac += pj; no += 1 } }
                let outDir = ac / no - wc / ni
                var tri = 0
                while tri * 3 < es.count {
                    var P = [SIMD3<Float>](repeating: .zero, count: 3), wall = true
                    for e in 0..<3 {
                        let (i, o) = es[tri * 3 + e], qi = tetF[4 * kk + i], qo = tetF[4 * kk + o]
                        P[e] = cp[qi] + (cp[qo] - cp[qi]) * (c[qi] / (c[qi] - c[qo])); if !(pad[qi] || pad[qo]) { wall = false }
                    }
                    tri += 1
                    let nrm = simd_cross(P[1] - P[0], P[2] - P[0]); if simd_length_squared(nrm) < 1e-14 { continue }
                    if simd_dot(nrm, outDir) < 0 { P.swapAt(1, 2) }
                    for q in P { out.p.append(pos4(q)) }; out.kind.append(wall ? 0 : 1)
                }
            }
        } } }
        sliceCache = out; sliceKey = key
        return out
    }
}

// ---- はちみつの拡大実験（とぐろの段階 1、2026-11-26）----
//   注ぎ口の下（粗い 32⁴ の 12 マス分の 4 次元の立方体）だけを、細かい 4D の格子（ふつう 48⁴ ＝ 粗いマスの 4 倍の細かさ）で計算する。
//   細いはちみつの糸が天井から落ちて、底のはちみつにぶつかった時に、座屈して（曲がって）とぐろを巻くかを見る。粗い格子とのつなぎはまだ無い。
//   環境変数：NSZOUT 書き出す場所・NSZN 細かさ・NSZNU 粘り ν・NSZT 秒・NSZR 糸の半径（細かいマス）・NSZV 出る速さ・NSZH 底のはちみつの高さ（−1〜1）・NSZG 重力
import CoreGraphics
import ImageIO
extension NS4 {
    static func zoomExperiment() {
        let E = ProcessInfo.processInfo.environment
        let n = Int(E["NSZN"] ?? "48") ?? 48, Hz = Float(OrigamiState.half) * 12 / 32        // 粗いマス 12 個分の広さ（世界の単位で 0.675）
        guard let z = NS4(N: n, H: Hz) else { print("拡大実験：作れなかった"); return }
        let nu = Float(E["NSZNU"] ?? "0.45") ?? 0.45, T = Double(E["NSZT"] ?? "5") ?? 5, rJ = Float(E["NSZR"] ?? "2.5") ?? 2.5
        let vJ = Float(E["NSZV"] ?? "0.3") ?? 0.3, h0 = Float(E["NSZH"] ?? "-0.75") ?? -0.75, g = Float(E["NSZG"] ?? "6.9") ?? 6.9
        let out = E["NSZOUT"] ?? NSTemporaryDirectory()
        let rdN = Int(E["NSZRD"] ?? "2") ?? 2                                          // φ を距離に直す回数（2 歩ごと）
        z.reset(level: h0)
        let c = Float(n) * 0.5
        z.par.jetOn = 1; z.par.pad2 = 0; z.par.topOpen = 0; z.par.hole = 0; z.par.open = 0
        z.par.jetC = SIMD4<Float>(c + 0.31, c - 0.17, c + 0.07, Float(n - 3))                // 真ん中から少しずらす（ぴったり対称だと、計算では いつまでも曲がらない）
        z.par.jetR = rJ; z.par.jetV = vJ; z.par.jetD = simd_normalize(SIMD4<Float>(0.012, 0.007, 0, -1))
        z.par.gvec = SIMD4<Float>(0, 0, 0, -g); z.par.nu = nu; z.viscStick = 1; z.cgIters = Int(E["NSZCG"] ?? "0") ?? 0
        z.par.vort = 0; z.par.smooth = 0; z.par.ex2 = SIMD4<Float>(0, 1, 0, 0); z.par.swirlOn = 0
        let dt = Float(E["NSZDT"] ?? "") ?? Float(1.0 / 240), steps = Int(T / Double(dt)), every = max(1, Int(0.25 / Double(dt)))
        print(String(format: "拡大実験：%d⁴・dx %.4f・ν %.3f・α %.1f・糸の半径 %.1f マス（%.3f）・%d 歩", n, z.par.dx, nu, nu * dt / (z.par.dx * z.par.dx), rJ, rJ * z.par.dx, steps))
        let M = z.M, MM = z.MM, P = 4, W = n * P                                              // 1 つの絵：n×n マスを 4 倍に
        var frames: [[UInt8]] = []
        let t0 = CFAbsoluteTimeGetCurrent()
        let pool = Int((Float(h0) + 1) * 0.5 * Float(n))
        for s in 0...steps {
            if s > 0 { z.step(dt: dt, iters: 50, target: nil, redistEvery: s % 2 == 0 ? rdN : 0) }
            if s % every != 0 { continue }
            let f = z.phi.contents().bindMemory(to: Float.self, capacity: MM)
            // 3 つの絵：横から（x‐w、y・z で重ねる）・横から（y‐w）・上から（x‐y、底のはちみつより上だけ、z・w で重ねる）。明るさは重なった厚さ
            var img = [UInt8](repeating: 0, count: 3 * W * W * 4)
            var thick = [[Int]](repeating: [Int](repeating: 0, count: n * n), count: 3)
            var cen: [(Int, SIMD3<Float>)] = []
            for l in 0..<n {
                var sx = SIMD3<Float>(0, 0, 0), cnt = 0
                for k in 0..<n { for j in 0..<n { for i in 0..<n where f[((l * M + k) * M + j) * M + i] < 0 {
                    thick[0][l * n + i] += 1; thick[1][l * n + j] += 1
                    if l > pool + 1 { thick[2][j * n + i] += 1; sx += SIMD3<Float>(Float(i), Float(j), Float(k)) + 0.5; cnt += 1 }
                } } }
                if cnt > 0 && l > pool + 1 { cen.append((l, sx / Float(cnt) - SIMD3<Float>(repeating: c))) }
            }
            for p in 0..<3 { for b in 0..<n { for a in 0..<n {
                let tk = thick[p][b * n + a]; guard tk > 0 else { continue }
                let x = min(1, 0.25 + Float(tk) / Float(n) * 3)
                let col: (UInt8, UInt8, UInt8) = (UInt8(255 * x), UInt8(170 * x * x), UInt8(40 * x * x * x))
                for yy in 0..<P { for xx in 0..<P {
                    let px = p * W + a * P + xx, py = (p == 2 ? b : n - 1 - b) * P + yy, o = (py * 3 * W + px) * 4
                    img[o] = col.0; img[o + 1] = col.1; img[o + 2] = col.2; img[o + 3] = 255
                } }
            } } }
            for p in 0..<3 { for y in 0..<W { let o = (y * 3 * W + p * W) * 4; img[o] = 60; img[o + 1] = 60; img[o + 2] = 80; img[o + 3] = 255 } }
            frames.append(img)
            let low = cen.prefix(4).map { String(format: "w%d:(%.1f,%.1f,%.1f)", $0.0, $0.1.x, $0.1.y, $0.1.z) }.joined(separator: " ")
            let uu = z.U.contents().bindMemory(to: Float.self, capacity: 4 * MM), pp = z.pr.contents().bindMemory(to: Float.self, capacity: MM)
            var bad = 0, um: Float = 0, pm: Float = 0
            for i in 0..<MM where !f[i].isFinite { bad += 1 }
            for i in 0..<(4 * MM) { let v = uu[i]; if !v.isFinite { bad += 1 } else { um = max(um, abs(v)) } }
            for i in 0..<MM { let v = pp[i]; if !v.isFinite { bad += 1 } else { pm = max(pm, abs(v)) } }
            if E["NSZDBG"] != nil {
                let ci = Int(c), line = (0..<n).reversed().map { l -> String in let id = ((l * M + ci) * M + ci) * M + ci; return String(format: "%d:%.2f/%.1f", l, uu[3 * MM + id], f[id] / z.par.dx) }
                print("    真ん中の線（w：速さ／φ マス）" + line.joined(separator: " "))
            }
            var cgr = ""
            if let sb = z.cgSBuf { let S = sb.contents().bindMemory(to: Float.self, capacity: 8); cgr = String(format: "・粘りの残り %.1e", (S[0] / max(1e-30, S[4])).squareRoot()) }
            print(String(format: "  %.2f 秒：体積 %.4f・数でない値 %d・いちばん速い %.2f・圧力 %.2f%@・底の上の糸のずれ（マス）%@", Double(s) * Double(dt), z.volumeOf(Array(UnsafeBufferPointer(start: f, count: MM))).0, bad, um, pm, cgr, low))
        }
        print(String(format: "拡大実験：計算 %.1f 秒（1 歩 %.1f ミリ秒）", CFAbsoluteTimeGetCurrent() - t0, z.stepMs))
        // 絵を並べて 1 枚に（4 列）
        let cols = 4, rows = (frames.count + cols - 1) / cols, FW = 3 * W + 8, FH = W + 8, TW = cols * FW, TH = rows * FH
        var all = [UInt8](repeating: 20, count: TW * TH * 4)
        for (q, img) in frames.enumerated() {
            let ox = (q % cols) * FW, oy = (q / cols) * FH
            for y in 0..<W { for x in 0..<(3 * W) { let s = (y * 3 * W + x) * 4, d = ((oy + y) * TW + ox + x) * 4; for k in 0..<4 { all[d + k] = img[s + k] } } }
        }
        let url = URL(fileURLWithPath: out).appendingPathComponent(String(format: "はちみつ拡大_%d_nu%.2f.png", n, nu))
        all.withUnsafeMutableBytes { b in
            guard let ctx = CGContext(data: b.baseAddress, width: TW, height: TH, bitsPerComponent: 8, bytesPerRow: TW * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let im = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dst, im, nil); CGImageDestinationFinalize(dst)
        }
        print("拡大実験の絵：\(url.path)")
    }
}
