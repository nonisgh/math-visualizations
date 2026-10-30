// 超球（Metal 版の試作）：ウェブ版 hypersphere_beta.html の核を、Swift と Metal で描く。
//   左：3D の球をリング（緯度の円）を積んで作る。右：4D の超球を球殻（w 一定の 2 次元の球面）を積んで作り、4D で回して 3D へ遠近で写す。
//   左の「リング ↔ 右の球殻」が 1 つずつ対応する（2 次元とのアナロジー：円を積むと球、球を積むと超球）。
//   回転の対応はウェブ版と同じ：左の前後傾き（x 軸まわり）＝右の Y-W、左右傾き（y 軸まわり）＝右の X-W（向きは逆）、面内（z 軸まわり）＝右の X-Y。
//   Z-W 傾きは左の 3D には無い第 4 の軸への傾きで、左では「z′＝0 で切った断面」としてリングが動く・消える。
//   ウェブ版の角度・色・遠近（camW）・層の作り方はそのまま。切り欠き・4D カメラ・旅・学習などは、まだ（ウェブ版の窓で）
import SwiftUI
import MetalKit
import CoreVideo

/// 共通の状態（左右の画面とパネルで共有）
final class HyperLabState: ObservableObject {
    // 傾き（ラジアン）は、描く側が毎コマ読むふつうの値。パネルの表示は、手で変えた時と、自動で回している間は 1 秒に 10 回だけ更新する
    //   （毎コマ SwiftUI の画面を作り直すと、それだけで重くなってコマ数が落ちる）
    var pitch = 0.0                                                   // 前後傾き
    var roll = 0.0                                                    // 左右傾き
    var yaw = 0.0                                                     // 面内
    var zw = 0.0                                                      // Z-W 傾き
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
        cutPhase += dt * 0.45; cutPos = sin(cutPhase) * 0.95; version &+= 1
    }
    @Published var gloss = 1.0                                        // 光沢（照り返しライト・映り込み）の強さ。0 で今までの見た目
    @Published var glare = true                                       // グレア（色を深く・ふちが白く光る・斜めの映り込みの帯）
    /// 1 秒あたりのコマ数の表示（左の画面で数える。1 秒ごと）。パネル全体を描き直さないよう、表示だけの小さな部品（HLStats）が見る
    let stats = HLStats()
    let live = HLLive()
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
    /// 超球の窓のショートカットキー（押した文字を渡す。使ったら true）
    static var hyperKey: ((String) -> Bool)? = nil
    @Published var shellMode = 0                                     // 球層の色：0 レインボー（w の 1 方向）・1 4 方向レインボー（x・y・z・w に重ねる）・2 軸の色・3 さんぽと同じ
    /// 今の球層の色（さんぽと同じ の時は、さんぽの設定から）
    var shellModeNow: Int {
        guard shellMode == 3 else { return shellMode }
        guard let s = HyperLabState.walkRendererGet?()?.set else { return 0 }
        return s.shAxis ? 2 : s.rainbow4 ? 1 : 0
    }
    @Published var padOn = false                                      // 画面のゲームパッド（さんぽと同じ。コントローラーと同じ働き）
    @Published var panelHidden = false                                // パネルを隠す（画面いっぱいに超球と景色だけ）
    @Published var coordOn = true                                     // 走行中の座標（右の画面の左上。x・y・z・w・アナ極からの角度・近い極・速さ）
    @Published var poleEN = false                                     // 英語モード：極の名前を英語（セリフ体で小さく）
    @Published var starDepth = 0.0                                    // 星の遠近（引きの絵）：超球の向こう側の遠い星ほど透明に・ぼかす（0 で今まで通り）
    @Published var soundOn = false                                    // 音：彗星が走る「シューッ」（速さ・ズームに合わせて）と、チェックポイントの「チリン」
    @Published var soundSpatial = true                                // 空間オーディオ：彗星のいる方向から聞こえる（ヘッドホンで上下・前後も）
    @Published var soundVol = 0.7                                     // 音の大きさ
    @Published var uiScale = 1.0                                      // パネルと隅の表示の大きさ（⌘＋・⌘−・⌘0。0.75〜2）
    @Published var lapClear = true                                    // 1 周（目印を全部通る）したら歩いた跡も消す
    @Published var show3D = true                                      // 左の 3D の球を出す（切ると、さんぽの景色と 4D の超球だけ）
    @Published var clearAhead = true                                  // 前方の跡を消す：同じ道をまた通る時、彗星（今いる所）の前の古い跡を一時的に薄くする
    @Published var trailW = 0.6                                       // 歩いた跡の太さ（倍率。1 が前の太さ）
    @Published var trailCol = 0                                       // 歩いた跡の色：0 桃色（古い所）→ 白（新しい所）・1 白い光・2 軸の色（いちばん近い軸の色）
    @Published var depth4On = false                                   // 4D の遠近（見る人の 4 次元の視線 w′ に沿って奥ほど）を入れる
    @Published var depth4 = 3                                         // 4D の遠近の種類：1 かすみ・2 ぼかし・3 両方
    @Published var symGlow = true                                     // 極・目印を光る星で描く（白い光に極の色がほんのり・十字のきらめき）。切ると前の丸と輪
    @Published var depth4K = 0.7                                      // 4D の遠近の強さ
    @Published var diveThird = false                                  // ダイブの行き先：false 一人称（自分の目＝さんぽの景色へ）・true 三人称（斜め後ろから自分＝彗星を追う）
    @Published var chaseDist = 0.5                                    // 三人称：後ろへの距離（3D の画面の長さ）
    @Published var chasePitch = 25.0                                  // 三人称：上から見下ろす角度（°）
    @Published var chaseYaw = 20.0                                    // 三人称：斜めの角度（°、＋で右うしろ）
    @Published var ovCursor = -1                                      // 全体像の今いる所の印：−1 ふつうと同じ・0 さんぽ・1 彗星・2 線の彗星・3 巨大彗星・4 大彗星
    @Published var diveOverview = false                               // ダイブ中は 3D の球の場所に、外から見た超球の全体像を出す（ダイブしながら全体も分かる）
    @Published var camShow = false                                    // ショーカメラ（オートカメラの仲間）：カーブは真後ろの低い所から、まっすぐな所はいろいろな角度へ切りかえて見せる
    var showDist = 1.0                                                // ショーカメラのカメラの距離の倍率（ゆっくり追う）
    var showFrame = SIMD2<Double>(0, 0)                               // ショーカメラの、彗星を画面に置く場所（ゆっくり追う）
    var showRoll = 0.0                                                // ショーカメラの傾き（斜めに構えて迫力を出す。ゆっくり追う）
    @Published var autoCam = true                                     // オートカメラ（ズームの三人称）：ゆっくり周りを漂い、曲がる時は外側へ回り込む（よく見える角度へ）
    @Published var splitX = 0.5                                       // 画面の仕切り：左の列の幅（窓の幅に対して）
    @Published var splitY = 0.5                                       // 画面の仕切り：左の列の上の画面の高さ
    @Published var axesDive = true                                    // ズーム（ダイブ）の間も座標軸を出す
    @Published var railOn = false                                     // 先に道を描く：決まった道・自分の道の 1 周ぶんを、歩く前から細い線で（ジェットコースターのレール）
    @Published var planOn = true                                      // 予定の道：決まった道・自分の道（巡回）を歩く時、これから先の道を光の点線で
    @Published var showMode = 1                                       // ショーカメラ：0 A（構図を順に回す＋カーブで真後ろの斜め構え）・1 B（ジェットコースター：先の落ち込み・昇り・急カーブへ先回り）
    @Published var spinMode = 0                                       // 矢印の回り方：0 拍（音のうなりに合わせたドミノ）・1 カーブ（曲がる所で自分から回る）・2 両方・3 波・4 らせん
    @Published var spinAmp = 90.0                                     // 波：振れ幅（度）。らせん：1 枚ごとのねじれ（度）
    @Published var spinLen = 6.0                                      // 波：波長（矢印の枚数）。らせん：拍 2 つで何回りするか（×0.1）
    @Published var opMode = false                                     // 操作モード（ダイブを見ながら、さんぽの窓と同じように歩く。スティックはカメラに使わない）
    @Published var planDense = true                                   // 粗密：まっすぐな所は矢印の間隔を広く、カーブは密に
    @Published var planLong = false                                   // 予定の道を全部（ダイブでも、左上の地図と同じように道の終わりまで矢印を出す）
    @Published var planShell = true                                   // 予定の道の矢印を、その場所の球殻の色にほんのり染める（緑の所なら半透明の緑）
    @Published var planMark = 0                                       // 予定の道の目印：0 立体の矢印・1 楕円の光（暖かい白）・2 金平糖（矢印と金平糖は青白にほんのり軸の色）
    @Published var hyperQ = 0                                         // 超球の窓の静かさ：0 さんぽに合わせる（さんぽの静かモードの時だけ静か）・1 いつも静か・2 いつも高画質
    @Published var wipeLow = true                                     // さんぽの景色の画面（ワイプ）を低負荷で：画素は半分（1 秒 60 コマ）
    @Published var walkPanelOn = false                                // さんぽの設定（さんぽのパネルを全部）を、この窓に浮かべる
    @Published var walkPanelSel = 1                                   // 開いているさんぽのパネル（ふだん「決まった道」）
    @Published var walkMenu = true                                    // さんぽメニュー（この窓に浮かぶ、さんぽの操作の小窓）を出す
    @Published var shutAuto = false                                   // 前の窓だけ描く（自動）：超球の窓が前ならさんぽの窓（景色・地図）を止め、さんぽの窓が前ならさんぽを描いて超球は控えめに。瞬時に切りかえ
    @Published var shutWalk = false                                   // さんぽの窓は描かない：さんぽの窓（景色・地図）を止め、描くのはこの窓だけ（景色の画面・ダイブは描く。歩く計算・跡はそのまま）
    @Published var naviCenter = true                                  // 上の地図を車のナビのように（自分がいつも真ん中で、背景が動く）
    @Published var map2 = true                                        // ダイブの間、さんぽの景色の場所をW 地図にする（地図 2 枚）
    var map2Now: Bool { map2 && (diveOn || diveT > 0) }
    @Published var ovShow = true                                      // 地図の構図：ダイブの間、全体像の向きを自動で（横から球層を見せる・赤と紫の玉を重ねて見せる）
    @Published var glareAuto = true                                   // 強い照り返しをよける（白いかたまりになる向きの間だけ、さっと弱める）
    @Published var cursor = 1                                         // 今いる所の印：0 さんぽ（青緑と白の三重の輪）・1 彗星（光で描く。コマと、ぼけた尾）・2 線の彗星（前の形）・3 巨大彗星・4 大彗星（光の玉の中に彗星。巨大はさらに大きく。ダイブで寄るとふつう）
    @Published var walkOpen = true                                    // パネルの「さんぽと連動」の欄を開いている
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
    var diveFade = 0.0                                                // 景色の重ねぐあい（最後の溶け込み）。表示は live.fade
    @Published var diveBlend = true                                   // 最後にさんぽの景色へ溶かす（切ると、寄ったまま超球の網目で見続ける）
    var diveT = 0.0, diveManual = false
    /// 彗星（今いる所）が見ている人からどれだけ近いか（0 奥〜1 手前）。右の画面が描く時に決める。引きの絵の音の大きさに
    var cometNear = 0.5
    /// 彗星の速さ（0〜1、ならしたもの）。速いほど彗星を派手に
    var cometSpd = 0.0
    /// 彗星の場所（見る人から見て：x 右・y 上・z 手前。長さ 1）。空間オーディオの向きに
    var cometDir = SIMD3<Double>(0, 0, -1)
    var camTan = SIMD4<Double>(0, 0, 0, 0)                            // オートカメラの視点：今いる所から見たカメラの向き（S³ の接線。全体像のカーソルのまわりに出す）
    /// ズーム中に回した分（ドラッグで足す。手を離すと所定の角度へゆっくり戻る）
    var diveYawOff = 0.0, divePitchOff = 0.0, diveDragging = false
    var padHolding = false                                            // コントローラーのスティックでダイブのカメラを回している間
    var camHeld: Bool { diveDragging }                                // マウスで回している間（オートカメラは休む）。コントローラーはオートカメラの上に足す（止めない）
    @Published var padCam = false                                     // ダイブのカメラをコントローラーのスティックで回す
    @Published var padCamStick = 1                                    // そのスティック：0 左・1 右・2 両方
    /// オートカメラの角度（ラジアン、なめらかに追う）と時刻
    var autoYaw = 0.0, autoPitch = 0.0, autoT = 0.0, autoDyn = 0.0   // autoDyn：ダイナミックの強さ（0〜1）
    private var diveYawVel = 0.0, divePitchVel = 0.0               // 戻る速さ（ばねのように：静かに動き出して、ゆっくり止まる）
    /// なめらかに追いかける値（三人称の割合・後ろ・見下ろす・斜め）：切りかえやスライダーで、カメラがパッと動かないように
    var thirdK = 0.0, chaseDistS = 0.5, chasePitchS = 25.0, chaseYawS = 20.0
    private var smoothReady = false
    /// ダイブを進める（受け持ちの画面が毎コマ呼ぶ）：ゆっくり入る（約 4.8 秒）・出る（約 4 秒）。ズームのスライダーを動かしている間は手で
    /// パネルの大きさ：+1 大きく・−1 小さく・0 元に（0.75〜2、0.1 ずつ）
    func zoomUI(_ d: Int) { uiScale = d == 0 ? 1 : min(2, max(0.75, ((uiScale + 0.1 * Double(d)) * 10).rounded() / 10)) }
    func tickDive(_ dt: Double) {
        if !diveManual {
            let tgt = diveOn ? 1.0 : 0.0
            if diveT != tgt { diveT = tgt > diveT ? min(tgt, diveT + dt / 4.8) : max(tgt, diveT - dt / 4.0); version &+= 1; if diveT == tgt { objectWillChange.send() } }
        }
        if !smoothReady { thirdK = diveThird ? 1 : 0; chaseDistS = chaseDist; chasePitchS = chasePitch; chaseYawS = chaseYaw; smoothReady = true }
        let k = 1 - exp(-dt * 2.0)                                     // 0.5 秒ほどで追いつく
        func ease(_ v: inout Double, _ to: Double, _ eps: Double) { if abs(to - v) > eps { v += (to - v) * k } else { v = to } }
        // ズーム中に回した分：離している間は、ゆーっくり所定の角度へ戻る（ちょうど止まるばね。静かに動き出して、約 6 秒でそっと止まる）
        if camHeld || padHolding { diveYawVel = 0; divePitchVel = 0 }   // 回している間は、戻すばねも休む
        else if diveYawOff != 0 || divePitchOff != 0 {
            let w = 0.75, h = min(dt, 0.05)
            diveYawVel += (-w * w * diveYawOff - 2 * w * diveYawVel) * h; diveYawOff += diveYawVel * h
            divePitchVel += (-w * w * divePitchOff - 2 * w * divePitchVel) * h; divePitchOff += divePitchVel * h
            if abs(diveYawOff) < 2e-4 && abs(divePitchOff) < 2e-4 && abs(diveYawVel) < 2e-4 && abs(divePitchVel) < 2e-4 { diveYawOff = 0; divePitchOff = 0; diveYawVel = 0; divePitchVel = 0 }
        }
        ease(&thirdK, diveThird ? 1 : 0, 1e-3); ease(&chaseDistS, chaseDist, 1e-4); ease(&chasePitchS, chasePitch, 0.01); ease(&chaseYawS, chaseYaw, 0.01)
        // 溶け込み：ズームの 0.86〜0.98 で少しずつ（段なしに）。表示の更新は変わった時だけ
        let x = max(0, min(1, (diveT - 0.86) / 0.12)), f = diveBlend ? x * x * (3 - 2 * x) * (1 - thirdK) : 0
        if abs(f - diveFade) > 0.01 || (f == 0 && diveFade != 0) || (f == 1 && diveFade != 1) { diveFade = f; live.fade = f }
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
    ///   walk：追う相手（書き出しで、裏で歩くさんぽを追う時）。nil なら今のさんぽ
    func tickFollow(_ dt: Double, walk: Walk? = nil) {
        guard followOn, let w = walk ?? Self.walkSource?() else { return }
        let p = w.pos, f = w.fwd
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
        if gl < 1e-6 { pitch += 0.02; version &+= 1; return }                  // 真裏などで坂がない時は、少しずらす
        let step = min(followSpeed * 2.2 * dt, 3 * followSpeed * dt * gl) // 1 秒に最大 2.2 rad × 速さ
        a -= g / gl * step
        zw = Self.norm(a[0]); yaw = Self.norm(a[1]); pitch = Self.norm(a[2]); roll = Self.norm(a[3]); version &+= 1
    }
    @Published var order = [0, 1, 2]
    static var walkRendererGet: (() -> Renderer?)?
    /// ダイブ中・自分を追う間は、さんぽの窓も画面のいちばん速いコマ数で（さんぽの「60 fps 前後」をゆるめる。景色がなめらかに流れるよう）
    static var boostWalk = false
    /// さんぽの窓は止める：さんぽの窓（景色・地図）は真っ黒にして、描くのは 4D 球アナロジーの窓だけ。4D 球アナロジーの窓を閉じたら、さんぽはまた描く
    static var walkShut = false
    /// 操作モード：超球の窓が前でも、キーとコントローラーをさんぽと同じ「歩く操作」に（スティックをカメラに使わない）
    static var opModeNow = false
    /// 前の窓だけ描く（自動）の時：さんぽの窓が前で、超球の窓は控えめに描く（1 秒 30 コマ）
    static var shutAuto = false, hyperIdle = false
    /// さんぽの景色の画面（ワイプ）を低負荷で描く（WalkWipe が読む）
    static var wipeLow = true
    static var quietNow = false                                        // 今、超球の窓を静かに描くか（hyperQ とさんぽの静かモードから。持ち主の画面が毎コマ決める）
    /// 英語モード（ワイプの極の名前も。WalkWipe が読む）
    static var poleENNow = false
    // 網目（ワイヤー）の色の加減（確かめ用に環境変数でも変えられる）：裏側を灰色へ寄せる割合・暗くする割合、宇宙モードでの濃さ
    static var wireBackGray = Double(ProcessInfo.processInfo.environment["S3_WG"] ?? "") ?? 0.15   // 網目は灰色へ寄せすぎない（黄色・緑がオリーブ色に濁って闇に溶ける）
    static var wireBackDark = Double(ProcessInfo.processInfo.environment["S3_WD"] ?? "") ?? 0.4
    static var spaceWire = Double(ProcessInfo.processInfo.environment["S3_SW"] ?? "") ?? 0.62   // 宇宙モードの網目（中の星を見せるため控えめに。0.45 だと暖かい色が闇に溶けた）
    static var shellPixelLight = ProcessInfo.processInfo.environment["S3_PIXLIGHT"] != nil   // 確かめ用：殻の光を画素ごとに（前のやり方）
    // 画質：0 自動・1 高・2 中・3 低。描く画素の数（画面の細かさ × renderK）。自動は、コマ数が目標に届かない時に下げ、余裕が戻ったら上げる
    @Published var quality = 0
    @Published var wireW = 1.8                                        // ワイヤー（網目の線）の太さ（画面の画素。Retina の 1 画素の線は細すぎて色が薄く見える）
    static var renderK = 1.0
    /// ダイブで右に景色が出ている：左下の景色の画面は休む（右の大きな画面へ受け渡し）
    static var walkBigShown = false
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
    struct Walk { var trail: [SIMD4<Double>]; var pos: SIMD4<Double>; var marks: [SIMD4<Double>] = []; var hit: [Bool] = []; var poles: [Int] = []; var lap = 1; var head: SIMD4<Double>? = nil; var space = false; var fwd = SIMD4<Double>(0, 0, 1, 0)
        var vR = SIMD4<Double>(0, 0, 0, 0), vU = SIMD4<Double>(0, 0, 0, 0), vL = SIMD4<Double>(0, 0, 0, 0), fov = 70.0
        var plan: [SIMD4<Double>] = []; var dist = 0.0; var rail: [SIMD4<Double>] = [] }   // plan：決まった道・自分の道の、これから先の道（予定の道を出す時だけ）。dist：歩いた道のり   // fwd：進む向き。vR・vU・vL：景色を写す向き（右・上・見ている向き）、fov：景色の縦の視野（度）   // poles：通った極（FIXED の番号）
    static var walkSource: (() -> Walk)?
    static var arrowLight = false                                      // 予定の道の矢印のまわりの殻を明るくするか（切ってある）
    static var railWanted = false                                      // 先に道を描くか（さんぽの側は、この時だけ 1 周ぶんの道を作る）
    static var planWanted = false                                      // 予定の道を描くか（さんぽの側は、この時だけ先の道を作る）
    static var planActive = false                                      // 今、予定の道がある（決まった道・自分の道を歩いている）
    /// さんぽのパネル（さんぽの窓と同じ中身）：番号で 1 枚ずつ。さんぽのアプリが入れる
    static var walkPanel: ((Int) -> AnyView)?
    static var walkPanelTitles: [String] = []
    /// 1 コマに 1 度だけ読む（跡は 1 万点を超えることもあるので、何度も写さない）＋なめらかに：さんぽの窓と超球の窓はコマの速さがちがう（72 と 144 など）ので、
    ///   さんぽが進めた 1 歩を、次の 1 歩までの間に少しずつ動かして見せる（1 歩ぶん遅れて、そのかわりカクつかない）
    private var wfT = -1.0, wfCache: Walk?, wPrev: Walk?, wCur: Walk?, wPrevT = 0.0, wCurT = 0.0
    func walkFrame() -> Walk? {
        let now = CACurrentMediaTime()
        if let c = wfCache, abs(now - wfT) < 0.003 { return c }
        guard let src = HyperLabState.walkSource else { return nil }
        let w = src()
        if let c = wCur, simd_distance(w.pos, c.pos) < 1e-12 { wCur = w } else { wPrev = wCur; wPrevT = wCurT; wCur = w; wCurT = now }
        var out = w
        if let p = wPrev, let c = wCur {
            let iv = wCurT - wPrevT
            if iv > 0.002 && iv < 0.25 && simd_distance(p.pos, c.pos) < 0.3 {
                let f = min(1, (now - wCurT) / iv)
                func mix(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> SIMD4<Double> { let m = a + (b - a) * f, l = simd_length(m); return l > 1e-9 ? m / l : b }
                out.dist = p.dist + (c.dist - p.dist) * f
                out.pos = mix(p.pos, c.pos); out.fwd = mix(p.fwd, c.fwd); out.vR = mix(p.vR, c.vR); out.vU = mix(p.vU, c.vU); out.vL = mix(p.vL, c.vL)
                if let ph = p.head, let ch = c.head { out.head = mix(ph, ch) }
                // 跡の先が、見せている所より前にあれば外す（彗星の前に跡が飛び出さない）
                let mv = c.pos - p.pos
                var k = 0
                while k < 3, let last = out.trail.last, simd_dot(last - out.pos, mv) > 0 { out.trail.removeLast(); k += 1 }
            }
        }
        wfT = now; wfCache = out
        return out
    }
    var viewYaw = 0.0, viewPitch = 0.0, viewDist = 7.5                // 右の 3D 視点（ドラッグで回す）
    var leftDist = 5.5
    var version = 0                                                   // 形が変わったら増やす（描く側は変わった時だけ作り直す）
    /// 形や向きが変わった：描く側は version で知る。パネルの表示（SwiftUI）は 1 秒に 12 回までにまとめる（ドラッグのたびに作り直すと、操作がひっかかる）
    // ---- 設定の保存（アプリの中に覚える。窓を開き直しても、アプリを開き直しても同じ） ----
    static let saveKey = "s3walk.hyperlab.v1"
    private var lastSaved = ""
    var snapshot: [String: Any] {
        ["pitch": pitch, "roll": roll, "yaw": yaw, "zw": zw, "viewYaw": viewYaw, "viewPitch": viewPitch, "viewDist": viewDist, "leftDist": leftDist,
         "layers": layers, "mode": mode, "camW": camW, "hemi": hemi, "gloss": gloss, "glare": glare, "lzw": lzw,
         "cutOn": cutOn, "cutRef": cutRef, "cutAngDeg": cutAngDeg, "cutWDeg": cutWDeg, "cutKind": cutKind, "planeDir": planeDir, "cutPos": cutPos, "cut4Axis": cut4Axis, "cutSweep": cutSweep,
         "axes": axes, "axPlus": axPlus, "axThin": axThin, "walk": walk, "marksOn": marksOn, "polesMode": polesMode,
         "spaceMode": spaceMode, "starsPct": starsPct, "layersLink": layersLink, "walkView": walkView, "order": order,
         "followOn": followOn, "followSlack": followSlack, "followSpeed": followSpeed, "followHeading": followHeading, "followDrift": followDrift,
         "diveBlend": diveBlend, "quality": quality, "adaptive": adaptive, "wireW": wireW, "walkOpen": walkOpen, "cursor": cursor, "naviCenter": naviCenter, "map2": map2, "ovShow": ovShow, "glareAuto": glareAuto, "shutWalk": shutWalk, "shutAuto": shutAuto, "walkMenu": walkMenu, "walkPanelOn": walkPanelOn, "walkPanelSel": walkPanelSel, "axesDive": axesDive, "wipeLow": wipeLow, "hyperQ": hyperQ, "planOn": planOn, "railOn": railOn, "planMark": planMark, "planShell": planShell, "planLong": planLong, "planDense": planDense, "opMode": opMode, "spinMode": spinMode, "showMode": showMode, "spinAmp": spinAmp, "spinLen": spinLen, "shellMode": shellMode, "splitX": splitX, "splitY": splitY, "diveThird": diveThird, "chaseDist": chaseDist, "chasePitch": chasePitch, "chaseYaw": chaseYaw, "autoCam": autoCam, "camShow": camShow, "padCam": padCam, "padCamStick": padCamStick, "diveOverview": diveOverview, "ovCursor": ovCursor, "depth4": depth4, "depth4K": depth4K, "depth4On": depth4On, "symGlow": symGlow, "trailW": trailW, "trailCol": trailCol, "poleEN": poleEN, "coordOn": coordOn, "panelHidden": panelHidden, "padOn": padOn, "clearAhead": clearAhead, "show3D": show3D, "lapClear": lapClear, "uiScale": uiScale, "soundOn": soundOn, "soundVol": soundVol, "soundSpatial": soundSpatial, "starDepth": starDepth]
    }
    func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: Self.saveKey) else { return }
        func dbl(_ k: String, _ v: inout Double) { if let x = d[k] as? Double { v = x } }
        func int(_ k: String, _ v: inout Int) { if let x = d[k] as? Int { v = x } }
        func bol(_ k: String, _ v: inout Bool) { if let x = d[k] as? Bool { v = x } }
        dbl("pitch", &pitch); dbl("roll", &roll); dbl("yaw", &yaw); dbl("zw", &zw); dbl("viewYaw", &viewYaw); dbl("viewPitch", &viewPitch); dbl("viewDist", &viewDist); dbl("leftDist", &leftDist)
        int("layers", &layers); int("mode", &mode); dbl("camW", &camW); int("hemi", &hemi); dbl("gloss", &gloss); bol("glare", &glare); int("lzw", &lzw)
        bol("cutOn", &cutOn); int("cutRef", &cutRef); dbl("cutAngDeg", &cutAngDeg); dbl("cutWDeg", &cutWDeg); int("cutKind", &cutKind); int("planeDir", &planeDir); dbl("cutPos", &cutPos); int("cut4Axis", &cut4Axis); bol("cutSweep", &cutSweep)
        bol("axes", &axes); bol("axPlus", &axPlus); bol("axThin", &axThin); bol("walk", &walk); bol("marksOn", &marksOn); int("polesMode", &polesMode)
        int("spaceMode", &spaceMode); dbl("starsPct", &starsPct); bol("layersLink", &layersLink); bol("walkView", &walkView)
        if let o = d["order"] as? [Int], o.count == 3, Set(o) == [0, 1, 2] { order = o }
        bol("followOn", &followOn); dbl("followSlack", &followSlack); dbl("followSpeed", &followSpeed); bol("followHeading", &followHeading); dbl("followDrift", &followDrift)
        bol("diveBlend", &diveBlend); int("quality", &quality); bol("adaptive", &adaptive); dbl("wireW", &wireW); bol("walkOpen", &walkOpen); int("cursor", &cursor); bol("naviCenter", &naviCenter); bol("map2", &map2); bol("ovShow", &ovShow); bol("glareAuto", &glareAuto); bol("shutWalk", &shutWalk); bol("shutAuto", &shutAuto); bol("walkMenu", &walkMenu); bol("walkPanelOn", &walkPanelOn); int("walkPanelSel", &walkPanelSel); bol("axesDive", &axesDive); bol("wipeLow", &wipeLow); int("hyperQ", &hyperQ); bol("planOn", &planOn); bol("railOn", &railOn); int("planMark", &planMark); bol("planShell", &planShell); bol("planLong", &planLong); bol("planDense", &planDense); bol("opMode", &opMode); int("showMode", &showMode); int("spinMode", &spinMode); if ![0, 5, 6].contains(spinMode) { spinMode = 0 }; dbl("spinAmp", &spinAmp); dbl("spinLen", &spinLen); int("shellMode", &shellMode); dbl("splitX", &splitX); dbl("splitY", &splitY); bol("diveThird", &diveThird); dbl("chaseDist", &chaseDist); dbl("chasePitch", &chasePitch); dbl("chaseYaw", &chaseYaw); bol("autoCam", &autoCam); bol("camShow", &camShow); bol("padCam", &padCam); int("padCamStick", &padCamStick); bol("diveOverview", &diveOverview); int("ovCursor", &ovCursor); int("depth4", &depth4); dbl("depth4K", &depth4K); bol("depth4On", &depth4On); bol("symGlow", &symGlow); dbl("trailW", &trailW); int("trailCol", &trailCol); bol("poleEN", &poleEN); bol("coordOn", &coordOn); bol("panelHidden", &panelHidden); bol("padOn", &padOn); bol("clearAhead", &clearAhead); bol("show3D", &show3D); bol("lapClear", &lapClear); bol("soundOn", &soundOn); dbl("soundVol", &soundVol); bol("soundSpatial", &soundSpatial); dbl("starDepth", &starDepth); dbl("uiScale", &uiScale); uiScale = min(2, max(0.75, uiScale))
        if cutOn && cutKind == 0 && cutRef == 2 { polyArm &+= 1 }            // ポリゴンカットは開いた時の手前で作り直す
        lastSaved = "\(snapshot)"
    }
    /// 変わっていれば覚える（左の画面が 1 秒ごとに呼ぶ）
    func saveIfChanged() {
        let s = snapshot, k = "\(s)"
        if k != lastSaved { lastSaved = k; UserDefaults.standard.set(s, forKey: Self.saveKey) }
    }
    /// 確かめ（--verify・--hyperpng など）の時は、覚えた設定を読まない（いつも同じ初めの状態で）
    init() { if !CommandLine.arguments.contains(where: { $0.hasPrefix("--") }) || CommandLine.arguments.contains("--userset") { load() } }
    func bump() {
        version &+= 1
        let now = CACurrentMediaTime()
        if now - lastSend > 0.16 { lastSend = now; objectWillChange.send() }
        else if !sendLater { sendLater = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in self?.sendLater = false; self?.lastSend = CACurrentMediaTime(); self?.objectWillChange.send() } }
    }
    private var lastSend = 0.0, sendLater = false
    func reset() { pitch = 0; roll = 0; yaw = 0; zw = 0; viewYaw = 0; viewPitch = 0; viewDist = 7.5; leftDist = 5.5; bump() }
    static func norm(_ a: Double) -> Double { var x = (a + .pi).truncatingRemainder(dividingBy: 2 * .pi); if x < 0 { x += 2 * .pi }; return x - .pi }
    /// 自動で回す（ウェブ版の「複合」：前後と左右を 1 : 0.67 の速さで）
    func tick(_ dt: Double) {
        guard auto else { return }
        let d = 0.72 * dt
        pitch = Self.norm(pitch + d); roll = Self.norm(roll + d * 0.67); version &+= 1
    }
}

/// スライダー：ドラッグ・矢印キー（スライダーを押してから。← → ↑ ↓、Shift で 10 倍）・数字の入力（右の欄に打って Return）
struct HLSlider: View {
    let name: String
    @Binding var value: Double
    let lo: Double, hi: Double, fmt: String
    @State private var text = ""
    @FocusState private var editing: Bool
    @FocusState private var focused: Bool
    /// 1 回のキーで動く量：表示のけた（%.0f なら 1、%.1f なら 0.1、%.2f なら 0.01）
    static func step(_ fmt: String) -> Double {
        if let r = fmt.range(of: #"\.(\d)f"#, options: .regularExpression), let d = Int(fmt[r].dropFirst().dropLast()) { return pow(10, -Double(d)) }
        return 1
    }
    /// 打った文字を数に（全角・−・°・% などは読み飛ばす。範囲の外は端に）。読めなければ nil
    static func parse(_ s: String, _ lo: Double, _ hi: Double) -> Double? {
        let a = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        let b = a.replacingOccurrences(of: "−", with: "-").filter { "0123456789.-+".contains($0) }
        guard let x = Double(b) else { return nil }
        return min(hi, max(lo, x))
    }
    /// 矢印キー k 回ぶん（k は ±1 か ±10）。けたにそろえて範囲の中に
    static func nudged(_ v: Double, _ k: Double, _ fmt: String, _ lo: Double, _ hi: Double) -> Double {
        let s = step(fmt)
        return min(hi, max(lo, ((v + k * s) / s).rounded() * s))
    }
    private var shown: String { String(format: fmt, value) }
    private func commit() {
        if let x = Self.parse(text, lo, hi) { value = x }
        text = shown
    }
    private func nudge(_ k: Double) { value = Self.nudged(value, k, fmt, lo, hi); text = shown }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name).font(.caption)
                Spacer(minLength: 2)
                TextField("", text: $text)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain).frame(width: 52).focused($editing)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .onSubmit { commit() }
                    .onChange(of: editing) { _, e in if !e { commit() } }
                    .help("数字を打って Return で決める")
            }
            Slider(value: $value, in: lo...hi)
                .focusable().focused($focused)
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if !focused { focused = true } })
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { p in
                    let down = p.key == .leftArrow || p.key == .downArrow
                    nudge((down ? -1 : 1) * (p.modifiers.contains(.shift) ? 10 : 1)); return .handled
                }
        }
        .onAppear { text = shown }
        .onChange(of: value) { _, _ in if !editing { text = shown } }
    }
}
/// さんぽメニュー：超球の窓に浮かぶ、さんぽの操作の小窓（さんぽの窓へ行かなくても歩ける）。半秒ごとに今の様子を読む
struct HLWalkMenu: View {
    let r: Renderer
    var close: () -> Void
    var openPanels: () -> Void = {}
    var panelsOn = false
    @State private var tick = 0
    @State private var folded = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk").foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
                Text("さんぽ").font(.caption.weight(.semibold))
                Text(r.walking || r.pathMode != .none || r.roaming ? "歩いている" : "止まっている").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { openPanels() } label: { Image(systemName: panelsOn ? "slider.horizontal.3" : "slider.horizontal.below.rectangle") }.buttonStyle(.plain)
                    .foregroundStyle(panelsOn ? Color(red: 0.55, green: 0.8, blue: 1.0) : .secondary).help("さんぽの設定（さんぽの窓のパネル全部。記録した道も）を出す・隠す")
                Button { folded.toggle() } label: { Image(systemName: folded ? "chevron.down" : "chevron.up") }.buttonStyle(.plain).help(folded ? "ひらく" : "たたむ")
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("さんぽメニューを隠す（パネルの「さんぽメニュー」でまた出す）")
            }
            if !folded {
                HStack(spacing: 6) {
                    Button(r.walking ? "■ 止まる" : "▶︎ 歩く") { r.walking.toggle(); r.roaming = false; r.pathMode = .none; tick &+= 1 }
                    Button("縦横無尽") { r.roaming.toggle(); r.walking = r.roaming; r.pathMode = .none; tick &+= 1 }.help("歩き続けながら、向きがゆっくり変わる")
                }
                HStack(spacing: 4) {
                    Text("速さ").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { r.set.cruise }, set: { r.set.cruise = $0; if r.walking { r.autoSpeed = $0 }; tick &+= 1 }), in: 0.2...8).frame(width: 120)
                    Text(String(format: "×%.1f", r.set.cruise)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    Button("目印を置く") { r.addMark(); tick &+= 1 }
                    Button("跡を消す") { r.clearTrail(); tick &+= 1 }
                    Button("アナ極へ") { r.resetNorth(); tick &+= 1 }.help("出発点（アナ極）に戻る。目印は残す")
                }
                HStack(spacing: 4) {
                    // 道の速さ：歩いている道の今の速さと、次に歩き始める時の速さ（出発の速さ）をいっしょに
                    Text("道の速さ").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { r.pathMode != .none ? r.pathSpeed : r.set.routeStart }, set: { v in r.set.routeStart = v; if r.pathMode != .none { r.pathSpeed = v }; tick &+= 1 }), in: 0.2...16).frame(width: 100)
                        .help("決まった道・自分の道の速さ。次に歩き始める時も、この速さから")
                    Text(String(format: "×%.1f", r.pathMode != .none ? r.pathSpeed : r.set.routeStart)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                HStack(spacing: 4) {
                    Text("決まった道").font(.caption2).foregroundStyle(.secondary)
                    ForEach([(PathMode.spiral, "螺旋"), (.ring, "回る輪"), (.tour, "極めぐり")], id: \.0.rawValue) { m, name in
                        let on = m == .tour ? r.tourActive : r.pathMode == m
                        Button(name) { if on { r.pathMode = .none } else { r.startPath(m) }; tick &+= 1 }
                            .tint(on ? Color(red: 0.55, green: 0.8, blue: 1.0) : nil)
                    }
                }
            }
        }
        .controlSize(.small).font(.caption)
        .padding(10).frame(width: 250, alignment: .leading)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
        .onReceive(timer) { _ in tick &+= 1 }
    }
}
/// さんぽの設定：さんぽの窓のパネル（歩く・決まった道（記録した自分の道も）・目印・球層・見え方…）を、そのまま浮かぶ窓に。上のタブで切りかえ
struct HLWalkPanels: View {
    @ObservedObject var st: HyperLabState
    var body: some View {
        let titles = HyperLabState.walkPanelTitles
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("さんぽの設定").font(.caption.weight(.semibold))
                Spacer()
                Button { st.walkPanelOn = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("さんぽの設定を隠す")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(titles.indices, id: \.self) { i in
                        Button(titles[i]) { st.walkPanelSel = i }
                            .buttonStyle(.plain).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3)
                            .background((st.walkPanelSel == i ? Color(red: 0.25, green: 0.4, blue: 0.65) : Color.white.opacity(0.06)), in: Capsule())
                    }
                }
            }
            ScrollView { (HyperLabState.walkPanel?(min(st.walkPanelSel, max(0, titles.count - 1))) ?? AnyView(EmptyView())).padding(.trailing, 6) }
                .frame(maxHeight: 420)
        }
        .controlSize(.small).font(.caption)
        .padding(10).frame(width: 330, alignment: .leading)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
    }
}
/// パネルを s 倍の大きさで（幅は窓に合わせ、中身を 1/s の幅で並べてから s 倍に。高さは中身に合わせる。はみ出したら横にスクロール）
struct HLScaled<C: View>: View {
    let s: CGFloat
    var maxH: CGFloat = .infinity                                     // 見せる高さの上限（窓の高さの 4 割ほど。超球の画面を必ず残す）
    @ViewBuilder let content: () -> C
    @State private var h: CGFloat = 100
    var body: some View {
        // パネルは窓を押し広げない：横にはみ出した分も、上限より高い分も、スクロールして見る（全画面・iPad で端が切れない）
        let vis = min(h * s, max(80, maxH))
        GeometryReader { g in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                content().environment(\.hlPanelW, g.size.width / s).frame(minWidth: g.size.width / s, alignment: .topLeading).fixedSize(horizontal: true, vertical: true)
                    .background(GeometryReader { q in Color.clear.preference(key: HLHeightKey.self, value: q.size.height) })
            }
            .frame(width: g.size.width / s, height: vis / s, alignment: .topLeading)
            .scaleEffect(s, anchor: .topLeading)
        }
        .frame(height: vis)
        .onPreferenceChange(HLHeightKey.self) { v in if abs(v - h) > 0.5 { h = v } }
    }
}
/// パネルの中身を並べる幅（HLScaled が入れる。折り返す段 HLWrap が使う）
private struct HLPanelWKey: EnvironmentKey { static let defaultValue: CGFloat = .infinity }
extension EnvironmentValues { var hlPanelW: CGFloat { get { self[HLPanelWKey.self] } set { self[HLPanelWKey.self] = newValue } } }
/// 横に並べて、幅を越える所で次の行へ折り返す（各行は縦の真ん中でそろえる）
struct HLFlow: Layout {
    var spacing: CGFloat = 8, lineSpacing: CGFloat = 6, maxW: CGFloat = .infinity
    private func lines(_ sv: Subviews, _ w: CGFloat) -> [[(Int, CGSize)]] {
        var out: [[(Int, CGSize)]] = [[]], x: CGFloat = 0
        for (i, v) in sv.enumerated() {
            let sz = v.sizeThatFits(.unspecified)
            if !out[out.count - 1].isEmpty && x + spacing + sz.width > w { out.append([]); x = 0 }
            x += (out[out.count - 1].isEmpty ? 0 : spacing) + sz.width
            out[out.count - 1].append((i, sz))
        }
        return out
    }
    private func width(_ p: ProposedViewSize) -> CGFloat { min(maxW, p.width ?? .infinity) }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ls = lines(subviews, width(proposal))
        var w: CGFloat = 0, h: CGFloat = 0
        for l in ls {
            var lw: CGFloat = 0, lh: CGFloat = 0
            for (_, sz) in l { lw += sz.width; lh = max(lh, sz.height) }
            lw += spacing * CGFloat(max(0, l.count - 1))
            w = max(w, lw); h += lh
        }
        h += lineSpacing * CGFloat(max(0, ls.count - 1))
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for l in lines(subviews, width(proposal)) {
            var lh: CGFloat = 0
            for (_, sz) in l { lh = max(lh, sz.height) }
            var x = bounds.minX
            for (i, sz) in l { subviews[i].place(at: CGPoint(x: x, y: y + (lh - sz.height) / 2), proposal: ProposedViewSize(sz)); x += sz.width + spacing }
            y += lh + lineSpacing
        }
    }
}
/// パネルの 1 段：パネルの幅に収まらない時は、次の行へ折り返す（右の端が見切れて触れなくならないように）
struct HLWrap<C: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> C
    @Environment(\.hlPanelW) private var pw
    var body: some View { HLFlow(spacing: spacing, maxW: max(300, pw - 28)) { content() } }
}
struct HLHeightKey: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) } }
/// 画面の仕切り（ドラッグで動かす。位置は仕切りの並ぶ範囲の中の座標で渡す）
struct HLSplitBar: View {
    let vertical: Bool                                                // true：左右を分ける縦の仕切り
    let onDrag: (CGFloat) -> Void, onReset: () -> Void
    @State private var hover = false
    var body: some View {
        Rectangle().fill(hover ? Color(red: 0.35, green: 0.55, blue: 0.85) : Color(red: 0.12, green: 0.16, blue: 0.23))
            .frame(width: vertical ? 5 : nil, height: vertical ? nil : 5)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("hlsplit")).onChanged { v in onDrag(vertical ? v.location.x : v.location.y) })
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
            .onHover { h in
                hover = h
                #if os(macOS)
                if h { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                #endif
            }
            .help("ドラッグで画面の大きさを変える（ダブルクリックで半分に）")
    }
}
/// コマ数の表示（1 秒ごとに変わる。ここだけ描き直す）
final class HLStats: ObservableObject { @Published var text = "" }
/// 動いている間に変わる表示（角度の読み・景色の重ねぐあい）。パネル全体を描き直すと 40 ms ほど止まってカクつくので、ここだけ描き直す
final class HLLive: ObservableObject { @Published var angles = ""; @Published var fade = 0.0; @Published var lap = ""; @Published var coords = "" }
/// 周回（右の画面の隅に小さく）
struct HLLapLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        if !live.lap.isEmpty {
            Text(live.lap).font(.system(size: 14 * scale, weight: .semibold, design: .serif)).foregroundStyle(Color(red: 0.85, green: 1.0, blue: 0.75))
                .padding(.horizontal, 11).padding(.vertical, 5).background(Color.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.64, green: 1.0, blue: 0.24).opacity(0.8), lineWidth: 1.5))   // 周回は蛍光の縁で目立たせる
                .padding(.top, 40).padding(.trailing, 12).allowsHitTesting(false)
        }
    }
}
/// 走行中の座標（右の画面の左上。計器のように 1 秒に 10 回書きかわる）
struct HLCoordLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        if !live.coords.isEmpty {
            Text(live.coords).font(.system(size: 10.5 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.62, green: 0.92, blue: 1.0)).lineSpacing(2)
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.7), radius: 3)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.4, green: 0.85, blue: 1.0).opacity(0.35), lineWidth: 1))
                .padding(.top, 40).padding(.leading, 12).allowsHitTesting(false)
        }
    }
}
struct HLAnglesLabel: View {
    @ObservedObject var live: HLLive
    var body: some View {
        Text(live.angles).font(.system(size: 10, design: .monospaced)).padding(6)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct HLDiveOverlay: View {
    @ObservedObject var live: HLLive
    var body: some View { if live.fade > 0 { WalkScenePane(big: true).opacity(live.fade).allowsHitTesting(false) } }
}
struct HLHandoffNote: View {
    @ObservedObject var live: HLLive
    var body: some View {
        if live.fade > 0.99 {
            Text("景色は右の大きな画面へ（ダイブ中）").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.6)).allowsHitTesting(false)
        }
    }
}
struct HLStatsLabel: View {
    @ObservedObject var stats: HLStats
    var body: some View { Text(stats.text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
}
/// 描く頂点：位置・法線・色（w は透明度）
struct HLVert { var p: SIMD4<Float>; var n: SIMD4<Float>; var c: SIMD4<Float> }
/// 描く時の定数：key・rim は照り返しライトの向き（カメラについて回る）、camR・camU はカメラの右・上（グレアの帯）、g は（光沢・グレア・光を当てる・未使用）
/// 右の殻の毎コマの定数（シェーダーの HR）
struct HLRight { var m4 = matrix_identity_float4x4; var q = SIMD4<Float>(1, 1, 3.8, 1.55); var r = SIMD4<Float>(1.35, 48, 0, 0); var d = SIMD4<Float>(0.6, 0, 0, 0); var e = SIMD4<Float>(0, 0, 0, 0); var s = SIMD4<Float>(0, 0, 0, 0); var t = SIMD4<Float>(0, 0, 0, 0); var f = SIMD4<Float>(0, 0, 0, 0)
    var a0 = SIMD4<Float>(0, 0, 0, 0), a1 = SIMD4<Float>(0, 0, 0, 0), a2 = SIMD4<Float>(0, 0, 0, 0), a3 = SIMD4<Float>(0, 0, 0, 0) }   // a0〜a3：予定の道の矢印の明かり（S³ の点。強さは t.w）   // f：進む向き（S³ の接する向き。ヘッドライト）   // s：自分のいる所（S³ の点）、t.x：その近くを濃くする強さ（下の HR と同じ）
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
// 左の輪（細い管）：1 本の型（cos u, sin u, cos v, sin v）を、輪ごとの半径 ρ・高さ h・管の太さで GPU が組み立てる（Z-W を動かしても CPU で作り直さない）
struct RI { float4 a; float4 c; };                            // a：ρ・h・管の太さ、c：色
vertex O ringv(uint vid [[vertex_id]], uint iid [[instance_id]], const device float4* m [[buffer(0)]], constant U& u [[buffer(1)]], const device RI* ri [[buffer(2)]]) {
    float4 q = m[vid]; RI r = ri[iid];
    float3 n = float3(q.z * q.x, q.z * q.y, q.w), p = float3(r.a.x * q.x, r.a.x * q.y, r.a.y) + n * r.a.z;
    if (r.a.w > 1.5) { p = p.xzy; n = n.xzy; } else if (r.a.w > 0.5) { p = p.zxy; n = n.zxy; }   // 4 方向・軸の色：y・x の軸のまわりの輪
    O o; float4 w = u.model * float4(p, 1.0); o.pos = u.mvp * w; o.wp = w.xyz; o.n = (u.model * float4(n, 0.0)).xyz; o.c = r.c; o.ph = 0.0; return o;
}
// 右の殻（GPU で 4D の回転・遠近）：元の点（層ごとに緯度 × 経度の 4D の点）は 1 度だけ送り、回す行列だけを毎コマ渡す。
//   法線はとなりの点を同じように写して求める。4D の裏側（4D の視点から見て奥の半分）は暗く・くすませる（ウェブ版の「裏側を暗く」）
struct HR { float4x4 m4; float4 q; float4 r; float4 d; float4 e; float4 s; float4 t; float4 f; float4 a0; float4 a1; float4 a2; float4 a3; };   // a0〜a3：矢印の明かり   // f：進む向き（ヘッドライト）   // s：自分のいる所（S³ の点）、t.x：その近くの殻・網目を濃くする強さ（selfK）
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
// 玉の交差を透かす（h.e.w）：w の極のまわりの殻（赤玉・紫玉）だけ残して、間の殻を透明に
inline float ballK(float4 b, constant HR& h) { return mix(1.0, smoothstep(0.80, 0.96, abs(b.w) / h.r.x) * (1.0 + 0.9 * h.e.w), h.e.w); }
inline float3 hproj(float4 b, constant HR& h) { float4 v = h.m4 * b; return v.xyz * (h.q.z / max(h.d.x, h.q.z - v.w) * h.q.w); }
vertex O hrv(uint vid [[vertex_id]], const device float4* base [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]], const device float4* lc [[buffer(3)]]) {
    uint M = uint(h.r.y), M1 = M + 1, per = M1 * M1, L = vid / per, k = vid % per, i = k / M1, j = k % M1, o0 = L * per;
    float4 b = base[vid], v = h.m4 * b; float3 P = hproj(b, h);
    float3 a = hproj(base[o0 + min(M, i + 1) * M1 + j], h) - hproj(base[o0 + (i > 0 ? i - 1 : 0) * M1 + j], h);
    float3 c = hproj(base[o0 + i * M1 + (j + 1) % M1], h) - hproj(base[o0 + i * M1 + (j + M - 1) % M], h);
    float3 n = cross(a, c); if (length(n) < 1e-7) n = P;
    float R = h.r.x, face = (v.w - R * R / h.q.z) / R, bk = 0.6 * (1.0 - smoothstep(-0.1, 0.05, face));
    float3 col = lc[L].rgb * h.q.x; float gray = dot(col, float3(0.299, 0.587, 0.114));
    O o; o.pos = u.mvp * float4(P, 1.0); o.wp = P; o.n = n; float hz = h.e.x * pow(dep4(v.w, h), 1.3);                          // 4D のかすみ：奥ほど背景の色へ溶けて淡く
    col = mix(col, float3(0.012, 0.027, 0.07), hz * 0.85);
    o.c = float4((col + (gray - col) * (0.4 * bk)) * (1.0 - 0.5 * bk), h.q.y * lc[L].a * (1.0 - 0.55 * hz)); o.ph = float(j) / float(M) * 2.0 * M_PI_F;
    // 殻（g.z ＝ 2）：光は頂点ごとに計算して面の上でなめらかにつなぐ（21 枚の半透明の殻を全部の画素で計算すると、とても重い。殻はなめらかな球なので頂点で十分）
    // 4 方向レインボー（h.r.z）：殻が何枚も重なるので、表面をざらっと（てかりがぼんやり広がる。殻ごとの小さなてかりが点々と並んで白い筋にならない）
    if (u.g.z > 1.5) o.c = lightHL(n, P, o.c, h.r.z > 0.0 ? 0.6 : 0.0, u);
    o.c.a *= ballK(b, h);                                             // 反射の明るさも一緒に透かす（照り返しは不透明さを足すので、光のあとで）
    // 自分の近くの殻：少し濃く・明るく（離れるほど元に）
    { float sk = selfK(b, h), ak = arrowK(b, h); o.c.a *= 1.0 + 1.6 * sk + 0.9 * ak; o.c.rgb *= (1.0 + 0.35 * sk) * max(headK(b, h), 0.7 + 0.3 * ak) + float3(1.0, 0.78, 0.35) * 0.12 * ak; }
    // 斜めから見た殻は濃く（薄い膜を斜めに通る光は、膜の中を長く通る：1 −（1 − a）^(1／cos)）。ふつうのレインボー（h.t.z）。
    //   4 方向・4 軸は下の「殻のふち」で同じ見え方を作っているので、ここでは足さない
    if (h.t.z > 0.0) { float cv = max(0.25, abs(dot(normalize(n), normalize(u.eye.xyz - P)))); float a0 = clamp(o.c.a, 0.0, 0.95); o.c.a = mix(o.c.a, 1.0 - pow(1.0 - a0, 1.0 / cv), h.t.z); }
    // 殻のふち（h.r.z。4 方向レインボー）：横から見ている所ほど少し濃く・明るく（ガラスの球のように形と奥行きが浮かぶ）
    if (h.r.z > 0.0) { float rim = 1.0 - abs(dot(normalize(n), normalize(u.eye.xyz - P))); float rk = pow(rim, 3.0) * h.r.z; o.c.a *= 1.0 + 1.8 * rk; o.c.rgb *= 1.0 + 0.5 * rk; }
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
    float4 b = base[vid], v = h.m4 * b; P = hproj(b, h);
    float R = h.r.x, face = (v.w - R * R / h.q.z) / R, bk = 0.6 * (1.0 - smoothstep(-0.1, 0.05, face));
    float3 col = lc[L].rgb * h.q.x;
    // 4 方向レインボー：光の線にするので、暗い色（紫・青）は明るさをそろえて光らせる（色合いはそのまま）
    if (h.r.z > 0.0) { float mx = max(max(col.r, col.g), col.b); col = col / max(mx, 0.05) * mix(0.75, mx, 0.4); }
    float gray = dot(col, float3(0.299, 0.587, 0.114));
    float dp = dep4(v.w, h), hz = h.e.x * pow(dp, 1.3);
    col = mix(col, float3(0.012, 0.027, 0.07), hz * 0.85);
    bl = h.e.y * pow(dp, 1.25);                                         // 4D のぼかし：奥ほど太く・やわらかく・淡く（ぼけた線の見え方）
    float la = h.r.z > 0.0 ? min(lc[L].a, h.r.z) : lc[L].a;              // 網目の濃さの上限（4 方向レインボー）
    float sk = selfK(b, h), ak = arrowK(b, h); la *= 1.0 + 1.3 * sk + 0.8 * ak; col = col * (1.0 + 0.4 * sk) * max(headK(b, h), 0.7 + 0.3 * ak) + float3(1.0, 0.78, 0.35) * 0.18 * ak;   // 自分の近くの網目：少し強く（離れるほど元に）。遠くはヘッドライトで暗く
    c = float4((col + (gray - col) * (h.d.y * bk)) * (1.0 - h.d.z * bk), h.q.y * la * (1.0 - 0.5 * hz) / (1.0 + 3.5 * bl) * ballK(base[vid], h)); ph = float(j) / float(M) * 2.0 * M_PI_F;   // 網目の裏側：灰色へ寄せる割合 d.y・暗くする割合 d.z
}
vertex WO hrwv(uint vid [[vertex_id]], uint iid [[instance_id]], const device float4* base [[buffer(0)]], constant U& u [[buffer(1)]], constant HR& h [[buffer(2)]],
               const device float4* lc [[buffer(3)]], const device uint* idx [[buffer(4)]], constant float4& k [[buffer(5)]]) {
    float3 Pa, Pb; float4 cA, cB; float pa, pb, ba, bb;
    hshade(idx[iid * 2], base, h, lc, Pa, cA, pa, ba); hshade(idx[iid * 2 + 1], base, h, lc, Pb, cB, pb, bb);
    return wideLine(u.mvp * float4(Pa, 1), u.mvp * float4(Pb, 1), cA, cB, Pa, Pb, pa, pb, vid, k, ba, bb);
}
// 左など：線分 iid ＝ 頂点 2 iid と 2 iid ＋ 1（HLVert の並び）
vertex WO segwv(uint vid [[vertex_id]], uint iid [[instance_id]], constant V* vs [[buffer(0)]], constant U& u [[buffer(1)]], constant float4& k [[buffer(5)]]) {
    V a = vs[iid * 2], b = vs[iid * 2 + 1];
    float4 wa = u.model * float4(a.p.xyz, 1), wb = u.model * float4(b.p.xyz, 1);
    return wideLine(u.mvp * wa, u.mvp * wb, a.c, b.c, wa.xyz, wb.xyz, 0, 0, vid, k, 0, 0);
}
fragment float4 wlf(WO in [[stage_in]], constant U& u [[buffer(1)]]) {
    if (u.cut.x > 2.5) { if (dot(in.wp, u.cutN.xyz) > u.cutN.w) discard_fragment(); }
    else if (u.cut.x > 0.5) {
        float a = (u.cut.x < 1.5 ? atan2(dot(in.wp, u.camR.xyz), dot(in.wp, cross(u.camR.xyz, u.camU.xyz))) : in.ph) - u.cut.y;
        a -= 2.0 * M_PI_F * floor((a + M_PI_F) / (2.0 * M_PI_F));
        if (abs(a) < u.cut.z) discard_fragment();
    }
    float a = clamp((in.hw + 0.5 + in.sf * 0.5 - abs(in.side)) / (1.0 + in.sf), 0.0, 1.0);   // ふちは 1 画素（ぼかしの時は、そのぶん広く）やわらかく
    if (in.sf > 0.01) a = a * a * (3.0 - 2.0 * a);
    if (a <= 0.0) discard_fragment();
    return float4(in.c.rgb, in.c.a * a);
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
    /// 全体像（ダイブ中に 3D の球の場所へ出す、ダイブしていない超球）：ダイブは見ない
    var overview = false
    var ovMotion = false                                              // 全体像のうち、W 地図（軸がうねうね動く・断面・中へ入る）。ふつうの全体像はナビ地図
    // 動画の書き出し（記録 → 書き出し）で、記録した時刻・拍・細かさで描き直すための差しかえ。nil ならふだんどおり
    var clockOverride: Double? = nil, domOverride: Double? = nil, renderKOverride: Double? = nil
    var nowT: Double { clockOverride ?? CACurrentMediaTime() }
    var rK: Double { renderKOverride ?? HyperLabState.renderK }
    /// いま画面に出ている、右の超球の画面（記録はこの画面から取る）
    static weak var liveMain: HyperLabRenderer?
    static var liveRightW = 1390.0
    /// 誘導灯の光とドミノの拍（彗星の音のうなり 6 つで 1 回。音が鳴っていない時は 4 秒ごと）
    static func domClock(_ now: Double) -> Double {
        let b = HyperSound.shared.beatClock()
        return now - b.stamp < 0.4 && b.rate > 0.05 ? (b.cyc + b.rate * (now - b.stamp)) / 6 : now / 4.0
    }
    private var dvT: Double { overview ? 0 : st.diveT }
    private var dvFade: Double { overview ? 0 : st.diveFade }
    private var dvThird: Double { overview ? 0 : st.thirdK }
    /// 今いる所の印（全体像は別に選べる。−1 ならふつうと同じ）
    private var cur: Int { overview && st.ovCursor >= 0 ? st.ovCursor : st.cursor }
    let device: MTLDevice, queue: MTLCommandQueue
    private var opaquePipe: MTLRenderPipelineState!, alphaPipe: MTLRenderPipelineState!
    private var depthWrite: MTLDepthStencilState!, depthRead: MTLDepthStencilState!, depthAlways: MTLDepthStencilState!
    private var tris: [HLVert] = [], glass: [HLVert] = [], lines: [HLVert] = []
    private var triBuf: MTLBuffer?, glassBuf: MTLBuffer?, lineBuf: MTLBuffer?
    /// 右：層ごとの範囲（殻の面・その層の線）。ウェブ版（three.js）と同じく、層の順に「面 → 線」と描く
    private var ranges: [(g: Range<Int>, l: Range<Int>)] = []
    /// 右：元の 4D の点・層の色・つなぎ方（三角形と線の番号）。層数・半球が変わった時だけ作る
    private var rBase: MTLBuffer?, rCol: MTLBuffer?, rIdx: MTLBuffer?, rMesh = 48
    private var rPipe: MTLRenderPipelineState!, dsPipe: MTLRenderPipelineState!, mirPipe: MTLRenderPipelineState!, mirTex: MTLTexture?
    private var polyArmSeen = 0
    private var wirePipe: MTLRenderPipelineState!, wirePipeAdd: MTLRenderPipelineState!, segPipe: MTLRenderPipelineState!
    private var ringPipe: MTLRenderPipelineState!, ringMesh: MTLBuffer?, ringMeshCount = 0, rings: [HLRing] = []
    private var leftRings: [(rho: Double, h: Double, col: SIMD3<Float>)] = []
    private var rPipeAdd: MTLRenderPipelineState!, starPipe: MTLRenderPipelineState!, bgPipe: MTLRenderPipelineState!, bgMakePipe: MTLRenderPipelineState!
    private var bgTex: MTLTexture?                                    // 宇宙の背景の絵（大きさが変わった時だけ作る。毎コマ星雲を計算すると重い）
    private var bgTex2: MTLTexture?
    /// 天の川：S³ の大きな球面（法線 milkyN に垂直な S²）のまわりに、細かい星と、ぼんやりした光の雲。寄ると見える
    static let milkyN = simd_normalize(SIMD4<Float>(0.35, 0.55, -0.25, 0.72))
    private lazy var milkyBufs: (dust: MTLBuffer?, haze: MTLBuffer?, nd: Int, nh: Int) = {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Float { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Float(seed % 1_000_000) / 1_000_000 }
        func gauss() -> Float { let u = max(1e-6, rnd()), v = rnd(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
        let n = Self.milkyN
        func make(_ count: Int, _ thick: Float, _ bright: ClosedRange<Float>) -> [StarGPU] {
            var out: [StarGPU] = []; out.reserveCapacity(count)
            while out.count < count {
                var p = SIMD4<Float>(gauss(), gauss(), gauss(), gauss()); p = simd_normalize(p)
                let d = simd_dot(p, n); p -= n * d; p = simd_normalize(p)                 // 帯の上へ
                p = simd_normalize(p + n * gauss() * thick)                               // 帯の厚み
                // 濃いところと薄いところ（ちぎれた雲のように）
                let cl = 0.5 + 0.5 * sin(p.x * 7.1 + p.y * 3.3) * sin(p.z * 5.7 - p.w * 4.1 + 1.3)
                if rnd() > 0.25 + 0.75 * cl { continue }
                let warm = rnd()
                let c = simd_mix(SIMD3<Float>(0.72, 0.82, 1.0), SIMD3<Float>(1.0, 0.88, 0.72), SIMD3(repeating: warm))
                out.append(StarGPU(p: p, c: SIMD4(c, bright.lowerBound + (bright.upperBound - bright.lowerBound) * rnd() * rnd())))
            }
            return out
        }
        let dust = make(30000, 0.06, 0.15...1.4)
        // 天の川の淡い光：さんぽの景色と同じ、大きな円（y・z の円。北極・南極・天極・地極を通る）のまわり（Renderer.makeStars の天の川の星と同じ広がり 0.11）
        var haze: [StarGPU] = []
        while haze.count < 6000 {
            let s = Double(rnd()) * 2 * .pi, g1 = Double(gauss()) * 0.13, g2 = Double(gauss()) * 0.13
            let p = simd_normalize(SIMD4<Float>(Float(g1), Float(cos(s)), Float(sin(s)), Float(g2)))
            let cl = 0.55 + 0.45 * sin(Float(s) * 5 + 1.3) * sin(Float(s) * 3.1 - 0.4)   // 濃いところと薄いところ
            if rnd() > cl { continue }
            let warm = rnd()
            haze.append(StarGPU(p: p, c: SIMD4(simd_mix(SIMD3<Float>(0.62, 0.74, 1.0), SIMD3<Float>(0.95, 0.88, 1.0), SIMD3(repeating: warm)), 0.08 + 0.2 * rnd())))
        }
        func buf(_ a: [StarGPU]) -> MTLBuffer? { a.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) } }
        return (buf(dust), buf(haze), dust.count, haze.count)
    }()
    /// 寄った時の天の川の淡い光（右の画面・ダイブで寄るほど。さんぽの景色と同じ y・z の円のまわり）。dust の帯は使っていない（さんぽと位置が合わない）
    ///   haze：ぼんやりした光の雲だけを、いちばん奥の背景として（網目より先に・奥行きを見ずに。網目の影が雲に浮き出ないように）。ほかは細かい星
    private func drawMilkyWay(_ e: MTLRenderCommandEncoder, _ u: HLUni, _ h: HLRight, _ z: Float, haze: Bool) {
        guard z > 0.02 else { return }
        let mb = milkyBufs
        var uu = u, hh = h; uu.cut = .zero
        var tz = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0.3 * z, z, 0)   // またたきは控えめ。z：遠近
        e.setRenderPipelineState(starPipe); e.setDepthStencilState(haze ? depthAlways : depthRead)
        e.setVertexBytes(&uu, length: MemoryLayout<HLUni>.stride, index: 1); e.setVertexBytes(&hh, length: MemoryLayout<HLRight>.stride, index: 2)
        e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
        if haze, let b = mb.haze {                                        // 天の川の淡い光（大きく・とても淡く。遠くの光なので遠近で消さない）
            var k = SIMD4<Float>(0.75, 0, 1, 0.19 * z)   // 帯に集まっているので少し強めに（強すぎるとまぶしい・画面が白い雲で覆われる）
            var tz2 = tz; tz2.y = 0; tz2.z = 0; tz2.w = 0; e.setVertexBytes(&tz2, length: 16, index: 4); e.setFragmentBytes(&tz2, length: 16, index: 4)
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&k, length: 16, index: 3)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: mb.nh)
            e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
        }
        if !haze, let b = mb.dust {                                       // 細かい星（またたく）
            var k = SIMD4<Float>(0.026, 0, 1, 1.0 * z)   // 星くず：景色と同じように星があると分かるくらい、ごく淡く小さく
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&k, length: 16, index: 3)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: mb.nd)
        }
    }
    private lazy var starBuf: MTLBuffer? = { let s = Renderer.starList; return device.makeBuffer(bytes: s, length: MemoryLayout<StarGPU>.stride * s.count) }()
    private var cometPipe: MTLRenderPipelineState!
    private var lbPipe: MTLRenderPipelineState!, labelTex: [String: MTLTexture] = [:]
    /// 左：2 倍の大きさで描くための絵（変わった時だけ作る）
    private var ssTex: (ms: MTLTexture, dep: MTLTexture, hi: MTLTexture)?
    private var builtKey = "", lastT = CACurrentMediaTime(), fpsN = 0, fpsT = CACurrentMediaTime()
    /// コマ数を動きに合わせる：見た目に関わる値の組（前のコマと同じなら「止まっている」）・止まっている時間・画面のいちばん速いコマ数
    private var lastSig: [Double] = [], stillT = 0.0, lowFPS = false, maxFPS = 60, moveFPS = 60
    private var pN = 0, pT = 0.0, slowS = 0, fastS = 0          // 実際のコマ数を数える（1 秒ごと）・遅い／速い秒が続いた数
    /// 描く画素の数を画質に合わせる（画面の細かさ × renderK）。画面には拡大して出す
    static func fit(_ view: MTKView, extra: Double = 1) {
        #if os(macOS)
        let bs = view.window?.backingScaleFactor ?? 2
        #else
        let bs = view.window?.screen.scale ?? UIScreen.main.scale
        #endif
        let k = HyperLabState.renderK * extra
        let want = CGSize(width: max(8, (view.bounds.width * bs * k).rounded()), height: max(8, (view.bounds.height * bs * k).rounded()))
        if view.autoResizeDrawable { view.autoResizeDrawable = false }
        if view.drawableSize != want { view.drawableSize = want }
    }
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
        func pipe(_ blend: Bool, _ vf: String = "hlv", _ ff: String = "hlf", add: Bool = false) -> MTLRenderPipelineState {   // add：足し合わせ
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
        opaquePipe = pipe(false); alphaPipe = pipe(true); rPipe = pipe(true, "hrv"); ringPipe = pipe(false, "ringv")
        wirePipe = pipe(true, "hrwv", "wlf"); wirePipeAdd = pipe(true, "hrwv", "wlf", add: true); segPipe = pipe(true, "segwv", "wlf")
        // 輪の型（周 160 × 管の周り 16 の三角形。cos u, sin u, cos v, sin v）
        var mesh: [SIMD4<Float>] = []; let sa = 160, sb = 16
        func rq(_ a: Int, _ b: Int) -> SIMD4<Float> { let uu = Float(a) / Float(sa) * 2 * .pi, vv = Float(b) / Float(sb) * 2 * .pi; return SIMD4(cos(uu), sin(uu), cos(vv), sin(vv)) }
        for a in 0..<sa { for b in 0..<sb { mesh += [rq(a, b), rq(a + 1, b), rq(a + 1, b + 1), rq(a, b), rq(a + 1, b + 1), rq(a, b + 1)] } }
        ringMeshCount = mesh.count
        ringMesh = mesh.withUnsafeBytes { d.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rPipeAdd = pipe(true, "hrv", add: true); cometPipe = pipe(true, "cmv", "cmf", add: true); starPipe = pipe(true, "stv", "stf", add: true); bgPipe = pipe(false, "dsv", "cpf")
        let bp = MTLRenderPipelineDescriptor(); bp.vertexFunction = lib.makeFunction(name: "bgv"); bp.fragmentFunction = lib.makeFunction(name: "bgf")
        bp.colorAttachments[0].pixelFormat = .bgra8Unorm; bgMakePipe = try! d.makeRenderPipelineState(descriptor: bp)
        let dp = MTLRenderPipelineDescriptor(); dp.vertexFunction = lib.makeFunction(name: "dsv"); dp.fragmentFunction = lib.makeFunction(name: "dsf")
        dp.colorAttachments[0].pixelFormat = .bgra8Unorm; dsPipe = try! d.makeRenderPipelineState(descriptor: dp)
        dp.fragmentFunction = lib.makeFunction(name: "mirf"); mirPipe = try! d.makeRenderPipelineState(descriptor: dp)
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
    /// S³ の点 p（長さ 1）のところの球殻の色（球層の色の決まり方 m：0 レインボー・1 4 方向レインボー・2 軸の色）。
    ///   レインボーは、その軸の座標 c から緯度 θ＝acos|c| を出して層の色（北は赤→水色、南は紫→青）。4 方向・軸の色は、
    ///   いちばん近い軸ほど強く（座標の 4 乗の重み）混ぜる
    static func shellTint(_ p: SIMD4<Double>, _ m: Int) -> SIMD3<Float> {
        func rain(_ c: Double) -> SIMD3<Float> {
            let th = acos(min(1, abs(c))), t = max(0, min(1, (th - MIN_THETA) / (Double.pi / 2 - MIN_THETA)))
            return c < 0 ? hsl(0.80 - t * 0.30, 0.95, 0.52) : hsl(t * 0.50, 0.95, 0.52)
        }
        if m != 1 && m != 2 { return rain(p.w) }
        let cs = [p.x, p.y, p.z, p.w]
        var sum = SIMD3<Float>(), wsum = 0.0
        for k in 0..<4 {
            let w = pow(cs[k], 4), col: SIMD3<Float>
            if m == 1 { col = rain(cs[k]) }
            else { let f = Float(1 - abs(cs[k])); col = simd_mix(axisCol[k] * (0.55 + 0.45 * f), SIMD3(repeating: 1), SIMD3(repeating: 0.18 * f)) }
            sum += col * Float(w); wsum += w
        }
        return wsum > 1e-12 ? sum / Float(wsum) : rain(p.w)
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

    /// 球層の組：レインボーは w の 1 組。4 方向・軸の色は x・y・z・w の 4 組（左は z を落とした x・y・z(w) の 3 組）。
    ///   k は囲む軸（0 x・1 y・2 z・3 w）。軸の色：その軸の色で、赤道に近い層ほど明るく
    func shellFams(left: Bool) -> [(k: Int, list: [(r: Double, w: Double, col: SIMD3<Float>)])] {
        let m = st.shellModeNow, L = layerList()
        guard m == 1 || m == 2 else { return [(3, L)] }
        return (left ? [3, 0, 1] : [3, 0, 1, 2]).map { k in
            (k, m == 1 ? L : L.map { e in
                let f = Float(1 - abs(e.w) / Self.R), c = Self.axisCol[k]
                return (e.r, e.w, simd_mix(c * (0.55 + 0.45 * f), SIMD3(repeating: 1), SIMD3(repeating: 0.18 * f)))
            })
        }
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
        tris = []; glass = []; lines = []; ranges = []; leftRings = []; rings = []
        let M = matrix_identity_double3x3, R = Self.R, cs = cos(st.zw)
        let n = max(2, st.layers), tube = n > 31 ? 0.008 : 0.02
        let sn = sin(st.zw), lzw = st.lzw
        for (k, list) in shellFams(left: true) where k != 3 {          // x・y の軸のまわりの輪（Z-W は w の組だけに効かせる）
            for (r, w, col) in list { rings.append(HLRing(a: SIMD4(Float(r), Float(w), Float(tube), k == 0 ? 1 : 2), c: SIMD4(col, 1))) }
        }
        let wList = shellFams(left: true)[0].list
        for (r, w, col) in wList {
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
            rings.append(HLRing(a: SIMD4(Float(rho), Float(h), Float(tube), 0), c: SIMD4(col, 1)))   // 細い管（トーラス）は GPU で組み立てる
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
    /// 地図の構図（全体像だけの向き）：ダイブの間、ときどき w 軸を横にして球層の重なりを見せ、赤い玉・紫の玉を通る時は w 軸に沿って正面から（今の玉の真後ろにもう 1 つが隠れる）
    private var ovAng: SIMD4<Double>? = nil, ovCur: SIMD4<Double>? = nil, ovVel = SIMD4<Double>(0, 0, 0, 0), ovDrift = 0.0, ovLast = -9.0, ovCutK = 0.0, ovCutLast = -99.0, ovSpd = 0.0, ovDist0: Double? = nil
    private var ovLogT = -9.0
    private var ovBallT = -99.0
    private func tickOvShot() {
        guard overview, ovMotion, st.ovShow, st.diveT > 0.3, let w = (wsrc)?() else { ovAng = nil; ovCur = nil; ovVel = .zero; ovCutK = 0; ovDist0 = nil; return }
        let now = nowT, dt = max(0, min(0.1, now - ovLast)); ovLast = now
        let cur0 = SIMD4(st.zw, st.yaw, st.pitch, st.roll)
        var cur = ovCur ?? cur0
        func toPole(_ p: SIMD4<Double>) -> Double { acos(min(1, abs(p.w) / max(1e-9, simd_length(p)))) }
        // 赤玉と紫玉の交差が主役：回すのに時間がかかるので、彗星の速さから逆算して、早めに動き出す（8 秒先に玉を通るなら重ねる向きへ、16 秒先なら横から）
        if let d0 = ovDist0, dt > 0 { ovSpd += (max(0, w.dist - d0) / dt - ovSpd) * (1 - exp(-dt * 2)) }
        ovDist0 = w.dist
        func within(_ sec: Double) -> Bool {
            let n = min(w.plan.count, Int(ovSpd * sec / 0.02) + 20)
            for i in stride(from: 0, to: n, by: 3) where toPole(w.plan[i]) < 0.3 { return true }
            return false
        }
        let ball = toPole(w.pos) < 0.42 || within(8), soon = within(16), rr = simd_length(walkPlace(w.pos).0) / (Self.R * Self.SCALE)
        var target = cur0
        if ball { ovBallT = now }
        // 断面：外の殻に隠れていた赤玉と紫玉を見せる
        let open: Double = abs(sin(cur.z)) < 0.72 ? 1 : 0                // 回転の角度で判断：赤と紫が重なる向き（0°・180°）に近づいたら、すかさず開く（約 0.3 秒）。離れたらゆっくり閉じる
        ovCutK += (open - ovCutK) * (1 - exp(-dt * (open > 0 ? 4 : 1)))
        if ovCutK < 0.002 { ovCutK = 0 }
        // 向きは Y-W 面の回転 1 つだけ：自分の w の高さで決まる。アナ極で 0°（赤玉が手前、紫玉が真後ろ）、赤道で 90°（球層が真横）、カタ極で 180°（紫玉が手前、赤玉が真後ろ）
        let py = acos(max(-1, min(1, w.pos.w / max(1e-9, simd_length(w.pos)))))
        target = SIMD4(0, 0, py, 0.22 * sin(py))
        // ばねで動かす：ゆっくり動き出して、ゆっくり止まる（加速度がついて、雄大に）。速さに上限（1 秒に約 15°）
        let om = 0.38
        for k in 0..<4 {
            let d = HyperLabState.norm(target[k] - cur[k])
            ovVel[k] += (om * om * d - 2 * om * ovVel[k]) * dt
            ovVel[k] = max(-0.26, min(0.26, ovVel[k]))
            cur[k] = HyperLabState.norm(cur[k] + ovVel[k] * dt)
        }
        ovCur = cur
        ovDrift = HyperLabState.norm(ovDrift + dt * 0.045)                // いつもゆっくり回っている（2 分あまりで 1 周）
        ovAng = cur + SIMD4(0, ovDrift, 0, 0)
        if Self.glintLog && now - ovLogT >= 3 { ovLogT = now; print(String(format: "地図 %.0f 秒 w %+.2f 目標 %.2f 今 %.2f 回 %.2f 面内 %.2f 全 %.2f", now, w.pos.w, target[2], cur[2], cur[3], cur[1], cur[0])) }
    }
    /// 上の地図（車のナビ）：自分がいつも真ん中で、背景が動く。自分のいる所を 4 次元の手前（w）へ、進む向きを画面の上（y）へ、右を右（x）へ写す。
    ///   ダイブの間だけ。曲がる時に背景がぱっと回らないよう、向きは少しならす
    private var naviM: simd_double4x4? = nil, naviR = SIMD4<Double>(0, 0, 0, 0), naviF = SIMD4<Double>(0, 0, 0, 0), naviU = SIMD4<Double>(0, 0, 0, 0), naviLast = -9.0, naviBall = 0.0
    private func tickNavi() {
        guard overview, !ovMotion, st.naviCenter, st.diveT > 0.3, let w = (wsrc)?(), simd_length(w.vL) > 0.5, simd_length(w.vR) > 0.5 else { naviM = nil; naviBall = 0; return }
        let now = nowT, dt = max(0, min(0.1, now - naviLast)); naviLast = now
        let p = simd_normalize(w.pos), f0 = simd_length(w.fwd) > 0.5 ? w.fwd : w.vL
        if naviM == nil { naviR = w.vR; naviF = f0; naviU = w.vU }
        let k = 1 - exp(-dt * 3)
        naviF += (f0 - naviF) * k; naviR += (w.vR - naviR) * k; naviU += (w.vU - naviU) * k
        // 今いる所に接する向きへ直して、たがいに直交させる
        func clean(_ v: SIMD4<Double>, _ o: [SIMD4<Double>]) -> SIMD4<Double> { var t = v; for q in o { t -= q * simd_dot(t, q) }; let l = simd_length(t); return l < 1e-9 ? v : t / l }
        naviF = clean(naviF, [p]); naviR = clean(naviR, [p, naviF]); naviU = clean(naviU, [p, naviF, naviR])
        naviM = simd_double4x4(rows: [naviR, naviF, naviU, p])
        // 赤玉・紫玉のそばを通る間だけ、間の殻を透かす（交わる所が見える）。さっと透けて、ゆっくり戻る
        let toBall = acos(min(1, abs(p.w))), want: Double = toBall < 0.62 ? 1 : 0
        naviBall += (want - naviBall) * (1 - exp(-dt * (want > 0 ? 3.5 : 1.2)))
    }
    func xf(_ v0: SIMD4<Double>) -> SIMD4<Double> {
        if let m = naviM { return m * v0 }
        var v = v0
        let g = ovAng ?? SIMD4(st.zw, st.yaw, st.pitch, st.roll)
        for (i, j, a) in [(2, 3, g[0]), (0, 1, g[1]), (1, 3, g[2]), (0, 3, -g[3])] where a != 0 {
            let c = cos(a), s = sin(a), t = v[i] * c - v[j] * s
            v[j] = v[i] * s + v[j] * c; v[i] = t
        }
        return v
    }
    func buildRight() {
        tris = []; glass = []; lines = []; ranges = []
        let n = max(2, st.layers), MESH0 = n > 61 ? 12 : n > 31 ? 16 : 24
        // 網目の線はウェブ版と同じ本数（MESH0）。面と線の曲がりは 2 倍に細かく（輪郭がカクカク・ギザギザしないよう）。4 方向・軸の色は殻が 4 倍なので 2 倍まで
        let SUB = shellFams(left: false).count > 1 ? 2 : 4, M = MESH0 * SUB, M1 = M + 1, per = M1 * M1   // 光を頂点で計算するので、網目は 4 倍に細かく（照り返しがなめらか）
        rMesh = M
        let fams = shellFams(left: false)
        let L = fams.flatMap { $0.list }
        // 元の 4D の点（網目の並びは three.js の SphereGeometry と同じ：極が上下＝y、地球儀のように緯線が横に並ぶ。ウェブ版と同じ見た目）
        var base = [SIMD4<Float>](); base.reserveCapacity(L.count * per)
        for (k, list) in fams { for (r, w, _) in list { for i in 0...M { let th = Double(i) / Double(M) * .pi; for j in 0...M {
            let ph = Double(j) / Double(M) * 2 * .pi
            var v = SIMD4<Float>(Float(-r * sin(th) * cos(ph)), Float(r * cos(th)), Float(r * sin(th) * sin(ph)), Float(w))
            if k != 3 { let s = v[k]; v[k] = v[3]; v[3] = s }            // 軸 k ＝ 一定の殻（w と入れかえる）
            base.append(v)
        } } } }
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
        let thin: Float = fams.count > 1 ? (st.shellModeNow == 1 ? 0.45 : 0.6) : 1   // 4 組重なるので 1 枚ずつ薄く（白っぽく埋まらないように）
        // 4 方向レインボー：極に近い殻（赤・紫など）ほど濃く、赤道に近い殻ほど薄く。描く順も、極に近い殻をあとに（上に重ねる）。
        //   真ん中の緑・水色に埋もれず、極の色が前に浮き出る（殻の形と場所はそのまま）
        func poleK(_ w: Double) -> Double { smoothstep(0.1, 0.9, abs(w) / Self.R) }
        let four = fams.count > 1 && st.shellModeNow == 1
        let cols = L.map { SIMD4<Float>($0.col, four ? thin * Float(0.2 + 1.7 * poleK($0.w)) : thin) }
        if four { ranges = ranges.indices.sorted { poleK(L[$0].w) < poleK(L[$1].w) }.map { ranges[$0] } }
        rBase = base.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rCol = cols.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(16, $0.count), options: .storageModeShared) }
        rIdx = idx.isEmpty ? nil : idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    // ---- 描く ----
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    // 確かめ用（環境変数 S3_HL_LOG）：1 秒ごとに、描く間隔の最大・描く処理の時間（CPU）の平均と最大
    static let logOn = ProcessInfo.processInfo.environment["S3_HL_LOG"] != nil
    private var lgN = 0, lgCPU = 0.0, lgMaxCPU = 0.0, lgMaxGap = 0.0, lgT = 0.0, lgLong = 0
    /// 音：彗星（今いる所）の S³ の上の速さ（ラジアン／秒）をならして、シューの大きさ・高さへ。当たった瞬間にチリン
    private var sndWobT = 0.0                                         // 前に低音をゆらした時刻
    private var sndIceT = 0.0                                          // 前にシュパッを鳴らした時刻
    private var sndPos: SIMD4<Double>?, sndSpeed = 0.0, sndFwd: SIMD4<Double>?, sndTurn = 0.0, sndPulseT = ProcessInfo.processInfo.systemUptime
    /// オートカメラ：ゆっくり周りを漂う（40 秒・27 秒の波）＋曲がる時は外側へ回り込む（曲がる道すじと尾が見えるように）。ズーム中だけ
    private var acFwd: SIMD4<Double>?, acTurn = 0.0, acTurnU = 0.0, acVert = 0.0
    /// 彗星の速さ（S³ の上で 1 秒に進む角度をならして、0〜1 に）
    private var csPos: SIMD4<Double>?
    private func tickCometSpeed(_ dt: Double) {
        guard let w = wsrc?() else { return }
        var v = 0.0
        if let p0 = csPos, dt > 0 { let d = simd_length(w.pos - p0); v = d > 0.5 ? 0 : d / dt }
        csPos = w.pos
        let target = min(1, (v / 1.4).squareRoot())
        st.cometSpd += (target - st.cometSpd) * (1 - exp(-dt * 3))
    }
    /// 確かめ用：オートカメラだけを 1 コマ進める
    func autoCamForTest(_ dt: Double) { tickAutoCam(dt) }
    /// 確かめ用：おくれて追うカメラを 1 コマ進めて、彗星が先へ出た分（画面の横・縦）とカメラの傾き
    func chaseForTest(_ dt: Double) -> (SIMD3<Double>, Double, Double) { if let w = wsrc?() { _ = lagFrame(w, 1, step: dt) }; return (leadOff, bank, simd_length(headWarp)) }
    /// ダイブのカメラをコントローラーで：三人称で寄っている間、選んだスティックで自分（彗星）のまわりを回す（左右・上下。離すとゆっくり元の角度へ）。
    ///   オートカメラは止めず、その上に足す（オートカメラの動きを、さらに手で操れる）。
    ///   そのスティックは、さんぽで歩くのには使わない
    private func tickPadCam(_ dt: Double) {
        let wr = HyperLabState.walkRendererGet?()
        if HyperLabState.opModeNow != st.opMode { HyperLabState.opModeNow = st.opMode }
        let on = st.padCam && !st.opMode && st.diveThird && st.diveT > 0.3 && wr != nil   // 操作モードの間は、スティックはみんな歩くのに使う
        let mask = on ? [1, 2, 3][max(0, min(2, st.padCamStick))] : 0
        if wr?.padCamMask != mask { wr?.padCamMask = mask }
        guard on, let g = wr?.game.sticks() else { st.padHolding = false; return }
        var v = SIMD2<Double>(0, 0)
        if mask & 1 != 0 { v += g.left }; if mask & 2 != 0 { v += g.right }
        let held = simd_length(v) > 0.02
        if held {
            st.diveYawOff += v.x * 1.9 * dt * (st.diveT > 0.65 ? 1 : -1)
            st.divePitchOff = max(-1.4, min(1.4, st.divePitchOff - v.y * 1.4 * dt))
        }
        st.padHolding = held
    }
    private func tickAutoCam(_ dt0: Double) {
        let dt = min(0.1, max(0, dt0))                                     // コマがつかえた時も、カメラが飛ばない
        tickPadCam(dt)
        var ty = 0.0, tp = 0.0
        if st.autoCam && st.diveT > 0.3 && !st.camHeld {
            st.autoT += dt
            var tr = 0.0, tu = 0.0, vert = 0.0
            if let w = (wsrc)?() {
                let hd = w.head ?? w.fwd
                if let f0 = acFwd, dt > 0, simd_length(w.vR) > 0.5 {
                    let df = hd - f0
                    // 左右に曲がる速さ・上下に曲がる速さ（コマの間隔が不ぞろいでも荒れないよう、1/60 秒より短い間隔では割らない）
                    let dd = max(dt, 1.0 / 60)
                    if simd_length(df) < 0.5 { tr = simd_dot(df, w.vR) / dd; tu = simd_dot(df, w.vU) / dd }
                }
                if simd_length(w.vU) > 0.5 { vert = simd_dot(hd, w.vU) }    // 進む向きの上下の成分（垂直に近いほど ±1）
                acFwd = hd
            }
            acTurn += (tr - acTurn) * (1 - exp(-dt * 1.5)); acTurnU += (tu - acTurnU) * (1 - exp(-dt * 1.5)); acVert += (vert - acVert) * (1 - exp(-dt * 2))
            let a = st.autoT
            ty = 0.6 * sin(2 * .pi * a / 40) - 0.45 * max(-1, min(1, acTurn / 1.2))   // 右へ曲がると左（外側）へ回り込む
            tp = 0.18 * sin(2 * .pi * a / 27 + 1)
            // ダイナミック：きついカーブ・垂直に近い動きの時は、水平の目線から真上近くの目線へ大きく展開（曲がる道すじ全体が見えるように）
            let sharp = min(1, (acTurn * acTurn + acTurnU * acTurnU).squareRoot() / 1.1), vertical = smoothstep(0.35, 0.85, abs(acVert))
            let dyn = max(sharp, vertical)
            st.autoDyn = dyn
            tp += 1.05 * dyn * (1 - 0.18 * sin(2 * .pi * a / 27 + 1))           // 最大およそ 60°、見下ろしを足す
            ty *= 1 - 0.5 * dyn                                               // 真上へ回る間は左右の回り込みを控えめに
            if st.camShow { let (sy, sp, sd, sr) = showShot(dt); ty = sy; tp = sp; showDistT = sd; showRollT = sr } else { showRollT = 0 }
            // 予定の道を全部出している時は、長い矢印の鎖が画面を大きく横切るので、傾き・ずらしを半分に（カメラが荒ぶって見えない）
            if st.planLong { showRollT *= 0.5; showFrameT *= 0.5; ty *= 0.7 }
        } else { showDistT = 1; showRollT = 0; showIdx = 0; showT = 0 }
        // 視点の切りかえは、ばねで S 字に動かす（ゆっくり動き出して、途中で速く、着く前にまたゆっくり。急に向きが変わった感じにしない）
        func spring(_ x: inout Double, _ v: inout Double, _ to: Double, _ w: Double) {
            let n = max(1, Int(ceil(dt / 0.01))), h = dt / Double(n)
            for _ in 0..<n { v += (w * w * (to - x) - 2 * w * v) * h; x += v * h }
        }
        spring(&st.showDist, &sdV, showDistT, 1.3)
        if !(st.camShow && st.autoCam && st.diveT > 0.3 && !st.camHeld) { showFrameT = .zero }
        spring(&st.showFrame.x, &sfV.x, showFrameT.x, 1.3); spring(&st.showFrame.y, &sfV.y, showFrameT.y, 1.3)
        // 展開する時は少し速く（約 1 秒）、戻る時はゆっくり（約 3 秒）
        let up = tp > st.autoPitch && st.autoDyn > 0.2
        let fast = st.camShow && st.autoCam                               // ショーカメラは、ゆっくり回り込む（切りかえに 2〜3 秒。落ち着いた動き）
        let k = 1 - exp(-dt * (fast ? 0.55 : 0.6)), kp = 1 - exp(-dt * (fast ? 0.55 : up ? 1.1 : 0.35))
        _ = k; _ = kp
        // 四元数のカメラ：左右・上下・傾きを 1 つの回転（四元数）にまとめて、ばねで追いかける。
        //   いつもいちばん近い回り方で、きれいな弧を描いて回り込む（左右を別々に追うと遠回りしたり、真上の近くでロックしたようにガクッと回ったりした）。
        //   向きの組み立て：左右（y 軸）→ 上下（x 軸）→ 傾き（z 軸）。追いかけた四元数を同じ組み立ての角度に戻して、カメラへ渡す
        let rollT = showRollT * 0.6                                           // 傾きは控えめに（ショーカメラ以外は 0）
        func qOf(_ y: Double, _ p: Double, _ rl: Double) -> simd_quatd {
            simd_quatd(angle: y, axis: SIMD3(0, 1, 0)) * simd_quatd(angle: p, axis: SIMD3(1, 0, 0)) * simd_quatd(angle: rl, axis: SIMD3(0, 0, 1))
        }
        var qT = qOf(ty, tp, rollT)
        if simd_dot(qT.vector, camQ.vector) < 0 { qT = simd_quatd(vector: -qT.vector) }
        let wq = up ? 1.9 : fast ? 1.25 : 1.0                                // 展開（見下ろしへ開く）は少し速く、ほかはゆっくり（約 3 秒で弧を描いて着く）
        let nq = max(1, Int(ceil(dt / 0.01))), hq = dt / Double(nq)
        for _ in 0..<nq {
            var e = qT * camQ.inverse; if e.real < 0 { e = simd_quatd(vector: -e.vector) }
            let ang = e.angle, ev = ang > 1e-9 ? e.axis * ang : SIMD3<Double>(0, 0, 0)
            camW += (wq * wq * ev - 2 * wq * camW) * hq                         // 回転のずれへ向かうばね（行き過ぎない）
            let wl = simd_length(camW)
            if wl > 1e-12 { camQ = simd_normalize(simd_quatd(angle: wl * hq, axis: camW / wl) * camQ) }
        }
        let mq = simd_matrix3x3(camQ), c3 = mq.columns.2
        st.autoPitch = asin(max(-1, min(1, -c3.y))); st.autoYaw = atan2(c3.x, c3.z); st.showRoll = atan2(mq.columns.0.y, mq.columns.1.y)
        if abs(st.autoYaw) < 1e-5 && ty == 0 { st.autoYaw = 0 }; if abs(st.autoPitch) < 1e-5 && tp == 0 { st.autoPitch = 0 }
    }
    /// ショーカメラ：カーブが近い（予定の道で 0.7 以内に、1 歩 0.02 で 0.7° より大きく曲がる所がある）か曲がっている間は、真後ろの低い所から
    ///   （ターンを後ろから見せる。曲がり終えて 1 秒は続ける）。まっすぐな所は 4.5 秒ごとに：斜め右上（傾ける）→ 右の真横 → 真上の近く → 斜め左上（傾ける）→ 左の真横 → 高く引いた全体 → 低い斜め後ろ → 後ろ。
    ///   返り値は、オートカメラの左右・見下ろしの目標（三人称の基本の角度からのずれ）と、距離の倍率
    private var showIdx = 0, showT = 0.0, showHold = 0.0, showDistT = 1.0, showRollT = 0.0, showFrameT = SIMD2<Double>(0, 0)
    // 演出 AI の覚え：先回りしている構図・そのカーブの種類・抜けてから戻るまで・最近使った構図
    private var sdV = 0.0, sfV = SIMD2<Double>(0, 0)                       // 視点のばねの速さ（距離・彗星の置き場所）
    private var camQ = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), camW = SIMD3<Double>(0, 0, 0)   // 四元数のカメラ：今の向きと、回る速さ（角速度）
    private var aiShot: (Double, Double, Double, Double, Double, Double)? = nil, aiKey = -99, aiHold = 0.0, aiHist: [Int] = []
    /// 演出 AI（ジェットコースター）：予定の道の先の落ち込み・昇り・急カーブを読み、先回りして構える。
    ///   落ち込みでは、カメラが前の高い所へゆっくり舞い上がり、向かってくる彗星を見下ろす（彗星はカメラの下へ落ちていく）。抜けたら少しして後ろへ戻る。
    ///   マンネリにならないよう、最近使った 3 つは選ばず、角度・距離に毎回少し揺らぎを入れ、4 回に 1 回はあえて先回りしない
    private func aiDirector(_ dt: Double) -> (Double, Double, Double, Double, Double, Double)? {
        // 赤い玉（アナ極）・紫の玉（カタ極）を通る時：真後ろから傾けずに、玉へまっすぐ向かう（彗星が玉に入っていくのが正面からわかる）。通り抜けたら、いつもの動きへ
        if let w = (wsrc)?() {
            func toPole(_ p: SIMD4<Double>) -> Double { acos(min(1, abs(p.w) / max(1e-9, simd_length(p)))) }
            let here = toPole(w.pos)
            var next = here
            for i in stride(from: 0, to: min(w.plan.count, 45), by: 3) { next = min(next, toPole(w.plan[i])) }
            if here < 0.42 || next < 0.3 {
                aiShot = nil; aiKey = -99; aiHold = 0
                return (0, 0.14, 1.2, 0, 0, 0)
            }
        }
        var ahead: (cat: Int, sg: Double)? = nil
        if let w = (wsrc)?(), w.plan.count >= 3 {
            let pl = w.plan
            for i in 1..<min(pl.count - 1, 46) {
                guard Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.03 else { continue }   // 1 歩（0.02）で 1.7° より急
                let p = simd_normalize(pl[i]); var bend = (pl[i + 1] - pl[i]) - (pl[i] - pl[i - 1]); bend -= p * simd_dot(bend, p)
                let lr = simd_dot(bend, w.vR), ud = simd_dot(bend, w.vU)
                ahead = abs(ud) > abs(lr) * 0.8 ? (ud < 0 ? 0 : 1, 1) : (2, lr >= 0 ? 1 : -1)   // 0 落ち込み・1 昇り・2 左右（sg ＋右）
                break
            }
        }
        // (左右（0 真後ろ・±π 真正面）、見下ろし、距離、傾き、彗星の横の置き場所、縦の置き場所)
        func shots(_ cat: Int, _ sg: Double) -> [(Double, Double, Double, Double, Double, Double)] {
            let s2: Double = Bool.random() ? 1 : -1
            switch cat {
            case 0: return [(2.4 * s2, 0.85, 1.5, 0.08 * s2, 0, -0.12),   // 先回り：前の高い所から、向かってくる彗星を見下ろす（下へ落ちていく）
                            (0.25, 1.1, 1.6, 0, 0, -0.15),                  // 真後ろの高い所から、落ちていく深さ
                            (1.4 * s2, 0.65, 1.5, 0.1 * s2, 0, -0.1)]       // 横の高い所から、落ちていく高低差
            case 1: return [(2.5 * s2, -0.35, 1.3, 0.06 * s2, 0, 0.18),  // 前の低い所から、昇ってくる彗星を見上げる
                            (1.3 * s2, 0.1, 1.6, 0, 0, 0)]                  // 真横から、高さの変わり方
            default: return [(-1.0 * sg, 0.5, 1.4, 0.12 * sg, 0, 0),       // カーブの外側の高い所
                             (-0.2 * sg, 0.25, 1.0, 0.18 * sg, 0, 0),       // 真後ろで、曲がる側へ軽く傾けて
                             (0.3 * sg, 1.0, 1.7, 0, 0, 0),                 // 上の引き（曲がる道すじ全体）
                             (-0.4 * sg, 0.3, 1.1, 0.85 * sg, 0, 0)]       // 飛行機の旋回のように、曲がる側へ大きく傾けて
            }
        }
        if let a = ahead {
            aiHold = 1.6
            let key = a.cat * 10 + Int(a.sg)
            if key != aiKey {
                aiKey = key
                let c = shots(a.cat, a.sg)
                let recent = Set(aiHist.suffix(3))
                var pool = c.indices.filter { !recent.contains(a.cat * 100 + $0) }; if pool.isEmpty { pool = Array(c.indices) }
                if Double.random(in: 0..<1) < 0.25 { aiShot = nil }                // あえて先回りしない（いつもの構図のまま）
                else {
                    let i = pool.randomElement()!, b = c[i]; aiHist.append(a.cat * 100 + i); if aiHist.count > 8 { aiHist.removeFirst() }
                    func jit(_ v: Double) -> Double { v * Double.random(in: 0.88...1.12) }
                    aiShot = (jit(b.0), jit(b.1), jit(b.2), jit(b.3), b.4, b.5)
                }
            }
        } else {
            aiHold -= dt
            if aiHold <= 0 { aiShot = nil; aiKey = -99 }
        }
        return aiShot
    }
    private func showShot(_ dt: Double) -> (Double, Double, Double, Double) {
        // 演出 AI が先回りしている時は、その構図（いつもの回し方は止めておく）
        if st.showMode == 1, let a = aiDirector(dt) {
            showFrameT = SIMD2(a.4, a.5); showT = 0
            let mw = smoothstep(0.52, 0.78, st.diveT)
            let baseY = st.chaseYawS * (1 - 2 * mw) * .pi / 180, baseP = st.chasePitchS * .pi / 180
            return (a.0 - baseY, a.1 - baseP, a.2, a.3)
        }
        var curve = abs(acTurn) > 0.35 || abs(acTurnU) > 0.35
        if let w = (wsrc)?(), w.plan.count >= 3 {
            let pl = w.plan
            for i in 1..<min(pl.count - 1, 36) {
                if Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.012 { curve = true; break }
            }
        }
        if curve { showHold = 2.5 } else { showHold -= dt }   // カーブを抜けて 2.5 秒は構えたまま（すぐ切りかわってカクつかない）
        // (左右（0 で真後ろ、＋で右）、見下ろし、距離の倍率)
        // (左右（0 で真後ろ、＋で右）、見下ろし、距離の倍率、傾き)。斜め上からの斜め構え（傾けて迫力）を、真横・真上・引きの間にはさむ
        //   6 つ目：彗星を画面のどこに置くか（横 −左 ＋右、縦 −下 ＋上。カメラの距離の割合）。左上・右上に置く構図、見下ろす構図も
        let shots: [(Double, Double, Double, Double, Double, Double)] = [
            (0, 0.16, 0.8, 0, 0, 0), (0.8, 0.45, 1.1, 0.34, 0, 0), (0.75, -0.42, 1.0, 0.16, -0.2, 0.2), (1.35, 0.22, 1.05, 0.12, 0, 0), (0.25, 1.2, 1.3, 0, 0, 0),
            (-0.8, 0.45, 1.1, -0.34, 0, 0), (-0.75, -0.42, 1.0, -0.16, 0.2, 0.2), (-1.35, 0.22, 1.05, -0.12, 0, 0), (0.55, 0.6, 1.8, 0.2, 0, 0),
            (0.7, 0.05, 0.9, -0.28, 0, 0),   // 見上げる構図（見下ろしがマイナス）：下から仰ぐので、彗星は画面の左上・右上に
            (0.3, 0.5, 3.0, 0, 0, 0), (-0.9, 0.35, 3.4, -0.08, 0, 0), (1.6, 0.8, 2.8, 0.08, 0, 0),   // 大きく引いた全体（まっすぐな所で、ときどき）
            (0.55, 0.2, 1.1, 0.8, 0, 0), (-0.55, 0.2, 1.1, -0.8, 0, 0)]   // 斜めの構図（地平線を大きく傾ける。飛行機の旋回のようにダイナミックに）
        // カーブの時：真後ろの少し斜め（曲がる側の外から）、曲がる側へ傾けて構える。彗星は真ん中
        let tsg: Double = acTurn >= 0 ? 1 : -1
        var shot: (Double, Double, Double, Double, Double, Double) = (-0.35 * tsg, 0.28, 0.85, 0.12 * tsg, 0, 0)
        if showHold > 0 { showT = 0; showIdx = 0 }
        else {
            showT += dt
            // 7 秒ごとに次の構図（忙しくない）。順番ではなくランダムに（同じのが続かない）。大きく引いた全体もときどき入る
            if showT > 7 { showT = 0; var n = Int.random(in: 0..<shots.count); if n == showIdx { n = (n + 1) % shots.count }; showIdx = n }
            shot = shots[showIdx]
        }
        showFrameT = SIMD2(shot.4, shot.5)
        // 三人称の基本の角度（camBasis：左右 chaseYawS ×（1 − 2 × 鏡の広がり）、見下ろし chasePitchS）からのずれにする
        let mw = smoothstep(0.52, 0.78, st.diveT)
        let baseY = st.chaseYawS * (1 - 2 * mw) * .pi / 180, baseP = st.chasePitchS * .pi / 180
        return (shot.0 - baseY, shot.1 - baseP, shot.2, shot.3)   // 置き場所（showFrameT）は別に渡す
    }
    private func tickSound(_ dt: Double) {
        let snd = HyperSound.shared
        guard st.soundOn else { if snd.running { snd.stop() }; return }
        if !snd.running { snd.start(); sndPulseT = ProcessInfo.processInfo.systemUptime }
        var sp = 0.0
        if let w = (wsrc)?() {
            if let p0 = sndPos, dt > 0 { let d = simd_length(w.pos - p0); sp = d > 0.5 ? 0 : d / dt }   // 飛んだ時（初めに戻した時など）は数えない
            sndPos = w.pos
            // 曲がる速さ：進む向きが、右の向き（景色の右）へ毎秒どれだけ変わったか（＋で右へ曲がる）
            var tr = 0.0
            let hd = w.head ?? w.fwd
            if let f0 = sndFwd, dt > 0, simd_length(w.vR) > 0.5 { let df = hd - f0; tr = simd_length(df) > 0.5 ? 0 : simd_dot(df, w.vR) / dt }
            sndFwd = hd
            sndTurn += (tr - sndTurn) * (1 - exp(-dt * 4))
        }
        sndSpeed += (sp - sndSpeed) * (1 - exp(-dt * 6))
        let trn = max(-1, min(1, sndTurn / 1.2))
        // 低音のゆらぎ：きついカーブの時と、走っている間にときどき（不定期に。続けて起きないよう 1.2 秒あける）
        let nowS = ProcessInfo.processInfo.systemUptime, spd01 = min(1, (sndSpeed / 1.4).squareRoot())
        if nowS - sndWobT > 1.2 && spd01 > 0.25 && (abs(trn) > 0.55 || Double.random(in: 0..<1) < dt * 0.12 * spd01) { snd.shellPass(); sndWobT = nowS }
        // シュパッ：ダイブ中、曲がっている時にときどき（カメラが揺れる時と同じころ。続けて鳴らないよう 1.8 秒あける）
        if Self.diveEase(st.diveT).1 > 0.5 && nowS - sndIceT > 1.8 && spd01 > 0.3 && abs(trn) > 0.25 && Double.random(in: 0..<1) < dt * 0.9 * abs(trn) { snd.icePop(); sndIceT = nowS }
        snd.update(speed: (sndSpeed / 1.4).squareRoot(), zoom: Self.diveEase(st.diveT).1, turn: trn, near: st.cometNear, volume: st.soundVol)
        // 空間オーディオ：彗星の方向から。一人称で寄り切った時は自分＝彗星なので、前から。曲がる時は外側の耳へ寄せる
        if snd.spatial != st.soundSpatial { snd.spatial = st.soundSpatial }
        let first = Self.diveEase(st.diveT).1 * (1 - st.thirdK)
        var d = st.cometDir * (1 - first) + SIMD3<Double>(0, 0, -1) * first; d.x -= 0.7 * trn
        let dl = simd_length(d); if dl > 1e-6 { d /= dl }
        snd.setPosition(SIMD3<Float>(d * 1.5))
        for h in Journey.hitPulse where h.t > sndPulseT { snd.chime(pole: h.pole) }
        if let last = Journey.hitPulse.last?.t, last > sndPulseT { sndPulseT = last }
    }
    /// 毎コマの受け持ち（状態を進める・画質の自動・保存など）：ふだんは左の画面。3D の球を隠している時は右の画面
    private var wasIdle = false, offShown = false
    private var owner: Bool { !ovMotion && (side == .left || overview || !st.show3D) }   // 全体像を 3D の球の場所に出している時は、全体像が受け持つ
    func draw(in view: MTKView) {
        let t0 = CACurrentMediaTime()
        if owner { HyperLabState.walkRendererGet?()?.driveIfIdle() }       // さんぽの画面が描かれていない時は、ここから歩く計算を進める
        defer {
            if Self.logOn {
                let c = (CACurrentMediaTime() - t0) * 1000; lgN += 1; lgCPU += c; lgMaxCPU = max(lgMaxCPU, c)
                if t0 - lgT >= 1 { print(String(format: "%@ n %d  CPU 平均 %.2f 最大 %.2f ms  間隔の最大 %.1f ms（12 ms 超 %d 回）  目標 %d", side == .left ? "左" : "右", lgN, lgCPU / Double(max(1, lgN)), lgMaxCPU, lgMaxGap, lgLong, view.preferredFramesPerSecond)); fflush(stdout); lgN = 0; lgLong = 0; lgCPU = 0; lgMaxCPU = 0; lgMaxGap = 0; lgT = t0 }
            }
        }
        if Self.logOn { let g = (t0 - lastT) * 1000; lgMaxGap = max(lgMaxGap, g); if g > 12 { lgLong += 1 } }
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        if VideoExport.shared.rendering && side == .right && !overview { return }   // 動画を書き出している間は、右の画面を止めて（GPU を書き出しに回す）
        #if os(macOS)
        if owner && st.shutAuto {                                        // 前の窓だけ描く：どちらの窓が前（キー）かで、瞬時に切りかえ
            let hk = HyperLabWindow.window?.isKeyWindow ?? false, wk = HyperLabWindow.walkWindow?.isKeyWindow ?? false
            if HyperLabState.walkShut != hk { HyperLabState.walkShut = hk }
            let idle = wk && !hk; if HyperLabState.hyperIdle != idle { HyperLabState.hyperIdle = idle }
        }
        #endif
        if owner { st.tick(dt); st.pullLayers(); st.tickCut(dt); st.tickFollow(dt); st.tickDive(dt); updateLive(now); tickSound(dt); tickAutoCam(dt); tickCometSpeed(dt) }   // 自動の回転・さんぽの層数を読むのは受け持ちの画面（ふだん左。右は同じ状態を描く）
        pace(view, dt)
        Self.fit(view)
        if owner { fpsN += 1; if now - fpsT >= 1 { st.saveIfChanged(); let f = Int((Double(fpsN) / (now - fpsT)).rounded()); fpsN = 0; fpsT = now; DispatchQueue.main.async { [st] in st.stats.text = String(format: "%d fps・GPU %.1f＋%.1f ms・画質 %.0f%%", f, st.gpuL, st.gpuR, HyperLabState.renderK * 100) } } }
        // 前の窓だけ描く（自動）で、さんぽの窓が前の時：この窓の画面はオフ（真っ暗を 1 回だけ出して、あとは描かない）
        if HyperLabState.hyperIdle {
            if !offShown, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() {
                let rp = MTLRenderPassDescriptor()
                rp.colorAttachments[0].texture = dr.texture; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
                rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding(); cb.present(dr); cb.commit(); offShown = true
            }
            return
        }
        offShown = false
        if side == .left {
            guard let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
            renderLeft(cb, into: dr.texture); timeGPU(cb); cb.present(dr); cb.commit(); return
        }
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        if dvT > 0 {
            // ダイブの間：マルチサンプルの絵を別の絵（mirTex）にまとめてから、鏡を広げて画面へ
            let W = dr.texture.width, H = dr.texture.height
            if mirTex == nil || mirTex!.width != W || mirTex!.height != H {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; mirTex = device.makeTexture(descriptor: d)
            }
            guard let mt = mirTex else { return }
            rpd.colorAttachments[0].resolveTexture = mt
            guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
            encode(e, view.drawableSize); e.endEncoding()
            mirrorPass(cb, mt, dr.texture)
        } else {
            mirTex = nil
            guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
            encode(e, view.drawableSize); e.endEncoding()
        }
        timeGPU(cb); cb.present(dr); cb.commit()
        if !overview && side == .right { Self.liveMain = self; Self.liveRightW = Double(view.bounds.width) }   // 右の画面の幅（点）：書き出しの文字を画面と同じ割合にする
        if (VideoExport.shared.recording || VideoExport.shared.keepLast || VideoExport.shared.armed) && !overview, let f = recordFrame() { VideoExport.shared.capture(f) }   // 記録している間・直前 1 分を覚える間：この画面の動きを 1 コマずつ覚える（描き直すのは止めたあと）
    }
    // ---- 動画の書き出し：16:9（1920×1080）で画面の裏でもう一度描く。ダイブ中は左上に小さく全体像の地図 ----
    private var exMS: MTLTexture?, exDep: MTLTexture?, exOut: MTLTexture?, exCache: CVMetalTextureCache?, exOverview: HyperLabRenderer?, exOverview2: HyperLabRenderer?, exGlass: InsetGlass?
    private func exAlloc(_ w: Int, _ h: Int) {
        guard exMS?.width != w || exMS?.height != h else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; exOut = device.makeTexture(descriptor: d)
        d.textureType = .type2DMultisample; d.sampleCount = 4; exMS = device.makeTexture(descriptor: d)
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = [.renderTarget]; dd.storageMode = .private; dd.textureType = .type2DMultisample; dd.sampleCount = 4; exDep = device.makeTexture(descriptor: dd)
    }
    private func exPass(_ cb: MTLCommandBuffer, _ resolve: MTLTexture, _ w: Int, _ h: Int) -> Bool {
        guard let ms = exMS, let dep = exDep else { return false }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = resolve
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        rp.depthAttachment.texture = dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return false }
        encode(e, CGSize(width: w, height: h)); e.endEncoding(); return true
    }
    /// 書き出しの 1 コマ：dst（w×h）へ描く（ダイブ中は鏡を広げ、左上に小さくガラスの窓の地図）。いつも最高の細かさ
    func renderExport(_ cb: MTLCommandBuffer, into dst: MTLTexture, w: Int, h: Int, withMap: Bool) -> Bool {
        renderKOverride = 1
        exAlloc(w, h)
        guard let mid = exOut, exPass(cb, dvT > 0 ? mid : dst, w, h) else { return false }
        if dvT > 0 { mirrorPass(cb, mid, dst) }                             // ダイブ：鏡を広げて（画面と同じ）
        if dvT > 0.3 && withMap {
            if exOverview == nil { exOverview = HyperLabRenderer(side: .right, state: st, view: nil); exOverview?.overview = true }
            if exGlass == nil { exGlass = InsetGlass(device) }
            if let ov = exOverview {
                ov.walkOverride = walkOverride; ov.clockOverride = clockOverride; ov.domOverride = domOverride; ov.renderKOverride = 1
                let iw = w / 4, ih = h / 4
                if let img = ov.renderInsetTexture(cb, iw, ih) { exGlass?.draw(cb, img, into: dst, x: w / 60, y: w / 60, w: iw, h: ih) }
            }
        }
        return true
    }
    /// 記録の 1 コマ：その時の動き（カメラ・ダイブ・彗星の場所・道・跡・拍）
    func recordFrame() -> VideoExport.RecFrame? {
        guard side == .right, let w = (wsrc)?() else { return nil }
        let now = CACurrentMediaTime(), raw = HyperLabState.walkSource?()
        return VideoExport.RecFrame(t: now, dom: Self.domClock(now), walk: w, rawTrail: raw?.trail ?? w.trail,
            f: [st.diveT, st.diveFade, st.thirdK, st.chaseDistS, st.chasePitchS, st.chaseYawS, st.autoYaw, st.autoPitch, st.autoT, st.autoDyn,
                st.showDist, st.showRoll, st.diveYawOff, st.divePitchOff, st.cometSpd, st.cometNear, st.zw, st.pitch, st.roll, st.yaw,
                st.viewYaw, st.viewPitch, st.viewDist, st.camW, st.cutPos, st.cutPhi],
            cometDir: st.cometDir, showFrame: st.showFrame, layers: st.layers, lzw: st.lzw, version: st.version,
            diveOn: st.diveOn, dragging: st.diveDragging, padHolding: st.padHolding, walkCam: HyperLabState.walkRendererGet?()?.cam)
    }
    /// 書き出し：ダイブ画面を描く入れ物（レイアウトの右の大きな所）
    private var exPaneTex: MTLTexture?
    func paneTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        if let t = exPaneTex, t.width == w, t.height == h { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; exPaneTex = device.makeTexture(descriptor: d); return exPaneTex
    }
    /// 書き出し：外から見た超球の全体像（地図）を w×h に描いた絵（黒地のまま）
    func overviewTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int, motion: Bool = false) -> MTLTexture? {
        if exOverview == nil { exOverview = HyperLabRenderer(side: .right, state: st, view: nil); exOverview?.overview = true }
        if motion && exOverview2 == nil { exOverview2 = HyperLabRenderer(side: .right, state: st, view: nil); exOverview2?.overview = true; exOverview2?.ovMotion = true }
        guard let ov = motion ? exOverview2 : exOverview else { return nil }
        ov.walkOverride = walkOverride; ov.clockOverride = clockOverride; ov.domOverride = domOverride; ov.renderKOverride = 1
        return ov.renderInsetTexture(cb, w, h)
    }
    /// 書き出し：さんぽの景色を、記録したさんぽのカメラで w×h に描いた絵（さんぽの窓と同じ描き方。カメラは描く間だけ借りて戻す）
    private var exWalkTex: MTLTexture?
    func walkSceneTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int, cam: Camera?) -> MTLTexture? {
        guard let wr = VideoExport.shared.gen ?? HyperLabState.walkRendererGet?() else { return nil }   // 決まった道から作る時は、裏で歩くさんぽで
        if exWalkTex?.width != w || exWalkTex?.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; exWalkTex = device.makeTexture(descriptor: d)
        }
        guard let t = exWalkTex else { return nil }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        let saved = wr.cam
        if let cam { wr.cam = cam }
        wr.encode(cb, rp, .rgba16Float, w, h)
        wr.cam = saved
        return t
    }
    /// 書き出しの左上の小さな地図：小さく描いた絵を返す（重ねるのは InsetGlass）
    func renderInsetTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int) -> MTLTexture? {
        exAlloc(w, h)
        guard let out = exOut, exPass(cb, out, w, h) else { return nil }
        return out
    }
    private var liveT = 0.0
    /// 角度の読みを 0.5 秒ごとに（変わった時だけ。表示を変えるたびに窓の並べ直しが走るので、少なめに）
    private var coordT = 0.0, coordP: SIMD4<Double>?, coordSpd = 0.0
    private func updateLive(_ now: Double) {
        // 走行中の座標（1 秒に 10 回）：S³ の上の x・y・z・w、アナ極からの角度、いちばん近い極、速さ（1 秒に進む角度）
        if now - coordT >= 0.1 {
            var cs = ""
            if st.coordOn && st.walk, let w = (wsrc)?() {
                let p = w.pos, en = st.poleEN, dtc = now - coordT
                if let p0 = coordP, dtc > 0 && dtc < 1 { let v = acos(max(-1, min(1, simd_dot(p, p0)))) / dtc; coordSpd += (v - coordSpd) * 0.35 }
                coordP = p
                let ana = acos(max(-1, min(1, p.w))) * 180 / .pi
                var bk = 0, bd = 9.0
                for (k, m) in FIXED.enumerated() { let d = acos(max(-1, min(1, simd_dot(p, m.c)))); if d < bd { bd = d; bk = k } }
                let pn = en ? MapRenderer.poleNameToEN(MapRenderer.poleName(FIXED[bk])) : MapRenderer.poleName(FIXED[bk])
                func f(_ v: Double) -> String { String(format: "%@%.3f", v < 0 ? "−" : "+", abs(v)) }
                cs = "S³  x \(f(p.x))  y \(f(p.y))  z \(f(p.z))  w \(f(p.w))\n"
                   + (en ? String(format: "from Ana %6.1f°   near %@ %5.1f°   v %.2f rad/s", ana, pn, bd * 180 / .pi, coordSpd)
                         : String(format: "アナ極から %6.1f°   近い極 %@ %5.1f°   速さ %.2f rad/s", ana, pn, bd * 180 / .pi, coordSpd))
            } else { coordP = nil }
            coordT = now
            if cs != st.live.coords { st.live.coords = cs }
        }
        guard now - liveT >= 0.5 else { return }
        liveT = now
        let s = String(format: "前後（Y-W）%+.0f°　左右（X-W）%+.0f°　面内（X-Y）%+.0f°　Z-W %+.0f°", st.pitch * 180 / .pi, -st.roll * 180 / .pi, st.yaw * 180 / .pi, st.zw * 180 / .pi)
        if s != st.live.angles { st.live.angles = s }
        // 周回：目印が 2 つ以上ある時は目印で、なければ 8 つの極で数える（英語モードは Lap n）
        var lp = ""
        if let w = (wsrc)?(), (st.marksOn && w.marks.count >= 2) || (w.marks.count < 2 && st.polesMode > 0) || w.lap > 1 {
            lp = st.poleEN ? "Lap \(w.lap)" : "\(w.lap) 周目"
        }
        if lp != st.live.lap { st.live.lap = lp }
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
        #if os(macOS)
        // 窓のある画面のいちばん速いコマ数に合わせる（外の 144 Hz の画面から MacBook の 120 Hz の画面へ移った時など）。
        //   全部の画面のいちばん速い値（144）のままだと、120 Hz の画面で 144 を目指して届かず「遅い」と判断し、
        //   画質を下げ、コマ数も 144 の半分の 72（120 Hz を割り切れない）にして、カクカクになる
        if let hz = view.window?.screen?.maximumFramesPerSecond, hz > 0, hz != maxFPS {
            maxFPS = hz; moveFPS = hz; pN = 0; pT = 0; slowS = 0; fastS = 0
            if owner && s.quality == 0 { HyperLabState.renderK = 1 }
            if !lowFPS { view.preferredFramesPerSecond = hz }
        }
        #endif
        var sig: [Double] = [s.pitch, s.roll, s.yaw, s.zw, s.viewYaw, s.viewPitch, s.viewDist, s.leftDist, s.camW, s.gloss, s.glare ? 1 : 0,
                             Double(s.layers), Double(s.mode), Double(s.hemi), Double(s.lzw), s.cutOn ? 1 : 0, Double(s.cutRef), s.cutAngDeg, s.cutWDeg, s.cutPhi, Double(s.cutKind), Double(s.planeDir), s.cutPos, s.cutSweep ? 1 : 0, Double(s.cut4Axis), s.wireW, s.followOn ? 1 : 0, s.followSlack, s.followDrift, s.diveT,
                             s.axes ? 1 : 0, s.axPlus ? 1 : 0, s.axThin ? 1 : 0, s.walk ? 1 : 0, s.marksOn ? 1 : 0, Double(s.cursor), Double(s.ovCursor), s.starDepth, s.autoYaw, s.autoPitch, s.diveYawOff, s.divePitchOff, s.thirdK, s.chaseDistS, s.chasePitchS, s.chaseYawS, Double(s.depth4), s.depth4K, s.depth4On ? 1 : 0, s.symGlow ? 1 : 0, s.trailW, Double(s.trailCol), s.clearAhead ? 1 : 0, s.poleEN ? 1 : 0, s.diveThird ? 1 : 0, s.chaseDist, s.chasePitch, s.chaseYaw, Double(s.shellModeNow), Double(s.polesMode), Double(s.spaceMode), s.starsPct, s.spaceNow ? 1 : 0, s.auto ? 1 : 0,
                             Double(view.drawableSize.width), Double(view.drawableSize.height)]
        if (s.walk || s.marksOn), let src = wsrc {
            let w = src(); sig += [Double(w.trail.count), w.pos.x, w.pos.y, w.pos.z, w.pos.w, Double(w.marks.count), Double(w.hit.filter { $0 }.count), Double(w.poles.count)]
        }
        if owner { HyperLabState.planWanted = s.walk && s.planOn; HyperLabState.railWanted = s.walk && s.railOn }
        if flashing || (side == .right && s.diveT > 0.05) || (s.walk && [1, 3, 4].contains(s.cursor)) || (HyperLabState.planWanted && HyperLabState.planActive) { sig.append(CACurrentMediaTime()) }   // 光の彗星を出している間も（すじが流れる）   // 光っている間・寄っている間（星がまたたく）は、止まっていても描き続ける                 // 当たった瞬間の光の間は、止まっていても描き続ける
        // ほんの少しの違い（計算の誤差）は「同じ」とみなす
        let moved = sig.count != lastSig.count || zip(sig, lastSig).contains { abs($0 - $1) > 1e-7 }
        // 動いている時のコマ数：ふだんは画面のいちばん速いコマ数。実際のコマ数が 2 秒続けて目標の 8 割に届かなければ（GPU があふれて
        //   コマを待つ間、ドラッグなどの操作も遅れてひっかかる）1 段下げ（画面の最高の 1/2・1/3…）、5 秒続けて余裕があれば 1 段上げてみる
        if owner { HyperLabState.boostWalk = s.diveFade > 0 }   // さんぽの窓を速くするのは、景色を右の大きな画面に重ねている間だけ（ふだんは 72 で十分。重ねる前に速くすると、ほかが詰まる）
        // コマ数の自動調整は、画面の半分（144Hz なら 72）より下げない。半端な速さ（80〜100）は 144Hz の画面でコマの間隔がそろわずカクついて見えるので、
        //   届かない時は、まず画質を下げ、それでも届かなければ画面の半分（一定の間隔）にする
        if owner { HyperLabState.walkBigShown = s.diveFade > 0.99 }
        if s.quality != 0 { HyperLabState.renderK = [1.0, 1.0, 0.75, 0.6][s.quality] }
        // さんぽの静かモード（ファンを回さない）の時は、超球の窓も静かに：コマ数だけ、画面の速さを割り切れる 45 以上のいちばん遅い速さへ（144Hz → 48）。
        //   描く画素は減らさない（減らして引き伸ばすと、細い線と小さな星がにじんで、透けたように色が薄く見える）
        let quiet = s.hyperQ == 1 || (s.hyperQ == 0 && (HyperLabState.walkRendererGet?()?.set.quiet ?? false))
        if owner { HyperLabState.quietNow = quiet }
        let kMax = 1.0
        // 遅い時は、まず画質（描く画素の数）を下げ、それでも遅ければコマ数を下げる（ダイブ・追う間はコマ数は下げない）。余裕が戻ったら逆の順に上げる。
        //   画質を決めるのは左の画面だけ（同じ窓の両方が同じ値を使う）
        // 超球だけ（さんぽの窓は止める）の時は静かに：動かす時も画面の速さを割り切れる 60 以上のいちばん遅い速さまで（144Hz → 72、120Hz → 60）。ファンを回さない
        //   上限はいつも 60 くらい（画面の速さを割り切れる 60 以上のいちばん遅い速さ：120Hz → 60、144Hz → 72）。それ以上は見た目がほとんど変わらず、熱くなるだけ
        var top = maxFPS / max(1, maxFPS / 60)
        if s.walk && [1, 3, 4].contains(s.cursor) && s.cometSpd < 0.03 && s.diveT == 0 { top = min(top, maxFPS / max(1, maxFPS / 60)) }   // 彗星が止まっている時は 60 まで（なめらかなまま、少し静かに）
        if quiet { top = min(top, maxFPS / max(1, maxFPS / 45)) }
        if HyperLabState.hyperIdle { top = maxFPS / max(1, maxFPS / 15) }   // 前の窓だけ描く：さんぽの窓が前の間は画面オフ（計算だけゆっくり続ける）
        if wasIdle && !HyperLabState.hyperIdle { moveFPS = top; if !lowFPS { view.preferredFramesPerSecond = moveFPS } }   // 超球の窓が前に戻ったら、すぐ元のなめらかさに
        wasIdle = HyperLabState.hyperIdle
        if moveFPS > top { moveFPS = top; if !lowFPS { view.preferredFramesPerSecond = moveFPS } }
        if !lowFPS {
            pN += 1; pT += dt
            // 0.5 秒ごとに数える（ダイブは 3 秒ほどなので、画質はすぐ下げる。上げるのはゆっくり＝ 2.5 秒続けて余裕がある時）
            if pT >= 0.5 {
                let got = Double(pN) / pT; pN = 0; pT = 0
                if got < Double(moveFPS) * 0.82 { slowS += 1; fastS = 0 } else if got > Double(moveFPS) * 0.94 { fastS += 1; slowS = 0 } else { slowS = 0; fastS = 0 }
                let lv = maxFPS / max(1, moveFPS), auto = s.quality == 0 && owner
                if slowS >= 2 {
                    slowS = 0
                    // 足りない時は、まずコマ数を落として画質を守る（粗密・道を全部などで重い時も、絵はきれいなまま）。
                    //   コマ数がもう半分（60Hz なら 30）まで落ちていたら、自動の時だけ画質を 75% まで（それより下げると細い線がぼやけて混ざり、色がくすんで見える）
                    if moveFPS > maxFPS / 2 { moveFPS = maxFPS / (lv + 1); view.preferredFramesPerSecond = moveFPS }
                    else if auto && HyperLabState.renderK > 0.76 { HyperLabState.renderK = max(0.75, HyperLabState.renderK - 0.125) }
                } else if fastS >= 2 && (s.diveT == 0 || s.diveT == 1) {     // 余裕が 1 秒続いたら戻す（画質を先に、次にコマ数）
                    fastS = 0
                    if auto && HyperLabState.renderK < kMax - 0.001 { HyperLabState.renderK = min(kMax, HyperLabState.renderK + 0.125) }
                    else if lv > 1 && maxFPS / (lv - 1) <= top { moveFPS = maxFPS / (lv - 1); view.preferredFramesPerSecond = moveFPS }
                }
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
        let key = side == .left ? "\(st.zw),\(st.layers),\(st.hemi),\(st.lzw),\(st.axes),\(st.shellModeNow)" : "\(st.layers),\(st.hemi),\(st.shellModeNow),\(st.cutOn && st.cutKind == 0 && st.cutRef == 2 ? "\(st.cutPhi),\(st.cutWDeg.rounded())" : "-")"
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
        if side == .right && dvFade > 0.995 { return }              // 景色に入りきった：上に重ねた景色で隠れるので、超球は描かない（軽く）
        if side == .right && dvT > 0 {
            let (_, e2) = Self.diveEase(dvT), f0 = Self.fitFov(Self.rightFov, asp), fov = f0 + (Float(diveFov) - f0) * Float(e2)   // 終わりは景色と同じ視野
            u.mvp = Self.persp(fov, asp) * view3()                       // 鏡は描いたあとで（mirf。なめらかに広げる）
            lastFov = Double(fov); lastAsp = Double(asp)
        } else { let fv = Self.fitFov(side == .right ? Self.rightFov : 45, asp); u.mvp = Self.persp(fv, asp) * view3(); lastFov = Double(fv); lastAsp = Double(asp) }
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
        if side == .right && st.glareAuto { let k = tickGlint(eye, R, Up, { let k = dir(-30, 33); return SIMD3<Double>(Double(k.x), Double(k.y), Double(k.z)) }()); u.g.x *= k; u.g.y *= k; u.eye.w = k }   // 固定の光はそのまま k 倍（eye.w）
        if side == .right && dvT > 0 { let k = Float(1 - Self.diveEase(dvT).1); u.g.x *= k; u.g.y *= k }   // ダイブ：近づくほど照り返し・グレアを消す（景色には無いので）
        if side == .right && (st.shellModeNow == 1 || st.shellModeNow == 2) { u.g.x *= 0.18; u.g.y *= 0.18 }   // 4 方向レインボー・軸の色：殻が 4 倍重なるので、照り返しの白いぼやけを弱く
        e.setCullMode(.none)
        planeCut(&u)
        // 宇宙モード：さんぽと同じ（さんぽで宇宙の背景を入れている時）か、入
        let wk = (wsrc)?()
        st.spaceNow = st.spaceMode == 1 || (st.spaceMode == 0 && (wk?.space ?? false))
        if st.spaceNow, let bg = spaceBackground(sz) {
            e.setRenderPipelineState(bgPipe); e.setDepthStencilState(depthAlways); e.setFragmentTexture(bg, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if side == .left, !rings.isEmpty, let mb = ringMesh {
            var ul = u; ul.g.z = 1; ul.g.w = 1
            e.setRenderPipelineState(ringPipe); e.setDepthStencilState(depthWrite)
            e.setVertexBuffer(mb, offset: 0, index: 0); e.setVertexBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1)
            rings.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 2) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 2) }
            }
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ringMeshCount, instanceCount: rings.count)
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
            hg.q = SIMD4(1, solidA * (sp ? 0.22 : 1), Float(effCamW), Float(Self.SCALE)); hl.q = SIMD4(1.4, wireA * (sp ? Float(HyperLabState.spaceWire) : 1), Float(effCamW), Float(Self.SCALE))
            hg.d.x = Float(effClamp); hl.d.x = Float(effClamp)
            hl.d.y = Float(HyperLabState.wireBackGray); hl.d.z = Float(HyperLabState.wireBackDark)   // 宇宙：殻と網目は控えめに（中の星が見えるよう）
            hg.r = SIMD4(Float(Self.R), Float(rMesh), 0, 0); hl.r = hg.r
            // 自分のいる所の近くの殻・網目を濃く（さんぽの跡を出している時。4 方向・4 軸は強め、ほかは控えめ）
            if st.walk, let w = wsrc?() {
                let k: Float = (st.shellModeNow == 1 || st.shellModeNow == 2) ? 1 : 0.6
                hg.s = SIMD4<Float>(w.pos); hg.t.x = k; hl.s = hg.s; hl.t.x = k
                // ヘッドライト（ダイブの景色の時だけ）：彗星から遠い殻・網目ほど暗く（遠くは闇に溶ける）
                let hd = Float(Self.diveEase(dvT).1); hg.t.y = hd; hl.t.y = hd
                // 矢印の明かり：予定の道の 0.06・0.12・0.18・0.24 先（ダイブの時だけ）
                if HyperLabState.arrowLight && st.planOn && hd > 0.3 && w.plan.count >= 2 {   // 矢印の明かり（いまは切ってある：殻の色が白く飛ぶので）
                    var acc = 0.0, out: [SIMD4<Float>] = [], want = [0.06, 0.12, 0.18, 0.24], wi = 0
                    for i in 1..<w.plan.count where wi < want.count {
                        acc += simd_length(w.plan[i] - w.plan[i - 1])
                        if acc >= want[wi] { out.append(SIMD4<Float>(w.plan[i])); wi += 1 }
                    }
                    while out.count < 4 { out.append(.zero) }
                    for h in [0, 1] { var r = h == 0 ? hg : hl; r.a0 = out[0]; r.a1 = out[1]; r.a2 = out[2]; r.a3 = out[3]; r.t.w = hd; if h == 0 { hg = r } else { hl = r } }
                }
                let hf = w.head ?? w.vL, fwd = hf - w.pos * simd_dot(hf, w.pos)
                if simd_length(fwd) > 1e-9 { hg.f = SIMD4<Float>(simd_normalize(fwd)); hl.f = hg.f }
            }
            // 4 方向レインボー：網目の線は、極に近い殻でも前より濃くしない（濃くすると、奥のかすみで暗くした線が黒い線になって上に重なる）。r.z：網目の濃さの上限
            //   宇宙の時は、網目と殻をもう少し透明に（中の星屑が見えるように）
            if st.shellModeNow == 1 && shellFams(left: false).count > 1 { hl.r.z = sp ? 0.28 : 0.45; if sp { hg.q.y *= 0.7 } }   // 軸の色（4 軸）は色が組ごとに違うので、足し合わせると白く混ざる。網目は前のまま
            //   ダイブで寄るほど、網目と殻をさらに透明に（中の星屑の景色を主役に）
            if hl.r.z > 0 { hg.r.z = 1 }                                     // 殻のふちを少し濃く（hrv）
            else if st.shellModeNow == 0 { hg.t.z = 1 }                       // ふつうのレインボー：斜めから見た殻を濃く（hrv）
            if hl.r.z > 0 && dvT > 0 { let dz = Float(Self.diveEase(dvT).1); hl.r.z *= 1 - 0.35 * dz; hg.q.y *= 1 - 0.15 * dz }
            // 4D の遠近：ダイブで寄るほど弱める（寄った所は景色と同じに）
            let dk = st.depth4On ? Float(st.depth4K * (1 - Self.diveEase(dvT).1)) : 0
            hg.e = SIMD4(st.depth4 == 1 || st.depth4 == 3 ? dk : 0, st.depth4 >= 2 ? dk : 0, 0, Float(naviBall)); hl.e = hg.e
            // 天の川の淡い光は出さない（暗いのが魅力）。天の川は星の密度で見せる（drawStars）
            var ug = u; ug.g.z = HyperLabState.shellPixelLight ? 1 : 2; ug.g.w = 0   // 殻の光：ふだんは頂点ごと（2）。比べる時は画素ごと（1）
            var ul = u; ul.g.z = 0
            if st.cutOn && st.cutKind == 0 && st.cutRef < 2 {
                let c = SIMD4<Float>(Float(st.cutRef + 1), Float(st.cutAngDeg * .pi / 180), Float(st.cutWDeg * .pi / 360), 0)
                ug.cut = c; ul.cut = c
            }
            if st.cutOn && st.cutKind == 2 && dvT == 0 {               // 4D で切る：超平面 w′ ＝ 一定の切り口だけ（殻・軸・跡は出さない）
                drawSlice4(e, u, m)
                var hs = hg; hs.r.z = Float(st.cutPos * Self.R); hs.r.w = Float(st.cut4Axis); drawStars(e, u, hs, slice: true)
                return
            }
            if dvT == 0 || st.axesDive { drawAxes4(e, u) }           // ダイブの間も（「ズーム中も」を切ると出さない）
            var wk = SIMD4<Float>(Float(sz.width), Float(sz.height), Float(st.wireW * rK * 0.5), 0)   // 線の太さ（画面の点 × 細かさ）
            e.setRenderPipelineState(rPipe); e.setVertexBuffer(rb, offset: 0, index: 0); e.setVertexBuffer(rc, offset: 0, index: 3)
            // 4 方向レインボー・軸の色：面を全部先に描いてから、線をまとめて描く（線が奥行きを書くので、層ごとに交互に描くと、あとの面が線の所だけ抜けて黒い筋になる）
            let multiFam = (st.shellModeNow == 1 || st.shellModeNow == 2) && shellFams(left: false).count > 1   // 4 方向レインボー・軸の色（4 軸）
            func drawFaces(_ r: (g: Range<Int>, l: Range<Int>)) {
                if solidA > 0 && !r.g.isEmpty {
                    e.setDepthStencilState(depthRead)
                    e.setVertexBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hg, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.drawIndexedPrimitives(type: .triangle, indexCount: r.g.count, indexType: .uint32, indexBuffer: ri, indexBufferOffset: r.g.lowerBound * 4)
                }
            }
            func drawWires(_ r: (g: Range<Int>, l: Range<Int>)) {
                if wireA > 0 && !r.l.isEmpty {
                    // 網目は太さのある帯で（1 画素の線は細すぎて色が薄く見える）。宇宙の時は足し合わせて光らせる（さんぽの景色の線のように）
                    // 4 方向レインボー・宇宙でダイブ中：線は奥行きを書かない（書くと、あとから描く星屑が線の所だけ隠れて、暗い筋になる）。
                    //   外から見る時は書く（書かないと、奥の線まで全部重なって白く飛ぶ）
                    //   奥行きを書かないのは 4 方向レインボーだけ（網目の濃さに上限があるので、奥まで見えても白く飛ばない）
                    e.setDepthStencilState(hl.r.z > 0 && sp && dvT > 0 ? depthRead : depthWrite)
                    e.setRenderPipelineState(sp || hl.r.z > 0 ? wirePipeAdd : wirePipe)   // 4 方向レインボーも光の線（暗い紫が黒い線に沈まない）
                    e.setVertexBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hl, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.setVertexBuffer(ri, offset: r.l.lowerBound * 4, index: 4); e.setVertexBytes(&wk, length: 16, index: 5)
                    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: r.l.count / 2)
                    e.setRenderPipelineState(rPipe)
                }
            }
            if multiFam { for r in ranges { drawFaces(r) }; for r in ranges { drawWires(r) } }
            else { for r in ranges { drawFaces(r); drawWires(r) } }
            drawStars(e, u, hg)
            // 寄った時の星は、さんぽと同じ本物の星だけ（drawStars。天の川は、さんぽと同じ y・z の大きな円のまわりの星）
            drawWalk(e, u); drawMarks(e, u)                               // ダイブの間も、跡をたどって背中へ寄る（玉は画面の上で大きくなりすぎないよう縮める）
            if st.spaceNow && st.shellModeNow == 1 { drawFlare(e, u) }   // 4 方向レインボー・宇宙：天の川の中心のレンズフレア
            if dvT == 0 || st.axesDive { drawAxisLabels(e, u) }
            return
        }
        if let b = glassBuf {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthRead); u.g.z = 1; u.g.w = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glass.count)
        }
        if let b = lineBuf {
            // 線は太さのある帯で（左は 2 倍の大きさに描くので、太さも 2 倍）
            var k = SIMD4<Float>(Float(sz.width), Float(sz.height), Float(st.wireW * (side == .left ? 2 : 1) * rK * 0.5), 0)   // 画質を下げても、画面の上の太さは同じ
            e.setRenderPipelineState(segPipe); e.setDepthStencilState(depthRead); u.g.z = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.setVertexBytes(&k, length: 16, index: 5)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: lines.count / 2)
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
    /// perspW：ダイブで寄る時。太さを目からの距離に比べて変える（距離 perspW の所で w。画面の上ではどこもだいたい同じ細さ。寄っても太い帯にならない）
    static func flatArrow(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, eye: SIMD3<Double>, w: Double, plus: Bool, perspW: Double? = nil) -> [HLVert] {
        let d = b - a, L = simd_length(d); guard L > 1e-6 else { return [] }
        let f = d / L, head = min(0.13, L * 0.18), neck = b - f * head, mid = (a + b) / 2
        if let D0 = perspW {
            func v(_ p: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: c) }
            func side(_ p: SIMD3<Double>) -> SIMD3<Double> {
                var s = simd_cross(f, eye - p); let l = simd_length(s); s = l < 1e-9 ? .zero : s / l
                return s * w * max(0.002, simd_length(eye - p) / D0)
            }
            func strip(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ c: SIMD4<Float>) -> [HLVert] {
                var o: [HLVert] = []; let n = 64
                for i in 0..<n {
                    let p0 = p + (q - p) * (Double(i) / Double(n)), p1 = p + (q - p) * (Double(i + 1) / Double(n)), s0 = side(p0), s1 = side(p1)
                    o += [v(p0 - s0, c), v(p1 - s1, c), v(p1 + s1, c), v(p0 - s0, c), v(p1 + s1, c), v(p0 + s0, c)]
                }
                return o
            }
            let on = SIMD4(col, 1), dim = SIMD4(col * 0.75, 0.55)
            var out = plus ? strip(a, neck, on) : strip(a, mid, dim) + strip(mid, neck, on)
            let sn = side(neck) * 4.5
            out += [v(neck - sn, on), v(b, on), v(neck + sn, on)]
            return out
        }
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
            let zoom = side == .right && dvT > 0                     // ダイブ：寄っても細い線のまま（立体の矢印も、この間は線に）
            tri += st.axThin || zoom ? Self.flatArrow(a, b, Self.axisCol[k], eye: eye, w: zoom ? 0.012 : 0.007, plus: st.axPlus, perspW: zoom ? st.viewDist : nil) : Self.arrow(a, b, Self.axisCol[k], plus: st.axPlus)
        }
        drawAxisTris(e, u0, tri, depthTest: true)
    }
    /// 軸の名前の文字の絵（数式の斜体。暗いふちどりつき。1 度だけ作る）
    private func labelTexture(_ s: String, _ col: SIMD3<Float>, math: Bool = true, serif: Bool = false) -> MTLTexture? {
        let key = "\(s)|\(col)|\(math)|\(serif)"
        if let t = labelTex[key] { return t }
        let size: CGFloat = 96
        let name = ["KaTeX_Math-Italic", "STIXTwoText-Italic", "Georgia-Italic"].first { (CTFontCopyPostScriptName(CTFontCreateWithName($0 as CFString, 12, nil)) as String) == $0 } ?? "Georgia-Italic"
        // 軸の名前は数式の斜体、目印の番号と ✓ はふつうの太字（数式の書体だと ✓ が √ のように見える）
        let font = serif ? CTFontCreateWithName("Baskerville-SemiBold" as CFString, size * 0.95, nil)   // 英語モードの極の名前（セリフ体）
            : math ? CTFontCreateWithName(name as CFString, size, nil) : (CTFontCreateUIFontForLanguage(.emphasizedSystem, size * 0.9, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size * 0.9, nil))
        func line(_ stroke: Bool) -> CTLine {
            var a: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let c = CGColor(srgbRed: CGFloat(col.x), green: CGFloat(col.y), blue: CGFloat(col.z), alpha: 1), dark = CGColor(srgbRed: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 0.92)
            a[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = stroke ? dark : c
            if stroke { a[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = 22.0; a[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = dark }
            let m = NSMutableAttributedString(string: s, attributes: a)
            // 通った極・目印の ✓ だけ蛍光の黄緑（名前はその色のまま）
            if !stroke && s.hasPrefix("✓") { m.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 1), range: NSRange(location: 0, length: 1)) }
            return CTLineCreateWithAttributedString(m)
        }
        let fill = line(false), bounds = CTLineGetBoundsWithOptions(fill, .useGlyphPathBounds)
        let check = s.hasPrefix("✓"), pad: CGFloat = check ? 40 : 18, W = Int(ceil(bounds.width + pad * 2)), H = Int(ceil(size * (check ? 1.55 : 1.3)))
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if check {
            // 通った極・目印：蛍光の黄緑の長丸で囲む（中はうすく光らせる）
            let r = CGRect(x: 8, y: 8, width: CGFloat(W) - 16, height: CGFloat(H) - 16), path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
            ctx.addPath(path); ctx.setFillColor(CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 0.10)); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(CGColor(srgbRed: 0.02, green: 0.04, blue: 0.08, alpha: 0.7)); ctx.setLineWidth(12); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(CGColor(srgbRed: 0.64, green: 1.0, blue: 0.24, alpha: 1)); ctx.setLineWidth(6); ctx.strokePath()
        }
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
    /// ダイブの間（右）は画面を左右の鏡にしているので、札の文字は逆に並べて裏返らないように
    private var mirrorX: Double { side == .right && diveMirror > 0.3 ? -1 : 1 }
    /// ダイブの鏡の広がり（0：鏡なし〜0.5：画面の端まで鏡。少し先まで行って、ふちのぼかしも画面の外へ）。
    ///   自分が画面の真ん中にそろった後（向きのそろえは 0.5 まで）、寄っていく途中の 0.52〜0.78 で広げる（真ん中がずれていると、物が 2 つに分かれて見える）
    var diveMirror: Double { side == .right && dvT > 0 ? -0.1 + 0.75 * smoothstep(0.52, 0.78, dvT) : -0.1 }
    /// 描いた絵 src を、鏡を広げながら dst へ
    private func mirrorPass(_ cb: MTLCommandBuffer, _ src: MTLTexture, _ dst: MTLTexture) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let f = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        // y：周辺減光とコントラスト（ダイブで寄るほど。黒をより黒く・端を暗く）、z：横÷縦
        var k = SIMD4<Float>(Float(diveMirror), Float(Self.diveEase(dvT).1), Float(src.width) / Float(max(1, src.height)), 0)
        f.setRenderPipelineState(mirPipe); f.setFragmentTexture(src, index: 0); f.setFragmentBytes(&k, length: 16, index: 0)
        f.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); f.endEncoding()
    }
    /// 札を 1 枚：c を真ん中に、いつも画面に向く板で（大きさは画面の上でだいたい同じに。k で倍率）
    private func drawLabel(_ e: MTLRenderCommandEncoder, _ s: String, _ col: SIMD3<Float>, _ c: SIMD3<Double>, k: Double = 1, math: Bool = true, serif: Bool = false) {
        guard let tex = labelTexture(s, col, math: math, serif: serif) else { return }
        let (eye, Rv, Uv, _) = camBasis()
        let dist = simd_length(eye - c), hgt = 0.075 * dist / 5.5 * 2.6 * k, wid = hgt * Double(tex.width) / Double(tex.height)
        let rx = Rv * (wid / 2 * mirrorX), uy = Uv * (hgt / 2)
        func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
        var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
        e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    /// 歩いた跡・目印の点を画面の 3 次元へ（右：超球の上を 4D の回転・遠近で、左：影 (x, y, w) を球の上へ）。face：見えている側なら 1、奥の側は 0
    private func walkPlace(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) {
        let R = Self.R, camW = side == .right ? effCamW : st.camW
        if side == .right {                                                // 右はカメラの向きを使わない（camBasis は重いので、左の時だけ求める）
            let v = effM * (p * R), s = camW / max(effClamp, camW - v.w) * Self.SCALE
            return (SIMD3(v.x, v.y, v.z) * s, smoothstep(-0.1, 0.05, (v.w - R * R / camW) / R))
        }
        let eye = camBasis().0
        var q = SIMD3(p.x, p.y, p.w); let l = simd_length(q); q = l < 1e-9 ? SIMD3(0, 0, 1) : q / l
        let w = leftRot() * (q * R * 1.012)
        return (w, smoothstep(-0.15, 0.1, simd_dot(simd_normalize(w), simd_normalize(eye - w))))
    }
    /// 強い照り返しのよけ：殻が平たくなる向きでは、何枚もの殻の照り返しが同じ所へ重なって白いかたまりになる。少ない点で殻の照り返しを足して、
    ///   画面の粗い升目でいちばん強い所を測り、強いと判断した間だけ反射を切る（さっと切って、弱くなったら戻す自動）。測るのは 1 秒に 10 回
    private var glintT = -9.0, glintLast = -9.0, glintNow = 0.0, glintK: Float = 1, glintCut = false, glintFlashT = -99.0, glintNext = 0.0
    private func tickGlint(_ eye: SIMD3<Double>, _ Rv: SIMD3<Double>, _ Uv: SIMD3<Double>, _ key: SIMD3<Double>) -> Float {
        let now = nowT, dt = max(0, min(0.1, now - glintLast)); glintLast = now
        if abs(now - glintT) >= 0.1 { glintT = now; glintNow = glintMeasure(eye, Rv, Uv, key) }
        // 反射カット：強いと判断したら、まず 1 秒あまりテカーッと見せてから、さっと切る。その向きにいる間も 7〜12 秒に 1 回テカーッと光らせる。
        //   十分弱くなったと判断したら戻す。切る値と戻す値を離して、行き来してちらつかないように
        if glintNow >= Self.glintHi {
            if !glintCut { glintCut = true; glintFlashT = now - 0.2; glintNext = now + Double.random(in: 7...12) }   // 入った時は、もう光っているので、光り始めから
        } else if glintNow < Self.glintLo { glintCut = false }
        if glintCut && now >= glintNext { glintFlashT = now; glintNext = now + Double.random(in: 7...12) }
        let fa = now - glintFlashT                                        // テカーッ：0.2 秒で明るく、0.7 秒そのまま、0.4 秒で消える
        let flash = fa < 0 ? 0 : Float(smoothstep(0, 0.2, fa) * (1 - smoothstep(0.9, 1.3, fa)))
        let target: Float = glintCut ? max(0.02, flash) : 1               // ふだんは、殻が何十枚も重なって足されるので、ぐっと下げる（ほんのり残す）
        glintK += (target - glintK) * Float(1 - exp(-dt * (glintCut ? 14 : 2.2)))
        return glintK
    }
    static var glintLo = 5.5, glintHi = 7.5
    static var glintLog = false
    private var camLogT = -9.0, railI = 0, railN = 0, railTrailN = 0
    static let glintL1 = simd_normalize(SIMD3<Double>(5, 12, 8))
    private func glintMeasure(_ eye: SIMD3<Double>, _ Rv: SIMD3<Double>, _ Uv: SIMD3<Double>, _ key: SIMD3<Double>) -> Double {
        let N = 6, shells = 7, rad = Self.R * Self.SCALE * 1.15
        var grid = [Double](repeating: 0, count: N * N)
        func pt(_ th: Double, _ ph: Double, _ la: Double) -> SIMD4<Double> {
            let st0 = sin(th), sp = sin(ph)
            return SIMD4(st0 * sp * cos(la), st0 * sp * sin(la), st0 * cos(ph), cos(th))
        }
        for t in 0..<shells {
            let th = 0.35 + (Double.pi - 0.7) * Double(t) / Double(shells - 1)
            for i in 1..<9 { let ph = Double.pi * Double(i) / 9
                for j in 0..<16 {
                    let la = 2 * Double.pi * Double(j) / 16, e = 0.02
                    let P = walkPlace(pt(th, ph, la)).0, A = walkPlace(pt(th, ph + e, la)).0, B = walkPlace(pt(th, ph, la + e)).0
                    var n = simd_cross(A - P, B - P); let nl = simd_length(n); if nl < 1e-12 { continue }; n /= nl
                    let v = simd_normalize(eye - P); if simd_dot(n, v) < 0 { n = -n }
                    func spec(_ l: SIMD3<Double>) -> Double { pow(max(0, simd_dot(n, simd_normalize(v + l))), 60) * max(0, simd_dot(n, l)) }
                    let sp = (spec(key) * 0.35 + spec(Self.glintL1)) * sin(ph)    // カメラについて回る光と、固定の光（シェーダーの L1）。極の近くは点が密なので、面積に合わせて減らす
                    let gx = Int((simd_dot(P, Rv) / rad * 0.5 + 0.5) * Double(N)), gy = Int((simd_dot(P, Uv) / rad * 0.5 + 0.5) * Double(N))
                    if gx >= 0 && gx < N && gy >= 0 && gy < N { grid[gy * N + gx] += sp }
                }
            }
        }
        let m = (grid.max() ?? 0) * Double(max(1, st.layers)) / Double(shells)
        if Self.glintLog && overview { print(String(format: "反射 %.1f 秒 %.2f 効き %.2f", nowT, m, glintK)) }
        return m
    }
    /// 当たった瞬間（極・目印が「通った」になった時刻）：ピカッと光らせる。前のコマの「通った」を覚えて比べる（初めのコマは光らせない）
    /// 光っている間（1 秒）は描き続ける（当たった瞬間の記録は Journey.hitPulse）
    var flashing: Bool { let now = ProcessInfo.processInfo.systemUptime; return Journey.hitPulse.contains { now - $0.t < 1.0 } }
    /// 極の色：軸の色の球層の時は、その極が乗る軸の色（アナ・カタ＝w 紫、東西＝x 赤、北南＝y 緑、天地＝z 青）。ほかは地図と同じ色
    func poleColor(_ k: Int) -> SIMD3<Float> {
        guard st.shellModeNow == 2 else { return MapRenderer.poleDotCol(k) }
        return Self.axisCol[[3, 3, 0, 0, 1, 1, 2, 2][k]]
    }
    /// 球面さんぽの目印（チェックポイント）：まだ通っていない目印は目印の色の輪、通った目印は塗りつぶしの丸と ✓。番号は地図と同じ（置いた順）
    private func drawMarks(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.marksOn || st.polesMode > 0, let src = wsrc else { return }
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
        var tags: [(String, SIMD3<Float>, SIMD3<Double>, Bool, Bool)] = []   // 名前・色・場所・英語（セリフ体）・極
        // 光で描く時：画面に向く板 1 枚に、cmf が色の光・十字のきらめき（通った）／光の輪（まだ）を描く
        var ctri: [HLCometVert] = []
        let now = ProcessInfo.processInfo.systemUptime
        /// 当たった瞬間の光の強さ（1 → 0、約 0.9 秒）。極は番号、目印は場所で探す（周回でチェックが消えても光る）
        func flashOf(pole k: Int) -> Float {
            guard let h = Journey.hitPulse.last(where: { $0.pole == k }) else { return 0 }
            let f = max(0, 1 - (now - h.t) / 0.9); return Float(f * f)
        }
        func flashOf(mark m: SIMD4<Double>) -> Float {
            guard let h = Journey.hitPulse.last(where: { $0.pole < 0 && simd_distance($0.p, m) < 1e-9 }) else { return 0 }
            let f = max(0, 1 - (now - h.t) / 0.9); return Float(f * f)
        }
        /// ピカッ：大きな板に、弾ける光と広がる輪
        func flash(_ c: SIMD3<Double>, _ col: SIMD3<Float>, _ fl: Float, _ big: Double) {
            guard fl > 0.001 else { return }
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), hs = big * sc * 2.6
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            func v(_ x: Double, _ y: Double) -> HLCometVert {
                HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), 6, fl), c: SIMD4(col, 1))
            }
            ctri += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        func glow(_ c: SIMD3<Double>, _ col: SIMD3<Float>, _ hit: Bool, _ vis: Float, _ big: Double) {
            let sc = max(0.004, min(1, simd_length(eye - c) / 7.5)), hs = big * sc
            let fw = eye - c, up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
            let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax))
            func v(_ x: Double, _ y: Double) -> HLCometVert {
                HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), hit ? 4 : 5, vis), c: SIMD4(col, 1))
            }
            ctri += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        // 8 つの極（さんぽの地図と同じ色・名前）：通った極は塗りつぶしと ✓、まだの極（いつも出す時）は輪
        for k in poles {
            let (c, f) = walkPlace(FIXED[k].c), col = poleColor(k), vis = Float(0.5 + 0.5 * f), hit = wk.poles.contains(k)
            let fl = flashOf(pole: k)
            flash(c, col, fl, 0.3)                                         // 当たった瞬間：ピカッ
            if st.symGlow { glow(c, col, hit, vis, 0.3 * Double(1 + 0.8 * fl)) }   // 光る星（極の色がほんのり。光っている間は少し大きく）
            else if hit { disc(c, 0, 0.11, SIMD4(col, 0.25 * vis)); disc(c, 0, 0.06, SIMD4(col, vis)); disc(c, 0.06, 0.072, SIMD4(1, 1, 1, 0.9 * vis)) }
            else { disc(c, 0, 0.06, SIMD4(col, 0.14 * vis)); disc(c, 0.045, 0.062, SIMD4(col, 0.9 * vis)) }
            let pn = st.poleEN ? MapRenderer.poleNameEN(FIXED[k]) : MapRenderer.poleName(FIXED[k])
            tags.append((hit ? "✓" + pn : pn, col, c + Uv * 0.15, st.poleEN, true))   // 名前は極の色、✓ だけ蛍光（labelTexture）
        }
        for (i, m) in wk.marks.enumerated() where st.marksOn {
            let (c, f) = walkPlace(m), col = Journey.markColor(i), vis = Float(0.5 + 0.5 * f)
            let hit = i < wk.hit.count && wk.hit[i]
            let fl = flashOf(mark: m)
            flash(c, SIMD3(1, 1, 1), fl, 0.27)                                // 目印は白く光る
            if st.symGlow { glow(c, col, hit, vis, 0.27 * Double(1 + 0.8 * fl)) }
            else if hit {
                disc(c, 0, 0.12, SIMD4(col, 0.28 * vis))                       // にじみ
                disc(c, 0, 0.068, SIMD4(col, vis))                             // 塗りつぶし
                disc(c, 0.068, 0.082, SIMD4(1, 1, 1, 0.9 * vis))               // 白いふち
            } else {
                disc(c, 0, 0.07, SIMD4(col, 0.16 * vis))                       // うすい中
                disc(c, 0.055, 0.075, SIMD4(col, 0.95 * vis))                  // 輪
            }
            tags.append((hit ? "✓\(i + 1)" : "\(i + 1)", col, c + Uv * 0.15, false, false))   // 番号は目印の色、✓ だけ蛍光
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0; u.cut = .zero
        if !tri.isEmpty {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
            tri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        }
        if !ctri.isEmpty {                                              // 光の極・目印（足し合わせ）
            e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
            ctri.withUnsafeBytes { b in if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
            var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ctri.count)
        }
        e.setRenderPipelineState(lbPipe); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
        let lk = side == .right && dvT > 0 ? 0.5 : 0.7                // 寄っている間も名前を（小さく）。目印の番号はこの大きさ
        for (s, col, c, en, pole) in tags { drawLabel(e, s, col, c, k: pole ? lk * 0.78 : lk, math: false, serif: en) }   // 極の名前は小さく（英語はセリフ体）
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
            let rx = Rv * (wid / 2 * mirrorX), uy = Uv * (hgt / 2)
            func lv(_ p: SIMD3<Double>, _ uv: SIMD2<Float>) -> HLLabelVert { HLLabelVert(p: SIMD4(SIMD3<Float>(p), 1), uv: SIMD4(uv.x, uv.y, 0, 0)) }
            var q = [lv(c - rx - uy, [0, 1]), lv(c + rx - uy, [1, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx - uy, [0, 1]), lv(c + rx + uy, [1, 0]), lv(c - rx + uy, [0, 0])]
            e.setVertexBytes(&q, length: MemoryLayout<HLLabelVert>.stride * 6, index: 0); e.setFragmentTexture(tex, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    /// 平面で切る：平面の向きと位置を定数へ（左右とも。くさびは右だけ、別に）。画面に固定は手前・右・上、物体に固定は x・y・z（左は球と一緒に傾く）
    private func planeCut(_ u: inout HLUni) {
        if overview && ovCutK > 0.001 {                                   // 地図の断面のカット：手前の半分を、カメラに向いた平面で切る
            let rad = Self.R * Self.SCALE * 1.15
            u.cut = SIMD4(3, 0, 0, 0); u.cutN = SIMD4(SIMD3<Float>(simd_normalize(camBasis().3)), Float((1 - ovCutK) * rad))
            return
        }
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
    /// おくれて追うカメラの向き（S³ の自分のいる所の接空間）と、彗星が画面の中で先へ出た分（3D）・カメラの傾き（バンク）
    private var lagR: SIMD4<Double>?, lagU = SIMD4<Double>(), lagL = SIMD4<Double>(), lagT = 0.0
    private var leadOff = SIMD3<Double>(), bank = 0.0, lagMix = 0.0
    /// 彗星の頭のゆがみ（3D。曲がる向き・強さ）：すぐ追う向き warpL からのずれを、ばね（少し揺れる）でならす
    private var warpL: SIMD4<Double>?, headWarp = SIMD3<Double>(), headWarpV = SIMD3<Double>()
    private func tickHeadWarp(_ w: HyperLabState.Walk, _ dt: Double) {
        var tgt = SIMD3<Double>()
        if var l = warpL, simd_dot(l, w.vL) > 0.2 {
            l = l - w.pos * simd_dot(l, w.pos); l = simd_normalize(l + (w.vL - l) * (1 - exp(-dt * 6)))
            let d = w.vL - l
            tgt = SIMD3(-simd_dot(d, w.vR), simd_dot(d, w.vU), 0) / 0.25
            if simd_length(tgt) > 1 { tgt = simd_normalize(tgt) }
            warpL = l
        } else { warpL = w.vL }
        // ばね：ω 9、減衰 0.45（曲がり始め・終わりに、ぷるっと揺れる）
        let om = 9.0, ze = 0.45, n = max(1, Int(ceil(dt / 0.005))), h = dt / Double(n)
        for _ in 0..<n { headWarpV += (om * om * (tgt - headWarp) - 2 * ze * om * headWarpV) * h; headWarp += headWarpV * h }
    }
    private func lagFrame(_ w: HyperLabState.Walk, _ k0: Double, step: Double? = nil) -> (SIMD4<Double>, SIMD4<Double>, SIMD4<Double>) {
        let now = nowT, dt = step ?? min(0.05, max(0, now - lagT)); lagT = now
        lagMix += (k0 - lagMix) * (1 - exp(-dt * 2)); if k0 == 0 && lagMix < 1e-3 { lagMix = 0 }   // オートカメラを入り切りした時もなめらかに
        let k = lagMix
        if dt > 0 { tickHeadWarp(w, dt) }
        guard k > 0, var r = lagR, dt > 0 else {
            lagR = w.vR; lagU = w.vU; lagL = w.vL
            leadOff += (SIMD3() - leadOff) * (1 - exp(-dt * 2)); bank += (0 - bank) * (1 - exp(-dt * 1.2))
            return (w.vR, w.vU, w.vL)
        }
        var u = lagU, l = lagL
        if simd_dot(l, w.vL) < 0.2 || simd_dot(u, w.vU) < 0.2 { r = w.vR; u = w.vU; l = w.vL }   // 飛んだ時（初めに戻した時など）は合わせ直す
        // 接空間へ戻して（自分のいる所が進んだ分）、今の向きへ寄せる（約 0.35 秒おくれ）
        let a = 1 - exp(-dt * 2.8)
        func tan(_ v: SIMD4<Double>) -> SIMD4<Double> { v - w.pos * simd_dot(v, w.pos) }
        l = tan(l + (w.vL - l) * a); l = simd_normalize(l)
        u = tan(u + (w.vU - u) * a); u -= l * simd_dot(u, l); u = simd_normalize(u)
        r = tan(r + (w.vR - r) * a); r -= l * simd_dot(r, l); r -= u * simd_dot(r, u); r = simd_normalize(r)
        lagR = r; lagU = u; lagL = l
        // 混ぜる（三人称へ入る途中・出る途中はなめらかに）
        var fr = w.vR + (r - w.vR) * k, fu = w.vU + (u - w.vU) * k, fl = w.vL + (l - w.vL) * k
        fl = simd_normalize(tan(fl)); fu -= fl * simd_dot(fu, fl); fu = simd_normalize(tan(fu)); fr -= fl * simd_dot(fr, fl); fr -= fu * simd_dot(fr, fu); fr = simd_normalize(fr)
        // 今の向きを、おくれたカメラの 3D で：まっすぐなら奥（−z）。曲がった分（横・上下）だけ画面の中を先へ流す
        let hd = w.vL
        let h3 = SIMD3(-simd_dot(hd, fr), simd_dot(hd, fu), -simd_dot(hd, fl))
        let side3 = SIMD3(h3.x, h3.y, 0)
        leadOff += (side3 * k - leadOff) * (1 - exp(-dt * 8))
        // カメラの傾きは、そのあとから（約 0.8 秒おくれ）。曲がる側へ傾ける
        bank += (max(-1, min(1, h3.x / 0.45)) * 0.38 * k - bank) * (1 - exp(-dt * 1.2))
        return (fr, fu, fl)
    }
    /// ダイブの進み（0〜1）を、向きを合わせる分 e1（0〜0.5）と近づく分 e2（0.08〜0.92）へ。どちらもなめらかに
    static func diveEase(_ t: Double) -> (Double, Double) {
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        // 回り込み（e1）と近づき（e2）を重ねて同時に：超球が回って自分の背中が正面に来ながら、カメラがそのまま寄っていく
        return (sm(t / 0.5), sm((t - 0.08) / 0.84))
    }
    /// 毎コマ：右の超球を写す 4D の回転・カメラの位置・遠近の下限を決める（ダイブしていなければ、ふだんの傾きのまま）
    private func diveSetup() {
        tickOvShot(); tickNavi()
        let m0 = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1))))
        effM = m0; effCamW = st.camW; effClamp = 0.6
        guard side == .right, dvT > 0, let w = (wsrc)?(), simd_length(w.vL) > 0.5 else { return }
        let (e1, e2) = Self.diveEase(dvT)
        // 景色と同じ向き：自分のいる所 → 4D の手前（w）、見ている向き → 画面の奥（−z）、上 → 上（y）、右 → 鏡にした x（画面の右）
        // オートカメラ（三人称）：カメラの向きは、彗星の向きを少しおくれて追う（スター・ウォーズの追いかけ。曲がる時は彗星が先に向きを変えて、
        //   画面の中を曲がる側へ流れ、あとからカメラが追いつく）
        let lagK = st.autoCam && !st.camHeld ? dvThird : 0
        let (lR, lU, lL) = lagFrame(w, lagK)
        let m1 = simd_double4x4(rows: [-lR, lU, -lL, w.pos])
        var m = m0 + (m1 - m0) * e1
        // 正規直交に直す（グラム・シュミット。列ごと）
        var c = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        for i in 0..<4 { for j in 0..<i { c[i] -= c[j] * simd_dot(c[i], c[j]) }; let l = simd_length(c[i]); if l > 1e-9 { c[i] /= l } }
        m = simd_double4x4(columns: (c[0], c[1], c[2], c[3]))
        effM = m
        // 4D のカメラを、自分のいる所のすぐ外まで（一人称）。三人称は少し手前で止める（すぐ外まで寄ると、すぐ後ろの道が引き伸ばされて、3D のカメラの後ろへ飛んでしまう）
        effCamW = st.camW + (Self.R * (1.012 + (1.15 - 1.012) * dvThird) - st.camW) * e2
        effClamp = 0.6 + (0.004 - 0.6) * e2
        diveFov = w.fov + (55 - w.fov) * dvThird                       // 三人称は少し狭く（自分のまわりを大きく）
        tickFocus(w)
    }
    /// オートカメラの見せ場：前の方に目印・極・道の点・カーブが近づくと、カメラが少しそちらを向き、彗星は画面の空いた所（反対側、
    ///   左右・上下どこでも）へずれて、行き先が見える。通り過ぎるとゆっくり元の構図へ。focusDir：行き先の向き（3D）、focusW：強さ 0〜1
    private var focusDir = SIMD3<Double>(), focusW = 0.0, focusT = 0.0
    /// ハイライトは一瞬：同じ行き先へは 1.6 秒だけ向き、通り過ぎて離れるまでは、もう向かない（focusKey：今の行き先、focusAge：向いている時間）
    private var focusKey = "", focusAge = 0.0, focusUsed: Set<String> = []
    /// 確かめ用：見せ場の向きを sec 秒ぶん進めて、強さを返す
    func focusForTest(_ sec: Double) -> Double { guard let w = wsrc?() else { return 0 }; diveSetup(); for _ in 0..<Int(sec * 60) { tickFocus(w, step: 1.0 / 60) }; return focusW }
    private func tickFocus(_ w: HyperLabState.Walk, step: Double? = nil) {
        let now = nowT, dt = step ?? min(0.05, max(0, now - focusT)); focusT = now
        var bestK = 0.0, bestD = SIMD3<Double>(), bestKey = "", seen: Set<String> = []
        if st.autoCam && !st.camHeld && dvThird > 0.5 && simd_length(w.vL) > 0.5 {
            let c0 = walkPlace(w.pos).0
            func consider(_ q: SIMD4<Double>, _ wgt: Double, _ key: String) {
                let cs = simd_dot(q, w.pos), a = acos(max(-1, min(1, cs)))
                guard a > 0.03 else { return }
                var t = q - w.pos * cs; let tl = simd_length(t); guard tl > 1e-9 else { return }
                t /= tl
                let k = wgt * (1 - smoothstep(0.25, 0.9, a)) * smoothstep(0.1, 0.5, simd_dot(t, w.vL))   // 近くて、前の方にあるものほど
                if k > 0.01 { seen.insert(key) }
                if k > bestK && !focusUsed.contains(key) { bestK = k; bestD = walkPlace(q).0 - c0; bestKey = key }
            }
            for (i, m) in w.marks.enumerated() where i >= w.hit.count || !w.hit[i] { consider(m, 1, "m\(i)") }
            if st.polesMode != 0 { for (k, p) in FIXED.enumerated() where !w.poles.contains(k) { consider(p.c, 1, "p\(k)") } }
            // カーブ：予定の道で最初に大きく曲がり始める所
            let pl = w.plan
            if pl.count >= 3 { for i in 1..<(pl.count - 1) {
                if Self.geoTurn(pl[i - 1], pl[i], pl[i + 1]) > 0.012 { let q = pl[min(pl.count - 1, i + 8)]; consider(q, 0.85, "c" + [q.x, q.y, q.z, q.w].map { String(Int(($0 * 6).rounded())) }.joined(separator: ",")); break }
            } }
        }
        // 一瞬のハイライト：新しい行き先へ 1.6 秒だけ向く。向き終えた行き先は、見えなくなる（離れる）まで使わない
        if bestKey != focusKey { focusKey = bestKey; focusAge = 0 }
        focusAge += dt
        if !bestKey.isEmpty && focusAge > 1.6 { focusUsed.insert(bestKey); bestK = 0 }
        focusUsed = focusUsed.filter { seen.contains($0) }
        let k = 1 - exp(-dt * (bestK > focusW ? 1.8 : 0.9))              // 向く時は約 0.55 秒、戻る時は約 1.1 秒
        focusW += (bestK - focusW) * k
        if bestK > 0.05, simd_length(bestD) > 1e-9 { let nd = simd_normalize(bestD); focusDir = simd_length(focusDir) < 1e-9 ? nd : simd_normalize(focusDir + (nd - focusDir) * (1 - exp(-dt * 2))) }
        if focusW < 1e-3 && bestK == 0 { focusW = 0 }
    }
    /// 宇宙の背景の絵：画面の大きさ（左は 2 倍で描くので、その半分）で 1 度だけ作る
    private func spaceBackground(_ sz: CGSize) -> MTLTexture? {
        let sc = side == .left ? 2.0 : 1.0, w = max(1, Int(Double(sz.width) / sc)), h = max(1, Int(Double(sz.height) / sc))
        if let t = bgTex, t.width == w, t.height == h { return t }
        if let t = bgTex2, t.width == w, t.height == h { return t }        // 動画を書き出している間は、画面の大きさと 16:9 の 2 つを覚えておく
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
        guard let tex = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return nil }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        var k = SIMD4<Float>(Float(Double(w) / Double(h)), 0, 0, 0)
        e.setRenderPipelineState(bgMakePipe); e.setFragmentBytes(&k, length: 16, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        cb.commit()                                                     // この後で積む絵より先に GPU で描かれる（同じ列）
        bgTex2 = bgTex; bgTex = tex
        return tex
    }
    /// 宇宙モードの星（球面さんぽと同じ 12000 個）。星の数で間引く。右は超球の上、左は影（球の中）
    private func drawStars(_ e: MTLRenderCommandEncoder, _ u: HLUni, _ h: HLRight, slice: Bool = false) {
        let z = side == .right && dvT > 0 ? Float(Self.diveEase(dvT).1) : 0   // ダイブで寄った割合
        guard st.spaceNow || z > 0.02, let b = starBuf else { return }
        let all = Renderer.starList.count, step = st.spaceNow ? max(1, Int((100 / max(5, st.starsPct)).rounded())) : 1
        var uu = u, hh = h, k = SIMD4<Float>(side == .right ? 0.02 : 0.015, side == .right ? 0 : 1, Float(step), (side == .right ? 0.9 : 0.42) * (st.spaceNow ? 1 : 0.6 * z))   // 左は球の中に詰まるので小さく淡く
        // またたき・十字の光：寄るほど強く（宇宙モードで外から見ている時も、ほんの少し）
        var tz = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), st.spaceNow ? 0.15 : 0, z, Float(st.starDepth) * (1 - z))   // またたきはほんの少し。z：寄った時の遠近、w：引きの遠近
        // 4 方向レインボー：網目がにぎやかなので、星屑を強めに（大きく・明るく・よくまたたく）。網目に負けずに星の海が見えるように
        //   星は遠近つき（近いほど大きくくっきり、遠いほど小さく淡く。hh.e.z）で、空間の奥行きがわかるように
        if (st.shellModeNow == 1 || st.shellModeNow == 2) && !slice { k.w *= 1.8 + 0.8 * z; tz.y = max(tz.y, 0.1) * 2.2; hh.e.z = 1 }   // ダイブで寄るほど、さらに明るく
        else if !slice && z > 0.02 { k.w *= 1 + 1.4 * z; tz.y = max(tz.y, 0.1) * 1.6; hh.e.z = Float(smoothstep(0.2, 0.8, Double(z))) }   // ふつうのレインボーも、ダイブでは星屑を遠近つきの小さな点で多めに（牡丹雪にはしない）
        e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
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
    ///   線はカメラに向いた帯（にじみの太い帯＋芯）、古い所ほど青く淡く、新しい所ほど白く明るい。超球（球）の奥の側は薄く。今いる所は青緑の玉
    private func drawWalk(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.walk, let src = wsrc else { return }
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
        var ctri: [HLCometVert] = []                                    // 光の彗星（足し合わせで、あとから描く）
        // カメラに近い所ほど小さく（ダイブで寄っても、画面の上の大きさがだいたい同じ。ふだんはほぼ 1）
        func near(_ p: SIMD3<Double>) -> Double { max(0.004, min(1, simd_length(eye - p) / 7.5)) }
        // 彗星の時：頭から道を戻った長さ。尾の届く所では跡を薄くして、尾が浮き出るように
        // 寄った割合（ダイブ）：ふつうは細くしぼむ尾、寄るほど写真のような 2 本の尾（広がるちりの尾・まっすぐな青いイオンの尾）へ
        let zm = [1, 3, 4].contains(cur) && side == .right && dvT > 0 ? Float(smoothstep(0.25, 0.75, Self.diveEase(dvT).1)) : 0
        // 引きの絵の光の彗星（印 4 大彗星・3 巨大彗星）：光の玉を大きくして、その中にふつうの大きさの彗星（全体像・引きの絵でも、どこにいるかひと目でわかる）。
        //   巨大彗星はさらに大きく。ダイブで寄るほど、ふつうの大きさへ戻す（印 1 彗星は、いつもふつうの大きさ）
        let gk = cur == 3 || cur == 4 ? (side == .right ? 1 - Self.diveEase(dvT).1 : 1) : 0
        let gHead = 1 + (cur == 3 ? 5.5 : 3.5) * gk, gTail = 1 + (cur == 3 ? 2.0 : 1.5) * gk
        // 彗星の明るさ：4D の奥の側（超球の殻の裏）は少し暗く。巨大彗星は殻をまたいでも同じ明るさ（大きな光が殻のふちで欠けて見えないように）
        func fz(_ f: Double) -> Double { 0.6 + 0.4 * (f + (1 - f) * gk) }
        // 尾の長さで速さを見せる：ダイブ中・大彗星・巨大彗星は、ゆっくりの時はほとんど尾を引かず、速さが乗ってくる（cometSpd 0.5 ほど）と今まで通りの尾に
        //   （ふだんの引きの彗星は、いつも今まで通り）
        let spW = max(side == .right ? Self.diveEase(dvT).1 : 0, gk > 0 ? 1 : 0), cs = st.cometSpd
        let spdK = (1 + 0.6 * cs) * (1 - spW * (1 - (0.15 + 0.85 * smoothstep(0.03, 0.5, cs))))
        let comet = cur >= 1, real = [1, 3, 4].contains(cur), tailL = 1.05 * spdK * near(P[P.count - 1].0) * (side == .right ? 1 + 3.5 * dvThird * Self.diveEase(dvT).1 : 1) * gTail * (side == .right ? 1 + 0.35 * max(0, st.showDist - 1) * dvThird : 1)   // ショーカメラが大きく引いた時は、尾を少し長く流す（遠くからでも流れがきれいに）
        var fromHead = [Double](repeating: .infinity, count: P.count)
        if comet {
            fromHead[P.count - 1] = 0
            var k = P.count - 2
            while k >= 0 { let d = simd_length(P[k].0 - P[k + 1].0); if d > 0.6 { break }; fromHead[k] = fromHead[k + 1] + d; if fromHead[k] > tailL * 3 { break }; k -= 1 }
        }
        // 前方の跡を消す：今いる所（S³ の上）の前の向き・すぐそばの古い跡を薄く（たった今歩いた分＝道に沿って 0.3 は残す）。通り過ぎるとまた見える
        let head4 = pts[pts.count - 1]
        var recentFrom = pts.count - 1
        if st.clearAhead {
            var a4 = 0.0, k = pts.count - 2
            while k >= 0 { a4 += simd_length(pts[k + 1] - pts[k]); if a4 > 0.3 { break }; recentFrom = k; k -= 1 }
        }
        let fw4: SIMD4<Double> = { let f = wk.fwd - head4 * simd_dot(wk.fwd, head4), l = simd_length(f); return l < 1e-9 ? .zero : f / l }()
        func aheadKeep(_ i: Int) -> Float {
            guard st.clearAhead, i < recentFrom else { return 1 }
            let q = pts[i], cs = max(-1, min(1, simd_dot(q, head4))), d = acos(cs)
            if d > 0.45 { return 1 }
            let dir = q - head4 * cs, l = simd_length(dir), a = l < 1e-9 ? 1 : simd_dot(dir / l, fw4)   // 前の向きとのなす角の cos
            let ahead = smoothstep(-0.2, 0.3, a), near = 1 - smoothstep(0.12, 0.45, d), close = 1 - smoothstep(0.03, 0.1, d)
            return Float(1 - max(near * ahead, close))
        }
        let railed = st.railOn && wk.rail.count >= 2
        // 線の遠近：near は画面の太さをそろえる補正。そこから彗星よりカメラに遠い所ほど細くする（3 割より細くはしないので、遠くでも消えない）
        let eyeC = max(1e-6, simd_length(eye - P[P.count - 1].0))
        func depthK(_ p: SIMD3<Double>) -> Double { max(0.3, min(1, pow(eyeC / max(1e-6, simd_length(eye - p)), 1.1))) }
        func ribbon(_ width: Double, _ alpha: Float, _ bright: Float) {
            guard P.count >= 2 else { return }
            var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
            for i in 0..<P.count {
                let a = P[max(0, i - 1)].0, b = P[min(P.count - 1, i + 1)].0, p = P[i].0
                if i > 0 && simd_length(P[i].0 - P[i - 1].0) > 0.6 { prev = nil; continue }   // 飛んだ所（初めに戻した時など）はつながない
                var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * width * near(p) * depthK(p)
                let t = Float(i) / Float(max(1, P.count - 1)), vis = Float(0.45 + 0.55 * P[i].1)
                let c: SIMD3<Float>
                switch st.trailCol {
                case 1: c = simd_mix(SIMD3<Float>(0.62, 0.74, 0.95), SIMD3<Float>(1.0, 1.0, 1.0), SIMD3(repeating: t * t)) * bright * 1.1   // 白い光（古い所はうすい青白）
                case 2:                                                     // 軸の色：その点がいちばん近い軸（x 赤・y 緑・z 青・w 紫）の色。間はなめらかに混ぜる
                    let q = pts[i], wq = SIMD4<Double>(pow(q.x, 4), pow(q.y, 4), pow(q.z, 4), pow(q.w, 4)), sw = max(1e-9, wq.x + wq.y + wq.z + wq.w)
                    var a = SIMD3<Float>(0, 0, 0); for k in 0..<4 { a += Self.axisCol[k] * Float(wq[k] / sw) }
                    c = simd_mix(a * 1.1, simd_mix(a, SIMD3(repeating: 1), SIMD3(repeating: 0.3)) * 1.25, SIMD3(repeating: t * t)) * bright   // 殻に埋もれないよう明るめに
                default: c = simd_mix(SIMD3<Float>(1.0, 0.30, 0.62), SIMD3<Float>(1.0, 0.97, 0.80), SIMD3(repeating: t * t)) * bright   // 殻の緑・青に映える暖かい色（古い所は桃色、新しい所は白）
                }
                // 彗星の尾の所は薄く（寄った時は、尾の届く先まで）
                let z0 = 0.35 + 0.65 * Double(zm), z1 = 1.1 + 1.4 * Double(zm)
                let fh = fromHead[i], keep = fh.isInfinite ? 1 : Float(max(0, min(1, (fh - z0 * tailL) / (z1 * tailL))))
                let c1 = railed ? (bright > 1.25 ? SIMD3<Float>(0.88, 1.0, 0.98) : bright > 1.1 ? SIMD3<Float>(0.42, 0.93, 0.90) : SIMD3<Float>(0.12, 0.85, 0.82)) : c   // 先に道を描く時：通った所は線の色によらず彗星の色（青緑のにじみと白っぽい芯）。古い所も薄くしない
                let col = SIMD4(c1, alpha * (railed ? 1 : 0.45 + 0.55 * t) * vis * keep * keep * aheadKeep(i))
                let l0 = p - sd, r0 = p + sd
                if let (pl, pr, pc) = prev {
                    func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                    tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                }
                prev = (l0, r0, col)
            }
        }
        // 先に描く道（レール）：1 周ぶんの道を、跡と同じ太さの薄赤の線で。彗星はこの上を走り、予定の道の矢印もこの上をなぞる。
        //   歩いた跡は白っぽい青緑で上に重なるので、線が塗りかわっていくように見える（1 周で跡を消す時は、跡が消えて薄赤へ戻る）
        if st.railOn && wk.rail.count >= 2 {
            // 彗星より先の所だけ描く（通った所に赤が残ると、彗星の色の線に透けて混ざる）。道の順にたどるので、道が交わる所でも飛ばない。
            //   跡が消えたら（1 周で跡を消す）はじめから全部。跡を消さない時は、1 周で全部が彗星の色のまま
            if wk.rail.count != railN || trail0.count + 5 < railTrailN { railN = wk.rail.count; railI = 0 }
            railTrailN = trail0.count
            if railI >= wk.rail.count { railI = 0 }
            if simd_dot(wk.rail[railI], pos) < cos(0.35) {                // 場所が飛んだ（走り直し・アナ極へ など）：いちばん近い所から合わせ直す
                var bi = 0, bv = -2.0
                for k in wk.rail.indices { let d = simd_dot(wk.rail[k], pos); if d > bv { bv = d; bi = k } }
                railI = bi
            }
            var best = railI, bd = -2.0
            for k in railI..<min(railI + 80, wk.rail.count) { let d = simd_dot(wk.rail[k], pos); if d > bd { bd = d; best = k } }
            railI = best
            if railI >= wk.rail.count - 2 && Journey.lapClearsTrail { railI = 0 }   // 1 周で跡を消す時は、また全部薄赤から（周回を数えない道でも）
            let R = wk.rail[railI...].map { place($0) }
            func rail(_ width: Double, _ alpha: Float, _ c: SIMD3<Float>) {
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
                for i in 0..<R.count {
                    if i > 0 && simd_length(R[i].0 - R[i - 1].0) > 3 { prev = nil; continue }   // ダイブで自分のそばは引き伸ばされて間があくので、跡より広くつなぐ（線が自分の所まで届く）
                    let a = R[max(0, i - 1)].0, b = R[min(R.count - 1, i + 1)].0, p = R[i].0
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * width * near(p) * depthK(p)
                    let col = SIMD4(c, alpha * Float(0.45 + 0.55 * R[i].1)), l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pc) = prev {
                        func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                        tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                    }
                    prev = (l0, r0, col)
                }
            }
            rail(0.05 * st.trailW, 0.16, SIMD3(1.0, 0.45, 0.5)); rail(0.016 * st.trailW, 0.85, SIMD3(1.0, 0.62, 0.66))
        }
        ribbon(0.05 * st.trailW, 0.22, 1.0)                             // にじみ（太さは「跡の太さ」で）
        ribbon(0.016 * st.trailW, 1.0, 1.2)                             // 芯
        if railed { ribbon(0.005 * st.trailW, 0.9, 1.3) }               // 先に道を描く時：通った線の真ん中に細い白っぽい光（彗星の色）
        // 今いる所：さんぽ＝青緑と白の三重の輪、彗星＝小さな光の頭と、歩いた道に沿って細く消えていく尾
        let (c, f) = P[P.count - 1], fw = SIMD3<Double>(eye - c), up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        if side == .right && !overview {                                // 音：手前ほど大きく（3D の距離と、4D の手前・奥の側）
            let span = Self.R * Self.SCALE, dd = simd_length(SIMD3<Double>(eye - c))
            st.cometNear = max(0, min(1, 0.5 + (simd_length(eye) - dd) / (2 * span))) * (0.35 + 0.65 * f)
            let (_, Rv, Uv, Bv) = camBasis(), rel = c - eye, rl = simd_length(rel)
            if rl > 1e-6 { st.cometDir = SIMD3(simd_dot(rel, Rv) * mirrorX, simd_dot(rel, Uv), simd_dot(rel, Bv)) / rl }   // ダイブの鏡の間は左右を逆に（画面と合わせる）
            // カメラの向きを、さんぽの向き（前・右・上）で表す。全体像は写し方がちがうので、S³ の接線の向きで渡す
            func axis3(_ t: SIMD4<Double>) -> SIMD3<Double> { let d = place(simd_normalize(pos + t * 0.02)).0 - c, l = simd_length(d); return l < 1e-9 ? .zero : d / l }
            let tan4 = wk.fwd * simd_dot(rel, axis3(wk.fwd)) + wk.vR * simd_dot(rel, axis3(wk.vR)) + wk.vU * simd_dot(rel, axis3(wk.vU))
            if simd_length(tan4) > 1e-9 { st.camTan = -simd_normalize(tan4) }   // rel はカメラ → 彗星なので、裏返して「彗星から見たカメラの向き」に
            if Self.glintLog, nowT - camLogT >= 1 {
                camLogT = nowT
                let ct = st.camTan, nearP = acos(min(1, abs(pos.w)))
                print(String(format: "カメラ %.0f 秒 前 %+.2f 右 %+.2f 上 %+.2f 極まで %.2f", nowT, simd_dot(ct, wk.fwd), simd_dot(ct, wk.vR), simd_dot(ct, wk.vU), nearP))
            }
        }
        let gone = Float(1 - (1 - dvThird) * max(0, min(1, (dvT - 0.8) / 0.12)))   // 一人称はダイブの終わり（背中に追いつく所）で消える
        let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax)), vis = Float(fz(f)) * gone
        let sc = near(c) * (side == .right ? 1 + 3.5 * dvThird * Self.diveEase(dvT).1 : 1) * gHead   // 三人称：寄っても彗星が点にならないように（巨大彗星は引きの絵で大きく）
        if comet {
            // 尾：頭から道を後ろへ、長さ tailL ぶん（画面の 3 次元で）。先へ行くほど細く・青く・淡く
            var idx = [P.count - 1], acc = [0.0]
            var i = P.count - 2
            while i >= 0 && acc[acc.count - 1] < tailL {
                let d = simd_length(P[i].0 - P[i + 1].0); if d > 0.6 { break }
                idx.append(i); acc.append(acc[acc.count - 1] + d); i -= 1
            }
            // 尾の先：跡が尾の長さより短い時（歩き始め・跡の飛び）は、ある所までを尾の長さとして先へ消す（尾の先が四角く切れない）
            let tailEnd = max(1e-9, min(tailL, acc[acc.count - 1]))
            func tail(_ w0: Double, _ a0: Float, _ hot: SIMD3<Float>, _ cool: SIMD3<Float>) {
                guard idx.count >= 2 else { return }
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
                for k in 0..<idx.count {
                    let j = idx[k], p = P[j].0
                    let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                    let s = min(1, acc[k] / tailEnd)                                 // 0：頭、1：尾の先
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                    sd = l < 1e-12 ? .zero : sd / l * w0 * sc * pow(1 - 0.92 * s, 1.4)                     // 頭の所が太く、後ろへしぼむ
                    let fv = Float(fz(P[j].1)) * gone, fs = Float(s)
                    let col = SIMD4(simd_mix(hot, cool, SIMD3(repeating: fs)), a0 * pow(1 - fs, 1.6) * fv)
                    let l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pc) = prev {
                        func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                        tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                    }
                    prev = (l0, r0, col)
                }
            }
            if real {
                func v(_ x: SIMD3<Double>, _ q: SIMD4<Float>) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(x), 1), q: q) }
                // 帯：点の列に沿って、横の半分の幅 wid(s) で。kind は cmf の種類
                func strip(_ pts: [SIMD3<Double>], _ ss: [Double], _ kind: Float, _ alpha: (Int) -> Float, _ wid: (Double) -> Double) {
                    guard pts.count >= 2 else { return }
                    var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                    for k in 0..<pts.count {
                        let p = pts[k], a = pts[max(0, k - 2)], b = pts[min(pts.count - 1, k + 2)]   // 横の向きは少し広く見て（つなぎ目で急に変わらない）
                        var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                        sd = l < 1e-12 ? .zero : sd / l * wid(ss[k])
                        let al = alpha(k), ql = SIMD4<Float>(Float(ss[k]), -1, kind, al), qr = SIMD4<Float>(Float(ss[k]), 1, kind, al), l0 = p - sd, r0 = p + sd
                        if let (pl, pr, pql, pqr) = prev { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                        prev = (l0, r0, ql, qr)
                    }
                }
                let tp0 = idx.map { P[$0].0 }, ts0 = acc.map { min(1, $0 / tailEnd) }, fc0 = idx.map { P[$0].1 }
                // 寄ると点の間が長く見えて折れ線の角が出るので、道すじをなめらかにして（少しならしてから）、点の間を曲線（Catmull-Rom）で 6 つずつ補う
                var tp: [SIMD3<Double>] = [], ts: [Double] = [], fc: [Double] = []
                if zm > 0.01 && tp0.count >= 2 {
                    var sm = tp0
                    for _ in 0..<2 where tp0.count >= 3 { var nx = sm; for i in 1..<(sm.count - 1) { nx[i] = sm[i] * 0.5 + (sm[i - 1] + sm[i + 1]) * 0.25 }; sm = nx }
                    let m = 6
                    for i in 0..<(sm.count - 1) {
                        let p0 = sm[max(0, i - 1)], p1 = sm[i], p2 = sm[i + 1], p3 = sm[min(sm.count - 1, i + 2)]
                        for j in 0..<m {
                            let u = Double(j) / Double(m), u2 = u * u, u3 = u2 * u
                            // Catmull-Rom の重み（4 点に掛ける数）
                            let w0 = -u3 + 2 * u2 - u, w1 = 3 * u3 - 5 * u2 + 2, w2 = -3 * u3 + 4 * u2 + u, w3 = u3 - u2
                            var q: SIMD3<Double> = p0 * w0
                            q += p1 * w1; q += p2 * w2; q += p3 * w3
                            tp.append(q * 0.5)
                            ts.append(ts0[i] + (ts0[i + 1] - ts0[i]) * u); fc.append(fc0[i] + (fc0[i + 1] - fc0[i]) * u)
                        }
                    }
                    tp.append(sm[sm.count - 1]); ts.append(ts0[ts0.count - 1]); fc.append(fc0[fc0.count - 1])
                }
                if zm > 0.01 && tp.count >= 2 {
                    // ちりの尾：道に沿って、先へ行くほど広がる
                    //   速さが乗るほど、傘（先の広がり）を大きく開く（疾走感）
                    let fan = 1 + 2.4 * smoothstep(0.25, 0.85, st.cometSpd)   // 速いと予定の道の矢印の幅くらいまで大きく開く
                    strip(tp, ts, 2, { k in Float(0.6 + 0.4 * fc[k]) * gone * zm }, { s in 0.09 * sc * (0.4 + 2.6 * s * fan) })
                    // イオンの尾：彗星の向き（今まっすぐ進もうとしている向き）の真後ろへ、まっすぐ長く（曲がっている最中も彗星の向きと平行。ちりの尾は道に沿ってなびく）
                    let hd = wk.head ?? wk.fwd                                      // 本当に進んでいく向き（さんぽは見ている方位へ進む）
                    let f4 = hd - wk.pos * simd_dot(hd, wk.pos), fl4 = simd_length(f4)
                    let jb = ts.firstIndex { $0 >= 0.3 } ?? (tp.count - 1)
                    let behind = fl4 > 1e-6 ? walkPlace(simd_normalize(wk.pos - f4 / fl4 * 0.05)).0 : tp[max(1, jb)]
                    let back = simd_normalize(behind - c + SIMD3(1e-9, 0, 0)), kk = simd_normalize(fw), th = 0.0
                    let d1: SIMD3<Double> = back * cos(th), d2: SIMD3<Double> = simd_cross(kk, back) * sin(th), d3: SIMD3<Double> = kk * (simd_dot(kk, back) * (1 - cos(th)))
                    let dir: SIMD3<Double> = d1 + d2 + d3
                    let n = 24, L = tailL * 1.45                                  // 真ん中の細い尾は中くらいの長さに
                    var ip: [SIMD3<Double>] = [], iss: [Double] = []
                    for q in 0...n { let f = Double(q) / Double(n); ip.append(c + dir * (L * f)); iss.append(f) }
                    strip(ip, iss, 3, { _ in vis * zm * 0.8 }, { s in 0.05 * sc * (0.45 + 1.0 * s) })
                }
                // 光の尾：道に沿った帯（頭で太く、後ろへしぼむ）。色と明るさは cmf が横の位置・頭からの割合で決める
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                for k in 0..<idx.count where idx.count >= 2 && zm < 0.99 {
                    let j = idx[k], p = P[j].0
                    let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                    let s = min(1, acc[k] / tailEnd)
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                    sd = l < 1e-12 ? .zero : sd / l * 0.085 * sc * pow(1 - 0.8 * s, 1.2)
                    let a0 = Float(fz(P[j].1) * (1 - 0.5 * gk)) * gone * (1 - zm)   // 巨大彗星の太い尾は控えめに（中の彗星の尾が見えるよう）
                    let ql = SIMD4<Float>(Float(s), -1, 1, a0), qr = SIMD4<Float>(Float(s), 1, 1, a0), l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pql, pqr) = prev { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                    prev = (l0, r0, ql, qr)
                }
                // 光の頭：画面に向く板（コマはぼんやり広いので、板は大きめ）
                let hw = side == .right && dvT > 0 ? headWarp : SIMD3(), wv = SIMD2(simd_dot(hw, ax), simd_dot(hw, ay)), wm = min(1, simd_length(wv))
                let hs = 0.2 * sc * (1 + 0.45 * wm)                              // ゆがんで伸びる分、板を大きく（ふちで切れないように）
                let wc = SIMD4<Float>(Float(wv.x), Float(wv.y), Float(gk), 1)
                func hv(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), 0, vis), c: wc) }
                ctri += [hv(-1, -1), hv(1, -1), hv(1, 1), hv(-1, -1), hv(1, 1), hv(-1, 1)]
                if gk > 0.01 {
                    // 巨大彗星の中に、ふつうの大きさの彗星（「ここだよ」の印）：細く明るい尾と、くっきりした頭
                    let sc0 = sc / gHead, tl0 = tailL / gTail
                    var pv: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                    for k in 0..<idx.count where idx.count >= 2 && acc[k] <= tl0 {
                        let j = idx[k], p = P[j].0
                        let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                        let s = min(1, acc[k] / max(1e-9, tl0))
                        var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                        sd = l < 1e-12 ? .zero : sd / l * 0.085 * sc0 * pow(1 - 0.8 * s, 1.2)
                        let a0 = Float(fz(P[j].1)) * gone * Float(gk)
                        let ql = SIMD4<Float>(Float(s), -1, 1, a0), qr = SIMD4<Float>(Float(s), 1, 1, a0), l0 = p - sd, r0 = p + sd
                        if let (pl, pr, pql, pqr) = pv { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                        pv = (l0, r0, ql, qr)
                    }
                    let hs0 = 0.26 * sc0, a0 = vis * Float(gk) * 1.6                // 頭は少し大きく明るく（「ここ」がわかるように）
                    func hv0(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs0) + ay * (y * hs0)), 1), q: SIMD4(Float(x), Float(y), 0, a0), c: SIMD4(0, 0, 0, 1)) }
                    ctri += [hv0(-1, -1), hv0(1, -1), hv0(1, 1), hv0(-1, -1), hv0(1, 1), hv0(-1, 1)]
                }
            } else {
                tail(0.075, 0.5, SIMD3(0.85, 0.95, 1.0), SIMD3(0.35, 0.45, 1.0))   // 尾のにじみ（青白く、しぼみながら消える）
                tail(0.024, 1.0, SIMD3(1.0, 1.0, 1.0), SIMD3(0.55, 0.85, 1.0))     // 尾の芯
            }
        }
        // 予定の道：これから進む道を、光の点線で（点はゆっくり進む向きへ流れる。先へ行くほど淡く、彗星のすぐ前は出さない）
        HyperLabState.planActive = !wk.plan.isEmpty
        if st.planOn && wk.plan.count >= 2 {
            // 予定の道の始まりは、彗星の少し先の道の点。頭に彗星の今の場所をつなぐ（矢印が彗星のすぐ前から並ぶ）
            var pl = wk.plan; if let f = pl.first, simd_length(f - wk.pos) > 1e-6 { pl.insert(wk.pos, at: 0) }
            let cb3 = camBasis(), Bv = cb3.3, Uv3 = cb3.2   // Uv3：画面の上の向き（矢印を寝かせる「水平」に使う）
            var cum = [0.0]; cum.reserveCapacity(pl.count)
            for i in 1..<pl.count { cum.append(cum[i - 1] + simd_length(pl[i] - pl[i - 1])) }
            // ダイブで寄るほど：自分のすぐ近くの空間が大きく引き伸ばされる（S³ の短い道のりが画面では長い）。そこで寄った時は、矢印を
            //   画面の 3D の距離で等間隔に並べ（すぐ前から）、大きさも 3D のまま（近いほど大きく、遠いほど小さく）にする
            let dz = side == .right ? Self.diveEase(dvT).1 : 0, ecd = max(0.05, simd_length(eye - c)), nearC = near(c)
            let total = cum[cum.count - 1], now = nowT
            let dive = side == .right ? 1 + 2.5 * dvThird * dz : 1
            let march = dz > 0.4, G = 0.47 * ecd * (1 - 0.55 * surgeK)   // 寄った時の矢印の間隔（3D）。迫る間はぐっと詰める
            // 曲がり具合（道の点ごと。となりの向きとの角度の、少し先までの大きい方）：カーブの所は工事の看板の矢印のように、光が手前から奥へ順に走る
            var bend = [Double](repeating: 0, count: pl.count)
            if pl.count >= 3 { for i in 1..<(pl.count - 1) {
                bend[i] = Self.geoTurn(pl[i - 1], pl[i], pl[i + 1])
            } }
            func seg(_ d: Double) -> (SIMD4<Double>, Int) {               // 道のり d の所の点（長さ 1 に直す前）と、その区間の番号
                var lo = 1, hi = cum.count - 1
                while lo < hi { let m = (lo + hi) / 2; if cum[m] < d { lo = m + 1 } else { hi = m } }
                let j = lo, a = cum[j - 1], b = cum[j], f = b > a ? max(0, min(1, (d - a) / (b - a))) : 0
                return (pl[j - 1] + (pl[j] - pl[j - 1]) * f, j)
            }
            // 寄った時（ダイブ）の矢印は「まぜる」やり方：場所は S³ の本当の点（殻や星と一緒に動き、彗星が近づくとちゃんと矢印の上を通る）、
            //   大きさと向きはふつうの 3D の空間で（大きさは 3D の距離だけ、向きは画面の上の道の向き）。4D の遠近で曲がりが強く出る遠くは出さない
            // 矢印を置く所：(道のり d、並びの番号 u（流れても連続）、手前の消え方)
            var marks: [(d: Double, u: Double, fade: Double, k: Double, sp: Double, dn: Double)] = []   // sp：となりの矢印との 3D の間隔（カメラ距離が 1。粗密で詰めたぶんは割り戻してある）、dn：粗密の詰め具合
            // 矢印は道の上に止まっている（歩いた道のり wk.dist からの決まった所に置く）。彗星が近づいて、矢印の間を通り抜けていく（導かれるように）
            if march {
                // 寄った時：間隔は彗星のそばで 3D の 0.37 × カメラの距離ほど（つながって見えて、カーブの曲がりもなめらかに見えるくらい）。左上の全体像と同じ間隔（S³ で 0.078）にすると、
                //   寄った画面では 1 つめの羽がもう遠すぎて出ないので、その間くらいに（1 つめの羽が彗星の 1 カメラ距離より少し手前）。寄ったあとは間隔を固定（鎖のように道の上に止まる）
                let m0 = simd_length(place(simd_normalize(wk.pos + wk.vL * 1e-3)).0 - c) / 1e-3
                let want = max(0.004, 0.37 * ecd / max(1e-6, m0))
                if marchGap <= 0 || want > marchGap * 2 || want < marchGap * 0.5 { marchGap = want }
                // 粗密：まっすぐな所は間隔を広く、カーブは密に。矢印が道の上に止まったままになるよう、「曲がり具合で重みをつけた道のり W」で等間隔に置く
                //   （重みは道の点ごとに決まるので、彗星が進んでも同じ所に矢印が残る。歩いたぶんの重みつきの道のりは planWAcc に足していく）
                let dense = st.planDense, gp = marchGap * (dense ? 1.4 : 1), w0 = wk.dist
                func dens(_ t: Double) -> Double { dense ? 1 + 2.5 * smoothstep(0.004, 0.03, bend[max(0, min(pl.count - 1, seg(t).1))]) : 1 }
                if let lw = planWLast, w0 >= lw, w0 - lw < 0.5 { planWAcc += (w0 - lw) * dens(0) } else { planWAcc = w0 }
                planWLast = w0
                var W = planWAcc, u = (W / gp).rounded(.up), s3 = 0.0, prev = c, last: SIMD3<Double>? = nil
                let lim = 8 * ecd                                              // 3D の道のりでここまで（並びの位置 k もこれで決める。数が変わっても k がとばない）
                // 「予定の道を全部」：左上の地図と同じように、道の終わりまで出す（3D の道のりで切らない。詰まる所は飛ばすだけ。並びの位置 k は S³ の道のみ）
                let long = st.planLong, dMax = long ? total : min(total, 0.8)   // ふだんは S³ の上で 0.8 先まで（十分に長いが、急なカーブでは先端に矢印が生まれていくのが分かるくらい）
                var t = 0.0
                marchLoop: while marks.count < (long ? 500 : 90) && t < dMax {
                    let step = (t < 0.05 ? 0.0008 : t < 0.3 ? 0.004 : 0.015) / max(1, dens(t)), tn = min(dMax, t + step), dw = (tn - t) * dens(t)
                    if !long { let (q4, _) = seg(tn), l = simd_length(q4); if l > 1e-9 { let q = place(q4 / l).0; s3 += simd_length(q - prev); prev = q } }   // 3D の道のりはふつうの長さの時だけ使う
                    while W + dw >= u * gp {                                     // この 1 歩の中に矢印の所がある（複数あればみんな）
                        let d = t + (tn - t) * max(0, min(1, (u * gp - W) / max(1e-12, dw)))   // 1 歩の中で、ちょうど重みつきの道のりが u・gp になる所
                        if !long && s3 > lim { break marchLoop }                     // 遠く（4D の遠近で大きく曲がる所）は出さない
                        // 遠くで道が 3D の 1 点へ縮む所（4D の遠近）：となりの羽との間が詰まったら、なめらかに淡く消す（羽が団子に重ならない）
                        let qd4 = seg(d).0, ld = simd_length(qd4), qd = ld > 1e-9 ? place(qd4 / ld).0 : prev
                        //   粗密で詰めた所は、そのぶん間隔を割り戻す（カーブで密にしても、4D の縮みと区別して淡くしない）
                        let sp = (last.map { simd_length(qd - $0) / ecd } ?? 1) * dens(d); last = qd
                        if sp < (long ? 0.02 : 0.06) { if long { u += 1; continue }; break marchLoop }
                        marks.append((d, u, smoothstep(0, 0.006, d) * (long ? smoothstep(0.02, 0.08, sp) : smoothstep(0.08, 0.3, sp)), long ? d / max(1e-9, total) : s3 / lim, sp, dens(d))); u += 1   // 1 枚ずつ消さない（彗星の真下に来た時だけ、ふっと消える）
                    }
                    W += dw; t = tn
                }
            } else {
                marchGap = 0; planWLast = nil                                   // 寄っていない間は、次に寄った時に合わせ直す
                let gap = 0.078, w0 = wk.dist
                var u = (w0 / gap).rounded(.up)
                while true { let d = u * gap - w0; if d >= total { break }; marks.append((d, u, smoothstep(0.03, 0.09, d), d / total, 1, 1)); u += 1 }
            }
            let mark = st.planMark, col = Self.beadPalette[mark == 1 ? 1 : 3]   // 目印の色：楕円の光は暖かい白、矢印と金平糖は青白（ほんのり軸の色を混ぜる）
            var side4: SIMD4<Double>? = nil                               // 矢印の横の向き（前の矢印の向きを使う時の予備）
            // 先導（ダイブ）：彗星の今の進む向き（接線）を、画面の 3D で。手前の矢印はこの向きを指し、先へ行くほど道の向きへ回っていく
            //   （「今の向きから、ここでこう曲がる」を前もって示す。道が曲がり始めると、その曲がりが手前から先へ波のように伝わる）
            // 引っぱる所（ダイブ）：道の 0.22 先の点。そこまでの矢印は、その点へまっすぐ引っぱる向きを指す（変化は彗星のすぐ前で終わり、そこからは一直線）
            let dAim = min(total, 0.22), aimP: SIMD3<Double>? = { let (a4, _) = seg(dAim), al = simd_length(a4); return al > 1e-9 ? place(a4 / al).0 : nil }()
            let hd0 = wk.head ?? wk.vL, cX: SIMD3<Double>? = {
                let q1 = place(simd_normalize(wk.pos + hd0 * 1e-3)).0 - c; var v = q1 - Bv * simd_dot(q1, Bv)
                let l = simd_length(v); if l < 1e-12 { return nil }; v /= l; return v
            }()
            // いちばんきつく曲がる所（矢印を置く所の中で、その場の曲がり具合がいちばん大きい所）：回るのはそのあたりの矢印だけ
            // 立体の矢印の向き（ダイブ）：道の始まりで決めた横の向きを、S³ の上で道に沿って平行移動で運ぶ（となりの点の接する面へ写して長さ 1 に直す）。
            //   まっすぐな所では矢印がみんな同じ向きにそろい、道がねじれる所では、道に合わせて自然にねじれる。カメラが動いても向きは変わらない。
            //   始まりの向きも、前のコマの向きを今の始まりへ運んで続ける（急に切りかわらない）
            var nf: [SIMD4<Double>] = []
            if march && mark == 0 && pl.count >= 2 {
                func tang(_ i: Int) -> SIMD4<Double> {
                    let p = simd_normalize(pl[i]); var t = pl[min(pl.count - 1, i + 1)] - pl[max(0, i - 1)]; t -= p * simd_dot(t, p)
                    let l = simd_length(t); return l > 1e-12 ? t / l : t
                }
                func flat(_ n: SIMD4<Double>, _ i: Int) -> SIMD4<Double> {
                    let p = simd_normalize(pl[i]), t = tang(i); return n - p * simd_dot(n, p) - t * simd_dot(n, t)
                }
                var n0: SIMD4<Double>? = nil
                if let pf = planFrame { let v = flat(pf, 0), l = simd_length(v); if l > 0.2 { n0 = v / l } }
                if n0 == nil {
                    var best = SIMD4<Double>(), bl = 0.0
                    for a in [SIMD4<Double>(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)] { let v = flat(a, 0), l = simd_length(v); if l > bl { bl = l; best = v / l } }
                    n0 = best
                }
                nf = [n0!]
                for i in 1..<pl.count { let v = flat(nf[i - 1], i), l = simd_length(v); nf.append(l > 1e-9 ? v / l : nf[i - 1]) }
                planFrame = nf[0]
            }
            var rollRef: Double? = nil                                       // このコマの、鎖全体の回し（立体の矢印）
            var ksRun = Double.infinity                                      // 立体の矢印の大きさ：道の先へ行くほど必ず小さく（それまでの矢印のいちばん小さい大きさ）
            // 誘導灯の光とドミノのスピンの拍：彗星の流れる音（エンジンの低いうなり）のリズムに合わせる。うなり 6 つで 1 回（走っている時で 4 秒ほど）、光の粒がうなりの山で手前を出発し、ゆっくり先へ走る。
            //   疾走感の中をゆっくり光がうねっていく。音が鳴っていない時は 4 秒ごと
            let domC = domOverride ?? Self.domClock(now)
            var bendMax = 0.0
            for mk in marks { let j = seg(mk.d).1; bendMax = max(bendMax, bend[max(0, j - 1)], bend[min(pl.count - 1, j)]) }
            let dtA = min(0.1, max(0, now - arrowSmT)); arrowSmT = now
            var smNew: [Int: (dev: Double, bank: Double, dv: Double, bv: Double)] = [:], rollNew: [Int: (r: Double, v: Double)] = [:]
            // 針のばね：ω 4.5（約 1.4 秒で 1 回ゆれる）、減衰 0.6（少しだけ行き過ぎて、ふわっと止まる）
            //   手前の矢印ほど早く、先の矢印ほどゆっくり追う（変化が手前からドミノのように先へ伝わる。のんびりしたタコメーターのよう）
            func needle(_ x: inout Double, _ v: inout Double, _ to: Double, _ mi: Int) { let w = 6.0 / (1 + 0.22 * Double(mi)), z = 0.6, n = max(1, Int(ceil(dtA / 0.008))), h = dtA / Double(n); for _ in 0..<n { v += (w * w * (to - x) - 2 * z * w * v) * h; x += v * h } }
            var spinNew: [Int: (r: Double, v: Double)] = [:], curveNew: [Int: Double] = [:]
            defer { arrowSm = smNew; arrowRoll = rollNew; spinSm = spinNew; curveSpin = curveNew }
            let camFwd = simd_normalize(c - eye)                              // カメラの向き（彗星はいつも画面の中ほど）。視界の外の矢印は計算しない
            for (mi, mk) in marks.enumerated() {
                let d = mk.d, (q4, j) = seg(d), l = simd_length(q4)
                if l > 1e-9 {
                    let (q, face) = place(q4 / l)
                    // 視界に入らない矢印（カメラの向きから 75° より外・後ろ）は、向きや回りの計算をしない（ばねの状態だけ持ち越す）
                    if march && mark == 0 {
                        let vq = q - eye, lq = simd_length(vq)
                        if lq < 1e-9 || simd_dot(vq / lq, camFwd) < 0.25 {
                            let key = Int(mk.u.rounded())
                            if let v = arrowSm[key] { smNew[key] = v }; if let v = spinSm[key] { spinNew[key] = v }
                            if let v = curveSpin[key] { curveNew[key] = v }; if let v = arrowRoll[key] { rollNew[key] = v }
                            continue
                        }
                    }
                    let k = mk.k, kc = k   // kc：並びの中の位置（0 手前 〜 1 先頭）
                    var bk = 0.0                                              // この矢印のあたり（前後 4 点）の曲がり具合
                    for t in max(0, j - 3)...min(pl.count - 1, j + 4) { bk = max(bk, bend[t]) }
                    let curv = smoothstep(0.006, 0.03, bk)                    // 1 点（0.02）で 0.35°〜1.7° 曲がる所から
                    let wave = pow(0.5 + 0.5 * cos(2 * .pi * (mk.u / 4 - now * 2.0)), 6)   // 手前から奥へ走る光（並びの 4 つおきに、1 秒に 2 回）
                    // 寄った時は、まっすぐな所でも光が手前から奥へ走る（先導する感じ。カーブではもっと強く）
                    //   寄った時（鎖のように道の上に止まった羽）は、光を走らせない（光が走ると、羽が流れて見える）
                    //   寄った時は、羽はうっすら灯っていて、光の粒が手前から先へ走り抜ける（羽は止まったまま、光だけが進む）。
                    //   ふだんからほんのり光っている（光が来るとさらに明るく）
                    //   滑走路の誘導灯のように：光の粒が 1 つ、手前から先へなめらかに走り抜けて（1.1 秒）、少し休む（全部で 1.8 秒）。
                    //   光の前はすっと明るくなり、後ろは尾を引いてゆっくり消える（ぱっぱっと点く看板のようにしない）
                    // ドミノのスピン（寄った時）。光ってスピンする所は同じ：矢印の光の強さは、その矢印が回る速さで決める（回っている間だけ光る。ぴったり同期）
                    var spinAng = 0.0, spinVel = 0.0
                    if march {
                        // ドミノのスピン：誘導灯の光の粒がこの矢印に届くと、進む向きのまわりにくるっと半回り（約 0.4 秒）。
                        //   光と一緒に、手前の矢印から順に回っていく。「»」は半回りで元と同じ形なので、回り終わったらそのまま次の光を待つ
                        //   回り方は風に吹かれるように：矢印ごとのやわらかいばねで追う（少し行き過ぎて、ゆらっと戻る）。さらに小さくそよぐ
                        let cyc = domC.rounded(.down), head = (domC - cyc) * 1.8 / 1.1 * 1.15 - 0.05
                        let skey = Int(mk.u.rounded())
                        // カーブで自分から回る（自律スピン）：道が曲がっている所の矢印は、曲がる向きへ回り続ける（右へ曲がる所は右回り、左は左回り。
                        //   上下に曲がる時もその向きで）。速さは曲がりの強さで（ゆるいカーブはゆっくり、急カーブで約 1.1 秒に 1 回り）。まっすぐな所は止まる。
                        //   回り方の選び：0 拍（音のうなりのドミノ）・1 カーブ・2 両方
                        var ex = curveSpin[skey] ?? 0
                        if st.spinMode != 0 {
                            // 曲がる向き：少し手前と少し先の道の向き（画面の 3D）の回る軸が、画面の奥を向くか手前を向くか
                            let qa4 = seg(max(0, d - 0.03)).0, qb4 = seg(min(total, d + 0.03)).0
                            let qa = place(simd_normalize(qa4)).0, qb = place(simd_normalize(qb4)).0
                            let ax = simd_cross(q - qa, qb - q), sg = simd_dot(ax, Bv) >= 0 ? 1.0 : -1.0
                            let strength = smoothstep(0.004, 0.03, bk)
                            ex += sg * 2 * .pi * (0.25 + 0.65 * strength) * strength * dtA
                        }
                        curveNew[skey] = ex
                        let xs0 = head - kc
                        var target = (st.spinMode == 1 || st.spinMode >= 3 ? 0 : .pi * (cyc + smoothstep(-0.12, 0.3, xs0))) + ex
                        // 波：傾きがサインカーブの波になって、手前から先へ伝わる（拍 2 つで 1 波。振れ幅・波長はパラメーター）。
                        // らせん：1 枚ごとに少しずつねじれて並び（DNA のように）、鎖全体が拍に合わせて回り続ける
                        if st.spinMode == 3 { target = st.spinAmp * .pi / 180 * sin(2 * .pi * (domC - mk.u / max(1, st.spinLen))) }
                        if st.spinMode == 4 { target = mk.u * st.spinAmp * .pi / 180 + 2 * .pi * domC * st.spinLen * 0.1 }
                        // 進路：今走っている向きと、その矢印の所の道の向きの角度で寝かせ方を決める（平行なら垂直に立って薄い板に、直角なら水平に寝て面が見える。間はなめらかに）。
                        //   遠くのまっすぐ先の板ほど薄く見え、自分が進んで向きが変わると、矢印が次々に起き上がったり寝たりする。完全に垂直だと厚みゼロで消えるので、少し手前まで
                        //   進路 B（6）はその逆：平行なら寝て面が見え、直角なら立って線に見える（遠くでカーブしている板ほどひねったテープのように薄く）
                        if st.spinMode == 5 || st.spinMode == 6, let cx = cX {
                            let qa4 = seg(max(0, d - 0.004)).0, qb4 = seg(min(total, d + 0.004)).0
                            var tg = place(simd_normalize(qb4)).0 - place(simd_normalize(qa4)).0; tg -= Bv * simd_dot(tg, Bv)
                            if simd_length(tg) > 1e-9 { let th = acos(min(1, abs(simd_dot(simd_normalize(tg), cx)))); target = 0.72 * (st.spinMode == 5 ? .pi / 2 - th : th) }
                        }
                        var ss = spinSm[skey] ?? (target, 0)
                        if abs(target - ss.r) > 1.5 * .pi { ss.r += .pi * ((target - ss.r) / .pi).rounded() }   // 拍の数えが飛んだ時（音が鳴り始めた時など）は、半回り単位で追いつかせる（くるくる回らない）
                        let sw = 6.5, sz = 0.35, sn = max(1, Int(ceil(dtA / 0.008))), sh = dtA / Double(sn)
                        for _ in 0..<sn { ss.v += (sw * sw * (target - ss.r) - 2 * sz * sw * ss.v) * sh; ss.r += ss.v * sh }
                        spinNew[skey] = ss
                        let breeze = 0.1 * sin(2 * .pi * 0.6 * now + 1.9 * mk.u) + 0.05 * sin(2 * .pi * 1.3 * now + 0.7 * mk.u)
                        spinAng = ss.r + breeze; spinVel = ss.v
                    }
                    let neon: Double = {
                        let head = (domC - domC.rounded(.down)) * 1.8 / 1.1 * 1.15 - 0.05   // 光の先頭（並びの位置 k、0 手前〜1 先）
                        let x = head - kc                                                        // 光の先頭からの距離（＋：先頭より手前）
                        // 白い光は拍のドミノと同じ：先頭が来た板だけがぱっと光って、すぐ落ち着く（短いきらめきが 1 枚ずつ先へ伝わる。前後の板は暗いまま）
                        let byLight = x >= 0 ? exp(-x / 0.055) : exp(-x * x / 0.0009)
                        if march && mark == 0 { return max(byLight, smoothstep(0.8, 7, abs(spinVel))) }   // 立体の矢印：走る光に加えて、回っている板も光る（拍のドミノでは同じ時に）
                        return byLight
                    }()
                    let lit = march ? 0.55 + 2.3 * neon : (1 - 0.55 * curv) + 2.8 * curv * wave
                    // 先へ行くほど消える（フェードアウト）。カーブの所は、曲がる先まではっきり見せる（消え方を弱める）
                    let keep = 1 - 0.35 * curv                                         // 先の方はだんだん薄く消える（最初の形のように）。カーブの所だけ少しゆるく
                    // 「道を全部」の時は、先の方も淡くしない（左上の地図のように、道の終わりの先端まで描き切る）
                    let allWay = march && st.planLong
                    var al = Float(mk.fade * (1 - smoothstep(0.55, 1.0, k) * keep * (allWay ? 0 : 1)) * (0.4 + 0.6 * face) * lit)
                    if march { al *= Float(1 - (allWay ? 0 : 0.55) * smoothstep(0.3, 1.0, k) * keep) }
                    if march && mark == 0 { al *= Float((1 + 0.7 * smoothstep(0.1, 0.8, k) * smoothstep(0.03, 0.12, mk.sp)) * (0.6 + 0.4 * smoothstep(0, 0.3, k))) }   // 自分のすぐ手前の板は少し暗め（明るすぎない）   // 立体の矢印：先端の方（奥の小さい矢印）ほど濃く（遠くまで線がくっきり続く）   // 寄った時は、先へ行くほどしっかり淡く（遠近。先はほとんど消える）
                    else { al *= Float(min(1.3, max(0.35 + 0.4 * curv, pow(nearC / max(1e-4, near(q)), 1.2)))) }   // 外から見る時も、奥の矢印ほど淡く
                    // 急カーブ（曲率半径が小さい所）：矢印を朱色寄りに、二重の「≫」にして、遠くても小さくはっきり（消えにくく）
                    let tight = smoothstep(0.03, 0.09, bk)
                    if tight > 0 { al = max(al, Float(0.55 * tight * mk.fade * (0.4 + 0.6 * face))) }
                    var colW = curv * wave > 0.3 ? simd_mix(col, SIMD4<Float>(1, 0.95, 0.8, 1), SIMD4(repeating: Float(min(1, curv * wave)))) : col   // 光った矢印は白っぽく
                    if tight > 0 { colW = simd_mix(colW, SIMD4<Float>(1, 0.42, 0.22, 1), SIMD4(repeating: Float(0.65 * tight * (1 - 0.6 * wave)))) }
                    // ほんのり軸の色：粒のある所（4D の x・y・z・w のどの向きに近いか）に合わせて、軸の色を少し混ぜる（進むと色合いがゆっくり移る）
                    if mark == 2 {
                        let p4 = q4 / l, w2 = p4 * p4, ac = Self.axisCol
                        var t: SIMD3<Float> = ac[0] * Float(w2.x)
                        t += ac[1] * Float(w2.y); t += ac[2] * Float(w2.z); t += ac[3] * Float(w2.w)
                        colW = simd_mix(colW, SIMD4(t, 1), SIMD4(repeating: Self.beadAxisTint))
                    } else if mark == 0 && st.planShell {
                        // 矢印：その場所の球殻の色の蛍光色で光る（色をいちばん明るく・あざやかにして、白を少し混ぜた強めの光）
                        let t = Self.shellTint(q4 / l, st.shellModeNow), mx = max(t.x, max(t.y, t.z)), v = t / max(0.001, mx)
                        let gray = (v.x + v.y + v.z) / 3, vivid = simd_clamp(SIMD3(repeating: gray) + (v - SIMD3(repeating: gray)) * 1.6, SIMD3(repeating: 0), SIMD3(repeating: 1))
                        colW = SIMD4(simd_mix(vivid, SIMD3(repeating: 1), SIMD3(repeating: 0.1)), 1); al *= 1.25
                    } else if mark == 0 {
                        // 矢印：手前から奥へ、軸の 4 色（x 赤 → y 緑 → z 青 → w 紫）がほんのりグラデーションでつながる
                        let ac = Self.axisCol, g = min(2.999, max(0, kc * 3)), gi = Int(g), gf = Float(g - Double(gi))
                        let t = simd_mix(ac[gi], ac[gi + 1], SIMD3(repeating: gf))
                        colW = simd_mix(colW, SIMD4(t, 1), SIMD4(repeating: Self.beadAxisTint))
                    }
                    if march { colW = simd_mix(colW, SIMD4<Float>(1, 1, 1, 1), SIMD4(repeating: Float(0.06 + 0.9 * neon))) }   // 寄った時：ふだんから少し白く光り、光が来た所はしっかり白く
                    if al > 0.01 {
                        // 大きさの遠近：寄った時は 3D のまま。外から見る時も、彗星より手前の矢印ほど大きく、奥ほど小さく（少し強めに）
                        //   外から見る時（左上の地図など）：矢印は 3D でだいたい同じ大きさの物として（彗星のそばの大きさがもと）、カメラから遠いほど必ず小さく。
                        //   奥の矢印はさらに少し小さく（遠近の演出）。前は 4D の写り方の大きさを使っていて、奥の矢印の方が大きく見えることがあった
                        let deep = pow(min(1, ecd / max(1e-4, simd_length(eye - q))), 0.7)   // 寄った時：カメラから遠いほど、3D の遠近よりさらに小さく
                        var hs = (march ? 0.16 * ecd * max(0.4, deep) : 0.085 * nearC * dive * min(1.8, max(0.3, pow(nearC / max(1e-4, near(q)), 0.6))))   // 矢印は大きさを変えない（光だけが進む。矢印そのものが飛んでいくようには見せない）
                        // カメラのすぐ前に来た矢印（カメラと彗星の間。4D の写り方でカメラの近くへ来る所）：大きくなりすぎず、淡く消す
                        let de = simd_length(eye - q)
                        //   大きさは、道の先へ行くほど必ず小さく（4D の写り方でカメラの近くへ来ても、先の矢印が大きくならない）
                        if march { hs = min(hs, 0.1 * de, 0.16 * ecd / (1 + 1.2 * k)); al *= Float(smoothstep(0.35 * ecd, 0.75 * ecd, de)) }
                        // 矢印は S³ の上に寝かせる：進む向き t4 と横の向き n4（どちらも 4D の、その点の接する向き）で形を作って、画面の 3 次元へ写す。
                        //   写した形のゆがみ（見る角度で斜めにつぶれる・伸びる）はそのまま、大きさだけ hs にそろえる
                        let p4 = q4 / l
                        var t4 = pl[min(pl.count - 1, j)] - pl[j - 1]; t4 -= p4 * simd_dot(t4, p4)
                        let tl4 = simd_length(t4)
                        if tl4 > 1e-12 {
                            t4 /= tl4
                            // 横の向き n4：その点の接する向きのうち、進む向きに垂直な 2 つ（e1・e2）を組み合わせて、画面の上でいちばん広く見える向きに
                            //   （横から見て線のようにつぶれない。形のゆがみ・大きさの遠近はそのまま）
                            let e = march ? 0.0005 : 0.01
                            func at(_ v: SIMD4<Double>) -> SIMD3<Double> { place(simd_normalize(p4 + v * e)).0 - q }
                            let ax: [SIMD4<Double>] = [SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)]
                            var basis: [SIMD4<Double>] = []
                            for a0 in ax where basis.count < 2 {
                                var v = a0 - p4 * simd_dot(a0, p4) - t4 * simd_dot(a0, t4)
                                for b0 in basis { v -= b0 * simd_dot(v, b0) }
                                let vl = simd_length(v); if vl > 0.3 { basis.append(v / vl) }
                            }
                            var n4 = side4 ?? SIMD4<Double>()
                            if basis.count == 2 && march && mark == 0 { n4 = basis[0] }   // 立体の矢印は横の向きを平行移動で決めるので、ここは何でもよい（計算を省く）
                            else if basis.count == 2 {
                                let xs = at(t4), want = simd_cross(Bv, xs)              // 画面の上で、進む向きに垂直な向き
                                let c1 = simd_dot(at(basis[0]), want), c2 = simd_dot(at(basis[1]), want)
                                if abs(c1) + abs(c2) > 1e-12 { n4 = basis[0] * c1 + basis[1] * c2 }
                            }
                            n4 -= p4 * simd_dot(n4, p4); n4 -= t4 * simd_dot(n4, t4)
                            let nl = simd_length(n4)
                            if nl > 1e-9 {
                                n4 /= nl; side4 = n4
                                var X3 = at(t4), Y3 = at(n4); var k = hs / max(1e-9, max(simd_length(X3), simd_length(Y3)))
                                if march && mark != 0 {                                  // 立体の矢印は道の接線と平行移動で向きを決めるので、前の羽の向きの計算は飛ばす
                                    // 寄った時（ダイブ）：S³ のゆがみは使わず、ふつうの 3D の空間で（向きは画面の上の道の向き、大きさは 3D の距離だけで決まる）
                                    var xs = simd_normalize(X3)
                                    // 先読み：矢印は、少し先（S³ の上で 0.05 先）の道の所を指す（曲がる手前から、曲がる側へ向いて導く）
                                    let (qa4, _) = seg(min(total, d + 0.08)), qal = simd_length(qa4)
                                    if qal > 1e-9 { var ch = place(qa4 / qal).0 - q; ch -= Bv * simd_dot(ch, Bv); if simd_length(ch) > 1e-9 { xs = simd_normalize(xs * 0.3 + simd_normalize(ch) * 0.7) } }
                                    // 強く導く：引っぱる所より手前の矢印は、その点へまっすぐ向く（一直線に引っぱられる）。その先は道の向き
                                    if let ap = aimP, d < dAim - 0.01 {
                                        var tv = ap - q; tv -= Bv * simd_dot(tv, Bv)
                                        if simd_length(tv) > 1e-9 { xs = simd_normalize(tv) }
                                    }
                                    if let cx = cX {
                                        // 先導の重み：彗星のすぐ前（S³ の上で 0.04 まで）で、今の向きから引っぱる向きへ切りかわる（変化はそこで終わる）
                                        let wgt = smoothstep(0, 0.04, d)
                                        let bl = cx * (1 - wgt) + xs * wgt; if simd_length(bl) > 1e-9 { xs = simd_normalize(bl) }
                                        // 先頭（奥）の矢印ほど、今の向きからの変わり方を大きく（変化率が高い。いちばん大きくて 83°）
                                        let cy = simd_cross(Bv, cx), th = atan2(simd_dot(xs, cy), simd_dot(xs, cx)), th2 = max(-1.45, min(1.45, th * (1 + 1.5 * kc)))
                                        xs = simd_normalize(cx * cos(th2) + cy * sin(th2))
                                    }
                                    // 向きの変わり方はアナログ（道の向きからのずれを、矢印ごとにスピードメーターの針のようなばねで追う。すっと動いて少し行き過ぎ、ふわっと止まる）
                                    var xp = X3 - Bv * simd_dot(X3, Bv)
                                    if simd_length(xp) > 1e-12 {
                                        xp = simd_normalize(xp)
                                        let yp = simd_cross(Bv, xp), dev = atan2(simd_dot(xs, yp), simd_dot(xs, xp)), key = Int(mk.u.rounded())
                                        var sm = arrowSm[key] ?? (dev, 0, 0, 0); needle(&sm.dev, &sm.dv, dev, mi)
                                        smNew[key] = sm
                                        xs = simd_normalize(xp * cos(sm.dev) + yp * sin(sm.dev))
                                    }
                                    // 横の向き：ふだんは水平（彗星の右の向き）。進む向きに直角にして、「＞」が飛ぶ向きに対して水平に寝る。
                                    //   水平の面がちょうど真横から見える時（線のように細くなる時）は、少しだけ画面の方へ起こす
                                    var ys = simd_cross(Bv, xs)
                                    // 水平の向き：画面から見ていちばん落ち着く水平（画面の上の向きに直角で、進む向きにも直角）。彗星やカメラが回っても、羽がふらつかない。
                                    //   進む向きが画面の上下に近い時（水平が決まらない時）は、画面に向く向きへなめらかに寄せる
                                    //   （進む向きは画面に写す前の 3D の向きで考える。画面に写した向きで考えると、水平が奥行きの向きになって羽が線のように細くなる）
                                    let F3 = simd_length(X3) > 1e-12 ? simd_normalize(X3) : xs
                                    let hz = simd_cross(F3, Uv3), hl = simd_length(hz)
                                    if hl > 1e-6 {
                                        var h = hz / hl; h -= xs * simd_dot(h, xs)
                                        if simd_length(h) > 1e-6 {
                                            h = simd_normalize(h)
                                            let f = simd_normalize(ys), face = abs(simd_dot(simd_cross(xs, h), Bv))   // 羽の面がどれだけ画面に向いているか
                                            let ok = smoothstep(0.04, 0.14, face) * smoothstep(0.1, 0.3, hl)   // ほとんど真横から見える時だけ起こす（ふだんは水平に寝かせる）
                                            let b = h * ok + f * (1 - ok) * (simd_dot(h, f) >= 0 ? 1 : -1)
                                            if simd_length(b) > 1e-9 { ys = simd_normalize(b) }
                                        }
                                    }
                                    // 水平の軸はゆっくり追いかける：羽の傾き（進む向きのまわりの回り）を、羽ごとにばねでなめらかに（急な切りかえで軸がふらつかない）。
                                    //   羽は左右対称なので、半回転（π）ちがいは同じ傾きとして扱う
                                    let r0 = simd_cross(Bv, xs)
                                    if simd_length(r0) > 1e-9 {
                                        let r0n = simd_normalize(r0), n0 = simd_cross(xs, r0n), rk = Int(mk.u.rounded())
                                        var phi = atan2(simd_dot(ys, n0), simd_dot(ys, r0n))
                                        var rs = arrowRoll[rk] ?? (phi, 0)
                                        while phi - rs.r > .pi / 2 { phi -= .pi }
                                        while phi - rs.r < -.pi / 2 { phi += .pi }
                                        let w = 3.5, nn = max(1, Int(ceil(dtA / 0.008))), hh = dtA / Double(nn)
                                        for _ in 0..<nn { rs.v += (w * w * (phi - rs.r) - 2 * w * rs.v) * hh; rs.r += rs.v * hh }
                                        rollNew[rk] = rs
                                        ys = r0n * cos(rs.r) + n0 * sin(rs.r)
                                    }
                                    let yl = simd_length(ys)
                                    if yl > 1e-9 { X3 = xs; Y3 = ys / yl; k = hs }
                                }
                                let bendHere = max(bend[max(0, j - 1)], bend[min(pl.count - 1, j)])
                                var ang = 0.0, bankOnly = 0.0
                                // くるっと回すのはやめた（速すぎて点滅に見える）。代わりに、いちばんきつく曲がる所の矢印は、車の方向指示器のように
                                //   ゆっくりやわらかく明るくなったり暗くなったりする（1 秒に 1 回ほど。「こっちへ曲がりますよ」）
                                if curv > 0.3 && bendMax > 0.006 && bendHere > 0.6 * bendMax {
                                    let blink = 0.5 + 0.5 * sin(now * 2 * .pi * 1.0)              // そろって明るくなる（ずらすと流れて見える）
                                    al *= Float(0.55 + 0.75 * blink * blink)
                                }
                                // 3D の傾き（ダイブ）：飛行機が曲がる時のように、矢印をその所の曲がりへ傾ける。曲がり具合は少し手前と少し先の道の向きの差
                                //   （その矢印の所の曲がりに合わせるので、軌道が少しずつちがう矢印が、なめらかにつながって傾く）
                                // 奥の小さな板（カメラ距離の 6 倍より遠い立体の矢印）は、曲がる所の傾きを求めない（見た目では分からない。計算を省く）
                                if march && !(mark == 0 && simd_length(eye - q) > 6 * ecd) {
                                    func dir(_ dd: Double) -> SIMD3<Double>? {
                                        let (a4, _) = seg(max(0, min(total, dd))), b4 = seg(max(0, min(total, dd + 0.01))).0, la = simd_length(a4), lb = simd_length(b4)
                                        guard la > 1e-9, lb > 1e-9 else { return nil }
                                        var v = place(b4 / lb).0 - place(a4 / la).0; v -= Bv * simd_dot(v, Bv); let l = simd_length(v); return l > 1e-12 ? v / l : nil
                                    }
                                    if let t0 = dir(d - 0.03), let t1 = dir(d + 0.03) {
                                        // 傾く大きさは S³ の上で本当に曲がる量で（まっすぐな道は、4D の写り方で曲がって見えても傾けない）。向き（左右）だけ画面の上で決める
                                        let turnS = atan2(simd_dot(simd_cross(t0, t1), Bv), simd_dot(t0, t1))
                                        var g = 0.0; for t in max(1, j - 2)...min(pl.count - 2, j + 2) { g = max(g, bend[t]) }
                                        let turnG = g * 3                                                  // 0.06 進む間に曲がる角度（1 点 0.02 ごとの角度 × 3）
                                        let bk = max(-1.1, min(1.1, -(turnS >= 0 ? 1 : -1) * turnG * 6))
                                        let key = Int(mk.u.rounded())                                     // 傾きも針のようなばねで
                                        var sm = smNew[key] ?? arrowSm[key] ?? (0, bk, 0, 0); needle(&sm.bank, &sm.bv, bk, mi); smNew[key] = sm
                                        ang += sm.bank * smoothstep(0.08, 0.45, kc)                        // 近くの羽ほど水平のまま（動きが少ない）
                                        bankOnly = 0.6 * ang                                               // 立体の矢印は、曲がる所でこの傾きだけ（少し控えめに）
                                        // 遠くの羽は、ときどきくるんとひっくり返って戻る（7 秒ごとに 2.6 秒かけて。サインカーブでやわらかく。遠いほど大きく）
                                        let ft = now.truncatingRemainder(dividingBy: 7.0)
                                        if ft < 2.6 { let fw = smoothstep(0.55, 0.9, kc); ang += fw * .pi * pow(sin(.pi * ft / 2.6), 2) }
                                        // メビウスの輪のように、先へ行くほど少しずつよじれる（手前は水平、見える所の先までで半回転）。
                                        //   よじれは彗星からの道のり（並びの位置 kc）で決まるので、羽が近づくにつれて、なめらかにほどけて水平になる
                                        ang += .pi * smoothstep(0.08, 0.95, kc)
                                    }
                                }
                                if ang != 0 {
                                    let lx = simd_length(X3), ly = simd_length(Y3)
                                    if lx > 1e-12 && ly > 1e-12 {
                                        let xh = X3 / lx, yh = Y3 / ly, zh = simd_normalize(simd_cross(xh, yh))
                                        Y3 = (yh * cos(ang) + zh * sin(ang)) * ly
                                    }
                                }
                                // 矢印は「»」の 1 つを前後に引きのばした形（形はシェーダーの kind 12。q.xy：板の上の位置）
                                func chevron(_ ox: Double, _ a: Float) {
                                    let x0 = -0.4 - 0.2, x1 = 0.58 + 0.2, y1 = 0.6
                                    func cv(_ x: Double, _ y: Double) -> HLCometVert {
                                        HLCometVert(p: SIMD4(SIMD3<Float>(q + X3 * ((x + ox) * k) + Y3 * (y * k)), 1), q: SIMD4(Float(x), Float(y), 12, a), c: colW)
                                    }
                                    ctri += [cv(x0, -y1), cv(x1, -y1), cv(x1, y1), cv(x0, -y1), cv(x1, y1), cv(x0, y1)]
                                }
                                if mark == 0 && march && j < nf.count {
                                    // 寄った時：厚みのある立体の「»」。前の向きは道の線の接線、横の向きは平行移動で運んだ向き。
                                    //   面ごとの明るさ（カメラの左上手前からの光、やわらかく）で立体に見せる。色は青白にほんのり軸の色。カメラから見えない裏の面は描かない
                                    // 前の向き：画面に描かれた道の線の接線（道の点を 3D へ写した曲線を微分した向き。すぐ前とすぐ後ろの点の差で）。
                                    //   矢印の中心の軸が道の線に乗り、線が曲がって見える所でも線に沿ってそろう（導く向きへ回すのは、立体の矢印ではしない）
                                    let qa4 = seg(max(0, d - 0.004)).0, qb4 = seg(min(total, d + 0.004)).0
                                    var Xf = place(simd_normalize(qb4)).0 - place(simd_normalize(qa4)).0
                                    if simd_length(Xf) < 1e-12 { Xf = at(t4) }
                                    Xf = simd_normalize(Xf)
                                    // 奥行きの成分だけ弱める（画面の上の向きは接線のまま、線に沿ってそろう）。道が奥へ向かう所でも、後ろから見た細い形にならない
                                    //   （奥行きは、カメラからこの点への見る線の向きで測る。遠近のある画面でも、写った向きが線の接線からずれない）
                                    let ray = simd_normalize(q - eye), dz = simd_dot(Xf, ray); Xf = simd_normalize(Xf - ray * dz * 0.65)
                                    let ca = cum[j - 1], cb = cum[j], fs = cb > ca ? max(0, min(1, (d - ca) / (cb - ca))) : 0
                                    var Yv = at(nf[j - 1] * (1 - fs) + nf[j] * fs); Yv -= Xf * simd_dot(Yv, Xf)
                                    if simd_length(Yv) > 1e-12 {
                                        var Yh = simd_normalize(Yv), Nh = simd_cross(Xf, Yh)
                                        let spin = spinAng
                                        // 鎖全体の回し：いちばん手前の矢印の面が画面に向くように、全部の矢印を同じ角だけ回す（矢印どうしの向きの関係は平行移動のまま）。
                                        //   その角はばねでゆっくり追う。「»」は半回りで同じ形なので、半回りちがいは同じとして扱う
                                        if rollRef == nil {
                                            let want = simd_normalize(simd_cross(simd_normalize(q - eye), Xf))
                                            var phi = atan2(simd_dot(simd_cross(Yh, want), Xf), simd_dot(Yh, want))
                                            var rs = planRoll ?? (phi, 0)
                                            while phi - rs.r > .pi / 2 { phi -= .pi }
                                            while phi - rs.r < -.pi / 2 { phi += .pi }
                                            let w = 2.5, nn = max(1, Int(ceil(dtA / 0.008))), hh = dtA / Double(nn)
                                            for _ in 0..<nn { rs.v += (w * w * (phi - rs.r) - 2 * w * rs.v) * hh; rs.r += rs.v * hh }
                                            if rs.r > 2 * .pi { rs.r -= 2 * .pi } else if rs.r < -2 * .pi { rs.r += 2 * .pi }
                                            planRoll = rs; rollRef = rs.r
                                        }
                                        let rollA = (rollRef ?? 0) + bankOnly + spin
                                        Yh = Yh * cos(rollA) + Nh * sin(rollA); Nh = simd_cross(Xf, Yh)
                                        let toEye = simd_normalize(eye - q), Lt = simd_normalize(Uv3 * 0.7 + toEye * 0.8 + simd_cross(Uv3, toEye) * 0.35)
                                        // 大きさは 3D の遠近だけ：どの矢印も 3D で同じ大きさ（カメラ距離の 0.07）の物として、カメラから遠いほど自然に小さく（手前から奥へ吸い込まれる）。
                                        //   カメラのすぐ前で大きくなりすぎないように。とても遠い所は点ほどに残す
                                        var ks = min(0.07 * ecd, 0.055 * simd_length(eye - q))
                                        ks = max(ks, 0.005 * simd_length(eye - q))
                                        //   道の先の方は 4D の写り方でカメラの方へ戻ってくることがある（3D では近くなって大きく見える）。
                                        //   道の先へ行くほど必ず小さくして、手前から奥へ遠ざかっていく 3D の遠近に見せる
                                        ks = min(ks, ksRun * 0.995); ksRun = ks
                                        //   となりの矢印との 3D の間隔でも抑える（道が 4D の写り方で縮む所では、矢印も一緒に小さく。重なって太い帯に見えない。
                                        //   先へ行くほど細く収束する 1 本の点線に）
                                        ks = min(ks, 0.6 * mk.sp / max(1, mk.dn) * ecd)   // 粗密で詰めた所も重ならない（重なると光が足し合わさって白く色が抜ける）
                                        func V(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { q + Xf * (x * ks) + Yh * (y * ks) + Nh * (z * ks) }
                                        // ほとんど 2 次元の矢印：薄いカード 1 枚に「»」の形（シェーダーの kind 12、ふちはなめらかで角は丸い）。
                                        //   向き・大きさ・回りは 3D のまま。面の明るさは光の当たり方でやわらかく
                                        // 陰影：2 本の腕を、進む向きのまわりに ±12° だけ折った面と考えて、それぞれの光の当たり方で明るさを変える
                                        let nf2 = simd_dot(Nh, toEye) >= 0 ? Nh : -Nh, fa = 0.21
                                        let nUp = simd_normalize(nf2 * cos(fa) + Yh * sin(fa)), nDn = simd_normalize(nf2 * cos(fa) - Yh * sin(fa))
                                        let bUp = 0.55 + 0.45 * max(0, simd_dot(nUp, Lt)), bDn = 0.55 + 0.45 * max(0, simd_dot(nDn, Lt)), bM = max(bUp, bDn)
                                        let cb = Float(bM)
                                        // 上の腕（シェーダーの y＞0）が明るい方になるように、横の向きを合わせる
                                        let upIsBright = bUp >= bDn
                                        let cw = SIMD4<Float>(colW.x * cb, colW.y * cb, colW.z * cb, Float(min(bUp, bDn) / bM))
                                        func cv2(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(V(x, upIsBright ? y : -y, 0)), 1), q: SIMD4(Float(x), Float(y), 12, al), c: cw) }
                                        ctri += [cv2(-0.6, -0.6), cv2(0.78, -0.6), cv2(0.78, 0.6), cv2(-0.6, -0.6), cv2(0.78, 0.6), cv2(-0.6, 0.6)]
                                    }
                                } else if mark == 0 {
                                    chevron(0, al)
                                    if tight > 0.2 { chevron(-0.6, al * Float(tight) * 0.85) }   // 急カーブ：少し後ろにもう 1 つ（≫）
                                } else {
                                    // 矢印の代わりに、光のビーズ（画面に向いた光の玉）。進む向きに長い楕円（長い向きが進む向きを教える）。寄った時も外から見る時も。
                                    //   画面に向いているので、向きの軸がふらつかない。外から見る時の大きさは hs（矢印の時と同じくらい）
                                    //   まっすぐな所ほど進む向きに伸びた楕円（勢いよく進む感じ）、曲がる所はまるい玉に縮む
                                    var xv = simd_length(X3) > 1e-12 ? X3 : at(t4); xv -= Bv * simd_dot(xv, Bv)
                                    let xn = simd_length(xv) > 1e-12 ? simd_normalize(xv) : simd_normalize(at(t4))
                                    let sd0 = simd_cross(Bv, xn)
                                    if simd_length(sd0) > 1e-9 {
                                        let sdn = simd_normalize(sd0), kon = mark == 2, ext = 1.9
                                        let rB = kon ? (march ? 0.15 * k : 0.45 * hs) : (march ? 0.13 * k : 0.3 * hs), el = kon ? 1 : 1 + (Self.beadStretch - 1) * (1 - curv)
                                        // 金平糖：まるいまま、ゆっくりくるくる回る（粒ごとに回り始めをずらす）
                                        let spin = kon ? now * 0.7 + mk.u * 1.3 : 0, ax = xn * cos(spin) + sdn * sin(spin), ay = sdn * cos(spin) - xn * sin(spin)
                                        let kind: Float = kon ? 16 : 15
                                        func bv(_ x: Double, _ y: Double) -> HLCometVert {
                                            HLCometVert(p: SIMD4(SIMD3<Float>(q + ax * (x * rB * el) + ay * (y * rB)), 1), q: SIMD4(Float(x), Float(y), kind, al), c: colW)
                                        }
                                        ctri += [bv(-ext, -ext), bv(ext, -ext), bv(ext, ext), bv(-ext, -ext), bv(ext, ext), bv(-ext, ext)]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let teal = SIMD3<Float>(0.06, 0.76, 0.94), ice = SIMD3<Float>(1.0, 0.93, 0.78)   // さんぽの印は青緑。彗星の頭は暖かい白（水色の殻に埋もれない）
        let discs: [(Double, SIMD4<Float>)] = real ? [] : comet
            ? [(0.085 * sc, SIMD4(ice, 0.28 * vis)), (0.045 * sc, SIMD4(ice, 0.8 * vis)), (0.022 * sc, SIMD4(1, 1, 1, vis))]   // 彗星の頭（玉より小さめ）
            : [(0.20 * sc, SIMD4(teal, 0.16 * vis)), (0.085 * sc, SIMD4(teal, vis)), (0.042 * sc, SIMD4(1, 1, 1, vis))]
        func rim(_ a: Double, _ rad: Double) -> SIMD3<Double> { let d: SIMD3<Double> = ax * cos(a) + ay * sin(a); return c + d * rad }
        for (rad, col) in discs {
            for k in 0..<24 {
                let a0 = Double(k) / 24 * 2 * .pi, a1 = Double(k + 1) / 24 * 2 * .pi
                for q in [c, rim(a0, rad), rim(a1, rad)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        if !comet && overview && st.autoCam && st.diveT > 0.3 && simd_length(st.camTan) > 0.5 {   // オートカメラの視点：カメラのいる方向の外に白い三角（中心を指す）。カメラが手前の側なら濃く、奥の側なら薄く
            let d3 = place(simd_normalize(pos + st.camTan * 0.03)).0 - c
            let dx = simd_dot(d3, ax), dy = simd_dot(d3, ay), dl = (dx * dx + dy * dy).squareRoot()
            if dl > 1e-9 {
                let ux: SIMD3<Double> = ax * (dx / dl) + ay * (dy / dl), px: SIMD3<Double> = ay * (dx / dl) - ax * (dy / dl)
                let col = SIMD4<Float>(1, 1, 1, (simd_dot(d3, fw) > 0 ? 0.95 : 0.5) * vis)
                let tip: SIMD3<Double> = c + ux * (0.215 * sc), base: SIMD3<Double> = c + ux * (0.35 * sc), half: SIMD3<Double> = px * (0.085 * sc)
                let tq: [SIMD3<Double>] = [tip, base + half, base - half]
                for q in tq { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        if !comet {                                                     // さんぽの印の三重の輪：外は青緑、内は白
            for (r0, r1, col) in [(0.165 * sc, 0.19 * sc, SIMD4(teal, 0.95 * vis)), (0.112 * sc, 0.128 * sc, SIMD4<Float>(1, 1, 1, 0.9 * vis))] {
                for k in 0..<48 {
                    let a0 = Double(k) / 48 * 2 * .pi, a1 = Double(k + 1) / 48 * 2 * .pi
                    for q in [rim(a0, r0), rim(a0, r1), rim(a1, r1), rim(a0, r0), rim(a1, r1), rim(a1, r0)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
                }
            }
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0
        if !tri.isEmpty {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
            tri.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        }
        if !ctri.isEmpty {                                              // 光の彗星：足し合わせ（重なるほど明るく、白く飛ぶ）
            e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
            ctri.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), Float(st.cometSpd), 0, 0)   // y：彗星の速さ（派手さ）
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ctri.count)
        }
    }
    /// ときどき彗星が画面の手前へ迫る強さ（0〜1）。たまにだけ（3 つのゆっくりした波が重なって強まる時。メリハリが大事）。
    ///   迫る間は、予定の道の矢印の間も詰めて見せる（望遠のように、奥行きが詰まって見える）
    private var surgeK: Double {
        guard side == .right, st.autoCam, !st.camHeld, dvThird > 0.3 else { return 0 }
        let t = nowT, zw = max(0, sin(t * 0.21) * sin(t * 0.53 + 0.7) * sin(t * 0.083 + 2.1))
        return smoothstep(0.3, 0.7, zw)
    }
    // 目印の色の候補：金・暖かい白・水色・青白・桃色・若葉
    static let beadPalette: [SIMD4<Float>] = [SIMD4(1.0, 0.78, 0.35, 1), SIMD4(1.0, 0.93, 0.8, 1), SIMD4(0.5, 0.9, 1.0, 1), SIMD4(0.75, 0.85, 1.0, 1), SIMD4(1.0, 0.68, 0.9, 1), SIMD4(0.65, 1.0, 0.7, 1)]
    static let beadAxisTint: Float = 0.3                                // 軸の色をどれだけ混ぜるか（ほんのり）
    static let beadStretch = Double(ProcessInfo.processInfo.environment["S3_BEAD"] ?? "") ?? 2.2   // 光のビーズの、まっすぐな所で進む向きに伸びる長さ（1 で球。確かめの絵でくらべる。曲がる所はまるくなる）
    private var planWAcc = 0.0, planWLast: Double? = nil               // 粗密：歩いたぶんの重みつきの道のり（矢印の並びのもと）と、前のコマの歩いた道のり
    private var curveSpin: [Int: Double] = [:]                       // 立体の矢印ごとの、カーブで自分から回った角
    private var spinSm: [Int: (r: Double, v: Double)] = [:]          // 立体の矢印ごとの、ドミノのスピンの回り（ばね。風に吹かれるように）
    private var planRoll: (r: Double, v: Double)? = nil                 // 立体の矢印の鎖全体の回し（ばね）
    private var planFrame: SIMD4<Double>? = nil                         // 立体の矢印の、道の始まりでの横の向き（平行移動で運ぶもと）
    private var arrowRoll: [Int: (r: Double, v: Double)] = [:]          // 予定の道の矢印ごとの、水平の軸の傾き（ばねでゆっくり追う）
    private var arrowSm: [Int: (dev: Double, bank: Double, dv: Double, bv: Double)] = [:], arrowSmT = 0.0   // 予定の道の矢印ごとの、向きのずれと傾き（とその速さ。スピードメーターの針のように、ばねで動く）
    private var marchGap = 0.0                                         // 寄った時の予定の道の矢印の間隔（S³ の道のり。ゆっくり合わせる）
    /// S³ の上で道が本当に曲がる角度（点 p で、a から来て b へ行く。大円＝S³ のまっすぐな道なら 0）。
    ///   となりの弦どうしの角度は、まっすぐな道でも歩幅ぶん（0.02 なら 0.02 rad）出てしまうので、p の接する向きにしてから比べる
    static func geoTurn(_ a: SIMD4<Double>, _ p: SIMD4<Double>, _ b: SIMD4<Double>) -> Double {
        let ta = a - p * simd_dot(a, p), tb = b - p * simd_dot(b, p), la = simd_length(ta), lb = simd_length(tb)
        guard la > 1e-12, lb > 1e-12 else { return 0 }
        return acos(max(-1, min(1, -simd_dot(ta, tb) / (la * lb))))
    }
    private var lastFov = 37.0, lastAsp = 1.0                          // 今の絵の縦の視野（度）と横÷縦（レンズフレアを画面の上に置くため）
    /// レンズフレア：天の川（さんぽと同じ y・z の大きな円）が画面に入ると、帯の上で画面の真ん中にいちばん近い所を光の元にして、
    ///   そこに光のにじみ、画面の真ん中をはさんだ反対側へ光の輪（色つき）が並び、横に光の筋。真ん中に近いほど強く、端から出ると消える。
    ///   ダイブの景色の時だけ（外から眺める時は出さない）。光の輪は、画面の手前の板（カメラの前）に置いて描く
    private func drawFlare(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let dz = side == .right ? Self.diveEase(dvT).1 : 0
        var best = 0.0, nx = 0.0, ny = 0.0
        for i in 0..<96 {
            let th = Double(i) / 96 * 2 * .pi, (q, face) = walkPlace(SIMD4(0, cos(th), sin(th), 0))
            let clip = u0.mvp * SIMD4<Float>(SIMD3<Float>(q), 1)
            guard clip.w > 1e-4 else { continue }
            let x = Double(clip.x / clip.w), y = Double(clip.y / clip.w), edge = max(abs(x), abs(y)), r0 = (x * x + y * y).squareRoot()
            let sc = (1 - smoothstep(0.85, 1.25, edge)) * (0.35 + 0.65 * (1 - smoothstep(0, 1.1, r0))) * (face + (1 - face) * dz)
            if sc > best { best = sc; nx = x; ny = y }
        }
        let vis = best * smoothstep(0.3, 0.9, dz)                         // ダイブの景色の時だけ（外から超球を見ている時は出さない）
        guard vis > 0.01 else { return }
        let (eye, Rv, Uv, Bv) = camBasis(), D = 0.5, ty = tan(lastFov * .pi / 360), tx = ty * lastAsp
        func at(_ x: Double, _ y: Double) -> SIMD3<Double> { eye - Bv * D + Rv * (x * tx * D) + Uv * (y * ty * D) }
        var vs: [HLCometVert] = []
        // (位置：中心から見て source の何倍か、大きさ（画面の縦の割合）、色、強さ、種類 8 光の輪・9 横の筋)
        let parts: [(Double, Double, SIMD3<Float>, Float, Float)] = [
            (1.0, 0.16, SIMD3(1.0, 0.92, 0.8), 0.55, 8), (1.0, 0.9, SIMD3(0.75, 0.85, 1.0), 0.32, 9),
            (0.55, 0.05, SIMD3(0.6, 0.5, 1.0), 0.22, 8), (0.25, 0.09, SIMD3(0.4, 1.0, 0.8), 0.14, 8),
            (-0.2, 0.035, SIMD3(1.0, 0.8, 0.4), 0.25, 8), (-0.45, 0.12, SIMD3(0.5, 0.7, 1.0), 0.12, 8),
            (-0.8, 0.06, SIMD3(1.0, 0.5, 0.8), 0.18, 8), (-1.25, 0.2, SIMD3(0.55, 1.0, 0.7), 0.1, 8)]
        for (t, sz, col, a, kind) in parts {
            let cx = nx * t, cy = ny * t, c = at(cx, cy), h = sz * ty * D, w = kind > 8.5 ? h * 1.0 : h, hh = kind > 8.5 ? h * 0.06 : h
            let al = Float(vis) * a * 0.4                                 // うーっすら
            func v(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + Rv * (x * w) + Uv * (y * hh)), 1), q: SIMD4(Float(x), Float(y), kind, al), c: SIMD4(col, 1)) }
            vs += [v(-1, -1), v(1, -1), v(1, 1), v(-1, -1), v(1, 1), v(-1, 1)]
        }
        var u = u0; u.model = matrix_identity_float4x4
        e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
        vs.withUnsafeBytes { b in e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
        var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0, 0, 0)
        e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vs.count)
    }
    /// 確かめの絵用：歩いた跡の代わり（無ければアプリのもの）
    var walkOverride: (() -> HyperLabState.Walk)?
    /// 歩いた跡などの読み口（確かめの絵では walkOverride、ふだんは 1 コマに 1 度・なめらかにした st.walkFrame）
    private var wsrc: (() -> HyperLabState.Walk)? {
        if let o = walkOverride { return o }
        guard HyperLabState.walkSource != nil else { return nil }
        return { [st] in st.walkFrame() ?? HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)) }
    }
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
        encode(e, CGSize(width: w, height: h)); e.endEncoding()
        if dvT > 0, let o2 = tex(.bgra8Unorm, false) { mirrorPass(cb, out, o2); cb.commit(); cb.waitUntilCompleted(); return readImage(o2, w, h) }   // ダイブ：鏡を広げて
        cb.commit(); cb.waitUntilCompleted()
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
        let ovFixed = ovMotion || naviM != nil                           // 2 枚の地図は、ドラッグの 3D の向きを使わない
        var yaw = side == .left || ovFixed ? 0 : st.viewYaw, pit = side == .left || ovFixed ? 0 : st.viewPitch, dist = side == .left ? st.leftDist : st.viewDist
        if side == .right && dvT > 0 {                              // ダイブ：見る向きは正面へ、3D のカメラは自分のいる所（原点）へ
            let (e1, e2) = Self.diveEase(dvT)
            // 一人称：見る向きは正面、背中へ寄る（近いほどゆっくり）。三人称：斜め後ろの少し上で止まって、自分（彗星）を追う
            // 三人称の斜め：鏡が広がるのに合わせて、真後ろを通って反対側へ回り込む（鏡と合わせて、見かけはずっと同じ側の斜め後ろ）
            let mw = smoothstep(0.52, 0.78, dvT), th = dvThird
            let ty = th * st.chaseYawS * (1 - 2 * mw) * .pi / 180, tp = th * st.chasePitchS * .pi / 180, td = 0.02 + (st.chaseDistS - 0.02) * th
            yaw += (ty - yaw) * e1; pit += (tp - pit) * e1; dist = td + (dist - td) * pow(1 - e2, 1.6)
            // オートカメラ（三人称の時だけ）とズーム中に回した分（自分のまわりを回る。離すと所定の角度へゆっくり戻る）
            yaw += (st.autoYaw * dvThird) * e1; pit += st.autoPitch * dvThird * e1
            // ときどき彗星が画面の手前へ迫る（カメラとの距離がぐっと縮まり、またゆっくり離れる。ゆっくりした 2 つの波が重なって強まる時だけ）
            dist *= 1 - 0.42 * surgeK * dvThird * e1
            dist *= 1 + (st.showDist - 1) * dvThird * e1                   // ショーカメラの寄り・引き
            yaw += st.diveYawOff * e1; pit = max(-1.45, min(1.45, pit + st.divePitchOff * e1))
        }
        var eye = SIMD3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit)) * dist
        let f = simd_normalize(-eye), up = SIMD3<Double>(0, 1, 0)
        var r = simd_normalize(simd_cross(f, up)), uu = simd_cross(r, f)
        if side == .right && dvT > 0 && focusW > 0 {
            // 見せ場：行き先が画面の真ん中寄りに来るよう、カメラを行き先の側へずらす（彗星は反対側の空いた所へ。左右・上下どこでも）。
            //   行き先がちょうど彗星の真後ろに重なる時は、彗星を下へずらす
            var dd = r * simd_dot(focusDir, r) + uu * simd_dot(focusDir, uu) * (st.camShow ? 0.35 : 1)   // ショーカメラは上下へはあまりずらさない（彗星が画面の下へ寄りすぎない）
            let dl = simd_length(dd)
            dd = dl > 0.25 ? dd / dl : simd_normalize(dd + uu * (0.25 - dl) * 4)
            eye += dd * (0.42 * dist * focusW)
        }
        if side == .right && dvT > 0 && dvThird > 0.3 && leadOff != SIMD3() {
            // カーブの揺れ：きつく曲がる時に、ときどき（ゆっくりした波で強まる時だけ）細かく揺れる。速いほど強く（スピード感）
            let t = CACurrentMediaTime()
            let turnK = smoothstep(0.06, 0.3, simd_length(leadOff)), spdK = 0.4 + 0.6 * st.cometSpd
            let burst = smoothstep(0.15, 0.6, (0.5 + 0.5 * sin(t * 0.9)) * (0.5 + 0.5 * sin(t * 0.37 + 1.3)) * 2)
            let a = 0.02 * dist * turnK * spdK * (0.25 + 0.75 * burst) * dvThird
            if a > 1e-6 {
                let jx = 0.6 * sin(t * 31) + 0.4 * sin(t * 47 + 1), jy = 0.6 * sin(t * 37 + 2) + 0.4 * sin(t * 53)
                eye += (r * jx + uu * jy) * a
            }
        }
        if side == .right && dvT > 0 && st.showFrame != .zero {
            // ショーカメラの構図：彗星を画面の左上・右上などへ（カメラの見る所を反対へずらす）
            eye -= (r * st.showFrame.x + uu * st.showFrame.y) * (dist * dvThird)
        }
        if side == .right && dvT > 0 && st.showRoll != 0 {
            // ショーカメラの斜め構え：カメラを少し傾ける
            let a = st.showRoll * dvThird, cb = cos(a), sb = sin(a)
            let r2 = r * cb - uu * sb, u2 = uu * cb + r * sb
            r = r2; uu = u2
        }
        if side == .right && dvT > 0 && (bank != 0 || leadOff != SIMD3()) {
            // オートカメラ：彗星が曲がる側へ先に流れる（カメラの見る所を反対へずらす）＋あとから曲がる側へ傾く
            let d = leadOff, sh = (r * simd_dot(d, r) + uu * simd_dot(d, uu) * (st.camShow ? 0.5 : 1)) * (0.55 * dist)
            eye -= sh
            let cb = cos(bank), sb = sin(bank)
            let r2 = r * cb - uu * sb, u2 = uu * cb + r * sb
            r = r2; uu = u2
        }
        return (eye, r, uu, -f)
    }
    func view3() -> simd_float4x4 {
        let (eye, r, uu, b) = camBasis(), f = -b
        let m = simd_double4x4(rows: [SIMD4(r, -simd_dot(r, eye)), SIMD4(uu, -simd_dot(uu, eye)), SIMD4(-f, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        return simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3))
    }
    /// 画面の形に合わせた縦の視野：横長の時は縦 fov のまま、縦長の時は横が fov になるよう広げる（幅と高さの狭い方に球が収まる。
    ///   仕切りで画面を広げると、球も自動で大きくなる）
    /// 右の超球の基本の視野：ふだんの距離（7.5）で、超球の輪郭（半径 ≈ 2.24）が画面の狭い方の 93% ほど（仕切りで広げると、ぎりぎりまで大きく）
    static let rightFov: Float = 37
    static func fitFov(_ fovDeg: Float, _ asp: Float) -> Float {
        guard asp < 1 else { return fovDeg }
        return 2 * atan(tan(fovDeg * .pi / 360) / max(0.05, asp)) * 180 / .pi
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
    private var lastFrame = -1, lastSize = CGSize.zero, sizeT = 0.0, offShown = false
    let big: Bool                                                    // ダイブで右に重ねる大きな画面か（小さい方は、その間は休む）
    #if os(macOS)
    weak var overlay: PoleOverlay?                                    // 景色の上の極（色の点と名前。さんぽの窓と同じ）
    #else
    weak var overlay: PoleOverlayIOS?
    #endif
    init(big: Bool) { self.big = big }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let r = HyperLabState.walkRendererGet?() else { return }
        if VideoExport.shared.rendering { return }                      // 動画を書き出している間は休む（さんぽの景色も書き出しに使うので）
        if !big && HyperLabState.walkBigShown { return }               // 右の大きな画面へ受け渡し中
        if HyperLabState.hyperIdle {                                     // 前の窓だけ描く：さんぽの窓が前の間はオフ（真っ暗を 1 回）
            if !offShown, let rpd = view.currentRenderPassDescriptor, let d = view.currentDrawable, let cb = r.queue.makeCommandBuffer() {
                rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                cb.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding(); cb.present(d); cb.commit(); offShown = true
            }
            return
        }
        if offShown { offShown = false; lastFrame = -1 }                  // 戻った：すぐ描き直す
        let low = HyperLabState.wipeLow && !big                         // 低負荷：画素は半分・1 秒 60 コマ（右に重ねる大きな画面はそのまま）
        HyperLabRenderer.fit(view, extra: low ? 0.5 : 1)
        // 静かモードの時は 30 コマ（画面の速さを割り切れる 30 以上のいちばん遅い速さ）
        let hz = max(60, view.window.flatMap { w -> Int? in
            #if os(macOS)
            return w.screen?.maximumFramesPerSecond
            #else
            return w.screen.maximumFramesPerSecond
            #endif
        } ?? 60)
        let fps = HyperLabState.quietNow && !big ? hz / max(1, hz / 30) : 60
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        let sz = view.drawableSize
        // さんぽが止まっていて（コマが進まない）も、出したばかり・大きさが変わったばかりの 0.6 秒は描き直す（最初の 1 枚が乱れたまま残らないように）
        let now = CACurrentMediaTime()
        if sz != lastSize { sizeT = now }
        if r.frameCount == lastFrame && sz == lastSize && now - sizeT > 0.6 { return }
        guard sz.width >= 8, sz.height >= 8, let rpd = view.currentRenderPassDescriptor, let d = view.currentDrawable, let cb = r.queue.makeCommandBuffer() else { return }
        lastFrame = r.frameCount; lastSize = sz
        r.encode(cb, rpd, view.colorPixelFormat, Int(sz.width), Int(sz.height))
        cb.present(d); cb.commit()
        var ls = r.poleLabels(aspect: Double(sz.width / max(1, sz.height)))   // 描いた時だけ（景色が変わった時）
        let en = HyperLabState.poleENNow
        if en { for i in ls.indices { ls[i].name = MapRenderer.poleNameToEN(ls[i].name) } }
        overlay?.serif = en; overlay?.update(ls)
    }
}
#if os(macOS)
struct WalkScenePane: NSViewRepresentable {
    var big = false
    final class Holder { let wipe: WalkWipe; init(_ b: Bool) { wipe = WalkWipe(big: b) } }
    func makeCoordinator() -> Holder { Holder(big) }
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: HyperLabState.walkRendererGet?()?.device ?? MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .rgba16Float; v.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)   // さんぽの窓と同じ（EDR）
        (v.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        v.framebufferOnly = true; v.preferredFramesPerSecond = 60; v.delegate = context.coordinator.wipe
        let po = PoleOverlay(frame: v.bounds); po.autoresizingMask = [.width, .height]; v.addSubview(po); context.coordinator.wipe.overlay = po
        return v
    }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct WalkScenePane: UIViewRepresentable {
    var big = false
    final class Holder { let wipe: WalkWipe; init(_ b: Bool) { wipe = WalkWipe(big: b) } }
    func makeCoordinator() -> Holder { Holder(big) }
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: HyperLabState.walkRendererGet?()?.device ?? MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm; v.framebufferOnly = true; v.preferredFramesPerSecond = 60; v.delegate = context.coordinator.wipe
        let po = PoleOverlayIOS(frame: v.bounds); po.autoresizingMask = [.flexibleWidth, .flexibleHeight]; po.isUserInteractionEnabled = false; v.addSubview(po); context.coordinator.wipe.overlay = po
        return v
    }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif
#if os(macOS)
struct HyperPane: NSViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState; var overview = false; var motion = false
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); context.coordinator.r?.overview = overview; context.coordinator.r?.ovMotion = motion; v.delegate = context.coordinator.r; return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct HyperPane: UIViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState; var overview = false; var motion = false
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); context.coordinator.r?.overview = overview; context.coordinator.r?.ovMotion = motion; v.delegate = context.coordinator.r; return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif

struct HyperLabView: View {
    @StateObject private var st = HyperLabState()
    @State private var last: CGSize = .zero
    @State private var pinch0: Double? = nil
    var body: some View {
        GeometryReader { full in
        VStack(spacing: 0) {
            // 並び：3 つの時は［左上・左下・右］、さんぽの景色を出さない時は［左・右］（order の順。⟳ で回す）
            let items = st.order.filter { ($0 != 1 || st.map2Now || (st.walkView && HyperLabState.walkRendererGet?() != nil)) && ($0 != 0 || st.show3D) }
            // 仕切りはドラッグで動かせる（位置は保存。ダブルクリックで半分に）。景色の画面を小さくすると、描く画素もそのぶん減って軽くなる
            GeometryReader { g in
                let W = max(1, g.size.width), H = max(1, g.size.height), bar: CGFloat = 5
                let lw: CGFloat = min(W - 140, max(140, W * CGFloat(st.splitX))), th: CGFloat = min(H - bar - 90, max(90, (H - bar) * CGFloat(st.splitY)))
                HStack(spacing: 0) {
                    if items.count == 1 { slot(items[0]) }                  // 4D の超球だけ
                    else if items.count == 3 {
                        VStack(spacing: 0) {
                            slot(items[0]).frame(height: th)
                            HLSplitBar(vertical: false, onDrag: { y in st.splitY = min(0.9, max(0.1, Double(y / H))) }, onReset: { st.splitY = 0.5 })
                            slot(items[1])
                        }.frame(width: lw)
                    } else { slot(items[0]).frame(width: lw) }
                    if items.count > 1 {
                        HLSplitBar(vertical: true, onDrag: { x in st.splitX = min(0.9, max(0.1, Double(x / W))) }, onReset: { st.splitX = 0.5 })
                        slot(items[items.count - 1])
                    }
                }
            }
            .coordinateSpace(name: "hlsplit")
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
            // 画面のゲームパッド（下の真ん中。パネルを隠していても出す）
            .overlay(alignment: .bottom) {
                if st.padOn, let r = HyperLabState.walkRendererGet?() {
                    VirtualPad(game: r.game) { st.padOn = false; r.game.vClear() }.spaceControls()
                        .padding(.bottom, 14).onAppear { r.set.gamepad = true }
                }
            }
            // さんぽメニュー（右上の少し下に浮かぶ。✕ で隠す。パネルの「さんぽメニュー」でまた出す）
            .overlay(alignment: .topTrailing) {
                // 閉じている時は、右上に小さな「さんぽ」ボタンだけ（押すとまた出る）
                if !st.walkMenu, HyperLabState.walkRendererGet?() != nil {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { st.walkMenu = true } } label: {
                        Label("さんぽ", systemImage: "figure.walk").font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.8), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                    }.buttonStyle(.plain).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0)).padding(.top, 74).padding(.trailing, 12)
                    .help("さんぽメニューを出す")
                }
                if st.walkMenu, let r = HyperLabState.walkRendererGet?() {
                    VStack(alignment: .trailing, spacing: 8) {
                        HLWalkMenu(r: r, close: { withAnimation(.easeInOut(duration: 0.15)) { st.walkMenu = false } }, openPanels: { st.walkPanelOn.toggle() }, panelsOn: st.walkPanelOn)
                        if st.walkPanelOn, HyperLabState.walkPanel != nil { HLWalkPanels(st: st) }
                    }.padding(.top, 74).padding(.trailing, 12)
                }
            }
            // パネルを隠している時：右下に小さな「パネル」ボタンだけ
            .overlay(alignment: .bottomTrailing) {
                if st.panelHidden {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden = false } } label: {
                        Label("パネル", systemImage: "slider.horizontal.3").font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.75), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).padding(12)
                    .help("パネルを出す（⌘⌥P）")
                }
            }
            if !st.panelHidden { HLScaled(s: CGFloat(st.uiScale), maxH: full.size.height * 0.42) { controls }.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        }
        // ⌘⌥P：パネルを隠す・出す（見えないボタンでキーだけ受ける）
        .background(Button("") { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden.toggle() } }.keyboardShortcut("p", modifiers: [.command, .option]).opacity(0).allowsHitTesting(false))
        // ⌘＋・⌘−・⌘0：パネルと隅の表示の大きさ
        .background(Button("") { st.zoomUI(1) }.keyboardShortcut("=", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(1) }.keyboardShortcut("+", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(-1) }.keyboardShortcut("-", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(0) }.keyboardShortcut("0", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
        .preferredColorScheme(.dark)
    }
    @ViewBuilder func slot(_ k: Int) -> some View {
        switch k {
        case 0:
            if st.diveOverview && (st.diveOn || st.diveT > 0) {
                pane(.right, "ナビ地図", overview: true).id(3)
            } else {
                pane(.left, "【操作側】3D の球（リングを積む）　ドラッグで傾ける・⇧＋横ドラッグで Z-W").id(0)
            }
        case 1:
            if st.map2Now { pane(.right, "W 地図", overview: true, motion: true).id(4) }
            else { walkPane.id(1) }
        default: pane(.right, "【観察側】4D の超球（球殻を積む）　ドラッグで見る向き").id(2)
        }
    }
    /// さんぽの景色（さんぽの窓と同じ景色。ここでは見るだけ。歩くのはさんぽの窓・コントローラーで）
    var walkPane: some View {
        ZStack(alignment: .topLeading) {
            WalkScenePane()
            HLHandoffNote(live: st.live)
            Text("【さんぽの景色】今いる所から見た S³（歩くのはさんぽの窓・コントローラーで）").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).allowsHitTesting(false)
        }
    }
    func pane(_ side: HyperLabRenderer.Side, _ tag: String, overview: Bool = false, motion: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            HyperPane(side: side, st: st, overview: overview, motion: motion)
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
                    } else if st.diveT > 0.05 && !overview {
                        // ズーム中：自分のまわりを回す（鏡に合わせて左右の向きをそろえる）。離すと所定の角度へゆっくり戻る
                        st.diveDragging = true
                        st.diveYawOff += Double(d.width) * 0.008 * (st.diveT > 0.65 ? 1 : -1); st.divePitchOff = max(-1.4, min(1.4, st.divePitchOff + Double(d.height) * 0.008))
                    } else {
                        st.viewYaw -= Double(d.width) * 0.008; st.viewPitch = max(-1.5, min(1.5, st.viewPitch + Double(d.height) * 0.008))
                    }
                    st.bump()
                }.onEnded { _ in last = .zero; st.diveDragging = false })
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
            if side == .right && !overview {
                HLDiveOverlay(live: st.live)                                  // ダイブの最後：さんぽの景色へ溶け込む
                HLAnglesLabel(live: st.live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8).allowsHitTesting(false)
                HLLapLabel(live: st.live, scale: CGFloat(st.uiScale)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)   // 周回（右上の隅に小さく）
                HLCoordLabel(live: st.live, scale: CGFloat(st.uiScale)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // 走行中の座標（左上）
            }
        }
    }
    var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ---- 4D 球を知る（このアプリの本体）----
            // 1 段目：見え方・画質（収まらない時は折り返す）
            HLWrap(spacing: 8) {
                Button(st.auto ? "停止" : "回転") { st.auto.toggle() }
                Button("初期位置") { st.reset() }
                HStack(spacing: 2) {
                    Button("A−") { st.zoomUI(-1) }.help("パネルを小さく（⌘−）")
                    Text(String(format: "%.0f%%", st.uiScale * 100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
                        .onTapGesture(count: 2) { st.zoomUI(0) }.help("パネルの大きさ（ダブルクリック・⌘0 で 100%）")
                    Button("A＋") { st.zoomUI(1) }.help("パネルを大きく（⌘＋）")
                }
                Button { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden = true } } label: { Label("パネルを隠す", systemImage: "rectangle.bottomthird.inset.filled") }
                    .help("パネルを隠して、画面いっぱいに超球と景色だけ（右下の「パネル」か ⌘⌥P で戻す）")
                Picker("", selection: Binding(get: { st.mode }, set: { st.mode = $0; st.bump() })) { Text("ハイブリッド").tag(0); Text("ワイヤー").tag(1); Text("半透明").tag(2) }
                    .pickerStyle(.segmented).frame(width: 240).labelsHidden()
                Picker("", selection: Binding(get: { st.hemi }, set: { st.hemi = $0; st.bump() })) { Text("全球").tag(0); Text("北").tag(1); Text("南").tag(2) }
                    .pickerStyle(.segmented).frame(width: 140).labelsHidden()
                Toggle("グレア", isOn: $st.glare).toggleStyle(.switch).font(.caption).fixedSize()
                Toggle("強い反射をよける", isOn: $st.glareAuto).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("殻の向きで照り返しが白いかたまりになったら、1 秒あまりテカーッと見せてから、さっと切る。その向きにいる間も、ときどきテカーッと光る。弱くなったら戻す（自動）")
                // 宇宙（パネルの右の外に見切れないよう、いちばん上の段に）
                Picker("宇宙", selection: $st.spaceMode) { Text("さんぽと同じ").tag(0); Text("入").tag(1); Text("切").tag(2) }
                    .pickerStyle(.segmented).frame(width: 200).font(.caption).fixedSize()
                    .help("宇宙モード：球面さんぽと同じ 12000 個の星を超球に（右は S³ の上、左は影で球の中）、背景は宇宙、網目は光る線。さんぽと同じ：さんぽで宇宙の背景を入れている時に入る")
                slider("星の数", Binding(get: { st.starsPct }, set: { st.starsPct = $0 }), 5, 100, fmt: "%.0f%%").frame(width: 90).disabled(!st.spaceNow && st.spaceMode != 1)
                slider("星の遠近", Binding(get: { st.starDepth }, set: { st.starDepth = $0 }), 0, 1, fmt: "%.2f").frame(width: 90).disabled(!st.spaceNow && st.spaceMode != 1)
                    .help("引きの絵で、超球の向こう側の遠い星ほど透明に・ぼかす（0 で今まで通り）。半透明の時などに。ズームで寄った時は、いつも遠い星を透明に")
                Spacer(minLength: 4)
                Picker("静かさ", selection: $st.hyperQ) { Text("さんぽに合わせる").tag(0); Text("静か").tag(1); Text("高画質").tag(2) }
                    .pickerStyle(.segmented).frame(width: 280).font(.caption)
                    .help("この窓の描き方。さんぽに合わせる：さんぽの静かモードの時だけ静か。静か：いつも静か（コマ数を少し下げる。144Hz の画面なら 72 → 48。さんぽの景色の画面は 30 コマ。描く画素は減らさないので、色や線の見え方は変わらない）。高画質：さんぽが静かモードでも、この窓はいつもなめらかに")
                Picker("画質", selection: $st.quality) { Text("自動").tag(0); Text("高").tag(1); Text("中").tag(2); Text("低").tag(3) }
                    .pickerStyle(.segmented).frame(width: 190).font(.caption)
                    .help("描く画素の数。自動：コマ数が目標に届かない時は下げ、余裕が戻ったら上げる（なめらかさ優先）")
                Toggle("省電力", isOn: $st.adaptive).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("止まっている間は 1 秒 10 コマに落とし、動かすとすぐ画面のいちばん速いコマ数に戻す（iPhone の ProMotion のように）")
                HLStatsLabel(stats: st.stats).frame(width: 250, alignment: .trailing)   // 幅を決めておく（数字が変わってもパネルの並びを動かさない）
            }
            // 2 段目：傾き・層・光
            HStack(spacing: 14) {
                slider("前後傾き", Binding(get: { st.pitch * 180 / .pi }, set: { st.pitch = $0 * .pi / 180; st.bump() }), -180, 180)
                slider("左右傾き", Binding(get: { st.roll * 180 / .pi }, set: { st.roll = $0 * .pi / 180; st.bump() }), -180, 180)
                slider("Z-W 傾き", Binding(get: { st.zw * 180 / .pi }, set: { st.zw = $0 * .pi / 180; st.bump() }), -180, 180)
                slider("層数", Binding(get: { Double(st.layers) }, set: { st.setLayers(Int($0.rounded())) }), 3, st.layersLink ? 21 : 41, fmt: "%.0f")
                slider("光沢", Binding(get: { st.gloss }, set: { st.gloss = $0 }), 0, 1.5, fmt: "%.2f")
                slider("線の太さ", Binding(get: { st.wireW }, set: { st.wireW = $0 }), 0.6, 4, fmt: "%.1f")
                    .help("ワイヤー（網目の線）の太さ（画面の画素）。細いと色が薄く見え、太いと鮮やかに")
            }
            // 3 段目：座標軸・Z-W の見せ方
            HStack(spacing: 10) {
                Picker("球層", selection: Binding(get: { st.shellMode }, set: { st.shellMode = $0; st.bump() })) {
                    Text("レインボー").tag(0); Text("4 方向").tag(1); Text("軸の色").tag(2); Text("さんぽと同じ").tag(3) }
                    .pickerStyle(.segmented).frame(width: 330).font(.caption)
                    .help("球層の色と向き。レインボー：w の向きに積んだ殻（ふだん）。4 方向：x・y・z・w のそれぞれの向きに殻を重ねる（レインボー）。軸の色：同じく 4 方向に、囲む軸の色で（x 赤・y 緑・z 青・w 紫）。左の球は z を落とすので x・y・z(w) の 3 方向。さんぽと同じ：球面さんぽの球層の色に合わせる。4 方向・軸の色は重い。キーの 4 で 4 方向 ⇄ レインボー")
                Divider().frame(height: 18)
                Toggle("座標軸", isOn: Binding(get: { st.axes }, set: { st.axes = $0; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("座標の矢印。左は x・y・z（z は右の w に当たるので紫）、右は x・y・z・w を超球と一緒に 4D で回す")
                Toggle("ズーム中も", isOn: Binding(get: { st.axesDive }, set: { st.axesDive = $0; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.axes)
                    .help("ダイブ（超ズーム）で寄っていく間も、座標軸と軸の名前を出す")
                Toggle("＋のみ", isOn: $st.axPlus).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.axes)
                    .help("座標軸をプラスの向きだけにする")
                Picker("", selection: $st.axThin) { Text("線").tag(true); Text("立体").tag(false) }
                    .pickerStyle(.segmented).frame(width: 90).labelsHidden().disabled(!st.axes)
                    .help("線：細い軸線と平たい矢じり。立体：つやのある管と円すいの矢印")
                Divider().frame(height: 18)
                Toggle("4D の遠近", isOn: $st.depth4On).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("右の超球で、4 次元で遠い所ほど、かすませる・ぼかす")
                Picker("", selection: $st.depth4) { Text("かすみ").tag(1); Text("ぼかし").tag(2); Text("両方").tag(3) }
                    .pickerStyle(.segmented).frame(width: 170).labelsHidden().disabled(!st.depth4On)
                    .help("右の超球で、4 次元で遠い所ほど：かすみ＝背景の色へ溶けて淡く、ぼかし＝網目の線が太くやわらかく淡く（ピンぼけのように）・星は大きくぼんやり。奥行きは物体の w 軸ではなく、見る人の 4 次元の視線（w′）で測る（4D で回すと、x・y・z・w の混ざった向きになる）")
                slider("強さ", Binding(get: { st.depth4K }, set: { st.depth4K = $0 }), 0, 1, fmt: "%.2f").frame(width: 90).disabled(!st.depth4On)
                Divider().frame(height: 18)
                Text("Z-W を左の球で").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { st.lzw }, set: { st.lzw = $0; st.bump() })) { Text("断面").tag(0); Text("影（投影）").tag(1); Text("両方").tag(2) }
                    .pickerStyle(.segmented).frame(width: 210).labelsHidden()
                    .help("断面：z′＝0 で切った円（断面と交わらなくなると消える）。影：z の向きから見た影。輪は消えず、各層が平たい楕円体（パンケーキ）に。両方：断面の輪＋影を薄く")
                Spacer()
                Text("Metal 版の試作").font(.caption).foregroundStyle(.secondary)
            }
            // 4 段目：断面カット
            HStack(spacing: 10) {
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
            // ---- さんぽと連動（球面さんぽとつなぐ機能を全部ここに。たためる）----
            walkSection
        }
        .padding(10)
        .background(Color(red: 0.04, green: 0.06, blue: 0.11))
        .controlSize(.small)
        .onAppear {
            HyperLabState.walkShut = st.shutWalk; HyperLabState.shutAuto = st.shutAuto; HyperLabState.opModeNow = st.opMode
            // 超球の窓のショートカットキー：4 球層の色を 4 方向レインボー ⇄ レインボー、D ダイブ（自動で寄る）⇄ 戻る、スペース パネルを隠す ⇄ 出す、O 操作モード
            let hs = st
            HyperLabState.hyperKey = { [weak hs] c in
                guard let st = hs else { return false }
                switch c {
                case "4": st.shellMode = st.shellModeNow == 1 ? 0 : 1; return true
                case "d", "D": guard HyperLabState.walkSource != nil else { return false }; st.diveManual = false; st.diveOn.toggle(); st.bump(); return true
                case " ": st.panelHidden.toggle(); return true
                case "o", "O": st.opMode.toggle(); return true
                default: return false
                }
            }
        }
        .onChange(of: st.shutAuto) { _, v in
            HyperLabState.shutAuto = v
            if !v { HyperLabState.walkShut = st.shutWalk; HyperLabState.hyperIdle = false }
        }
        .onChange(of: st.shutWalk) { _, v in
            guard !st.shutAuto else { return }
            HyperLabState.walkShut = v
            // 窓を勝手に前へ出すことはしない（どちらの窓でも好きに使えるように）
        }
        .onAppear { HyperLabState.wipeLow = st.wipeLow; HyperLabState.poleENNow = st.poleEN; Journey.lapClearsTrail = st.lapClear }
        .onChange(of: st.lapClear) { _, v in Journey.lapClearsTrail = v }
        .onChange(of: st.poleEN) { _, v in HyperLabState.poleENNow = v }
        .onChange(of: st.wipeLow) { _, v in HyperLabState.wipeLow = v }
        // 窓を閉じた（iPad は全画面を閉じた）：さんぽはまた描く・音も止める
        .onChange(of: st.opMode) { _, v in HyperLabState.opModeNow = v }
        .onDisappear { HyperLabState.opModeNow = false; HyperLabState.walkShut = false; HyperLabState.shutAuto = false; HyperLabState.hyperIdle = false; HyperSound.shared.stop() }
    }
    /// 球面さんぽとつなぐ機能：景色の画面・並び・歩いた跡・目印・極・球層の数・宇宙・自分を追う・ダイブ
    var walkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { st.walkOpen.toggle() } } label: {
                    Label("さんぽと連動", systemImage: st.walkOpen ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                }.buttonStyle(.plain).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
                    .help("球面さんぽとつなぐ機能（さんぽの景色・歩いた跡・目印・極・宇宙・自分を追う・ダイブ）。たたむと隠れる（働きはそのまま）")
                Toggle("前の窓だけ描く（自動）", isOn: $st.shutAuto).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("今前にある窓の景色と地図だけを描く：超球の窓が前なら、さんぽの窓はオフ（真っ暗）。さんぽの窓が前なら、さんぽの景色と地図を描いて、この窓はオフ（真っ暗）。窓を選ぶと瞬時に切りかわる")
                Toggle("さんぽの窓は止める（この窓だけで描く）", isOn: $st.shutWalk).toggleStyle(.switch).font(.caption).fixedSize().disabled(st.shutAuto)
                    .help("重い時に。（歩くキーはこの窓でそのまま効く）。さんぽの窓（景色・地図）は真っ黒にして描かず、GPU をこの窓（超球・さんぽの景色の画面・ダイブ）だけに使う。この窓も 1 秒 72 コマ（120Hz の画面は 60）までにして静かに。この窓を閉じると、さんぽはまた描く。歩く計算・跡・目印・自分を追うはそのまま（コントローラーで歩ける）")
                if !st.walkOpen {
                    Text(walkSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            if st.walkOpen {
                // 見せるもの（収まらない時は折り返す）
                HLWrap(spacing: 10) {
                    Toggle("自分が真ん中", isOn: $st.naviCenter).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの間、上の地図を車のナビのように：自分がいつも真ん中で背景が動き、進む向きが上。赤い玉へ向かうと赤い玉が近づき、裏から紫の玉が寄ってくる")
                    Toggle("地図 2 枚", isOn: $st.map2).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの間、さんぽの景色の場所をW 地図にする（上はナビ地図：自分を追う。下はW 地図：軸がうねうね動く・断面・中へ入る）。切ると、さんぽの景色に戻す")
                    Toggle("さんぽの景色", isOn: $st.walkView).toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("さんぽの窓と同じ景色（今いる所から見た S³）を、画面を割って出す")
                    Picker("", selection: $st.wipeLow) { Text("低負荷").tag(true); Text("きれい").tag(false) }
                        .pickerStyle(.segmented).frame(width: 120).labelsHidden().disabled(!st.walkView)
                        .help("さんぽの景色の画面（ワイプ）の描き方。低負荷：画素は半分（超球の方に力を回す）。きれい：画面の細かさ。どちらも 1 秒 60 コマ")
                    Toggle("3D の球", isOn: $st.show3D).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("左の 3D の球（リングを積む）を出す。切ると、さんぽの景色と 4D の超球だけの並びに")
                    Button("⟳ 並び") { let o = st.order; st.order = [o[2], o[0], o[1]] }
                        .help("3 つの画面（3D の球・さんぽの景色・4D の超球）の置き場所を順に回す（左上 → 左下 → 右）")
                    Toggle("歩いた跡", isOn: $st.walk).toggleStyle(.switch).font(.caption).fixedSize()
                    Toggle("予定の道", isOn: $st.planOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                    Toggle("先に道を描く", isOn: $st.railOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("決まった道・自分の道の 1 周ぶんを、歩く前から薄赤の線で描く（太さは跡の太さ）。彗星はこの上を走り、歩いた所は白っぽい青緑に塗りかわる。「1 周で跡を消す」が入っていれば、1 周で薄赤へ戻る")
                        .help("決まった道（螺旋・回る輪・極めぐりなど）や自分の道（巡回）を歩いている時、これから進む道を光の点線で出す（点は進む向きへゆっくり流れ、先へ行くほど淡く）")
                    Toggle("粗密", isOn: $st.planDense).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn)
                        .help("予定の道の矢印の間隔を、まっすぐな所は広く、カーブでは密に（急なカーブで 3 倍ほど）。矢印は道の上に止まったまま")
                    Toggle("道を全部", isOn: $st.planLong).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn)
                        .help("ダイブで寄った時も、左上の地図と同じように予定の道の終わりまで矢印を出す（遠くは 4D の遠近で小さく詰まって見える）。切ると、彗星の先のほどよい長さまで")
                    // 回り方は「拍・進路A・進路B」の 3 つに整理（カーブ・両方・波・らせんは選べないようにした。仕組みは残してある）
                    Picker("", selection: Binding(get: { [0, 5, 6].contains(st.spinMode) ? st.spinMode : 0 }, set: { st.spinMode = $0 })) { Text("拍").tag(0); Text("進路A").tag(5); Text("進路B").tag(6) }
                        .pickerStyle(.segmented).frame(width: 170).labelsHidden().disabled(!st.walk || !st.planOn || st.planMark != 0)
                        .help("立体の矢印の回り方。拍：彗星の音（エンジンの低いうなり）に合わせて、手前から順にドミノのように回る。カーブ：道が曲がっている所の矢印が、曲がる向きへ自分から回り続ける（右へ曲がる所は右回り、左は左回り。急なほど速く。まっすぐな所は止まる）。両方：その両方。波：傾きがサインカーブの波になって手前から先へ伝わる（拍に合わせて）。らせん：1 枚ごとにねじれて並び、鎖全体が拍に合わせて回り続ける。進路A：今走っている向きと矢印の向きの角度で、平行なら立って薄く、直角なら寝て面が見える（まっすぐ先ほど薄く）。進路B：その逆で、直角なら立って線に見える（遠くでカーブしている板ほどひねったテープのように薄く）。どちらも進むにつれて次々に寝たり起き上がったりする（回らない。ゆがんだ矢印のスピード感を生かす）。回っている間は光る")
                    if false && (st.spinMode == 3 || st.spinMode == 4) {
                        slider(st.spinMode == 3 ? "振れ" : "ねじれ", Binding(get: { st.spinAmp }, set: { st.spinAmp = $0 }), 0, 180, fmt: "%.0f°").frame(width: 90)
                            .help("波：傾きの振れ幅。らせん：となりの矢印とのねじれの角")
                        slider(st.spinMode == 3 ? "波長" : "速さ", Binding(get: { st.spinLen }, set: { st.spinLen = $0 }), 1, 20, fmt: "%.0f").frame(width: 90)
                            .help("波：1 つの波の長さ（矢印の枚数）。らせん：回る速さ（拍 2 つで ×0.1 回り。10 で 1 回り）")
                    }
                    Toggle("球殻の色に染まる", isOn: $st.planShell).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn || st.planMark != 0)
                        .help("立体の矢印を、その場所の球殻の色にほんのり染める（緑の所なら半透明の緑）。切ると、手前から奥へ軸の 4 色のグラデーション")
                    Picker("", selection: $st.planMark) { Text("立体の矢印").tag(0); Text("楕円の光").tag(1); Text("金平糖").tag(2) }
                        .pickerStyle(.segmented).frame(width: 190).labelsHidden().disabled(!st.walk || !st.planOn)
                        .help("予定の道の目印。立体の矢印：厚みのある「»」、青白にほんのり軸の色。向きは S³ の上で道に沿って平行移動で運ぶ（まっすぐな所でそろい、道のねじれに合わせてねじれる）。楕円の光：暖かい白、まっすぐな所で進む向きに伸びる。金平糖：青白にほんのり軸の色、くるくる回る")
                    Picker("", selection: $st.trailCol) { Text("桃色").tag(0); Text("白い光").tag(1); Text("軸の色").tag(2) }
                        .pickerStyle(.segmented).frame(width: 170).labelsHidden().disabled(!st.walk)
                        .help("歩いた跡の色。桃色：古い所は桃色、新しい所は白。白い光：青白から白。軸の色：その場所がいちばん近い軸の色（x 赤・y 緑・z 青・w 紫）")
                    Toggle("1 周で跡を消す", isOn: $st.lapClear).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("1 周したら、チェックと一緒に歩いた跡も消す（その周の跡だけ残る）。1 周＝置いた目印（2 つ以上）を全部通る。目印がなければ 8 つの極を全部通る。周回は右上の隅とさんぽの窓に小さく出る")
                    Toggle("前方の跡を消す", isOn: $st.clearAhead).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("同じ道をまた通る時、今いる所（彗星）の前とすぐそばの古い跡を一時的に薄くして、今いる所を目立たせる。通り過ぎるとまた見える")
                    slider("跡の太さ", Binding(get: { st.trailW }, set: { st.trailW = $0 }), 0.2, 2, fmt: "×%.1f").frame(width: 90).disabled(!st.walk)
                        .help("球面さんぽで歩いた跡と今いる所を、右の超球（S³ そのもの）と左の球（影）に描く")
                    Picker("", selection: $st.cursor) { Text("さんぽ").tag(0); Text("彗星").tag(1); Text("大彗星").tag(4); Text("巨大彗星").tag(3); Text("線の彗星").tag(2) }
                        .pickerStyle(.segmented).frame(width: 310).labelsHidden().disabled(!st.walk)
                        .help("今いる所の印。さんぽ：青緑と白の三重の輪。彗星：光で描く（白く飛んだ核と青緑のコマ、ぼけてすじの流れる尾）。大彗星：引きの絵では大きな光の玉の中に、白い頭と尾のふつうの彗星（どこにいるかひと目でわかる）。巨大彗星：光の玉をさらに大きく（ダイブ中の全体像でも目立つ）。大彗星・巨大彗星もダイブで寄るとふつうの彗星。線の彗星：線で描いた前の形")
                    Toggle("目印", isOn: $st.marksOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("球面さんぽで置いた目印。歩いて通った目印（チェックポイント）は塗りつぶしと ✓、まだの目印は輪")
                    Toggle("光で描く", isOn: $st.symGlow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.marksOn && st.polesMode == 0)
                        .help("極と目印を光る星で描く（通った所は白く光る星に極の色がほんのり、十字のきらめき。まだの所は光の輪。ゆっくりまたたく）。切ると前の丸と輪")
                    RecordPanelButton()
                    Toggle("音", isOn: $st.soundOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("音を出す：彗星が空気を押し切って走る風切り音（速いほど高く大きく・重く、曲がる時は外側へ風が流れてひと吹き強まる、ズームで寄るほど大きく）と、チェックポイントに当たった時の「チリン」")
                    slider("音量", Binding(get: { st.soundVol }, set: { st.soundVol = $0 }), 0, 1, fmt: "%.2f").frame(width: 80).disabled(!st.soundOn)
                    Toggle("空間オーディオ", isOn: $st.soundSpatial).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.soundOn)
                        .help("彗星のいる方向から音が聞こえる（ヘッドホンだと左右だけでなく上下・前後も。広い場所の残響を少し）。切ると左右だけのステレオ")
                    Toggle("さんぽメニュー", isOn: $st.walkMenu).toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("この窓に、さんぽの操作の小窓を浮かべる（歩く・止まる・速さ・目印・跡を消す・アナ極へ・決まった道）。✕ で隠す")
                    Toggle("ゲームパッド", isOn: Binding(get: { st.padOn }, set: { on in st.padOn = on; if !on { HyperLabState.walkRendererGet?()?.game.vClear() } }))
                        .toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("画面のゲームパッドを出す（さんぽの窓と同じ。押すとコントローラーと同じ働きで歩く）。パネルを隠していても出る")
                    Toggle("座標", isOn: $st.coordOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                    Toggle("W 地図の動き", isOn: $st.ovShow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("W 地図の演出。自分の w の高さに合わせて Y-W 面でゆっくり回す（赤道で球層が真横、アナ極・カタ極で赤と紫の玉が重なる）。玉の近くでは断面を開く")
                        .help("走行中の座標を右の画面の左上に（S³ の上の x・y・z・w、アナ極からの角度、いちばん近い極、速さ）。計器のように書きかわる")
                    Toggle("英語", isOn: $st.poleEN).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("極の名前を英語に（セリフ体で小さく）：Ana・Kata・North・South・East・West・Zenith・Nadir。さんぽの景色の画面も")
                    Picker("極", selection: $st.polesMode) { Text("出さない").tag(0); Text("通ると出る").tag(1); Text("いつも").tag(2) }
                        .pickerStyle(.segmented).frame(width: 210).font(.caption)
                        .help("8 つの極（アナ極・カタ極・東西南北・天・地）。通ると出る：歩いて通った極だけ ✓ つきで出てくる。いつも：全部出し、通った極は ✓")
                    Toggle("球層の数をさんぽと同じに", isOn: Binding(get: { st.layersLink }, set: { on in st.layersLink = on; if on, let w = HyperLabState.walkShells { st.setLayers(w.get()) } }))
                        .toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkShells == nil)
                        .help("入れると、球層の数を球面さんぽと同じにする。さんぽで増やす・減らすとこちらも、こちらで変えるとさんぽも変わる（3〜21）")
                }
                // 動かし方：自分を追う・ダイブ（収まらない時は折り返す）
                HLWrap(spacing: 10) {
                    Menu(st.followOn ? (st.followSlack < 1 ? "追う：いつも中心" : String(format: "追う：遊び %.0f°", st.followSlack)) : "自分を追う") {
                        Button("いつも中心（さんぽの自分中心と同じ）") { st.followOn = true; st.followSlack = 0; st.followHeading = true }
                        Button("奥に行ったら回す（手前の半分は自由）") { st.followOn = true; st.followSlack = 90; st.followHeading = false }
                        Button("自由（追わない）") { st.followOn = false }
                        Divider()
                        Toggle("進む向きも合わせる", isOn: $st.followHeading)
                    }.fixedSize().help("さんぽで歩く自分を、超球の手前に保つ。遊び：真ん中からどこまで自由に動けるか。0° ならいつも中心、90° なら奥（4D の裏）へ行きかけた時だけ回す")
                    if st.followOn {
                        slider("遊び", Binding(get: { st.followSlack }, set: { st.followSlack = $0.rounded() }), 0, 150, fmt: "%.0f°").frame(width: 120)
                        slider("戻す速さ", Binding(get: { st.followSpeed }, set: { st.followSpeed = $0 }), 0.2, 3, fmt: "%.1f").frame(width: 120)
                        slider("ゆるく回す", Binding(get: { st.followDrift }, set: { st.followDrift = $0 }), 0, 1, fmt: "%.2f").frame(width: 120)
                            .help("遊びの中でも、弱い力で少しずつ自分の方へ回り続ける。0 で遊びの中は止まる")
                    }
                    Divider().frame(height: 18)
                    Button(st.diveOn ? "⤴ 戻る" : "⤵ ダイブ") { st.diveManual = false; st.diveOn.toggle(); st.bump() }
                        .disabled(HyperLabState.walkSource == nil)
                        .help("超ズームで、今いる所へ飛び込んで、さんぽの景色に入る（ゆっくり約 5 秒）。もう一度押すと外へ出る。キーの D でも（ほかのキー：スペースでパネルを隠す・出す、4 で球層の色を 4 方向 ⇄ レインボー）")
                    slider("ズーム", Binding(get: { st.diveT }, set: { st.diveManual = true; st.diveT = $0; st.diveOn = $0 > 0.5; st.bump() }), 0, 1, fmt: "%.2f").frame(width: 120)
                    Picker("", selection: Binding(get: { st.diveThird }, set: { st.diveThird = $0; st.bump() })) { Text("一人称").tag(false); Text("三人称").tag(true) }
                        .pickerStyle(.segmented).frame(width: 120).labelsHidden()
                        .help("ダイブの行き先。一人称：自分の目へ（さんぽの景色）。三人称：斜め後ろの少し上で止まって、走る自分（彗星）を追う")
                    if st.diveThird {
                        slider("後ろ", Binding(get: { st.chaseDist }, set: { st.chaseDist = $0; st.bump() }), 0.1, 2, fmt: "%.2f").frame(width: 100)
                        slider("見下ろす", Binding(get: { st.chasePitch }, set: { st.chasePitch = $0; st.bump() }), -70, 80, fmt: "%+.0f°").frame(width: 100)
                            .help("上から見下ろす角度。マイナスにすると、下から見上げる")
                        slider("斜め", Binding(get: { st.chaseYaw }, set: { st.chaseYaw = $0; st.bump() }), -90, 90).frame(width: 100)
                    }
                    Toggle("ダイブ中は全体像", isOn: $st.diveOverview).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブしている間、3D の球の場所に、外から見た超球の全体像を出す（どこを走っているかを見ながらダイブできる）。3D の球を出している時だけ")
                    Picker("", selection: $st.ovCursor) { Text("同じ").tag(-1); Text("さんぽ").tag(0); Text("彗星").tag(1); Text("大").tag(4); Text("巨大").tag(3); Text("線").tag(2) }
                        .pickerStyle(.segmented).frame(width: 245).labelsHidden().disabled(!st.diveOverview)
                        .help("全体像の今いる所の印。同じ：ふつうと同じ。さんぽ：青緑と白の三重の輪（遠くからでも見つけやすい）。彗星・線：光の彗星・線の彗星")
                    Toggle("オートカメラ", isOn: $st.autoCam).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird)
                        .help("ズーム（三人称）の時、よく見える角度へ自動で：ゆっくり周りを漂い、曲がる時は外側へ回り込む。きついカーブや垂直に近い動きの時は、水平の目線から真上近くへ大きく展開して、曲がる道すじ全体を見せる（ダイナミック）。ドラッグで回すとその間は止まる")
                    Toggle("操作モード", isOn: $st.opMode).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの画面を見ながら、さんぽの窓と同じように歩く（キーの W・A・S・D・矢印、コントローラーのスティック・ボタンがみんな歩く操作に。スティックでカメラは回さない）。キーの O で入る（操作モードの間は、D・O などのキーはさんぽの操作なので、切るのはこのスイッチで）")
                    Toggle("カメラをコントローラーで", isOn: $st.padCam).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird)
                        .help("ズーム（三人称）の間、コントローラーのスティックで自分（彗星）のまわりのカメラを回す（離すとゆっくり元の角度へ）。オートカメラ・ショーカメラは止めず、その上に足す。そのスティックは歩くのには使わない")
                    Picker("", selection: $st.padCamStick) { Text("左").tag(0); Text("右").tag(1); Text("両方").tag(2) }
                        .pickerStyle(.segmented).frame(width: 110).labelsHidden().disabled(!st.padCam || !st.diveThird)
                        .help("カメラを回すスティック（手で持った時の左右）")
                    Toggle("ショーカメラ", isOn: $st.camShow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird || !st.autoCam)
                        .help("オートカメラの仲間：カーブが近づくと彗星の真後ろの低い所へ回り込んで、ターンを後ろから見せる。まっすぐな所では 7 秒ごとにランダムに、大きく引いた全体も交えて、斜め右上（傾ける）・右の真横・真上の近く・斜め左上（傾ける）・左の真横・高く引いた全体・低い斜め後ろ、と角度を切りかえる。下から見上げて、彗星を画面の左上・右上に置く構図も（極めぐりのショーと相性がいい）")
                    Picker("", selection: $st.showMode) { Text("A").tag(0); Text("B").tag(1) }
                        .pickerStyle(.segmented).frame(width: 70).labelsHidden().disabled(!st.diveThird || !st.autoCam || !st.camShow)
                        .help("ショーカメラの演出。A：いろいろな構図を順に回して、カーブでは真後ろの斜めに構える。B：ジェットコースターのように、先の落ち込み・昇り・急カーブを読んで先回りする（落ち込みでは前の高い所へ舞い上がり、向かってくる彗星を見下ろす）。どちらもゆっくり落ち着いて動く")
                    Toggle("景色に溶かす", isOn: $st.diveBlend).toggleStyle(.switch).font(.caption).fixedSize()
                        .disabled(st.diveThird).help("ダイブの最後に、さんぽの景色へ溶け込ませる（一人称の時）。切ると、寄ったまま超球の網目（4D の外から見た姿）で見続けられる（左下の景色と見比べに）")
                    Spacer()
                }
            }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.2, green: 0.25, blue: 0.33)).frame(height: 1).offset(y: -3) }
    }
    /// たたんでいる時の要約（入っている物だけ）
    var walkSummary: String {
        var a: [String] = []
        if st.walkView { a.append("景色") }
        if st.walk { a.append("跡") }
        if st.marksOn { a.append("目印") }
        if st.polesMode > 0 { a.append("極") }
        if st.layersLink { a.append("層数") }
        if st.spaceNow { a.append("宇宙") }
        if st.followOn { a.append("追う") }
        if st.diveOn { a.append("ダイブ中") }
        return a.isEmpty ? "（どれも切）" : a.joined(separator: "・")
    }
    func slider(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, fmt: String = "%+.0f°") -> some View {
        HLSlider(name: name, value: v, lo: lo, hi: hi, fmt: fmt)
    }
}

#if os(macOS)
/// Mac：Metal 版の試作を別の窓で
enum HyperLabWindow {
    static var window: NSWindow?
    /// さんぽの窓（球面さんぽ）
    static var walkWindow: NSWindow? { NSApp.windows.first { $0 !== window && $0.isVisible && $0.title.hasPrefix("球面さんぽ") } }
    static func open() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "超球（Metal 版の試作）"; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: HyperLabView())
        w.setFrameAutosaveName("S3WalkHyperLab"); if !w.setFrameUsingName("S3WalkHyperLab") { w.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            window = nil; HyperLabState.walkShut = false
        }
        window = w; w.makeKeyAndOrderFront(nil)
    }
}
#endif
