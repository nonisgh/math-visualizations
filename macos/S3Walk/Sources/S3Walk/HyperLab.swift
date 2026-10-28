// 超球（Metal 版の試作）：ウェブ版 hypersphere_beta.html の核を、Swift と Metal で描く。
//   左：3D の球をリング（緯度の円）を積んで作る。右：4D の超球を球殻（w 一定の 2 次元の球面）を積んで作り、4D で回して 3D へ遠近で写す。
//   左の「リング ↔ 右の球殻」が 1 つずつ対応する（2 次元とのアナロジー：円を積むと球、球を積むと超球）。
//   回転の対応はウェブ版と同じ：左の前後傾き（x 軸まわり）＝右の Y-W、左右傾き（y 軸まわり）＝右の X-W（向きは逆）、面内（z 軸まわり）＝右の X-Y。
//   Z-W 傾きは左の 3D には無い第 4 の軸への傾きで、左では「z′＝0 で切った断面」としてリングが動く・消える。
//   ウェブ版の角度・色・遠近（camW）・層の作り方はそのまま。切り欠き・4D カメラ・旅・学習などは、まだ（ウェブ版の窓で）
import SwiftUI
import MetalKit

/// 共通の状態（左右の画面とパネルで共有）
final class HyperLabState: ObservableObject {
    // 傾き（ラジアン）は、描く側が毎コマ読むふつうの値。パネルの表示は、手で変えた時と、自動で回している間は 1 秒に 10 回だけ更新する
    //   （毎コマ SwiftUI の画面を作り直すと、それだけで重くなってコマ数が落ちる）
    var pitch = 0.0                                                   // 前後傾き
    var roll = 0.0                                                    // 左右傾き
    var yaw = 0.0                                                     // 面内
    var zw = 0.0                                                      // Z-W 傾き
    private var uiAcc = 0.0
    var gpuL = 0.0, gpuR = 0.0                                        // 左右それぞれの 1 コマの GPU の時間（ミリ秒、ならした値）
    @Published var layers = 11
    @Published var auto = false
    @Published var mode = 0                                          // 0 ハイブリッド・1 ワイヤー・2 半透明
    @Published var camW = 3.8                                         // 4D の遠近（視点は +w 側の camW の所）
    @Published var hemi = 0                                           // 0 全球・1 北・2 南
    @Published var lzw = 0                                            // Z-W 傾きを左の球でどう見せる：0 断面（z′＝0 で切る）・1 影（投影）・2 両方
    // 断面カット（くさび形に切り欠いて中をのぞく。ウェブ版の「断面カット」）：基準 0 画面に固定・1 物体に固定（超球の経度）・2 ポリゴンカット
    //   （押した時に画面の手前を向いている 90° ぶんの網目を作らない。次に押すまで超球に固定）
    @Published var cutOn = false
    @Published var cutRef = 0
    @Published var cutAngDeg = 0.0                                    // 切り欠きの位置（画面に固定：0° 手前・90° 右／物体に固定：経度）
    @Published var cutWDeg = 120.0                                    // 開き具合
    var cutPhi = Double.pi * 1.75, polyArm = 0                        // ポリゴンカットの中心の経度（押した時に決める）・押した回数
    // 切り方：0 くさび（画面に固定・物体に固定・ポリゴンカット）・1 平面で切る（その平面より手前を消す）・2 4D で切る（超平面 w′ ＝ 一定の切り口だけ見る。ウェブ版の切断面）
    @Published var cutKind = 0
    @Published var planeDir = 0                                       // 平面の向き：0 画面の手前・1 右・2 上（画面に固定）・3 x・4 y・5 z（物体に固定）
    @Published var cutPos = 0.0                                       // 切り口の位置（−1〜1。平面は半径の何倍か、4D は w′ ＝ cutPos × R）
    @Published var cutSweep = false                                   // 切り口を自動で行ったり来たり
    @Published var cut4Axis = 3                                       // 4D で切る向き（超平面の法線）：0 x′・1 y′・2 z′・3 w′（見る人の向き。回すと斜めの切断にも）
    private var cutPhase = 0.0
    /// 切り口を自動で動かす（左の画面が毎コマ呼ぶ）
    func tickCut(_ dt: Double) {
        guard cutOn && cutSweep && cutKind != 0 else { return }
        cutPhase += dt * 0.45; cutPos = sin(cutPhase) * 0.95; bump()
    }
    @Published var gloss = 1.0                                        // 光沢（照り返しライト・映り込み）の強さ。0 で今までの見た目
    @Published var glare = true                                       // グレア（色を深く・ふちが白く光る・斜めの映り込みの帯）
    @Published var fps = 0                                            // 1 秒あたりのコマ数（左の画面で数える。1 秒ごとに更新）
    @Published var adaptive = true                                    // 止まっている間はコマ数を落とす（ProMotion のように。動かすとすぐ最高に戻す）
    @Published var walk = true                                        // 球面さんぽで歩いた跡と今いる所を描く（お遊び）
    @Published var axes = true                                        // 座標の矢印（左は x・y・z、右は x・y・z・w）
    @Published var axPlus = false                                     // 座標軸はプラスの向きだけ
    @Published var axThin = true                                      // 座標軸を細い線（平たい矢じり）で。切ると立体の矢印
    @Published var marksOn = true                                     // 球面さんぽの目印（通った目印＝チェックポイントは塗りつぶしと ✓）
    @Published var polesMode = 1                                      // 8 つの極：0 出さない・1 通ると出てくる・2 いつも出す（通った極は ✓）
    // 宇宙モード（球面さんぽの宇宙の景色）：さんぽと同じ 12000 個の星を超球に、背景は宇宙、網目は光る線。0 さんぽと同じ・1 入・2 切
    @Published var spaceMode = 0
    @Published var starsPct = 100.0                                   // 星の数（重い時は間引く）
    var spaceNow = false                                              // 今、宇宙モードか（描く側が毎コマ決める）
    // 球層の数をさんぽと連動（入れると、さんぽで増減したらこっちへ、こっちで増減したらさんぽへ。さんぽは 3〜21 なので、その間で）
    @Published var layersLink = false
    // さんぽの景色の画面（今いる所から見た S³。さんぽの窓と同じ景色を、描くだけ）。並び：order の順に［左上・左下・右］へ（0 3D の球・1 さんぽの景色・2 4D の超球）
    @Published var walkView = true
    // 自分を追う（さんぽの「自分中心」を広げたもの）：歩く人が真ん中（4D の手前、超球の正面）から「遊び」の角度より離れたら、
    //   傾き（Z-W・面内・前後・左右）を少しずつ動かして手前へ連れ戻す。遊び 0° ＝ いつも中心、90° ＝ 手前の半分は自由に横断して奥へ行きかけたら回す。
    //   「進む向きも合わせる」は、進む向きがいつも画面の上を向くように回す（さんぽの自分中心と同じ）
    @Published var followOn = false
    @Published var followSlack = 90.0                                 // 遊び（度）
    @Published var followSpeed = 1.0                                  // 戻す速さ
    @Published var followHeading = false                              // 進む向きも合わせる
    // ダイブ（超ズームで、さんぽの景色に入る）：diveT 0 ＝ 外から見た超球（ロングショット）、1 ＝ 中から見た景色。
    //   0〜0.3 で超球を景色と同じ向きへ回し、0.25〜0.92 で 4D のカメラを自分のいる所へ近づける（本当の 4D の遠近）、最後に景色へ溶かす
    @Published var diveOn = false
    @Published var diveFade = 0.0                                     // 景色の重ねぐあい（最後の溶け込み）
    @Published var diveBlend = true                                   // 最後にさんぽの景色へ溶かす（切ると、寄ったまま超球の網目で見続ける）
    var diveT = 0.0, diveManual = false
    /// ダイブを進める（左の画面が毎コマ呼ぶ）：約 3 秒で入る・出る。ズームのスライダーを動かしている間は手で
    func tickDive(_ dt: Double) {
        if !diveManual {
            let tgt = diveOn ? 1.0 : 0.0
            if diveT != tgt { diveT = tgt > diveT ? min(tgt, diveT + dt / 3.2) : max(tgt, diveT - dt / 2.4); bump() }
        }
        // 溶け込み：ズームの 0.86〜0.98 で少しずつ（段なしに）。表示の更新は変わった時だけ
        let x = max(0, min(1, (diveT - 0.86) / 0.12)), f = diveBlend ? x * x * (3 - 2 * x) : 0
        if abs(f - diveFade) > 0.01 || (f == 0 && diveFade != 0) || (f == 1 && diveFade != 1) { diveFade = f }
    }
    @Published var followDrift = 0.3                                  // ゆるく回す：遊びの中でも、弱い力で少しずつ自分の方へ回り続ける（止まって見えないように。奥へ縮む距離が分かる）
    /// 4D の回転（描く側の xf と同じ順：Z-W → 面内 X-Y → 前後 Y-W → 左右 X-W、向きは逆）
    func rot4(_ v0: SIMD4<Double>, _ a: SIMD4<Double>? = nil) -> SIMD4<Double> {
        let g = a ?? SIMD4(zw, yaw, pitch, roll)
        var v = v0
        for (i, j, ang) in [(2, 3, g[0]), (0, 1, g[1]), (1, 3, g[2]), (0, 3, -g[3])] where ang != 0 {
            let c = cos(ang), s = sin(ang), t = v[i] * c - v[j] * s
            v[j] = v[i] * s + v[j] * c; v[i] = t
        }
        return v
    }
    /// 自分を追う（左の画面が毎コマ呼ぶ）：遊びの外に出た分と、向きのずれを小さくするよう、傾きの 4 つを少しずつ動かす（数値で坂を下る）
    func tickFollow(_ dt: Double) {
        guard followOn, let src = Self.walkSource else { return }
        let w = src(), p = w.pos, f = w.fwd
        let slack = followSlack * .pi / 180, head = followHeading
        func cost(_ a: SIMD4<Double>) -> Double {
            let v = rot4(p, a), th = acos(max(-1, min(1, v.w)))
            var e = max(0, th - slack); e = e * e
            e += followDrift * 0.05 * th * th                              // ゆるく回す（弱い力。歩く速さよりずっとゆっくり）
            if head { let fv = rot4(f, a); e += 0.35 * (1 - fv.y) * max(0, 1 - th / 1.2) }   // 真ん中の近くで、進む向きを画面の上へ
            return e
        }
        var a = SIMD4(zw, yaw, pitch, roll)
        let e0 = cost(a); guard e0 > 1e-7 else { return }
        var g = SIMD4<Double>(0, 0, 0, 0); let hgt = 1e-4
        for k in 0..<4 { var b = a; b[k] += hgt; g[k] = (cost(b) - e0) / hgt }
        if !head { g[1] = 0 }                                            // 向きを合わせない時は、面内（X-Y）は回さない
        let gl = simd_length(g)
        if gl < 1e-6 { pitch += 0.02; bump(); return }                  // 真裏などで坂がない時は、少しずらす
        let step = min(followSpeed * 2.2 * dt, 3 * followSpeed * dt * gl) // 1 秒に最大 2.2 rad × 速さ
        a -= g / gl * step
        zw = Self.norm(a[0]); yaw = Self.norm(a[1]); pitch = Self.norm(a[2]); roll = Self.norm(a[3]); bump()
    }
    @Published var order = [0, 1, 2]
    static var walkRendererGet: (() -> Renderer?)?
    /// ダイブ中・自分を追う間は、さんぽの窓も画面のいちばん速いコマ数で（さんぽの「60 fps 前後」をゆるめる。景色がなめらかに流れるよう）
    static var boostWalk = false
    static var walkShells: (get: () -> Int, set: (Int) -> Void)?
    /// 連動の時、さんぽの層数を読んでこちらへ（毎コマ。変わっていれば形を作り直す）
    func pullLayers() {
        guard layersLink, let w = Self.walkShells else { return }
        let n = max(3, min(21, w.get()))
        if n != layers { layers = n; bump() }
    }
    /// こちらで層数を変えた：連動の時はさんぽへも
    func setLayers(_ n: Int) {
        let v = layersLink ? max(3, min(21, n)) : max(3, min(41, n))
        layers = v; bump()
        if layersLink, let w = Self.walkShells, w.get() != v { w.set(v) }
    }
    /// 球面さんぽの歩いた跡（S³ の上の長さ 1 の点。古い順）・今いる所・目印と通ったかどうか。アプリが起動した時に入れる（無ければ描かない）
    struct Walk { var trail: [SIMD4<Double>]; var pos: SIMD4<Double>; var marks: [SIMD4<Double>] = []; var hit: [Bool] = []; var poles: [Int] = []; var space = false; var fwd = SIMD4<Double>(0, 0, 1, 0)
        var vR = SIMD4<Double>(0, 0, 0, 0), vU = SIMD4<Double>(0, 0, 0, 0), vL = SIMD4<Double>(0, 0, 0, 0), fov = 70.0 }   // fwd：進む向き。vR・vU・vL：景色を写す向き（右・上・見ている向き）、fov：景色の縦の視野（度）   // poles：通った極（FIXED の番号）
    static var walkSource: (() -> Walk)?
    var viewYaw = 0.0, viewPitch = 0.0, viewDist = 7.5                // 右の 3D 視点（ドラッグで回す）
    var leftDist = 5.5
    var version = 0                                                   // 形が変わったら増やす（描く側は変わった時だけ作り直す）
    /// 形や向きが変わった：描く側は version で知る。パネルの表示（SwiftUI）は 1 秒に 12 回までにまとめる（ドラッグのたびに作り直すと、操作がひっかかる）
    func bump() {
        version &+= 1
        let now = CACurrentMediaTime()
        if now - lastSend > 0.08 { lastSend = now; objectWillChange.send() }
        else if !sendLater { sendLater = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.sendLater = false; self?.lastSend = CACurrentMediaTime(); self?.objectWillChange.send() } }
    }
    private var lastSend = 0.0, sendLater = false
    func reset() { pitch = 0; roll = 0; yaw = 0; zw = 0; viewYaw = 0; viewPitch = 0; viewDist = 7.5; leftDist = 5.5; bump() }
    static func norm(_ a: Double) -> Double { var x = (a + .pi).truncatingRemainder(dividingBy: 2 * .pi); if x < 0 { x += 2 * .pi }; return x - .pi }
    /// 自動で回す（ウェブ版の「複合」：前後と左右を 1 : 0.67 の速さで）
    func tick(_ dt: Double) {
        guard auto else { return }
        let d = 0.72 * dt
        pitch = Self.norm(pitch + d); roll = Self.norm(roll + d * 0.67); version &+= 1
        uiAcc += dt; if uiAcc >= 0.1 { uiAcc = 0; objectWillChange.send() }
    }
}

/// 描く頂点：位置・法線・色（w は透明度）
struct HLVert { var p: SIMD4<Float>; var n: SIMD4<Float>; var c: SIMD4<Float> }
/// 描く時の定数：key・rim は照り返しライトの向き（カメラについて回る）、camR・camU はカメラの右・上（グレアの帯）、g は（光沢・グレア・光を当てる・未使用）
/// 右の殻の毎コマの定数（シェーダーの HR）
struct HLRight { var m4 = matrix_identity_float4x4; var q = SIMD4<Float>(1, 1, 3.8, 1.55); var r = SIMD4<Float>(1.35, 48, 0, 0); var d = SIMD4<Float>(0.6, 0, 0, 0) }
/// 名前の札の頂点（位置・文字の絵の座標）
struct HLLabelVert { var p: SIMD4<Float>; var uv: SIMD4<Float> }
struct HLUni {
    var mvp = matrix_identity_float4x4; var model = matrix_identity_float4x4
    var eye = SIMD4<Float>(0, 0, 5, 1), key = SIMD4<Float>(0, 0, 1, 0), rim = SIMD4<Float>(0, 0, -1, 0)
    var camR = SIMD4<Float>(1, 0, 0, 0), camU = SIMD4<Float>(0, 1, 0, 0), g = SIMD4<Float>(1, 1, 1, 0)
    var cut = SIMD4<Float>(0, 0, 0, 0)                                // 断面カット：（0 なし・1 画面に固定・2 物体に固定・3 平面、中心の角、開きの半分）
    var cutN = SIMD4<Float>(0, 0, 1, 0)                               // 平面で切る：平面の向き（xyz）と位置（w）。向きの側（手前）を消す
}

private let hlShader = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 p; float4 n; float4 c; };
struct U { float4x4 mvp; float4x4 model; float4 eye; float4 key; float4 rim; float4 camR; float4 camU; float4 g; float4 cut; float4 cutN; };
struct O { float4 pos [[position]]; float3 n; float3 wp; float4 c; float ph; };   // ph：殻の経度（物体に固定の断面カット）
vertex O hlv(uint vid [[vertex_id]], constant V* vs [[buffer(0)]], constant U& u [[buffer(1)]]) {
    V v = vs[vid]; O o; float4 w = u.model * float4(v.p.xyz, 1.0);
    o.pos = u.mvp * w; o.wp = w.xyz; o.n = (u.model * float4(v.n.xyz, 0.0)).xyz; o.c = v.c; o.ph = 0.0; return o;
}
float4 lightHL(float3 nIn, float3 wp, float4 c, float roughAdd, constant U& u);
// 右の殻（GPU で 4D の回転・遠近）：元の点（層ごとに緯度 × 経度の 4D の点）は 1 度だけ送り、回す行列だけを毎コマ渡す。
//   法線はとなりの点を同じように写して求める。4D の裏側（4D の視点から見て奥の半分）は暗く・くすませる（ウェブ版の「裏側を暗く」）
struct HR { float4x4 m4; float4 q; float4 r; float4 d; };    // q：色の倍率・透明度・camW・SCALE、r：R・網目の細かさ M、d.x：遠近の下限（ふだん 0.6、ダイブで近づく時は小さく）
inline float3 hproj(float4 b, constant HR& h) { float4 v = h.m4 * b; return v.xyz * (h.q.z / max(h.d.x, h.q.z - v.w) * h.q.w); }
vertex O hrv(uint vid [[vertex_id]], const device float4* base [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]], const device float4* lc [[buffer(3)]]) {
    uint M = uint(h.r.y), M1 = M + 1, per = M1 * M1, L = vid / per, k = vid % per, i = k / M1, j = k % M1, o0 = L * per;
    float4 b = base[vid], v = h.m4 * b; float3 P = hproj(b, h);
    float3 a = hproj(base[o0 + min(M, i + 1) * M1 + j], h) - hproj(base[o0 + (i > 0 ? i - 1 : 0) * M1 + j], h);
    float3 c = hproj(base[o0 + i * M1 + (j + 1) % M1], h) - hproj(base[o0 + i * M1 + (j + M - 1) % M], h);
    float3 n = cross(a, c); if (length(n) < 1e-7) n = P;
    float R = h.r.x, face = (v.w - R * R / h.q.z) / R, bk = 0.6 * (1.0 - smoothstep(-0.1, 0.05, face));
    float3 col = lc[L].rgb * h.q.x; float gray = dot(col, float3(0.299, 0.587, 0.114));
    O o; o.pos = u.mvp * float4(P, 1.0); o.wp = P; o.n = n; o.c = float4((col + (gray - col) * (0.4 * bk)) * (1.0 - 0.5 * bk), h.q.y); o.ph = float(j) / float(M) * 2.0 * M_PI_F;
    // 殻（g.z ＝ 2）：光は頂点ごとに計算して面の上でなめらかにつなぐ（21 枚の半透明の殻を全部の画素で計算すると、とても重い。殻はなめらかな球なので頂点で十分）
    if (u.g.z > 1.5) o.c = lightHL(n, P, o.c, 0.0, u);
    return o;
}
// 名前の札：文字の絵（色・ふちどり済み、アルファを掛けてある）を、いつも画面に向く板に貼る。奥行きは見ない（いつも見える）
struct LVert { float4 p; float4 uv; };
struct LO { float4 pos [[position]]; float2 uv; };
vertex LO lbv(uint vid [[vertex_id]], constant LVert* vs [[buffer(0)]], constant U& u [[buffer(1)]]) { LO o; o.pos = u.mvp * float4(vs[vid].p.xyz, 1.0); o.uv = vs[vid].uv.xy; return o; }
fragment float4 lbf(LO in [[stage_in]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear, address::clamp_to_edge); return t.sample(s, in.uv); }
struct QO { float4 pos [[position]]; float2 uv; };   // 画面いっぱいの三角形（背景・縮める）
// 宇宙モードの星（球面さんぽと同じ S³ の星）：右は超球の上を殻と同じ 4D の回転・遠近で、左は 4 つ目を落とした影 (x, y, w)（球の中に詰まる）。
//   カメラに向いた小さな板に、光の点（芯とにじみ）を足し合わせて描く。明るい星ほど大きく。右の超球の奥（4D の裏）の星は少し暗く
struct Star { float4 p; float4 c; };
struct SO { float4 pos [[position]]; float4 c; float2 q; };
vertex SO stv(uint vid [[vertex_id]], uint iid [[instance_id]], const device Star* st [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]], constant float4& k [[buffer(3)]]) {
    Star s = st[iid * uint(k.z)];                                       // k：大きさ・左右（0 右・1 左）・間引き・明るさ
    float R = h.r.x; float3 P; float vis = 1.0;
    if (k.y < 0.5) {
        float4 v = h.m4 * (s.p * R); P = v.xyz * (h.q.z / max(h.d.x, h.q.z - v.w) * h.q.w);
        vis = 0.45 + 0.55 * smoothstep(-0.1, 0.05, (v.w - R * R / h.q.z) / R);
    } else if (k.y > 1.5) {                                             // 4D で切る：超平面（法線 h.r.w の軸）＝ h.r.z のすぐそばの星だけ（切り口の 3D の中に、遠近なしで。切った軸の所に w を置く）
        float4 v = h.m4 * (s.p * R); int ax = int(h.r.w); float vk = v[ax];
        float3 q = v.xyz; if (ax < 3) q[ax] = v.w; P = q * h.q.w;
        float dw = (vk - h.r.z) / 0.07; vis = exp(-dw * dw);
    } else { P = (u.model * float4(float3(s.p.x, s.p.y, s.p.w) * R, 1.0)).xyz; }
    float2 q = float2((vid == 1 || vid == 2 || vid == 4) ? 1.0 : -1.0, (vid == 2 || vid == 4 || vid == 5) ? 1.0 : -1.0);
    float b = s.c.w, r = k.x * (0.55 + 0.45 * sqrt(b)) * clamp(length(u.eye.xyz - P) / 7.5, 0.02, 1.0);   // カメラに近い星も、画面の上の大きさは同じくらいに（ダイブ）
    P += (u.camR.xyz * q.x + u.camU.xyz * q.y) * r;
    SO o; o.pos = u.mvp * float4(P, 1.0); o.c = float4(s.c.rgb, min(2.2, 0.45 + 0.7 * b) * vis * k.w); o.q = q; return o;
}
fragment float4 stf(SO in [[stage_in]]) {
    float d2 = dot(in.q, in.q); if (d2 > 1.0) discard_fragment();
    float a = in.c.a * (exp(-d2 * 9.0) + 0.18 * exp(-d2 * 2.5));
    return float4(in.c.rgb, a);                                        // 足し合わせ（色 × a を足す）
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
fragment float4 dsf(QO in [[stage_in]], texture2d<float> t [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 px = 1.0 / float2(t.get_width(), t.get_height()) * 0.75;
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
    float3 col = dD + dS + (tube ? C * 0.4 : float3(0.0));
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
    // 断面カット（ウェブ版と同じ）：画面に固定は、画面から見た向き（0 ＝ 手前・右回りに 90° ＝ 右）、物体に固定は殻の経度。くさびの中は描かない
    if (u.cut.x > 2.5) { if (dot(in.wp, u.cutN.xyz) > u.cutN.w) discard_fragment(); }   // 平面で切る：向きの側（手前）を消す
    else if (u.cut.x > 0.5) {
        float a = (u.cut.x < 1.5 ? atan2(dot(in.wp, u.camR.xyz), dot(in.wp, cross(u.camR.xyz, u.camU.xyz))) : in.ph) - u.cut.y;
        a -= 2.0 * M_PI_F * floor((a + M_PI_F) / (2.0 * M_PI_F));
        if (abs(a) < u.cut.z) discard_fragment();
    }
    if (u.g.z < 0.5 || u.g.z > 1.5) return in.c;                     // 光なし（線・札）か、頂点で光を計算済み（右の殻）
    float3 nn = normalize(in.n), dxy = max(abs(dfdx(nn)), abs(dfdy(nn)));   // 粗さに面の曲がり具合を足す（細い管がチラつかない。three.js と同じ）
    return lightHL(in.n, in.wp, in.c, max(max(dxy.x, dxy.y), dxy.z), u);
}
"""

/// 左右どちらかの画面を描く
final class HyperLabRenderer: NSObject, MTKViewDelegate {
    enum Side { case left, right }
    let side: Side, st: HyperLabState
    let device: MTLDevice, queue: MTLCommandQueue
    private var opaquePipe: MTLRenderPipelineState!, alphaPipe: MTLRenderPipelineState!
    private var depthWrite: MTLDepthStencilState!, depthRead: MTLDepthStencilState!, depthAlways: MTLDepthStencilState!
    private var tris: [HLVert] = [], glass: [HLVert] = [], lines: [HLVert] = []
    private var triBuf: MTLBuffer?, glassBuf: MTLBuffer?, lineBuf: MTLBuffer?
    /// 右：層ごとの範囲（殻の面・その層の線）。ウェブ版（three.js）と同じく、層の順に「面 → 線」と描く
    private var ranges: [(g: Range<Int>, l: Range<Int>)] = []
    /// 右：元の 4D の点・層の色・つなぎ方（三角形と線の番号）。層数・半球が変わった時だけ作る
    private var rBase: MTLBuffer?, rCol: MTLBuffer?, rIdx: MTLBuffer?, rMesh = 48
    private var rPipe: MTLRenderPipelineState!, dsPipe: MTLRenderPipelineState!
    private var polyArmSeen = 0
    private var leftRings: [(rho: Double, h: Double, col: SIMD3<Float>)] = []
    private var rPipeAdd: MTLRenderPipelineState!, starPipe: MTLRenderPipelineState!, bgPipe: MTLRenderPipelineState!, bgMakePipe: MTLRenderPipelineState!
    private var bgTex: MTLTexture?                                    // 宇宙の背景の絵（大きさが変わった時だけ作る。毎コマ星雲を計算すると重い）
    private lazy var starBuf: MTLBuffer? = { let s = Renderer.starList; return device.makeBuffer(bytes: s, length: MemoryLayout<StarGPU>.stride * s.count) }()
    private var lbPipe: MTLRenderPipelineState!, labelTex: [String: MTLTexture] = [:]
    /// 左：2 倍の大きさで描くための絵（変わった時だけ作る）
    private var ssTex: (ms: MTLTexture, dep: MTLTexture, hi: MTLTexture)?
    private var builtKey = "", lastT = CACurrentMediaTime(), fpsN = 0, fpsT = CACurrentMediaTime()
    /// コマ数を動きに合わせる：見た目に関わる値の組（前のコマと同じなら「止まっている」）・止まっている時間・画面のいちばん速いコマ数
    private var lastSig: [Double] = [], stillT = 0.0, lowFPS = false, maxFPS = 60, moveFPS = 60
    private var pN = 0, pT = 0.0, slowS = 0, fastS = 0          // 実際のコマ数を数える（1 秒ごと）・遅い／速い秒が続いた数
    static let idleFPS = 10, idleAfter = 0.6
    static let R = 1.35, SCALE = 1.55, MIN_THETA = 0.08

    init?(side: Side, state: HyperLabState, view: MTKView?) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        self.side = side; st = state; device = d; queue = q
        super.init()
        if let view {
            view.device = d; view.colorPixelFormat = .bgra8Unorm
            // 左は自分で 2 倍の大きさに描いて縮めるので、画面そのものは 1 点・奥行きなし。右は画面に 4 倍のなめらかさ（マルチサンプル）で
            if side == .left { view.depthStencilPixelFormat = .invalid; view.sampleCount = 1 } else { view.depthStencilPixelFormat = .depth32Float; view.sampleCount = 4 }
            view.clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
            // 画面のいちばん速いコマ数で（144 Hz の画面なら 144。120 にすると 144 の半分の 72 になってしまう。ウェブ版と同じぬるぬる）
            #if os(macOS)
            maxFPS = NSScreen.screens.map { $0.maximumFramesPerSecond }.max() ?? 60
            #else
            maxFPS = UIScreen.main.maximumFramesPerSecond
            #endif
            view.preferredFramesPerSecond = maxFPS; moveFPS = maxFPS
        }
        let lib = try! d.makeLibrary(source: hlShader, options: nil)
        func pipe(_ blend: Bool, _ vf: String = "hlv", _ ff: String = "hlf", add: Bool = false) -> MTLRenderPipelineState {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = lib.makeFunction(name: vf); p.fragmentFunction = lib.makeFunction(name: ff)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm; p.depthAttachmentPixelFormat = .depth32Float; p.rasterSampleCount = 4
            if blend {
                let c = p.colorAttachments[0]!; c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                if add { c.destinationRGBBlendFactor = .one; c.destinationAlphaBlendFactor = .one }   // 足し合わせ（光る線・星）
            }
            return try! d.makeRenderPipelineState(descriptor: p)
        }
        opaquePipe = pipe(false); alphaPipe = pipe(true); rPipe = pipe(true, "hrv")
        rPipeAdd = pipe(true, "hrv", add: true); starPipe = pipe(true, "stv", "stf", add: true); bgPipe = pipe(false, "dsv", "cpf")
        let bp = MTLRenderPipelineDescriptor(); bp.vertexFunction = lib.makeFunction(name: "bgv"); bp.fragmentFunction = lib.makeFunction(name: "bgf")
        bp.colorAttachments[0].pixelFormat = .bgra8Unorm; bgMakePipe = try! d.makeRenderPipelineState(descriptor: bp)
        let dp = MTLRenderPipelineDescriptor(); dp.vertexFunction = lib.makeFunction(name: "dsv"); dp.fragmentFunction = lib.makeFunction(name: "dsf")
        dp.colorAttachments[0].pixelFormat = .bgra8Unorm; dsPipe = try! d.makeRenderPipelineState(descriptor: dp)
        let lp = MTLRenderPipelineDescriptor(); lp.vertexFunction = lib.makeFunction(name: "lbv"); lp.fragmentFunction = lib.makeFunction(name: "lbf")
        lp.colorAttachments[0].pixelFormat = .bgra8Unorm; lp.depthAttachmentPixelFormat = .depth32Float; lp.rasterSampleCount = 4
        let lc = lp.colorAttachments[0]!; lc.isBlendingEnabled = true; lc.sourceRGBBlendFactor = .one; lc.destinationRGBBlendFactor = .oneMinusSourceAlpha
        lc.sourceAlphaBlendFactor = .one; lc.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        lbPipe = try! d.makeRenderPipelineState(descriptor: lp)
        let w = MTLDepthStencilDescriptor(); w.depthCompareFunction = .less; w.isDepthWriteEnabled = true; depthWrite = d.makeDepthStencilState(descriptor: w)
        let r = MTLDepthStencilDescriptor(); r.depthCompareFunction = .less; r.isDepthWriteEnabled = false; depthRead = d.makeDepthStencilState(descriptor: r)
        let a = MTLDepthStencilDescriptor(); a.depthCompareFunction = .always; a.isDepthWriteEnabled = false; depthAlways = d.makeDepthStencilState(descriptor: a)
    }

    // ---- 色（ウェブ版の layerColor：中心が赤、北は赤→水色、南は紫→青）----
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> SIMD3<Float> {
        func f(_ n: Double) -> Double { let k = (n + h * 12).truncatingRemainder(dividingBy: 12), a = s * min(l, 1 - l); return l - a * max(-1, min(k - 3, 9 - k, 1)) }
        return SIMD3(Float(f(0)), Float(f(8)), Float(f(4)))
    }
    static func layerColor(_ i: Int, _ n: Int, _ south: Bool) -> SIMD3<Float> {
        let t = Double(i) / Double(max(1, n - 1))
        return south ? hsl(0.80 - t * 0.30, 0.95, 0.52) : hsl(t * 0.50, 0.95, 0.52)
    }
    /// 層：北・南それぞれ n 枚（緯度 θ のリング＝半径 R sin θ・高さ ±R cos θ）。南の赤道は北と重なるので 1 枚だけ
    func layerList() -> [(r: Double, w: Double, col: SIMD3<Float>)] {
        let n = max(2, st.layers), R = Self.R
        var out: [(Double, Double, SIMD3<Float>)] = []
        for south in [false, true] {
            if (st.hemi == 1 && south) || (st.hemi == 2 && !south) { continue }
            for i in 0..<n {
                if south && i == n - 1 && st.hemi == 0 { continue }
                let th = Self.MIN_THETA + Double(i) / Double(n - 1) * (Double.pi / 2 - Self.MIN_THETA)
                out.append((R * sin(th), (south ? -1 : 1) * R * cos(th), Self.layerColor(i, n, south)))
            }
        }
        return out
    }

    // ---- 左：リングの球（3D）----
    /// three.js の Euler（順序 YXZ）：ベクトルには面内（z）→ 前後（x）→ 左右（y）の順で効く
    func leftRot() -> simd_double3x3 {
        func rx(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[1, 0, 0], [0, cos(a), -sin(a)], [0, sin(a), cos(a)]]) }
        func ry(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[cos(a), 0, sin(a)], [0, 1, 0], [-sin(a), 0, cos(a)]]) }
        func rz(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[cos(a), -sin(a), 0], [sin(a), cos(a), 0], [0, 0, 1]]) }
        return ry(st.roll) * rx(st.pitch) * rz(st.yaw)
    }
    /// 左の形（傾きは描く時に GPU で回すので、形は Z-W・層数・半球が変わった時だけ作る）
    func buildLeftForBench() { buildLeft() }
    func buildLeft() {
        tris = []; glass = []; lines = []; ranges = []; leftRings = []
        let M = matrix_identity_double3x3, R = Self.R, cs = cos(st.zw)
        let n = max(2, st.layers), tube = n > 31 ? 0.008 : 0.02, segA = 160, segB = 16
        let sn = sin(st.zw), lzw = st.lzw
        for (r, w, col) in layerList() {
            // 影（投影。ウェブ版の leftZW 'shadow'・'both'）：層（半径 r の球面）を z の向きから写した影＝平たい回転楕円体
            //   （中心の高さ w·cos、横の半径 r、厚み r·|sin|）。網目で薄く。影だけの時（1）は輪も消えず、影の赤道（高さ w·cos・半径 r）に
            if lzw != 0 && abs(sn) > 1e-3 {
                let a: Float = lzw == 2 ? 0.32 : 0.55, c4 = SIMD4(col * 1.25, a), th = abs(sn) * r   // 左は 2 倍に描いて縮めるので、細い線はウェブ版（0.16・0.28）の倍くらいの濃さで
                func ep(_ i: Int, _ j: Int) -> SIMD3<Double> {
                    let t = Double(i) / 14 * .pi, f = Double(j) / 32 * 2 * .pi
                    return SIMD3(r * sin(t) * cos(f), r * sin(t) * sin(f), w * cs + th * cos(t))
                }
                for i in 1..<14 { for j in 0..<32 { addLine(ep(i, j), ep(i, j + 1), c4) } }   // 緯線
                for j in 0..<32 { for i in 0..<14 { addLine(ep(i, j), ep(i + 1, j), c4) } }   // 経線
            }
            // 輪：断面（0・2）は z′＝0 で切った円。高さ w の層は h ＝ w／cos(Z-W) の所の円（半径 √(R² − h²)）。超球からはみ出すと消える。影（1）は影の赤道
            var rho = r, h = w
            if lzw == 1 { h = w * cs }
            else if abs(st.zw) > 1e-6 {
                guard abs(cs) > 1e-3 || abs(w) < 1e-9 else { continue }
                h = abs(w) < 1e-9 ? 0 : w / cs
                guard abs(h) <= R + 1e-6 else { continue }
                rho = (max(0, R * R - h * h)).squareRoot()
            }
            leftRings.append((rho, h, col))
            // 細い管（トーラス）
            for a in 0..<segA {
                for b in 0..<segB {
                    func vtx(_ ia: Int, _ ib: Int) -> HLVert {
                        let u = Double(ia) / Double(segA) * 2 * .pi, v = Double(ib) / Double(segB) * 2 * .pi
                        let ctr = SIMD3(rho * cos(u), rho * sin(u), h), nr = SIMD3(cos(v) * cos(u), cos(v) * sin(u), sin(v))
                        let p = M * (ctr + nr * tube), nn = M * nr
                        return HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: SIMD4(SIMD3<Float>(nn), 0), c: SIMD4(col, 1))
                    }
                    let v00 = vtx(a, b), v10 = vtx(a + 1, b), v01 = vtx(a, b + 1), v11 = vtx(a + 1, b + 1)
                    tris += [v00, v10, v11, v00, v11, v01]
                }
            }
        }
        // 球の輪郭（うすい円）と、z 軸（4 次元目の w と対応する軸）
        let eq = (0...96).map { k -> SIMD3<Double> in let a = Double(k) / 96 * 2 * .pi; return SIMD3(R * cos(a), R * sin(a), 0) }
        for k in 0..<96 { addLine(M * eq[k], M * eq[k + 1], SIMD4(0.58, 0.64, 0.72, 0.18)) }
        if !st.axes { addLine(M * SIMD3(0, 0, -R * 1.25), M * SIMD3(0, 0, R * 1.25), SIMD4(0.38, 0.65, 0.98, 0.55)) }   // 座標軸を出す時は、毎コマ drawAxes で
    }
    private func addLine(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD4<Float>) {
        lines.append(HLVert(p: SIMD4(SIMD3<Float>(a), 1), n: .zero, c: c)); lines.append(HLVert(p: SIMD4(SIMD3<Float>(b), 1), n: .zero, c: c))
    }

    // ---- 右：球殻の超球（4D → 3D）----
    /// 4D の回転（ウェブ版の mkSteps と同じ順）：Z-W → X-Y（面内）→ Y-W（前後）→ X-W（左右、向きは逆）
    func xf(_ v0: SIMD4<Double>) -> SIMD4<Double> {
        var v = v0
        for (i, j, a) in [(2, 3, st.zw), (0, 1, st.yaw), (1, 3, st.pitch), (0, 3, -st.roll)] where a != 0 {
            let c = cos(a), s = sin(a), t = v[i] * c - v[j] * s
            v[j] = v[i] * s + v[j] * c; v[i] = t
        }
        return v
    }
    func buildRight() {
        tris = []; glass = []; lines = []; ranges = []
        let n = max(2, st.layers), MESH0 = n > 61 ? 12 : n > 31 ? 16 : 24
        // 網目の線はウェブ版と同じ本数（MESH0）。面と線の曲がりは 2 倍に細かく（輪郭がカクカク・ギザギザしないよう）
        let SUB = 4, M = MESH0 * SUB, M1 = M + 1, per = M1 * M1   // 光を頂点で計算するので、網目は 4 倍に細かく（照り返しがなめらか）
        rMesh = M
        let L = layerList()
        // 元の 4D の点（網目の並びは three.js の SphereGeometry と同じ：極が上下＝y、地球儀のように緯線が横に並ぶ。ウェブ版と同じ見た目）
        var base = [SIMD4<Float>](); base.reserveCapacity(L.count * per)
        for (r, w, _) in L { for i in 0...M { let th = Double(i) / Double(M) * .pi; for j in 0...M {
            let ph = Double(j) / Double(M) * 2 * .pi
            base.append(SIMD4<Float>(Float(-r * sin(th) * cos(ph)), Float(r * cos(th)), Float(r * sin(th) * sin(ph)), Float(w)))
        } } }
        // つなぎ方：層ごとに「三角形」→「線（緯線・経線・升目の斜め）」。three.js の網目は三角形の辺を全部描くので、升目ごとに (i, j) → (i+1, j+1) の斜めが入る（織物のような見た目）
        // ポリゴンカット：押した時に画面の手前を向いていた経度 cutPhi を中心に、開き具合ぶんの網目を作らない（ふちの線は残す）
        let poly = st.cutOn && st.cutKind == 0 && st.cutRef == 2, cphi = st.cutPhi, half = st.cutWDeg * .pi / 360
        func gone(_ jj: Double) -> Bool {
            guard poly else { return false }
            var a = jj / Double(M) * 2 * .pi - cphi; a -= 2 * .pi * ((a + .pi) / (2 * .pi)).rounded(.down)
            return abs(a) < half - 1e-6
        }
        var idx = [UInt32]()
        for li in 0..<L.count {
            let o = UInt32(li * per), g0 = idx.count
            for i in 0..<M { for j in 0..<M where !gone(Double(j) + 0.5) {
                let k = UInt32(i * M1 + j) + o, d = UInt32(M1)
                idx += [k, k + d, k + d + 1, k, k + d + 1, k + 1]
            } }
            let l0 = idx.count
            for i in stride(from: 0, through: M, by: SUB) { for j in 0..<M where !gone(Double(j) + 0.5) { let k = UInt32(i * M1 + j) + o; idx += [k, k + 1] } }
            for j in stride(from: 0, to: M, by: SUB) where !gone(Double(j)) { for i in 0..<M { let k = UInt32(i * M1 + j) + o; idx += [k, k + UInt32(M1)] } }
            for i in stride(from: 0, to: M, by: SUB) { for j in stride(from: 0, to: M, by: SUB) { for s in 0..<SUB where !gone(Double(j + s) + 0.5) {
                let k = UInt32((i + s) * M1 + j + s) + o; idx += [k, k + UInt32(M1) + 1]
            } } }
            ranges.append((g0..<l0, l0..<idx.count))
        }
        let cols = L.map { SIMD4<Float>($0.col, 1) }
        rBase = base.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rCol = cols.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(16, $0.count), options: .storageModeShared) }
        rIdx = idx.isEmpty ? nil : idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    // ---- 描く ----
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        if side == .left { st.tick(dt); st.pullLayers(); st.tickCut(dt); st.tickFollow(dt); st.tickDive(dt) }               // 自動の回転・さんぽの層数を読むのは左の画面（右は同じ状態を描く）
        pace(view, dt)
        if side == .left { fpsN += 1; if now - fpsT >= 1 { let f = Int((Double(fpsN) / (now - fpsT)).rounded()); fpsN = 0; fpsT = now; DispatchQueue.main.async { [st] in st.fps = f } } }
        if side == .left {
            guard let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
            renderLeft(cb, into: dr.texture); timeGPU(cb); cb.present(dr); cb.commit(); return
        }
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer(),
              let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encode(e, view.drawableSize)
        e.endEncoding(); timeGPU(cb); cb.present(dr); cb.commit()
    }
    /// 1 コマの GPU の時間を測って、ならして覚える（コマ数を決めるのに使う）
    private func timeGPU(_ cb: MTLCommandBuffer) {
        let left = side == .left, s = st
        cb.addCompletedHandler { c in
            let ms = (c.gpuEndTime - c.gpuStartTime) * 1000
            guard ms > 0 && ms < 200 else { return }
            DispatchQueue.main.async { if left { s.gpuL = s.gpuL * 0.9 + ms * 0.1 } else { s.gpuR = s.gpuR * 0.9 + ms * 0.1 } }
        }
    }
    /// コマ数を動きに合わせる（iPhone の ProMotion のように）：見た目に関わる値が 0.6 秒変わらなければ 1 秒 10 コマに落とし、
    ///   どれかが変わったら（ドラッグ・自動の回転・スライダー・さんぽで歩く…）すぐ画面のいちばん速いコマ数に戻す
    private func pace(_ view: MTKView, _ dt: Double) {
        let s = st
        var sig: [Double] = [s.pitch, s.roll, s.yaw, s.zw, s.viewYaw, s.viewPitch, s.viewDist, s.leftDist, s.camW, s.gloss, s.glare ? 1 : 0,
                             Double(s.layers), Double(s.mode), Double(s.hemi), Double(s.lzw), s.cutOn ? 1 : 0, Double(s.cutRef), s.cutAngDeg, s.cutWDeg, s.cutPhi, Double(s.cutKind), Double(s.planeDir), s.cutPos, s.cutSweep ? 1 : 0, Double(s.cut4Axis), s.followOn ? 1 : 0, s.followSlack, s.followDrift, s.diveT,
                             s.axes ? 1 : 0, s.axPlus ? 1 : 0, s.axThin ? 1 : 0, s.walk ? 1 : 0, s.marksOn ? 1 : 0, Double(s.polesMode), Double(s.spaceMode), s.starsPct, s.spaceNow ? 1 : 0, s.auto ? 1 : 0,
                             Double(view.drawableSize.width), Double(view.drawableSize.height)]
        if (s.walk || s.marksOn), let src = walkOverride ?? HyperLabState.walkSource {
            let w = src(); sig += [Double(w.trail.count), w.pos.x, w.pos.y, w.pos.z, w.pos.w, Double(w.marks.count), Double(w.hit.filter { $0 }.count), Double(w.poles.count)]
        }
        // ほんの少しの違い（計算の誤差）は「同じ」とみなす
        let moved = sig.count != lastSig.count || zip(sig, lastSig).contains { abs($0 - $1) > 1e-7 }
        // 動いている時のコマ数：ふだんは画面のいちばん速いコマ数。実際のコマ数が 2 秒続けて目標の 8 割に届かなければ（GPU があふれて
        //   コマを待つ間、ドラッグなどの操作も遅れてひっかかる）1 段下げ（画面の最高の 1/2・1/3…）、5 秒続けて余裕があれば 1 段上げてみる
        let boost = s.diveT > 0 || s.followOn
        if side == .left { HyperLabState.boostWalk = boost }
        if boost && moveFPS != maxFPS { moveFPS = maxFPS; if !lowFPS { view.preferredFramesPerSecond = moveFPS } }   // ダイブ・追う間は省電力をゆるめる（コマ数を下げない）
        if !lowFPS && !boost {
            pN += 1; pT += dt
            if pT >= 1 {
                let got = Double(pN) / pT; pN = 0; pT = 0
                if got < Double(moveFPS) * 0.8 { slowS += 1; fastS = 0 } else if got > Double(moveFPS) * 0.93 { fastS += 1; slowS = 0 } else { slowS = 0; fastS = 0 }
                let lv = maxFPS / max(1, moveFPS)
                if slowS >= 2 && moveFPS > 30 { slowS = 0; moveFPS = maxFPS / (lv + 1); view.preferredFramesPerSecond = moveFPS }
                else if fastS >= 5 && lv > 1 { fastS = 0; moveFPS = maxFPS / (lv - 1); view.preferredFramesPerSecond = moveFPS }
            }
        } else { pN = 0; pT = 0; slowS = 0; fastS = 0 }
        if moved || !s.adaptive {
            lastSig = sig; stillT = 0
            if lowFPS { lowFPS = false; view.preferredFramesPerSecond = moveFPS }
        } else {
            stillT += dt
            if !lowFPS && stillT > Self.idleAfter { lowFPS = true; view.preferredFramesPerSecond = Self.idleFPS }
        }
    }
    /// 左の輪：縦横 2 倍の大きさに 4 倍のマルチサンプルで描いて（1 画素に 16 点）、4 点を混ぜて縮める。細い管のふちと照り返しの筋がギザギザしない。
    ///   マルチサンプルの絵と奥行きは、GPU の中の小さな記憶（タイル）だけで済ませる（memoryless。大きな記憶を使わない）
    func renderLeft(_ cb: MTLCommandBuffer, into target: MTLTexture) {
        let W = target.width * 2, H = target.height * 2
        if ssTex == nil || ssTex!.hi.width != W || ssTex!.hi.height != H {
            var memless = true
            #if os(macOS)
            memless = device.supportsFamily(.apple7) || device.supportsFamily(.apple6)
            #endif
            func tex(_ f: MTLPixelFormat, ms: Bool) -> MTLTexture? {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: W, height: H, mipmapped: false)
                if ms { d.textureType = .type2DMultisample; d.sampleCount = 4; d.usage = [.renderTarget]; d.storageMode = memless ? .memoryless : .private }
                else { d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private }
                return device.makeTexture(descriptor: d)
            }
            guard let ms = tex(.bgra8Unorm, ms: true), let dep = tex(.depth32Float, ms: true), let hi = tex(.bgra8Unorm, ms: false) else { return }
            ssTex = (ms, dep, hi)
        }
        guard let s = ssTex else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = s.ms; rp.colorAttachments[0].resolveTexture = s.hi
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        rp.depthAttachment.texture = s.dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        encode(e, CGSize(width: W, height: H)); e.endEncoding()
        let fp = MTLRenderPassDescriptor()
        fp.colorAttachments[0].texture = target; fp.colorAttachments[0].loadAction = .dontCare; fp.colorAttachments[0].storeAction = .store
        guard let f = cb.makeRenderCommandEncoder(descriptor: fp) else { return }
        f.setRenderPipelineState(dsPipe); f.setFragmentTexture(s.hi, index: 0); f.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); f.endEncoding()
    }
    /// 形を（変わっていれば）作り直して、描く命令を積む
    func encode(_ e: MTLRenderCommandEncoder, _ sz: CGSize) {
        if side == .right && st.polyArm != polyArmSeen { polyArmSeen = st.polyArm; st.cutPhi = viewerPhi() }
        let key = side == .left ? "\(st.zw),\(st.layers),\(st.hemi),\(st.lzw),\(st.axes)" : "\(st.layers),\(st.hemi),\(st.cutOn && st.cutKind == 0 && st.cutRef == 2 ? "\(st.cutPhi),\(st.cutWDeg.rounded())" : "-")"
        if builtKey != key {
            builtKey = key
            if side == .left { buildLeft() } else { buildRight() }
            func buf(_ a: [HLVert]) -> MTLBuffer? { a.isEmpty ? nil : a.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) } }
            triBuf = buf(tris); glassBuf = buf(glass); lineBuf = buf(lines)
        }
        let asp = Float(sz.width / max(1, sz.height))
        var u = HLUni()
        // ダイブ（右）：超球の向き・4D のカメラ・視野を、景色と同じへ。左右を鏡に（景色の右・上・前と、画面の右・上・奥をそろえるため。超球の外の姿はほぼ左右対称）
        diveSetup()
        if side == .right && st.diveFade > 0.995 { return }              // 景色に入りきった：上に重ねた景色で隠れるので、超球は描かない（軽く）
        if side == .right && st.diveT > 0 {
            let (_, e2) = Self.diveEase(st.diveT), fov = Float(45 + (diveFov - 45) * e2)
            u.mvp = simd_float4x4(diagonal: SIMD4(-1, 1, 1, 1)) * Self.persp(fov, asp) * view3()
        } else { u.mvp = Self.persp(45, asp) * view3() }
        if side == .left { let m = leftRot(); u.model = simd_float4x4(SIMD4<Float>(SIMD3<Float>(m.columns.0), 0), SIMD4<Float>(SIMD3<Float>(m.columns.1), 0), SIMD4<Float>(SIMD3<Float>(m.columns.2), 0), SIMD4(0, 0, 0, 1)) }
        // 照り返しライト（visual-fx の shineRig と同じ置き方）：主光は カメラから見て左 30°・上 33°、逆光は 右うしろ 168°・上 23°。カメラについて回る
        let (eye, R, Up, B) = camBasis()
        func dir(_ az: Double, _ el: Double) -> SIMD4<Float> {
            let a = az * .pi / 180, l = el * .pi / 180
            return SIMD4(SIMD3<Float>(simd_normalize(R * (sin(a) * cos(l)) + Up * sin(l) + B * (cos(a) * cos(l)))), 0)
        }
        u.eye = SIMD4(SIMD3<Float>(eye), 1); u.key = dir(-30, 33); u.rim = dir(168, 23)
        u.camR = SIMD4(SIMD3<Float>(R), 0); u.camU = SIMD4(SIMD3<Float>(Up), 0)
        u.g = SIMD4(Float(max(0, st.gloss)), st.glare && st.gloss > 0 ? 1 : 0, 1, 0)
        if side == .right && st.diveT > 0 { let k = Float(1 - Self.diveEase(st.diveT).1); u.g.x *= k; u.g.y *= k }   // ダイブ：近づくほど照り返し・グレアを消す（景色には無いので）
        e.setCullMode(.none)
        planeCut(&u)
        // 宇宙モード：さんぽと同じ（さんぽで宇宙の背景を入れている時）か、入
        let wk = (walkOverride ?? HyperLabState.walkSource)?()
        st.spaceNow = st.spaceMode == 1 || (st.spaceMode == 0 && (wk?.space ?? false))
        if st.spaceNow, let bg = spaceBackground(sz) {
            e.setRenderPipelineState(bgPipe); e.setDepthStencilState(depthAlways); e.setFragmentTexture(bg, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if let b = triBuf {
            e.setRenderPipelineState(opaquePipe); e.setDepthStencilState(depthWrite); u.g.z = 1; u.g.w = 1
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tris.count)
        }
        if side == .right {
            // 右：層の順に「殻の面（奥行きは書かない）→ その層の線（奥行きを書く）」。ウェブ版（three.js の透明な物の描く順）と同じ。
            //   線が奥行きを書くので、あとの層の面に線が埋もれない。4D の回転・遠近は GPU で（回す行列だけ渡す）
            guard let rb = rBase, let rc = rCol, let ri = rIdx else { return }
            let n = max(2, st.layers), dens = Float(min(1, 12 / Double(n)))
            let solidA: Float = st.mode == 1 ? 0 : (st.mode == 2 ? min(0.85, 0.22 * 1.5 * dens) : 0.22 * dens)
            let wireA: Float = st.mode == 2 ? 0 : min(0.95, 0.22 * (st.mode == 1 ? 3.5 : 2.8) * dens)
            let m = effM
            var hg = HLRight(), hl = HLRight()
            hg.m4 = simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)); hl.m4 = hg.m4
            let sp = st.spaceNow
            hg.q = SIMD4(1, solidA * (sp ? 0.22 : 1), Float(effCamW), Float(Self.SCALE)); hl.q = SIMD4(1.4, wireA * (sp ? 0.45 : 1), Float(effCamW), Float(Self.SCALE))
            hg.d.x = Float(effClamp); hl.d.x = Float(effClamp)   // 宇宙：殻と網目は控えめに（中の星が見えるよう）
            hg.r = SIMD4(Float(Self.R), Float(rMesh), 0, 0); hl.r = hg.r
            var ug = u; ug.g.z = 2; ug.g.w = 0
            var ul = u; ul.g.z = 0
            if st.cutOn && st.cutKind == 0 && st.cutRef < 2 {
                let c = SIMD4<Float>(Float(st.cutRef + 1), Float(st.cutAngDeg * .pi / 180), Float(st.cutWDeg * .pi / 360), 0)
                ug.cut = c; ul.cut = c
            }
            if st.cutOn && st.cutKind == 2 && st.diveT == 0 {               // 4D で切る：超平面 w′ ＝ 一定の切り口だけ（殻・軸・跡は出さない）
                drawSlice4(e, u, m)
                var hs = hg; hs.r.z = Float(st.cutPos * Self.R); hs.r.w = Float(st.cut4Axis); drawStars(e, u, hs, slice: true)
                return
            }
            if st.diveT == 0 { drawAxes4(e, u) }                          // ダイブの間は軸を出さない
            e.setRenderPipelineState(rPipe); e.setVertexBuffer(rb, offset: 0, index: 0); e.setVertexBuffer(rc, offset: 0, index: 3)
            for r in ranges {
                if solidA > 0 && !r.g.isEmpty {
                    e.setDepthStencilState(depthRead)
                    e.setVertexBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hg, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.drawIndexedPrimitives(type: .triangle, indexCount: r.g.count, indexType: .uint32, indexBuffer: ri, indexBufferOffset: r.g.lowerBound * 4)
                }
                if wireA > 0 && !r.l.isEmpty {
                    e.setDepthStencilState(depthWrite); if sp { e.setRenderPipelineState(rPipeAdd) }   // 宇宙：網目は足し合わせて光らせる（さんぽの景色の線のように）
                    e.setVertexBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hl, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.drawIndexedPrimitives(type: .line, indexCount: r.l.count, indexType: .uint32, indexBuffer: ri, indexBufferOffset: r.l.lowerBound * 4)
                    if sp { e.setRenderPipelineState(rPipe) }
                }
            }
            drawStars(e, u, hg)
            drawWalk(e, u); drawMarks(e, u)                               // ダイブの間も、跡をたどって背中へ寄る（玉は画面の上で大きくなりすぎないよう縮める）
            if st.diveT == 0 { drawAxisLabels(e, u) }
            return
        }
        if let b = glassBuf {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthRead); u.g.z = 1; u.g.w = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glass.count)
        }
        if let b = lineBuf {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthRead); u.g.z = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lines.count)
        }
        drawAxes3(e, u)
        if st.cutOn && st.cutKind == 2 { drawSlicePlane2(e, u) }
        var hL = HLRight(); hL.r = SIMD4(Float(Self.R), 0, 0, 0); drawStars(e, u, hL)
        drawWalk(e, u); drawMarks(e, u); drawAxisLabels(e, u)
    }
    // ---- 座標の矢印（さんぽの地図と同じ色：x 赤・y 緑・z 青・w 紫）----
    static let AXL = 1.35 * 1.32                                      // 矢印の長さ（球の半径の 1.32 倍）
    static let axisCol: [SIMD3<Float>] = [SIMD3(1.0, 0.365, 0.424), SIMD3(0.239, 0.863, 0.518), SIMD3(0.337, 0.659, 1.0), SIMD3(0.690, 0.486, 1.0)]
    static let axisName = ["x", "y", "z", "w"]
    /// a から b への矢印（細い管＋円すいの頭。マイナスの側は細く）。光の当たり方は輪と同じ（つや）
    static func arrow(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, r: Double = 0.016, plus: Bool = false) -> [HLVert] {
        let d = b - a, L = simd_length(d); guard L > 1e-6 else { return [] }
        let f = d / L, up0 = abs(f.y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let ex = simd_normalize(simd_cross(up0, f)), ey = simd_cross(f, ex)
        let head = min(0.16, L * 0.2), mid = (a + b) / 2, neck = b - f * head, seg = 14
        var out: [HLVert] = []
        func v(_ p: SIMD3<Double>, _ n: SIMD3<Double>, _ c: SIMD3<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: SIMD4(SIMD3<Float>(n), 0), c: SIMD4(c, 1)) }
        for k in 0..<seg {
            let t0 = Double(k) / Double(seg) * 2 * .pi, t1 = Double(k + 1) / Double(seg) * 2 * .pi
            let n0 = ex * cos(t0) + ey * sin(t0), n1 = ex * cos(t1) + ey * sin(t1)
            // 管：マイナス側（a → 真ん中）は細く暗め、プラス側（真ん中 → 頭）は太く
            for (p, q, rr, c) in plus ? [(a, neck, r, col)] : [(a, mid, r * 0.55, col * 0.6), (mid, neck, r, col)] {
                out += [v(p + n0 * rr, n0, c), v(q + n0 * rr, n0, c), v(q + n1 * rr, n1, c), v(p + n0 * rr, n0, c), v(q + n1 * rr, n1, c), v(p + n1 * rr, n1, c)]
            }
            // 頭（円すい）と、その底
            let hr = r * 3.2, s0 = simd_normalize(n0 * head + f * hr), s1 = simd_normalize(n1 * head + f * hr)
            out += [v(neck + n0 * hr, s0, col), v(b, simd_normalize(s0 + s1), col), v(neck + n1 * hr, s1, col)]
            out += [v(neck, -f, col * 0.7), v(neck + n1 * hr, -f, col * 0.7), v(neck + n0 * hr, -f, col * 0.7)]
        }
        return out
    }
    /// 細い線の矢印：カメラに向いた細い帯と、平たい三角の矢じり（光は当てない。マイナス側は淡く）
    static func flatArrow(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, eye: SIMD3<Double>, w: Double, plus: Bool) -> [HLVert] {
        let d = b - a, L = simd_length(d); guard L > 1e-6 else { return [] }
        let f = d / L, head = min(0.13, L * 0.18), neck = b - f * head, mid = (a + b) / 2
        var sd = simd_cross(f, eye - mid); let sl = simd_length(sd); sd = sl < 1e-9 ? SIMD3(0, 0, 0) : sd / sl
        func v(_ p: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: c) }
        func band(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ c: SIMD4<Float>) -> [HLVert] {
            [v(p - sd * w, c), v(q - sd * w, c), v(q + sd * w, c), v(p - sd * w, c), v(q + sd * w, c), v(p + sd * w, c)]
        }
        let on = SIMD4(col, 1), dim = SIMD4(col * 0.75, 0.55)
        var out = plus ? band(a, neck, on) : band(a, mid, dim) + band(mid, neck, on)
        out += [v(neck - sd * w * 4.5, on), v(b, on), v(neck + sd * w * 4.5, on)]
        return out
    }
    /// 左：x・y・z の 3 本（球と一緒に傾く）。z は右の w に当たるので紫
    private func drawAxes3(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let lr = leftRot(), (eye, _, _, _) = camBasis()
        var tri: [HLVert] = []
        for k in 0..<3 {
            var d = SIMD3<Double>(0, 0, 0); d[k] = Self.AXL
            let a = st.axPlus ? SIMD3<Double>(0, 0, 0) : lr * -d, b = lr * d, c = Self.axisCol[k == 2 ? 3 : k]
            tri += st.axThin ? Self.flatArrow(a, b, c, eye: eye, w: 0.006, plus: st.axPlus) : Self.arrow(a, b, c, plus: st.axPlus)
        }
        drawAxisTris(e, u0, tri, depthTest: true)
    }
    private func drawAxisTris(_ e: MTLRenderCommandEncoder, _ u0: HLUni, _ tri: [HLVert], depthTest: Bool) {
        guard !tri.isEmpty else { return }
        var u = u0; u.model = matrix_identity_float4x4; u.cut = .zero
        if st.axThin { u.g.z = 0; e.setRenderPipelineState(alphaPipe) } else { u.g.z = 1; u.g.w = 1; e.setRenderPipelineState(opaquePipe) }
        e.setDepthStencilState(depthWrite)
        tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 右：x・y・z・w の 4 本の軸を、殻と同じ 4D の回転・遠近で写す（4D の直線は遠近で写しても直線）
    private func axis4(_ k: Int, _ s: Double) -> SIMD3<Double> {
        var e4 = SIMD4<Double>(0, 0, 0, 0); e4[k] = s * Self.AXL
        let v = xf(e4), sc = st.camW / max(0.6, st.camW - v.w) * Self.SCALE
        return SIMD3(v.x, v.y, v.z) * sc
    }
    private func drawAxes4(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let (eye, _, _, _) = camBasis()
        var tri: [HLVert] = []
        for k in 0..<4 {
            let a = axis4(k, st.axPlus ? 0 : -1), b = axis4(k, 1)
            tri += st.axThin ? Self.flatArrow(a, b, Self.axisCol[k], eye: eye, w: 0.007, plus: st.axPlus) : Self.arrow(a, b, Self.axisCol[k], plus: st.axPlus)
        }
        drawAxisTris(e, u0, tri, depthTest: true)
    }
    /// 軸の名前の文字の絵（数式の斜体。暗いふちどりつき。1 度だけ作る）
    private func labelTexture(_ s: String, _ col: SIMD3<Float>, math: Bool = true) -> MTLTexture? {
        let key = "\(s)|\(col)|\(math)"
        if let t = labelTex[key] { return t }
        let size: CGFloat = 96
        let name = ["KaTeX_Math-Italic", "STIXTwoText-Italic", "Georgia-Italic"].first { (CTFontCopyPostScriptName(CTFontCreateWithName($0 as CFString, 12, nil)) as String) == $0 } ?? "Georgia-Italic"
        // 軸の名前は数式の斜体、目印の番号と ✓ はふつうの太字（数式の書体だと ✓ が √ のように見える）
        let font = math ? CTFontCreateWithName(name as CFString, size, nil) : (CTFontCreateUIFontForLanguage(.emphasizedSystem, size * 0.9, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size * 0.9, nil))
        func line(_ stroke: Bool) -> CTLine {
            var a: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let c = CGColor(srgbRed: CGFloat(col.x), green: CGFloat(col.y), blue: CGFloat(col.z), alpha: 1), dark = CGColor(srgbRed: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 0.92)
            a[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = stroke ? dark : c
            if stroke { a[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 22.0; a[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = dark }
            return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: a))
        }
        let fill = line(false), bounds = CTLineGetBoundsWithOptions(fill, .useGlyphPathBounds)
        let pad: CGFloat = 18, W = Int(ceil(bounds.width + pad * 2)), H = Int(ceil(size * 1.3))
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.textPosition = CGPoint(x: pad - bounds.minX, y: (CGFloat(H) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line(true), ctx)
        ctx.textPosition = CGPoint(x: pad - bounds.minX, y: (CGFloat(H) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(fill, ctx)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: W, height: H, mipmapped: false); d.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: px, bytesPerRow: W * 4)   // 記憶の 1 行目が絵の上（そのまま送る）
        labelTex[key] = tex
        return tex
    }
    /// 札を 1 枚：c を真ん中に、いつも画面に向く板で（大きさは画面の上でだいたい同じに。k で倍率）
    private func drawLabel(_ e: MTLRenderCommandEncoder, _ s: String, _ col: SIMD3<Float>, _ c: SIMD3<Double>, k: Double = 1, math: Bool = true) {
        guard let tex = labelTexture(s, col, math: math) else { return }
        let (eye, Rv, Uv, _) = camBasis()
        let dist = simd_length(eye - c), hgt = 0.075 * dist / 5.5 * 2.6 * k, wid = hgt * Double(tex.width) / Double(tex.height)
        let rx = Rv * (wid / 2), uy = Uv * (hgt / 2)
        func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
        var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
        e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    /// 歩いた跡・目印の点を画面の 3 次元へ（右：超球の上を 4D の回転・遠近で、左：影 (x, y, w) を球の上へ）。face：見えている側なら 1、奥の側は 0
    private func walkPlace(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) {
        let R = Self.R, camW = side == .right ? effCamW : st.camW, (eye, _, _, _) = camBasis()
        if side == .right {
            let v = effM * (p * R), s = camW / max(effClamp, camW - v.w) * Self.SCALE
            return (SIMD3(v.x, v.y, v.z) * s, smoothstep(-0.1, 0.05, (v.w - R * R / camW) / R))
        }
        var q = SIMD3(p.x, p.y, p.w); let l = simd_length(q); q = l < 1e-9 ? SIMD3(0, 0, 1) : q / l
        let w = leftRot() * (q * R * 1.012)
        return (w, smoothstep(-0.15, 0.1, simd_dot(simd_normalize(w), simd_normalize(eye - w))))
    }
    /// 球面さんぽの目印（チェックポイント）：まだ通っていない目印は目印の色の輪、通った目印は塗りつぶしの丸と ✓。番号は地図と同じ（置いた順）
    private func drawMarks(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.marksOn || st.polesMode > 0, let src = walkOverride ?? HyperLabState.walkSource else { return }
        let wk = src()
        let poles = (0..<FIXED.count).filter { st.polesMode == 2 || (st.polesMode == 1 && wk.poles.contains($0)) }
        guard (st.marksOn && !wk.marks.isEmpty) || !poles.isEmpty else { return }
        let (eye, _, Uv, _) = camBasis()
        var tri: [HLVert] = []
        func disc(_ c: SIMD3<Double>, _ r00: Double, _ r10: Double, _ col: SIMD4<Float>) {
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), r0 = r00 * sc, r1 = r10 * sc   // カメラに近いと縮める（ダイブ）
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            for k in 0..<28 {
                let a0 = Double(k) / 28 * 2 * .pi, a1 = Double(k + 1) / 28 * 2 * .pi
                let d0: SIMD3<Double> = ax * cos(a0) + ay * sin(a0), d1: SIMD3<Double> = ax * cos(a1) + ay * sin(a1)
                let ps: [SIMD3<Double>] = [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d0 * r0, c + d1 * r1, c + d1 * r0]
                for q in ps { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        var tags: [(String, SIMD3<Float>, SIMD3<Double>)] = []
        // 8 つの極（さんぽの地図と同じ色・名前）：通った極は塗りつぶしと ✓、まだの極（いつも出す時）は輪
        for k in poles {
            let (c, f) = walkPlace(FIXED[k].c), col = MapRenderer.poleDotCol(k), vis = Float(0.5 + 0.5 * f), hit = wk.poles.contains(k)
            if hit { disc(c, 0, 0.11, SIMD4(col, 0.25 * vis)); disc(c, 0, 0.06, SIMD4(col, vis)); disc(c, 0.06, 0.072, SIMD4(1, 1, 1, 0.9 * vis)) }
            else { disc(c, 0, 0.06, SIMD4(col, 0.14 * vis)); disc(c, 0.045, 0.062, SIMD4(col, 0.9 * vis)) }
            tags.append((hit ? "✓" + MapRenderer.poleName(FIXED[k]) : MapRenderer.poleName(FIXED[k]), hit ? SIMD3<Float>(0.75, 1.0, 0.55) : col, c + Uv * 0.15))
        }
        for (i, m) in wk.marks.enumerated() where st.marksOn {
            let (c, f) = walkPlace(m), col = Journey.markColor(i), vis = Float(0.5 + 0.5 * f)
            let hit = i < wk.hit.count && wk.hit[i]
            if hit {
                disc(c, 0, 0.12, SIMD4(col, 0.28 * vis))                       // にじみ
                disc(c, 0, 0.068, SIMD4(col, vis))                             // 塗りつぶし
                disc(c, 0.068, 0.082, SIMD4(1, 1, 1, 0.9 * vis))               // 白いふち
            } else {
                disc(c, 0, 0.07, SIMD4(col, 0.16 * vis))                       // うすい中
                disc(c, 0.055, 0.075, SIMD4(col, 0.95 * vis))                  // 輪
            }
            tags.append((hit ? "✓\(i + 1)" : "\(i + 1)", hit ? SIMD3<Float>(0.75, 1.0, 0.55) : col, c + Uv * 0.15))
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
        tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        e.setRenderPipelineState(lbPipe); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        if side == .left || st.diveT == 0 { for (s, col, c) in tags { drawLabel(e, s, col, c, k: 0.7, math: false) } }
    }
    /// 軸の名前の札：矢印の先の少し外に、いつも画面に向く板で。左の z は右の w に当たるので「z(w)」（紫）
    private func drawAxisLabels(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.axes else { return }
        let (eye, Rv, Uv, _) = camBasis(), lr = leftRot()
        var items: [(String, SIMD3<Float>, SIMD3<Double>)] = []
        if side == .left { for k in 0..<3 { var d = SIMD3<Double>(0, 0, 0); d[k] = Self.AXL + 0.2; items.append((k == 2 ? "z(w)" : Self.axisName[k], Self.axisCol[k == 2 ? 3 : k], lr * d)) } }
        else { for k in 0..<4 { let tip = axis4(k, 1), dir = simd_normalize(tip + SIMD3(1e-9, 0, 0)); items.append((Self.axisName[k], Self.axisCol[k], tip + dir * 0.2)) } }
        var u = u0; u.model = matrix_identity_float4x4
        e.setRenderPipelineState(lbPipe); e.setDepthStencilState(depthAlways)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        for (s, col, c) in items {
            guard let tex = labelTexture(s, col) else { continue }
            let dist = simd_length(eye - c), hgt = 0.075 * dist / 5.5 * 2.6, wid = hgt * Double(tex.width) / Double(tex.height)   // 画面の上でだいたい同じ大きさに
            let rx = Rv * (wid / 2), uy = Uv * (hgt / 2)
            func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
            var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
            e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    /// 平面で切る：平面の向きと位置を定数へ（左右とも。くさびは右だけ、別に）。画面に固定は手前・右・上、物体に固定は x・y・z（左は球と一緒に傾く）
    private func planeCut(_ u: inout HLUni) {
        guard st.cutOn && st.cutKind == 1 else { return }
        let (_, Rv, Uv, Bv) = camBasis()
        var n: SIMD3<Double>
        switch st.planeDir {
        case 0: n = Bv
        case 1: n = Rv
        case 2: n = Uv
        default: var a = SIMD3<Double>(0, 0, 0); a[st.planeDir - 3] = 1; n = side == .left ? leftRot() * a : a
        }
        let rad = side == .left ? Self.R * 1.05 : Self.R * Self.SCALE * 1.08
        u.cut = SIMD4(3, 0, 0, 0); u.cutN = SIMD4(SIMD3<Float>(simd_normalize(n)), Float(st.cutPos * rad))
    }
    /// 線を、カメラに向いた細い帯に（光は当てない）
    static func ribbon(_ pts: [SIMD3<Double>], _ col: SIMD4<Float>, w: Double, eye: SIMD3<Double>) -> [HLVert] {
        guard pts.count >= 2 else { return [] }
        var out: [HLVert] = []; out.reserveCapacity(pts.count * 6)
        func v(_ p: SIMD3<Double>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: col) }
        var prev: (SIMD3<Double>, SIMD3<Double>)?
        for i in 0..<pts.count {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)], p = pts[i]
            var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * w
            if let (pl, pr) = prev { out += [v(pl), v(pr), v(p + sd), v(pl), v(p + sd), v(p - sd)] }
            prev = (p - sd, p + sd)
        }
        return out
    }
    /// 4D で切る（右）：見る人に固定の超平面 w′ ＝ c（c ＝ cutPos × R）と超球の切り口。切り口は半径 √(R² − c²) の球（2 次元球面）で、
    ///   各層の殻（w ＝ 一定の球）はその中の円になる（左の「輪 ∩ 平面 ＝ 2 点」のアナロジー）。切り口の 3D をそのまま（遠近なし、ウェブ版と同じ）
    private func drawSlice4(_ e: MTLRenderCommandEncoder, _ u0: HLUni, _ m: simd_double4x4) {
        let R = Self.R, c = st.cutPos * R, (eye, Rv, Uv, _) = camBasis(), ax = st.cut4Axis
        // 超平面 v[ax] ＝ c（v ＝ 回した後の 4D の点）。殻の点 p ＝ (u, w) では v[ax] ＝ a·u ＋ b·w
        let a = SIMD3(m.columns.0[ax], m.columns.1[ax], m.columns.2[ax]), b = m.columns.3[ax], la = simd_length(a)
        // 切り口の 3D：残りの 3 つの軸。切った軸の所に w を置く（x′ で切ると w は横、y′ は縦、z′ は手前＝左の「z(w)」と同じ）
        func disp(_ p: SIMD4<Double>) -> SIMD3<Double> { let v = m * p; var q = SIMD3(v.x, v.y, v.z); if ax < 3 { q[ax] = v.w }; return q * Self.SCALE }
        var tri: [HLVert] = []
        for (r, w, col) in layerList() {
            let cc = SIMD4(simd_min(col * 1.3, SIMD3(repeating: 1)), 1)
            if la < 1e-6 {                                             // 超平面が殻と平行（回していない時）：w ＝ c の殻がまるごと切り口
                guard abs(b * w - c) < 0.03 else { continue }
                for k in 1..<6 { let th = Double(k) / 6 * .pi
                    tri += Self.ribbon((0...72).map { j in let f = Double(j) / 72 * 2 * .pi; return disp(SIMD4(-r * sin(th) * cos(f), r * cos(th), r * sin(th) * sin(f), w)) }, cc, w: 0.006, eye: eye) }
                for k in 0..<6 { let f = Double(k) / 6 * .pi
                    tri += Self.ribbon((0...72).map { j in let th = Double(j) / 72 * 2 * .pi; return disp(SIMD4(-r * sin(th) * cos(f), r * cos(th), r * sin(th) * sin(f), w)) }, cc, w: 0.006, eye: eye) }
                continue
            }
            let ah = a / la, d = (c - b * w) / la
            guard abs(d) < r else { continue }                         // この殻は超平面と交わらない
            let rho = (r * r - d * d).squareRoot(), u0 = ah * d
            let e1 = simd_normalize(simd_cross(ah, abs(ah.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0))), e2 = simd_cross(ah, e1)
            let pts = (0...120).map { j -> SIMD3<Double> in let f = Double(j) / 120 * 2 * .pi; let q = u0 + (e1 * cos(f) + e2 * sin(f)) * rho; return disp(SIMD4(q, w)) }
            tri += Self.ribbon(pts, cc, w: 0.009, eye: eye)
        }
        // 切り口の球のふち（見る向きから見た輪郭）
        let rs = (max(0, R * R - c * c)).squareRoot() * Self.SCALE
        tri += Self.ribbon((0...120).map { j in let f = Double(j) / 120 * 2 * .pi; return (Rv * cos(f) + Uv * sin(f)) * rs }, SIMD4(0.85, 0.9, 1.0, 0.4), w: 0.006, eye: eye)
        guard !tri.isEmpty else { return }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthWrite)
        tri.withUnsafeBytes { bb in if let buf = device.makeBuffer(bytes: bb.baseAddress!, length: bb.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 4D で切る（左）：アナロジー。見る人に固定の平面（右の切る向きに当たる軸 ＝ c）の円盤と、輪（円）がそれを貫く点（2 点ずつ）。
    ///   右の「殻（球）∩ 超平面 ＝ 円」に当たるのが、左の「輪（円）∩ 平面 ＝ 2 点」
    private func drawSlicePlane2(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let R = Self.R, c = st.cutPos * R, lr = leftRot(), (eye, Rv, Uv, _) = camBasis()
        let rs = (max(0, R * R - c * c)).squareRoot()
        var tri: [HLVert] = []
        // 右で切る向きに当たる左の平面：x′ → x ＝ c、y′ → y ＝ c、w′ → z ＝ c（左の z は右の w）。z′ は左の球に当たる軸がないので出さない
        guard st.cut4Axis != 2 else { return }
        var nv = SIMD3<Double>(0, 0, 0); nv[st.cut4Axis == 3 ? 2 : st.cut4Axis] = 1
        let ctr = nv * c, e1 = simd_normalize(simd_cross(nv, abs(nv.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0))), e2 = simd_cross(nv, e1)
        // 円盤（うすい面）とふち
        for k in 0..<64 {
            let f0 = Double(k) / 64 * 2 * .pi, f1 = Double(k + 1) / 64 * 2 * .pi
            let q0: SIMD3<Double> = ctr + (e1 * cos(f0) + e2 * sin(f0)) * rs, q1: SIMD3<Double> = ctr + (e1 * cos(f1) + e2 * sin(f1)) * rs
            for q in [ctr, q0, q1] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: SIMD4(0.75, 0.85, 1.0, 0.10))) }
        }
        tri += Self.ribbon((0...96).map { j in let f = Double(j) / 96 * 2 * .pi; let d: SIMD3<Double> = e1 * cos(f) + e2 * sin(f); return ctr + d * rs }, SIMD4(0.85, 0.9, 1.0, 0.55), w: 0.006, eye: eye)
        // 輪が平面を貫く点：輪 (ρ cos u, ρ sin u, h) を傾けた点の nv の成分が c になる u（2 つ）
        let r2 = lr.transpose * nv
        func dot(_ p: SIMD3<Double>, _ col: SIMD3<Float>) {
            let rings: [(Double, SIMD4<Float>)] = [(0.07, SIMD4<Float>(col, 0.35)), (0.042, SIMD4<Float>(col, 1)), (0.018, SIMD4<Float>(1, 1, 1, 1))]
            func rim(_ f: Double, _ rad: Double) -> SIMD3<Double> { let d: SIMD3<Double> = Rv * cos(f) + Uv * sin(f); return p + d * rad }
            for (rad, cc) in rings {
                for k in 0..<20 {
                    let f0 = Double(k) / 20 * 2 * .pi, f1 = Double(k + 1) / 20 * 2 * .pi
                    for q in [p, rim(f0, rad), rim(f1, rad)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: cc)) }
                }
            }
        }
        for (rho, h, col) in leftRings {
            let A = r2.x * rho, B = r2.y * rho, C = c - r2.z * h, M = (A * A + B * B).squareRoot()
            guard M > 1e-9, abs(C) <= M else { continue }
            let base = atan2(B, A), dl = acos(max(-1, min(1, C / M)))
            for uu in [base + dl, base - dl] { dot(lr * SIMD3(rho * cos(uu), rho * sin(uu), h), col) }
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
        tri.withUnsafeBytes { bb in if let buf = device.makeBuffer(bytes: bb.baseAddress!, length: bb.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    // ---- ダイブ ----
    private var effM = matrix_identity_double4x4, effCamW = 3.8, effClamp = 0.6, diveFov = 70.0
    /// ダイブの進み（0〜1）を、向きを合わせる分 e1（0〜0.5）と近づく分 e2（0.08〜0.92）へ。どちらもなめらかに
    static func diveEase(_ t: Double) -> (Double, Double) {
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        // 回り込み（e1）と近づき（e2）を重ねて同時に：超球が回って自分の背中が正面に来ながら、カメラがそのまま寄っていく
        return (sm(t / 0.5), sm((t - 0.08) / 0.84))
    }
    /// 毎コマ：右の超球を写す 4D の回転・カメラの位置・遠近の下限を決める（ダイブしていなければ、ふだんの傾きのまま）
    private func diveSetup() {
        let m0 = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        effM = m0; effCamW = st.camW; effClamp = 0.6
        guard side == .right, st.diveT > 0, let w = (walkOverride ?? HyperLabState.walkSource)?(), simd_length(w.vL) > 0.5 else { return }
        let (e1, e2) = Self.diveEase(st.diveT)
        // 景色と同じ向き：自分のいる所 → 4D の手前（w）、見ている向き → 画面の奥（−z）、上 → 上（y）、右 → 鏡にした x（画面の右）
        let m1 = simd_double4x4(rows: [-w.vR, w.vU, -w.vL, w.pos])
        var m = m0 + (m1 - m0) * e1
        // 正規直交に直す（グラム・シュミット。列ごと）
        var c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        for i in 0..<4 { for j in 0..<i { c[i] -= c[j] * simd_dot(c[i], c[j]) }; let l = simd_length(c[i]); if l > 1e-9 { c[i] /= l } }
        m = simd_double4x4(columns: (c[0], c[1], c[2], c[3]))
        effM = m
        effCamW = st.camW + (Self.R * 1.012 - st.camW) * e2           // 4D のカメラを、自分のいる所のすぐ外まで
        effClamp = 0.6 + (0.004 - 0.6) * e2
        diveFov = w.fov
    }
    /// 宇宙の背景の絵：画面の大きさ（左は 2 倍で描くので、その半分）で 1 度だけ作る
    private func spaceBackground(_ sz: CGSize) -> MTLTexture? {
        let sc = side == .left ? 2.0 : 1.0, w = max(1, Int(Double(sz.width) / sc)), h = max(1, Int(Double(sz.height) / sc))
        if let t = bgTex, t.width == w, t.height == h { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        guard let tex = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return nil }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        var k = SIMD4<Float>(Float(Double(w) / Double(h)), 0, 0, 0)
        e.setRenderPipelineState(bgMakePipe); e.setFragmentBytes(&k, length: 16, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        cb.commit()                                                     // この後で積む絵より先に GPU で描かれる（同じ列）
        bgTex = tex
        return tex
    }
    /// 宇宙モードの星（球面さんぽと同じ 12000 個）。星の数で間引く。右は超球の上、左は影（球の中）
    private func drawStars(_ e: MTLRenderCommandEncoder, _ u: HLUni, _ h: HLRight, slice: Bool = false) {
        guard st.spaceNow, let b = starBuf else { return }
        let all = Renderer.starList.count, step = max(1, Int((100 / max(5, st.starsPct)).rounded()))
        var uu = u, hh = h, k = SIMD4<Float>(side == .right ? 0.02 : 0.015, side == .right ? 0 : 1, Float(step), side == .right ? 0.9 : 0.42)   // 左は球の中に詰まるので小さく淡く
        uu.cut = .zero
        if slice { k.y = 2; k.w = 2.2; k.z = 1 }                       // 4D の切り口：そばの星だけ（間引かず、明るく）
        e.setRenderPipelineState(starPipe); e.setDepthStencilState(depthRead)
        e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&uu, length: MemoryLayout<HLUni>.stride, index: 1)
        e.setVertexBytes(&hh, length: MemoryLayout<HLRight>.stride, index: 2); e.setVertexBytes(&k, length: 16, index: 3)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: slice ? all : all / step)
    }
    /// 球面さんぽで歩いた跡と今いる所（お遊び）。
    ///   右：S³ はこの超球そのもの。歩いた点 (x, y, z, w) を R 倍して、殻と同じ 4D の回転・遠近で写す（超球の面の上を這う光の線）。
    ///   左：2 次元とのアナロジー。4 つ目の z を落とした影 (x, y, w) を球の上へ（左の高さ z は右の w。輪と同じ対応）。
    ///   線はカメラに向いた帯（にじみの太い帯＋芯）、古い所ほど青く淡く、新しい所ほど白く明るい。超球（球）の奥の側は薄く。今いる所は黄色の玉
    private func drawWalk(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.walk, let src = walkOverride ?? HyperLabState.walkSource else { return }
        let wk = src(), trail0 = wk.trail, pos = wk.pos
        var pts = trail0
        if pts.count > 3000 { let k = Double(pts.count) / 3000; pts = (0..<3000).map { trail0[min(trail0.count - 1, Int(Double($0) * k))] } }   // 多い時は間引く
        pts.append(pos)
        let (eye, _, _, _) = camBasis()
        // 点を画面の 3 次元へ。face：見えている側なら 1、奥の側は 0（なめらかに）
        func place(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) {
            walkPlace(p)                                                  // 目印・ダイブと同じ写し方
        }
        let P = pts.map { place($0) }
        var tri: [HLVert] = []; tri.reserveCapacity(P.count * 12)
        // カメラに近い所ほど小さく（ダイブで寄っても、画面の上の大きさがだいたい同じ。ふだんはほぼ 1）
        func near(_ p: SIMD3<Double>) -> Double { max(0.004, min(1, simd_length(eye - p) / 7.5)) }
        func ribbon(_ width: Double, _ alpha: Float, _ bright: Float) {
            guard P.count >= 2 else { return }
            var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
            for i in 0..<P.count {
                let a = P[max(0, i - 1)].0, b = P[min(P.count - 1, i + 1)].0, p = P[i].0
                if i > 0 && simd_length(P[i].0 - P[i - 1].0) > 0.6 { prev = nil; continue }   // 飛んだ所（初めに戻した時など）はつながない
                var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * width * near(p)
                let t = Float(i) / Float(max(1, P.count - 1)), vis = Float(0.45 + 0.55 * P[i].1)
                let c = simd_mix(SIMD3<Float>(1.0, 0.30, 0.62), SIMD3<Float>(1.0, 0.97, 0.80), SIMD3(repeating: t * t)) * bright   // 殻の緑・青に映える暖かい色（古い所は桃色、新しい所は白）
                let col = SIMD4(c, alpha * (0.45 + 0.55 * t) * vis)
                let l0 = p - sd, r0 = p + sd
                if let (pl, pr, pc) = prev {
                    func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                    tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                }
                prev = (l0, r0, col)
            }
        }
        ribbon(0.05, 0.22, 1.0)                                         // にじみ
        ribbon(0.016, 1.0, 1.2)                                         // 芯
        // 今いる所：カメラに向いた丸（黄色のにじみ＋白い芯）
        let (c, f) = P[P.count - 1], fw = SIMD3<Double>(eye - c), up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let gone = Float(1 - max(0, min(1, (st.diveT - 0.8) / 0.12)))   // ダイブの終わり（背中に追いつく所）で消える
        let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax)), vis = Float(0.6 + 0.4 * f) * gone, sc = near(c)
        let gold = SIMD3<Float>(0.98, 0.80, 0.08)
        let discs: [(Double, SIMD4<Float>)] = [(0.15 * sc, SIMD4(gold, 0.3 * vis)), (0.075 * sc, SIMD4(gold, vis)), (0.035 * sc, SIMD4(1, 1, 0.9, vis))]
        func rim(_ a: Double, _ rad: Double) -> SIMD3<Double> { let d: SIMD3<Double> = ax * cos(a) + ay * sin(a); return c + d * rad }
        for (rad, col) in discs {
            for k in 0..<24 {
                let a0 = Double(k) / 24 * 2 * .pi, a1 = Double(k + 1) / 24 * 2 * .pi
                for q in [c, rim(a0, rad), rim(a1, rad)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        guard !tri.isEmpty else { return }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0
        e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
        tri.withUnsafeBytes { b in
            if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
            else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) }
        }
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
    }
    /// 確かめの絵用：歩いた跡の代わり（無ければアプリのもの）
    var walkOverride: (() -> HyperLabState.Walk)?
    /// 画面なしで描いて絵にする（確かめ用。4 倍のなめらかさ）
    func image(_ w: Int, _ h: Int) -> CGImage? {
        func tex(_ f: MTLPixelFormat, _ ms: Bool) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = ms ? .private : .shared
            if ms { d.textureType = .type2DMultisample; d.sampleCount = 4 }
            return device.makeTexture(descriptor: d)
        }
        guard let ms = tex(.bgra8Unorm, true), let out = tex(.bgra8Unorm, false), let dep = tex(.depth32Float, true), let cb = queue.makeCommandBuffer() else { return nil }
        if side == .left { renderLeft(cb, into: out); cb.commit(); cb.waitUntilCompleted(); return readImage(out, w, h) }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = out
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        rp.depthAttachment.texture = dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        encode(e, CGSize(width: w, height: h)); e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return readImage(out, w, h)
    }
    /// 重さを測る（確かめ用）：この大きさで n コマ描いて、1 コマの GPU と CPU の時間（ミリ秒）
    func bench(_ w: Int, _ h: Int, frames n: Int = 30) -> (gpu: Double, cpu: Double) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        let out = device.makeTexture(descriptor: d)!
        d.textureType = .type2DMultisample; d.sampleCount = 4; let ms = device.makeTexture(descriptor: d)!
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = [.renderTarget]; dd.storageMode = .private; dd.textureType = .type2DMultisample; dd.sampleCount = 4
        let dep = device.makeTexture(descriptor: dd)!
        var g = 0.0, c = 0.0
        for i in 0..<(n + 5) {
            st.pitch += 0.01; st.roll += 0.007; st.version &+= 1
            let t0 = CACurrentMediaTime(), cb = queue.makeCommandBuffer()!
            if side == .left { renderLeft(cb, into: out) }
            else {
                let rp = MTLRenderPassDescriptor()
                rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = out; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
                rp.depthAttachment.texture = dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
                let e = cb.makeRenderCommandEncoder(descriptor: rp)!; encode(e, CGSize(width: w, height: h)); e.endEncoding()
            }
            let t1 = CACurrentMediaTime(); cb.commit(); cb.waitUntilCompleted()
            if i >= 5 { g += (cb.gpuEndTime - cb.gpuStartTime) * 1000; c += (t1 - t0) * 1000 }
        }
        return (g / Double(n), c / Double(n))
    }
    private func readImage(_ out: MTLTexture, _ w: Int, _ h: Int) -> CGImage? {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        out.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return ctx?.makeImage()
    }
    /// 視点：左は正面（+z の 5.5 から、北極が手前）。右は正面から、ドラッグで回した向き
    /// 画面（観察者）の向きを超球の元の座標へ戻して、手前を向いている経度（ウェブ版の viewerPhi。SphereGeometry：x ＝ −cosφ·sinθ、z ＝ sinφ·sinθ）
    func viewerPhi() -> Double {
        let m = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        let (eye, _, _, _) = camBasis(), o = m.transpose * SIMD4(eye, 0)
        if (o.x * o.x + o.z * o.z).squareRoot() < 1e-3 { return st.cutPhi }   // 真上・真下から見ている時は前のまま
        var a = atan2(o.z, -o.x); if a < 0 { a += 2 * .pi }
        return a
    }
    /// カメラの位置と、右・上・うしろ（画面の奥と逆）の向き
    func camBasis() -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        var yaw = side == .left ? 0 : st.viewYaw, pit = side == .left ? 0 : st.viewPitch, dist = side == .left ? st.leftDist : st.viewDist
        if side == .right && st.diveT > 0 {                              // ダイブ：見る向きは正面へ、3D のカメラは自分のいる所（原点）へ
            let (e1, e2) = Self.diveEase(st.diveT)
            yaw *= 1 - e1; pit *= 1 - e1; dist = 0.02 + (dist - 0.02) * pow(1 - e2, 1.6)   // 背中へ寄る（近いほどゆっくり）
        }
        let eye = SIMD3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit)) * dist
        let f = simd_normalize(-eye), up = SIMD3<Double>(0, 1, 0)
        let r = simd_normalize(simd_cross(f, up)), uu = simd_cross(r, f)
        return (eye, r, uu, -f)
    }
    func view3() -> simd_float4x4 {
        let (eye, r, uu, b) = camBasis(), f = -b
        let m = simd_double4x4(rows: [SIMD4(r, -simd_dot(r, eye)), SIMD4(uu, -simd_dot(uu, eye)), SIMD4(-f, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        return simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3))
    }
    static func persp(_ fovDeg: Float, _ asp: Float) -> simd_float4x4 {
        let n: Float = 0.1, f: Float = 100, ys = 1 / tan(fovDeg * .pi / 360), xs = ys / asp
        return simd_float4x4(rows: [[xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, f / (n - f), f * n / (n - f)], [0, 0, -1, 0]])
    }
}

// ---- 画面：左右の 2 枚と、下のパネル ----
/// さんぽの景色を描く：さんぽの窓と同じ Renderer の「描く」だけを呼ぶ（歩く計算はさんぽの窓が 1 回だけ）。
///   さんぽの窓が新しいコマを描いた時（frameCount が進んだ時）か、大きさが変わった時だけ描き直す（止まっている間は休む）
final class WalkWipe: NSObject, MTKViewDelegate {
    private var lastFrame = -1, lastSize = CGSize.zero
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let r = HyperLabState.walkRendererGet?() else { return }
        let sz = view.drawableSize
        if r.frameCount == lastFrame && sz == lastSize { return }
        guard sz.width >= 8, sz.height >= 8, let rpd = view.currentRenderPassDescriptor, let d = view.currentDrawable, let cb = r.queue.makeCommandBuffer() else { return }
        lastFrame = r.frameCount; lastSize = sz
        r.encode(cb, rpd, view.colorPixelFormat, Int(sz.width), Int(sz.height))
        cb.present(d); cb.commit()
    }
}
#if os(macOS)
struct WalkScenePane: NSViewRepresentable {
    final class Holder { let wipe = WalkWipe() }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: HyperLabState.walkRendererGet?()?.device ?? MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .rgba16Float; v.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)   // さんぽの窓と同じ（EDR）
        (v.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        v.framebufferOnly = true; v.preferredFramesPerSecond = 60; v.delegate = context.coordinator.wipe
        return v
    }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct WalkScenePane: UIViewRepresentable {
    final class Holder { let wipe = WalkWipe() }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: HyperLabState.walkRendererGet?()?.device ?? MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm; v.framebufferOnly = true; v.preferredFramesPerSecond = 60; v.delegate = context.coordinator.wipe
        return v
    }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif
#if os(macOS)
struct HyperPane: NSViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct HyperPane: UIViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif

struct HyperLabView: View {
    @StateObject private var st = HyperLabState()
    @State private var last: CGSize = .zero
    @State private var pinch0: Double? = nil
    var body: some View {
        VStack(spacing: 0) {
            // 並び：3 つの時は［左上・左下・右］、さんぽの景色を出さない時は［左・右］（order の順。⟳ で回す）
            let items = st.order.filter { $0 != 1 || (st.walkView && HyperLabState.walkRendererGet?() != nil) }
            Group {
                if items.count == 3 {
                    HStack(spacing: 1) {
                        VStack(spacing: 1) { slot(items[0]); slot(items[1]) }
                        slot(items[2])
                    }
                } else {
                    HStack(spacing: 1) { ForEach(items, id: \.self) { slot($0) } }
                }
            }
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
            controls
        }
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
        .preferredColorScheme(.dark)
    }
    @ViewBuilder func slot(_ k: Int) -> some View {
        switch k {
        case 0: pane(.left, "【操作側】3D の球（リングを積む）　ドラッグで傾ける・⇧＋横ドラッグで Z-W").id(0)
        case 1: walkPane.id(1)
        default: pane(.right, "【観察側】4D の超球（球殻を積む）　ドラッグで見る向き").id(2)
        }
    }
    /// さんぽの景色（さんぽの窓と同じ景色。ここでは見るだけ。歩くのはさんぽの窓・コントローラーで）
    var walkPane: some View {
        ZStack(alignment: .topLeading) {
            WalkScenePane()
            Text("【さんぽの景色】今いる所から見た S³（歩くのはさんぽの窓・コントローラーで）").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).allowsHitTesting(false)
        }
    }
    func pane(_ side: HyperLabRenderer.Side, _ tag: String) -> some View {
        ZStack(alignment: .topLeading) {
            HyperPane(side: side, st: st)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let d = CGSize(width: g.translation.width - last.width, height: g.translation.height - last.height); last = g.translation
                    if side == .left {
                        #if os(macOS)
                        let shift = NSEvent.modifierFlags.contains(.shift)
                        #else
                        let shift = false
                        #endif
                        if shift { st.zw = HyperLabState.norm(st.zw + Double(d.width) * 0.012) }
                        else { st.pitch = HyperLabState.norm(st.pitch + Double(d.height) * 0.012); st.roll = HyperLabState.norm(st.roll + Double(d.width) * 0.012) }
                    } else {
                        st.viewYaw -= Double(d.width) * 0.008; st.viewPitch = max(-1.5, min(1.5, st.viewPitch + Double(d.height) * 0.008))
                    }
                    st.bump()
                }.onEnded { _ in last = .zero })
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    if pinch0 == nil { pinch0 = side == .left ? st.leftDist : st.viewDist }
                    let d = max(2.2, min(30, pinch0! / Double(k)))
                    if side == .left { st.leftDist = d } else { st.viewDist = d }
                    st.bump()
                }.onEnded { _ in pinch0 = nil })
            Text(tag).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).allowsHitTesting(false)
            if side == .right && st.diveFade > 0 {
                WalkScenePane().opacity(st.diveFade).allowsHitTesting(false)   // ダイブの最後：さんぽの景色へ溶け込む
            }
            if side == .right {
                Text(String(format: "前後（Y-W）%+.0f°　左右（X-W）%+.0f°　面内（X-Y）%+.0f°　Z-W %+.0f°", st.pitch * 180 / .pi, -st.roll * 180 / .pi, st.yaw * 180 / .pi, st.zw * 180 / .pi))
                    .font(.system(size: 10, design: .monospaced)).padding(6)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8).allowsHitTesting(false)
            }
        }
    }
    var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(st.auto ? "停止" : "回転") { st.auto.toggle() }
                Button("初期位置") { st.reset() }
                Menu(st.followOn ? (st.followSlack < 1 ? "追う：いつも中心" : String(format: "追う：遊び %.0f°", st.followSlack)) : "自分を追う") {
                    Button("いつも中心（さんぽの自分中心と同じ）") { st.followOn = true; st.followSlack = 0; st.followHeading = true }
                    Button("奥に行ったら回す（手前の半分は自由）") { st.followOn = true; st.followSlack = 90; st.followHeading = false }
                    Button("自由（追わない）") { st.followOn = false }
                    Divider()
                    Toggle("進む向きも合わせる", isOn: $st.followHeading)
                }.fixedSize().help("さんぽで歩く自分を、超球の手前に保つ。遊び：真ん中からどこまで自由に動けるか。0° ならいつも中心、90° なら奥（4D の裏）へ行きかけた時だけ回す")
                if st.followOn {
                    slider("遊び", Binding(get: { st.followSlack }, set: { st.followSlack = $0.rounded() }), 0, 150, fmt: "%.0f°").frame(width: 110)
                    slider("戻す速さ", Binding(get: { st.followSpeed }, set: { st.followSpeed = $0 }), 0.2, 3, fmt: "×%.1f").frame(width: 110)
                    slider("ゆるく回す", Binding(get: { st.followDrift }, set: { st.followDrift = $0 }), 0, 1, fmt: "%.2f").frame(width: 110)
                        .help("遊びの中でも、弱い力で少しずつ自分の方へ回り続ける。0 で遊びの中は止まる")
                }
                Button(st.diveOn ? "⤴ 戻る" : "⤵ ダイブ") { st.diveManual = false; st.diveOn.toggle(); st.bump() }
                    .disabled(HyperLabState.walkSource == nil)
                    .help("超ズームで、今いる所へ飛び込んで、さんぽの景色に入る（約 3 秒）。もう一度押すと外へ出る")
                Toggle("景色に溶かす", isOn: $st.diveBlend).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("ダイブの最後に、さんぽの景色へ溶け込ませる。切ると、寄ったまま超球の網目（4D の外から見た姿）で見続けられる（左下の景色と見比べに）")
                slider("ズーム", Binding(get: { st.diveT }, set: { st.diveManual = true; st.diveT = $0; st.diveOn = $0 > 0.5; st.bump() }), 0, 1, fmt: "%.2f").frame(width: 100)
                Toggle("さんぽの景色", isOn: $st.walkView).toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                    .help("さんぽの窓と同じ景色（今いる所から見た S³）を、画面を割って出す")
                Button("⟳ 並び") { let o = st.order; st.order = [o[2], o[0], o[1]] }
                    .help("3 つの画面（3D の球・さんぽの景色・4D の超球）の置き場所を順に回す（左上 → 左下 → 右）")
                Picker("", selection: Binding(get: { st.mode }, set: { st.mode = $0; st.bump() })) { Text("ハイブリッド").tag(0); Text("ワイヤー").tag(1); Text("半透明").tag(2) }
                    .pickerStyle(.segmented).frame(width: 260).labelsHidden()
                Picker("", selection: Binding(get: { st.hemi }, set: { st.hemi = $0; st.bump() })) { Text("全球").tag(0); Text("北").tag(1); Text("南").tag(2) }
                    .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                Spacer()
                Picker("宇宙", selection: $st.spaceMode) { Text("さんぽと同じ").tag(0); Text("入").tag(1); Text("切").tag(2) }
                    .pickerStyle(.segmented).frame(width: 230).font(.caption)
                    .help("宇宙モード：球面さんぽと同じ 12000 個の星を超球に（右は S³ の上、左は影で球の中）、背景は宇宙、網目は光る線。さんぽと同じ：さんぽで宇宙の背景を入れている時に入る")
                slider("星の数", Binding(get: { st.starsPct }, set: { st.starsPct = $0 }), 5, 100, fmt: "%.0f%%").frame(width: 110).disabled(!st.spaceNow && st.spaceMode != 1)
                Toggle("省電力", isOn: $st.adaptive).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("止まっている間は 1 秒 10 コマに落とし、動かすとすぐ画面のいちばん速いコマ数に戻す（iPhone の ProMotion のように）")
                Text(String(format: "%d fps・GPU %.1f＋%.1f ms", st.fps, st.gpuL, st.gpuR)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("Metal 版の試作（ウェブ版の核だけ）").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                slider("前後傾き", Binding(get: { st.pitch * 180 / .pi }, set: { st.pitch = $0 * .pi / 180; st.bump() }), -180, 180)
                slider("左右傾き", Binding(get: { st.roll * 180 / .pi }, set: { st.roll = $0 * .pi / 180; st.bump() }), -180, 180)
                slider("Z-W 傾き", Binding(get: { st.zw * 180 / .pi }, set: { st.zw = $0 * .pi / 180; st.bump() }), -180, 180)
                VStack(alignment: .leading, spacing: 0) {
                    slider("層数", Binding(get: { Double(st.layers) }, set: { st.setLayers(Int($0.rounded())) }), 3, st.layersLink ? 21 : 41, fmt: "%.0f")
                    Toggle("さんぽと連動", isOn: Binding(get: { st.layersLink }, set: { on in st.layersLink = on; if on, let w = HyperLabState.walkShells { st.setLayers(w.get()) } }))
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #else
                        .toggleStyle(.switch)
                        #endif
                        .font(.caption2).disabled(HyperLabState.walkShells == nil)
                        .help("入れると、球層の数を球面さんぽと同じにする。さんぽで増やす・減らすとこちらも、こちらで変えるとさんぽも変わる（3〜21）")
                }
                slider("光沢", Binding(get: { st.gloss }, set: { st.gloss = $0 }), 0, 1.5, fmt: "%.2f")
                Toggle("グレア", isOn: $st.glare).toggleStyle(.switch).font(.caption).fixedSize()
                Toggle("座標軸", isOn: Binding(get: { st.axes }, set: { st.axes = $0; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("座標の矢印。左は x・y・z（z は右の w に当たるので紫）、右は x・y・z・w を超球と一緒に 4D で回す")
                Toggle("＋のみ", isOn: $st.axPlus).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.axes)
                    .help("座標軸をプラスの向きだけにする")
                Picker("", selection: $st.axThin) { Text("線").tag(true); Text("立体").tag(false) }
                    .pickerStyle(.segmented).frame(width: 90).labelsHidden().disabled(!st.axes)
                    .help("線：細い軸線と平たい矢じり。立体：つやのある管と円すいの矢印")
                Toggle("歩いた跡", isOn: $st.walk).toggleStyle(.switch).font(.caption).fixedSize()
                Toggle("目印", isOn: $st.marksOn).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("球面さんぽで置いた目印。歩いて通った目印（チェックポイント）は塗りつぶしと ✓、まだの目印は輪")
                Picker("極", selection: $st.polesMode) { Text("出さない").tag(0); Text("通ると出る").tag(1); Text("いつも").tag(2) }
                    .pickerStyle(.segmented).frame(width: 210).font(.caption)
                    .help("8 つの極（アナ極・カタ極・東西南北・天・地）。通ると出る：歩いて通った極だけ ✓ つきで出てくる。いつも：全部出し、通った極は ✓")
                    .help("球面さんぽで歩いた跡と今いる所を、右の超球（S³ そのもの）と左の球（影）に描く")
            }
            HStack(spacing: 10) {
                Text("Z-W を左の球で").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { st.lzw }, set: { st.lzw = $0; st.bump() })) { Text("断面").tag(0); Text("影（投影）").tag(1); Text("両方").tag(2) }
                    .pickerStyle(.segmented).frame(width: 210).labelsHidden()
                    .help("断面：z′＝0 で切った円（断面と交わらなくなると消える）。影：z の向きから見た影。輪は消えず、各層が平たい楕円体（パンケーキ）に。両方：断面の輪＋影を薄く")
                Divider().frame(height: 18)
                Toggle("断面カット", isOn: Binding(get: { st.cutOn }, set: { on in
                    st.cutOn = on; if on && st.cutKind == 0 && st.cutRef == 2 { st.polyArm &+= 1 }; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("超球を切って中をのぞく。くさび（キャベツを切るように）・平面（輪切り）・4D（超平面で切った 3D の切り口）")
                Picker("", selection: Binding(get: { st.cutKind }, set: { k in st.cutKind = k; st.cutOn = true; if k == 0 && st.cutRef == 2 { st.polyArm &+= 1 }; st.bump() })) {
                    Text("くさび").tag(0); Text("平面").tag(1); Text("4D").tag(2) }
                    .pickerStyle(.segmented).frame(width: 170).labelsHidden()
                    .help("くさび：くさび形に切り欠く。平面：1 枚の平面より手前を消す（輪切り）。4D：見る人に固定の超平面 w′ ＝ 一定で切った 3D の切り口だけを見る（左は平面 z′ ＝ 一定と、輪がそれを貫く点）")
                if st.cutKind == 0 {
                    Picker("", selection: Binding(get: { st.cutRef }, set: { r in
                        st.cutRef = r; if r == 2 { st.polyArm &+= 1; st.cutOn = true }; st.bump() })) { Text("画面に固定").tag(0); Text("物体に固定").tag(1); Text("ポリゴンカット").tag(2) }
                        .pickerStyle(.segmented).frame(width: 300).labelsHidden()
                        .help("画面に固定：見る人から見て同じ側を切る。物体に固定：超球の経度で切る（回すと切り口も動く）。ポリゴンカット：押した時に手前を向いている所を中心に、開き具合ぶんの網目を作らない（次に押すまで超球に固定）")
                    slider("切り欠きの位置", Binding(get: { st.cutAngDeg }, set: { st.cutAngDeg = $0 }), 0, 360, fmt: "%.0f°").disabled(!st.cutOn || st.cutRef == 2)
                    slider("開き具合", Binding(get: { st.cutWDeg }, set: { st.cutWDeg = $0.rounded() }), 10, 300, fmt: "%.0f°").disabled(!st.cutOn)
                } else {
                    if st.cutKind == 1 {
                        Picker("", selection: $st.planeDir) { Text("手前").tag(0); Text("右").tag(1); Text("上").tag(2); Text("x").tag(3); Text("y").tag(4); Text("z").tag(5) }
                            .pickerStyle(.segmented).frame(width: 250).labelsHidden()
                            .help("切る平面の向き。手前・右・上：画面に固定（見る人から見て、その側を消す）。x・y・z：物体に固定（その軸のプラス側を消す。左は球と一緒に傾く）")
                    }
                    if st.cutKind == 2 {
                        Picker("", selection: $st.cut4Axis) { Text("x′").tag(0); Text("y′").tag(1); Text("z′").tag(2); Text("w′").tag(3) }
                            .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                            .help("4D で切る向き（超平面に垂直な軸）。w′：見る人の 4 次元の奥行きの向き。x′・y′・z′：層を積んだ向きと直角に切るので、殻が円になって積み重なる（左の輪を積んだ球のアナロジー）。4D で回すと斜めの切断にも")
                    }
                    slider(st.cutKind == 1 ? "切り口の位置" : ["x′", "y′", "z′", "w′"][st.cut4Axis] + " の位置", Binding(get: { st.cutPos }, set: { st.cutPos = $0; st.cutSweep = false; st.bump() }), -1, 1, fmt: "%+.2f")
                    Toggle("自動で動かす", isOn: $st.cutSweep).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("切り口をゆっくり行ったり来たりさせる（MRI の輪切りのように）")
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.04, green: 0.06, blue: 0.11))
        .controlSize(.small)
    }
    func slider(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, fmt: String = "%+.0f°") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.caption); Spacer(); Text(String(format: fmt, v.wrappedValue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: v, in: lo...hi)
        }
    }
}

#if os(macOS)
/// Mac：Metal 版の試作を別の窓で
enum HyperLabWindow {
    static var window: NSWindow?
    static func open() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "超球（Metal 版の試作）"; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: HyperLabView())
        w.setFrameAutosaveName("S3WalkHyperLab"); if !w.setFrameUsingName("S3WalkHyperLab") { w.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in window = nil }
        window = w; w.makeKeyAndOrderFront(nil)
    }
}
#endif
