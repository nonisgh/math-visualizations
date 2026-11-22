// 三角形で描く（超立方体に合わせた描き方）：面は四角を 2 つの三角形に、線は画面の上で太さの決まった帯に、目印の玉は向きのそろった丸い板（奥行きつき）に。
//   4 倍のぼかし（4×MSAA）で、ふちも線もなめらか。画面の細かさ 100% でも軽い（光の道を画素ごとに飛ばす描き方より、画面の部品が得意な描き方）。
//   色の付け方は、光で描くシェーダー（tlShader）の部品をそのまま使う（stdShade・plate・glossy）。面は毎コマ奥から手前へ並べて重ねる（ウェブ版の「正確」と同じ）。
//   流れ：① 4×MSAA の明るさの絵（半精度）に、背景 → 玉（奥行きを書く）→ 面（奥行きを見るだけ）→ 線（足し合わせ）
//         ② ぼかしをまとめた絵を、画面へ（明るい所をやわらかく丸める仕上げも、ここで 1 回だけ）
import MetalKit
import simd

/// 積分の三角形の頂点（位置・色。色は濃さを掛けてある）と、まとめ（足し合わせか、ふつうに重ねるか）
struct IntVert { var p: SIMD4<Float>; var c: SIMD4<Float> }
/// 積分の玉（本物の球）：真ん中と半径・回す角と濃さ
struct IntSphere {
    var c: SIMD4<Float>; var m: SIMD4<Float>
    // だ円体のとき：玉の 3 本の半径の軸（写した向きと長さ）。0 なら半径 c.w のまんまるの球。4D で回すと玉は つぶれて写る
    var ax = SIMD4<Float>(0, 0, 0, 0), ay = SIMD4<Float>(0, 0, 0, 0), az = SIMD4<Float>(0, 0, 0, 0)
}
struct IntTriBatch { var add: Bool; var verts: [IntVert]; var spin: Float = 0; var depth = false }   // depth：奥行きを見て描く（不透明な輪切りの形）
struct RasterU {
    var VP = matrix_identity_float4x4                 // 景色（GPU の座標）→ 画面
    var vp = SIMD4<Float>(0, 0, 0, 0)                  // 絵の幅・高さ（画素）・ふつうの線の太さ（画素）・線の濃さ
    // 3D の奥を暗く（ウェブ版の brightOf）：カメラからの距離のいちばん近い・遠い、手前の明るさ・奥の明るさ
    var dz = SIMD4<Float>(0, 1, 1, 1)
    // 4D：手前を光らせる強さ・奥を乗算する強さ・形どうしの映り込みの強さ・映り込みの球の半径
    var fx = SIMD4<Float>(0, 0, 0, 0)
    // 映り込みの絵を撮った所（形を包む箱の真ん中）と、箱の半分の大きさ（w：スタジオの光の帯の強さ）
    var pc = SIMD4<Float>(0, 0, 0, 0)
    var pb = SIMD4<Float>(1, 1, 1, 0)
    // 奥の目印の玉の画面の上の真ん中（画素）と半径（画素）。w：1 なら手前の目印と重なった所を乗算に
    var mk = SIMD4<Float>(0, 0, 0, 0)
    // 密度の乗算：x つぶれた胞ほど（4D）・y 斜めから見た面ほど（3D）の強さ
    var sq = SIMD4<Float>(0, 0, 0, 0)
    // 線：x 胞の色の線を乗算でなじませる強さ
    var lx = SIMD4<Float>(0, 0, 0, 0)
}

let rasterShaderBody = """
struct RU { float4x4 VP; float4 vp; float4 dz; float4 fx; float4 pc; float4 pb; float4 mk; float4 sq; float4 lx; };
// ---- 形どうしの映り込み：形の真ん中から 6 方向（±x・±y・±z）を見た絵（2D の 6 枚重ね）。向き v の色を読む ----
//   描く時と同じ決まり：前 F・上 U・右 R＝F×U、画面の x＝v·R / v·F、y＝v·U / v·F（90° の画角）
constant float3 PF[6] = { float3(1, 0, 0), float3(-1, 0, 0), float3(0, 1, 0), float3(0, -1, 0), float3(0, 0, 1), float3(0, 0, -1) };
constant float3 PU[6] = { float3(0, 0, 1), float3(0, 0, 1), float3(0, 0, 1), float3(0, 0, 1), float3(0, 1, 0), float3(0, 1, 0) };
float3 probeRead(texture2d_array<float> t, float3 v) {
    float3 a = abs(v); uint f;
    if (a.x >= a.y && a.x >= a.z) f = v.x > 0.0 ? 0 : 1; else if (a.y >= a.z) f = v.y > 0.0 ? 2 : 3; else f = v.z > 0.0 ? 4 : 5;
    float3 F = PF[f], U = PU[f], R = cross(F, U);
    float fz = max(dot(v, F), 1e-5);
    float2 uv = float2(dot(v, R) / fz * 0.5 + 0.5, 0.5 - dot(v, U) / fz * 0.5);
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return t.sample(s, uv, f).rgb;
}
constant int QI[6] = { 0, 1, 2, 0, 2, 3 };
constant int RL_END[6] = { 0, 1, 1, 0, 1, 0 };
constant float RL_SIDE[6] = { -1, -1, 1, -1, 1, 1 };
constant float2 RB_CO[6] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, -1), float2(1, 1), float2(-1, 1) };
constant float2 QUV[4] = { float2(0, 0), float2(1, 0), float2(1, 1), float2(0, 1) };
// ---- 背景（tlf と同じ：次元おりがみの紺、真ん中が少し明るい）----
struct BGO { float4 pos [[position]]; float2 uv; };
vertex BGO rbgv(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); BGO o; o.pos = float4(p * 2.0 - 1.0, 1.0, 1); o.uv = p; return o; }
fragment float4 rbgf(BGO in [[stage_in]], constant U& u [[buffer(0)]]) {
    float2 nn = in.uv * 2.0 - 1.0;
    float3 d = normalize(u.F.xyz + u.R.xyz * nn.x * u.p.x * u.p.y + u.U.xyz * nn.y * u.p.x);
    float3 bg = mix(float3(0.010, 0.016, 0.040), float3(0.035, 0.045, 0.10), 0.5 + 0.5 * d.z);
    if (u.L3.y > 0.5) bg = mix(float3(0.020, 0.031, 0.086), float3(0.010, 0.014, 0.040), clamp(length(nn) * 0.7, 0.0, 1.0));
    return float4(bg, 1.0);
}
// ---- 面（四角を 2 つの三角形に。ord：奥から手前の順）----
struct FV { float4 pos [[position]]; float3 P; float3 n; float4 col; float2 uv; float2 L; float m; float s; float wr; float sqz; };
vertex FV rfv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Quad* Q [[buffer(1)]], const device uint* ord [[buffer(4)]], constant RU& r [[buffer(5)]]) {
    Quad q = Q[ord[iid]]; int k = QI[vid];
    float3 C = k == 0 ? q.a.xyz : k == 1 ? q.b.xyz : k == 2 ? q.c.xyz : q.d.xyz;
    FV o; o.P = C; o.pos = r.VP * float4(C, 1.0); o.n = q.n.xyz; o.col = q.col; o.uv = QUV[k];
    o.L = float2(length(q.b.xyz - q.a.xyz), length(q.d.xyz - q.a.xyz)); o.m = q.m.x;
    o.s = k == 0 ? q.a.w : k == 1 ? q.b.w : k == 2 ? q.c.w : q.d.w;     // 4D の奥行き（−1 手前 〜 ＋1 奥）
    o.wr = q.m.z;                                                       // 包む胞のぐあい（胞ごと。0〜1）
    o.sqz = q.m.w;                                                      // 胞のつぶれ具合（胞ごと。0〜1）
    return o;
}
fragment float4 rff(FV in [[stage_in]], constant U& u [[buffer(0)]]) {
    float3 d = normalize(in.P - u.eye.xyz);
    float e = min(min(in.uv.x * in.L.x, (1.0 - in.uv.x) * in.L.x), min(in.uv.y * in.L.y, (1.0 - in.uv.y) * in.L.y));
    float ek = (1.0 - smoothstep(0.012, 0.045, e)) * in.col.w;
    float4 g = u.L3.w > 0.5 ? stdShade(in.col.rgb, in.m, in.n, d, in.P, u) : plate(in.col.rgb, in.n, d, in.P, ek, u, in.m > 0.0 ? in.m : -1.0);
    if (u.L2.y > 0.5) return float4(g.rgb * g.a * 1.4, 0.0);          // ホログラム：足し合わせ
    return float4(g.rgb * g.a, g.a);                                    // 奥の色の上に、濃さ g.a で重ねる
}
// ---- 面（ふつうの時）：3D の奥ほど暗く ＋ 4D の手前は光る（足し合わせ）・奥は吸いこむ（乗算＝色つきのセロハン）----
//   2 つの出力で重ねる：出力 0 を足し、後ろの色に出力 1（色ごとの通す割合）を掛ける。
//   ふつうの重ねは 通す＝1−濃さ、足し合わせは 通す＝1（後ろを隠さない）、乗算は 通す＝1−濃さ×(1−色)
struct FO { float4 c [[color(0), index(0)]]; float4 t [[color(0), index(1)]]; };
// やわらかい乗算（pc.w：0〜1）：掛ける色（通す割合）を、先に少し灰色へ寄せて（色の強さを 45% まで弱め）、白へ寄せて（暗くする深さを 30% まで浅く。浅くしすぎると、光った白い所が広がる）から掛ける。
//   色は分かるまま、重なっても暗く沈みにくい＝明るい所との差が小さくなって目がつかれにくい
float3 softF(float3 f, float s) {
    if (s <= 0.0) return f;
    float lum = dot(f, float3(0.2126, 0.7152, 0.0722));
    float3 g = mix(f, float3(lum), 0.45 * s);
    return 1.0 - (1.0 - g) * (1.0 - 0.3 * s);
}
fragment FO rffm(FV in [[stage_in]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]], texture2d_array<float> pr [[texture(1)]]) {
    float3 d = normalize(in.P - u.eye.xyz);
    float e = min(min(in.uv.x * in.L.x, (1.0 - in.uv.x) * in.L.x), min(in.uv.y * in.L.y, (1.0 - in.uv.y) * in.L.y));
    float ek = (1.0 - smoothstep(0.012, 0.045, e)) * in.col.w;
    float4 g = u.L3.w > 0.5 ? stdShade(in.col.rgb, in.m, in.n, d, in.P, u) : plate(in.col.rgb, in.n, d, in.P, ek, u, in.m > 0.0 ? in.m : -1.0);
    // lx.w：面の濃さの倍率（展開図のふつうの立体で、うしろに隠れた面をうっすら描く時。0 はふつう＝1 倍）
    if (r.lx.w > 0.0) g.a *= r.lx.w;
    // 3D の奥：手前は明るく（1.25 倍）、奥ほど暗く（0.6 倍）＝立体感（ウェブ版の頂点の明るさと同じ式。ここでは画素ごと）
    float tz = smoothstep(0.0, 1.0, (length(in.P - u.eye.xyz) - r.dz.x) / max(r.dz.y - r.dz.x, 1e-3));
    float3 c = g.rgb * mix(r.dz.z, r.dz.w, tz);
    float a = g.a, gl = saturate(-in.s) * r.fx.x, k = max(saturate(in.s) * r.fx.y, r.sq.z);   // sq.z：展開図の色で乗算
    // 乗算の色：胞の色（光の当たり方ではなく、セロハンの色そのもの）。うすいガラスでも色が分かるように濃さを 2.5 倍に
    float3 filt = 1.0 - min(1.0, a * 2.5) * (1.0 - saturate(in.col.rgb));
    // 密度の乗算：同じガラスがせまく押しこまれた所ほど色が深い。
    //   A：4D でつぶれた胞ほど（胞のつぶれ具合 sqz）。B：斜めから見た面ほど（ガラスを通る道が長い＝1/cos）。
    //   どちらも、その分だけ乗算の割合と、色の濃さ（通す割合の下がり方）を上げる。ふつうの乗算（4D の奥）と強いほうを使う
    {
        float3 nq = dot(in.n, d) > 0.0 ? -in.n : in.n;
        float cq = saturate(dot(-d, nq)), sz = smoothstep(0.0, 1.0, saturate(in.sqz));
        float kq = saturate(r.sq.x * sz + r.sq.y * pow(1.0 - cq, 1.5));
        // 強いほうを選ぶ所は、なめらかに混ぜる（選びが変わる瞬間に色の濃さが段にならないように）
        float wq = smoothstep(-0.08, 0.08, kq - k);
        if (wq > 0.0) {
            float dens = (1.0 + 1.5 * r.sq.x * sz) * mix(1.0, min(1.0 / max(cq, 0.12), 4.0), r.sq.y);
            float3 fq = 1.0 - min(1.0, a * 2.5 * dens) * (1.0 - saturate(in.col.rgb));
            k = mix(k, max(k, kq), wq); filt = mix(filt, fq, wq);
        }
    }
    filt = softF(filt, r.pc.w);
    FO o;
    // 光る所は面をうすく（濃さを最大 6 割引き）＝後ろがよく透けるガラスのまま光る。足す光は強めて、明るさはほぼそのまま
    float ag = a * (1.0 - 0.6 * gl);
    o.c = float4(c * ag * (1.0 - k) * (1.0 + 1.2 * gl), ag * (1.0 - k) * (1.0 - gl));
    o.t = float4((1.0 - k) * (1.0 - ag * (1.0 - gl)) + k * filt, 1.0);
    // 外から包む胞（4D の手前。胞ごと）は本物の色ガラス：光がガラスを通る道の長さ（正面 1・斜めほど 1/cos で長い）だけ色を吸う（ビア・ランベルト）。
    //   正面はうすい色で中の胞の色がそのまま見え、斜めの面・ふちほど自分の色で濃く染まる（コップのふちが濃く見えるのと同じ）。
    //   ふちの濃い所は、ガラスの中で散った光が少し自分の色に光る
    float nw = saturate(in.wr) * r.fx.w;
    if (nw > 0.0) {
        float3 nv = dot(in.n, d) > 0.0 ? -in.n : in.n;
        float ct = saturate(dot(-d, nv)), L = 1.0 / max(ct, 0.12);
        float3 gc = saturate(in.col.rgb) * 0.92 + 0.06;
        float3 tb = softF(pow(gc, float3(0.16 * L)) * 0.96, r.pc.w);
        float3 ab = c * a * (1.0 - ct) * 0.7;
        o.c = float4(mix(o.c.rgb, ab, nw), mix(o.c.a, 0.0, nw));
        o.t = float4(mix(o.t.rgb, tb, nw), 1.0);
    }
    // 形どうしの映り込み（ツルピカ）：面で跳ね返った向きの先にある形の色を、6 方向の絵から読んで足す。
    //   絵は形を包む箱の真ん中から撮ったので、跳ね返った光が箱の壁に当たる所の向きで読む（箱の形の物は、まっすぐな辺がまっすぐ映る）。
    //   ふちほど強く映る（フレネル：正面 0.12 〜 ふちで 1）＝ガラスやつやのあるプラスチックの光り方
    // スタジオの光の帯（つや）：カメラのうしろ・少し左上に、ななめの細長いライトが 2 本（カメラについてくる）。
    //   正面を向いたガラスは、跳ね返った光がカメラのうしろへ向かうので、そこに置いたライトが「ななめの光の帯」として映る（商品写真のアクリルのつや）。
    //   q：跳ね返った向きを、カメラのうしろの面に写した位置（正面の面なら、ほぼ画面の上の位置と同じ。画角の半分の高さが 0.41）
    if (r.pb.w > 0.0) {
        float3 nb = dot(in.n, d) > 0.0 ? -in.n : in.n;
        float3 rb = reflect(d, nb);
        float rz = dot(rb, u.F.xyz);
        if (rz < -0.2) {
            float2 q = float2(dot(rb, u.R.xyz), dot(rb, u.U.xyz)) / -rz;
            float2 ax = normalize(float2(1.0, -1.15)), np = float2(-ax.y, ax.x);
            float2 q1 = q - float2(-0.07, 0.09), q2 = q - float2(-0.13, 0.03);
            float b1 = (1.0 - smoothstep(0.012, 0.034, abs(dot(q1, np)))) * (1.0 - smoothstep(0.22, 0.36, abs(dot(q1, ax))));
            float b2 = (1.0 - smoothstep(0.004, 0.012, abs(dot(q2, np)))) * (1.0 - smoothstep(0.16, 0.28, abs(dot(q2, ax))));
            float fb = 0.35 + 0.65 * pow(1.0 - saturate(dot(-d, nb)), 2.0);
            o.c.rgb += float3(0.95, 0.97, 1.0) * (b1 + 0.6 * b2) * fb * r.pb.w * 1.2 * (1.0 - 0.6 * k);
        }
    }
    if (r.fx.z > 0.0) {
        float3 nf = dot(in.n, d) > 0.0 ? -in.n : in.n;
        float3 rv = reflect(d, nf), oc = in.P - r.pc.xyz;
        float3 tb = (sign(rv) * r.pb.xyz - oc) / select(rv, float3(1e-6), abs(rv) < 1e-6);
        float t = max(min(min(tb.x, tb.y), tb.z), 0.0);
        float3 refl = probeRead(pr, oc + rv * t);
        float fr = 0.12 + 0.88 * pow(1.0 - saturate(dot(-d, nf)), 4.0);
        o.c.rgb += refl * fr * r.fx.z * (1.0 - 0.5 * k);
    }
    // 乗算を 2 回に分ける（sq.w：1 ＝ ふつうの順番の回、2 ＝ 最後にもう一度の回）。
    //   後ろの色に掛ける割合 t を、ふつうの順番の回で t^(1−mm)、最後の回で t^mm に分ける（掛けると元の t）。足す色は (1−mm) と mm に。
    //   mm は乗算の強さでなめらかに 0〜1 ＝ 乗算の強い所ほど、手前のガラスの上からも色が掛かる。前は強さ 0.15 で面ごと最後へ移していて、
    //   またぐたびにポンと切りかわっていた
    if (r.sq.w > 0.5) {
        float sz2 = smoothstep(0.0, 1.0, saturate(in.sqz));
        float kk = max(max(saturate(in.s) * r.fx.y, nw), r.sq.x * sz2);
        float mm = smoothstep(0.03, 0.25, kk);
        float3 T = max(o.t.rgb, float3(1e-4));
        //   面の色・つや（足す分）も同じ割合で分ける：mm＝1 なら前の「面ごと最後に描く」と同じ見た目、mm＝0 ならふつうの順番のまま
        if (r.sq.w > 1.5) { o.c *= mm; o.t = float4(pow(T, float3(mm)), 1.0); }
        else { o.c *= 1.0 - mm; o.t = float4(pow(T, float3(1.0 - mm)), 1.0); }
    }
    return o;
}
// ---- 面の奥行きだけを書く（線の見え隠れ用。色は書かない）----
fragment float4 rfd(FV in [[stage_in]]) { return float4(0.0); }
// ---- 線（両はしを画面へ写し、その間を太さの決まった帯に。ふちは 1 画素ぶんなめらかに）----
struct LV { float4 pos [[position]]; float3 col; float off; float hw; float a; float3 hue; float mul; };
vertex LV rlv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Rod* RD [[buffer(2)]], constant RU& r [[buffer(5)]], constant U& u [[buffer(0)]]) {
    Rod rd = RD[iid];
    // 線を奥行きで隠す時（展開図のふつうの立体）：面と同じ深さで争わないよう、線をカメラへ少し寄せる
    float3 pa = rd.a.xyz, pb = rd.b.xyz;
    if (r.lx.y > 0.001) { pa += normalize(u.eye.xyz - pa) * 0.006; pb += normalize(u.eye.xyz - pb) * 0.006; }
    float4 A = r.VP * float4(pa, 1.0), B = r.VP * float4(pb, 1.0);
    // 線の色：濃さ（手前 0.80 〜 奥 0.17）をそのまま色に（ウェブ版の edgeTint：わずかに青白い）。足し合わせではなく、ふつうに重ねる＝奥の線は暗い細い筋に
    LV o; o.col = rd.col.rgb * min(1.0, rd.col.w * 1.4); o.a = r.vp.w; o.hue = rd.col.rgb;
    // a.w が −10 より下＝胞の色の線（乗算でなじませる印。残りはつなぎ目の印）
    float fl = rd.a.w; bool tinted = fl < -9.5; if (tinted) fl += 10.0;
    o.mul = tinted ? r.lx.x : 0.0;
    if (A.w < 0.01 || B.w < 0.01) { o.pos = float4(2.0, 2.0, 2.0, 1.0); o.off = 0; o.hw = 0; o.a = 0; return o; }   // カメラの後ろ（めったにない）
    float2 hv = r.vp.xy * 0.5, sa = A.xy / A.w * hv, sb = B.xy / B.w * hv, dv = sb - sa;
    float len = length(dv); float2 dir = len > 1e-4 ? dv / len : float2(1, 0), nrm = float2(-dir.y, dir.x);
    // b.w：太さの倍率（0 はふつう＝1）。1 より細い線は芯が 1 画素に足りず、自然にうすく見える（賢い線の、立体の中を通る線）
    float hw = 0.5 * r.vp.z * (rd.b.w > 0.0 ? rd.b.w : 1.0), ext = hw + 1.0;      // 芯の半分の太さ・ぼかしの 1 画素を足した広さ
    int ei = RL_END[vid]; float side = RL_SIDE[vid];
    float4 P = ei == 0 ? A : B;
    // 端を少しのばして角をなめらかに。ただし分けた辺のつなぎ目（a.w：−1 は A 側・−2 は B 側・−3 は両方）はのばさない（重なって点々に光るので）
    bool keep = ei == 0 ? !(fl == -1.0 || fl == -3.0) : !(fl == -2.0 || fl == -3.0);
    float2 off = nrm * side * ext + dir * (ei == 0 ? -1.0 : 1.0) * (keep ? min(ext, 1.0) : 0.0);
    P.xy += off / hv * P.w;
    o.pos = P; o.off = side * ext; o.hw = hw;
    return o;
}
// 胞の色の線（乗算でなじませる）：明るい色の線を少し重ね、残りは同じ色の濃いめで後ろに掛ける＝ガラスのふちの厚みが濃く見えるような線
fragment FO rlfm(LV in [[stage_in]]) {
    float cov = clamp(in.hw + 0.5 - abs(in.off), 0.0, 1.0) * in.a, m = in.mul * 0.65, wn = 1.0 - m;
    FO o;
    o.c = float4(in.col * cov * wn, cov * wn);
    o.t = float4(wn * (1.0 - cov) + m * (1.0 - cov * (1.0 - saturate(in.hue * 0.55))), 1.0);
    return o;
}
fragment float4 rlf(LV in [[stage_in]]) {
    float cov = clamp(in.hw + 0.5 - abs(in.off), 0.0, 1.0) * in.a;
    return float4(in.col * cov, cov);                                    // ふつうに重ねる（濃さ cov。色は濃さを掛けてある）
}
// ---- 目印の玉（カメラに向いた丸い板に、球の光り方。奥行きを書く）----
struct BV { float4 pos [[position]]; float2 q; float4 col; float3 c; };
vertex BV rbv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Ball* BL [[buffer(3)]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    Ball b = BL[iid]; float2 q = RB_CO[vid];
    float3 P = b.p.xyz + (u.R.xyz * q.x + u.U.xyz * q.y) * b.p.w;
    BV o; o.pos = r.VP * float4(P, 1.0); o.q = q; o.col = b.col; o.c = b.p.xyz; return o;
}
fragment float4 rbf(BV in [[stage_in]], constant U& u [[buffer(0)]]) {
    float r2 = dot(in.q, in.q); if (r2 > 1.0) discard_fragment();
    float z = sqrt(1.0 - r2);
    float3 bn = normalize(u.R.xyz * in.q.x + u.U.xyz * in.q.y - u.F.xyz * z), d = normalize(in.c - u.eye.xyz);
    float3 c = in.col.w > 1.5 ? in.col.rgb * (0.85 + 0.35 * max(0.0, dot(bn, LD[0]))) + 0.25 * pow(max(0.0, dot(reflect(d, bn), LD[0])), 30.0) : glossy(in.col.rgb, bn, d, u);
    return float4(c, 1.0);
}
// ---- 手前と奥の頂点の目印：立体に隠れないよう最後に上から描く。奥（0 番）をふつうに、手前（1 番）は奥と重なった所だけ乗算
//   （ピンク × 水色＝青。ウェブ版の「重なったら乗算」と同じ。重なっていない所は自分の色のまま）----
struct MV { float4 pos [[position]]; float2 q; float4 col; float3 c; uint id; };
vertex MV rmv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Ball* BL [[buffer(7)]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    Ball b = BL[iid]; float2 q = RB_CO[vid];
    float3 P = b.p.xyz + (u.R.xyz * q.x + u.U.xyz * q.y) * b.p.w;
    MV o; o.pos = r.VP * float4(P, 1.0); o.q = q; o.col = b.col; o.c = b.p.xyz; o.id = iid; return o;
}
fragment FO rmf(MV in [[stage_in]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    float r2 = dot(in.q, in.q); if (r2 > 1.0) discard_fragment();
    float z = sqrt(1.0 - r2);
    float3 bn = normalize(u.R.xyz * in.q.x + u.U.xyz * in.q.y - u.F.xyz * z), d = normalize(in.c - u.eye.xyz);
    float3 c = in.col.rgb * (0.85 + 0.35 * max(0.0, dot(bn, LD[0]))) + 0.25 * pow(max(0.0, dot(reflect(d, bn), LD[0])), 30.0);
    bool over = in.id == 1 && r.mk.w > 0.5 && length(in.pos.xy - r.mk.xy) < r.mk.z;
    FO o;
    if (over) { o.c = float4(0, 0, 0, 0); o.t = float4(saturate(c), 1.0); }          // 重なった所：奥の目印の色に掛ける
    else { o.c = float4(c, 1.0); o.t = float4(0, 0, 0, 1.0); }                       // ふつう：上に塗る
    return o;
}
// ---- 座標軸の先の矢印（円すい。CG ソフトの軸の矢印）：底の円を 20 に分けて、横の三角形と底のふた。奥行きを書く。光り方は目印の玉と同じ ----
struct Cone { float4 a, b, col; };
struct CV { float4 pos [[position]]; float3 n; float3 P; float3 col; };
vertex CV rcv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Cone* CN [[buffer(6)]], constant RU& r [[buffer(5)]]) {
    Cone c = CN[iid]; uint seg = vid / 6, k = vid % 6;
    float3 A = c.a.xyz - c.b.xyz; float h = max(length(A), 1e-5), rr = c.b.w; float3 ax = A / h;
    float3 t = abs(ax.z) < 0.9 ? float3(0, 0, 1) : float3(1, 0, 0), e1 = normalize(cross(ax, t)), e2 = cross(ax, e1);
    float a0 = float(seg) * 6.2831853 / 20.0, a1 = float(seg + 1) * 6.2831853 / 20.0, am = (a0 + a1) * 0.5;
    float3 r0 = e1 * cos(a0) + e2 * sin(a0), r1 = e1 * cos(a1) + e2 * sin(a1), rm = e1 * cos(am) + e2 * sin(am);
    float3 P, n;
    if (k == 0)      { P = c.a.xyz;             n = normalize(rm * h + ax * rr); }
    else if (k == 1) { P = c.b.xyz + r0 * rr;   n = normalize(r0 * h + ax * rr); }
    else if (k == 2) { P = c.b.xyz + r1 * rr;   n = normalize(r1 * h + ax * rr); }
    else if (k == 3) { P = c.b.xyz;             n = -ax; }
    else if (k == 4) { P = c.b.xyz + r1 * rr;   n = -ax; }
    else             { P = c.b.xyz + r0 * rr;   n = -ax; }
    CV o; o.pos = r.VP * float4(P, 1.0); o.n = n; o.P = P; o.col = c.col.rgb; return o;
}
fragment float4 rcf(CV in [[stage_in]], constant U& u [[buffer(0)]]) {
    float3 d = normalize(in.P - u.eye.xyz), n = normalize(in.n); if (dot(n, d) > 0.0) n = -n;
    float3 c = in.col * (0.8 + 0.4 * max(0.0, dot(n, LD[0]))) + 0.3 * pow(max(0.0, dot(reflect(d, n), LD[0])), 30.0);
    return float4(c, 1.0);
}
// ---- 仕上げ：ぼかしをまとめた明るさの絵を画面へ（tlf の最後と同じ丸め方）----
struct TO { float4 pos [[position]]; float2 uv; };
vertex TO rtv(uint vid [[vertex_id]]) { float2 p = float2((vid << 1) & 2, vid & 2); TO o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = float2(p.x, 1.0 - p.y); return o; }
fragment float4 rtf(TO in [[stage_in]], texture2d<float> t [[texture(0)]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 acc = t.sample(s, in.uv).rgb;
    // 色温度（lx.z：−1 青み 〜 0 そのまま 〜 ＋1 暖かみ）：赤と青の割合をずらし、明るさ（輝度）は変えない＝写真の色温度と同じ考え
    float tk = r.lx.z;
    if (tk != 0.0) {
        float Y0 = dot(acc, float3(0.2126, 0.7152, 0.0722));
        acc *= float3(1.0 + 0.30 * tk, 1.0 + 0.06 * tk, 1.0 - 0.34 * tk);
        float Y1 = dot(acc, float3(0.2126, 0.7152, 0.0722));
        acc *= Y1 > 1e-5 ? Y0 / Y1 : 1.0;
        acc = max(acc, 0.0);
    }
    if (u.L3.w > 0.5) { float3 k = step(float3(0.85), acc); acc = mix(acc, 0.85 + 0.15 * (1.0 - exp(-(acc - 0.85) / 0.15)), k); return float4(acc, 1.0); }
    acc = 1.0 - exp(-acc * 1.25);
    return float4(pow(acc, float3(0.95)), 1.0);
}
// ---- 積分の三角形（頂点ごとの色。色は濃さを掛けてある）：奥行きを見ずに、ふつうに重ねる／足し合わせる ----
struct IVx { float4 p; float4 c; };
struct IVo { float4 pos [[position]]; float4 c; float m; float4 cf [[flat]]; };   // cf：まぜない値（サイコロの目の番号と色）
vertex IVo riv(uint vid [[vertex_id]], const device IVx* T [[buffer(8)]], constant RU& r [[buffer(5)]]) {
    IVo o; o.pos = r.VP * float4(T[vid].p.xyz, 1.0); o.c = T[vid].c; o.m = T[vid].p.w; o.cf = T[vid].c; return o;
}
// 七色の帯の m 番目の色（ウェブ版の band と同じ：色相 0.82×(m＋0.5)／7・彩度 1・明るさ 0.58）
float3 bandC(float m) { float h = 0.82 * (m + 0.5) / 7.0; float3 k = clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); return 0.58 + 0.84 * (k - 0.5); }
// p.w ＜ 0 の頂点＝レインボーボール：c.xyz＝玉の上の位置（単位球）・c.w＝陰の明るさ・−p.w＝濃さ。
//   帯の色は画素ごとに決める（三角形ごとだと境目が階段になる）。境目は 1 画素ぶんだけ隣の色と混ぜる＝なめらかで、ぼけない
// ---- サイコロの目（画像なし：画素ごとに「点の中か」を計算）。p.w ≤ −2 の頂点：c.xy＝面の上の位置（0〜1、v が上）・
//   c.z＝目の数 ＋ 100 × 形（0 点の粒の数字・1 ふつうのサイコロの点）＋ 1000 × 塗る（1 サイコロの面ごと塗る・0 点だけ重ねる）・c.w＝色（RGB を 1 つの数に）・濃さ ＝ −p.w − 2
constant int DICE_DIG[10] = {31599, 11415, 29671, 29647, 23497, 31183, 31215, 29257, 31727, 31695};
float dcov(float2 uv, float2 c, float r, float w) { float d = length(uv - c); return 1.0 - smoothstep(r - w, r + w, d); }
float diceCov(float2 uv, int num, int style, float w, float rk) {
    if (style == 1) {
        float r = 0.092 * rk, L = 0.26, M = 0.5, H = 0.74, c = 0.0;
        if (num % 2 == 1) c = max(c, dcov(uv, float2(M, M), r, w));
        if (num >= 2) { c = max(c, dcov(uv, float2(L, H), r, w)); c = max(c, dcov(uv, float2(H, L), r, w)); }
        if (num >= 4) { c = max(c, dcov(uv, float2(H, H), r, w)); c = max(c, dcov(uv, float2(L, L), r, w)); }
        if (num == 6) { c = max(c, dcov(uv, float2(L, M), r, w)); c = max(c, dcov(uv, float2(H, M), r, w)); }
        return c;
    }
    int nd = num >= 10 ? 2 : 1, cols = nd == 2 ? 7 : 3;
    float p = nd == 2 ? 0.118 : 0.15, x0 = 0.5 - 0.5 * float(cols - 1) * p, y0 = 0.5 + 2.0 * p;
    int ci = int(floor((uv.x - x0) / p + 0.5)), ri = int(floor((y0 - uv.y) / p + 0.5));
    if (ci < 0 || ci >= cols || ri < 0 || ri > 4) return 0.0;
    int dg = num, col = ci;
    if (nd == 2) { if (ci == 3) return 0.0; dg = ci < 3 ? num / 10 : num % 10; col = ci < 3 ? ci : ci - 4; }
    if (((DICE_DIG[dg] >> ((4 - ri) * 3 + (2 - col))) & 1) == 0) return 0.0;
    return dcov(uv, float2(x0 + float(ci) * p, y0 - float(ri) * p), 0.38 * p * rk, w);
}
float4 diceF(IVo in) {
    float2 uv = in.c.xy; float w = max(length(fwidth(uv)) * 0.75, 1e-4);
    int code = int(in.cf.z + 0.5), fill = code / 1000, style = (code / 100) % 10, num = code % 100;
    int pk = int(in.cf.w);                                              // 色の数はちょうどの整数（＋0.5 すると 2^24 近くで丸めがずれる）
    float3 col = float3(float((pk >> 16) & 255), float((pk >> 8) & 255), float(pk & 255)) / 255.0;
    float a = -in.m - 2.0;
    float cov = diceCov(uv, num, style, w, 1.0);
    if (fill == 0) {                                                   // 点だけ重ねる：まわりにうすい影の輪（明るい面の上でも見えるように）
        float ring = diceCov(uv, num, style, w * 1.5, 1.38), al = max(cov, 0.55 * ring) * a;
        if (al < 0.003) discard_fragment();
        return float4(col * cov * a, al);
    }
    // サイコロの面：ふちを少し暗く（角の丸い板のように）、目は白く、まわりにうすい影（彫ったように）
    float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float3 base = col * mix(0.6, 1.0, smoothstep(0.0, 0.09, e));
    float sh = diceCov(uv, num, style, w * 2.0, 1.3);
    float3 o = mix(base * (1.0 - 0.35 * sh), float3(0.97, 0.97, 1.0), cov);
    if (fill == 2) {                                                   // あたりの面：金のふち（内側へやわらかく光る）
        float g = 1.0 - smoothstep(0.0, 0.075, e), g2 = 1.0 - smoothstep(0.0, 0.2, e);
        o = mix(o, float3(1.0, 0.83, 0.35), 0.9 * g) + float3(0.35, 0.25, 0.05) * g2 * 0.5;
    }
    return float4(o * a, a);
}
fragment float4 rif(IVo in [[stage_in]], constant float& spin [[buffer(0)]]) {
    if (in.m < -1.5) return diceF(in);
    if (in.m >= 0.0) return in.c;
    float a = -in.m;
    float3 s = normalize(in.c.xyz), ax = normalize(float3(0.62, 0.72, 0.3));
    float cs = cos(-spin), sn = sin(-spin);
    float3 q = s * cs + cross(ax, s) * sn + ax * dot(ax, s) * (1.0 - cs);
    float x = clamp((q.y + 1.0) * 0.5, 0.0, 0.99999) * 7.0, i = floor(x), fr = x - i, w = max(fwidth(x), 1e-4);
    // 境目をはさんで半画素ずつ：下からも上からも、境目でちょうど半分ずつ混ざる
    float3 col = mix(bandC(i), bandC(min(i + 1.0, 6.0)), smoothstep(1.0 - 0.5 * w, 1.0 + 0.5 * w, fr));
    col = mix(col, bandC(max(i - 1.0, 0.0)), 1.0 - smoothstep(-0.5 * w, 0.5 * w, fr));
    return float4(col * in.c.w * a, a);
}
// ---- 積分の玉（本物の球を画素ごとに）：カメラを向いた板の上で、視線と球の交わりを 1 画素ずつ解く。輪郭も陰もまんまる、奥行きも本物の球の所に書く ----
//   c：真ん中と半径（だ円体は、いちばん長い半径）、m：x 回す角・y 濃さ。色は七色の帯（球の上の位置の高さで。傾いた軸のまわりに回す）
//   ax・ay・az：だ円体の 3 本の半径の軸（4D で回した玉は、写すと だ円体につぶれる）。全部 0 ならまんまるの球
struct SphI { float4 c; float4 m; float4 ax; float4 ay; float4 az; };
struct SphV { float4 pos [[position]]; float3 P; float4 c; float4 m; float3 a1 [[flat]]; float3 a2 [[flat]]; float3 a3 [[flat]]; };
float3x3 inv3(float3x3 m) {
    float3 r0 = cross(m[1], m[2]), r1 = cross(m[2], m[0]), r2 = cross(m[0], m[1]);
    return transpose(float3x3(r0, r1, r2)) * (1.0 / dot(m[0], r0));
}
vertex SphV rsv(uint vid [[vertex_id]], uint iid [[instance_id]], const device SphI* S [[buffer(9)]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    SphI s = S[iid]; float2 q = RB_CO[vid];
    float3 C = s.c.xyz, toE = normalize(u.eye.xyz - C);
    float3 rt = normalize(cross(abs(toE.z) < 0.95 ? float3(0, 0, 1) : float3(1, 0, 0), toE)), up = cross(toE, rt);
    float3 P = C + (rt * q.x + up * q.y) * s.c.w * 1.25 + toE * s.c.w;   // 球の手前に、少し大きめの板（遠近でふくらむ分）
    SphV o; o.pos = r.VP * float4(P, 1.0); o.P = P; o.c = s.c; o.m = s.m;
    bool ell = dot(s.ax.xyz, s.ax.xyz) > 0.0;
    o.a1 = ell ? s.ax.xyz : float3(s.c.w, 0, 0); o.a2 = ell ? s.ay.xyz : float3(0, s.c.w, 0); o.a3 = ell ? s.az.xyz : float3(0, 0, s.c.w);
    return o;
}
struct SphF { float4 col [[color(0)]]; float depth [[depth(any)]]; };
fragment SphF rsf(SphV in [[stage_in]], constant U& u [[buffer(0)]], constant RU& r [[buffer(5)]]) {
    // だ円体（まんまるの球も同じ）：視線をだ円体の中の単位球の座標へうつして、単位球との交わりを解く
    float3 e = u.eye.xyz, d = normalize(in.P - e);
    float3x3 Mi = inv3(float3x3(in.a1, in.a2, in.a3));
    float3 o2 = Mi * (e - in.c.xyz), d2 = Mi * d;
    float A = dot(d2, d2), b = dot(o2, d2), cc = dot(o2, o2) - 1.0, disc = b * b - A * cc;
    if (disc < 0.0) discard_fragment();
    float t = (-b - sqrt(disc)) / A;
    float3 H = e + d * t, n = normalize(transpose(Mi) * (o2 + d2 * t));
    // 帯の色は、真ん中から見たその点の向き（まんまるの球では面の向きと同じ。つぶれた玉でも高さで帯になる）。
    //   景色の向き（y が上）に：描く側は z が上なので (x, z, −y)
    float3 hv = normalize(H - in.c.xyz);
    float3 sv = float3(hv.x, hv.z, -hv.y), ax = normalize(float3(0.62, 0.72, 0.3));
    float an = -in.m.x, cs = cos(an), sn = sin(an);
    float3 q = sv * cs + cross(ax, sv) * sn + ax * dot(ax, sv) * (1.0 - cs);
    float x = clamp((q.y + 1.0) * 0.5, 0.0, 0.99999) * 7.0, i = floor(x), fr = x - i, w = max(fwidth(x), 1e-4);
    float3 col = mix(bandC(i), bandC(min(i + 1.0, 6.0)), smoothstep(1.0 - 0.5 * w, 1.0 + 0.5 * w, fr));
    col = mix(col, bandC(max(i - 1.0, 0.0)), 1.0 - smoothstep(-0.5 * w, 0.5 * w, fr));
    float sh = 0.45 + 0.55 * max(dot(n, -d), 0.0);
    float a = in.m.y;
    float4 cl = r.VP * float4(H, 1.0);
    SphF o; o.col = float4(col * sh * a, a); o.depth = cl.z / cl.w; return o;
}
"""

/// 三角形で描く 1 つの窓の道具（パイプライン・4×MSAA の絵）
final class OrigamiRaster {
    private let device: MTLDevice
    // 奥行きの下描きのずらし（奥へ。ごく小さな差までは「同じ深さ」として、どの面も手前に描く）
    static let prepassBias: Float = 16, prepassSlope: Float = 1
    private let bgP, faceP, faceAddP, lineP, lineNormP, ballP, toneP, faceP1, lineP1, coneP, markP, faceDepthP, intNormP, intAddP, sphP: MTLRenderPipelineState
    // 形どうしの映り込みの絵（6 方向 × 128 画素）と、映り込みの絵を撮る時に読ませる空の入れ物。
    //   128 画素で毎コマ撮る（256 画素だと GPU の仕事が倍に。2 コマに 1 回にすると、回している時に映り込みだけ 1 コマおきに遅れて、明るい線の映り込みがネオンのようにちらついた）
    private var probe: MTLTexture?, probeDummy: MTLTexture?
    static let probeSize = 128
    private let dsWrite, dsRead, dsAlways, dsBehind: MTLDepthStencilState
    private var msColor: MTLTexture?, msDepth: MTLTexture?, resolved: MTLTexture?
    static let samples = 4, hdr = MTLPixelFormat.rgba16Float

    init?(device d: MTLDevice) {
        let pre = tlShader.components(separatedBy: "fragment float4 tlf")[0]   // 光で描くシェーダーの形の入れ物と色付けの部品
        let lib: MTLLibrary
        do { lib = try d.makeLibrary(source: pre + rasterShaderBody, options: nil) } catch { print("三角形のシェーダーを作れなかった：", error); return nil }
        func pipe(_ v: String, _ f: String, blend: Int, ms: Bool = true, fmt: MTLPixelFormat = OrigamiRaster.hdr, noColor: Bool = false) -> MTLRenderPipelineState? {
            let p = MTLRenderPipelineDescriptor(); p.vertexFunction = lib.makeFunction(name: v); p.fragmentFunction = lib.makeFunction(name: f)
            p.colorAttachments[0].pixelFormat = fmt
            if ms { p.rasterSampleCount = Self.samples; p.depthAttachmentPixelFormat = .depth32Float }
            let c = p.colorAttachments[0]!
            if noColor { c.writeMask = [] }
            if blend == 1 {                                                    // 重ねる（色は濃さを掛けてある）
                c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            } else if blend == 3 {                                             // 足して、後ろの色に出力 1 を掛ける（ふつうの重ね＋乗算）
                c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .source1Color
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            } else if blend == 2 {                                             // 足し合わせ
                c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
            }
            return try? d.makeRenderPipelineState(descriptor: p)
        }
        func ds(_ write: Bool, _ cmp: MTLCompareFunction) -> MTLDepthStencilState? {
            let s = MTLDepthStencilDescriptor(); s.isDepthWriteEnabled = write; s.depthCompareFunction = cmp; return d.makeDepthStencilState(descriptor: s)
        }
        guard let a = pipe("rbgv", "rbgf", blend: 0), let b = (ProcessInfo.processInfo.environment["ORIGAMI_OLDFACE"] != nil ? pipe("rfv", "rff", blend: 1) : pipe("rfv", "rffm", blend: 3)), let b2 = pipe("rfv", "rff", blend: 2), let c = pipe("rlv", "rlf", blend: 2),
              let c1 = pipe("rlv", "rlfm", blend: 3), let e = pipe("rbv", "rbf", blend: 0), let f = pipe("rtv", "rtf", blend: 0, ms: false, fmt: .bgra8Unorm),
              let b1 = pipe("rfv", "rffm", blend: 3, ms: false), let c2 = pipe("rlv", "rlf", blend: 1, ms: false), let cn = pipe("rcv", "rcf", blend: 0), let mp = pipe("rmv", "rmf", blend: 3),
              let fd = pipe("rfv", "rfd", blend: 0, noColor: true), let bh = ds(false, .greater), let iN = pipe("riv", "rif", blend: 1), let iA = pipe("riv", "rif", blend: 2), let sp = pipe("rsv", "rsf", blend: 1),
              let w = ds(true, .lessEqual), let r = ds(false, .lessEqual), let al = ds(false, .always) else { print("三角形のパイプラインを作れなかった"); return nil }
        device = d; bgP = a; faceP = b; faceAddP = b2; lineP = c; lineNormP = c1; ballP = e; toneP = f; faceP1 = b1; lineP1 = c2; coneP = cn; markP = mp; faceDepthP = fd; intNormP = iN; intAddP = iA; sphP = sp; dsWrite = w; dsRead = r; dsAlways = al; dsBehind = bh
        let pd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdr, width: Self.probeSize, height: Self.probeSize, mipmapped: false)
        pd.textureType = .type2DArray; pd.arrayLength = 6; pd.usage = [.renderTarget, .shaderRead]; pd.storageMode = .private
        probe = d.makeTexture(descriptor: pd)
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdr, width: 1, height: 1, mipmapped: false)
        dd.textureType = .type2DArray; dd.arrayLength = 6; dd.usage = [.shaderRead]; dd.storageMode = .private
        probeDummy = d.makeTexture(descriptor: dd)
    }

    private func textures(_ w: Int, _ h: Int) -> Bool {
        if let t = msColor, t.width == w, t.height == h { return true }
        let c = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdr, width: w, height: h, mipmapped: false)
        c.textureType = .type2DMultisample; c.sampleCount = Self.samples; c.usage = .renderTarget; c.storageMode = .private
        let z = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        z.textureType = .type2DMultisample; z.sampleCount = Self.samples; z.usage = .renderTarget; z.storageMode = .private
        let r = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdr, width: w, height: h, mipmapped: false)
        r.usage = [.renderTarget, .shaderRead]; r.storageMode = .private
        msColor = device.makeTexture(descriptor: c); msDepth = device.makeTexture(descriptor: z); resolved = device.makeTexture(descriptor: r)
        return msColor != nil && msDepth != nil && resolved != nil
    }

    /// 1 コマ。rpd：画面（か確かめの絵）。extra：仕上げのあとに同じ絵へ足して描くもの（星屑・光の波）
    func encode(_ cb: MTLCommandBuffer, _ rpd: MTLRenderPassDescriptor, _ w: Int, _ h: Int, u: inout TLUni,
                quads: MTLBuffer, nq: Int, order: MTLBuffer, rods: MTLBuffer, nr: Int, balls: MTLBuffer, nb: Int, lineW: Float, lineA: Float, faceWrite: Bool, depth: SIMD4<Float>, fx4: SIMD4<Float>, probeAt: SIMD4<Float>, probeBox: SIMD4<Float>, squash: SIMD4<Float> = .zero, lineFx: SIMD4<Float> = .zero, cones: [TLCone] = [], marks: [TLBall] = [], nq2: Int = 0, nAx: Int = 0, shift: SIMD2<Float> = .zero, intTris: [IntTriBatch] = [], intSpheres: [IntSphere] = [], extra: (MTLRenderCommandEncoder) -> Void) {
        guard textures(w, h), let mc = msColor, let md = msDepth, let rs = resolved else { return }
        // カメラ：GPU の座標（右 R・上 U・前 F）。見る側を −z にして、tlf の光の道と同じ写し方（縦の画角 tanF・横÷縦）
        let R = SIMD3(u.R.x, u.R.y, u.R.z), Uv = SIMD3(u.U.x, u.U.y, u.U.z), F = SIMD3(u.F.x, u.F.y, u.F.z), B = -F, eye = SIMD3(u.eye.x, u.eye.y, u.eye.z)
        let view = simd_float4x4(SIMD4(R.x, Uv.x, B.x, 0), SIMD4(R.y, Uv.y, B.y, 0), SIMD4(R.z, Uv.z, B.z, 0), SIMD4(-simd_dot(R, eye), -simd_dot(Uv, eye), -simd_dot(B, eye), 1))
        let f = 1 / u.p.x, asp = u.p.y, zn: Float = 0.05, zf: Float = 2000
        let proj = simd_float4x4(SIMD4(f / asp, 0, 0, 0), SIMD4(0, f, 0, 0), SIMD4(0, 0, zf / (zn - zf), -1), SIMD4(0, 0, zn * zf / (zn - zf), 0))
        // 図形の移動：写したあとの画面の上で、平行にずらす（カメラは動かさない）
        let shiftM = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(shift.x, shift.y, 0, 1))
        var ru = RasterU(VP: shiftM * proj * view, vp: SIMD4(Float(w), Float(h), lineW, lineA), dz: depth, fx: fx4, pc: probeAt, pb: probeBox, sq: squash, lx: lineFx)
        // 乗算を 2 回に分ける時（nq2：最後にもう一度描く面の数。順番の表の nq 番目から）は、ふつうの順番の回を sq.w ＝ 1 に
        ru.sq.w = nq2 > 0 && u.L2.y <= 0.5 ? 1 : 0
        // ⓪ 形どうしの映り込みの絵：形の真ん中から 6 方向を、90° の画角で（面と線だけ。映り込みの中の映り込みはなし）
        let useProbe = fx4.z > 0 && nq > 0 && probe != nil
        if useProbe, let pt = probe, let dm = probeDummy {
            let C = SIMD3(probeAt.x, probeAt.y, probeAt.z), ps = Float(Self.probeSize)
            let pF: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
            let pU: [SIMD3<Float>] = [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(0, 1, 0)]
            let pproj = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, zf / (zn - zf), -1), SIMD4(0, 0, zn * zf / (zn - zf), 0))
            for fi in 0..<6 {
                let Fv = pF[fi], Uq = pU[fi], Rv = simd_cross(Fv, Uq), Bv = -Fv
                let pv = simd_float4x4(SIMD4(Rv.x, Uq.x, Bv.x, 0), SIMD4(Rv.y, Uq.y, Bv.y, 0), SIMD4(Rv.z, Uq.z, Bv.z, 0), SIMD4(-simd_dot(Rv, C), -simd_dot(Uq, C), -simd_dot(Bv, C), 1))
                var rp = ru; rp.VP = pproj * pv; rp.vp = SIMD4(ps, ps, 1, lineA); rp.fx.z = 0; rp.pb.w = 0; rp.sq.w = 0
                let pp = MTLRenderPassDescriptor()
                pp.colorAttachments[0].texture = pt; pp.colorAttachments[0].slice = fi
                pp.colorAttachments[0].loadAction = .clear; pp.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.022, blue: 0.055, alpha: 1)
                pp.colorAttachments[0].storeAction = .store
                guard let pe = cb.makeRenderCommandEncoder(descriptor: pp) else { break }
                pe.setCullMode(.none)
                pe.setVertexBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0); pe.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
                pe.setVertexBytes(&rp, length: MemoryLayout<RasterU>.stride, index: 5); pe.setFragmentBytes(&rp, length: MemoryLayout<RasterU>.stride, index: 5)
                pe.setVertexBuffer(quads, offset: 0, index: 1); pe.setVertexBuffer(rods, offset: 0, index: 2); pe.setVertexBuffer(order, offset: 0, index: 4)
                pe.setFragmentTexture(dm, index: 1)
                pe.setRenderPipelineState(faceP1); pe.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
                if nr > 0 { pe.setRenderPipelineState(lineP1); pe.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nr) }
                pe.endEncoding()
            }
        } else { ru.fx.z = 0 }
        // ① 4×MSAA の明るさの絵へ
        let p1 = MTLRenderPassDescriptor()
        p1.colorAttachments[0].texture = mc; p1.colorAttachments[0].resolveTexture = rs
        p1.colorAttachments[0].loadAction = .dontCare; p1.colorAttachments[0].storeAction = .multisampleResolve
        p1.depthAttachment.texture = md; p1.depthAttachment.loadAction = .clear; p1.depthAttachment.clearDepth = 1; p1.depthAttachment.storeAction = .dontCare
        guard let e = cb.makeRenderCommandEncoder(descriptor: p1) else { return }
        e.setCullMode(.none)
        e.setVertexBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0); e.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
        e.setVertexBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
        e.setFragmentTexture(useProbe ? probe : probeDummy, index: 1)
        e.setVertexBuffer(quads, offset: 0, index: 1); e.setVertexBuffer(rods, offset: 0, index: 2); e.setVertexBuffer(balls, offset: 0, index: 3); e.setVertexBuffer(order, offset: 0, index: 4)
        e.setRenderPipelineState(bgP); e.setDepthStencilState(dsAlways); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if nb > 0 { e.setRenderPipelineState(ballP); e.setDepthStencilState(dsWrite); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nb) }
        if !cones.isEmpty {
            var cs = cones
            e.setVertexBytes(&cs, length: MemoryLayout<TLCone>.stride * cs.count, index: 6)
            e.setRenderPipelineState(coneP); e.setDepthStencilState(dsWrite); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 120, instanceCount: cs.count)
        }
        // 面：展開図のふつうの立体の度合い（lx.y）がある間は、まず面の奥行きだけを書き、いちばん手前の面はそのまま、
        //   うしろに隠れた面は濃さ（1 − ふつうの度合い）で描く＝組み上がるにつれて、うしろの面がうっすら → だんだん濃く（パッと切りかわらない）
        var depthReady = false
        if nq > 0 {
            let fp = u.L2.y > 0.5 ? faceAddP : faceP
            if lineFx.y > 0.001 && !faceWrite {
                // 下描きの奥行きは少しだけ奥へずらして書く：同じ平面にぴったり重なった別の胞の面（z をつぶした展開図など）が、
                //   どれも「いちばん手前」として描かれるように（ずらさないと、画面の場所ごとに手前・うしろがでたらめに決まって市松もようにちらついた）
                e.setDepthBias(Self.prepassBias, slopeScale: Self.prepassSlope, clamp: 0)
                e.setRenderPipelineState(faceDepthP); e.setDepthStencilState(dsWrite); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
                e.setDepthBias(0, slopeScale: 0, clamp: 0)
                e.setRenderPipelineState(fp); e.setDepthStencilState(dsRead); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
                let hid = 1 - lineFx.y
                if hid > 0.004 {
                    var rh = ru; rh.lx.w = hid
                    e.setVertexBytes(&rh, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&rh, length: MemoryLayout<RasterU>.stride, index: 5)
                    e.setDepthStencilState(dsBehind); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
                    e.setVertexBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
                }
                depthReady = true
            } else {
                e.setRenderPipelineState(fp); e.setDepthStencilState(faceWrite ? dsWrite : dsRead); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
            }
        }
        // 乗算の残り（最後にもう一度）：乗算の強い所ほど、手前のガラスの上からも色を掛ける
        if nq > 0 && nq2 > 0 && ru.sq.w > 0.5 {
            var r2 = ru; r2.sq.w = 2
            e.setVertexBytes(&r2, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&r2, length: MemoryLayout<RasterU>.stride, index: 5)
            e.setVertexBuffer(order, offset: 4 * nq, index: 4)
            e.setRenderPipelineState(faceP); e.setDepthStencilState(dsRead); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq2)
            e.setVertexBuffer(order, offset: 0, index: 4)
            e.setVertexBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
        }
        // 積分の三角形（段の立方体の面・ドラゴンボールの玉と星）：奥行きを見ずに、並んだ順に重ねる（ウェブ版と同じ）
        for b in intTris where b.verts.count >= 3 {
            var vv = b.verts
            let len = MemoryLayout<IntVert>.stride * vv.count
            if len <= 4096 { e.setVertexBytes(&vv, length: len, index: 8) }
            else if let tb = device.makeBuffer(bytes: &vv, length: len, options: .storageModeShared) { e.setVertexBuffer(tb, offset: 0, index: 8) } else { continue }
            var sp = b.spin; e.setFragmentBytes(&sp, length: 4, index: 0)
            e.setRenderPipelineState(b.add ? intAddP : intNormP); e.setDepthStencilState(b.depth ? dsWrite : dsAlways)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vv.count)
        }
        // 積分の玉（本物の球を画素ごとに。奥行きを書く）
        if !intSpheres.isEmpty {
            var ss = intSpheres
            let len = MemoryLayout<IntSphere>.stride * ss.count
            if len <= 4096 { e.setVertexBytes(&ss, length: len, index: 9) }
            else if let sb = device.makeBuffer(bytes: &ss, length: len, options: .storageModeShared) { e.setVertexBuffer(sb, offset: 0, index: 9) }
            e.setRenderPipelineState(sphP); e.setDepthStencilState(dsWrite)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: ss.count)
        }
        // 線は面の上に足し合わせる（光で描く版と同じく、面に隠れない）
        // 線はふつう面の上に描く。展開図のふつうの立体の時（lx.y）は、奥行きを見て、うしろの面に隠れた線は描かない
        //   展開図のふつうの立体の時（lx.y：ふつうの度合い）は、面の奥行きを書いてから、見えている所はそのまま、
        //   面のうしろに隠れた所は濃さ（1 − ふつうの度合い）で描く＝組み上がるにつれて、奥の線がすーっと現れる
        if nr > 0 {
            e.setRenderPipelineState(u.cnt.w > 0.001 ? lineP : lineNormP)
            if lineFx.y > 0.001 && nq > 0 {
                if !faceWrite && !depthReady {
                    e.setDepthBias(Self.prepassBias, slopeScale: Self.prepassSlope, clamp: 0)
                    e.setRenderPipelineState(faceDepthP); e.setDepthStencilState(dsWrite); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nq)
                    e.setDepthBias(0, slopeScale: 0, clamp: 0)
                    e.setRenderPipelineState(u.cnt.w > 0.001 ? lineP : lineNormP)
                }
                e.setDepthStencilState(dsRead); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nr)
                let hidA = lineA * max(0, 1 - lineFx.y)
                // 座標軸（線の最後の nAx 本）は、展開図のすけない立体の中でもうっすら見せる（濃さ 45% 以上）
                let na = min(nAx, nr), hidAx = max(hidA, lineA * 0.45)
                if hidA > 0.004 || na > 0 {
                    var rh = ru; rh.vp.w = hidA
                    e.setDepthStencilState(dsBehind)
                    if hidA > 0.004 && nr - na > 0 {
                        e.setVertexBytes(&rh, length: MemoryLayout<RasterU>.stride, index: 5)
                        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nr - na)
                    }
                    if na > 0 {
                        rh.vp.w = hidAx
                        e.setVertexBytes(&rh, length: MemoryLayout<RasterU>.stride, index: 5)
                        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: na, baseInstance: nr - na)
                    }
                    e.setVertexBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
                }
            } else {
                e.setDepthStencilState(dsAlways); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nr)
            }
        }   // 宇宙の時だけ光る線（足し合わせ）
        // 手前と奥の頂点の目印：いちばん上に（立体に隠れない）。奥の目印の画面の上の丸（真ん中と半径）を渡して、手前の目印は重なった所だけ乗算
        //   3 番から先は置いた点（点のタブ）：乗算はせず、上に塗るだけ
        if marks.count >= 2 {
            var ms = marks
            let fc = SIMD3(ms[0].p.x, ms[0].p.y, ms[0].p.z), fr = ms[0].p.w, Rv = SIMD3(u.R.x, u.R.y, u.R.z)
            func px(_ p: SIMD3<Float>) -> SIMD3<Float> { let c = ru.VP * SIMD4(p, 1); return SIMD3((c.x / c.w * 0.5 + 0.5) * Float(w), (0.5 - c.y / c.w * 0.5) * Float(h), c.w) }
            let a = px(fc), b = px(fc + Rv * fr)
            ru.mk = SIMD4(a.x, a.y, simd_distance(SIMD2(a.x, a.y), SIMD2(b.x, b.y)), a.z > 0.01 ? 1 : 0)
            e.setVertexBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5); e.setFragmentBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
            let len = MemoryLayout<TLBall>.stride * ms.count
            if len <= 4096 { e.setVertexBytes(&ms, length: len, index: 7) }
            else if let mb = device.makeBuffer(bytes: &ms, length: len, options: .storageModeShared) { e.setVertexBuffer(mb, offset: 0, index: 7) }
            e.setRenderPipelineState(markP); e.setDepthStencilState(dsAlways); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: ms.count)
        }
        e.endEncoding()
        // ② 画面へ（仕上げ）＋ 星屑・光の波
        rpd.colorAttachments[0].loadAction = .dontCare
        guard let e2 = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        e2.setRenderPipelineState(toneP); e2.setFragmentTexture(rs, index: 0); e2.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
        e2.setFragmentBytes(&ru, length: MemoryLayout<RasterU>.stride, index: 5)
        e2.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        extra(e2)
        e2.endEncoding()
    }
}
