// 次元おりがみ（ネイティブ版・移植の第 1 歩）：ウェブ版 hypercube.html の基本を、Swift と Metal（光で描く TesseractLab の描き方）で。
//   左：2D の展開図（正方形 6 枚）を折りたたんで立方体に。右：3D の展開図（立方体 8 つ）を折りたたんで超立方体に。
//   折り方はウェブ版（共通部品 nd-geom の PRESETS.okami）と同じ：腕が先（0〜0.60）、ふたは少しあと（0.45〜1）、なめらか（smootherstep）、
//     ふたは +y の腕の先、組み上がるにつれて中心が原点へ寄る。頂点は ±0.9（辺 1.8）。
//   回し方もウェブ版と同じ：左をドラッグ＝左の X-Z・Y-Z ＝ 右の X-W・Y-W（いっしょに回る）、⇧＋横ドラッグ＝Z-W、右をドラッグ＝右の 3D の回転（X-Z・Y-Z）。
//     超立方体は X-W → Y-W → Z-W → X-Y → X-Z → Y-Z の順に回し、w を遠近（D＝4.5、±(D − 0.5) ではさむ）で 3D へ写す。
//   色もウェブ版：立方体は中央とふた＝z の濃い青、±y 緑、±x ローズ。超立方体は中央とふた＝w の紫、±y 緑、±x ローズ、±z 水色。
//     面は展開図ほど濃く（紙の展開図）、組み上がると透ける。辺は手前が白く奥ほど暗い。手前の頂点はマゼンタ、奥は水色の目印
import SwiftUI
import MetalKit
import QuartzCore
import CoreText

/// 毎コマ変わる値（角度・組み立て具合・分解のぐあい）の知らせ（1 秒 15 回まで）
final class LiveTick: ObservableObject {}

final class OrigamiState: ObservableObject {
    // 毎コマ変わる値（組み立て具合と 6 つの角度）は @Published にしない：変わるたびにパネル全部を作り直すとコマが飛ぶので、
    //   時間を進めている間（tick の中）は、パネルの書きかえを 1 秒 15 回までにまとめる。スライダーなどで手で変えた時はすぐに
    private var inTick = false, uiPending = false, uiLast = 0.0
    //   知らせは live（別の入れ物）から出す：パネル全部ではなく、角度や組み立て具合を出している所（LiveRead の中）だけが作り直される
    let live = LiveTick()
    // つまみを動かしている間（tick の外）も、知らせは 1 秒 30 回まで（マウスの動きのたびに出すと、そのたびに作り直しが走る）。残りは次の tick で出す
    func uiChanged() {
        let now = CACurrentMediaTime()
        if inTick || now - uiLast < 1.0 / 30 { uiPending = true } else { uiLast = now; uiPending = false; live.objectWillChange.send() }
    }
    /// 動いている間のパネルの書きかえ（1 秒に何回）
    static var uiHz = 60.0
    private func flushUI() {
        guard uiPending else { return }
        let now = CACurrentMediaTime()
        if now - uiLast >= 1.0 / Self.uiHz { uiLast = now; uiPending = false; live.objectWillChange.send() }
    }
    var progress = 1.0 { willSet { uiChanged() } }            // 組み立て（0 展開図・1 組み上がり）
    // 色の組み立て具合：形（progress）に少し遅れてなめらかについていく。展開図のふつうの立体 → ガラス・4D の光と乗算・面の濃さは、
    //   これで決める＝組み上がった瞬間に色がぐっと変わらず、形ができたあとも少しのあいだ色がゆっくり移る（時間の決まり COLOR_LAG 秒）
    var colorP = Double.nan
    static let COLOR_LAG = 0.35
    var colorProg: Double { colorP.isNaN ? progress : colorP }
    @Published var playing = false           // 折る・開くの途中
    var target = 1.0
    var ax = 0.0 { willSet { uiChanged() } }                   // 左 X-Z ／ 右 X-W
    var ay = 0.0 { willSet { uiChanged() } }                   // 左 Y-Z ／ 右 Y-W
    var zw = 0.0 { willSet { uiChanged() } }                   // Z-W
    var xy = 0.0 { willSet { uiChanged() } }                   // 3D の回転（右の超立方体。左は X-Y だけ＝ウェブ版の標準）
    var xz = 0.0 { willSet { uiChanged() } }                   // 初めは正面（ウェブ版と同じ。全部の角度が 0 ＝「胞から」）
    var yz = 0.0 { willSet { uiChanged() } } 
    // ---- 5 次元 β（Origami5D.swift）：左に超立方体・右に 5 次元超立方体。上の X-W・Y-W・Z-W は 5 次元では X-V・Y-V・Z-V（v＝折りたたみでできた次元）----
    @Published var dim5 = false
    var xw5 = 0.0 { willSet { uiChanged() } }                  // 5 次元だけの面（超立方体は動かない）：X-W
    var yw5 = 0.0 { willSet { uiChanged() } }                  // Y-W
    var zw5 = 0.0 { willSet { uiChanged() } }                  // Z-W
    var wv5 = 0.0 { willSet { uiChanged() } }                  // W-V
    @Published var spin5 = false                               // 5 次元だけの 4 面を回し続ける
    @Published var net5 = OrigamiState.p5Dali                  // 5 次元の展開図（胞 10 個の親）。図鑑・見本・でたらめでえらぶ（OrigamiNet5.swift）
    @Published var net5No = 1                                  // 図鑑の番号（1〜9,694。図鑑に無い形は 0）
    @Published var atlas5Open = false                          // 5 次元の展開図図鑑の画面
    @Published var drag5Roll = true                            // 5 次元の窓のドラッグ：true 転がす（3D の回転＝形はゆがまない）・false 5 次元だけの X-W・Y-W（w がせり出す）
    var r5a: [[Double]] = OrigamiState.eye5, m5: [[Double]] = OrigamiState.eye5   // 5 次元の回転（4D・5D の分／3D も入れた全部）
    var tw5: (from: [Double], to: [Double], t: Double)? = nil   // 見え方のおすすめへなめらかに移る途中（10 面）
    // ---- 回し続ける（ウェブ版の回転バー。速さはウェブ版の 1 コマの角度 × 60 コマ、再生の速さもかかる）----
    // X-W・Y-W・Z-W（左は X-Z・Y-Z）
    @Published var spinX = false
    @Published var spinY = false
    @Published var spinZW = false
    // 3D の回転
    @Published var spinXY = false
    @Published var spinXZ = false
    @Published var spinYZ = false
    // ---- 再生（ウェブ版の「再生」の区切り）----
    @Published var loop = false               // 往復の自動再生（1 秒に 0.24）
    @Published var speed = 1.0                // 速さ（0.5・1・1.5・2・3・4 倍）
    static let speeds = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
    @Published var foldStagger = true         // 多段階で折る（切＝全部いっしょ。最大の段数 1 と同じ）
    // 組み上がりの向き（OrigamiAsmPose.swift）
    @Published var asmPose = 0                // 0 そのまま・1 胞・2 面・3 辺・4 頂点（等角）・5 自由
    @Published var asmVanish = 3              // 消失軸 0 x・1 y・2 z・3 w（いつもの W 消失）
    @Published var asmFree = [0.0, 0, 0, 0, 0, 0]   // 自由の角度（度）：X-W・Y-W・Z-W・X-Y・X-Z・Y-Z
    @Published var unfPose = 0                // 展開の向き：0 そのまま・1 W 消失にもどす（3D は残す）・2 W 正面 Z 正面（全部 0）・3 上から・4 横から・5 ななめ上から・6 自由
    @Published var unfFree = [0.0, 0, 0, 0, 0, 0]   // 展開の向きの自由の角度（度）
    @Published var asmPresets: [AsmPreset] = AsmPreset.load()
    @Published var asmPresetName = ""
    @Published var asmBasic: AsmBasic? = AsmBasic.load()   // 自分で決めた基本（↺ 基本にもどす の行き先）
    var asmLand: AsmLand? = nil, asmLastP = -1.0
    var asmSeenUp: [Double]? = nil, asmSeenDown: [Double]? = nil
    // 展開する時・組み上げる時の形の角度（折りたたみタブの 2 × 2 の表）。4D の角度（X-W・Y-W・Z-W）と 3D の角度（X-Y・X-Z・Y-Z）を別々に：
    //   0 そのまま（今の角度）・1 覚えた（前にその状態だった時の角度）・2 ゼロ（4D はまっすぐ＝ゆがみなし・3D は正面）
    /// おまかせ（入れている間は表を使わない）：0 表で決める・
    ///   1 ゆがみなし：開く時はいちばん近いまっすぐ（4D のゆがみを入れない）・組む時は前に組んだ向き（4D のかたむきも）へ
    ///   2 ゆがみも：開く時も組む時も今の向きのまま（4D のゆがみもそのまま展開図に）
    @Published var autoMode = 1
    var asmAuto: Bool { get { autoMode != 0 } set { autoMode = newValue ? max(1, autoMode) : 0 } }
    /// 開いた時に、4D の回し続けるを 3D に置きかえた分（組む時にもどす）：4D の X-W・Y-W・Z-W と、こちらで入れた 3D の X-Z・Y-Z・X-Y
    var spin4Saved: [Bool]? = nil, spin3Added: [Bool] = [false, false, false]
    /// 4D の回し続ける（X-W・Y-W・Z-W）の速さの倍率。開く時に 3D に置きかえる・組む時にもどすのを、一瞬ではなく 0.5 秒かけて（カクッとならないように）
    var spin4K = 1.0, spin4FadeOut = false
    static let SPIN4_FADE = 0.5
    @Published var intExact = true                                  // 積分の超球の輪切りを、遠近でも正確な形に（切ると近道＝ぷよぷよのゴムボール）
    @Published var inSphereDent = true                              // 内接球が、写した奥の胞にめりこんで見える所を暗く
    @Published var inSphereDentSharp = true                         // めりこみの境目をくっきり（画素ごとに奥の胞の中か外かで分ける）。切るとふんわり
    // （前の 2 × 2 の表のマス：今は使わない。古い保存・プリセットを読むためだけに残す）
    @Published var unf4 = 1
    @Published var unf3 = 1
    @Published var asm4 = 1
    @Published var asm3 = 1
    /// 前の 1 つのスイッチ（覚えた形へ）：古い保存・確かめ用
    var poseMemory: Bool {
        get { unf4 == 1 || unf3 == 1 || asm4 == 1 || asm3 == 1 }
        set { let v = newValue ? 1 : 0; unf3 = v; asm4 = v; asm3 = v; unf4 = unf4 == 2 ? 2 : v }
    }
    // 2 つの向き：組み上がっている時の向き（memUp）と、開いている時の向き（memDown）を別々に持つ。回すと今いる方が変わり、
    //   C で組む・開くと、もう一方の続きへ着地する（往復）。4D・3D の角度ごとに「別々（往復）」か「共通」か（sep4・sep3）
    @Published var memUp: [Double]? = nil     // 組んだ時の向き（6 つの角度）
    @Published var memDown: [Double]? = nil   // 開いた時の向き（6 つの角度）
    @Published var sep4 = true                // 表で決める時：4D の角度を 2 つの向きで別々に（往復）。切ると共通（今のまま持ちこむ）
    @Published var sep3 = false               // 表で決める時：3D の角度を別々に。切ると共通（開いている間に回した分は、組んだ時の向きも回る）
    @Published var foldCourse = false         // 一筆（くるくる）：いちばん長いつながりのはしから 1 個ずつ折る
    @Published var courseFromB = false        // 一筆の出発：はし A ／ はし B
    var courseCache: [String: [Int]] = [:], courseRootCache: [String: Int] = [:]
    @Published var foldMaxStages = 4          // 多段階の最大の段数（1〜4）。展開図の深さがこれより多い時は、近い深さをまとめる
    // ---- 自動ズーム（ウェブ版の「組み上げ時に大きさを自動で合わせる」と「大きさ ▾」：形が画面の何%を占めるか＝中心から端まで）----
    @Published var autoZoom = true            // 切ると、折りたたみ・分解でも今の大きさのまま
    // 展開図（0.5〜1）
    var zfNet = 0.85 { willSet { uiChanged() } }
    // 組み上がり（0.25〜0.85）
    var zfAsm = 0.5 { willSet { uiChanged() } }
    // 分解（0.5〜1）
    var zfXp = 0.86 { willSet { uiChanged() } }
    // 奥の表現：3D の奥ほど暗く（ウェブ版と同じ。0〜1）・4D の手前は光る／奥は乗算（0〜1）
    var depth3 = 1.0 { willSet { uiChanged() } }
    var depthDeep = 0.5 { willSet { uiChanged() } }               // 3D の奥を色濃く（奥ほど自分の色を掛けて深く・少し暗く）
    var line3W = 0.0 { willSet { uiChanged() } }                  // 線の 3D の奥行きでの太さ（−1〜1）：− 奥ほど細く（手前が太い）・＋ 奥ほど太く
    var line3K = 0.0 { willSet { uiChanged() } }                  // 線の 3D の奥行きでの濃さ（0〜1）：奥ほどうすく
    var slantSheen = 0.5 { willSet { uiChanged() } }              // 斜めの面の照り返し（目から見て斜めの面ほど、光の向きでふんわり光る）
    var mul4 = 0.6 { willSet { uiChanged() } }
    // 4D の手前を光らせる強さ（0〜1。既定 0.3）
    var glow4 = 0.3 { willSet { uiChanged() } }
    // 外から包む胞（4D の手前）を本物の色ガラスに（0〜1。既定 0.8）：正面はうすい色で中がよく見え、斜め・ふちほど自分の色で濃く染める
    var glass4 = 0.8 { willSet { uiChanged() } }
    // 展開図をふつうの（すけない）立体に（0〜1。既定 1）：組み上がるにつれてガラスへ
    var netSolid = 1.0 { willSet { uiChanged() } }
    // ファンタジーの強さ（0〜1。既定 1）：0 にすると、展開図のふつうの見え方のまま組み上がる（効果をまとめて切る）
    var fantasy = 1.0 { willSet { uiChanged() } }
    // 展開図の色で乗算（0〜1。既定 0.5）：組み上がるにつれて、面が自分の色のまま色つきセロハンのように重なる（色が急に変わらない）
    var netMul = 0.5 { willSet { uiChanged() } }
    // ---- 積分（OrigamiIntegral.swift）：立方体を w の方向に積む ----
    @Published var intOn = false                                   // 動かしている
    @Published var intPaused = false
    var intT = 0.0 { willSet { uiChanged() } }                     // 1 周の中の時刻
    var intN = 41.0 { willSet { uiChanged() } }                    // 区分の数（2〜512）
    @Published var intPace = 0                                     // 積む速さ：0 だんだん速く・1 一定
    @Published var intLidMode = 0                                  // 積分のふた：0 直角に開く・1 開けたまま・2 消す（薄く）・3 開けない（OrigamiLid.swift）
    @Published var intOutOpp = false                               // 取り出し口：入れた側／反対側
    @Published var intFly = true                                   // 外から飛びこむ演出
    @Published var intColor = 2                                    // 色：0 白・1 層ごとに 1 色・2 七色の縞・3 ドラゴンボール
    @Published var intBallSpin = true                              // 玉・殻を回す
    @Published var intStars = 1                                    // ドラゴンボールの星：1・4
    @Published var intLook = 0                                     // 積分中の超立方体：0 ふつう・1 線だけ・2 消す
    var intAmount = 1.0 { willSet { uiChanged() } }                // 入れる量（底から何割まで入れるか。0.1〜1）
    @Published var intAxes = 8                                      // 入れる向き（ビット：x 1・y 2・z 4・w 8）。2 つ以上で「何方向も同時」
    var intItems: [IntItem] = []
    // 見本の小窓（積分に詰める立方体 1 個を、ふつうの 3 次元の立方体として）：その小窓だけの状態。柄は本体（previewSrc）からうつす
    var isPreview = false
    weak var previewSrc: OrigamiState?
    @Published var intPreview = false                               // 積分タブに見本の小窓を出す
    // ---- 4 次元の水（OrigamiWater.swift）。積分の「② どう足す？」で選ぶ ----
    // サイコロ（OrigamiDice.swift）
    @Published var diceMode = 24                                    // 目の数：24（正方形ごと）・48（胞 × 面）
    @Published var diceOneShot = true                               // 一発（4D と 3D を同時に）・2 段階（胞が飛び出す）
    @Published var diceFaces = false                                // 超立方体の面にいつも目を描く
    @Published var diceRes: DiceResult? = nil                       // 出た目
    @Published var diceFlash = false                                // ドン！の札
    @Published var diceHist: [DiceResult] = []                      // これまでの目（新しい順）
    @Published var diceCount24 = [Int](repeating: 0, count: 24)
    @Published var diceCount48 = [Int](repeating: 0, count: 48)
    var diceRoll: DiceRoll? = nil                                   // 振っている途中
    var diceHold: SIMD3<Double>? = nil                              // 振ったあとの X-W・Y-W・Z-W（動かすまで遠近のまま）
    var diceEyeK = 0.0, diceDim = 0.0                               // 面の目の濃さ・超立方体をうすくする度合い（②の間）
    @Published var inSphereColor = 0                                // 内接球の色：0 アプリの色（近い胞の色）・1 レインボー（超球面アプリの層の色）
    @Published var inSphereTouch = true                             // 内接球が胞（面）に接する点を、光の輪で
    @Published var inSphereTouchCol = 0                             // 接点の輪の色：0 軸の色（x 赤・y 緑・z 青・w 紫）・1 胞の色（パレットの胞の色。−w を黄色にしていれば手前と奥がわかる）
    @Published var inSphere120 = false                              // 内接球の正 120 胞体のワイヤー（点 600・辺 1200。接点が正十二面体の部屋の真ん中）
    @Published var inSphereLat = true                               // 内接球の緯度（w 一定で切った球殻）。緯度・経度・円錐はいくつでも同時に
    @Published var inSphereCone = true                              // 内接球の円錐の面（θ 一定、5 枚）
    @Published var inSphereLon = true                               // 内接球の経度面（大円の球の半分 8 枚）
    @Published var inSphereGlass = true                             // 内接球をガラスに（超立方体のようなシースルー・ふちの反射・つや）
    @Published var inSphereLayers = 10                              // 内接球の片側の層の数（北・南それぞれ。全部で 2×−1 枚）
    @Published var inSphere = false                                 // 内接する超球面（回転バーの「内接球」、OrigamiInSphere.swift）
    @Published var intOnce = false                                  // 積分：1 往復（入れて取り出したら止める）か、くり返すか
    @Published var intView = 1                                      // 積分をはじめる時の見る向き：0 そのまま（w から）・1 横（x）＝輪切りが左右に並ぶ・2 横（y）＝下から積み上がる
    @Published var intShape = 0                                     // なにの体積？：0 超立方体（立方体を積む）・1 球柱・2 デュオシリンダー・3 タイガー
    @Published var waterReal = true                                  // 4 次元の水をリアルに（画素ごとの映りこみ・屈折・さざ波・キラキラ）。切ると前の図のような水
    @Published var intMethod = 0                                    // 0 輪切りを積む・1 4 次元の水を注ぐ・2 玉を詰める（OrigamiBalls.swift）
    // ---- 玉を詰める ----
    let balls4 = BallSim(dim: 4), balls3 = BallSim(dim: 3)
    @Published var ballR = 0.38                                      // 玉の半径（箱の半分の幅を 1 として）
    @Published var ballsAuto = false                                // どんどん入れる
    @Published var ballGravMode = 2                                 // 玉の重力の向き：0 画面の奥・1 画面の下・2 箱の −w（+W→−W）
    @Published var ballG = 6.0                                      // 玉の重力の強さ（0 で無重力）
    var ballsDropT = 0.0, ballsSeed = 0, ballsRev = 0, ballsNoRoom = 0
    var waterT = 0.0, waterTT = 0.0                                  // 1 回りの中の時刻・通しの時刻
    var waterH = -1.0 { willSet { uiChanged() } }                   // 水位（−1 空 〜 ＋1 いっぱい）
    var waterPhase = 0 { willSet { uiChanged() } }                  // 0 開ける・1 注ぐ・2 いっぱい・3 栓を抜く・4 抜ける・5 栓をする・6 空
    var waterOut: SIMD2<Double>? = nil                              // 底から流れ出る水のかたまり（上の端・下の端の w）
    var waterPour = -9.0                                             // 水の筋の上の端（w）
    // ---- 下水道（ウェブ版の穴の工事・排水口・通気口。OrigamiDrain.swift）----
    @Published var drainMode = 0                                    // 抜き方：0 底を全部開ける・1 小さい排水口（渦）・2 交互
    @Published var holesOpenSet = false                             // 排水口：栓をする（ふつう）／開けっぱなし（工事済みの時だけ）
    @Published var waterVent = true                                 // 通気口：あり＝空気が入ってふつうに抜ける、なし＝ごぼごぼゆっくり
    @Published var waterBallWall = true                             // 内接球を出している時：玉は壁（水が入らない）。切ると「内接球無視モード」（水は玉を通りぬける）。本物の 4D の水だけ
    var waterBallOn: Bool { inSphere && waterBallWall && waterNS }
    @Published var waterBallLook = 0                                // 水の時の内接球の見せ方：0 見えない玉（水族館の水槽のように、水が入って初めて穴で分かる）・1 すき通った真珠色の玉
    var waterCyc = 0, waterDOpen = 0.0, waterHEq = 0.0, waterEmptyT: Double? = nil   // 1 回りの数（交互の入れ替え）・開けっぱなしの水の深さ・つり合う水位
    var waterLid = 0.0, waterBLid = 0.0                             // 上のふた・底の栓の開き具合
    var waterVD = 0.0, waterSD = 0.0, waterBurst = 0.0, waterGlugN = -1, waterPrevPhase = 0, waterVented = true   // 渦のくぼみ・抜けた割合・開けた瞬間の吸い込み・ごぼっ
    @Published var waterNS = true                                   // 本物の 4D の水（32⁴ のナビエ–ストークスを GPU で。OrigamiNS4.swift）。切ると浅水方程式の水
    @Published var waterNSRes = 0                                   // 4D の水のマスの細かさ：0 おまかせ（16）・8・12・16・24・32
    // ---- 遊ぶモード（重力は画面の下。自分で回して、開けた所からこぼす。押している間だけ注ぐ）----
    @Published var waterFree = false {                              // 入れた時：ジョッキの口（ふた +W）を真上に向けて、ふたを開ける（水は底にたまり、上から注いだ水が口から入る）
        didSet {
            if waterFree && !oldValue { waterLidSet = true; waterFreeView(ay: waterFreeAY(0), xz: 0, yz: 0) }
            // 切った時：遊ぶモードで足していた 3D の傾き（X‐Z・Y‐Z）を正面に戻す（左の立方体は X‐Z・Y‐Z では回らないので、右だけ斜めに見えていた）
            if !waterFree && oldValue && (abs(xz) > 1e-4 || abs(yz) > 1e-4) { tween = (cur6, [ax, ay, zw, xy, 0, 0], 0, 1.2, projBlend, projBlend) }
        }
    }
    @Published var gravX = 0.0                                      // 好きな向きの重力（waterGravMode ＝ 3）：箱の x・y・z・w。長さは使う時に 1 に
    @Published var gravY = 0.0
    @Published var gravZ = 0.0
    @Published var gravW = -1.0
    var gravGrabW = false, gravGrabDir = SIMD2<Double>(1, 0)        // w のメーターの輪をつかんだか・つかんだ所の向き（真ん中から。外へ ＝ +w）
    @Published var gravHandleShow = true                            // 画面に重力ハンドル（矢印と w のメーター）を出すか
    var gravGrab = false                                            // 画面の重力ハンドルをつかんでいる間
    var paneSize: [Int: CGSize] = [:]                               // 絵の窓の大きさ（ポイント。重力ハンドルを指でつかむ時の当たり判定に）
    @Published var waterGravMode = 2 {                              // 遊ぶモードの重力：0 画面の奥（w の消失点へ。4D らしい）・1 画面の下（見慣れた）・2 箱の −w（+W→−W、積分と同じ。回してもこぼれない）
        didSet { }   // 切りかえても見る向きはそのまま。重力の向きだけが、なめらかに回って変わる（waterFreeTick）
    }
    /// 遊ぶモードの向き（Y‐W の角）：k ＝ 0 口が上・1 ななめ（ジョッキ）・2 横倒し（こぼれる）。重力が画面の奥なら、口（+W）が手前の時が「上」
    func waterFreeAY(_ k: Int) -> Double {
        let base = waterGravMode == 1 ? 0 : Double.pi / 2   // 画面の奥・箱の −w：口（+W）が手前の時が「上」
        return base + [-Double.pi / 2, -0.95, 0.4][max(0, min(2, k))]
    }
    @Published var waterG = 9.8                                     // 遊ぶモードの重力加速度（箱の半分を 0.9 m とすると 9.8 が本物）
    @Published var waterPourRate = 1.0                              // 注ぐ勢い
    @Published var waterPourX = 0.3                                 // 注ぐ場所（x・y・z、−1〜1）
    @Published var waterPourY = -0.35
    @Published var waterPourZ = 0.2
    @Published var waterLidSet = true                               // ふた（+W）を開ける（ジョッキの口。遊ぶモードは口を上にして始める）
    @Published var waterBottomSet = false                           // 底（−W）を開ける（抜き方が排水口なら排水口）
    @Published var waterPourHold = false                            // 注ぐボタンを押している間
    var waterGDir = SIMD4<Double>(0, -1, 0, 0)                      // 遊ぶモードの重力の向き（箱の x・y・z・w）。目標の向きへ なめらかに回っていく
    var waterGDirInit = false
    var waterCanPour: Bool { true }                                  // 遊ぶモード：どの向きでも注げる（箱のいちばん上の面から入る）
    var waterEntry4 = SIMD4<Double>(0, 0, 0, 0)                      // 遊ぶモード：筋が箱に入る所（4D、世界の単位）
    // 一時停止：注ぐのを止めるだけ（水の計算は続けて、水面が静かになる）
    var waterPauseT = 0.0                                           // 止めてからの時間（水の筋のしっぽが落ちる）
    var waterPauseK = 0.0                                           // 止めている度合い（0〜1、なめらかに）：底のふたを閉めて、流れを止める
    // 遊ぶモードの左の 3D の水（左の立方体の x・y・z）：重力の向き・水面の向き（ばねで追いかけて、ちゃぷちゃぷ）・筋が入る所
    var waterGDir3 = SIMD3<Double>(0, 0, -1)
    var waterN3 = SIMD3<Double>(0, 0, 1)
    var waterN3V = SIMD3<Double>(0, 0, 0)
    var waterEntry3 = SIMD3<Double>(0, 0, 0)
    @Published var waterSlice = 0                                   // 輪切り：0 なし・1 x・2 y・3 z ＝ 一定で切って、残りの 3D の水を左の窓に（本物の 4D の水の時）
    @Published var waterSlicePos = 0.0                              // 切る位置（−1〜1）
    @Published var waterVort = 1.0                                  // 渦の強調（渦度の閉じこめ ε）：粗いマスで消える細い渦を足し戻す。0 で なし
    var waterDrainH: Double? = nil                                  // 自動モードの「今すぐ抜く」：押した時の水位（nil ＝ いっぱいまで注いでから抜く、ふつう）
    @Published var drainSize = 0.58                                // 排水口の大きさ（底の幅の何倍か。4D では穴の広さは 3 乗）
    @Published var waterSwirl = 0.3                                 // 排水口を開けた時に残っている回転（x‐y の面）の強さ
    var nsPrevM4: simd_double4x4? = nil, nsPrevW = simd_double4x4(0)   // 箱の向きの前のコマ・回る速さ（ちゃぷちゃぷ用）
    var waterDragIdle = 99.0                                       // 最後に箱を回すドラッグをしてからの秒（離したら水をおだやかに）
    var waterShakeAcc = SIMD2<Double>(0, 0), waterShakeV = SIMD2<Double>(0, 0)   // ゆさぶり：このコマにたまったドラッグ量・なめらかにした手の速さ（画面の横・縦）
    var nsLagM4: simd_double4x4? = nil                              // 水が感じる「下」の向き：箱の向きに少し遅れてついてくる（回すと水が傾いて寄り、止めるとゆれもどる）
    @Published var waterNu = 0.004                                  // 本物の 4D の水の粘り（動粘性、世界の単位）。小さいほどさらさら（前は 0.012）
    @Published var waterSlosh = 1.0                                 // 回した時のちゃぷちゃぷの強さ（1 ＝ 本物どおり）
    var ns4: NS4? = nil, ns4Failed = false, nsVTarget = 0.0, nsPrevT = 0.0, nsPrevPhase = 0
    /// 4D の水のマスの細かさ（おまかせ：16。ユーザーが「いろいろ試したが 16⁴ で十分、これがいちばん軽い」）
    var ns4N: Int { [8, 12, 16, 24, 32].contains(waterNSRes) ? waterNSRes : 16 }
    func ns4Get() -> NS4? {
        if let s = ns4, s.N != ns4N { ns4 = nil; ns4Failed = false; nsVTarget = 0; _ = s }   // 細かさを変えたら作り直す（水は最初から）
        if ns4 == nil && !ns4Failed { ns4 = NS4(N: ns4N); if let s = ns4 { s.reset(level: -1) } else { ns4Failed = true } }
        ns4?.setBall(waterBallOn)                                       // 内接球の壁（入れた・切った時だけ作り直す）
        return ns4
    }
    var holeDA = 0.0, holeVA = 0.0, holeDHL = 0.0, holeVHL = 0.0, holeLastT = 0.0, holeShow = 0.0   // 格子のふたの開き具合（排水口・通気口）と、開け閉めの途中の明るさ
    lazy var swe = WaterSWE(us: OrigamiState.wUS)
    var intFront = -1.0 { willSet { uiChanged() } }
    var intBack = -1.0 { willSet { uiChanged() } }
    var intFilling = true
    // ---- 断面（OrigamiSection.swift）：組み上がった形を、平らな包丁（超立方体は w、立方体は z に垂直）で切った切り口 ----
    @Published var secOn = false
    var secPos = 0.0 { willSet { uiChanged() } }                  // 包丁の位置（−1 いちばん手前の頂点 〜 ＋1 いちばん奥の頂点）
    @Published var secPlay = false                                // 包丁を自動で往復させる
    var secDirSign = 1.0
    var secInfo = ["", ""] { willSet { uiChanged() } }            // 切り口の形の名前（立方体・超立方体）
    var smartLine = 0.7 { willSet { uiChanged() } }   // 線を立体になじませる（賢く）：胞の色を混ぜた角の色・輪郭ははっきり・中の線はうすく。0 で今までの線
    var softMul = 0.5 { willSet { uiChanged() } }   // やわらかい乗算（0 今までの乗算・1 いちばんやわらか）。目がつかれにくいように
    // 色温度（−1 青み 〜 ＋1 暖かみ。既定 0）：画面全体の色を、明るさを変えずにずらす（青みがかって目がつかれる時に）
    var warmth = 0.0 { willSet { uiChanged() } }
    // 密度の乗算：つぶれた胞ほど（4D。0〜1、既定 0.6）・斜めから見た面ほど（3D。0〜1、既定 0.4）色を深く掛ける
    var squash4 = 0.6 { willSet { uiChanged() } }
    var slant3 = 0.4 { willSet { uiChanged() } }
    // 線を胞の色にして乗算でなじませる（0〜1。既定 0＝白い線のまま）
    var lineTint = 0.0 { willSet { uiChanged() } }
    @Published var lineTintMode = 1                            // 線をなじませる色：0 その胞の色・1 重なっている胞の色を掛け合わせた色（セロハンを重ねた色）
    // 線の 4D の奥行き：0 同じ・1 奥ほどうすく（既定）・2 奥ほど濃く。強さ（0〜1）
    @Published var line4 = 1
    var line4K = 1.0 { willSet { uiChanged() } }
    var lineWidthNet = 1.0 { willSet { uiChanged() } }             // 線の太さ（展開図の時。全部の線の倍率 0.5〜3）
    var lineWidthSolid = 1.0 { willSet { uiChanged() } }           // 線の太さ（組み上がりの時）。組み立てる間はなめらかに切りかわる
    var inSphereWireW = 1.0 { willSet { uiChanged() } }
    var inSphereDepth = 0.6 { willSet { uiChanged() } }
    @Published var inSphereFilm = false                            // 緯度の殻を油膜（シャボン玉）に：少し暗い透けた玉で、ふちほど虹色がゆらぐ。色（胞の色）はそのまま
    var inSphereTone = 0.75 { willSet { uiChanged() } }            // 油膜の殻の色のトーン（0.3〜1。下げると落ち着いた色）
    /// 内接球の出現の時計（0〜1）：組み上がって内接球が見えはじめてから 1.8 秒で 1。0 なら何も出ていない。
    ///   正 120 胞体は 8 つの接点から結晶が育ち、緯度の殻は w の方向に積み上がり、経度は扇・円錐は花のように順に
    var inSphereAppear = 0.0
    static let SPH_APPEAR = 1.8            // 内接球の遠近（手前の膜と線は明るく太く、奥はうすく細く。0〜1）            // 内接球のワイヤーの太さ（線の太さとは別。0.5〜4）
    /// 今の線の太さ（展開図 → 組み上がりへ、組み具合でなめらかに）
    var lineWidthNow: Double { lineWidthNet + (lineWidthSolid - lineWidthNet) * Self.smoother(max(0, min(1, progress))) }
    var line4W = -0.7 { willSet { uiChanged() } }                  // 線の 4D の奥行きでの太さ（−1〜1）：− 奥ほど細く（手前が太い）・＋ 奥ほど太く・0 同じ。濃さ（line4）とは別
    // 形どうしの映り込み（ツルピカ。0〜1）：形の真ん中から 6 方向を撮った絵を、面が鏡の向きで読む
    var reflSelf = 0.7 { willSet { uiChanged() } }
    // スタジオの光の帯（つや。0〜1.5。既定 0＝切）：カメラのうしろのななめの細長いライトが、正面のガラスに光の帯として映る
    var stripK = 0.0 { willSet { uiChanged() } }
    // 開く（展開）の速さ：組み立ての何倍か（ウェブ版は同じ）
    var unfoldK = 1.0 { willSet { uiChanged() } }
    var loopDir = 1.0
    // ---- 投影（ウェブ版：遠近／平行。平行の時は W の角度が付いている・W を回している時だけ平行。胞から以外の「どこから見る」は平行）----
    @Published var perspMode = true           // true 遠近（既定）・false 平行投影
    var projBlend = 0.0                       // 4D → 3D の写し方の混ざり（0 遠近・1 平行）。なめらかに移る
    var presetPar: Double? = nil              // 「どこから見る」で決めた投影（W を動かすまで）
    var presetHold = SIMD3<Double>(0, 0, 0)   // その時の X-W・Y-W・Z-W
    // ---- どこから見る（ウェブ版の PROJ_PRESETS と周回）：視線の向きに X-W・Y-W・Z-W を 1 つずつ足していく ----
    static let EA = Double.pi / 4, EB = asin(1 / sqrt(3.0)), EC = asin(0.5)
    static let views: [(name: String, a: Double, b: Double, c: Double, par: Bool, note: String)] = [
        ("胞から", 0, 0, 0, false, "視線 (0,0,0,1)｜内と外の立方体（遠近あり）"),
        ("面から", EA, 0, 0, true, "視線 (1,0,0,1)/√2｜12 頂点（六角柱）"),
        ("辺から", EA, EB, 0, true, "視線 (1,1,0,1)/√3｜14 頂点"),
        ("頂点から", EA, EB, EC, true, "視線 (1,1,1,1)/2｜菱形十二面体（等角図）"),
    ]
    @Published var viewSel = -1               // 最後に選んだ見方
    // 見せる胞（ウェブ版の「見せる胞」）：0 全部・1 表だけ・2 裏だけ。
    //   表＝ひとつ上の次元の目から見て表を向いている胞。超立方体は w の向こうの目（4D→3D の写し方の目）から見て、多くて 4 個（胞からだと蓋の 1 個だけ）。
    //   立方体は、カメラから見て表を向いている面（多くて 3 面）。裏だけ＝その反対。胞ごと（面も辺も）描かない
    @Published var faceSide = 0
    // 見えている胞の数（窓ごと：[見せている数, 全部]）。表だけ・裏だけの時、窓の上の札に（ウェブ版の「見えている胞 4 / 8」）
    var sideShown = [[0, 6], [0, 8]] { willSet { uiChanged() } }
    /// その胞が表か（組み上がった形での外向きの向きで決める。ウェブ版の xpIsFront と同じ）
    func cellFront(_ cell: Cell, _ n: Int, eye: SIMD3<Double>) -> Bool {
        let (fa, fv) = Self.fixed(cell, n)
        if n == 5 { return cellFront5(fa, fv) }
        if n == 4 {
            var e = SIMD4<Double>(0, 0, 0, 0); e[fa] = fv
            // 遠近：目 (0,0,0,D) から胞の真ん中 half·n を見て表 ⇔ 回したあとの w ＞ half／D（平行なら w ＞ 0）
            return (m4 * e).w > Self.half / camW * (1 - projBlend) + 1e-6
        }
        var p = [0.0, 0.0, 0.0]; p[fa] = fv
        let o = place([0, 0, 0], 3).0, c = place(p.map { $0 * Self.half }, 3).0, nv = place(p, 3).0 - o
        return simd_dot(nv, eye - c) > 1e-6
    }
    // 見方を選んだ時の投影：0 おまかせ（胞からは遠近、面・辺・頂点からは平行＝ウェブ版）・1 いつも遠近（ふだん目で見る見え方）・2 いつも平行（形がそろってきれい）
    @Published var viewProj = 0 { didSet { if viewSel >= 0 && !cycling { presetPar = viewPar(Self.views[viewSel].par) } } }
    func viewPar(_ par: Bool) -> Double { viewProj == 1 ? 0 : viewProj == 2 ? 1 : (par ? 1 : 0) }
    @Published var cycling = false            // 胞 → 面 → 辺 → 頂点 を自動で周回
    // 一周の秒数
    var cyclePeriod = 12.0 { willSet { uiChanged() } }
    var cyclePhase = 0.0
    var tween: (from: [Double], to: [Double], t: Double, dur: Double, p0: Double, p1: Double)? = nil
    // ---- 立方体・表示（ウェブ版の「立方体」「表示」）----
    @Published var left3DAll = false          // 立方体の 3D の回転：false＝X-Y だけ（自分の平面の回転だけ）・true＝全部（X-Y・X-Z・Y-Z）
    @Published var displayMode = 0            // 0 両方・1 超立方体（右上に立方体のミニ）・2 超立方体だけ・3 立方体だけ
    @Published var swapViews = false          // 立方体と超立方体の左右を入れかえる
    @Published var wireOnly = false           // ワイヤー（面を描かない）
    // ---- 手前と奥の辺を色で強調（ウェブ版の「点」タブ：手前＝ふたの胞・奥＝真ん中の胞）----
    // 手前と奥の辺を色で強調（マゼンタ・水色）。図形をそのまま立体に見せたいので、初めは切（線で確かめたい時に入れる）
    @Published var ehOn = false
    @Published var ehNear = SIMD3<Float>(1.0, 0.267, 0.867)   // #ff44dd
    @Published var ehFar = SIMD3<Float>(0.2, 0.898, 1.0)      // #33e5ff（ユーザーの希望で水色）
    @Published var ehNearOn = true                               // 手前（ふた）の胞の辺を強調するか
    @Published var ehFarOn = true                                // 奥（真ん中）の胞の辺を強調するか
    @Published var ehCells: [String: SIMD3<Float>] = [:]         // ほかの胞（面）の辺の強調："4:px"（超立方体の ＋X の胞）・"3:ny"（立方体の −Y の面）→ 色。入っている胞だけ強調
    var ehWidthOther = 3.0 { willSet { uiChanged() } }           // ほかの胞の辺の太さ（画素）
    // 太さ（画素）
    var ehWidthNear = 3.0 { willSet { uiChanged() } }
    var ehWidthFar = 3.0 { willSet { uiChanged() } }
    // ---- 置いた点（OrigamiPoints.swift）。ptRev：変わった回数（描き直しの合図）----
    @Published var userPts: [UPoint] = [] { didSet { ptRev += 1 } }
    var ptRev = 0
    @Published var ptLabels = true             // 名前（座標）を出す
    @Published var ptLeft = true               // 立方体にも (x, y, w) に出す
    @Published var ptStatus = ""
    var ptSize = 0.55 { willSet { uiChanged() } }   // 置いた点の大きさ（手前・奥の目印は対象外）
    // 手前（ピンク）・奥（水色）の頂点の目印：色・大きさ・表示・重なりの乗算（点のタブ。ウェブ版の「既定の点」）
    @Published var markNear = SIMD3<Float>(1.0, 0.267, 0.867)   // #ff44dd
    @Published var markFar = SIMD3<Float>(0.2, 0.898, 1.0)      // #33e5ff
    var markSize = 0.65 { willSet { uiChanged() } }             // 半径 0.055 の何倍か（既定 0.65＝置いた点（大きさ ×0.55）の 1.3 倍くらい）
    @Published var markShowNear = true
    @Published var markShowFar = true
    @Published var markGlue = true                              // 重なった所だけ色を掛け合わせる
    @Published var markSame = true                              // 手前と奥の目印を、画面の上で同じ大きさに（遠近で大きさを変えない＝重なると皆既日食）
    @Published var markMagnet = true                            // 手前と奥の目印が重なりそうになったら、ぴたっと吸いつく（磁石）
    @Published var markFlash = true                             // ぴったり重なった瞬間に、光の輪
    var markAlign = 1.0, markWasAligned = false, markFlashT = 9.0   // 2 つの目印を結ぶ線と、目のずれ（ラジアン）・重なっていたか・光の輪が出てからの秒
    // 内接球の回転（模様が回る。球はまんまるなので形と接点は変わらない）：0 なし・1 3D（層ごとに速さがちがう）・2 4D の二重回転
    @Published var inSphereSpin = 0
    @Published var inSphereSpinSpeed = 1.0                      // 回る速さ（×）
    @Published var inSphereDiff = 0.6                           // 3D：層ごとの速さの差（0＝地球儀・1＝極は止まる）
    @Published var inSphereRatio = 0                            // 4D：2 つの面（X-Y・Z-W）の速さの比（OrigamiState.sphRatios の番号）
    @Published var inSphereHopf = true                          // 4D：模様の点が走る道（ホップの輪）を光る輪で
    @Published var inSphereFlash = true                         // 模様の経線が接点を通る時に、接点の輪がチカッと光る
    var inSphereT = 0.0                                         // 回った角（ラジアン）
    static let markNearDef = SIMD3<Float>(1.0, 0.267, 0.867), markFarDef = SIMD3<Float>(0.2, 0.898, 1.0)
    // ---- 回転アニメ（入力した角度まで再生。空欄は今のまま）----
    @Published var animXW = ""
    @Published var animYW = ""
    @Published var animZW = ""
    // ---- 角度のプリセット・往復（OrigamiPlay.swift）----
    @Published var presets: [AnglePreset] = AnglePreset.load()
    @Published var presetName = ""
    @Published var ppPresets: [PingPongPreset] = PingPongPreset.load()   // 保存した往復
    @Published var ppPresetName = ""
    @Published var editPreset: UUID? = nil    // 編集中の角度のプリセット
    @Published var editPP: UUID? = nil        // 編集中の往復のプリセット
    @Published var ppStops: [[Double]] = [[0, 0, 0, 0, 0, 0], [45, 35.26, 30, 0, 0, 0]]   // 停留点（度。X-W・Y-W・Z-W・X-Y・X-Z・Y-Z）
    // 1 区間の秒数
    var ppSec = 3.0 { willSet { uiChanged() } }
    @Published var ppCycle = false            // 動く順番：false 往復（A→B→C→D→C→B→A…）・true ぐるっと（A→B→C→D→A…）
    @Published var ppEase = "spring"          // 動き方：spring ばね・turn ターン・sine 単振動・cradle ゆりかご・bounce バウンド
    // 単振動の緩やかさ
    var ppSine = 1.0 { willSet { uiChanged() } }
    // ばねの弾み
    var ppSpring = 0.5 { willSet { uiChanged() } }
    // ターンのきびきび
    var ppTurn = 0.4 { willSet { uiChanged() } }
    @Published var ppRunning = false          // 往復中（片道 1 回も含む）
    var pp: PingPong? = nil
    var ppOnceFwd = true                      // 片道ボタン：次は A→B（false なら B→A）
    // ---- 画面（ウェブ版のパネルと表示）----
    @Published var showAxes = true            // 座標軸
    @Published var panelOpen = true           // 右のパネル（スペースキーで開け閉め）
    @Published var panelLeft = false          // パネルを左に（B キー）
    @Published var panelTab = 0               // 0 折りたたみ・1 回転・2 見え方・3 点
    @Published var raster = true              // 描き方：true 三角形（超立方体向け。4×MSAA でなめらか・軽い）・false 光の道（宇宙・面の網目・星屑つき）
    @Published var renderScale = 0.0          // 描く細かさ：0＝自動（重い時だけ細かさを下げて 144 コマを守る）・1・0.85・0.75
    var autoScale = 1.0                       // 自動の時の今の細かさ（1 → 0.85 → 0.75 → 0.67）
    // 画面の細かさの何割で描くか。下げると軽くなって 144 コマに届きやすい
    var effScale: Double { renderScale > 0 ? renderScale : autoScale }
    @Published var split = 0.3                // 立方体の窓の広さ（境目をドラッグ。立方体はアナロジーなので小さめに＝3 割）
    var camW = 4.5 { willSet { uiChanged() } }
    @Published var look = 0
    // ---- 光と質感（ウェブ版の visual-fx：照り返しライト・グレア・鮮やかさ、shadeFace の奥・内側の濃さ）----
    @Published var shine = true              // 照り返しライト
    // 照り返しの強さ（0〜4）
    var shineK = 1.0 { willSet { uiChanged() } }
    // 照りの広さ（−1 鋭く小さく・0 今まで・1 広くやわらか）
    var shineSpread = 0.0 { willSet { uiChanged() } }
    // 主光の向き：カメラから見た左右（度）
    var shineAz = -30.0 { willSet { uiChanged() } }
    // 上下（度）
    var shineEl = 33.0 { willSet { uiChanged() } }
    // グレア（ウェブ版の今の設定と同じ 0。上げると白いキラッが出る）
    var glare = 0.0 { willSet { uiChanged() } }
    // 鮮やかさ
    var vivid = 0.0 { willSet { uiChanged() } }
    // 映り込み（スタジオの空と照明）
    var envK = 0.35 { willSet { uiChanged() } }
    // 奥の胞ほど濃く・深い色に（ウェブ版の「奥を濃く（4次元）」は初め切＝0。どの面も同じうすさのガラス）
    var deep = 0.0 { willSet { uiChanged() } }
    // 入れ子の内側の面ほど濃く（初め 0＝ウェブ版と同じ）
    var inner = 0.0 { willSet { uiChanged() } }
    // ---- 宇宙（OrigamiSpace.swift：組み立てるにつれて、箱が宇宙モードの雰囲気に。組み上がった瞬間に光の波）----
    @Published var spaceMode = 2             // 0 組み立てに合わせる・1 入・2 切（初めは切＝ウェブ版の見た目）
    // 星の数（%）
    var starsPct = 100.0 { willSet { uiChanged() } }
    @Published var bgSpace = false           // 背景も宇宙に（星空と星雲）。ふだんは紺のまま
    @Published var meshOn = false            // 面の光の網目（ふだんは出さない）
    // 面の光の網目：1 辺の升の数
    var gridN = 6.0 { willSet { uiChanged() } }
    var flashT = 9.0, lastProg = 1.0         // 光の波が出てからの秒・前のコマの組み立て具合（組み上がった瞬間を見つける）
    /// 照り返しライトの時のざらつきの倍率（visual-fx の shineRough：今までの 0.8 倍、広さで −85%〜0.7 まで）
    func roughMul(_ r0: Double) -> Double {
        let b = r0 * 0.8, s = shineSpread
        return (s < 0 ? b * (1 + 0.85 * s) : b + (max(b, 0.7) - b) * s) / r0
    }
    /// 色を濃く（彩度を上げて少し暗く。visual-fx の deepen）
    static func deepen(_ c: SIMD3<Float>, _ t: Double) -> SIMD3<Float> {
        guard t > 0 else { return c }
        let Y = simd_dot(c, SIMD3(0.299, 0.587, 0.114)), sat = Float(1 + t), dk = Float(max(0.18, 1 - 0.45 * t))
        return simd_clamp((SIMD3(repeating: Y) + (c - Y) * sat) * dk, .zero, SIMD3(repeating: 1))
    }
    var settingsTimer: Timer?                 // 設定の保存（OrigamiSettings.swift）
    // 胞の色のパレット（OrigamiPalette.swift）：3D・4D × ±X〜±W、補色モード・中心だけ補色・軸の色を立体に合わせる（＋側／−側）、選んでいる枠
    // 展開図のかたち（OrigamiNets.swift）と、折りの変換のとりおき
    @Published var net: NetDef = OrigamiState.netDali
    @Published var atlasOpen = false          // 展開図図鑑の画面（OrigamiNetAtlas.swift）
    var netCache: [Int: ([Double], [Aff])] = [:]
    var netMorph: NetMorph? = nil             // 展開図の組み変わりの途中
    var netMorphFoldAfter = false             // 組み変わったら組み立てる（図鑑から選んだ時）
    @Published var netAnim = true             // 展開図を切りかえる時に組み変わりアニメを入れる
    @Published var pal3: [String: UInt32] = OrigamiState.palDef3
    @Published var pal4: [String: UInt32] = OrigamiState.palDef4
    @Published var palComp = false
    @Published var palCompCenter = false
    @Published var axisSyncOn = false
    @Published var axisSyncMinus = false
    @Published var palSel = "4:px"
    var zoom = [1.0, 1.0], dist = [9.0, 9.0], center = [SIMD2<Double>(0, 0), SIMD2<Double>(0, 0)]   // 見る所（形の真ん中へなめらかに寄る）
    // 図形の移動（ウェブ版の移動パッド・⌘／Ctrl＋ドラッグ）：絵を画面の上で平行にずらす量（窓の幅・高さの半分を 1 とする。右・上が＋。窓ごと）。
    //   見る位置（カメラ）は動かさないので、図形の見え方（遠近のかかり方）は変わらない（ウェブ版の setViewOffset と同じ）
    var pan = [SIMD2<Double>(0, 0), SIMD2<Double>(0, 0)] { willSet { uiChanged() } }
    var paneWpt = [400.0, 400.0], paneHpt = [400.0, 400.0]   // 窓の幅・高さ（ポイント。ドラッグの量を割合に直すため）
    @Published var panPad = true                 // 移動パッド（窓の左の丸）を出す
    /// 画面で (dx, dy) ポイント（右・下が＋）つかんで動かす：中身がつかんだ向きへついてくる
    func panBy(_ i: Int, _ dx: Double, _ dy: Double) {
        pan[i] += SIMD2(2 * dx / max(50, paneWpt[i]), -2 * dy / max(50, paneHpt[i]))
    }
    static let half = 0.9

    func reset() {
        ax = 0; ay = 0; zw = 0; xy = 0; xz = 0; yz = 0; xw5 = 0; yw5 = 0; zw5 = 0; wv5 = 0; zoom = [1, 1]; view3 = matrix_identity_double4x4
        xyManualOff = 0; pend = [0, 0, 0, 0, 0]; stepRemain = [0, 0, 0]; stepVel = [0, 0, 0]; updateMats()
    }

    // ---- 手で回す（ウェブ版 hypercube.html と同じ回し方。ドラッグになめらかについていく）----
    //   （離すとすべって止まる慣性は、ウェブ版に無いのでやめた）
    //   左の窓のドラッグ：X-W・Y-W（左は X-Z・Y-Z）の角度に足す。Z-W で裏返っている間（cos < 0）は向きを逆に（見た目の前後が逆になるので）
    //   右の窓のドラッグ：つかんだ形を、画面の縦の軸（左右ドラッグ）・横の軸（上下ドラッグ）のまわりに回し、X-Y → X-Z → Y-Z の 3 つの角度に分け直す（ウェブ版の turn3D）。
    //     右へドラッグ＝手前の面が右へ、下へドラッグ＝手前の面が下へ。手で回して生まれた X-Y は左の立方体には伝えない（xyManualOff）。⇧＋横ドラッグ：Z-W
    var xyManualOff = 0.0                     // 右を手で回して生まれた X-Y の分（左の立方体は無視する）
    var rotRev = 0.0                          // 手で回した回数（止まっているかの判定に）
    var dragging = false
    enum DragCh: Int { case l4x, l4y, zw, r3x, r3y, x5, y5, wv5 }      // x5・y5・wv5：5 次元の窓（5 次元だけの X-W・Y-W・W-V）
    var pend = [0.0, 0, 0, 0, 0]              // まだ回していない分（なめらかについていく。離したらその場で止まる＝ウェブ版と同じ）
    /// ドラッグ：マウスが動いたらその場ですぐ回す（ウェブ版と同じ。なめらかについていくと、手から遅れてゴムでひっぱるように重く感じる）。
    ///   パネルの書きかえは、時間を進める時と同じく 1 秒 15 回までにまとめる（マウスが動くたびに作り直すとコマが飛ぶ）
    func drag(_ ch: DragCh, _ d: Double) {
        // 知らせつきの値（cycling）は、変わる時だけ書く（同じ値でも書くたびに画面全体の作り直しが走る）
        //   角度の往復の間も、右の窓の 3D の回転（r3x・r3y）は止めずに見る向き（view3）を回す。4D の向きを手で動かす時は往復を止める
        let view3D = pp != nil && (ch == .r3x || ch == .r3y)
        // 4D の水のちゃぷちゃぷ：ドラッグを「コップをゆさぶる手の動き」としてためる（画面の横・縦、ラジアン）
        if ch == .r3x || ch == .l4x { waterShakeAcc.x += d } else if ch == .r3y || ch == .l4y { waterShakeAcc.y += d }
        waterDragIdle = 0
        dragging = true; if pp != nil && !view3D { stopPP() }; if cycling { cycling = false }; tween = nil
        inTick = true; applyStep(ch.rawValue, d); inTick = false
    }
    // ---- 90° 回す（X・Y・Z キー）：「あと何度回すか」をためて、ばねのようになめらかに回し切る ----
    //   押すたびに 90° 足す（zz なら 180°）。ほかの操作（回し続ける・どこから見る・ドラッグ）とは足し合わせで、途中で止まらない。
    //   前は行き先を決めて 1.2 秒で回す「なめらか移動」だったので、ほかの操作で上書きされたり、回し続けるが止まったりした
    var stepRemain = [0.0, 0.0, 0.0], stepVel = [0.0, 0.0, 0.0]     // X-W・Y-W・Z-W の残り（ラジアン）と速さ
    func stepPlane(_ k: Int, _ deg: Double) {
        if pp != nil { stopPP() }                                          // 角度の往復・周回は角度を毎コマ決めるので止める
        if cycling { cycling = false }
        stepRemain[k] += deg * .pi / 180
    }
    func tickSteps(_ dt: Double) {
        guard dt > 0 else { return }
        let w = 5.0                                                        // ばねの強さ（90° を約 1.2 秒で回し切る。止まり際も出だしもなめらか）
        var moved = false
        for k in 0..<3 where abs(stepRemain[k]) > 1e-7 || abs(stepVel[k]) > 1e-7 {
            stepVel[k] += (w * w * stepRemain[k] - 2 * w * stepVel[k]) * dt
            var m = stepVel[k] * dt
            if abs(stepRemain[k]) < 0.002 && abs(stepVel[k]) < 0.02 { m = stepRemain[k]; stepVel[k] = 0 }   // 残りわずかなら最後まで
            stepRemain[k] -= m
            switch k { case 0: ax = Self.wrapPi(ax + m); case 1: ay = Self.wrapPi(ay + m); default: zw = Self.wrapPi(zw + m) }
            // なめらか移動（どこから見る など）の途中なら、その出発と行き先も同じだけずらす（次のコマで上書きされない）
            if var tw = tween { tw.from[k] += m; tw.to[k] += m; tween = tw }
            moved = true
        }
        if moved { updateMats() }
    }
    func tickDrag(_ dt: Double) {
        guard dt > 0 else { return }
        let follow = 1 - exp(-dt * 30)
        for c in 0..<5 {
            var step = pend[c] * follow
            if abs(pend[c] - step) < 1e-4 { step = pend[c] }                    // 残りがわずかなら最後まで（いつまでも動き続けない）
            pend[c] -= step
            if abs(step) > 1e-12 { applyStep(c, step) }
        }
    }
    static func wrapPi(_ a: Double) -> Double { var x = (a + .pi).truncatingRemainder(dividingBy: 2 * .pi); if x < 0 { x += 2 * .pi }; return x - .pi }
    /// 向き R ＝ Y-Z(γ)・X-Z(β)・X-Y(α) を 3 つの角度に分け直す（ウェブ版の decomposeRot3D）。解は 2 通りあるので、今の角度に近いほう（数字が飛ばない）
    static func decompose(_ m: simd_double4x4, _ prev: [Double]) -> [Double] {
        func R(_ i: Int, _ j: Int) -> Double { m[j][i] }                       // 行 i・列 j
        let b0 = asin(max(-1, min(1, -R(0, 2)))), cb = cos(b0)
        var a0: Double, g0: Double
        if abs(cb) > 1e-6 { a0 = atan2(-R(0, 1), R(0, 0)); g0 = atan2(-R(1, 2), R(2, 2)) }
        else { a0 = prev[0]; g0 = -R(0, 2) > 0 ? a0 - atan2(R(1, 0), R(1, 1)) : atan2(R(1, 0), R(1, 1)) - a0 }
        let s1 = [a0, b0, g0], s2 = [a0 + .pi, .pi - b0, g0 + .pi]
        func dist(_ v: [Double]) -> Double { zip(v, prev).reduce(0) { $0 + abs(wrapPi($1.0 - $1.1)) } }
        return (dist(s1) <= dist(s2) ? s1 : s2).map(wrapPi)
    }
    /// 右：画面の縦の軸まわりに h（右へ＝手前の面が右へ）、横の軸まわりに v（下へ＝手前の面が下へ）回す（ウェブ版の turn3D）
    func turn3D(_ h: Double, _ v: Double) {
        let q = Self.R(2, 0, h) * Self.R(2, 1, -v)
        let prev = [xy, xz, yz], r = Self.decompose(q * c3, prev)
        xy = r[0]; xz = r[1]; yz = r[2]
        xyManualOff = Self.wrapPi(xyManualOff + Self.wrapPi(xy - prev[0]))
    }
    func applyStep(_ c: Int, _ t: Double) {
        let flip: Double = cos(zw) < 0 ? -1 : 1
        switch DragCh(rawValue: c)! {
        case .l4x: ax = Self.wrapPi(ax + t * flip)
        case .l4y: ay = Self.wrapPi(ay + t * flip)
        case .zw: zw = Self.wrapPi(zw + t)
        case .r3x: if pp != nil { view3 = Self.R(2, 0, t) * view3; updateMats() } else { updateMats(); turn3D(t, 0) }
        case .r3y: if pp != nil { view3 = Self.R(2, 1, -t) * view3; updateMats() } else { updateMats(); turn3D(0, t) }
        case .x5: xw5 = Self.wrapPi(xw5 - t); tw5 = nil                      // 5 次元の窓：横ドラッグで w がせり出す（ウェブ版の p5XW −= dx）
        case .y5: yw5 = Self.wrapPi(yw5 + t); tw5 = nil
        case .wv5: wv5 = Self.wrapPi(wv5 + t); tw5 = nil
        }
        rotRev += 1; updateMats()
    }
    // 回転の行列（毎コマ 1 回作って使い回す）
    // 角度の往復の間だけの、見る向きの 3D の回転（往復が決める 6 つの角度の上から、さらに 3D で回す）。往復が止まったら X-Y・X-Z・Y-Z に入れて元にもどす
    var view3 = matrix_identity_double4x4
    private(set) var m4 = matrix_identity_double4x4, r4a = matrix_identity_double4x4, c3 = matrix_identity_double4x4, l3 = matrix_identity_double4x4, rxy = matrix_identity_double4x4
    static func R(_ i: Int, _ j: Int, _ t: Double) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        m[i][i] = cos(t); m[j][j] = cos(t); m[i][j] = sin(t); m[j][i] = -sin(t)   // 列 i が (cos, sin)：e_i → cos e_i ＋ sin e_j
        return m
    }
    func updateMats() {
        rxy = Self.R(0, 1, xy - xyManualOff)                                         // 左の立方体の X-Y（右を手で回した分は除く）
        if left3DAll { rxy = view3 * Self.R(1, 2, yz) * Self.R(0, 2, xz) * rxy }     // 「全部」：立方体も X-Z・Y-Z で一緒に転がる
        c3 = view3 * Self.R(1, 2, yz) * Self.R(0, 2, xz) * Self.R(0, 1, xy)         // X-Y → X-Z → Y-Z（w はそのまま）。往復中は見る向きの回転も
        r4a = Self.R(2, 3, zw) * Self.R(1, 3, ay) * Self.R(0, 3, ax)                // X-W → Y-W → Z-W
        m4 = c3 * r4a
        l3 = Self.R(1, 2, ay) * Self.R(0, 2, ax)                                     // 左：X-Z → Y-Z
        updateMats5()                                                                // 5 次元（Origami5D.swift）
    }

    // ---- 分解（くっついた ⇔ バラバラ。ウェブ版の applyExplode・xpCellE・数える）----
    @Published var explodeRaw = 0.0          // スライダー（0 くっついた・1 全部バラバラ）
    @Published var xpStagger = true          // 時間差（1 個ずつ順に）
    // 離す距離の倍率
    var xpDistK = 1.0 { willSet { uiChanged() } }
    var xpAnim: (from: Double, to: Double, t: Double, total: Double)? = nil
    static let XP_DUR = 0.72, XP_STAG = 0.05, XP_FLASH = 0.35
    var labels: [[SIMD3<Double>]] = [[], []]  // 番号の札の位置（離したあとの胞の中心。左・右）
    var xpStag: Double { xpStagger ? Self.XP_STAG : 0 }
    static func easeOutBack(_ u: Double, _ k: Double = 1.7) -> Double { 1 + (k + 1) * pow(u - 1, 3) + k * pow(u - 1, 2) }
    static func easeInBack(_ u: Double, _ k: Double = 1.4) -> Double { (k + 1) * u * u * u - k * u * u }
    /// 全体の進み（札の濃さ・ボタンの向き）
    var explodeE: Double { if let a = xpAnim { return a.from + (a.to - a.from) * Self.smoother(min(1, a.t / a.total)) }; return Self.smoother(explodeRaw) }
    /// 胞 i の今の離し具合（アニメ中は胞ごとに時間差・バラす時は行き過ぎ、くっつける時は一度ためてから吸いつく）
    func xpCellE(_ i: Int) -> Double {
        guard let a = xpAnim else { return Self.smoother(explodeRaw) }
        let u = max(0, min(1, (a.t - Double(max(0, i - 1)) * xpStag) / Self.XP_DUR))
        return a.from + (a.to - a.from) * (a.to > a.from ? Self.easeOutBack(u) : Self.easeInBack(u))
    }
    /// くっついた瞬間の光（0〜1）。中心は最後の胞が吸いついた時に
    func xpFlash(_ i: Int, _ n: Int) -> Double {
        guard let a = xpAnim, a.to == 0 else { return 0 }
        let arrive = Double(i == 0 ? n - 2 : i - 1) * xpStag + Self.XP_DUR, dt = a.t - arrive
        return dt >= 0 && dt < Self.XP_FLASH ? 1 - dt / Self.XP_FLASH : 0
    }
    func startXp(_ to: Double) {
        let from = explodeE
        if abs(from - to) < 1e-4 { xpAnim = nil; explodeRaw = to; return }
        xpAnim = (from, to, 0, Self.XP_DUR + (dim5 ? 8 : 6) * xpStag + (to == 0 ? Self.XP_FLASH : 0))
    }
    var apart: Bool { if let a = xpAnim { return a.to == 1 }; return explodeRaw >= 0.5 }
    // 数える：まずバラして、番号の順に 1 個ずつ光らせる（まだの胞はうっすら、今の胞は濃く）
    @Published var counting = false
    @Published var countIdx = -1
    var countPhase = 0, countT = 0.0          // 0 バラしている・1 1 個ずつ・2 数え終わった
    static let XP_STEP = 0.85
    func startCount() { counting = true; countPhase = 0; countIdx = -1; countT = 0; startXp(1) }
    func endCount() { counting = false; countIdx = -1 }
    /// 胞の面・辺の強さ（くっついた瞬間の光・数えている時）
    func cellFocus(_ i: Int, _ n: Int) -> (face: Double, edge: Double) {
        let fl = xpFlash(i, n)
        if fl > 0 { return (1 + 0.4 * fl, 1 + 1.8 * fl) }
        guard counting, countPhase == 1, countIdx < n else { return (1, 1) }
        return i > countIdx ? (0.12, 0.16) : i == countIdx ? (1.7, 1.3) : (1, 1)
    }
    /// 離す量（3D）。組み上がり：外向きへ（新しい次元の向きは斜めへ逃がす）、展開図：中心からの距離に比例して広げる。途中は折り具合で混ぜる
    func explodeOffsets(_ CV: [[SIMD3<Double>]], _ n: Int) -> [SIMD3<Double>] {
        let S = 1.8, DF = 2.2 * xpDistK, GN = 1.2 * xpDistK, last = CV.count - 1
        let m = Self.smoother(max(0, min(1, progress)))
        let ctr = CV.map { vs in vs.reduce(SIMD3<Double>(0, 0, 0), +) / Double(vs.count) }, c0 = ctr[0]
        let rad = CV.indices.map { i in CV[i].map { simd_distance($0, ctr[i]) }.max() ?? 0 }
        return CV.indices.map { i in
            let e = i == 0 ? 0 : xpCellE(i)
            guard e != 0 else { return .zero }
            let fo = m > 0 ? foldedOffset(i, n, i == last ? DF * e * 1.35 : DF * e) : .zero
            var no = SIMD3<Double>(0, 0, 0)
            if m < 1 {
                let rel = ctr[i] - c0, len = simd_length(rel), far = 1.0 - 0.25 * max(0, len / S - 1)
                no = len > 0.6 * S ? rel * (GN * e / S * far) : foldedOffset(i, n, e * (rad[i] + rad[0] + GN))
            }
            return no * (1 - m) + fo * m
        }
    }
    /// 組み上がりの離す向き（胞の外向き。x・y はそのまま、z は (0.55, 0.42, 1)×1.25、新しい次元は (0.75, −0.75, −0.3)×1.4）を、形と同じに回す
    func foldedOffset(_ i: Int, _ n: Int, _ d: Double) -> SIMD3<Double> {
        let EZ = simd_normalize(SIMD3<Double>(0.55, 0.42, 1)) * 1.25, EF = simd_normalize(SIMD3<Double>(0.75, -0.75, -0.3)) * 1.4
        var q = [Double](repeating: 0, count: n)
        switch Self.cells(n)[i] { case .center: q[n - 1] = -1; case .cap: q[n - 1] = 1; case .arm(let a, let s): q[a] = s }
        var o: SIMD3<Double>
        if n == 5 { return foldedOffset5(q, d) }
        if n == 3 {
            let r = l3 * SIMD4(q[0], q[1], q[2], 0)
            o = SIMD3(1, 0, 0) * r.x + SIMD3(0, 1, 0) * r.y + EF * r.z
            let v = rxy * SIMD4(o * d, 0); return SIMD3(v.x, v.y, v.z)                // 左は X-Y だけ
        }
        let r = r4a * SIMD4(q[0], q[1], q[2], q[3])
        o = SIMD3(1, 0, 0) * r.x + SIMD3(0, 1, 0) * r.y + EZ * r.z + EF * r.w
        let v = c3 * SIMD4(o * d, 0)
        return SIMD3(v.x, v.y, v.z)
    }
    static let shortNames = [["−Z（中心）", "+Y", "−Y", "+X", "−X", "+Z（蓋）"], ["−W（中心）", "+Y", "−Y", "+X", "−X", "+Z", "−Z", "+W（蓋）"], ["−V（中心）", "+Y", "−Y", "+X", "−X", "+Z", "−Z", "+W", "−W", "+V（蓋）"]]
    static let longNames = [["中央面", "上面", "下面", "右面", "左面", "最上蓋"], ["中央固定核胞", "上ヒンジ胞", "下ヒンジ胞", "右ヒンジ胞", "左ヒンジ胞", "前ヒンジ胞", "後ヒンジ胞", "連鎖頂点胞"], ["中央固定核胞", "上ヒンジ胞", "下ヒンジ胞", "右ヒンジ胞", "左ヒンジ胞", "前ヒンジ胞", "後ヒンジ胞", "外ヒンジ胞", "内ヒンジ胞", "連鎖頂点胞"]]
    /// 組み立てる・開く（今の向きの逆へ。ウェブ版の ▶）
    var lastTickT = 0.0
    // コマ数（左・右の窓）：GPU で 1 コマ描くのにかかった時間（ミリ秒、ならした値）と、1 秒に出したコマの数
    var gpuMs = [0.0, 0.0], fps = [0, 0]
    lazy var driver = FrameDriver(st: self)
    /// 1 コマに 1 回だけ時間を進める（窓が 2 つあっても、片方だけでも）
    func tickOnce(_ now: Double) {
        if lastTickT == 0 { lastTickT = now; return }
        let dt = now - lastTickT
        if dt < 0.002 { return }
        lastTickT = now; tick(min(0.05, dt))
    }
    func toggleFold() { loop = false; target = progress > 0.5 ? 0 : 1; playing = true }
    func playFold() { loop = false; target = 1; playing = true }
    func playUnfold() { loop = false; target = 0; playing = true }
    func toggleLoop() { playing = false; loop.toggle(); loopDir = progress >= 1 ? -1 : 1 }
    func nextSpeed() { let i = Self.speeds.firstIndex(of: speed) ?? 1; speed = Self.speeds[(i + 1) % Self.speeds.count] }
    // 回転バーのボタン（ウェブ版と同じ決まり）
    var allW: Bool { spinX && spinY && spinZW }
    var w2Only: Bool { spinX && spinY && !spinZW }
    var all3D: Bool { spinXY && spinXZ && spinYZ }
    var anySpin: Bool { spinX || spinY || spinZW || spinXY || spinXZ || spinYZ }
    /// W の 3 面（X-W・Y-W・Z-W）を同時に（どれか切なら全部入、全部入なら全部切）
    func toggleWAll() { let t = !allW; spinX = t; spinY = t; spinZW = t }
    /// X-W・Y-W だけ（Z-W あり中に押したら Z-W だけ止めて切りかえる）
    func toggleW2() { if w2Only { spinX = false; spinY = false } else { spinX = true; spinY = true; spinZW = false } }
    func toggle3D() { let t = !all3D; spinXY = t; spinXZ = t; spinYZ = t }
    func toggle6() { let t = !(allW && all3D); spinX = t; spinY = t; spinZW = t; spinXY = t; spinXZ = t; spinYZ = t }
    /// 補正：z を画面に垂直に立て直す（z を傾ける Z-W・X-Z・Y-Z を 0 に、その回転も止める。X-W・Y-W・X-Y はそのまま）
    func snap() {
        zw = 0; xz = 0; yz = 0; spinZW = false; spinXZ = false; spinYZ = false; pend[2] = 0; pend[3] = 0; pend[4] = 0
        stepRemain[2] = 0; stepVel[2] = 0                                  // Z-W の 90° の残りも捨てる
        // なめらかに回っている途中なら、行き先の Z-W・X-Z・Y-Z も 0 に（でないと次のコマで回転が上書きして、補正が消える）
        if var tw = tween { for k in [2, 4, 5] { tw.from[k] = 0; tw.to[k] = 0 }; tween = tw }
        updateMats()
    }
    /// リセット：回転を止めて、全部の角度を 0 に（正面）
    func resetAll() { memUp = nil; memDown = nil; asmLand = nil; asmPose = 0; asmVanish = 3; if unfPose >= 2 { unfPose = 0 }; stopSpins(); stopPP(); cycling = false; tween = nil; stepRemain = [0, 0, 0]; stepVel = [0, 0, 0]; presetPar = nil; viewSel = -1; pan = [.zero, .zero]; reset() }
    func stopSpins() { spinX = false; spinY = false; spinZW = false; spinXY = false; spinXZ = false; spinYZ = false; spin4Saved = nil; spin4FadeOut = false; spin4K = 1; if spin5 { spin5 = false } }
    /// ゆがみなしで開く時：4D の回し続ける（X-W・Y-W・Z-W）を 3D（X-Z・Y-Z・X-Y）に置きかえる（展開図をゆがませずに回し続ける）
    func swapSpinsTo3D() {
        let s4 = [spinX, spinY, spinZW]
        guard s4.contains(true) else { return }
        spin3Added = [s4[0] && !spinXZ, s4[1] && !spinYZ, s4[2] && !spinXY]
        // 4D はすぐには止めず、0.5 秒かけて止める（止まりきったら tick で切る）
        spin4FadeOut = true
        if s4[0] { spinXZ = true }; if s4[1] { spinYZ = true }; if s4[2] { spinXY = true }
        spin4Saved = s4
    }
    /// 組む時：置きかえた 3D の回し続けるを、元の 4D にもどす（こちらで入れた 3D が、まだ入っている分だけ）。もどしたら true
    func restoreSpins4D() -> Bool {
        guard let s4 = spin4Saved else { return false }
        // 止めている途中なら、そこから回しはじめる。止まりきっていたら 0 から 0.5 秒かけて
        if spin4FadeOut { spin4FadeOut = false } else { spin4K = 0 }
        let still = [spinXZ, spinYZ, spinXY]
        for i in 0..<3 where s4[i] && (still[i] || !spin3Added[i]) { if i == 0 { spinX = true } else if i == 1 { spinY = true } else { spinZW = true } }
        if spin3Added[0] { spinXZ = false }; if spin3Added[1] { spinYZ = false }; if spin3Added[2] { spinXY = false }
        spin4Saved = nil; spin3Added = [false, false, false]
        return true
    }
    /// 投影：平行にしたい時（ウェブ版の wantParallel）
    /// 平行投影にするか：「平行投影」を選んでいれば、W の角度が 0（いつもの形）でも平行に。
    ///   （ウェブ版は W を回した時だけ平行にしていたが、それだと最初の形で切りかえても何も変わらなかった。
    ///    W の角度 0 の平行投影では、外の立方体と内の立方体がぴったり重なって 1 つの立方体に見える＝それが本当の平行投影）
    var wantParallel: Bool { !perspMode && !diceKeepsPersp }
    /// どこから見る：k 番の見方へ（animated＝今の角度からなめらかに移る。3D の回転は 0 に、回転は止める）
    func goView(_ k: Int, animated: Bool) {
        let v = Self.views[k]
        cycling = false; stopSpins(); playing = false; loop = false; viewSel = k; xyManualOff = 0
        pend = [0, 0, 0, 0, 0]
        let to = [v.a, v.b, v.c, 0, 0, 0], p1 = viewPar(v.par)
        if animated { tween = ([ax, ay, zw, xy, xz, yz], to, 0, 1.2, projBlend, p1) }
        else { ax = to[0]; ay = to[1]; zw = to[2]; xy = 0; xz = 0; yz = 0; projBlend = p1; tween = nil }
        presetPar = p1; presetHold = SIMD3(to[0], to[1], to[2]); updateMats()
    }
    func toggleCycle() {
        cycling.toggle(); tween = nil
        if cycling { stopSpins(); playing = false; loop = false; progress = 1; xy = 0; xz = 0; yz = 0; xyManualOff = 0; cyclePhase = 0; viewSel = -1 }
        else { presetPar = projBlend >= 0.5 ? 1 : 0; presetHold = SIMD3(ax, ay, zw) }
    }
    func tickView(_ dt: Double) {
        if pp != nil { return }                                           // 往復中は、往復が角度と投影を決める
        if var tw = tween {
            tw.t += dt
            let f = Self.smoother(tw.t / tw.dur)
            var a = [Double](repeating: 0, count: 6)
            for k in 0..<6 { a[k] = tw.from[k] + Self.wrapPi(tw.to[k] - tw.from[k]) * f }   // どの面も短いほうへ回る
            ax = a[0]; ay = a[1]; zw = a[2]; xy = a[3]; xz = a[4]; yz = a[5]
            projBlend = tw.p0 + (tw.p1 - tw.p0) * f
            tween = tw.t >= tw.dur ? nil : tw
            return
        }
        if cycling {                                                      // 胞 → 面 → 辺 → 頂点 →（胞）を 4 区間で。区間ごとに smootherstep で、それぞれの見方で一瞬たまる
            cyclePhase += dt / max(1, cyclePeriod); cyclePhase -= floor(cyclePhase)
            let seg = cyclePhase * 4, i = Int(seg) % 4, j = (i + 1) % 4, f = Self.smoother(seg - floor(seg))
            let A = Self.views[i], B = Self.views[j], pa = viewPar(A.par), pb = viewPar(B.par)
            ax = A.a + (B.a - A.a) * f; ay = A.b + (B.b - A.b) * f; zw = A.c + (B.c - A.c) * f
            projBlend = pa + (pb - pa) * f
            return
        }
        // 「どこから見る」で決めた投影は、W を動かす（回す・ドラッグ・スライダー）まで続く
        if let p = presetPar, spinX || spinY || spinZW || simd_length(SIMD3(Self.wrapPi(ax - presetHold.x), Self.wrapPi(ay - presetHold.y), Self.wrapPi(zw - presetHold.z))) > 1e-3 { _ = p; presetPar = nil; viewSel = -1 }
        let target = presetPar ?? (wantParallel ? 1 : 0)
        let step = dt / 0.5                                                // 0.5 秒で移る（ウェブ版の ensureProjection）
        projBlend += max(-step, min(step, target - projBlend))
    }
    func tick(_ dt: Double) {
        inTick = true
        defer { inTick = false; flushUI() }
        if loop {                                                             // 往復（ウェブ版：1 コマ 0.004 × 速さ）
            progress += 0.576 * speed * dt * loopDir                        // ウェブ版：1 コマ 0.004 を 144 コマ/秒で
            if progress >= 1 { progress = 1; loopDir = -1 } else if progress <= 0 { progress = 0; loopDir = 1 }
        } else if playing {
            // ウェブ版の 1 倍と同じ（1 コマ 0.005 を 144 コマ/秒で＝1 秒に 0.72 ＝ 約 1.4 秒）。開く（展開）は unfoldK 倍
            let sp = dt * 0.72 * speed * (target < progress ? unfoldK : 1), d = target - progress
            if abs(d) <= sp { progress = target; playing = false } else { progress += d > 0 ? sp : -sp }
        }
        flashT += dt
        if lastProg < 0.999 && progress >= 0.999 { flashT = 0 }
        lastProg = progress
        asmTick()                                                          // 組み上がりの向きへ回す・展開で W 消失へもどす
        if var x = xpAnim { x.t += dt; if x.t >= x.total { explodeRaw = x.to; xpAnim = nil } else { xpAnim = x; uiPending = true } }
        if counting {
            if countPhase == 0 { if xpAnim == nil && explodeRaw >= 1 { countPhase = 1; countT = Self.XP_STEP } }
            else {
                countT += dt
                if countPhase == 1 && countT >= Self.XP_STEP { countT = 0; countIdx += 1; if countIdx >= (dim5 ? 10 : 8) { countPhase = 2 } }
                else if countPhase == 2 && countT > 3 { endCount() }
            }
        }
        tickDrag(dt)
        tickPP(dt)
        tickView(dt)
        tickSteps(dt)
        markTick(dt)                                                       // 手前と奥の目印：磁石・重なった光
        sphereSpinTick(dt)                                                 // 内接球の模様の回転
        tick5(dt)                                                          // 5 次元：5 次元だけの 4 面を回し続ける
        if colorP.isNaN { colorP = progress }
        else if abs(progress - colorP) > 1e-4 { colorP += (progress - colorP) * (1 - exp(-dt / Self.COLOR_LAG)) } else { colorP = progress }
        diceTick(dt)
        netMorphTick(dt)
        if isPreview {                                                     // 見本の小窓：柄だけ本体からうつす（段は 1 個のまま）
            if let s = previewSrc {
                if intColor != s.intColor { intColor = s.intColor }
                if intStars != s.intStars { intStars = s.intStars }
                if intBallSpin != s.intBallSpin { intBallSpin = s.intBallSpin }
            }
        } else if intOn && intMethod == 2 {                                // 玉を詰める：組み上がっている時だけ
            if !intPaused && progress >= 0.92 && explodeE < 0.25 { ballsTick(dt) }
            if !intItems.isEmpty { intItems = [] }
        } else if intOn && intMethod == 1 {                                // 4 次元の水：組み上がっている時だけ時間を進める
            if progress >= 0.92 && explodeE < 0.25 { waterTick(dt) }       // 一時停止中も水は動かす（注ぐのを止めるだけ。水面は静かになっていく）
            if !intItems.isEmpty { intItems = [] }
        } else if intOn {                                                  // 積分：組み上がっている時だけ時間を進める
            if !intPaused && progress >= 0.92 && explodeE < 0.25 {
                intT += dt
                // 1 往復：入れて取り出して空になったら、そこで止める（「最初から」でもう一度）
                if intOnce { let c = intCycleT; if intT >= c { intT = c - 1e-6; intPaused = true } }
            }
            intItems = intUpdate()
        } else if !intItems.isEmpty { intItems = [] }
        if secPlay && secOn {                                              // 断面の包丁を自動で往復（端から端まで約 8 秒）
            secPos += dt * 0.25 * secDirSign
            if secPos >= 1 { secPos = 1; secDirSign = -1 } else if secPos <= -1 { secPos = -1; secDirSign = 1 }
        }
        // 内接球の出現の時計：見えている間は進め、見えなくなったら 0 へ（次に組み上がった時に、また育つ）
        if inSphere && progress > 0.92 && explodeE < 0.25 { if inSphereAppear < 1 { inSphereAppear = min(1, inSphereAppear + dt / Self.SPH_APPEAR) } }
        else if inSphereAppear != 0 { inSphereAppear = 0 }
        let k = speed * dt * 144                                              // ウェブ版の 1 コマの角度 × 144 コマ/秒（ウェブ版は 144 コマ/秒の時の量で決めてある。速さをずらして同じ姿勢に戻りにくく）
        //   着地（組む・開く）の途中でも止めずに回す：着地の出発と行き先も同じだけ回す
        //   ただし止めている途中の 4D（spin4FadeOut）は、行き先（ゆがみのない向き）を動かさない＝止まりながら、ぴったりそこへ着く
        func land(_ i: Int, _ d: Double) { if asmLand != nil && !(i < 3 && spin4FadeOut) { asmLand!.from[i] += d; asmLand!.to[i] += d } }
        // 4D の速さの倍率：止める時は 0.5 秒で 1 → 0（0 になったら切る）、回しはじめは 0 → 1。なめらかに（smoother）
        if spin4FadeOut {
            spin4K = max(0, spin4K - dt / Self.SPIN4_FADE)
            if spin4K <= 0 { spinX = false; spinY = false; spinZW = false; spin4FadeOut = false }
        } else if spin4K < 1 { spin4K = min(1, spin4K + dt / Self.SPIN4_FADE) }
        let k4 = k * Self.smoother(spin4K)
        if spinX { ax = Self.wrapPi(ax + 0.006 * k4); land(0, 0.006 * k4) }
        if spinY { ay = Self.wrapPi(ay + 0.0037 * k4); land(1, 0.0037 * k4) }
        if spinZW { zw = Self.wrapPi(zw + 0.007 * k4); land(2, 0.007 * k4) }
        if pp != nil {
            // 角度の往復の間：3D の回し続ける（X-Y・X-Z・Y-Z）は、往復の角度の上から見る向き（view3）を回す（往復は止めない）
            if spinXY { view3 = Self.R(0, 1, 0.0045 * k) * view3 }
            if spinXZ { view3 = Self.R(0, 2, 0.0053 * k) * view3 }
            if spinYZ { view3 = Self.R(1, 2, 0.0031 * k) * view3 }
            if spinXY || spinXZ || spinYZ { updateMats() }
        } else {
            if spinXY { xy = Self.wrapPi(xy + 0.0045 * k); land(3, 0.0045 * k) }
            if spinXZ { xz = Self.wrapPi(xz + 0.0053 * k); land(4, 0.0053 * k) }
            if spinYZ { yz = Self.wrapPi(yz + 0.0031 * k); land(5, 0.0031 * k) }
        }
    }

    // ---- 折りたたみ（nd-geom の foldAngles・foldPoint と同じ式）----
    static func smoother(_ t: Double) -> Double { let c = max(0, min(1, t)); return c * c * c * (c * (c * 6 - 15) + 10) }
    func foldAngles() -> (arm: Double, cap: Double) {
        if !foldStagger { let a = Self.smoother(progress) * .pi / 2; return (a, a) }   // 同時：腕もふたもいっしょに
        return (Self.smoother(min(1, progress / 0.60)) * .pi / 2, Self.smoother(max(0, (progress - 0.45) / 0.55)) * .pi / 2)
    }
    enum Cell: Equatable { case center, arm(Int, Double), cap }
    /// 胞の並び（ウェブ版の NET3_CELLS・NET4_CELLS）：真ん中・+y・−y・+x・−x・（+z・−z）・ふた
    static func cells(_ n: Int) -> [Cell] {
        var c: [Cell] = [.center, .arm(1, 1), .arm(1, -1), .arm(0, 1), .arm(0, -1)]
        if n >= 4 { c += [.arm(2, 1), .arm(2, -1)] }
        if n >= 5 { c += [.arm(3, 1), .arm(3, -1)] }                     // 5 次元：±w の胞（ウェブ版の P5_CELLS と同じ並び）
        return c + [.cap]
    }
    /// 組み上がりの位置 p（±1）の点を、今の折り具合の位置へ（×0.9）
    //   展開図のかたち（net：どの胞がどの胞にくっついているか）にしたがって、ちょうつがいごとに折る（OrigamiNets.swift）
    func fold(_ cell: Cell, _ p: [Double], _ n: Int) -> [Double] {
        let N = n - 1, idx = Self.cells(n).firstIndex(of: cell) ?? 0
        var o = netTransforms(n)[idx].apply(p)
        // 真ん中を原点へ（展開図では真ん中の胞が 0、組み上がりで中心が 0）。根に近いちょうつがいの折り具合で
        let parent = netParent(n), dep = Self.depths(parent)
        o[N] += 1 - (foldCourse ? Self.smoother(progress / Self.COURSE_ROLL) * .pi / 2 : foldTheta(1, dep.max() ?? 1)) / (.pi / 2)
        return o.map { $0 * Self.half }
    }
    /// 胞の決まった軸と値（真ん中は軸 N の −1、ふたは ＋1、腕は軸 a の s）
    static func fixed(_ cell: Cell, _ n: Int) -> (Int, Double) {
        switch cell { case .center: return (n - 1, -1); case .cap: return (n - 1, 1); case .arm(let a, let s): return (a, s) }
    }
    // ---- 回して写す ----
    static func rot(_ v: inout [Double], _ i: Int, _ j: Int, _ a: Double) {
        guard a != 0 else { return }
        let c = cos(a), s = sin(a), t = v[i] * c - v[j] * s; v[j] = v[i] * s + v[j] * c; v[i] = t
    }
    /// 3 次元（左の立方体）：X-Z → Y-Z →（Z-W の遠近）→ X-Y。返り値は見かけの縮み
    func place3(_ p: [Double]) -> (SIMD3<Double>, Double) {
        var v = l3 * SIMD4(p[0], p[1], p[2], 0)                              // X-Z → Y-Z
        var k = 1.0
        if zw != 0 {                                                     // Z-W：z の分が 4 次元へ逃げ、右と同じ遠近で縮む
            let w = v.z * sin(zw), D = camW, wc = max(-D + 0.5, min(D - 0.5, w)); k = 1 + (1 / (1 - wc / D) - 1) * (1 - projBlend)
            v.x *= k; v.y *= k; v.z = v.z * cos(zw) * k
        }
        v = rxy * v
        return (SIMD3(v.x, v.y, v.z), k)
    }
    /// 4 次元（右の超立方体）：X-W → Y-W → Z-W → X-Y → X-Z → Y-Z、w を遠近で
    func place4(_ p: [Double]) -> (SIMD3<Double>, Double) {
        let v = m4 * SIMD4(p[0], p[1], p[2], p[3])
        let D = camW, w = max(-D + 0.5, min(D - 0.5, v.w)), k = 1 + (1 / (1 - w / D) - 1) * (1 - projBlend)   // 平行投影の分だけ縮みを 1 へ
        return (SIMD3(v.x * k, v.y * k, v.z * k), k)
    }
    func place(_ p: [Double], _ n: Int) -> (SIMD3<Double>, Double) { n == 3 ? place3(p) : n == 4 ? place4(p) : place5(p) }

    static let axisCol: [SIMD3<Float>] = [[1.0, 0.365, 0.424], [0.239, 0.863, 0.518], [0.337, 0.659, 1.0], [0.690, 0.486, 1.0], [0.984, 0.749, 0.141]]   // 5 本目 v は琥珀   // 座標軸 x・y・z・w（Glass.axisCols と同じ）
    static let faceCol3: [UInt32] = [0x0284c7, 0x10b981, 0x10b981, 0xf43f5e, 0xf43f5e, 0x0284c7]
    static let cellCol4: [UInt32] = [0x9333ea, 0x10b981, 0x10b981, 0xf43f5e, 0xf43f5e, 0x38bdf8, 0x38bdf8, 0x9333ea]
    static func rgb(_ h: UInt32) -> SIMD3<Float> { SIMD3(Float((h >> 16) & 255) / 255, Float((h >> 8) & 255) / 255, Float(h & 255) / 255) }
}

/// 景色の座標（ウェブ版は y が上）を、描く側（z が上）へ
@inline(__always) private func gpu(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

final class OrigamiRenderer: NSObject, MTKViewDelegate {
    let n: Int, st: OrigamiState
    let device: MTLDevice, queue: MTLCommandQueue
    /// 排水口・通気口のふたを、底（0）・上（1）の胞と同じガラスで描くための、その胞の見た目（面ごとの色と濃さ・重ねる順の番号・包む強さ・4D の奥行き）
    struct HoleLook { var sh: [(SIMD3<Float>, Float)]; var tag, wrap, w, squash: Float }
    var holeLook: [Int: HoleLook] = [:]
    /// 底（0）・上（1）の胞の辺の線（色・明るさ・太さ・なじませる印）。排水口と通気口を同じワイヤーで描く
    var holeEdge: [Int: TLRod] = [:]
    private var holeCI: [Int: Int] = [:], holeRodIdx: [Int: Int] = [:]
    private var pipe: MTLRenderPipelineState!
    private var lastT = CACurrentMediaTime()
    let sky: OrigamiSky?                      // 宇宙（背景と星屑）
    let raster: OrigamiRaster?                // 三角形で描く道具
    var lastOff: [SIMD3<Double>] = []         // 胞を離した量（星屑も一緒に動かす）

    convenience init?(n: Int, state: OrigamiState, view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice() else { return nil }
        self.init(n: n, state: state, device: d)
        view.device = d; view.colorPixelFormat = .bgra8Unorm; view.preferredFramesPerSecond = 60
    }
    init?(n: Int, state: OrigamiState, device d: MTLDevice) {
        guard let q = d.makeCommandQueue() else { return nil }
        self.n = n; st = state; device = d; queue = q; sky = OrigamiSky(device: d, n: min(n, 4)); raster = OrigamiRaster(device: d)
        super.init()
        let lib = try! d.makeLibrary(source: tlShader, options: nil)
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = lib.makeFunction(name: "tlv"); p.fragmentFunction = lib.makeFunction(name: "tlf"); p.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipe = try! d.makeRenderPipelineState(descriptor: p)
    }
    /// 面（板）・辺（線）・目印の頂点を作る。eye：カメラの位置（景色の座標）。分解（バラす）もここで（ウェブ版の applyExplode）
    /// 画面の上でずらす量（図形の移動。三角形で描く時だけ。光の道の描き方では動かさない）
    var PS: SIMD2<Double> { st.raster ? st.pan[st.wix(n)] : .zero }
    var intSpheres: [IntSphere] = []                                        // 積分の玉（本物の球を画素ごとに）
    var intMarks: [TLBall] = []                                             // 積分の光る点（内接する超球が胞に接する所）
    var intBatches: [IntTriBatch] = []                                     // 積分の三角形（geometry で作り、描く時に渡す）
    var lastSecF = 0.0                                                       // 断面を出している度合い（描く時に、元の形の映り込みを弱める・立方体の面の奥行きを書かない）
    var axisTip = [SIMD3<Double>](repeating: SIMD3(0, 0, 0), count: 5)   // 軸の矢印の先（景色の座標。名前の位置に）
    var nAxRods = 0                                                         // 線の最後の何本が座標軸か（展開図でも軸をうっすら見せる）
    var axisT = [1.0, 1.0, 1.0, 1.0, 1.0], paneW = 0, paneH = 0          // 軸の長さの割合（見切れ防止）・窓の大きさ（画素）
    /// 軸（原点 o から先 b）の先と名前が窓に収まる割合（0.25〜1）。b は矢印の先まで。名前はその外に札の大きさぶん置くので、50 ポイント内側を枠に
    /// 原点から、窓のふち（名前の分のすき間を残す）までの、いちばん近い所のきょり（景色の長さ）。そこから先の矢印の分を引き、少し余裕をもたせる
    func axisRoom(_ o: SIMD3<Double>, _ eye: SIMD3<Double>) -> Double {
        guard paneW > 0, paneH > 0 else { return .infinity }
        let W = Double(paneW), H = Double(paneH), tanF = tan(22.5 * Double.pi / 180), asp = W / H, m = 50 * pxPerPt
        let z = eye.z - o.z; guard z > 0.1 else { return .infinity }
        let sx = ((o.x - eye.x) / (z * tanF * asp) * 0.5 + 0.5 + PS.x * 0.5) * W, sy = (0.5 - (o.y - eye.y) / (z * tanF) * 0.5 - PS.y * 0.5) * H
        let px = min(W - m - sx, sx - m, H - m - sy, sy - m)              // いちばん近いふちまでの画素
        guard px > 1 else { return 0.3 }
        let perPx = 2 * z * tanF / H                                       // 原点の深さでの、1 画素あたりの景色の長さ
        return max(0.3, 0.9 * px * perPx - 0.17)
    }
    func axisFit(_ o: SIMD3<Double>, _ b: SIMD3<Double>, _ eye: SIMD3<Double>) -> Double {
        guard paneW > 0, paneH > 0 else { return 1 }
        let W = Double(paneW), H = Double(paneH), tanF = tan(22.5 * Double.pi / 180), asp = W / H, m = 50 * pxPerPt
        func scr(_ p: SIMD3<Double>) -> SIMD2<Double>? {
            let z = eye.z - p.z; guard z > 0.1 else { return nil }
            return SIMD2(((p.x - eye.x) / (z * tanF * asp) * 0.5 + 0.5 + PS.x * 0.5) * W, (0.5 - (p.y - eye.y) / (z * tanF) * 0.5 - PS.y * 0.5) * H)
        }
        guard let os = scr(o), let bs = scr(b), os.x > m, os.x < W - m, os.y > m, os.y < H - m else { return 1 }
        var t = 1.0
        if bs.x > W - m { t = min(t, (W - m - os.x) / (bs.x - os.x)) }
        if bs.x < m { t = min(t, (m - os.x) / (bs.x - os.x)) }
        if bs.y > H - m { t = min(t, (H - m - os.y) / (bs.y - os.y)) }
        if bs.y < m { t = min(t, (m - os.y) / (bs.y - os.y)) }
        return max(0.25, t)
    }
    // 座標軸の先の矢印（geometry で作り、三角形で描く時に使う）
    var cones: [TLCone] = []
    // 手前と奥の頂点の目印（三角形で描く時。立体の上に描く）
    var marks: [TLBall] = []
    // 置いた点の名前の札（景色の座標・文字・色）
    var uptLabels: [(SIMD3<Double>, String, UInt32)] = []
    // 展開図をふつうの（すけない）立体に見せる度合い（geometry で決め、描く時に奥行きと線の隠れに使う）
    var solidK = 0.0
    func geometry(eye: SIMD3<Double>) -> ([TLQuad], [TLRod], [TLBall], Double, SIMD2<Double>) {
        let cells = OrigamiState.cells(n), di = st.wix(n)
        var quads: [TLQuad] = [], rods: [TLRod] = [], balls: [TLBall] = []
        // segK：辺の両はしの 4D の遠近の縮み（線の 4D の奥行きの濃さに使う）
        var segs: [(SIMD3<Double>, SIMD3<Double>, Int)] = [], segK: [(Double, Double)] = [], rMax = 0.0, lo = SIMD2<Double>(1e9, 1e9), hi = SIMD2<Double>(-1e9, -1e9)
        // 1. 胞ごとの頂点（折って・回して・写した 3D）
        var CV: [[SIMD3<Double>]] = [], FREE: [[Int]] = [], KV: [[Double]] = [], KW: [[Double]] = []
        for cell in cells {
            let (fa, fv) = OrigamiState.fixed(cell, n), free = (0..<n).filter { $0 != fa }
            let pk = (0..<(1 << free.count)).map { bits -> (SIMD3<Double>, Double, Double) in
                var p = [Double](repeating: 0, count: n); p[fa] = fv
                for (k, ax) in free.enumerated() { p[ax] = bits & (1 << k) != 0 ? 1 : -1 }
                if n == 5 { return st.place5KW(st.fold(cell, p, n)) }
                let r = st.place(st.fold(cell, p, n), n); return (r.0, r.1, r.1)
            }
            CV.append(pk.map(\.0)); KV.append(pk.map(\.1)); KW.append(pk.map(\.2)); FREE.append(free)
        }
        // 5 次元：見せる 4 次元の奥行き KD（頂点ごと、大きいほど手前）。展開図のあいだは、1 つ 1 つの超立方体の中での奥行き
        //   （w の遠近：外の立方体が手前・内の立方体が奥）＝どの胞も小さな超立方体に見える。組み上がるにつれて、5 次元超立方体全体の奥行きへ
        var KD = KV
        if n == 5 {
            let g = OrigamiState.smoother(st.progress), all = KV.flatMap { $0 }, gLo = all.min() ?? 0, gSp = max((all.max() ?? 1) - gLo, 1e-9)
            for ci in KD.indices {
                let lo = KW[ci].min() ?? 0, sp = max((KW[ci].max() ?? 1) - lo, 1e-9)
                for b in KD[ci].indices { KD[ci][b] = (KW[ci][b] - lo) / sp * (1 - g) + (KV[ci][b] - gLo) / gSp * g }
            }
        }
        // 2. 分解：胞を離す（中心の胞は動かない）
        let off = st.explodeOffsets(CV, n); lastOff = off
        for i in CV.indices { for k in CV[i].indices { CV[i][k] += off[i] } }
        st.labels[di] = CV.map { vs in vs.reduce(SIMD3<Double>(0, 0, 0), +) / Double(vs.count) }   // 番号の札の位置（離したあとの胞の中心）
        // 面の濃さ：展開図ほど濃く（ウェブ版の netOpacity：0.30 → 0.85）
        let pr = st.colorProg, mix = pow(1 - max(0, min(1, pr)), 1.5), base = 0.26, alpha0 = min(0.97, base + (max(base, 0.85) - base) * mix)
        // 奥・内側（visual-fx の cellDepth・innerAmount・shadeFace）：超立方体は 4D の遠近の縮み K（大きいほど手前）、立方体はカメラからの距離で。
        //   奥の胞ほど色を深く・濃く、手前の胞は薄く＝奥の濃い色が手前を透かして見える（組み上がった形の色が、重なり方から自然に決まる）
        var depthOf: [Double] = []
        for ci in CV.indices {
            if n >= 4 { let s: Double = KV[ci].reduce(0, +); depthOf.append(-s / Double(KV[ci].count)) }
            else { var s = 0.0; for p in CV[ci] { s += simd_distance(p, eye) }; depthOf.append(s / Double(CV[ci].count)) }
        }
        //   奥行きの幅は 0.15 より細くしない：展開図（みんな同じ奥行き）で、組み変わりの胞が少しだけ 4D へ浮いた時に、そのわずかな差が
        //   0〜1 いっぱいに引きのばされて色が一気に深くなり、降りた瞬間に 1 コマでもどっていた
        let dLo = depthOf.min() ?? 0, dSp = max((depthOf.max() ?? 1) - dLo, 0.15)
        let kD = 2 * st.deep, kI = 3.75 * st.inner
        let pcols = st.cellColors(n)                                     // 面・胞の色（パレット）
        // 展開図はふつうの立体（超立方体の展開図は 3 次元のふつうの物＝すけない十字架）。折りはじめると、組み上がるにつれてガラス（ファンタジー）へ
        //   組み立ての最初から最後まで全部をかけて、やわらかい曲線（5 次のなめらかな階段）で変える＝いつのまにかガラスになっている
        //   5 次元：展開図の 1 つ 1 つが超立方体（中に内側の立方体と、それをつなぐ線がある）なので、ふつうの立体にすると中が隠れる。
        //   すけない立体にはせず、面のうすさを「ふつうの立体」のつまみに合わせて変える（下の f5）。線はいつも見える
        solidK = n == 4 ? st.netSolid * (1 - OrigamiState.smoother(pr)) : 0
        let f5 = n == 5 ? 0.4 + 0.35 * st.netSolid + (1 - 0.4 - 0.35 * st.netSolid) * OrigamiState.smoother(pr) : 1
        // 断面：組み上がっている時だけ（分解したら消す）。出している間は、元の形をうすく（切り口が主役）
        let secF = st.secOn && n <= 4 ? OrigamiState.smoother((pr - 0.9) / 0.1) * (1 - min(1, st.explodeE * 3)) : 0
        lastSecF = secF
        let intV = st.intVis                                               // 積分が見えている度合い（積分中の超立方体の見え方に）
        // 4D の奥行き（頂点ごと）：手前は光る（足し合わせ）・奥は吸いこむ（乗算）。超立方体だけ。
        //   胞ごとに 1 色ではなく頂点ごとに決めて面の中をなめらかに変える＝色分けではなく、4 次元の奥行きのグラデーションに。
        //   展開図のあいだは効かせず、半分折れたあたりから組み上がりへなめらかに（ウェブ版の kF4 と同じ）
        let kAll = KD.flatMap { $0 }, kHi = kAll.max() ?? 1, kSp = max(kHi - (kAll.min() ?? 0), 1e-6)
        //   ここは奥行きと折り具合だけ（−1〜1）。光らせる・乗算の強さは、シェーダーでそれぞれのつまみの値を掛ける
        func sm4(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        //   5 次元は展開図のあいだも効かせる（1 つ 1 つの超立方体の、外の立方体が光って内の立方体が沈む）
        let kW4 = n >= 4 && (st.mul4 > 0 || st.glow4 > 0 || st.glass4 > 0) ? (n == 5 ? 1 : sm4((pr - 0.35) / 0.65)) : 0
        // 包む胞は胞ごと：胞の頂点の奥行きの平均が手前の半分にある胞ほど（ウェブ版の「包み込む胞」と同じく胞の真ん中で）。
        //   横の胞（手前と奥にまたがる）は平均が真ん中なので 0
        func wrap4(_ ci: Int) -> Float {
            guard kW4 > 0 else { return 0 }
            let tm = KV[ci].reduce(0.0) { $0 + (kHi - $1) / kSp } / Double(max(1, KV[ci].count))
            return Float(sm4((0.5 - tm) / 0.4) * kW4)
        }
        /// 4D の奥の乗算の強さ（胞ごとに 1 つ）：その胞の頂点の 4D の奥行きの平均（0 手前 〜 1 奥）。いちばん奥の胞 1・横の胞 0.5 くらい・手前 0。
        ///   胞の中は同じ濃さ（前は頂点ごとで、奥の半分だけ効いたので、横の胞の中に濃淡の帯＝むらが出た）
        func mulCell(_ ci: Int) -> Float {
            guard kW4 > 0 else { return 0 }
            let tm = n == 5 ? KD[ci].reduce(0.0) { $0 + (1 - $1) } / Double(max(1, KD[ci].count)) : KV[ci].reduce(0.0) { $0 + (kHi - $1) / kSp } / Double(max(1, KV[ci].count))
            return Float(pow(max(0, min(1, tm)), 0.7) * kW4)                       // 横の胞（平均 0.5）は 0.6 くらい
        }
        /// m.y に胞の番号と乗算の強さをいっしょに入れる（番号 ＋ 0.24 × 強さ。番号は Int にすれば元のまま）
        func cellTag(_ ci: Int) -> Float { Float(ci) + 0.24 * min(1, max(0, mulCell(ci))) }
        func w4(_ ci: Int, _ b: Int) -> Float {
            guard kW4 > 0 else { return 0 }
            let t = n == 5 ? (1 - KD[ci][b]) : (kHi - KV[ci][b]) / kSp       // 0 いちばん手前 〜 1 いちばん奥（4D の遠近の縮みで。5 次元は KD）
            return Float((2 * sm4(t) - 1) * kW4)
        }
        // 宇宙：板はうすいガラスに（球殻の宇宙モードと同じくらい）、辺は明るく光る線に。組み上がった瞬間の光で、辺がさらに光る
        let sk = st.spaceK, fl = st.spaceFlash, plateK = 1 - 0.72 * sk, edgeK = Float(1 + 0.7 * sk + 1.5 * fl)
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        // 見せる胞（表だけ・裏だけ）の濃さ：展開図は表も裏も見えるので全部見せ、組み上がるにつれて（0.45〜0.95）見せない胞をすーっと消す
        var shownCells = 0, sideVis = [Double](repeating: 1, count: CV.count)
        let lidsNow = n <= 4 ? st.lidOpens() : []                           // 積分のふた（OrigamiLid.swift）
        holeLook = [:]; holeEdge = [:]; holeCI = [:]; holeRodIdx = [:]
        for (ci, P) in CV.enumerated() {
            let col00 = OrigamiState.rgb(pcols[min(ci, pcols.count - 1)])
            //   5 次元：展開図のあいだは色を濃く・あざやかに（同じ色のセロハンが重なる感じ）
            let col0 = n == 5 ? col00 + (OrigamiRenderer.vivid(col00) * 0.95 - col00) * Float(1 - OrigamiState.smoother(pr)) : col00
            let deepC = (depthOf[ci] - dLo) / dSp
            let foc = st.cellFocus(ci, cells.count)
            // 胞の中の面の縮み（入れ子の内側ぐあい）
            var faceKs: [Double]? = nil
            if n == 4 {
                var ks: [Double] = []
                for fi in 0..<6 {
                    let f = fi / 2, sv = fi % 2; var s = 0.0
                    for b in 0..<8 where (b >> f) & 1 == sv { s += KV[ci][b] }
                    ks.append(s / 4)
                }
                faceKs = ks
            }
            let fkLo = faceKs?.min() ?? 0, fkHi = faceKs?.max() ?? 0
            func shade(_ fi: Int) -> (SIMD3<Float>, Float) {
                var inn = 0.0
                //   幅は 0.15 より細くしない：平らな展開図（胞の中の面がみな同じ奥行き）から 1% 折れただけで、わずかな差が 0〜1 に引きのばされて色が飛んでいた
                if let ks = faceKs { inn = (fkHi - ks[fi]) / max(fkHi - fkLo, 0.15) }
                let tIn: Double = kI * sm(inn)
                let c = OrigamiState.deepen(OrigamiState.deepen(col0, kD * sm(deepC) * 0.8), tIn)
                // 濃さ（visual-fx の shadeFace と同じ式）：手前の胞はうすく（0.55 倍）、奥の胞ほど濃く（1.6 倍まで）、入れ子の内側ほどさらに濃く。
                //   奥の濃い色が、手前のうすいガラスを透けて見える＝線の図ではなく、物があるように見える
                let dens: Double = max(0.12, 1 - 0.45 * kD + 1.05 * kD * deepC)
                let aGlass: Double = min(0.95, alpha0 * dens * (1 + 1.4 * tIn) * foc.face) * plateK
                let a: Double = (aGlass + (min(0.98, 0.98 * foc.face) - aGlass) * solidK) * f5
                return (c, Float(a * sideVis[ci] * (1 - 0.72 * secF) * (st.intLook >= 1 ? 1 - intV : 1) * (1 - 0.78 * st.diceDim)))
            }
            for p in P { lo = simd_min(lo, SIMD2(p.x, p.y)); hi = simd_max(hi, SIMD2(p.x, p.y)) }
            // 見せる胞（表だけ・裏だけ）：見せない胞は面も辺も作らない
            if st.faceSide != 0 && st.cellFront(cells[ci], n, eye: eye) != (st.faceSide == 1) {
                sideVis[ci] = 1 - OrigamiState.smoother((pr - 0.45) / 0.5)
                if sideVis[ci] < 0.01 { continue }
            }
            // 積分のふた：開いている間、直角に開く時は元の胞を消して（開いたふたは lidGeometry で別に描く）、消す時は薄く
            let lidO = lidAmount(lidsNow, cells[ci])
            if lidO > 0.001 {
                if st.intLidMode == 2 { sideVis[ci] *= 1 - 0.85 * lidO } else if lidO > 0.02 { sideVis[ci] = 0; continue }
            }
            if sideVis[ci] >= 0.5 { shownCells += 1 }
            let nb = FREE[ci].count
            // 胞のつぶれ具合（0 立方体のまま 〜 1 ぺちゃんこ）：4D で回すと、胞が w の方へ倒れて 3D では薄い板のように写る。
            //   写った胞の 3 本の辺の張る体積 ÷ 3 本の長さの積（向きだけを見る。遠近の大きさにはよらない）。つぶれているほど乗算を強く（つまみ squash4）
            var squash: Float = 0
            if n == 4 && nb == 3 && P.count >= 5 {
                let e1 = P[1] - P[0], e2 = P[2] - P[0], e3 = P[4] - P[0], l = simd_length(e1) * simd_length(e2) * simd_length(e3)
                if l > 1e-9 { squash = Float(max(0, min(1, 1 - abs(simd_dot(e1, simd_cross(e2, e3))) / l))) }
            }
            // 5 次元：胞は超立方体＝自由な軸 4 本から 2 本えらんで張る正方形（6 組 × 残り 2 本の ± の 4 か所 ＝ 24 枚）
            if nb == 4 && !st.wireOnly {
                let (col, alpha) = shade(0)
                if alpha >= 0.002 {
                    for i in 0..<4 { for j in (i + 1)..<4 {
                        let rest = (0..<4).filter { $0 != i && $0 != j }
                        for rb in 0..<4 {
                            let b0 = (rb & 1 != 0 ? 1 << rest[0] : 0) | (rb & 2 != 0 ? 1 << rest[1] : 0)
                            let idx = [b0, b0 | (1 << i), b0 | (1 << i) | (1 << j), b0 | (1 << j)]
                            let Q = idx.map { gpu(P[$0]) }, S = idx.map { w4(ci, $0) }
                            var nn = simd_cross(Q[1] - Q[0], Q[3] - Q[0]); let l = simd_length(nn); if l < 1e-7 { continue }; nn /= l
                            quads.append(TLQuad(a: SIMD4(Q[0], S[0]), b: SIMD4(Q[1], S[1]), c: SIMD4(Q[2], S[2]), d: SIMD4(Q[3], S[3]), n: SIMD4(nn, simd_dot(nn, Q[0])), col: SIMD4(col, 0), m: SIMD4(alpha, cellTag(ci), wrap4(ci), 0)))
                        }
                    } }
                }
            }
            // 排水口・通気口：底（−W、左の窓は −Z）と上の胞の見た目を覚えておく（ふたを同じガラスで描く）。左の窓で口が開いている面は、穴あきで描く（OrigamiDrain.swift）
            var cutFace = false
            if n <= 4 && !st.wireOnly {
                let (fa, fs) = OrigamiState.fixed(cells[ci], n)
                if fa == n - 1 {
                    let ws = (0..<(1 << nb)).map { w4(ci, $0) }
                    holeCI[ci] = fs < 0 ? 0 : 1
                    holeLook[fs < 0 ? 0 : 1] = HoleLook(sh: (0..<(nb == 3 ? 6 : 1)).map { shade($0) }, tag: cellTag(ci), wrap: wrap4(ci), w: ws.reduce(0, +) / Float(max(1, ws.count)), squash: squash)
                    cutFace = n == 3 && st.holeCut(top: fs > 0) != nil
                }
            }
            // 面：自由な軸のうち 2 本で張る正方形（立方体の胞は 6 枚、正方形の面は 1 枚）
            for f in (nb == 3 ? [0, 1, 2] : nb == 2 ? [-1] : []) where !st.wireOnly && !cutFace {
                for fsv in (f < 0 ? [0] : [0, 1]) {
                    let (col, alpha) = shade(f < 0 ? 0 : f * 2 + fsv)
                    // 消えている面（積分中の「線だけ」「消す」・見本の小窓）は作らない：濃さ 0 でも、つや・映り込みは足し合わせで残るので
                    if alpha < 0.002 { continue }
                    let span = (0..<nb).filter { $0 != f }
                    let b0 = f < 0 ? 0 : fsv << f
                    let idx = [b0, b0 | (1 << span[0]), b0 | (1 << span[0]) | (1 << span[1]), b0 | (1 << span[1])]
                    let Q = idx.map { gpu(P[$0]) }, S = idx.map { w4(ci, $0) }
                    var nn = simd_cross(Q[1] - Q[0], Q[3] - Q[0]); let l = simd_length(nn); if l < 1e-7 { continue }; nn /= l
                    // 角の w：4D の奥行き（−1 手前で光る 〜 ＋1 奥で乗算）・m.y：胞の番号（三角形で描く時の重ねる順に）
                    quads.append(TLQuad(a: SIMD4(Q[0], S[0]), b: SIMD4(Q[1], S[1]), c: SIMD4(Q[2], S[2]), d: SIMD4(Q[3], S[3]), n: SIMD4(nn, simd_dot(nn, Q[0])), col: SIMD4(col, 0), m: SIMD4(alpha, cellTag(ci), wrap4(ci), squash)))
                }
            }
            // 辺：1 本の軸だけ違う頂点の組
            for a in 0..<(1 << nb) { for k in 0..<nb where a & (1 << k) == 0 { segs.append((P[a], P[a | (1 << k)], ci)); segK.append((KD[ci][a], KD[ci][a | (1 << k)])) } }
        }
        // 見えている胞の数（変わった時だけ書く＝札の作り直しは回っている間も少しだけ）
        if st.faceSide != 0 && st.sideShown[di] != [shownCells, cells.count] { st.sideShown[di] = [shownCells, cells.count] }
        let c = (lo + hi) / 2
        for (a, b, _) in segs { for p in [a, b] { rMax = max(rMax, simd_length(SIMD2(p.x, p.y) - c) + abs(p.z) * 0.3) } }
        // 辺の色：手前は白く（0.80）、奥ほど暗く（0.17）。カメラからの距離で。数えている・くっついた瞬間は、その胞の辺を強く
        let ds = segs.flatMap { [simd_distance($0.0, eye), simd_distance($0.1, eye)] }
        let dmin = ds.min() ?? 0, dmax = ds.max() ?? 1, sp = max(dmax - dmin, 1e-3)
        //   5 次元：中のワイヤーが黒い筋にならないよう、奥でも 0.5 まで
        let brFar = n == 5 ? 0.5 : 0.17
        func br(_ p: SIMD3<Double>) -> Float { let t = max(0, min(1, (simd_distance(p, eye) - dmin) / sp)), s = t * t * (3 - 2 * t); return Float(0.80 + (brFar - 0.80) * s) }
        // 組み上がると、となりの胞の辺がぴったり重なる（超立方体は 96 本 → 32 本）。重なった辺は 1 本にまとめて、明るさは足す（見た目は同じで、調べる本数が減る）
        struct SegKey: Hashable { let a, b: SIMD3<Int> }
        func q(_ p: SIMD3<Double>) -> SIMD3<Int> { SIMD3(Int((p.x * 1e4).rounded()), Int((p.y * 1e4).rounded()), Int((p.z * 1e4).rounded())) }
        //   手前と奥の胞の辺を色で強調（ウェブ版の「手前と奥の辺を色で強調」：手前＝ふたの胞はマゼンタ、奥＝真ん中の胞は水色、どちらも 3 画素。
        //   奥の辺ほど少し暗く＝0.86〜1.14 倍）。重なった時は強調の色が勝つ。線は光らせない（にじみなし。ウェブ版の細い線）
        //   明るさは 1.4 で割る（シェーダーの線の芯は 1.4 倍で描くので、ウェブ版と同じ 0.80〜0.17 の濃さになるように）
        var seen: [SegKey: Int] = [:], hlRod = Set<Int>(), rodK: [(Double, Double)] = []
        let last = cells.count - 1
        let ehSlots = n == 3 ? OrigamiState.palSlots3 : n == 4 ? OrigamiState.palSlots4 : OrigamiState.palSlots5
        // 線を立体になじませる（賢く：smartLine）
        //   A：線の色を、その辺を持つ胞（2〜3 個）の色を混ぜた色に。光の来る側（左上の手前）を向いた辺は明るく、反対側は少し暗く＝ガラスの角がまわりの色を拾って光る
        //   B：形の外の輪郭（写した形のふち＝すべての頂点が線の片側にある辺）ははっきり、立体の中を通る線はうすく
        let smK = st.smartLine
        var edgeCells: [SegKey: [Int]] = [:]
        var scr2: [SIMD2<Double>] = [], ctr3 = SIMD3<Double>(0, 0, 0)
        /// 景色の点を、カメラから見た画面の向き（遠近つき）へ
        func proj2(_ p: SIMD3<Double>) -> SIMD2<Double> { let z = max(0.05, eye.z - p.z); return SIMD2((p.x - eye.x) / z, (p.y - eye.y) / z) }
        /// 形の外の輪郭か（写したすべての頂点が、この線の片側にある）
        func isOutline(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
            let pa = proj2(a), pb = proj2(b), d = pb - pa, L = simd_length(d)
            guard L > 1e-6 else { return false }
            var pos = false, neg = false
            for p in scr2 {
                let c = (d.x * (p.y - pa.y) - d.y * (p.x - pa.x)) / L
                if c > 1e-4 { pos = true } else if c < -1e-4 { neg = true }
                if pos && neg { return false }
            }
            return true
        }
        let ovl = st.lineTintMode == 1 && n != 5 && st.lineTint > 0.001            // 「線を胞の色でなじませる」を使っている時だけ
        if smK > 0.001 || ovl {
            for (a, b, ci) in segs {
                let qa = q(a), qb = q(b), key = (qa.x, qa.y, qa.z) < (qb.x, qb.y, qb.z) ? SegKey(a: qa, b: qb) : SegKey(a: qb, b: qa)
                if !(edgeCells[key]?.contains(ci) ?? false) { edgeCells[key, default: []].append(ci) }
            }
        }
        /// 重なりの色：その辺を持つ胞（2〜3 個）の色を掛け合わせた色（色つきセロハンを重ねた色）。掛けると暗くなるので、色合いはそのままで明るさをそろえる
        func overlapCol(_ cs: [Int], _ own: SIMD3<Float>) -> SIMD3<Float> {
            guard cs.count > 1 else { return own }
            var p = SIMD3<Float>(1, 1, 1)
            for c in cs { p *= simd_max(OrigamiState.rgb(pcols[min(c, pcols.count - 1)]), SIMD3(repeating: 0.04)) }
            let m = max(p.x, p.y, p.z)
            return m > 1e-5 ? p / m * 0.9 : own
        }
        if smK > 0.001 {
            var seenP = Set<SIMD3<Int>>()
            for (a, b, _) in segs { for p in [a, b] where seenP.insert(q(p)).inserted { scr2.append(proj2(p)); ctr3 += p } }
            ctr3 /= Double(max(1, seenP.count))
        }
        let lightDir = simd_normalize(SIMD3<Double>(-0.45, 0.6, 0.65))
        for (si, (a, b, ci)) in segs.enumerated() {
            let k = Float(st.cellFocus(ci, cells.count).edge * sideVis[ci] * (1 - 0.5 * secF) * (st.intLook == 2 ? 1 - intV : 1) * (1 - st.diceLineDim)) * edgeK, base = (br(a) + br(b)) / 2
            //   手前（ふた）・奥（真ん中）と、ほかに選んだ胞（ehCells：パレットと同じ ＋X〜−W の名前）
            let hl: SIMD3<Float>? = !st.ehOn ? nil : ci == last ? (st.ehNearOn ? st.ehNear : nil) : ci == 0 ? (st.ehFarOn ? st.ehFar : nil) : st.ehCells["\(n):\(ehSlots[min(ci, ehSlots.count - 1)])"]
            let hlW = Float((ci == last ? st.ehWidthNear : ci == 0 ? st.ehWidthFar : st.ehWidthOther) / 1.5)   // ふつうの線（1.5 画素）の何倍か
            var bright = (hl != nil ? 0.86 + 0.28 * min(1, base / 0.80) : base) * k / 1.4
            // 5 次元の展開図：1 つ 1 つの超立方体の外の立方体の辺（枠）はうすく細く、内側の立方体とつなぐ線（ワイヤー）ははっきり。組み上がると元へ
            var w5: Float = 1
            if n == 5 && hl == nil {
                let g5 = Float(1 - OrigamiState.smoother(pr)), o = Float(sm4(((segK[si].0 + segK[si].1) / 2 - 0.35) / 0.4))   // o：1 外の枠・0 内側
                bright *= 1 - 0.6 * o * g5
                w5 = 1 + ((0.4 + 0.3 * (1 - o)) - 1) * g5
            }
            // 消えている辺（積分中の「消す」など）は描かない：明るさ 0 の線は、黒い筋として上に塗られてしまう
            if bright < 1e-4 { continue }
            let qa = q(a), qb = q(b), key = (qa.x, qa.y, qa.z) < (qb.x, qb.y, qb.z) ? SegKey(a: qa, b: qb) : SegKey(a: qb, b: qa)
            if let j = seen[key] {
                if let sl = holeCI[ci], hl == nil, !hlRod.contains(j) { holeRodIdx[sl] = j }
                if let c = hl { rods[j].col = SIMD4(c, bright); rods[j].b.w = hlW; hlRod.insert(j) }
                else if !hlRod.contains(j) { rods[j].col.w += bright }
                continue
            }
            seen[key] = rods.count
            if hl != nil { hlRod.insert(rods.count) }
            // 線の色：強調の辺はその色。ほかは胞の色に寄せる（lineTint。白っぽい線から、少し明るい胞の色へ）。胞の色の線は a.w に −10 の印（乗算でなじませる）
            //   5 次元：線は胞と同じ色のワイヤーに（展開図の 1 つ 1 つの超立方体の、内側の立方体とつなぐ線が見えるように）
            let tintK = Float(n == 5 ? max(st.lineTint, 0.8) : st.lineTint), cellC = OrigamiState.rgb(pcols[min(ci, pcols.count - 1)])
            let baseC = SIMD3<Float>(0.92, 0.95, 1.0)
            //   重なりの乗算色（lineTintMode 1）：組み上がって重なった辺は、それを持つ胞の色を掛け合わせた色へ
            let tintC = ovl ? overlapCol(edgeCells[key] ?? [ci], cellC) : cellC
            var lc = baseC + ((tintC * 0.8 + 0.2) - baseC) * tintK, fb: Float = 1
            if n == 5 { lc = simd_min((cellC * 0.62 + 0.38) * 1.12, SIMD3<Float>(repeating: 1)) }   // 5 次元：胞と同じ色の明るいワイヤー（乗算にしない）
            if smK > 0.001 && hl == nil && n != 5 {
                // A：この辺を持つ胞の色を混ぜ、少し明るく（線が立体の色の「角」に見える）。光の来る側の辺ほど明るく
                let cs = edgeCells[key] ?? [ci]
                var avg = SIMD3<Float>(0, 0, 0)
                for c in cs { avg += OrigamiState.rgb(pcols[min(c, pcols.count - 1)]) }
                avg /= Float(cs.count)
                if ovl { avg = tintC }                                           // 重なりの乗算色の時は、混ぜた色ではなく掛け合わせた色
                let mid = (a + b) / 2, o = simd_length(mid - ctr3) > 1e-6 ? simd_normalize(mid - ctr3) : SIMD3<Double>(0, 0, 1)
                // 線はうしろのガラスに重ねて塗るので、ガラスより暗い色だと黒い線に見える。胞の色を白へ半分寄せた明るい色に（光の側ほど明るく）
                let lit = Float(0.82 + 0.3 * max(0, simd_dot(o, lightDir)))
                let smart = simd_min((avg * 0.45 + 0.55) * lit, SIMD3(repeating: 1))
                lc = lc + (smart - lc) * Float(smK)
                // B：形の外の輪郭ははっきり（少しだけ細く 85%）、立体の中を通る線は細く（50%）＝細くてもわかる。
                //   この線は明るさを下げると暗い筋に塗られるので、うすさは明るさではなく細さで（1 画素より細い線は自然にうすく見える）
                fb = 1 + ((isOutline(a, b) ? 0.85 : 0.5) - 1) * Float(smK)
            }
            let fbw = fb * w5
            rods.append(TLRod(a: SIMD4(gpu(a), hl == nil && tintK > 0 && n != 5 ? (st.lineTintMode == 2 ? -20 : -10) : 0), b: SIMD4(gpu(b), hl != nil ? hlW : (fbw < 0.999 ? fbw : 0)), col: SIMD4(hl ?? lc, bright)))
            if let sl = holeCI[ci], hl == nil { holeRodIdx[sl] = rods.count - 1 }
            rodK.append(segK[si])
        }
        for (sl, j) in holeRodIdx where j < rods.count { holeEdge[sl] = rods[j] }   // 4D の奥行きで分ける前の値（分ける時は真ん中の 1 本で上書き）
        // 線の 4D の奥行き（超立方体だけ）：辺を 4 つに分けて、それぞれの真ん中の 4D の奥行き（0 いちばん手前 〜 1 いちばん奥）で濃さと太さを変える。
        //   1 本の辺の中でもなめらかに変わる（手前から奥へのびる w の辺がグラデーションに）。展開図のあいだは効かず、折れるほど効く。
        //   line4：濃さ（1 奥ほどうすく・2 奥ほど濃く）。line4W：太さ（− 奥ほど細く＝手前が太い・＋ 奥ほど太く。いちばん太い所で 1 ＋ |line4W| 倍）
        let g4 = n == 5 ? 1 : sm4((pr - 0.2) / 0.6)                                                // 5 次元は展開図のあいだも
        let l4 = n >= 4 ? st.line4 : 0, l4k = st.line4K * g4, w4k = n >= 4 ? st.line4W * g4 : 0
        if ((l4 != 0 && l4k > 0) || abs(w4k) > 0.001) && kSp > 1e-4 {
            var out: [TLRod] = []; out.reserveCapacity(rods.count * 4)
            for (j, r) in rods.enumerated() {
                // 手前と奥の辺の強調（色で強調した辺）は、4D の奥行きでうすくしない（奥の水色が暗く沈んで乗算のように見えた）
                if hlRod.contains(j) { out.append(r); continue }
                let (ka, kb) = rodK[j], A = SIMD3(r.a.x, r.a.y, r.a.z), B = SIMD3(r.b.x, r.b.y, r.b.z)
                for s in 0..<4 {
                    let u0 = Float(s) / 4, u1 = Float(s + 1) / 4, um = Double(u0 + u1) / 2
                    let t = sm4((kHi - (ka + (kb - ka) * um)) / kSp)
                    let f: Double = l4 == 0 ? 1 : l4 == 1 ? 1 - (n == 5 ? 0.4 : 0.8) * t : 0.55 + 0.85 * t   // 5 次元は奥のワイヤーも色が見えるように
                    let br4 = Float(1 + (f - 1) * l4k), w4 = Float(1 + abs(w4k) * (w4k < 0 ? 1 - t : t))
                    // a.w：つなぎ目の印（−1 は A 側・−2 は B 側・−3 は両方。のばさない）
                    let joint: Float = (s == 0 ? -2 : s == 3 ? -1 : -3) + (r.a.w < -19.5 ? -20 : r.a.w < -9.5 ? -10 : 0)
                    out.append(TLRod(a: SIMD4(A + (B - A) * u0, joint), b: SIMD4(A + (B - A) * u1, (r.b.w > 0 ? r.b.w : 1) * w4), col: SIMD4(r.col.x, r.col.y, r.col.z, r.col.w * br4)))
                    if s == 1 { for (sl, jj) in holeRodIdx where jj == j { var e = out[out.count - 1]; e.a.w = r.a.w; holeEdge[sl] = e } }   // 排水口の線は分けないので、つなぎ目の印は元のまま
                }
            }
            rods = out
        }
        // 断面の切り口：面（多角形を扇に分けて 4 つ角の板に）と、ふちの線。面の色は、その面のもとの胞の色（立方体は金色）
        if secF > 0.001 {
            let sec = st.section(n)
            if st.secInfo[di] != sec.info { st.secInfo[di] = sec.info }
            var seenSE = Set<SegKey>()
            for poly in sec.polys {
                let G: [SIMD3<Float>] = poly.pts.map { p in
                    let arr: [Double] = (0..<n).map { k in p[k] }
                    return gpu(st.place(arr, n).0)
                }
                let col: SIMD3<Float> = poly.cell >= 0 ? OrigamiState.rgb(pcols[min(poly.cell, pcols.count - 1)]) : SIMD3(1.0, 0.82, 0.4)
                var i = 1
                while i + 1 < G.count {
                    let q0 = G[0], q1 = G[i], q2 = G[i + 1], q3 = i + 2 < G.count ? G[i + 2] : G[i + 1]
                    var nn = simd_cross(q1 - q0, q2 - q0); let l = simd_length(nn)
                    if l > 1e-9 {
                        nn /= l
                        // m.y＝99：切り口の板は、ひとまとまりで元の形のあとに重ねる
                        quads.append(TLQuad(a: SIMD4(q0, 0), b: SIMD4(q1, 0), c: SIMD4(q2, 0), d: SIMD4(q3, 0), n: SIMD4(nn, simd_dot(nn, q0)), col: SIMD4(col, 0), m: SIMD4(Float(0.78 * secF), 99, 0, 0)))
                    }
                    i += 2
                }
                for j in 0..<G.count {
                    let a = G[j], b = G[(j + 1) % G.count]
                    let qa = SIMD3(Int((a.x * 1e4).rounded()), Int((a.y * 1e4).rounded()), Int((a.z * 1e4).rounded())), qb = SIMD3(Int((b.x * 1e4).rounded()), Int((b.y * 1e4).rounded()), Int((b.z * 1e4).rounded()))
                    let key = (qa.x, qa.y, qa.z) < (qb.x, qb.y, qb.z) ? SegKey(a: qa, b: qb) : SegKey(a: qb, b: qa)
                    if seenSE.insert(key).inserted { rods.append(TLRod(a: SIMD4(a, 0), b: SIMD4(b, 0), col: SIMD4(0.97, 0.98, 1.0, Float(0.9 * secF / 1.4)))) }
                }
            }
        }
        // 積分の段（線は rods に足す・面と玉は三角形で）
        intMarks = []; intSpheres = []
        intBatches = []
        if n <= 4 {                                                        // 積分・内接球・サイコロは立方体と超立方体だけ（5 次元 β にはまだ無い）
            intBatches = st.intMethod == 1 ? waterGeometry(&rods, eye: eye) : st.intMethod == 2 ? ballsGeometry(&rods) : integralGeometry(&rods, eye: eye)
            intBatches += lidGeometry(&rods, st.lidOpens())                  // 直角に開くふた
            intBatches += holesGeometry(&rods, &quads)                      // 排水口と通気口（OrigamiDrain.swift）
            // 内接する超球面（回転バーの「内接球」。超球面アプリと同じ球殻の層）
            let r0s = rods.count, tsp0 = CACurrentMediaTime()
            let sgb = inSphereGeometry(&rods, eye: eye), tdf0 = CACurrentMediaTime()
            intBatches += inSphereDepthFx(&rods, from: r0s, sgb, eye: eye)
            if PerfTest.on && st.inSphere { PerfTest.add("　内接球・遠近", CACurrentMediaTime() - tdf0) }
            if PerfTest.on && st.inSphere { PerfTest.add("内接球を作る", CACurrentMediaTime() - tsp0) }
            // サイコロ（面の目と、②の立方体のサイコロ）
            intBatches += diceGeometry(eye: eye)
        } else {
            let r0s = rods.count
            intBatches += inSphereDepthFx(&rods, from: r0s, inSphere5Geometry(&rods, eye: eye), eye: eye)   // 5 次元 β の内接球（OrigamiInSphere5.swift）
        }
        // 座標軸（ウェブ版の X/Y/Z/W の軸：長さ 1.8 × 1.35、同じ回転と遠近）：形と同じコマで、光る線と先の矢印（名前は OrigamiAxes）
        //   長さ：前は 1.8 × 1.35 のままで、窓が細いと、どの向きでも窓のはしで切りそろえられて、回しても長さが変わらなかった。
        //   窓に収まる長さ（原点から窓のふちまで。先の矢印と名前の分を引く）より長くしない。そうすれば、回すと縮む・のびるが見える
        let o0 = st.place([Double](repeating: 0, count: n), n).0, AL = min(1.8 * 1.35, axisRoom(o0, eye))
        cones = []
        let rods0 = rods.count
        for ax in 0..<n where st.showAxes {
            var e = [Double](repeating: 0, count: n); e[ax] = AL
            let b0 = st.place(e, n).0, col = st.axisColor(ax, n)
            // 軸の見切れ防止（ウェブ版と同じ）：先の矢印（長さ 0.17）と、その外の名前が窓からはみ出しそうなら、その軸をその時だけ短く。
            //   矢印の先まで含めて調べ、矢印の分を引いた所を軸の先に（窓のはばを仕切りで変えた時も、毎コマ調べ直す）
            let d0 = simd_length(b0 - o0), dir0 = d0 > 1e-9 ? (b0 - o0) / d0 : SIMD3<Double>(0, 0, 0)
            let tA = axisFit(o0, b0 + dir0 * 0.17, eye)
            let lenB = max(0.05, min(d0, tA * (d0 + 0.17) - 0.17))
            axisT[ax] = d0 > 1e-9 ? lenB / d0 : 1; let b = o0 + dir0 * min(d0, lenB)
            if simd_distance(b, o0) > 1e-3 { rods.append(TLRod(a: SIMD4(gpu(o0), 0), b: SIMD4(gpu(b), 0), col: SIMD4(col, 0.8 / 1.4))) }
            // 先は CG ソフトのような円すいの矢印（三角形で描く時）。軸がこっちを向いて中心でつぶれている時は、矢印を低くして玉にもどす
            //   f：軸の向きと見る向きの間の sin（0＝まっすぐこっちを向いている）
            let dS = b - o0, dl = simd_length(dS)
            let f = dl > 1e-3 ? simd_length(simd_cross(dS / dl, simd_normalize(b - eye))) : 0
            let kc = st.raster ? sm4((f - 0.08) / 0.3) : 0
            // こっちを向いていくと、まず矢印の先が引っこんで平たい円盤に（kc 1 → 0.5）、それから円盤の中から玉がふくらむ（0.5 → 0）。
            //   こっちを向いた円盤は丸く見えるので、玉に入れかわっても目立たない。前は矢印が低くなるのと玉がふくらむのが同時で、
            //   途中で玉から矢印の先がちょこっと出ていた
            let kh = sm4((kc - 0.5) / 0.5), kb = 1 - sm4(kc / 0.5)
            axisTip[ax] = b + dS / max(dl, 1e-6) * (0.17 * kh)              // 名前は矢印の先の外に置く
            if kc > 0.01 {
                let apex = b + dS / max(dl, 1e-6) * max(0.004, 0.17 * kh)
                cones.append(TLCone(a: SIMD4(gpu(apex), 0), b: SIMD4(gpu(b), 0.045), col: SIMD4(col, 1)))
            }
            // 玉：円盤の中からふくらむ（いちばんつぶれた時に円盤と同じ 0.045）。光の道で描く時は今までの玉
            let ballR: Float = st.raster ? Float(0.045 * kb) : 0.035
            if ballR > 0.001 { balls.append(TLBall(p: SIMD4(gpu(b), ballR), col: SIMD4(col, 2))) }
        }
        nAxRods = rods.count - rods0
        // 目印：手前の頂点（ふたの胞の ＋…＋）はマゼンタ、奥の頂点（真ん中の胞の −…−）は水色。胞と一緒に離れる
        let near = st.place(st.fold(.cap, [Double](repeating: 1, count: n), n), n).0 + off[cells.count - 1]
        let far = st.place(st.fold(.center, [Double](repeating: -1, count: n), n), n).0 + off[0]
        //   三角形で描く時は、立体に隠れないよう最後に上から描く（marks：奥 → 手前の順。重なった所は乗算）。光の道で描く時は今まで通り玉
        //   隠した目印は半径 0（三角形で描く時は 0 番＝奥・1 番＝手前の並びを保つため、消さずに大きさ 0 で残す）
        let mR = Float(0.055 * st.markSize)
        // 同じ大きさ：遠近で小さく・大きく見えないよう、目からの距離に合わせて半径を変える（原点の深さで見た大きさにそろえる）
        let o0m = st.place([Double](repeating: 0, count: n), n).0, dO = max(1e-6, simd_distance(eye, o0m))
        func mRad(_ p: SIMD3<Double>) -> Float { st.markSame ? mR * Float(simd_distance(eye, p) / dO) : mR }
        let nearB = TLBall(p: SIMD4(gpu(near), st.markShowNear ? mRad(near) : 0), col: SIMD4(st.markNear, 2)), farB = TLBall(p: SIMD4(gpu(far), st.markShowFar ? mRad(far) : 0), col: SIMD4(st.markFar, 2))
        if st.raster { marks = st.isPreview ? [] : [farB, nearB] } else { marks = []; if st.markShowNear { balls.append(nearB) }; if st.markShowFar { balls.append(farB) } }
        gravHandleGeometry(&rods, &balls)                                   // 好きな向きの重力の矢印（OrigamiWater.swift）。玉は、ラスターの時は marks に
        if st.raster { marks += intMarks }                                // 積分：内接する超球が胞に接する点の光
        // 手前と奥の目印がぴったり重なった瞬間：光の輪が 2 重に広がって消える（0.8 秒）
        if st.raster && !st.isPreview && n == 4 && st.markFlash && st.markFlashT < 0.8 && st.markShowNear && st.markShowFar {
            let t = st.markFlashT / 0.8, fa = Float((1 - t) * (1 - t)), r0 = mRad(near)
            let fc = simd_clamp((st.markNear + st.markFar) * 0.5 * 1.3 + SIMD3<Float>(repeating: 0.25), .zero, SIMD3<Float>(repeating: 1))
            marks.append(TLBall(p: SIMD4(gpu(near), r0 * Float(1.6 + 6 * t)), col: SIMD4(fc * fa * 1.6, 3)))
            marks.append(TLBall(p: SIMD4(gpu(near), r0 * Float(1.3 + 3 * t)), col: SIMD4(SIMD3<Float>(repeating: 1) * fa, 3)))
        }
        // 内接球の接点：各胞（立方体の窓は各面）の真ん中に、光の輪（後光）。色は胞が垂直に立つ軸の色（点のタブの「胞の中心 8 個」と同じ約束：
        //   x 赤・y 緑・z 青・w 紫。立方体の窓の z の面は、超立方体の w にあたるので紫）。輪の真ん中はあけておき、置いた点が中におさまる。胞についていく
        //   輪の真ん中には、本当の接点（大きさゼロの 1 点）を小さな光の点で（col.w ＝ 3.5。輪と同じ色で、チカッと光る時もいっしょに光る）
        if st.raster && !st.isPreview && st.inSphere && st.inSphereTouch {
            let kA = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)    // 内接球が見えている時（組み上がり）
            let kT = kA, cellCols = st.inSphereTouchCol == 1 ? st.cellColors(n) : []
            if kT > 0.01 {
                for (ci, c) in OrigamiRenderer.cellNormals[n - 3].enumerated() where ci < cells.count {
                    var u = [Double](repeating: 0, count: n); u[c.0] = c.1
                    let pos = st.place(st.fold(cells[ci], u, n), n).0 + (ci < off.count ? off[ci] : SIMD3(0, 0, 0))
                    let ax = n == 3 && c.0 == 2 ? 3 : c.0
                    // 内接球を回している時：模様の経線がこの接点を通る瞬間に、チカッと明るく大きく
                    var c4 = SIMD4<Double>(0, 0, 0, 0); if c.0 < 4 { c4[c.0] = c.1 }
                    //   出現のはじめ（時計の 0〜35%）は、接点の輪がチカッと光ってから落ち着く（結晶はここから育つ）
                    let apx = st.inSphereAppear, apFl: Float = apx > 0 && apx < 0.35 ? Float(1 - apx / 0.35) : 0
                    let fl = max(n == 5 ? 0 : Float(st.sphereContactFlash(c4, n: n)), apFl)
                    marks.append(TLBall(p: SIMD4(gpu(pos), Float(0.11 * max(st.ptSize, 0.55)) * (1 + 0.35 * fl)), col: SIMD4((ci < cellCols.count ? OrigamiRenderer.vivid(OrigamiState.rgb(cellCols[ci])) : OrigamiState.rgb(ax < 4 ? OrigamiState.ptAxisCol[ax] : 0xf59e0b)) * Float(kT) * (1 + 2.2 * fl), 3.5)))
                }
            }
        }
        // 置いた点（点のタブ）：境界の点はその胞についていく（展開図でも・バラしても胞の同じ場所に）。目印のあとに上から描く
        //   大きさはウェブ版の比（目印 0.07 に対して 0.065 × 大きさ）
        uptLabels = []
        if (n == 4 || st.ptLeft) && n <= 4 {
            let r = Float(0.055 / 0.07 * 0.065 * st.ptSize)
            // 立方体では z だけちがう点が同じ場所 (x, y, w) に重なるので、同じ場所は 1 つだけ（名前のない点の札は立方体の座標で）
            var seen3 = Set<[Double]>()
            for var p in st.userPts {
                if n == 3 {
                    guard p.show, seen3.insert([p.x, p.y, p.w]).inserted else { continue }
                    if p.label.isEmpty { p.label = "(" + [p.x, p.y, p.w].map(OrigamiState.fmtPt).joined(separator: ", ") + ")" }
                }
                guard let (q, ci) = st.ptPosition(p, n) else { continue }
                let pos = st.place(q, n).0 + (ci >= 0 && ci < off.count ? off[ci] : SIMD3(0, 0, 0))
                let b = TLBall(p: SIMD4(gpu(pos), r), col: SIMD4(OrigamiState.rgb(p.color), 2))
                if st.raster { marks.append(b) } else { balls.append(b) }
                if st.ptLabels { uptLabels.append((pos, OrigamiState.ptLabelText(p), p.color)) }
            }
        }
        return (quads, rods, balls, rMax, c)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    // ---- 軽くする：止まっている時はゆっくり（1 秒に 10 回）。描く細かさはいつも同じ（切りかえるとちらつくので）----
    private var lastSig: [Double] = [], movedT = 0.0, drawnT = 0.0, drawnSize = CGSize.zero
    private var fitKey: [Double] = [], fitWant = 9.0, fitCtr = SIMD2<Double>(0, 0)   // 大きさと真ん中を決めた時の値
    static let stillAfter = 0.6, stillFPS = 10.0
    /// 見た目に関わる値の組（前のコマと同じなら止まっている）
    func drawSig() -> [Double] {
        let i = st.wix(n)
        return [st.progress, st.colorProg, st.ax, st.ay, st.zw, st.xy, st.xz, st.yz, st.xw5, st.yw5, st.zw5, st.wv5, st.dim5 ? 1 : 0, st.camW, Double(st.look), st.shine ? 1 : 0, st.shineK, st.shineSpread, st.shineAz, st.shineEl,
                st.glare, st.vivid, st.envK, st.deep, st.inner, st.explodeE, st.xpDistK, st.counting ? 1 : 0, Double(st.countIdx), Double(st.countPhase), st.spaceFlash,
                Double(st.spaceMode), st.bgSpace ? 1 : 0, st.starsPct, st.meshOn ? 1 : 0, st.gridN.rounded(), st.zoom[i], st.dist[i], st.center[i].x, st.center[i].y, st.pan[i].x, st.pan[i].y, st.rotRev, st.showAxes ? 1 : 0, st.foldStagger ? Double(st.foldMaxStages) : 0, st.foldCourse ? (st.courseFromB ? 2 : 1) : 0, st.projBlend, st.wireOnly ? 1 : 0, st.ehOn ? 1 : 0, st.ehWidthNear, st.ehWidthFar, st.ehWidthOther, (st.ehNearOn ? 1 : 0) + (st.ehFarOn ? 2 : 0), st.ehCells.reduce(0.0) { $0 + Double($1.key.hashValue % 9973) + Double($1.value.x + $1.value.y * 3 + $1.value.z * 7) }, st.markSize, Double(st.markNear.x + st.markNear.y * 2 + st.markNear.z * 4), Double(st.markFar.x + st.markFar.y * 2 + st.markFar.z * 4), (st.markShowNear ? 1 : 0) + (st.markShowFar ? 2 : 0) + (st.markGlue ? 4 : 0),
                Double(st.ehNear.x + st.ehNear.y * 2 + st.ehNear.z * 4), Double(st.ehFar.x + st.ehFar.y * 2 + st.ehFar.z * 4), st.left3DAll ? 1 : 0, st.raster ? 1 : 0,
                Double(st.ptRev), st.ptSize, st.ptLabels ? 1 : 0, st.ptLeft ? 1 : 0, st.secOn ? 1 : 0, st.secPos, st.intT, st.intOn ? 1 : 0, Double(st.intColor * 10 + st.intStars), Double(st.intLook), st.intN, st.intAmount, Double(st.intAxes), Double(st.intMethod), st.intMethod == 2 ? Double(st.ballsRev % 100000) + st.ballR : 0, st.waterTT, st.waterReal ? 1 : 0, st.waterNS ? 1 + st.waterSwirl : 0, Double(st.waterSlice) * 10 + st.waterSlicePos, st.waterFree ? 1 : 0, Double(st.waterNSRes), st.waterLidSet ? 1 : 0, st.waterBottomSet ? 1 : 0, Double(st.intLidMode), Double(st.drainMode) + (st.drainShown ? 10 : 0) + (st.holesOpenSet ? 100 : 0) + (st.waterVent ? 1000 : 0), st.holesAnimating ? CACurrentMediaTime().truncatingRemainder(dividingBy: 1000) : 0, Double(st.intShape), st.inSphere ? Double(1 + st.inSphereColor * 2 + st.inSphereLayers * 10) : 0, st.inSphereGlass ? 1 : 0, st.inSphereLon ? 1 : 0, st.inSphereCone ? 1 : 0, st.inSphereLat ? 1 : 0, st.inSphere120 ? 1 : 0, st.inSphereTouch ? 1 + Double(st.inSphereTouchCol) : 0, Double(st.lineTintMode), st.lineTint, st.depthDeep, st.slantSheen, st.line3W, st.line3K, st.lineWidthNet, st.lineWidthSolid, st.inSphereWireW, st.inSphereDepth, st.inSphereFilm ? 1 + st.inSphereTone : 0, st.inSphere ? st.inSphereAppear : 0, st.line4W, Double(st.line4), st.line4K, st.inSphereDent ? (st.inSphereDentSharp ? 2 : 1) : 0, st.inSphere && st.inSphereSpin != 0 ? st.inSphereT + Double(st.inSphereSpin * 100 + st.inSphereRatio * 10) + st.inSphereDiff * 1000 : 0, st.inSphereHopf ? 1 : 0, st.inSphereFlash ? 1 : 0, st.markSame ? 1 : 0, st.markFlashT < 0.8 ? st.markFlashT : 9, st.diceEyeK, st.diceDim, Double(st.diceMode), st.diceRoll.map { Double($0.phase) * 100 + $0.t } ?? -1, st.netMorph?.t ?? -1, st.intOn && st.intShape == 4 ? Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000) : 0, st.intOn && st.intBallSpin && (st.intColor == 5 || st.intColor == 7) ? Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000) : 0]
    }
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        defer { if PerfTest.on { PerfTest.add("1 つの窓の draw 全部", CACurrentMediaTime() - now) } }
        st.tickOnce(now)                                                  // 時間を進めるのは、先に描いた窓（片方だけ出している時も進む）
        let sig = drawSig()
        if sig.count != lastSig.count || zip(sig, lastSig).contains(where: { abs($0 - $1) > 1e-5 }) { lastSig = sig; movedT = now }
        let still = now - movedT > Self.stillAfter
        Self.fitDrawable(view, st.effScale)
        pxPerPt = Double(view.drawableSize.height / max(1, view.bounds.height))
        if !st.isPreview && st.paneSize[n] != view.bounds.size { st.paneSize[n] = view.bounds.size }
        if still && view.drawableSize == drawnSize && now - drawnT < 1 / Self.stillFPS { return }
        let td0 = CACurrentMediaTime()
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        if PerfTest.on { PerfTest.add("描く板を待つ", CACurrentMediaTime() - td0) }
        let sz = view.drawableSize
        encode(cb, rpd, Int(sz.width), Int(sz.height), now: now, dt: dt)
        let pi = st.wix(n)
        cb.addCompletedHandler { [weak self] c in
            let ms = (c.gpuEndTime - c.gpuStartTime) * 1000
            DispatchQueue.main.async { guard let self, ms > 0, ms < 500 else { return }; self.st.gpuMs[pi] = self.st.gpuMs[pi] * 0.9 + ms * 0.1 }
        }
        // iPad のシミュレーターには、出た時刻を知る仕組みと「間をあけて出す」仕組みがないので、ふつうに出す
        #if targetEnvironment(simulator)
        cb.present(dr)
        #else
        if PerfTest.on { dr.addPresentedHandler { d in let t = d.presentedTime; if t > 0 { DispatchQueue.main.async { PerfTest.note(pi, t) } } } }
        // 1 コマを画面に「ちょうど 1 拍（時計の回数の 1 回分）」出す：GPU が終わったらすぐ出すと、画面の書きかえに間に合うかが運しだいで、間隔がばらばらになる
        let r = st.driver.rate
        if r > 0 { cb.present(dr, afterMinimumDuration: 1.0 / Double(r)) } else { cb.present(dr) }
        #endif
        cb.commit()
        drawnT = now; drawnSize = sz
        frames += 1
        if now - fpsT >= 1 { st.fps[pi] = Int((Double(frames) / (now - fpsT)).rounded()); frames = 0; fpsT = now }
    }
    private var frames = 0, fpsT = CACurrentMediaTime()
    // ---- 座標軸の名前（x・y・z・w、数式の斜体）を Metal で：文字は一度だけ絵にして、毎コマは置くだけ ----
    private var labelTex: [MTLTexture?] = [], labelScale = 0.0
    private var labelCols: [SIMD3<Float>] = []
    private lazy var labelPipe: MTLRenderPipelineState? = {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct SO { float4 pos [[position]]; float2 uv; };
        vertex SO sprv(uint vid [[vertex_id]], constant float4& r [[buffer(0)]]) {
            float2 c = float2(vid & 1, vid >> 1); SO o; o.pos = float4(mix(r.x, r.z, c.x), mix(r.y, r.w, c.y), 0, 1); o.uv = float2(c.x, 1.0 - c.y); return o;
        }
        fragment float4 sprf(SO in [[stage_in]], texture2d<float> t [[texture(0)]], constant float& op [[buffer(0)]]) { constexpr sampler s(filter::linear, address::clamp_to_edge); return t.sample(s, in.uv) * op; }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
        let p = MTLRenderPipelineDescriptor(); p.vertexFunction = lib.makeFunction(name: "sprv"); p.fragmentFunction = lib.makeFunction(name: "sprf")
        let c = p.colorAttachments[0]!; c.pixelFormat = .bgra8Unorm; c.isBlendingEnabled = true
        c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: p)
    }()
    var pxPerPt = 2.0                         // 画面の 1 ポイントが、描く絵の何画素か
    /// 文字を絵（色つき・まわりは透明。色は濃さを掛けてある）に
    func textTexture(_ s: String, _ col: SIMD3<Float>, _ px: CGFloat) -> MTLTexture? {
        let font = CTFontCreateWithName("KaTeX_Math-Italic" as CFString, px, nil)
        let cg = CGColor(srgbRed: CGFloat(col.x), green: CGFloat(col.y), blue: CGFloat(col.z), alpha: 1)
        let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg])
        let line = CTLineCreateWithAttributedString(attr)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let wd = CTLineGetTypographicBounds(line, &asc, &desc, &lead), pad = 4
        let W = Int(ceil(wd)) + pad * 2, H = Int(ceil(asc + desc)) + pad * 2
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let data = ctx.data else { return nil }
        ctx.textPosition = CGPoint(x: CGFloat(pad), y: CGFloat(pad) + desc); CTLineDraw(line, ctx)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false); td.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: data, bytesPerRow: W * 4)
        return t
    }
    /// 軸の先のそばに名前を置く（軸の向きへ 24 ポイント外。w がこちらを向いている時は真ん中の少し上）
    func drawAxisLabels(_ e: MTLRenderCommandEncoder, w: Int, h: Int, eye: SIMD3<Double>) {
        guard st.showAxes, let pipe = labelPipe else { return }
        // 名前の絵は、大きさか色（軸の色を立体に合わせる）が変わった時だけ作り直す
        let lcols = (0..<n).map { st.axisColor($0, n) }
        if labelScale != pxPerPt || labelTex.count != n || lcols != labelCols {
            labelTex = (0..<n).map { textTexture(Glass.axisNames[$0], lcols[$0], CGFloat(26 * pxPerPt)) }; labelScale = pxPerPt; labelCols = lcols
        }
        let tanF = tan(22.5 * Double.pi / 180), W = Double(w), H = Double(h), asp = W / max(1, H)
        func scr(_ p: SIMD3<Double>) -> SIMD2<Double>? {
            let z = eye.z - p.z; guard z > 0.1 else { return nil }
            return SIMD2(((p.x - eye.x) / (z * tanF * asp) * 0.5 + 0.5 + PS.x * 0.5) * W, (0.5 - (p.y - eye.y) / (z * tanF) * 0.5 - PS.y * 0.5) * H)
        }
        guard let o = scr(st.place([Double](repeating: 0, count: n), n).0) else { return }
        e.setRenderPipelineState(pipe)
        var one: Float = 1; e.setFragmentBytes(&one, length: 4, index: 0)
        var faceOn = 0.0                          // こっちを向いてつぶれた軸の名前を、横に並べる時の次の位置（ポイント）
        for ax in 0..<n {
            // 名前は矢印の先（geometry で決めた axisTip）のさらに外へ：名前の札の半分の大きさ（軸の向きに測った分）＋すき間 5 ポイント。
            //   前は軸の先から 24 ポイントの所だったので、矢印が長く写る向きでは、文字が矢印にかぶった
            guard let b = scr(axisTip[ax]), let t = labelTex[ax] else { continue }
            let d = b - o, l = max(1, simd_length(d)), uvec = d / l, k = pxPerPt
            let hw = Double(t.width) / 2, hh = Double(t.height) / 2
            let ext = abs(uvec.x) * hw + abs(uvec.y) * hh
            // こっちを向いてつぶれた軸は、真ん中の少し上に。2 本以上ある時（胞から見た z と w など）は重ならないよう横に並べる
            var c = b + uvec * (5 * k + ext)
            if l < 6 * k { c = o + SIMD2(faceOn * k + hw, -(18 * k + hh)); faceOn += Double(t.width) / k + 4 }
            var r = SIMD4<Float>(Float((c.x - hw) / W * 2 - 1), Float(1 - (c.y + hh) / H * 2), Float((c.x + hw) / W * 2 - 1), Float(1 - (c.y - hh) / H * 2))
            e.setVertexBytes(&r, length: 16, index: 0); e.setFragmentTexture(t, index: 0)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    // ---- 分解の番号の札（胞の色の丸に番号、横に ±軸の名前）を Metal で：形と同じコマに描くので、回してもぴったりついてくる ----
    //   札の絵は、番号・色・大きさ（数えている今の札は 1.3 倍で金のふち）ごとに一度だけ作って、毎コマは置くだけ
    private var xpTex: [String: MTLTexture] = [:]
    func xpLabelTexture(_ k: Int, _ rgb: SIMD3<Float>, _ hi: Bool) -> MTLTexture? {
        let key = "\(k)-\(rgb)-\(hi)-\(pxPerPt)"
        if let t = xpTex[key] { return t }
        let sc = (hi ? 1.3 : 1.0) * pxPerPt, name = OrigamiState.shortNames[n - 3][k]
        let h = 22 * sc
        let nameFont = CTFontCreateWithName("HiraginoSans-W6" as CFString, 11 * sc, nil), numFont = CTFontCreateWithName("HiraginoSans-W7" as CFString, 10 * sc, nil)
        func line(_ s: String, _ f: CTFont) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]))
        }
        let nl = line(name, nameFont), num = line("\(k + 1)", numFont)
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        let nw = CTLineGetTypographicBounds(nl, &a, &d, &l)
        let W = Int(ceil(h + nw + 12 * sc)), H = Int(ceil(h)) + 2
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let data = ctx.data else { return nil }
        let box = CGRect(x: 1, y: 1, width: CGFloat(W) - 2, height: h)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.88)); ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setStrokeColor(hi ? CGColor(srgbRed: 0.98, green: 0.75, blue: 0.3, alpha: 1) : CGColor(srgbRed: 0.2, green: 0.25, blue: 0.33, alpha: 1)); ctx.setLineWidth(hi ? 2 * pxPerPt : pxPerPt); ctx.strokePath()
        let cr = CGRect(x: box.minX + 3 * sc, y: box.minY + 3 * sc, width: h - 6 * sc, height: h - 6 * sc)
        ctx.setFillColor(CGColor(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)); ctx.fillEllipse(in: cr)
        let numW = CTLineGetTypographicBounds(num, &a, &d, &l)
        ctx.textPosition = CGPoint(x: cr.midX - numW / 2, y: cr.midY - (a - d) / 2); CTLineDraw(num, ctx)
        CTLineGetTypographicBounds(nl, &a, &d, &l)
        ctx.textPosition = CGPoint(x: cr.maxX + 5 * sc, y: box.midY - (a - d) / 2); CTLineDraw(nl, ctx)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false); td.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: data, bytesPerRow: W * 4)
        if xpTex.count > 64 { xpTex.removeAll() }
        xpTex[key] = t
        return t
    }
    // ---- 置いた点の名前の札（ウェブ版の makePtSprite：等幅の太字、点の色、まわりに暗いふち）。文字・色・大きさごとに一度だけ絵に ----
    private var ptTex: [String: MTLTexture] = [:]
    func ptLabelTexture(_ s: String, _ col: UInt32, _ k: Double) -> MTLTexture? {
        let key = "\(s)|\(col)|\(k)|\(pxPerPt)"
        if let t = ptTex[key] { return t }
        let px = CGFloat(11 * k * pxPerPt), font = CTFontCreateWithName("Menlo-Bold" as CFString, px, nil)
        let c = OrigamiState.rgb(col)
        func line(_ cg: CGColor) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg]))
        }
        let fill = line(CGColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let wd = CTLineGetTypographicBounds(fill, &asc, &desc, &lead), pad = Int(ceil(3 * pxPerPt))
        let W = Int(ceil(wd)) + pad * 2, H = Int(ceil(asc + desc)) + pad * 2
        guard W > 0, H > 0, let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let data = ctx.data else { return nil }
        // 暗いふち（文字を太くなぞる）→ 上に点の色の文字
        ctx.setTextDrawingMode(.stroke); ctx.setLineWidth(CGFloat(2.4 * pxPerPt)); ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(srgbRed: 0.008, green: 0.024, blue: 0.07, alpha: 0.92))
        let edge = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]))
        ctx.textPosition = CGPoint(x: CGFloat(pad), y: CGFloat(pad) + desc); CTLineDraw(edge, ctx)
        ctx.setTextDrawingMode(.fill)
        ctx.textPosition = CGPoint(x: CGFloat(pad), y: CGFloat(pad) + desc); CTLineDraw(fill, ctx)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false); td.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: data, bytesPerRow: W * 4)
        if ptTex.count > 400 { ptTex.removeAll() }
        ptTex[key] = t
        return t
    }
    /// 置いた点の名前：点のすぐ右上に
    func drawPtLabels(_ e: MTLRenderCommandEncoder, w: Int, h: Int, eye: SIMD3<Double>) {
        guard !uptLabels.isEmpty, let pipe = labelPipe else { return }
        let tanF = tan(22.5 * Double.pi / 180), W = Double(w), H = Double(h), asp = W / max(1, H), k = max(0.6, st.ptSize) / 0.55
        e.setRenderPipelineState(pipe)
        var one: Float = 1; e.setFragmentBytes(&one, length: 4, index: 0)
        for (p, s, col) in uptLabels {
            let z = eye.z - p.z
            guard z > 0.1, let t = ptLabelTexture(s, col, k) else { continue }
            let c = SIMD2(((p.x - eye.x) / (z * tanF * asp) * 0.5 + 0.5 + PS.x * 0.5) * W, (0.5 - (p.y - eye.y) / (z * tanF) * 0.5 - PS.y * 0.5) * H)
            let x0 = c.x + 7 * pxPerPt * k, y1 = c.y - 4 * pxPerPt * k, y0 = y1 - Double(t.height), x1 = x0 + Double(t.width)
            var r = SIMD4<Float>(Float(x0 / W * 2 - 1), Float(1 - y1 / H * 2), Float(x1 / W * 2 - 1), Float(1 - y0 / H * 2))
            e.setVertexBytes(&r, length: 16, index: 0); e.setFragmentTexture(t, index: 0)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    func drawXpLabels(_ e: MTLRenderCommandEncoder, w: Int, h: Int, eye: SIMD3<Double>) {
        let ex = st.explodeE
        guard ex > 0.01 || st.counting, let pipe = labelPipe else { return }
        let i = st.wix(n), tanF = tan(22.5 * Double.pi / 180), W = Double(w), H = Double(h), asp = W / max(1, H), cols = st.cellColors(n)
        e.setRenderPipelineState(pipe)
        for (k, p) in st.labels[i].enumerated() where k < cols.count {
            var op = min(1, ex * 1.6), hi = false
            if st.counting && st.countPhase != 0 {
                if st.countPhase == 1 && k > st.countIdx { op = 0 } else { op = 1; hi = st.countPhase == 1 && k == st.countIdx }
            }
            let z = eye.z - p.z
            guard z > 0.1, op > 0.01, let t = xpLabelTexture(k, OrigamiState.rgb(cols[k]), hi) else { continue }
            let c = SIMD2(((p.x - eye.x) / (z * tanF * asp) * 0.5 + 0.5 + PS.x * 0.5) * W, (0.5 - (p.y - eye.y) / (z * tanF) * 0.5 - PS.y * 0.5) * H)
            let hw = Double(t.width) / 2, hh = Double(t.height) / 2
            var r = SIMD4<Float>(Float((c.x - hw) / W * 2 - 1), Float(1 - (c.y + hh) / H * 2), Float((c.x + hw) / W * 2 - 1), Float(1 - (c.y - hh) / H * 2))
            var o = Float(op)
            e.setVertexBytes(&r, length: 16, index: 0); e.setFragmentBytes(&o, length: 4, index: 0); e.setFragmentTexture(t, index: 0)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    /// 描く画素の数＝画面の細かさ × k（いつも同じ k。動く時だけ変えるとちらつくので）。画面には拡大して出す
    static func fitDrawable(_ view: MTKView, _ k: Double) {
        #if os(macOS)
        let bs = view.window?.backingScaleFactor ?? 2
        #else
        let bs = view.window?.screen.scale ?? UIScreen.main.scale
        #endif
        let want = CGSize(width: max(8, (view.bounds.width * bs * k).rounded()), height: max(8, (view.bounds.height * bs * k).rounded()))
        if view.autoResizeDrawable { view.autoResizeDrawable = false }
        if view.drawableSize != want { view.drawableSize = want }
    }
    // ---- 升の一覧：画面を 32 画素の升に分け、その升にかかる面・辺の番号を並べる（シェーダーはその升の分だけ調べる）----
    private var tileBufs: [MTLBuffer] = [], tileRing = 0
    static let tileSize = 32
    func buildTiles(_ quads: [TLQuad], _ rods: [TLRod], eye: SIMD3<Float>, w: Int, h: Int, glowPad: Float) -> (MTLBuffer, MTLBuffer, SIMD4<Float>)? {
        let TS = Self.tileSize, tx = (w + TS - 1) / TS, ty = (h + TS - 1) / TS
        let cap = max(1, min(1023, max(quads.count, rods.count))), stride = cap + 1, count = tx * ty * stride
        if tileBufs.count < 6 || tileBufs[0].length < count * 2 {           // 3 組を順に使う（GPU がまだ前のコマを読んでいる間に書きかえない）
            tileBufs = (0..<6).compactMap { _ in device.makeBuffer(length: count * 2, options: .storageModeShared) }
            if tileBufs.count < 6 { tileBufs = []; return nil }
        }
        let qb = tileBufs[tileRing * 2], rb = tileBufs[tileRing * 2 + 1]; tileRing = (tileRing + 1) % 3
        let QL = qb.contents().bindMemory(to: UInt16.self, capacity: count), RL = rb.contents().bindMemory(to: UInt16.self, capacity: count)
        for t in 0..<(tx * ty) { QL[t * stride] = 0; RL[t * stride] = 0 }
        let tanF = Float(tan(22.5 * Double.pi / 180)), asp = Float(w) / Float(max(1, h)), W = Float(w), H = Float(h), fT = Float(TS)
        let ps = SIMD2<Float>(0, 0)   // 光の道の描き方では図形の移動はしない
        func add(_ pts: [SIMD3<Float>], _ pad: Float, _ L: UnsafeMutablePointer<UInt16>, _ idx: Int) {
            var lo = SIMD2<Float>(.infinity, .infinity), hi = -lo, full = false
            for p in pts {
                let v = p - eye, z = v.y                                    // カメラは +y を見る（右 x・上 z）
                if z < 0.05 { full = true; break }
                let sx: Float = (v.x / (z * tanF * asp) * 0.5 + 0.5 + ps.x * 0.5) * W
                let sy: Float = (0.5 - v.z / (z * tanF) * 0.5 - ps.y * 0.5) * H
                let sp = SIMD2(sx, sy)
                lo = simd_min(lo, sp); hi = simd_max(hi, sp)
            }
            let x0 = full ? 0 : max(0, Int(floor((lo.x - pad) / fT))), x1 = full ? tx - 1 : min(tx - 1, Int(floor((hi.x + pad) / fT)))
            let y0 = full ? 0 : max(0, Int(floor((lo.y - pad) / fT))), y1 = full ? ty - 1 : min(ty - 1, Int(floor((hi.y + pad) / fT)))
            if x0 > x1 || y0 > y1 { return }
            for y in y0...y1 { for x in x0...x1 {
                let b = (y * tx + x) * stride, c = Int(L[b])
                if c < cap { L[b + 1 + c] = UInt16(idx); L[b] = UInt16(c + 1) }
            } }
        }
        func xyz(_ v: SIMD4<Float>) -> SIMD3<Float> { SIMD3(v.x, v.y, v.z) }
        for (i, q) in quads.enumerated() { add([xyz(q.a), xyz(q.b), xyz(q.c), xyz(q.d)], 2, QL, i) }
        for (i, r) in rods.enumerated() { add([xyz(r.a), xyz(r.b)], glowPad + 3 * max(1, r.b.w), RL, i) }
        return (qb, rb, SIMD4(fT, Float(tx), Float(cap), 1))
    }
    /// 1 コマを積む（画面へも、確かめの絵へも）
    func encode(_ cb: MTLCommandBuffer, _ rpd: MTLRenderPassDescriptor, _ w: Int, _ h: Int, now: Double, dt: Double) {
        st.updateMats()
        let spaceK = st.spaceK
        let spTex = spaceK > 0.001 && st.bgSpace && !st.raster ? sky?.render(cb, w, h, st, now) : nil
        let i = st.wix(n)
        // カメラ：正面（ウェブ版と同じく、物を回してカメラは回さない）。全体が収まる距離へなめらかに寄る
        let eyeW = SIMD3<Double>(st.center[i].x, st.center[i].y, st.dist[i])
        st.paneWpt[i] = Double(w) / max(0.5, pxPerPt); st.paneHpt[i] = Double(h) / max(0.5, pxPerPt)
        let tg0 = CACurrentMediaTime()
        paneW = w; paneH = h
        let (quads, rods, balls, rMax, ctr) = geometry(eye: eyeW)
        if PerfTest.on { PerfTest.add("形を作る", CACurrentMediaTime() - tg0) }
        // 大きさと真ん中は、折りたたみ・バラす量・離す距離・ズームが変わった時だけ決め直す。回しているだけの時は据え置き
        //   （ウェブ版と同じ。毎コマ形に合わせると、回すたびに大きさと位置が息をするように揺れる）
        // 窓の縦横の比（境目を動かすと変わる）も決め直しの合図に。横が狭い窓では、横がはみ出さないように引く（ウェブ版：縦横の短いほうに合わせる）
        let asp = Double(w) / Double(max(1, h))
        // 展開図のかたちが変わった時も決め直す（かたちの番号の並びを 1 つの数に）
        let netKey = Double(st.netParent(n).reduce(0) { $0 * 11 + ($1 + 1) })
        let key = st.autoZoom ? [st.progress, st.explodeE, st.xpDistK, st.zoom[i], st.projBlend, (asp * 50).rounded() / 50, st.zfNet, st.zfAsm, st.zfXp, netKey]
                              : [st.zoom[i], (asp * 50).rounded() / 50, netKey]   // 自動ズームを切ると、折りたたみ・分解では決め直さない
        if fitKey.count != key.count || zip(key, fitKey).contains(where: { abs($0 - $1) > 1e-4 }) {
            // ウェブ版の自動ズーム（zoomFit）：組み上がりは画面の半分（0.5）、展開図は 85%（0.85）を形が占めるように。間は折り具合で混ぜる
            let fFold = st.zfAsm + (st.zfNet - st.zfAsm) * pow(1 - max(0, min(1, st.progress)), 1.5)
            let f = fFold + (st.zfXp - fFold) * max(0, min(1, st.explodeE))      // 分解：バラすほど「分解」の大きさへ
            fitKey = key; fitWant = max(3.0, rMax / (tan(22.5 * .pi / 180) * min(1, asp) * f)) / st.zoom[i]; fitCtr = ctr
        }
        let k = min(1, dt * 6)
        st.dist[i] += (fitWant - st.dist[i]) * k; st.center[i] += (fitCtr - st.center[i]) * k
        if abs(fitWant - st.dist[i]) < 1e-4 { st.dist[i] = fitWant }
        if simd_length(fitCtr - st.center[i]) < 1e-4 { st.center[i] = fitCtr }
        var u = TLUni()
        u.eye = SIMD4(gpu(eyeW), 0); u.R = SIMD4(1, 0, 0, 0); u.U = SIMD4(0, 0, 1, 0); u.F = SIMD4(0, 1, 0, 0)
        let sz = CGSize(width: w, height: h)
        u.p = SIMD4(Float(tan(22.5 * Double.pi / 180)), Float(sz.width / max(1, sz.height)), 0, 1)
        let L = Glass.looks[st.look]
        u.q = SIMD4(Float(quads.count), 0, Float(now.truncatingRemainder(dividingBy: 1000)), 0)
        u.cnt = SIMD4(Float(rods.count), Float(balls.count), Float(2 * tan(22.5 * Double.pi / 180) / max(1, sz.height)), Float(0.30 * spaceK))   // 細い線（ふだんはにじみなし＝ウェブ版。宇宙ではネオンのように）
        u.L0 = SIMD4(L.base, L.fresA, L.fresP, L.rimK); u.L1 = SIMD4(L.lumT, L.lumK, L.env, L.sat)
        u.L2 = SIMD4(L.lift, L.add ? 1 : 0, 0, 1)                         // 辺は細い線（ウェブ版の 1 画素の線）
        u.rim = SIMD4(L.rim, L.rodEnv); u.L3 = SIMD4(L.soft ? 1 : 0, 1, 0, st.look == 0 ? 1 : 0)   // 質感「次元おりがみ」は three.js と同じ光で
        // 照り返しライト：主光はカメラから見て左右 az・上下 el、見ている点からの距離 D × 0.762。逆光は左右 +168°・上下 ×0.7、D × 0.886（visual-fx の shinePlace）
        let r0 = n == 3 ? 0.2 : 0.15, m0 = n == 3 ? 0.4 : 0.5
        u.S0 = SIMD4(st.shine ? 1 : 0, Float(st.shineK), Float(st.roughMul(r0)), Float(st.glare))
        u.S1 = SIMD4(Float(st.vivid), Float(st.envK), Float(m0), Float(r0))
        func lightAt(_ az: Double, _ el: Double, _ k: Double) -> SIMD4<Float> {
            let a = az * .pi / 180, e = el * .pi / 180, D = st.dist[i] * k
            let T = SIMD3<Double>(st.center[i].x, st.center[i].y, 0)
            return SIMD4(gpu(T + SIMD3(D * cos(e) * sin(a), D * sin(e), D * cos(e) * cos(a))), 0)
        }
        u.S2 = lightAt(st.shineAz, st.shineEl, 0.762); u.S3 = lightAt(st.shineAz + 168, max(-85, min(85, st.shineEl * 0.7)), 0.886)
        // 背景の混ぜ方は早めに（星がぽつぽつ灯る具合は、星ごとのしきい値で）
        u.X = SIMD4(spTex != nil ? Float(min(1, 3 * spaceK)) : 0, Float(st.spaceFlash), st.meshOn ? Float(spaceK) : 0, Float(st.gridN.rounded()))
        // 形ぜんぶを囲む箱（面・辺・玉。光る線のにじみの分だけ少し大きく）
        var bLo = SIMD3<Float>(repeating: 1e9), bHi = SIMD3<Float>(repeating: -1e9)
        for q in quads { for c in [q.a, q.b, q.c, q.d] { bLo = simd_min(bLo, SIMD3(c.x, c.y, c.z)); bHi = simd_max(bHi, SIMD3(c.x, c.y, c.z)) } }
        for r in rods { for c in [r.a, r.b] { bLo = simd_min(bLo, SIMD3(c.x, c.y, c.z)); bHi = simd_max(bHi, SIMD3(c.x, c.y, c.z)) } }
        for b in balls { let p = SIMD3(b.p.x, b.p.y, b.p.z); bLo = simd_min(bLo, p - b.p.w); bHi = simd_max(bHi, p + b.p.w) }
        if bLo.x <= bHi.x { u.B0 = SIMD4(bLo - 0.08, 0); u.B1 = SIMD4(bHi + 0.08, 1) }
        var qd = quads.isEmpty ? [TLQuad(a: .zero, b: .zero, c: .zero, d: .zero, n: .zero, col: .zero)] : quads, rd = rods, bl = balls
        guard let qb = device.makeBuffer(bytes: &qd, length: MemoryLayout<TLQuad>.stride * qd.count, options: .storageModeShared),
              let rb = device.makeBuffer(bytes: &rd, length: MemoryLayout<TLRod>.stride * max(1, rd.count), options: .storageModeShared),
              let bb = device.makeBuffer(bytes: &bl, length: MemoryLayout<TLBall>.stride * max(1, bl.count), options: .storageModeShared) else { return }
        // 三角形で描く：重ねる順はウェブ版（three.js）と同じ＝胞の順番（真ん中 → ±y → ±x → ±z → ふた）のまま、
        //   どの胞も裏向きの面を先・表向きの面をあとに（両面の透明な物の描き方）。超立方体は奥行きを書かない、立方体の面は書く（ウェブ版の「立体感」）
        if st.raster, let rr = raster {
            let eg = gpu(eyeW)
            func ctr(_ q: TLQuad) -> SIMD3<Float> { let c = (q.a + q.b + q.c + q.d) * 0.25; return SIMD3(c.x, c.y, c.z) }
            var byCell: [Int: [Int]] = [:]
            for (k, q) in quads.enumerated() { byCell[Int(q.m.y), default: []].append(k) }
            var ord: [UInt32] = []
            for c in byCell.keys.sorted() {
                let ks = byCell[c]!, cc = ks.reduce(SIMD3<Float>(0, 0, 0)) { $0 + ctr(quads[$1]) } / Float(ks.count)
                var back: [UInt32] = [], front: [UInt32] = []
                for k in ks {
                    let q = quads[k], fc = ctr(q); var nv = SIMD3(q.n.x, q.n.y, q.n.z)
                    if simd_dot(nv, fc - cc) < 0 { nv = -nv }                   // 胞の外向きに
                    if simd_dot(nv, fc - eg) > 0 { back.append(UInt32(k)) } else { front.append(UInt32(k)) }
                }
                ord += back + front
            }
            // 4D の奥（乗算）の面は最後に：ふつうに重ねた手前のガラスの上からも色を掛けて、セロハンを重ねたように色が混ざる
            //   （先に描くと、あとから手前の面がふつうに上に乗って、乗算の色が届かない）。並びはそのまま後ろへ移す
            //   包む胞の色ガラスも最後に：先に描いた中の胞の色の上から、ガラスの色を掛ける
            //   前は乗算の強い面（0.15 をこえた面）を面ごと最後へ移していたので、またぐたびにポンと切りかわった。
            //   今は、どの面もふつうの順番で描き、乗算のある面はもう一度最後に（ord2）。どれだけ最後に回すかはシェーダーがなめらかに決める
            //   （ここは「もしかすると乗算がある面」を多めに選ぶだけ。シェーダーの強さの上限：4D の奥・包む胞・つぶれ）
            var ord2: [UInt32] = []
            if n >= 4 && (st.mul4 > 0 || st.glass4 > 0 || st.squash4 > 0) {
                func sMax(_ k: UInt32) -> Float {
                    let q = quads[Int(k)], sv = (q.m.y - q.m.y.rounded(.down)) / 0.24        // 胞ごとの乗算の強さ
                    return max(sv * Float(st.mul4), q.m.z * Float(st.glass4), 3 * q.m.w * q.m.w * Float(st.squash4))
                }
                ord2 = ord.filter { sMax($0) > 0.02 }
            }
            // 表だけ・裏だけで面の数が減った時も、描く数は順番の表の長さ（前は面の数だけ描いて、表の外を読んでいた）
            let nq1 = quads.isEmpty ? 0 : ord.count
            var ordAll = ord + ord2
            if ordAll.isEmpty { ordAll = [0] }
            guard let ob = device.makeBuffer(bytes: &ordAll, length: 4 * ordAll.count, options: .storageModeShared) else { return }
            // 線：ウェブ版と同じ 1 画素・濃さ 0.9。組み上がるほどうすく（組み上がりで 0.65 倍）＝展開図はくっきりした紙、組み上がると線が引いて「物」に見える
            let sm = { (x: Double) -> Double in let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
            let lineA = st.wireOnly ? Float(1.0) : Float(0.9 * (1 - 0.35 * sm((st.colorProg - 0.4) / 0.6)))   // ワイヤーの時は面がないので、組み上がっても線をうすくしない
            // 3D の奥を暗く（ウェブ版の brightOf）：形の頂点のカメラからの距離の幅で、手前 1.25 倍 → 奥 0.6 倍。展開図は奥をさらに暗く（コントラスト 1.4）
            let ey = SIMD3(u.eye.x, u.eye.y, u.eye.z)
            var zLo: Float = .greatestFiniteMagnitude, zHi: Float = 0
            for q in quads { for v in [q.a, q.b, q.c, q.d] { let dd = simd_distance(SIMD3(v.x, v.y, v.z), ey); zLo = min(zLo, dd); zHi = max(zHi, dd) } }
            let s3 = Float(st.depth3), prC: Double = max(0, min(1, st.colorProg))
            let farDim = Float(0.6 / (1 + 0.4 * (1 - prC)))
            let nearB: Float = 1 + 0.25 * s3, farB: Float = 1 - (1 - farDim) * s3
            let depth = SIMD4<Float>(quads.isEmpty ? 0 : zLo, quads.isEmpty ? 1 : zHi, nearB, farB)
            // 形どうしの映り込み：形を包む箱（角の最小・最大）の真ん中から撮り、箱の壁で映る向きを決める
            var bMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude), bMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for q in quads { for v in [q.a, q.b, q.c, q.d] { let p = SIMD3(v.x, v.y, v.z); bMin = simd_min(bMin, p); bMax = simd_max(bMax, p) } }
            if quads.isEmpty { bMin = SIMD3(-1, -1, -1); bMax = SIMD3(1, 1, 1) }
            let pcC = (bMin + bMax) * 0.5, half = simd_max((bMax - bMin) * 0.5 * 1.02, SIMD3(repeating: 0.05))
            // ファンタジーの強さ（0 でふつうの見え方のまま組み上がる）：光らせる・乗算・映り込み・色ガラス・密度の乗算・光の帯をまとめて弱める
            let F = Float(st.fantasy)
            // 断面を出している間は、映り込み（白い帯）を弱める＝切り口の形が見やすい
            let fx4 = SIMD4<Float>(Float(st.glow4), Float(st.mul4), Float(st.reflSelf * (1 - 0.7 * lastSecF)), Float(st.glass4)) * F
            // 展開図のふつうの立体の間は、密度の乗算は効かせない（ふつうの物の見え方）
            //   z：展開図の色で乗算（ふつうの立体からガラスへ、自分の色のまま色つきセロハンのように重なる。組み上がるほど）
            let sq4 = SIMD4<Float>((n == 4 ? Float(st.squash4) : 0) * Float(1 - solidK) * F, Float(st.slant3) * Float(1 - solidK) * F, n == 5 ? Float(max(st.netMul, 0.55) * (1 - 0.4 * OrigamiState.smoother(st.progress))) : n == 4 ? Float(st.netMul * (1 - solidK)) : 0, 0)   // 5 次元：重なった所が乗算で濃く
            // w：やわらかい乗算（掛ける色を灰色と白へ寄せる）
            let probeAt = SIMD4<Float>(pcC, Float(st.softMul)), probeBox = SIMD4<Float>(half, Float(st.stripK * (1 - 0.7 * lastSecF)) * F)
            rr.encode(cb, rpd, w, h, u: &u, quads: qb, nq: nq1, order: ob, rods: rb, nr: rods.count, balls: bb, nb: balls.count, lineW: Float(max(0.3, st.lineWidthNow)), lineA: lineA, faceWrite: n == 3 && lastSecF < 0.001 && !(st.intVis > 0.01 && (st.intShape != 0 || st.intMethod == 2)), depth: depth, fx4: fx4, probeAt: probeAt, probeBox: probeBox, squash: sq4, lineFx: SIMD4<Float>(Float(st.lineTint), Float(solidK), Float(st.warmth), 0), cones: cones, marks: marks, nq2: nq1 > 0 ? ord2.count : 0, nAx: nAxRods, shift: SIMD2<Float>(Float(PS.x), Float(PS.y)), intTris: intBatches, intSpheres: intSpheres, markGlue: st.markGlue, ex: SIMD4<Float>(Float(st.depthDeep), Float(st.slantSheen), Float(st.line3W), Float(st.line3K))) { e2 in
                self.sky?.drawDust(e2, self.st, self.lastOff, eye: eyeW, tanF: tan(22.5 * Double.pi / 180), w: w, h: h, now: now)
                self.sky?.drawFlash(e2, self.st, w: w, h: h)
                self.drawAxisLabels(e2, w: w, h: h, eye: eyeW)
                self.drawXpLabels(e2, w: w, h: h, eye: eyeW)
                self.drawPtLabels(e2, w: w, h: h, eye: eyeW)
            }
            return
        }
        guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        if let spTex { e.setFragmentTexture(spTex, index: 0) }
        let tt0 = CACurrentMediaTime()
        defer { if PerfTest.on { PerfTest.add("升の一覧〜積む", CACurrentMediaTime() - tt0) } }
        if let (ql, rl, t0) = buildTiles(quads, rods, eye: gpu(eyeW), w: w, h: h, glowPad: spaceK > 0.001 ? 14 : 2) {
            u.T0 = t0; e.setFragmentBuffer(ql, offset: 0, index: 4); e.setFragmentBuffer(rl, offset: 0, index: 5)
        } else { e.setFragmentBuffer(qb, offset: 0, index: 4); e.setFragmentBuffer(qb, offset: 0, index: 5) }   // 一覧を作れなかった時は全部を調べる（T0.w ＝ 0）
        e.setRenderPipelineState(pipe)
        e.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
        e.setFragmentBuffer(qb, offset: 0, index: 1); e.setFragmentBuffer(rb, offset: 0, index: 2); e.setFragmentBuffer(bb, offset: 0, index: 3)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        sky?.drawDust(e, st, lastOff, eye: eyeW, tanF: tan(22.5 * Double.pi / 180), w: w, h: h, now: now)
        if spTex == nil { sky?.drawFlash(e, st, w: w, h: h) }
        drawAxisLabels(e, w: w, h: h, eye: eyeW)
        e.endEncoding()
    }
}

#if os(macOS)
struct OrigamiPane: NSViewRepresentable {
    let n: Int; let st: OrigamiState
    var driver: FrameDriver? = nil                 // コマを進める係（見本の小窓は、本体の係に乗せる＝別の画面のコマ送りを増やさない）
    final class Holder { var r: OrigamiRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = OrigamiMTKView(); v.n = n; v.st = st; context.coordinator.r = OrigamiRenderer(n: n, state: st, view: v); v.delegate = context.coordinator.r; (driver ?? st.driver).attach(v); return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}

/// Mac の絵の窓：マウスのドラッグとトラックパッドのつまみを、この窓が直接受ける。
///   SwiftUI のジェスチャーで受けると、マウスが動くたびに SwiftUI の作り直し（画面全体の並べ直し）が走って、絵のコマが落ちる
final class OrigamiMTKView: MTKView {
    var n = 4; weak var st: OrigamiState?
    private var last: NSPoint? = nil
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        last = e.locationInWindow
        // 重力ハンドル（矢印の先の玉）の近くを押したら、つかむ（形は回さない）
        if let st, st.gravHandleOn(n) {
            let q = convert(e.locationInWindow, from: nil)
            st.gravGrab = st.gravHit(n, CGPoint(x: q.x, y: bounds.height - q.y), size: bounds.size)
        }
    }
    override func mouseDragged(with e: NSEvent) {
        guard let st else { return }
        let p = e.locationInWindow, l = last ?? p; last = p
        // 窓の座標は上が＋なので、画面の下向き＋（SwiftUI のドラッグと同じ向き）にそろえる
        let dx = Double(p.x - l.x), dy = -Double(p.y - l.y)
        if st.gravGrab { st.gravDrag(n, dx, dy, alt: e.modifierFlags.contains(.option), size: bounds.size); return }
        // ⌘／Ctrl＋ドラッグ＝図形を動かす（回さない。ウェブ版と同じ）
        if !e.modifierFlags.intersection([.command, .control]).isEmpty { st.panBy(st.wix(n), dx, dy) }
        else if n == 5 {                                                     // 5 次元：転がす（3D の回転）か、5 次元だけの X-W・Y-W（⇧ W-V）
            if st.drag5Roll { st.drag(.r3x, dx * 0.01); st.drag(.r3y, dy * 0.01) }
            else if e.modifierFlags.contains(.shift) { st.drag(.wv5, dx * 0.01) } else { st.drag(.x5, dx * 0.01); st.drag(.y5, dy * 0.01) }
        }
        else if e.modifierFlags.contains(.shift) { st.drag(.zw, dx * 0.01) }
        else if e.modifierFlags.contains(.option) && n == 4 { st.drag(.l4x, dx * 0.01); st.drag(.l4y, dy * 0.01) }   // ⌥＋ドラッグ：w を傾ける（X‐W・Y‐W。4D の水をこぼす時など）
        else if n == 3 || st.dim5 { st.drag(.l4x, dx * 0.01); st.drag(.l4y, dy * 0.01) }   // 左：X-W・Y-W（左は X-Z・Y-Z。5 次元では超立方体の X-W・Y-W＝5 次元の X-V・Y-V）
        else { st.drag(.r3x, dx * 0.01); st.drag(.r3y, dy * 0.01) }            // 右：画面の縦・横の軸のまわりに形を回す
    }
    override func mouseUp(with e: NSEvent) { last = nil; st?.dragging = false; st?.gravGrab = false }
    override func magnify(with e: NSEvent) {
        guard let st else { return }
        let i = st.wix(n)
        st.zoom[i] = max(0.3, min(8, st.zoom[i] * (1 + Double(e.magnification))))
    }
    /// マウスのホイール・トラックパッドの 2 本指のスクロールで拡大・縮小（ウェブ版と同じ。上へ＝寄る）。
    ///   ホイールは 1 目盛りが大きいので弱め、トラックパッド（細かい量が来る）はなめらかに。倍率は 0.3〜8 倍
    override func scrollWheel(with e: NSEvent) {
        guard let st else { return }
        let i = st.wix(n)
        let dy = Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.004 : 0.06)
        guard dy != 0 else { return }
        st.zoom[i] = max(0.3, min(8, st.zoom[i] * exp(dy)))
    }
}
#else
struct OrigamiPane: UIViewRepresentable {
    let n: Int; let st: OrigamiState
    var driver: FrameDriver? = nil
    final class Holder { var r: OrigamiRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = OrigamiRenderer(n: n, state: st, view: v); v.delegate = context.coordinator.r; (driver ?? st.driver).attach(v); return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif

/// 座標軸の名前（数式の斜体。軸の線は Metal で描く）
struct OrigamiAxes: View {
    let n: Int; @ObservedObject var st: OrigamiState
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let i = st.wix(n), dist = st.dist[i], c = st.center[i], tanF = tan(22.5 * Double.pi / 180), asp = Double(size.width / max(1, size.height))
                func scr(_ p: SIMD3<Double>) -> CGPoint? {
                    let z = dist - p.z; guard z > 0.1 else { return nil }
                    return CGPoint(x: ((p.x - c.x) / (z * tanF * asp) * 0.5 + 0.5) * Double(size.width), y: (0.5 - (p.y - c.y) / (z * tanF) * 0.5) * Double(size.height))
                }
                guard st.showAxes else { return }
                let L = 1.8 * 1.35
                guard let o = scr(n == 3 ? st.place3([0, 0, 0]).0 : st.place4([0, 0, 0, 0]).0) else { return }
                for ax in 0..<n {
                    var e = [Double](repeating: 0, count: n); e[ax] = L
                    guard let b = scr(st.place(e, n).0) else { continue }
                    // 軸の線と先の玉は Metal で形と同じコマに描く（ここは名前だけ）
                    let col = Glass.axisCols[ax]
                    let dx = b.x - o.x, dy = b.y - o.y, l = max(1, hypot(dx, dy)), ux = dx / l, uy = dy / l
                    ctx.draw(Text(Glass.axisNames[ax]).font(.custom("KaTeX_Math-Italic", size: 26)).foregroundColor(col), at: CGPoint(x: b.x + ux * 24, y: b.y + uy * 24 - (l < 6 ? 18 : 0)))
                }
            }
        }
    }
}

/// 分解の番号の札（ウェブ版の xp-label：胞の色の丸に番号、横に ±軸の名前）と、数える時の札（「3 / 8 +X（右ヒンジ胞）」）
struct OrigamiLabels: View {
    let n: Int; @ObservedObject var st: OrigamiState
    var pi: Int { st.wix(n) }
    var body: some View {
        // 分解・数える時だけ、毎コマの時計を回す（いつも回すと、画面の組み立てが 1 秒 144 回走って重くなる）
        ZStack(alignment: .top) {
            // 三角形で描く時は、札は Metal で形と同じコマに描く（drawXpLabels）。光の道の時だけ、ここで重ねる
            if !st.raster && (st.explodeE > 0.01 || st.counting || st.xpAnim != nil) {
                TimelineView(.animation) { _ in Canvas { ctx, size in draw(ctx, size) } }
            }
            badge
        }
    }
    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let i = pi, e = st.explodeE, dist = st.dist[i], c = st.center[i]
        let tanF = tan(22.5 * Double.pi / 180), asp = Double(size.width / max(1, size.height))
        let cols = st.cellColors(n)
        for (k, p) in st.labels[i].enumerated() where k < cols.count {
            var op = min(1, e * 1.6), sc = 1.0
            if st.counting && st.countPhase != 0 {
                if st.countPhase == 1 && k > st.countIdx { op = 0 } else { op = 1; if st.countPhase == 1 && k == st.countIdx { sc = 1.3 } }
            }
            let z = dist - p.z
            guard z > 0.1, op > 0 else { continue }
            let x = ((p.x - c.x) / (z * tanF * asp) * 0.5 + 0.5) * Double(size.width)
            let y = (0.5 - (p.y - c.y) / (z * tanF) * 0.5) * Double(size.height)
            drawLabel(ctx, k, CGPoint(x: x, y: y), op, sc, OrigamiState.rgb(cols[k]))
        }
    }
    func drawLabel(_ ctx: GraphicsContext, _ k: Int, _ at: CGPoint, _ op: Double, _ sc: Double, _ rgb: SIMD3<Float>) {
        var g = ctx; g.opacity = op
        let name = OrigamiState.shortNames[n - 3][k], h: Double = 22 * sc
        let w: Double = h + Double(name.count) * 9 * sc
        let box = CGRect(x: at.x - w / 2, y: at.y - h / 2, width: w, height: h)
        let pill = Path(roundedRect: box, cornerRadius: h / 2)
        g.fill(pill, with: .color(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.88)))
        let ring: Color = sc > 1 ? Color(red: 0.98, green: 0.75, blue: 0.3) : Color(red: 0.2, green: 0.25, blue: 0.33)
        g.stroke(pill, with: .color(ring), lineWidth: sc > 1 ? 2 : 1)
        let cr = CGRect(x: box.minX + 3, y: box.minY + 3, width: h - 6, height: h - 6)
        g.fill(Path(ellipseIn: cr), with: .color(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))))
        g.draw(Text("\(k + 1)").font(.system(size: 10 * sc, weight: .bold)).foregroundColor(.white), at: CGPoint(x: cr.midX, y: cr.midY))
        g.draw(Text(name).font(.system(size: 11 * sc, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: cr.maxX + (w - h) / 2 + 2, y: at.y))
    }
    /// 数える時の札：今の番号と名前、数え終わったら全部の数
    @ViewBuilder var badge: some View {
        if st.faceSide != 0 && !(st.counting && st.countPhase != 0) {
            // 見せる胞（表だけ・裏だけ）の札：数える札が出ている時はそちらを先に（ウェブ版と同じ）
            LiveRead(live: st.live) { sideBadge }
        }
        if st.counting && st.countPhase != 0 && st.countIdx >= 0 {
            let cnt = n == 3 ? 6 : n == 4 ? 8 : 10, di = n - 3
            let done = st.countIdx >= cnt || st.countPhase == 2
            let text = done ? "全部で \(cnt)\(n == 3 ? "枚の正方形" : n == 4 ? "個の立方体" : "個の超立方体")"
                            : "\(st.countIdx + 1) / \(cnt)　\(OrigamiState.shortNames[di][st.countIdx])（\(OrigamiState.longNames[di][st.countIdx])）"
            Text(text)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color(red: 1.0, green: 0.9, blue: 0.6))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(red: 0.25, green: 0.16, blue: 0.04).opacity(0.85), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.98, green: 0.75, blue: 0.3).opacity(0.7)))
                .padding(.top, 70)
        }
    }
}

extension OrigamiLabels {
    /// 「見えている胞 4 / 8」＋小さな説明（ウェブ版の XP_SIDE_KIND と同じ言い方）
    var sideBadge: some View {
        let v = st.sideShown[pi], front = st.faceSide == 1
        let head = n == 3 ? (front ? "見えている面" : "裏の面") : (front ? "見えている胞" : "裏の胞")
        let sub = n == 3 ? (front ? "カメラから見て表を向いている正方形" : "カメラから見て裏を向いている正方形")
                         : (front ? "w の向こうから見て表を向いている立方体" : "w の向こうから見て裏を向いている立方体")
        return VStack(spacing: 1) {
            Text("\(head) \(v[0]) / \(v[1])").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.87, green: 0.84, blue: 1.0))
            Text(sub).font(.system(size: 10)).foregroundStyle(UIC.sub)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(Color(red: 0.12, green: 0.09, blue: 0.24).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.55)))
        .padding(.top, 70)
    }
}

/// 確かめ（--perftest）：本当に画面に出たコマの時刻を記録して、間隔のばらつきを数える（自分で回し続けて、8 秒で終わる）
enum PerfTest {
    static var on = false
    static var who: Any?
    static var sphPill = CGRect.zero
    static var rotPill = CGRect.zero                                  // 確かめ（ORIGAMI_BARTEST）：回転のボタンの場所（窓の中、左上が原点）
    static var scale = 0.75
    static var times: [[Double]] = [[], []]
    static var info: [String] = []
    static func note(_ i: Int, _ t: Double) { times[i].append(t) }
    static var parts: [String: (Double, Int)] = [:]
    static func add(_ k: String, _ s: Double) { let v = parts[k] ?? (0, 0); parts[k] = (v.0 + s, v.1 + 1) }
    static func report() {
        for (i, name) in ["立方体", "超立方体"].enumerated() {
            let t = times[i].filter { $0 > (times[i].first ?? 0) + 2 }      // はじめの 2 秒は数えない
            guard t.count > 10 else { print(name, "：コマが出ていない"); continue }
            let iv = zip(t.dropFirst(), t).map { ($0 - $1) * 1000 }.sorted()
            let med = iv[iv.count / 2], fps = Double(iv.count) / (t.last! - t.first!)
            let hist = Dictionary(grouping: iv, by: { Int(($0 / (1000.0 / 144)).rounded()) }).mapValues(\.count).sorted { $0.key < $1.key }
            print(String(format: "%@：画面に出たのは 1 秒 %.1f コマ・間隔の真ん中 %.2f ミリ秒・いちばん長い %.1f ミリ秒", name, fps, med, iv.last!))
            print("  間隔（144 分の 1 秒の何倍か：回数）", hist.map { "\($0.key)：\($0.value)" }.joined(separator: "　"))
        }
        info.forEach { print($0) }
        for (k, v) in parts.sorted(by: { $0.key < $1.key }) { print(String(format: "  %@：1 回 %.3f ミリ秒（%d 回）", k, v.0 / Double(max(1, v.1)) * 1000, v.1)) }
    }
}

/// 1 つの時計で、2 つの窓をいっしょに描く（窓ごとに別の時計だと、出る時刻がずれてコマが 1・2・3 回分とばらばらに出る＝とびとびに見える）。
///   画面に「ちょうどこの回数で」と頼む：画面の最高（144 など）で描き切れるならそれ、無理なら半分（72）・3 分の 1（48）。どれも画面の回数で割り切れるので、間隔がそろう
final class FrameDriver: NSObject {
    weak var st: OrigamiState?
    private struct W { weak var v: MTKView? }
    private var views: [W] = []
    private var link: CADisplayLink?
    private(set) var rate = 0
    private var rateT = 0.0, downT = CACurrentMediaTime(), scaleDownT = 0.0, scaleUpT = 0.0
    private(set) var costMs = 0.0, cpuMs = 0.0
    init(st: OrigamiState) { self.st = st }
    func attach(_ v: MTKView) {
        v.isPaused = true; v.enableSetNeedsDisplay = false
        views.removeAll { $0.v == nil }
        views.append(W(v: v))
        if link == nil {
            #if os(macOS)
            link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(step(_:)))
            #else
            link = CADisplayLink(target: self, selector: #selector(step(_:)))
            #endif
            link?.add(to: .main, forMode: .common)
            setRate(maxRate)
        }
    }
    var maxRate: Int {
        #if os(macOS)
        return max(60, (NSScreen.main ?? NSScreen.screens.first)?.maximumFramesPerSecond ?? 60)
        #else
        return max(60, UIScreen.main.maximumFramesPerSecond)
        #endif
    }
    private func setRate(_ r: Int) {
        guard r != rate, let link else { return }
        if PerfTest.on { PerfTest.info.append(String(format: "時計 %d → %d（重さ %.2f・頭脳 %.2f ミリ秒）", rate, r, costMs, cpuMs)) }
        rate = r; let f = Float(r)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }
    @objc private func step(_ l: CADisplayLink) {
        let t0 = CACurrentMediaTime()
        views.removeAll { $0.v == nil }
        st?.tickOnce(l.targetTimestamp)                                    // 動きは「このコマが画面に出る時刻」で進める（毎コマ同じだけ動く＝ゆれない）
        for w in views { w.v?.draw() }
        // 1 コマの重さ＝頭脳（ここで積んだ時間）と GPU の重いほう。画面の 1 回分の 8 割に収まるかで、回数を決める（下げるのはすぐ、上げるのは 1.5 秒ようすを見て）
        let cpu = (CACurrentMediaTime() - t0) * 1000, gpu = (st?.gpuMs[0] ?? 0) + (st?.gpuMs[1] ?? 0)
        // 一瞬の重さ（開いた時・窓の大きさが変わった時など）に引っぱられないよう、1 コマの値は持ち時間の 2 倍で頭打ちに
        let mx0 = maxRate, cap = 2000 / Double(mx0)
        costMs = costMs * 0.9 + min(cap, max(cpu, gpu)) * 0.1; cpuMs = cpuMs * 0.9 + cpu * 0.1
        let mx = maxRate, budget = 1000 / Double(mx)
        // 上げる時は、もっと余裕がある（6 割に収まる）のが 3 秒続いてから（境目で 144 と 72 を行ったり来たりすると、間隔がばらばらになる）
        // 下げるのは持ち時間の 9 割をこえた時、上げるのは 7 割 5 分より軽い時（前は 8 割・6 割で、大きく写すと 144 にもどれなかった）
        let down = costMs < budget * 0.9 ? mx : costMs < budget * 1.8 ? mx / 2 : mx / 3
        let up = costMs < budget * 0.75 ? mx : costMs < budget * 1.5 ? mx / 2 : mx / 3
        let now = t0
        // 下げるのも、重いのが 0.5 秒続いてから（一瞬の引っかかりで下げると、行ったり来たりする）
        // 描く細かさが「自動」の時は、コマ数を下げる前に細かさを下げる（寄って形が画面いっぱいになると、重なったガラスの面の光の計算が増える）
        if let st, st.renderScale == 0 {
            let g = st.gpuMs[0] + st.gpuMs[1], steps = [1.0, 0.85, 0.75, 0.67], k = steps.firstIndex(where: { abs($0 - st.autoScale) < 0.01 }) ?? 0
            if g > budget * 0.75 && k < steps.count - 1 {
                if now - scaleDownT > 0.4 { st.autoScale = steps[k + 1]; scaleDownT = now; scaleUpT = now }
            } else { scaleDownT = now }
            // 上げるのは、上げたあとの重さ（細かさの 2 乗に比例）でも 6 割 5 分に収まる時が 2 秒続いたら
            if k > 0 && g * pow(steps[k - 1] / steps[k], 2) < budget * 0.65 {
                if now - scaleUpT > 2 { st.autoScale = steps[k - 1]; scaleUpT = now }
            } else { scaleUpT = now }
            if k < steps.count - 1 { downT = now }                       // まだ細かさを下げられる間は、コマ数は下げない
        }
        if down < rate { if now - downT > 0.5 { setRate(down); rateT = now } }
        else { downT = now }
        if up > rate { if now - rateT > 2 { setRate(up); rateT = now } }
        else if up == rate { rateT = now }
    }
}
