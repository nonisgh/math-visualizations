// 超球の窓の共通の状態（左右の画面とパネルで共有）：設定・ダイブ・自分を追う・さんぽとのつなぎ・設定の保存
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
    @Published var auto = false { didSet { if auto { claim(.auto) } } }   // 4D 回転：超球そのものをゆっくり回す（回転ボタン）
    @Published var spin3D = false                                     // 3D 回転：今の 4D の姿（角度）はそのままで、右の 3D のカメラをゆっくり回し続ける（ろくろのように。w はからまない）
    // 2 重回転：直交する 2 つの面（X-Y と Z-W）を同時に回す。回す順は Z-W → 面内 X-Y → 前後 → 左右なので、面内と Z-W を進めると超球そのものが回り、
    //   前後・左右の傾きは見る向きのまま残る。2 つの円はそれぞれ自分の上をすべるだけで、円の形は動かない。速さが同じならクリフォード回転（全部の点が同じ速さで大円を回る）
    @Published var rot2On = false { didSet { if rot2On { claim(.rot2); if !oldValue { swingStart() } } } }
    // ゆらす（単振動）：一方向に回し続ける代わりに、面内と Z-W の角度を sin で行ったり来たりさせる（始めた時の角度が真ん中）。
    //   位相は「速さ」で進むので、1 往復は 360 ÷ 速さ 秒（30°/秒なら 12 秒）。比のボタンはそのまま 2 つの振動の速さの比になる
    @Published var rot2Swing = false { didSet { if rot2Swing != oldValue { swingStart() } } }
    @Published var rot2Amp = 60.0                                     // ゆれ幅（度）
    @Published var rot2XY = 30.0                                      // X-Y の面の速さ（度／秒）
    @Published var rot2ZW = 30.0                                      // Z-W の面の速さ（度／秒）
    @Published var rot2Rings = true                                   // 2 つの円を出す
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
    @Published var knifeOn = false                                   // ナイフモード（K）：右の超球をドラッグすると、y 軸のまわりにその経度から切れていく
    @Published var knifeMove = false                                 // ナイフのドラッグ：true 開き具合の切り欠きがナイフに付いてくる・false 引いて広げる
    var knifePtr: CGPoint? = nil, knifeStart = CGPoint.zero, knifeDown = false, knifeHover: CGPoint? = nil, knifeLon: Double? = nil   // 画面の上のナイフ（点）・押した所・押している間・押さずに指している所・指している経度（刃の線）
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
    @Published var lowView = 0                                        // ダイブしていない間の画面：0 さんぽの景色・1 景色の場所にダイブ画面・2 両方（上にダイブ画面、下にさんぽの景色）
    @Published var lightWrap = false                                  // 光の回り込み：アナ極・カタ極の近くで、光が超球を回って自分へ届く道を見せる
    @Published var lowFirst = false                                   // ダイブしていない間、さんぽの景色の場所に一人称のダイブ画面を出す
    var lowFirstNow: Bool { lowFirst && walkView && !diveOn && diveT == 0 }
    @Published var mainBarOn = true                                   // 窓の上のメインメニューを出す
    @Published var lowSwap = false                                    // 両方の時に上下を入れかえる（上にさんぽの景色、下にダイブ画面）
    var lowDiveNow: Bool { lowView == 1 && walkView && !diveOn && diveT == 0 }
    var lowBothNow: Bool { lowView == 2 && walkView && !diveOn && diveT == 0 }
    // 左の窓の中身と、左の窓を黒くおおう濃さ
    var paneDive = false, paneCover = 0.0
    private var paneStep = 0, paneT = 0.0
    var paneSwapT = 0.0, paneDrawn = false
    // シースルー：変形の間、左の窓に右の絵の続きを暗く透かす。paneSee 出している、paneSeeB 明るさ、paneSeeA 重ねる濃さ
    @Published var seeThrough = true
    var paneSee = false, paneSeeB = 0.0, paneSeeA = 0.0
    static let seeBright = 0.4
    var paneBusy: Bool { paneStep != 0 }
    /// 左の窓を黒くする間（ボタンを押した瞬間から。毎コマの進みを待たない）
    var paneBlack: Bool { (paneStep >= 1 && paneStep <= 3) || (paneStep == 0 && paneDue) }
    /// 左の窓を入れかえる番が来た（ズームを始める・ぱっと切りかえた。ズームのスライダーを手で動かしている間は、そのまま）
    private var paneDue: Bool { !diveManual && (diveT != (diveOn ? 1 : 0) || (diveOn || diveT > 0) != paneDive) }
    static let paneOut = 0.12, paneIn = 0.15, seeOut = 0.3            // 黒くする・出す（どちらもすばやく）・シースルーから地図へ入れかえる
    static var paneFreezeNow = false
    var paneFirst: Bool { lowFirst && walkView && !paneDive }
    var paneWipe: Bool { lowView == 1 && walkView && !paneDive }
    var paneBoth: Bool { lowView == 2 && walkView && !paneDive }
    var paneMap2: Bool { map2 && paneDive }
    // アニメーションなしの切りかえ：右の画面を前の絵からリゾルブする（左の窓は黒を通って入れかわる）
    var resolveArmed = false, resolveT = -9.0
    /// ダイブのカメラの計算が見るズーム：ダイブ画面を別に出している間は、寄り切っているのと同じ
    var diveLive: Double { lowDiveNow || lowBothNow || lowFirstNow || exWipeNow ? 1 : diveT }
    var exWipeNow = false                                             // 決まった道から作る書き出しで、ダイブ画面を出している（カメラは書き出しの中で動かす）
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
    @Published var soundPlace = 0.7                                   // 場所の音の強さ（w の高さの音色。0 なし）
    @Published var passOn = true                                      // 極の通過のテロップ
    @Published var noteOn = true                                      // 赤玉・紫玉の解説のテロップ
    @Published var soundLayer = false                                 // 球層を横切る音
    @Published var soundBass = 1.0                                    // 低音の倍率（1 が元のまま）
    @Published var soundRough = 1.0                                   // ガラララッの荒さ（0 なし）
    @Published var soundRail = 1.0                                    // 線路の音：光の矢印を通るたびの、かすかな「カタン」（0 なし）
    @Published var soundSong = 0.0                                    // 渦の歌：流体の渦を波形にした音（0 なし）
    @Published var soundWind = 1.0                                    // 風の音の大きさ（プープーの機械音は別）
    @Published var soundRush = 1.0                                    // 直線の加速：まっすぐ走るほど音が伸びていく強さ（0 なし）
    @Published var soundPhones = false                                // ヘッドホン用：低音に隠れないようにガラララッを調整する
    @Published var soundVol = 0.7                                     // 音の大きさ
    @Published var soundFar = true                                    // ダイブの外でも、彗星の走る音を小さく鳴らす
    @Published var airOn = true                                       // 空気あり：彗星のまわりの空気をナビエ・ストークス方程式で解いて、音とカメラの揺れを動かす
    @Published var coaster = true                                     // ジェットコースター：アナ極が高く、カタ極が低い。下りで速く、上りで遅く（道の形はそのまま）
    var airLift = 0.0, coastG = 0.0, meterM = 1.0                     // 空気の揚力（渦でゆれる）・加速の強さ（＋で加速）・速さの倍率（平均が 1）
    @Published var dopplerOn = true                                   // 極のドップラー：近づくと高く、通り過ぎると低い音。カタ星は後ろから追い抜く（エンタメ）
    @Published var dopK = 0.9                                         // 極の音の大きさ
    var flyA = 0.0, flySide = 0.0                                     // 極の音の強さ・左右（空気を乱す）
    @Published var meriK = 0.7                                        // メリハリ：直線で速く、カーブで遅く（0 で一定の速さ）。設定の速さは全体の平均
    @Published var topK = 1.6                                         // 直線の上限（平均の何倍まで）
    @Published var meterOn = true                                     // 速度メーター（右の画面の下）
    @Published var meterVideo = true                                  // 速度メーターを動画にも入れる
    @Published var feelK = 1.6                                        // 勢いの強さ：本当の速さはそのまま、音・尾・揺れ・彗星の派手さだけ何倍の速さに見せるか（1 で本当の速さのまま）
    @Published var soundFarK = 0.2                                    // ダイブの外の大きさ（ダイブの音に対して）
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
    @Published var diveSpin = 0                                       // ダイブの回り方：0 ふつう・1 くるくる（入る間に 4 次元をもう 1 周）・2 ぐるぐる（2 周）
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
    let splitA = HLSplitAnim()
    var ovDragYaw = 0.0, ovDragPitch = 0.0, ovDragging = false, ovDragT = 0.0   // 下の地図を手で回した分（離すと、少し待って元へ戻る）
    var splitK = 0.0, splitP = 0.0                                    // 交差で仕切りを下げる量（0〜1）とその進み
    func splitAt(_ k: Double) -> Double { max(splitY, min(0.8, splitY + 0.13 * k)) }
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
    @Published var heavy = false                                      // ヘビーモード：色はそのままで、ダイブの殻を細かく描く（網目 2 倍・地平線のふちを画素ごとに・画質を下げない）
    @Published var hyperQ = 0                                         // 超球の窓の静かさ：0 さんぽに合わせる（さんぽの静かモードの時だけ静か）・1 いつも静か・2 いつも高画質
    @Published var wipeLow = true                                     // さんぽの景色の画面（ワイプ）を低負荷で：画素は半分（1 秒 60 コマ）
    @Published var walkPanelOn = false                                // さんぽの設定（さんぽのパネルを全部）を、この窓に浮かべる
    @Published var walkPanelSel = 1                                   // 開いているさんぽのパネル（ふだん「決まった道」）
    @Published var walkMenu = true                                    // さんぽメニュー（この窓に浮かぶ、さんぽの操作の小窓）を出す
    @Published var shutAuto = false                                   // 前の窓だけ描く（自動）：超球の窓が前ならさんぽの窓（景色・地図）を止め、さんぽの窓が前ならさんぽを描いて超球は控えめに。瞬時に切りかえ
    @Published var shutWalk = false                                   // さんぽの窓は描かない：さんぽの窓（景色・地図）を止め、描くのはこの窓だけ（景色の画面・ダイブは描く。歩く計算・跡はそのまま）
    @Published var naviCenter = true                                  // 上の地図を車のナビのように（自分がいつも真ん中で、背景が動く）
    @Published var map2 = true                                        // ダイブの間、さんぽの景色の場所をY-W 地図にする（地図 2 枚）
    var map2Now: Bool { map2 && (diveOn || diveT > 0) }
    @Published var ovShow = true                                      // 地図の構図：ダイブの間、全体像の向きを自動で（横から球層を見せる・赤と紫の玉を重ねて見せる）
    @Published var glareAuto = false                                  // 地図の強い照り返しをよける（白いかたまりになる向きの間だけ、さっと弱める）。ふだんは切る（強い反射も見せる）。ダイブ画面はいつもよける
    @Published var cursor = 1                                         // 今いる所の印：0 さんぽ（青緑と白の三重の輪）・1 彗星（光で描く。コマと、ぼけた尾）・2 線の彗星（前の形）・3 巨大彗星・4 大彗星（光の玉の中に彗星。巨大はさらに大きく。ダイブで寄るとふつう）
    @Published var panelTab = 0                                       // パネルのタブ
    @Published var ovFlip = false                                     // 下の地図の w の頭とケツを入れかえる
    @Published var ovFx = 0                                           // W 消失地図の切り方：0 おまかせ（ほかの地図と同じ見せ場）・手で選ぶ時は 1 半分・2 くさび・3 玉ねぎ・4 ポリゴン・5 回る断面
    @Published var ovZoom = false                                     // W 消失地図の真ん中へ寄る
    @Published var overlapGlow = false                                // 地図で赤玉と紫玉が重なる時の光の円（ふだんは切って、殻をそのまま見せる）
    @Published var ovShuffle = false                                  // 下の地図の軸をランダムに切りかえる
    @Published var ovView = 0                                         // 下の地図：消失させる軸（0 y・1 x・2 z・3 w）
    var ovCaption: String {
        let n = ["Y 消失地図\n球層を横から\n", "X 消失地図\n球層が縦に並ぶ\n", "Z 消失地図\n", "W 消失地図\n赤と紫が真ん中\n"][max(0, min(3, ovView))]
        return n + [ovFlip ? "カタ極が上" : "アナ極が上", ovFlip ? "カタ極が右" : "アナ極が右", ovFlip ? "カタ極が正面\n頭が奥" : "アナ極が正面\n頭が手前", ovFlip ? "カタ極が手前" : "アナ極が手前"][max(0, min(3, ovView))]
    }
    @Published var shakeK = 1.0                                       // 疾走の揺れの強さ（0 なし）
    @Published var holeOn = false                                     // 上の地図のカーソルのまわりを、ポリゴンごと抜く
    @Published var wireWMap = -1.0                                    // 地図のワイヤーの太さ（0 以下はダイブ画面と同じ）
    // 自分を追う（さんぽの「自分中心」を広げたもの）：歩く人が真ん中（4D の手前、超球の正面）から「遊び」の角度より離れたら、
    //   傾き（Z-W・面内・前後・左右）を少しずつ動かして手前へ連れ戻す。遊び 0° ＝ いつも中心、90° ＝ 手前の半分は自由に横断して奥へ行きかけたら回す。
    //   「進む向きも合わせる」は、進む向きがいつも画面の上を向くように回す（さんぽの自分中心と同じ）
    @Published var followOn = false { didSet { if followOn { claim(.follow) } } }
    @Published var followXYZ = false { didSet { if followXYZ { claim(.followXYZ) } } }   // 自分を追う（xyz のみ）：超球の姿はそのままで、右の 3D のカメラが自分の見える側へ回り込む。遊び・戻す速さ・ゆるく回すは共通
    /// 自分を追う：0 追わない・1 xyz のみ・2 xyzw
    var followKind: Int {
        get { followXYZ ? 1 : followOn ? 2 : 0 }
        set { followXYZ = newValue == 1; followOn = newValue == 2 }
    }
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
    /// 切りかえの順番：左の窓をすばやく黒くする → 右の画面が変わる → 左の中身を入れかえて出す。ぱっと切りかえる時は、右がリゾルブする間に左が同じように黒を通る
    private func tickPane(_ dt: Double) {
        let zooming = !diveManual && diveT != (diveOn ? 1 : 0)
        func swapPane() { let want = diveOn || diveT > 0; if paneDive != want { paneDive = want; paneSwapT = CACurrentMediaTime(); paneDrawn = false; objectWillChange.send() } else { paneDrawn = true } }
        switch paneStep {
        case 0: if paneDue { paneStep = 1 } else { swapPane() }
        case 1:
            paneCover = min(1, paneCover + dt / Self.paneOut)
            if paneCover == 1 {
                paneStep = 2; paneT = 0
                if seeThrough && zooming { paneSee = true; paneSeeA = 1; paneSeeB = 0; objectWillChange.send() }   // 黒の上に重ねて、黒から少しずつ見せる
            }
        case 2:
            paneT += dt; if paneT > 0.1 { Self.paneFreezeNow = true }          // 黒が画面に出てから、左の窓を描くのをやめて右の画面へ力を回す
            if paneSee { paneSeeB = min(Self.seeBright, paneSeeB + dt / 0.9) }
            if !zooming { paneStep = 3; paneT = 0; Self.paneFreezeNow = false; swapPane() }
        case 3:                                                                // 新しい窓の最初の絵ができたら、すぐ出す
            paneT += dt; if paneDrawn || paneT > 0.3 { paneStep = 4; objectWillChange.send() }
        default:
            paneCover = max(0, paneCover - dt / Self.paneIn)
            if paneSee { paneSee = false; objectWillChange.send() }
            paneSeeA = max(0, paneSeeA - dt / Self.seeOut)
            if paneCover == 0 && paneSeeA == 0 { paneStep = 0; paneSeeB = 0 }
        }
    }
    /// 確かめ用：切りかえの間だけ、毎コマの間隔を覚えて、終わったら S3_CAM_LOG の横のファイルへ足す
    private static let zoomLog = ProcessInfo.processInfo.environment["S3_CAM_LOG"].map { $0 + ".zoom" }
    private var zoomLines: [String] = [], zoomT = 0.0
    private func logZoom(_ dt: Double) {
        guard let path = Self.zoomLog else { return }
        let now = CACurrentMediaTime()
        if paneBusy || demoOn || (diveT != 0 && diveT != 1) {
            zoomLines.append(String(format: "%.3f 間隔 %.0f dt %.0f 寄り %.4f 順 %d 細かさ %.3f", now, (now - zoomT) * 1000, dt * 1000, diveT, paneStep, Self.renderK))
        } else if !zoomLines.isEmpty {
            let text = (zoomLines + ["---"]).joined(separator: "\n") + "\n"; zoomLines = []
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        }
        zoomT = now
    }
    /// 確かめ用（環境変数 S3_SEE_DEMO）：起動の 3 秒あとに 1 度だけ、ダイブに入る（シースルーを実際の画面で見る）
    private static var seeDemoT = ProcessInfo.processInfo.environment["S3_SEE_DEMO"] != nil ? CACurrentMediaTime() + 3 : Double.infinity
    func tickDive(_ dt: Double) {
        logZoom(dt)
        if CACurrentMediaTime() > Self.seeDemoT {
            Self.seeDemoT = .infinity
            if ProcessInfo.processInfo.environment["S3_SEE_DEMO"] == "demo" { toggleDemo() } else { diveManual = false; diveOn = true; bump() }
        }
        if demoOn { tickDemo(dt) }                                     // 大きな画面が描くたびに、ちょうど 1 回進める（別の窓の間隔にひきずられない）
        tickRun(dt)
        tickDrill(dt)
        tickGlide(dt)
        if fillOn && fillA > 0 { fillA = max(0, fillA - min(0.05, dt) / Self.fillLen); version &+= 1 }
        if !diveManual {
            let tgt = diveOn ? (drillOn || runOn || tunnelNow ? 0.45 : 1.0) : 0.0                // ドリルの間は少し引いて、殻のあいだを落ちるのを見せる
            if diveT != tgt && paneStep == 2 { diveT = tgt > diveT ? min(tgt, diveT + dt / 4.8) : max(tgt, diveT - dt / 4.0); version &+= 1; if diveT == tgt { objectWillChange.send() } }
        }
        tickPane(dt)
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
        guard followOn || followXYZ, let w = walk ?? Self.walkSource?() else { return }
        if followXYZ { tickFollowXYZ(dt, w); return }
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
    /// 自分を追う（xyz のみ）：4D の角度はさわらず、カメラの向きを自分のいる向きへ寄せる。遊びの中は「ゆるく回す」の分だけ
    private func tickFollowXYZ(_ dt: Double, _ w: Walk) {
        let v = rot4(w.pos), l = simd_length(SIMD3(v.x, v.y, v.z))
        guard l > 0.02 else { return }                                    // 超球の真ん中：向きが決まらない
        let d = SIMD3(v.x, v.y, v.z) / l
        let toYaw = atan2(d.x, d.z), toPit = max(-1.2, min(1.2, asin(max(-1, min(1, d.y)))))
        let eye = SIMD3(sin(viewYaw) * cos(viewPitch), sin(viewPitch), cos(viewYaw) * cos(viewPitch))
        let th = acos(max(-1, min(1, simd_dot(eye, d))))
        let out = th > 1e-6 ? max(0, th - followSlack * .pi / 180) / th : 0
        let t = max(0, min(1, (l - 0.05) / 0.25)), sure = t * t * (3 - 2 * t)   // 真ん中のそばは向きが急に変わるので、効きを弱める
        let k = (out * (1 - exp(-dt * 1.5 * followSpeed)) + (1 - exp(-dt * 0.15 * followDrift))) * sure
        viewYaw = Self.norm(viewYaw + Self.norm(toYaw - viewYaw) * k); viewPitch += (toPit - viewPitch) * k; version &+= 1
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
    @Published var wireT = 0.0                                        // ワイヤーの透明度（0 そのまま・1 見えない）
    @Published var wireAuto = true                                    // 線の自動整理（ダイブ画面：密な線と遠い線を薄くして、遠い殻を溶かし、赤星・紫星までの視線を開ける）
    static var renderK = 1.0
    /// ダイブで右に景色が出ている：左下の景色の画面は休む（右の大きな画面へ受け渡し）
    static var walkBigShown = false
    static var walkShells: (get: () -> Int, set: (Int) -> Void)?
    /// 連動の時、さんぽの層数を読んでこちらへ（毎コマ。変わっていれば形を作り直す）
    func pullLayers() {
        guard layersLink, let w = Self.walkShells else { return }
        let n = max(3, min(61, w.get()))                                 // 殻を宇宙に合わせている時は 21 より多くなる（こちらも 61 まで。多いと網目を粗くして軽く）
        if n != layers { layers = n; bump() }
    }
    /// こちらで層数を変えた：連動の時はさんぽへも
    func setLayers(_ n: Int) {
        let v = max(3, min(61, n))
        layers = v; bump()
        if layersLink, let w = Self.walkShells, w.get() != v { w.set(v) }
    }
    /// 球面さんぽの歩いた跡（S³ の上の長さ 1 の点。古い順）・今いる所・目印と通ったかどうか。アプリが起動した時に入れる（無ければ描かない）
    struct Walk { var trail: [SIMD4<Double>]; var pos: SIMD4<Double>; var marks: [SIMD4<Double>] = []; var hit: [Bool] = []; var poles: [Int] = []; var lap = 1; var head: SIMD4<Double>? = nil; var space = false; var fwd = SIMD4<Double>(0, 0, 1, 0)
        var vR = SIMD4<Double>(0, 0, 0, 0), vU = SIMD4<Double>(0, 0, 0, 0), vL = SIMD4<Double>(0, 0, 0, 0), fov = 70.0
        var plan: [SIMD4<Double>] = []; var dist = 0.0; var rail: [SIMD4<Double>] = []; var railGen = 0 }   // plan：決まった道・自分の道の、これから先の道（予定の道を出す時だけ）。dist：歩いた道のり   // fwd：進む向き。vR・vU・vL：景色を写す向き（右・上・見ている向き）、fov：景色の縦の視野（度）   // poles：通った極（FIXED の番号）
    static var walkSource: (() -> Walk)?
    static var mainBar: ((HyperLabState) -> AnyView)?                 // 窓の上の段（さんぽの窓のツールバーと同じ操作。Mac だけ）
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
    /// 覚える設定の一覧（保存のキーと値）。保存も読み込みもこの表から作るので、設定を足すのはここ 1 か所（並びは読み込む順。後の didSet が前の値を直すことがある）
    enum Saved { case d(String, ReferenceWritableKeyPath<HyperLabState, Double>), i(String, ReferenceWritableKeyPath<HyperLabState, Int>), b(String, ReferenceWritableKeyPath<HyperLabState, Bool>) }
    static let savedKeys: [Saved] = [
        .d("pitch", \.pitch), .d("roll", \.roll), .d("yaw", \.yaw), .d("zw", \.zw), .d("viewYaw", \.viewYaw), .d("viewPitch", \.viewPitch), .d("viewDist", \.viewDist),
        .d("leftDist", \.leftDist), .i("layers", \.layers), .i("mode", \.mode), .d("camW", \.camW), .i("hemi", \.hemi), .d("gloss", \.gloss), .b("glare", \.glare),
        .i("lzw", \.lzw), .b("cutOn", \.cutOn), .i("cutRef", \.cutRef), .d("cutAngDeg", \.cutAngDeg), .d("cutWDeg", \.cutWDeg), .i("cutKind", \.cutKind),
        .i("planeDir", \.planeDir), .d("cutPos", \.cutPos), .i("cut4Axis", \.cut4Axis), .b("cutSweep", \.cutSweep), .b("axes", \.axes), .b("axPlus", \.axPlus),
        .b("axThin", \.axThin), .b("walk", \.walk), .b("marksOn", \.marksOn), .i("polesMode", \.polesMode), .i("spaceMode", \.spaceMode), .d("starsPct", \.starsPct),
        .b("spin3Dview", \.spin3D), .b("layersLink", \.layersLink), .b("walkView", \.walkView), .i("lowView", \.lowView), .b("lowSwap", \.lowSwap),
        .b("lightWrap", \.lightWrap), .i("ovFx2", \.ovFx), .b("mainBarOn", \.mainBarOn), .b("lowFirst", \.lowFirst), .b("followOn", \.followOn),
        .b("followXYZ", \.followXYZ), .d("followSlack", \.followSlack), .d("followSpeed", \.followSpeed), .b("followHeading", \.followHeading),
        .d("followDrift", \.followDrift), .b("diveBlend", \.diveBlend), .b("soundPhones", \.soundPhones), .d("soundRush", \.soundRush), .b("seeThrough", \.seeThrough),
        .d("soundRail", \.soundRail), .d("soundSong2", \.soundSong), .d("soundWind2", \.soundWind), .b("soundFar", \.soundFar), .d("soundFarK", \.soundFarK),
        .d("feelK", \.feelK), .b("airOn", \.airOn), .b("coaster", \.coaster), .b("dopplerOn", \.dopplerOn), .d("dopK", \.dopK), .d("meriK", \.meriK), .d("topK", \.topK),
        .b("meterOn", \.meterOn), .b("meterVideo", \.meterVideo), .i("quality", \.quality), .b("adaptive", \.adaptive), .d("wireW", \.wireW),
        .d("soundPlace", \.soundPlace), .b("passOn", \.passOn), .b("noteOn", \.noteOn), .b("soundLayer", \.soundLayer), .d("soundBass", \.soundBass),
        .d("soundRough", \.soundRough), .d("wireT", \.wireT), .b("wireAuto", \.wireAuto), .i("panelTab", \.panelTab), .i("ovView", \.ovView),
        .b("ovShuffle", \.ovShuffle), .b("overlapGlow", \.overlapGlow), .b("ovZoom", \.ovZoom), .b("ovFlip", \.ovFlip), .d("shakeK", \.shakeK), .b("holeOn", \.holeOn),
        .d("wireWMap", \.wireWMap), .i("cursor", \.cursor), .b("naviCenter", \.naviCenter), .b("map2", \.map2), .b("ovShow", \.ovShow), .b("glareAuto2", \.glareAuto),
        .b("shutWalk", \.shutWalk), .b("shutAuto", \.shutAuto), .b("walkMenu", \.walkMenu), .b("walkPanelOn", \.walkPanelOn), .i("walkPanelSel", \.walkPanelSel),
        .b("axesDive", \.axesDive), .b("wipeLow", \.wipeLow), .i("hyperQ", \.hyperQ), .b("heavy", \.heavy), .b("planOn", \.planOn), .b("railOn", \.railOn),
        .i("planMark", \.planMark), .b("planShell", \.planShell), .b("planLong", \.planLong), .b("planDense", \.planDense), .b("opMode", \.opMode),
        .i("showMode", \.showMode), .i("spinMode", \.spinMode), .d("spinAmp", \.spinAmp), .d("spinLen", \.spinLen), .i("shellMode", \.shellMode), .d("splitX", \.splitX),
        .d("splitY", \.splitY), .b("diveThird", \.diveThird), .d("chaseDist", \.chaseDist), .d("chasePitch", \.chasePitch), .d("chaseYaw", \.chaseYaw),
        .b("autoCam", \.autoCam), .b("camShow", \.camShow), .b("padCam", \.padCam), .i("padCamStick", \.padCamStick), .b("diveOverview", \.diveOverview),
        .i("ovCursor", \.ovCursor), .i("depth4", \.depth4), .d("depth4K", \.depth4K), .b("depth4On", \.depth4On), .b("symGlow", \.symGlow), .d("trailW", \.trailW),
        .i("trailCol", \.trailCol), .b("poleEN", \.poleEN), .b("coordOn", \.coordOn), .b("panelHidden", \.panelHidden), .b("padOn", \.padOn),
        .b("clearAhead", \.clearAhead), .b("show3D", \.show3D), .b("lapClear", \.lapClear), .b("soundOn", \.soundOn), .d("soundVol", \.soundVol),
        .b("soundSpatial", \.soundSpatial), .d("starDepth", \.starDepth), .d("rot2XY", \.rot2XY), .d("rot2ZW", \.rot2ZW), .b("rot2Rings", \.rot2Rings),
        .b("rot2Swing", \.rot2Swing), .d("rot2Amp", \.rot2Amp), .d("shotEvery", \.shotEvery), .d("shotEase", \.shotEase), .b("shotCam", \.shotCam),
        .b("shotCurve", \.shotCurve), .d("shotCurveEvery", \.shotCurveEvery), .d("uiScale", \.uiScale)]
    var snapshot: [String: Any] {
        var s: [String: Any] = ["order": order]
        for k in Self.savedKeys {
            switch k {
            case .d(let n, let p): s[n] = self[keyPath: p]
            case .i(let n, let p): s[n] = self[keyPath: p]
            case .b(let n, let p): s[n] = self[keyPath: p]
            }
        }
        return s
    }
    func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: Self.saveKey) else { return }
        apply(d)
    }
    /// 覚えた設定を当てはめる（load と、確かめの往復）
    func apply(_ d: [String: Any]) {
        for k in Self.savedKeys {
            switch k {
            case .d(let n, let p): if let x = d[n] as? Double { self[keyPath: p] = x }
            case .i(let n, let p): if let x = d[n] as? Int { self[keyPath: p] = x }
            case .b(let n, let p): if let x = d[n] as? Bool { self[keyPath: p] = x }
            }
        }
        if let o = d["order"] as? [Int], o.count == 3, Set(o) == [0, 1, 2] { order = o }
        if ![0, 5, 6].contains(spinMode) { spinMode = 0 }
        uiScale = min(2, max(0.75, uiScale))
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
    // ---- 自動の動き（超球デモ・超球を詰める・視点切りかえ）の設定。動かす中身は HyperLabMotion.swift ----
    @Published var demoOn = false
    var demoGlass = 1.0                                                // デモの殻の濃さ：W 消失の真正面では透かして、中の赤玉を見せる
    // 超球（試作）：半径のちがう超球面を重ねて、外から中心へ敷き詰める。半径 r の超球面の広がり 2π²r³ を積分すると、超球の体積 π²/2
    @Published var fillOn = false
    var fillA = 1.0                                                    // どこまで詰めたか（残っている内側の半径。1 → 0）
    @Published var fillLayers = 4 { didSet { version &+= 1 } }        // 内側の超球（詰める・拡張のステージ）の球層の数：R ＝ 1 の層の数のうち何層ぶん描くか（1〜R ＝ 1 の層の数。多いほど重い）
    @Published var fillCount = 10 { didSet { version &+= 1 } }        // 詰める数：外の R ＝ 1 から中心へ、等しい間隔で何枚の超球面を詰めるか（2〜30。多いほど重い）
    @Published var fillAuto = true                                    // 内側の球層を自動で（VBR）：重い時は減らし、余裕があれば R ＝ 1 の層の数まで増やす
    // 超球面拡張（試作）：超球の中の小さい S³（ステージ）と、下のステージへの入口のブラックホール。第 1 段階は外から見る絵だけ（HyperLabExpand.swift）
    @Published var expandOn = false { didSet { if expandOn { fillOn = false }; version &+= 1 } }
    @Published var stageView = 0                                      // 光らせるステージ（0 外の R ＝ 1・1 R ＝ 0.8 …）
    @Published var stageOnly = false                                  // ほかのステージを消す（光らせるステージの S³ とブラックホールだけ）
    /// 今いる R の世界（超球の中の半径 R の S³。0.05〜1）：さんぽは宇宙の大きさに R をかけ（自分の大きさはそのまま。速さ・目印の見かけは 1/R）、
    ///   超球の窓の彗星・跡・目印・ダイブはこの半径の S³ の上に。R ＝ 0 は割り算がこわれるので 0.05 まで（特異点はいつか別の駅に）
    @Published var worldR = 1.0 { didSet { let v = max(0.05, min(1, worldR)); if v != worldR { worldR = v }; if worldR != oldValue { if !noSink { Self.worldRSink?(worldR) }; version &+= 1 } } }
    var noSink = false                                                // 書き出し用の状態：R の世界をさんぽの窓へ知らせない（再生で、今のさんぽの世界を変えないように）
    static var worldRSink: ((Double) -> Void)?
    /// さんぽの窓で泳いだ R を、超球の窓の今いる世界へ（超球の窓が開いている時）。コントローラーの十字（ダイブ・ドリル）も超球の窓へ
    static var worldRFromWalk: ((Double) -> Void)?, padAction: ((String) -> Void)?
    /// ドリル（B・十字の左）：今いる所から超球の中心をまっすぐ通って、反対側の点まで掘り進む。R は R0 → 0.05 → R0 となめらかに（中心で反対側の点へ抜ける）。
    ///   drillS：進んだ道のり（R0 を 1 として 0〜2。1 が中心）、drillK：超球の窓の見せ方の効き（掘る間 1、着いたら 0 へ）。ダイブ中は少し引いて、殻のあいだを落ちるのを見せる
    @Published var drillOn = false
    /// ドリルの決まった道：0 なし・1 往復ドリル（中心を通って行ったり来たり）・2 D の字めぐり（中心を通るドリル ＋ 地表を半周歩いて戻る）。端に着いたら少し止まる
    @Published var drillTour = 0 { didSet { if drillTour == 0 { tourWait = nil } else if oldValue == 0 && !drillOn { startDrill() } } }
    var tourWait: Double? = nil                                       // 次のドリルまで待つ秒数
    static let tourPause = 1.0
    static var tourWalkSink: ((Double) -> Void)?                      // D の字めぐり：さんぽの窓で、まっすぐこの角度だけ歩く（着いたら tourArrived）
    func tourArrived() { if drillTour == 2 { tourWait = Self.tourPause } }
    @Published var drillMirror = false                                // 鏡の世界：中心を抜ける時に体を回さない（本当に体の向きのままつきぬける）。反対側では、世界に対して自分が鏡写しになる。もう一度抜けると元へ
    var drillS = 0.0, drillU = 0.0, drillR0 = 1.0, drillK = 0.0
    static let drillLen = 7.0                                         // 掘り始めから反対側に着くまでの秒数
    static var drillSink: ((Int) -> Void)?
    func startDrill() { guard !drillOn, !runOn else { return }; drillR0 = worldR; drillU = 0; drillS = 0; drillOn = true; runLine = false; tunnelDrillStart(); Self.drillSink?(0); bump() }
    /// 超球ラン（B トンネル）：表面すれすれ → 穴から殻と殻のすき間へ → すき間を飛ぶ → … → 中心の炉 → 反対側へ脱出、をくり返す（HyperLabTunnel.swift）
    @Published var runOn = false { didSet { if runOn != oldValue { if runOn { startRun() } else { stopRun() } } } }
    /// ドリル・ドリルの道もトンネル（自分を通る 4D の断面）で見る
    @Published var tunnelView = false
    // ダイブ画面で見る超球ラン：通った道（4D の点。7 秒分）を金色の線で。書き出しでは記録した点を使う
    var runLine = false, runClock = 0.0
    var runTrail: [(t: Double, x: SIMD4<Double>)] = []
    var runPathOverride: [SIMD4<Double>]? = nil
    let hrun = HyperRun()
    var runT = 0.0, runGen = 0, runFlips = 0
    var tunHoles: [TunnelHole] = [], tunBase: TunnelBase? = nil
    var tunForce: Bool? = nil, tunOverride: SIMD4<Double>? = nil      // 書き出し：記録したトンネルの見え方（彗星の場所）をそのまま使う
    static var runPoseSink: ((SIMD4<Double>, SIMD4<Double>) -> Void)?   // ラン：さんぽの体の場所と前の向きを合わせる
    /// R の世界を滑らかに降りる・上る：−1 降りる・＋1 上る・0 止まる。速さは約 2 秒でなめらかに乗って、止める時もすっと減速する
    @Published var glideDir = 0
    @Published var glideSpeed = 1.0                                   // 降りる速さの倍率（1 で R 1 → 0.05 が約 16 秒）
    private(set) var glideV = 0.0                                      // 今の R の変わる速さ（1 秒あたり）
    static let glideMax = 0.06
    func tickGlide(_ dt: Double) {
        guard !drillOn, dt > 0 else { glideV = 0; return }
        let room = glideDir < 0 ? worldR - 0.05 : glideDir > 0 ? 1 - worldR : 1
        let to = Double(glideDir) * Self.glideMax * glideSpeed * min(1, max(0.1, room / 0.08))   // いちばん下・外の手前では減速して着地（ゆっくりでも必ず着く）
        glideV += (to - glideV) * (1 - exp(-dt * 1.5))
        if glideDir == 0 && abs(glideV) < 2e-4 { glideV = 0; return }   // ほとんど止まったら止める
        var r = worldR + glideV * dt
        if r <= 0.05 + 1e-4 && glideV < 0 { r = 0.05; glideDir = 0; glideV = 0 }
        if r >= 1 - 1e-4 && glideV > 0 { r = 1; glideDir = 0; glideV = 0 }
        if r != worldR { worldR = r }
    }
    func tickDrill(_ dt: Double) {
        if !drillOn, let w = tourWait { let left = w - dt; tourWait = left > 0 ? left : nil; if left <= 0 && drillTour != 0 { startDrill() } }   // 決まった道：止まったあと、次のドリル
        if !drillOn && runOn && !tunnelNow { if drillK < 1 { drillK = min(1, drillK + dt / 0.6); version &+= 1 }; return }   // ダイブ画面で見るラン：殻をうっすら出しておく
        guard drillOn else { if drillK > 0 { drillK = max(0, drillK - dt / 0.8); version &+= 1 }; return }
        drillK = min(1, drillK + dt / 0.6)
        let was = drillS
        drillU = min(1, drillU + dt / Self.drillLen)
        drillS = 2 * drillU * drillU * (3 - 2 * drillU)                  // 中心のあたりがいちばん速い
        if was < 1 && drillS >= 1 { Self.drillSink?(drillMirror ? 3 : 1) }   // 3：鏡の世界（体を回さずに抜ける）
        worldR = drillU >= 1 ? drillR0 : max(0.05, drillR0 * abs(1 - drillS))
        if drillU >= 1 {
            drillOn = false; Self.drillSink?(2)
            if drillTour == 1 { tourWait = Self.tourPause }                    // 往復ドリル：少し止まって、また中心へ
            else if drillTour == 2 { Self.tourWalkSink?(.pi) }               // D の字めぐり：地表をまっすぐ半周（π）歩いて、反対側（掘り始めた所）へ
        }
        version &+= 1
    }
    @Published var chaosOn = false { didSet { version &+= 1 } }      // 内核の演出：R が小さい殻ほど、焼けた鉄の色・ゆらぐ網目・脈打つ明るさ（オプション）
    @Published var rOnly = false { didSet { version &+= 1 } }        // つまみで選んだ半径 R の S³ だけを描く
    @Published var rOnlyR = 0.6 { didSet { version &+= 1 } }
    // 視点切りかえ（左下の地図のデモ版）：消失させる軸のちがう見え方へ、ぱっ、ぱっと切りかえる。傾き（前後・左右）を動かすので、2 重回転や Z-W 回転はそのまま回り続ける
    @Published var shotOn = false { didSet { if shotOn { claim(.shots); run.shotT = shotEvery; run.curveK = [] } else { shotName = "" } } }
    // つなぎ方：ぱっ（間隔ごとに切りかえる）・カーブ（見え方を順に通るなめらかな曲線の上を、止まらずに流れる。キャットマル・ロムの曲線）
    @Published var shotCurve = true { didSet { run.curveK = []; run.shotT = shotEvery } }
    @Published var shotCurveEvery = 3.0                               // カーブ：1 つの見え方から次までの時間（秒）
    @Published var shotEvery = 1.2                                    // 切りかえの間隔（秒）
    @Published var shotEase = 0.15                                    // つなぎの時間（秒）。0 ならその 1 コマで切りかわる
    @Published var shotCam = true                                     // 3D のカメラの向きも一緒に切りかえる
    @Published var shotName = ""                                      // 今の見え方の名前
    var run = HLMotionRun()                                            // 自動の動きの途中の値（時刻・つなぎの目印など。覚えない）
}
