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
    var ex2 = SIMD4<Float>(0.8, 0, 0, 0)                              // x：波のブレーキ（1 秒あたりの弱まり γ。壁とのこすれのかわり：ちゃぷちゃぷが数秒で静まる）
    var kick = simd_float4x4(0)                                       // 箱を回した時の、回る速さの変わり（箱から見た 4D の回転の生成子の差 ΔW）。水には −ΔW r の速さ（オイラーの力：水はその場に残ろうとする）
}

let ns4Shader = """
#include <metal_stdlib>
using namespace metal;
struct P { float4 jetC; int N; int M; int c; int par; int open; int jetOn; int swirlOn; int topOpen; float dx; float dt; float g; float hole; float omega; float jetR; float jetV; float shift; float nu; float smooth; float pad2; float vort; float4 gvec; float4 jetD; float4 ex2; float4x4 kick; };
inline int4 dec(uint id, int M) { int i = int(id) % M; int j = (int(id) / M) % M; int k = (int(id) / (M * M)) % M; int l = int(id) / (M * M * M); return int4(i, j, k, l); }
inline int enc(int4 q, int M) { return ((q.w * M + q.z) * M + q.y) * M + q.x; }
inline int4 ax(int c) { return int4(c == 0, c == 1, c == 2, c == 3); }
inline bool inCell(int4 q, int N) { return all(q >= 0) && all(q < N); }
inline bool inFace(int4 q, int c, int N) { int4 hi = int4(N - 1); hi[c] = N; return all(q >= 0) && all(q <= hi); }
// 底（l ＝ 0 の w の壁）のこの壁が開いているか（全開、または真ん中の排水口）
inline bool inJet(int4 q, constant P& p) { return p.jetOn != 0 && p.topOpen == 0 && int(p.jetC.w) >= p.N - 3 && length(float3(q.xyz) + 0.5 - p.jetC.xyz) < p.jetR; }   // 天井から入れる時だけ、天井の壁を開ける
inline bool openAt(int4 q, constant P& p) {
    if (p.open == 1) return true;
    if (p.hole <= 0.0) return false;
    float3 r = abs(float3(q.xyz) + 0.5 - float(p.N) * 0.5);
    return r.x < p.hole && r.y < p.hole && r.z < p.hole;
}
// 成分 c の速さを、格子の点 x（マスの真ん中が i＋0.5）で 16 点の補間
float sampleF(device const float* U, int c, float4 x, constant P& p) {
    float4 q = x - 0.5; q[c] = x[c];
    float4 hi = float4(float(p.N - 1)); hi[c] = float(p.N);
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
    float4 q = clamp(x - 0.5, float4(0.0), float4(float(p.N - 1)));
    int4 i0 = clamp(int4(floor(q)), int4(0), int4(p.N - 2));
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
    int MM = p.M * p.M * p.M * p.M;
    return float4(sampleF(U, 0, x, p), sampleF(U + MM, 1, x, p), sampleF(U + 2 * MM, 2, x, p), sampleF(U + 3 * MM, 3, x, p));
}
// 速さを運ぶ（成分 c）
kernel void advU(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); int c = p.c;
    if (!inFace(q, c, p.N)) { UT[c * MM + id] = 0.0; return; }
    float4 x = float4(q) + 0.5; x[c] = float(q[c]);
    bool wall = q[c] == 0 || q[c] == p.N;
    if (c == 3 && q.w == p.N && inJet(q, p)) { UT[c * MM + id] = p.jetD.w * p.jetV; return; }   // 上から注ぐ所は、入ってくる速さ
    if (wall && !(c == 3 && q.w == 0 && openAt(q, p)) && !(c == 3 && q.w == p.N && p.topOpen != 0)) { UT[c * MM + id] = 0.0; return; }
    float4 v = velAt(U, x, p);
    float4 xb = x - p.dt * v / p.dx;
    UT[c * MM + id] = sampleF(U + c * MM, c, xb, p);
}
// 水面までの距離 φ を運ぶ（体積を合わせるずれ shift もここで足す）
kernel void advPhi(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* phiT [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); if (!inCell(q, p.N)) { phiT[id] = 1.0; return; }
    float4 x = float4(q) + 0.5;
    float4 v = velAt(U, x, p);
    float4 xb = x - p.dt * v / p.dx;
    // 開いた口（ふた +W）・開いた底の外は空気（外から流れこむ所は空気が入る。箱の端と同じ水にすると、満タンの時に空気が入れ替われず抜けない）
    if ((p.topOpen != 0 && xb.w > float(p.N)) || (xb.w < 0.0 && openAt(q, p))) { phiT[id] = p.dx; return; }
    float f = sampleC(phi, xb, p);
    phiT[id] = f + (abs(f) < 3.0 * p.dx ? p.shift : 0.0);   // 体積を合わせるずれは水面の近くだけ（遠くの空気に水がわかないように）
}
// 注ぐ水：上（w の上の端）の、筋の真ん中のまわりのマスを水にして、下向きの速さを入れる
kernel void jet(device float* U [[buffer(0)]], device float* phi [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM || p.jetOn == 0) return;
    int4 q = dec(id, p.M); if (!inCell(q, p.N)) return;
    float r;
    if (p.pad2 > 0.5) {                                                // 遊ぶモード：入れる所は 4 次元の玉（箱のいちばん上の面の近く、どの向きでも）
        r = length(float4(q) + 0.5 - p.jetC);
    } else {                                                           // 積分：水面のすぐ上の 3 マス（落ちる高さを小さく＝おだやかに）
        int l0 = int(p.jetC.w);
        if (q.w < l0 || q.w >= l0 + 3) return;
        r = length(float3(q.xyz) + 0.5 - p.jetC.xyz);
    }
    if (r >= p.jetR) return;
    if (q.w == p.N - 1 && p.topOpen == 0) U[3 * MM + enc(q + int4(0, 0, 0, 1), p.M)] = p.jetD.w * p.jetV;
    phi[id] = min(phi[id], (r - p.jetR) * p.dx);
    for (int c = 0; c < 4; c++) U[c * MM + id] = p.jetD[c] * p.jetV;   // 注ぐ水の向き（遊ぶモードでは、画面の上から＝重力の向き）
}
// 重力（w の下向き）。swirlOn：はじめのゆらぎ（x‐y の面で少し回す。お風呂の水に残っている小さな回転）
kernel void force(device float* U [[buffer(0)]], constant P& p [[buffer(1)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    float dmp = exp(-p.ex2.x * p.dt);                                   // 波のブレーキ（だんだん静かに）
    for (int c = 0; c < 4; c++) if (inFace(q, c, p.N)) U[c * MM + id] = U[c * MM + id] * dmp + p.gvec[c] * p.dt;   // 重力（どの向きでも）
    // 箱を回した時：水はその場に残ろうとするので、箱から見ると回る速さの変わりの逆に動く（壁の真ん中の位置 r で −ΔW r）
    if (p.pad2 < 0.5 || true) {
        float h = float(p.N) * 0.5;
        for (int c = 0; c < 4; c++) {
            if (!inFace(q, c, p.N)) continue;
            float4 r = (float4(q) + 0.5 - h) * p.dx; r[c] = (float(q[c]) - h) * p.dx;
            float4 dv = p.kick * r;
            U[c * MM + id] -= dv[c];
        }
    }
    if (p.swirlOn != 0) {
        float h = float(p.N) * 0.5;
        if (inFace(q, 0, p.N)) { float y = float(q.y) + 0.5 - h; U[id] += -p.shift * y / h; }
        if (inFace(q, 1, p.N)) { float x = float(q.x) + 0.5 - h; U[MM + id] += p.shift * x / h; }
    }
}
// 粘り：水に触れている壁の速さを、まわりの同じ成分とならす（ν Δu。マス 1 つ分の時間なら、この大きさの ν で安定）
kernel void visc(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], device const float* phi [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    float k = min(0.1, p.nu * p.dt / (p.dx * p.dx));
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id); UT[fi] = U[fi];
        if (!inFace(q, c, p.N) || q[c] == 0 || q[c] == p.N) continue;
        if (!(phi[enc(q - ax(c), p.M)] < 0.0 || phi[id] < 0.0)) continue;
        float s = 0.0, n = 0.0;
        for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) { int4 nb = q + sg * ax(d); if (inFace(nb, c, p.N)) { s += U[c * MM + enc(nb, p.M)]; n += 1.0; } }
        UT[fi] = U[fi] + k * (s - n * U[fi]);
    }
}
// 水面をならす（水面の近くだけ、となりの平均へ少し寄せる＝曲がった所ほど平らに：表面張力のかわり。小さな粒・うすい膜は消えていく）
kernel void smoothPhi(device const float* phi [[buffer(0)]], device float* phiT [[buffer(1)]], constant P& p [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); float f = phi[id];
    if (!inCell(q, p.N) || abs(f) > 3.0 * p.dx) { phiT[id] = f; return; }
    float s = 0.0, n = 0.0;
    for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) { int4 nb = q + sg * ax(d); if (inCell(nb, p.N)) { s += phi[enc(nb, p.M)]; n += 1.0; } }
    phiT[id] = f + p.smooth * (s / n - f);
}
// ---- 渦の強調（渦度の閉じこめ）：粗いマスでならされて消える細い渦を、少し足し戻す ----
//   4 次元の渦度は「回る面」の 6 成分 Ω_ij ＝ ∂_i u_j − ∂_j u_i（3 次元の渦の軸 ω のかわり）。強さ |Ω| ＝ √(Σ_{i<j} Ω_ij²)。
//   N ＝ ∇|Ω|／|∇|Ω||（渦の強い所へ向かう向き）。力 f_i ＝ ε·dx·Σ_j Ω_ij N_j（3 次元の ε·h·(N × ω) と同じ形：N × ω の i 成分 ＝ Σ_j Ω_ij N_j）
inline float ucell(device const float* U, int4 q, int j, constant P& p) {   // マスの真ん中の速さ（成分 j：両側の壁の平均）
    int MM = p.M * p.M * p.M * p.M;
    return 0.5 * (U[j * MM + enc(q, p.M)] + U[j * MM + enc(q + ax(j), p.M)]);
}
inline float dU(device const float* U, int4 q, int i, int j, constant P& p) {   // ∂_i u_j（マスの真ん中で、となりのマスとの差。端は片側）
    int4 a = q - ax(i), b = q + ax(i); float span = 2.0;
    if (!inCell(a, p.N)) { a = q; span = 1.0; }
    if (!inCell(b, p.N)) { b = q; span = span - 1.0; }
    if (span <= 0.0) return 0.0;
    return (ucell(U, b, j, p) - ucell(U, a, j, p)) / (span * p.dx);
}
kernel void vortW(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* W [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCell(q, p.N) || phi[id] >= 0.0) { W[id] = 0.0; return; }
    float s = 0.0;
    for (int i = 0; i < 4; i++) for (int j = i + 1; j < 4; j++) { float o = dU(U, q, i, j, p) - dU(U, q, j, i, p); s += o * o; }
    W[id] = sqrt(s);
}
kernel void vortF(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device const float* W [[buffer(2)]], device float* Fv [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) Fv[c * MM + id] = 0.0;
    if (!inCell(q, p.N) || phi[id] >= 0.0) return;
    float4 g = float4(0.0);
    for (int i = 0; i < 4; i++) {
        int4 a = q - ax(i), b = q + ax(i); float span = 2.0;
        if (!inCell(a, p.N)) { a = q; span = 1.0; }
        if (!inCell(b, p.N)) { b = q; span = span - 1.0; }
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
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        if (!inFace(q, c, p.N) || q[c] == 0 || q[c] == p.N) continue;
        int ia = enc(q - ax(c), p.M);
        if (!(phi[ia] < 0.0 && phi[id] < 0.0)) continue;               // 水の中だけ（水面のそばはさわらない）
        U[c * MM + id] += p.dt * 0.5 * (Fv[c * MM + ia] + Fv[c * MM + id]);
    }
}
// 圧力の式の右辺：−（流れの湧き出し）× dx² ／ dt
kernel void rhs(device const float* U [[buffer(0)]], device const float* phi [[buffer(1)]], device float* R [[buffer(2)]], device float* Pr [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCell(q, p.N) || phi[id] >= 0.0) { R[id] = 0.0; Pr[id] = 0.0; return; }
    float dv = 0.0;
    for (int c = 0; c < 4; c++) dv += U[c * MM + enc(q + ax(c), p.M)] - U[c * MM + id];
    R[id] = -dv * p.dx / p.dt;   // （dv／dx）× dx² ／ dt
}
// 赤黒の SOR：水のマスだけ。となりが水ならその圧力、空気なら 0（水面までの距離の割合 θ で近さを入れる）、壁なら入れない（流れが通らない）
kernel void press(device float* Pr [[buffer(0)]], device const float* phi [[buffer(1)]], device const float* R [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    if (!inCell(q, p.N) || ((q.x + q.y + q.z + q.w) & 1) != p.par) return;
    float pc = phi[id]; if (pc >= 0.0) { Pr[id] = 0.0; return; }
    float diag = 0.0, s = 0.0;
    for (int c = 0; c < 4; c++) {
        for (int sg = -1; sg <= 1; sg += 2) {
            int4 nb = q + sg * ax(c);
            if (!inCell(nb, p.N)) {
                if (c == 3 && sg < 0 && openAt(q, p)) diag += 1.0;   // 開いた底：外は圧力 0
                if (c == 3 && sg > 0 && p.topOpen != 0) diag += 1.0;   // 開いたふた：外は圧力 0
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
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        if (!inFace(q, c, p.N)) continue;
        int fi = c * MM + int(id);
        if (q[c] == p.N) {
            if (c == 3 && p.topOpen != 0) { int ib = enc(q - ax(c), p.M); if (phi[ib] < 0.0) U[fi] -= p.dt / p.dx * (0.0 - Pr[ib]); continue; }   // 開いたふた：水は外へ出ていける
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
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id);
        if (!inFace(q, c, p.N)) { V[fi] = 0.0; continue; }
        if (q[c] == 0 || q[c] == p.N) {
            // 開いた口・底：水に触れていない所の速さは 0 に（重力が毎コマ足されて、そこだけ速くなり続け、口のまわりの水面を暴れさせていた）
            if (c == 3 && q[c] == 0 && openAt(q, p)) { V[fi] = phi[id] < 0.0 ? 1.0 : 0.0; if (V[fi] < 0.5) U[fi] = 0.0; continue; }
            if (c == 3 && q[c] == p.N && p.topOpen != 0) { V[fi] = phi[enc(q - ax(c), p.M)] < 0.0 ? 1.0 : 0.0; if (V[fi] < 0.5) U[fi] = 0.0; continue; }
            V[fi] = 1.0; continue;
        }
        int ia = enc(q - ax(c), p.M);
        V[fi] = (phi[ia] < 0.0 || phi[id] < 0.0) ? 1.0 : 0.0;
        if (V[fi] < 0.5) U[fi] = 0.0;   // 水から離れた空気の速さは 0 に（重力で速くなり続けて、水面を変な所から運んでこないように）
    }
}
// 空気側へ速さをのばす：決まっていない壁は、まわりの決まっている壁の平均に
kernel void extrap(device const float* U [[buffer(0)]], device float* UT [[buffer(1)]], device const float* V [[buffer(2)]], device float* VT [[buffer(3)]], constant P& p [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M);
    for (int c = 0; c < 4; c++) {
        int fi = c * MM + int(id);
        UT[fi] = U[fi]; VT[fi] = V[fi];
        if (V[fi] > 0.5 || !inFace(q, c, p.N) || q[c] == 0 || q[c] == p.N) continue;
        float s = 0.0, n = 0.0;
        for (int d = 0; d < 4; d++) for (int sg = -1; sg <= 1; sg += 2) {
            int4 nb = q + sg * ax(d);
            if (!inFace(nb, c, p.N)) continue;
            int ni = c * MM + enc(nb, p.M);
            if (V[ni] > 0.5) { s += U[ni]; n += 1.0; }
        }
        if (n > 0.0) { UT[fi] = s / n; VT[fi] = 1.0; }
    }
}
// 水面までの距離を、ほんとうの距離に近づける（形は変えずに、坂を 1 にそろえる。数回だけ）
kernel void redist(device const float* phi [[buffer(0)]], device const float* phi0 [[buffer(1)]], device float* phiT [[buffer(2)]], constant P& p [[buffer(3)]], uint id [[thread_position_in_grid]]) {
    int MM = p.M * p.M * p.M * p.M; if (int(id) >= MM) return;
    int4 q = dec(id, p.M); if (!inCell(q, p.N)) { phiT[id] = phi[id]; return; }
    float f = phi[id], s0 = phi0[id] / sqrt(phi0[id] * phi0[id] + p.dx * p.dx), g2 = 0.0;
    for (int c = 0; c < 4; c++) {
        int4 lo = q - ax(c), hi = q + ax(c);
        float fl = inCell(lo, p.N) ? phi[enc(lo, p.M)] : f, fh = inCell(hi, p.N) ? phi[enc(hi, p.M)] : f;
        float a = (f - fl) / p.dx, b = (fh - f) / p.dx;
        if (s0 > 0.0) { float ap = max(a, 0.0), bm = min(b, 0.0); g2 += max(ap * ap, bm * bm); }
        else { float am = min(a, 0.0), bp = max(b, 0.0); g2 += max(am * am, bp * bp); }
    }
    phiT[id] = f - 0.3 * p.dx * s0 * (sqrt(g2) - 1.0);
}
"""

final class NS4 {
    static var syncAll = false                                        // 確かめの絵：1 コマごとに計算の終わりを待つ（ちょうどその時刻の水に）
    let N: Int, M: Int, MM: Int, dev: MTLDevice, queue: MTLCommandQueue
    private var ps: [String: MTLComputePipelineState] = [:]
    var U, UT, V, VT, phi, phiT, phi0, pr, rh, vW, vF: MTLBuffer
    var par = NS4Params()
    let H: Float
    var stepMs = 0.0                                                  // 1 歩の時間（ミリ秒、GPU）
    let lock = NSLock(); var inFlight = false, pendDt = 0.0, stepCount = 0
    var sliceKey = -1, sliceCache = NS4Mesh()
    var lastOutflow = 0.0                                             // 穴から出ていく量（世界の単位：1 秒あたりの 4 次元の体積）
    var phiCPU: [Float] = [], phiDisp: [Float] = [], lastVol = 0.0, resultID = 0, meshID = -1, meshCache = NS4Mesh(), meshBusy = false
    init?(N: Int = 32, H: Float = Float(OrigamiState.half)) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        dev = d; queue = q; self.N = N; M = N + 1; MM = M * M * M * M; self.H = H
        let lib: MTLLibrary
        do { lib = try d.makeLibrary(source: ns4Shader, options: nil) } catch { print("4D の水のシェーダーを作れなかった：", error); return nil }
        for n in ["advU", "advPhi", "jet", "force", "visc", "smoothPhi", "vortW", "vortF", "vortAdd", "rhs", "press", "proj", "valid", "extrap", "redist"] {
            guard let f = lib.makeFunction(name: n), let p = try? d.makeComputePipelineState(function: f) else { print("4D の水の計算を作れなかった：", n); return nil }
            ps[n] = p
        }
        func buf(_ n: Int) -> MTLBuffer? { d.makeBuffer(length: n * 4, options: .storageModeShared) }
        guard let u = buf(4 * MM), let ut = buf(4 * MM), let v = buf(4 * MM), let vt = buf(4 * MM), let f = buf(MM), let ft = buf(MM), let f0 = buf(MM), let p = buf(MM), let r = buf(MM), let w = buf(MM), let fv = buf(4 * MM) else { return nil }
        vW = w; vF = fv
        U = u; UT = ut; V = v; VT = vt; phi = f; phiT = ft; phi0 = f0; pr = p; rh = r
        par.N = Int32(N); par.M = Int32(M); par.dx = 2 * H / Float(N)
        phiCPU = [Float](repeating: 1, count: MM)
    }
    /// 水位 h（−1 空 〜 1 いっぱい）の静かな水に
    func reset(level h: Float) {
        lock.lock(); let busy = inFlight; lock.unlock()
        if busy { queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() } }
        let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MM); for i in 0..<(4 * MM) { u[i] = 0 }
        let p = pr.contents().bindMemory(to: Float.self, capacity: MM); for i in 0..<MM { p[i] = 0 }
        let f = phi.contents().bindMemory(to: Float.self, capacity: MM)
        let lev = (h + 1) * 0.5 * Float(N)                              // 水面の高さ（格子の単位、w の下の端から）
        for l in 0..<M { for k in 0..<M { for j in 0..<M { for i in 0..<M {
            f[((l * M + k) * M + j) * M + i] = h <= -1 ? 2 * H : (Float(l) + 0.5 - lev) * par.dx   // 空：どこも遠く離れた空気
        } } } }
        phiCPU = Array(UnsafeBufferPointer(start: f, count: MM)); phiDisp = phiCPU; lastVol = h <= -1 ? 0 : volumeOf(phiCPU).0; resultID += 1
    }
    @inline(__always) func at(_ i: Int, _ j: Int, _ k: Int, _ l: Int) -> Int { ((l * M + k) * M + j) * M + i }
    /// 水の 4 次元の体積（世界の単位）と、水面の大きさ（体積を合わせる時に使う）
    func volume() -> (Double, Double) {
        let f = phi.contents().bindMemory(to: Float.self, capacity: MM), e = Double(par.dx) * 1.5
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
        func run(_ name: String, _ bufs: [MTLBuffer], _ p0: NS4Params? = nil) {
            guard let e = cb.makeComputeCommandEncoder(), let pp = ps[name] else { return }
            e.setComputePipelineState(pp)
            for (i, b) in bufs.enumerated() { e.setBuffer(b, offset: 0, index: i) }
            var p = p0 ?? par; e.setBytes(&p, length: MemoryLayout<NS4Params>.stride, index: bufs.count)
            e.dispatchThreads(MTLSize(width: MM, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, pp.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
            e.endEncoding()
        }
        for c in 0..<4 { var p = par; p.c = Int32(c); run("advU", [U, UT], p) }
        run("advPhi", [U, phi, phiT]); swap(&phi, &phiT); swap(&U, &UT)
        run("jet", [U, phi])
        var pf = par; pf.shift = 0; pf.swirlOn = 0; run("force", [U], pf)
        if par.nu > 0 { run("visc", [U, UT, phi]); swap(&U, &UT) }
        if par.vort > 0 { run("vortW", [U, phi, vW]); run("vortF", [U, phi, vW, vF]); run("vortAdd", [U, vF, phi]) }
        if par.smooth > 0 { run("smoothPhi", [phi, phiT]); swap(&phi, &phiT) }
        run("rhs", [U, phi, rh, pr])
        for it in 0..<iters { var p = par; p.par = Int32(it & 1); run("press", [pr, phi, rh], p) }
        run("proj", [U, pr, phi])
        run("valid", [phi, V, U])
        for _ in 0..<3 { run("extrap", [U, UT, V, VT]); swap(&U, &UT); swap(&V, &VT) }
        if redistEvery > 0 {
            if let bl = cb.makeBlitCommandEncoder() { bl.copy(from: phi, sourceOffset: 0, to: phi0, destinationOffset: 0, size: MM * 4); bl.endEncoding() }
            for _ in 0..<redistEvery { run("redist", [phi, phi0, phiT]); swap(&phi, &phiT) }
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
    /// x‐y の面で回す小さなゆらぎ（いちどだけ）
    func addSwirl(_ s: Float) {
        guard let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder(), let pp = ps["force"] else { return }
        var p = par; p.g = 0; p.dt = 0; p.swirlOn = 1; p.shift = s
        e.setComputePipelineState(pp); e.setBuffer(U, offset: 0, index: 0); e.setBytes(&p, length: MemoryLayout<NS4Params>.stride, index: 1)
        e.dispatchThreads(MTLSize(width: MM, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)); e.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
    }
    /// 速さのいちばん大きい値（世界の単位）
    func maxSpeed() -> Float {
        let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MM), f = phi.contents().bindMemory(to: Float.self, capacity: MM)
        var m: Float = 0
        for i in 0..<MM where f[i] < 0 { for c in 0..<4 { m = max(m, abs(u[c * MM + i])) } }
        return m
    }
    /// 水面の高さ（w、格子の単位）：x・y・z のマス (i, j, k) の柱で、水から空気に変わる所
    func surfaceW(_ i: Int, _ j: Int, _ k: Int) -> Float {
        let f = phi.contents().bindMemory(to: Float.self, capacity: MM)
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

// ---- 画面で動かす：計算は裏で（GPU が終わったら次を出す）、描くのは終わった分のうつし ----
extension NS4 {
    /// 1 コマ分：前の歩が終わっていれば、結果を写して（体積も数えて）次の歩を出す。終わっていなければ時間をためておく
    func tick(_ dt: Double, target: Double?, keepAir: Bool = false) {   // keepAir：空気が少ない時（86% 以上）は水を足す向きに合わせない（遊ぶモード：開いた口の下のうすい空気の層を守る）
        if Self.syncAll { queue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() }; lock.lock(); inFlight = false; lock.unlock() }
        lock.lock(); let busy = inFlight; lock.unlock()
        pendDt += dt
        if busy { return }
        // 終わった結果を写す（描く用）
        let f = phi.contents().bindMemory(to: Float.self, capacity: MM)
        phiCPU.withUnsafeMutableBufferPointer { b in _ = memcpy(b.baseAddress!, f, MM * 4) }
        let (v, a) = volumeOf(phiCPU)
        lastVol = v; resultID += 1
        // 穴（排水口・底の全開）から出ていく量：底の壁（w の下の端）の、開いている所の下向きの速さ × 面の広さ（4D では 3 次元の体積 dx³）
        do {
            let u = U.contents().bindMemory(to: Float.self, capacity: 4 * MM), h = Float(N) * 0.5, dx3 = Double(par.dx * par.dx * par.dx)
            var q = 0.0
            if par.open != 0 || par.hole > 0 {
                for k in 0..<N { for j in 0..<N { for i in 0..<N {
                    if par.open == 0 { if abs(Float(i) + 0.5 - h) >= par.hole || abs(Float(j) + 0.5 - h) >= par.hole || abs(Float(k) + 0.5 - h) >= par.hole { continue } }
                    let id = at(i, j, k, 0)
                    if phiCPU[id] < 0 { q += Double(max(0, -u[3 * MM + id])) * dx3 }
                } } }
            }
            lastOutflow += (q - lastOutflow) * 0.3                         // 少しなめらかに
        }
        // 描く水面：前の結果と半分ずつまぜて、ゆるやかに（細かい粒がちらちら出たり消えたりしないように）
        if phiDisp.count != MM { phiDisp = phiCPU } else { phiCPU.withUnsafeBufferPointer { s in phiDisp.withUnsafeMutableBufferPointer { d in for i in 0..<MM { d[i] = 0.5 * d[i] + 0.5 * s[i] } } } }
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
struct NS4Mesh { var p: [SIMD4<Float>] = []; var t1: [SIMD4<Float>] = []; var t2: [SIMD4<Float>] = []; var kind: [Float] = [] }   // t1・t2：点ごとの、水面に沿った 2 つの向き（4D。なめらかな面の向きを出す。0 なら三角形の向き）

extension NS4 {
    /// 水の皮：今の結果のものがあればそれを、なければ裏で作り始めて、前のものを返す（確かめの絵の時は、その場で作る）
    func wallMesh() -> NS4Mesh {
        lock.lock(); let have = meshCache, hid = meshID, busy = meshBusy, rid = resultID; lock.unlock()
        if hid == rid { return have }
        if Self.syncAll { let m = buildMesh(phiDisp.count == MM ? phiDisp : phiCPU); lock.lock(); meshCache = m; meshID = rid; lock.unlock(); return m }
        if !busy {
            lock.lock(); meshBusy = true; lock.unlock()
            let snap = phiDisp.count == MM ? phiDisp : phiCPU           // 写しを持っておく（次の結果は別の配列に書かれる）
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let m = self.buildMesh(snap)
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
    func buildMesh(_ phiSnap: [Float]) -> NS4Mesh {
        var out = NS4Mesh()
        out.p.reserveCapacity(120_000); out.kind.reserveCapacity(40_000)
        let n = N, Hf = H, dx = par.dx
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
                @inline(__always) func vv(_ u: Int, _ v: Int, _ t: Int) -> Float { F[base + max(0, min(n - 1, u)) * s0 + max(0, min(n - 1, v)) * s1 + max(0, min(n - 1, t)) * s2] }
                // 点の水面の向き（φ の坂）から、水面に沿った 2 つの向き
                @inline(__always) func tang(_ g: SIMD3<Float>) -> (SIMD4<Float>, SIMD4<Float>) {
                    let l = simd_length(g); if l < 1e-9 { return (.zero, .zero) }
                    let gn = g / l, h: SIMD3<Float> = abs(gn.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
                    let a1 = simd_normalize(simd_cross(gn, h)), a2 = simd_cross(gn, a1)
                    return (dir4(a1), dir4(a2))
                }
                for t in -1..<n { let t0 = max(0, t), t1 = min(n - 1, t + 1)
                for v in -1..<n { let v0 = max(0, v), v1 = min(n - 1, v + 1)
                    // この行（u の向き）に水面が無ければ、まとめて飛ばす
                    var anyNeg = false, anyPos = false
                    for tt in [t0, t1] { for vv in [v0, v1] { let rb = base + vv * s1 + tt * s2; for u in 0..<n { if F[rb + u * s0] < 0 { anyNeg = true } else { anyPos = true }; if anyNeg && anyPos { break } } } }
                    if !(anyNeg && anyPos) { continue }
                for u in -1..<n {
                    let u0 = max(0, u), u1 = min(n - 1, u + 1)
                    var neg = 0
                    for b in 0..<8 {
                        let x = F[base + ((b & 1) != 0 ? u1 : u0) * s0 + ((b & 2) != 0 ? v1 : v0) * s1 + ((b & 4) != 0 ? t1 : t0) * s2]
                        c[b] = x; if x < 0 { neg += 1 }
                    }
                    if neg == 0 || neg == 8 { continue }
                    for b in 0..<8 {
                        let uu = u + (b & 1), vq = v + ((b >> 1) & 1), tq = t + ((b >> 2) & 1)
                        cpv[b] = SIMD3(coord(uu), coord(vq), coord(tq))
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
                    let f0 = Float(i0 == 0 ? -1 : 1) * Hf, f1 = Float(i1 == 0 ? -1 : 1) * Hf
                    @inline(__always) func P(_ x: Float, _ y: Float) -> SIMD4<Float> { var r = SIMD4<Float>(0, 0, 0, 0); r[a] = x; r[b] = y; r[o[0]] = f0; r[o[1]] = f1; return r }
                    // 行 j の水の範囲（a の向き）：はじめの続き 1 つ（なければ nil）
                    func span(_ j: Int) -> (Float, Float)? {
                        var lo = -1, hi = -1
                        for i in 0..<n where F[base + i * sa + j * sb] < 0 { if lo < 0 { lo = i }; hi = i } 
                        if lo < 0 { return nil }
                        func cross(_ i: Int, _ k: Int) -> Float {   // マス i（水）と k（空気）のあいだの水面
                            let x = F[base + i * sa + j * sb], y = F[base + k * sa + j * sb]; return coord(i) + (coord(k) - coord(i)) * x / (x - y)
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
        return out
    }
}

// ---- 輪切り：4D の水を 1 枚切って（軸 a ＝ 一定）、残りの 3 つの向きの 3D の水を取り出す（まわりは空気として閉じる：水面も壁に触れている所も）----
extension NS4 {
    func sliceMesh(axis a: Int, index k: Int) -> NS4Mesh {
        let key = (resultID * 8 + a) * 64 + k
        if key == sliceKey { return sliceCache }
        var out = NS4Mesh()
        let n = N, Hf = H, dx = par.dx, F = phiDisp.count == MM ? phiDisp : phiCPU
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
