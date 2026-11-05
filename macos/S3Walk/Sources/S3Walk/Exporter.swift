// 動画の書き出し（記録 → 書き出し）：
//   ① 記録：走っている間は絵を描かずに、右の超球の画面の「動き」だけを 1 コマずつ覚える（カメラ・ダイブ・ショーカメラの構図・彗星の場所・予定の道・跡・拍の時刻）。
//      音（風切り音・エンジン・チリン）もアプリの音をそのまま覚える。処理落ちして記録がまばらでも、あとで前後のコマの間をなめらかにつなぐ。
//   ② 書き出し：止めたあと、覚えた動きを 1 コマずつ再生して、16:9（フル HD か 4K）・きっちり 60 コマ・最高の細かさで描き直す（待ち時間がある）。
//      窓の形やパネルに関係なく描くので、足りない所は視野を広げて補う。ダイブ中は左上に小さく、ガラスの窓の地図（外から見た全体像）。
//   設定（予定の道・矢印・球殻の色など）は、超球の窓の設定に従う。Mac は「ムービー／球面さんぽ」、iPad・iPhone は写真へ
import SwiftUI
import AVFoundation
import CoreVideo
import VideoToolbox
#if os(iOS)
import Photos
#endif

final class VideoExport: ObservableObject {
    static let shared = VideoExport()
    /// 記録の 1 コマ
    struct RecFrame {
        var t: Double, dom: Double
        var walk: HyperLabState.Walk                                    // 跡は空にしてしまっておく（跡はふえた分だけ下に）
        var trailAdd: [SIMD4<Double>] = [], trailReset = false, trailTrim = 0
        var f: [Double]
        var cometDir: SIMD3<Double>, showFrame: SIMD2<Double>
        var layers: Int, lzw: Int, version: Int
        var diveOn: Bool, dragging: Bool, padHolding: Bool
        var walkCam: Camera?                                            // さんぽの景色のカメラ（書き出しで、さんぽの景色もこのカメラで描き直す）
        var first = false                                               // 景色の場所を一人称のダイブ画面にしていた
        var both = false, swap = false                                  // 「両方」でダイブ画面を出していた・上下を入れかえていた
        var pane = false                                                // 左の窓がダイブの時の中身（地図）だった
        var ball = false                                                // 左上の窓に 3D の球を出していた
        var run: [Double] = []                                          // ダイブ画面の超球ラン：金色の線の点（x・y・z・w × 数）。空なら線なし
        var tun: [Double] = []                                          // トンネル：彗星の場所（断面の 3 つ）・断面の向き（12）・穴（半径・向き 3・開き × 数）。空ならトンネルでない
        init(t: Double, dom: Double, walk: HyperLabState.Walk, rawTrail: [SIMD4<Double>], f: [Double], cometDir: SIMD3<Double>, showFrame: SIMD2<Double>,
             layers: Int, lzw: Int, version: Int, diveOn: Bool, dragging: Bool, padHolding: Bool, walkCam: Camera?, both: Bool = false, swap: Bool = false, first: Bool = false, pane: Bool = false, ball: Bool = false) {
            self.walkCam = walkCam; self.both = both; self.swap = swap; self.first = first; self.pane = pane; self.ball = ball
            self.t = t; self.dom = dom; var w = walk; trailTrim = max(0, rawTrail.count - walk.trail.count); w.trail = []; self.walk = w
            self.f = f; self.cometDir = cometDir; self.showFrame = showFrame; self.layers = layers; self.lzw = lzw; self.version = version
            self.diveOn = diveOn; self.dragging = dragging; self.padHolding = padHolding
            trailAdd = rawTrail                                         // ふえた分に直すのは capture で
        }
    }
    // 大きさ：16:9 のフル HD（1920×1080）か 4K（3840×2160）。左上の小さな地図はその 1/4 の幅
    @Published var uhd = UserDefaults.standard.bool(forKey: "s3walk.export.4k") { didSet { UserDefaults.standard.set(uhd, forKey: "s3walk.export.4k") } }
    // 画質：0 標準（ファイルが小さい）・1 高画質（細い線がつぶれにくい）・2 最高（ProRes 422 HQ。圧縮でほとんど崩れないが、とても大きい）
    @Published var quality = UserDefaults.standard.object(forKey: "s3walk.export.quality") as? Int ?? 1 { didSet { UserDefaults.standard.set(quality, forKey: "s3walk.export.quality") } }
    /// 1 秒あたりの大きさ（Mbit）の目安
    var mbps: Double { quality == 2 ? (uhd ? 1800 : 450) : quality == 1 ? (uhd ? 250 : 80) : (uhd ? 60 : 24) }
    @Published var withMap = UserDefaults.standard.object(forKey: "s3walk.export.map") as? Bool ?? true { didSet { UserDefaults.standard.set(withMap, forKey: "s3walk.export.map") } }   // 左上に小さく全体像の地図を入れる
    @Published fileprivate(set) var recording = false
    @Published private(set) var rendering = false
    @Published private(set) var progress = 0.0
    // 書き出しのレイアウト：0 ダイブ画面だけ（左上に小さくガラスの窓の地図）・1 超球の窓のレイアウト（左上 地図・左下 さんぽの景色・残りに大きくダイブ画面。仕切りは超球の窓と同じ比率）
    @Published var layout = UserDefaults.standard.integer(forKey: "s3walk.export.layout") { didSet { UserDefaults.standard.set(layout, forKey: "s3walk.export.layout") } }
    // ダイブしていなくても、書き出しはダイブ（三人称）で描く。カメラ（オートカメラ・ショーカメラ）は書き出しの中で動かす
    // ダイブイン：動画の始めに 6 秒、超球の全体から走る所へ寄っていく。走り出しは寄り切る 2 秒前からゆっくり（速さがつながる）。音はその間、風の音がだんだん大きくなる
    @Published var diveIn = UserDefaults.standard.bool(forKey: "s3walk.export.diveIn") { didSet { UserDefaults.standard.set(diveIn, forKey: "s3walk.export.diveIn") } }
    private static let introFrames = 360, introEase = 120
    private var introN = 0
    /// 書き出しのコマ i が、記録の何コマ目か（ダイブインの間は止まっていて、少しずつ動き出す）
    private func recFrame(_ i: Int) -> Double {
        guard introN > 0 else { return Double(i) }
        let T = Double(Self.introEase), st0 = introN - Self.introEase
        if gen != nil { return Double(Self.genFI + max(0, i - st0)) }    // 決まった道から作る時：はじめの待ちを飛ばす（道には走り出しのゆっくりが入っている）
        if i <= st0 { return 0 }
        if i < introN { let u = Double(i - st0); return u * u / (2 * T) }
        return Double(i - introN) + T / 2
    }
    /// 音を後ろへずらす秒数（ダイブインの分）
    private var audioD: Double { introN == 0 ? 0 : gen != nil ? Double(introN - Self.introEase - Self.genFI) / 60 : Double(introN - Self.introEase / 2) / 60 }
    /// ダイブインの風の音の長さ（秒）
    private var introSec: Double { gen != nil ? Double(introN - Self.introEase) / 60 + 0.7 : audioD }   // 道から作る時は、走りの音が立ち上がるまで少し重ねる
    private var introCount = 0                                           // 音の並びの、はじめのダイブインの音の数
    @Published var forceDive = UserDefaults.standard.object(forKey: "s3walk.export.forceDive") as? Bool ?? true { didSet { UserDefaults.standard.set(forceDive, forKey: "s3walk.export.forceDive") } }
    // 2 本の書き出し：1 回の走りから、ダイブの本と超球の本（全面・同じコマ数・同じ音）を順に描く。編集ソフトで重ねて切りかえる用
    @Published var dual = UserDefaults.standard.bool(forKey: "s3walk.export.dual") { didSet { UserDefaults.standard.set(dual, forKey: "s3walk.export.dual") } }
    var dualOnce: Bool? = nil                                            // らくらく書き出し：今回だけ dual の代わりに
    private var pass = 0, dualStamp = "", firstURL: URL? = nil, mapOn = true   // pass：0 ふつう・1 ダイブの本・2 超球の本
    // プロキシ：走っている間、画面は粗く描いて（小さい画面は止める）、本物の動画は記録を追いかけて裏で描く。記録は動きだけなので、画面の粗さは動画に入らない
    var proxy = false                                                    // 次の記録をプロキシで
    private(set) var liveRun = false                                     // 記録しながら描いている
    var proxyNow: Bool { proxy && recording }
    private static let liveMargin = 2.2                                  // 記録の先端からこれだけ後ろを描く（終わりのフェードが間に合うように）
    private var aFed = 0                                                 // 記録した音のうち、書く側へ渡した数
    @Published var message: String? = nil
    // 画面の上の文字も描き込む（窓の見出し・走行中の座標・周回・角度の読み・さんぽの景色の極）
    @Published var heavy = UserDefaults.standard.object(forKey: "s3walk.export.heavy") as? Bool ?? false { didSet { UserDefaults.standard.set(heavy, forKey: "s3walk.export.heavy") } }   // 書き出しはヘビーモードで描く
    @Published var withText = UserDefaults.standard.object(forKey: "s3walk.export.text") as? Bool ?? true { didSet { UserDefaults.standard.set(withText, forKey: "s3walk.export.text") } }
    // 決まった道から作る：道（PathMode の番号。7 は自分の道 genRoute）と長さ（秒）
    @Published var genPath = UserDefaults.standard.object(forKey: "s3walk.export.genPath") as? Int ?? PathMode.tour.rawValue { didSet { UserDefaults.standard.set(genPath, forKey: "s3walk.export.genPath") } }
    @Published var genRoute = UserDefaults.standard.string(forKey: "s3walk.export.genRoute") ?? "" { didSet { UserDefaults.standard.set(genRoute, forKey: "s3walk.export.genRoute") } }
    @Published var genSeconds = min(60, UserDefaults.standard.object(forKey: "s3walk.export.genSec") as? Double ?? 0) { didSet { UserDefaults.standard.set(genSeconds, forKey: "s3walk.export.genSec") } }   // 0：1 周・−1：2 周
    /// 書き出しの間だけ：裏で道を歩く、もう一人のさんぽ（さんぽの景色もこれで描く）
    private(set) var gen: Renderer? = nil
    private var genTpl: RecFrame? = nil, genCs: SIMD4<Double>? = nil, genSpd = 0.0, genFreed = 0
    // 決まった道から作る時の音：画面に出さずに作る音（超球の窓の音と同じ作り方）と、その時の速さ・曲がり・チェックポイント
    private var genBall = true, gsRailK = 1.0, gsRailN = 0, gsSong = 0.0, gsWind = 1.0, gsRush = 0.0, gsAim = 0.0, gsAir = AirSim(), gsFlyA = 0.0, gsFlySide = 0.0   // 極の音は 1 コマ前の値で空気を乱す
    private var genSnd: HyperSound? = nil, genAFmt: AVAudioFormat? = nil, gsVol = 0.7, gsPlace = 0.7, gsLayerOn = false, gsBass = 1.0, gsRough = 1.0, gsSwing = 0.0, gsPass = PolePass(), gsLayer: Int? = nil, gsPos: SIMD4<Double>? = nil, gsFwd: SIMD4<Double>? = nil
    private var gsTurn = 0.0, gsSpeed = 0.0, gsWobT = -9.0, gsIceT = -9.0, genHits: [(p: V4, t: Double, pole: Int)] = []
    /// 決まった道から作る時の超球の向き（自動で回す・自分を追う・切り口の往復を、超球の窓と同じく 1/60 秒ずつ進める）
    private var genSt: HyperLabState? = nil, genLW = LapWatch(), genLapN = 1
    var active: Bool { recording }
    var busy: Bool { rendering }
    private(set) var started = Date()

    // 記録
    fileprivate var frames: [RecFrame] = [], lastRaw: [SIMD4<Double>] = []
    fileprivate var audio: [(b: AVAudioPCMBuffer, t: Double)] = [], audioFormat: AVAudioFormat? = nil, aClock: Double? = nil
    private let aq = DispatchQueue(label: "s3walk.export.audio")
    private var watch: Timer? = nil

    // 走り出しで始めて、止まったら黒く消して終わる：押すと待機。走り出したら記録を始めてフェードイン、止まったらフェードアウトして、真っ黒で記録も終わり
    @Published var autoRec = UserDefaults.standard.bool(forKey: "s3walk.export.auto") { didSet { UserDefaults.standard.set(autoRec, forKey: "s3walk.export.auto") } }
    @Published private(set) var armed = false
    private var armPos: SIMD4<Double>? = nil, armT = 0.0, stillSince: Double? = nil, recFade = false, fadeNow = false, autoStopping = false
    func toggle() {
        if armed { armed = false; return }
        if recording { stopRecording(); return }
        recFade = false
        if autoRec { armPos = nil; autoStopping = false; armed = true } else { startRecording() }
    }

    private func fileName(_ dualNow: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd_HHmmss"
        guard dualNow else { return "球面さんぽ_ダイブ_\(f.string(from: Date())).mov" }
        if pass == 0 { dualStamp = f.string(from: Date()) }                 // 2 本は同じ時刻の名前で並ぶように
        return "球面さんぽ_\(dualStamp)_\(pass == 2 ? "超球" : "ダイブ").mov"
    }

    // ---- 音を写し取る（記録と、直前 1 分のどちらにも使う。1 本の口で）----
    private var aRingClock: Double? = nil
    fileprivate var ringMoving = false, ringVT = 0.0, ringVTReal = 0.0
    private func ensureTap() {
        guard HyperSound.shared.running, !HyperSound.shared.tapped else { return }
        if audioFormat == nil { audioFormat = HyperSound.shared.tapFormat() }
        HyperSound.shared.tap { [weak self] b, t in
            guard let self, self.recording || (self.keepLast && self.ringMoving), let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength) else { return }   // 音の入れ物は使い回されるので写す
            c.frameLength = b.frameLength
            let n = Int(b.frameLength), ch = Int(b.format.channelCount)
            if let src = b.floatChannelData, let dst = c.floatChannelData {
                if b.format.isInterleaved { dst[0].update(from: src[0], count: n * ch) } else { for k in 0..<ch { dst[k].update(from: src[k], count: n) } }
            }
            // 音の時刻：最初の 1 回だけ時計で決めて、あとは音の長さを足していく（時刻のずれ・飛びが起きない）
            let now = t.isHostTimeValid ? AVAudioTime.seconds(forHostTime: t.hostTime) : CACurrentMediaTime()
            let len = Double(c.frameLength) / c.format.sampleRate
            let rec = self.recording, ring = self.keepLast && self.ringMoving, vt = self.ringVT + max(0, min(0.1, now - self.ringVTReal))
            self.aq.async {
                if rec {
                    if self.aClock == nil || abs(now - self.aClock!) > 0.5 { self.aClock = now }   // 大きくずれた時（音が止まっていた後など）だけ合わせ直す
                    let ht = self.aClock!; self.aClock = ht + len; self.audio.append((c, ht))
                }
                if ring {                                                   // 直前 1 分：動いている間の時刻（止まっていた間は数えない）
                    if self.aRingClock == nil || abs(vt - self.aRingClock!) > 0.5 { self.aRingClock = vt }
                    let ht = self.aRingClock!; self.aRingClock = ht + len; self.ringAudio.append((c, ht))
                    let old = vt - self.ringKeep - 2
                    if let f = self.ringAudio.first, f.t < old - 2 { self.ringAudio.removeFirst(self.ringAudio.prefix { $0.t < old }.count) }   // 2 秒ぶんまとめて捨てる
                }
            }
        }
    }

    // ---- ① 記録 ----
    /// 止めるタイマー（分。0 はなし）：書き出しの記録も、画面の録画も、時間が来たら止める（止め忘れても大丈夫なように）
    @Published var stopMin = UserDefaults.standard.object(forKey: "s3walk.export.stopMin") as? Int ?? 0 { didSet { UserDefaults.standard.set(stopMin, forKey: "s3walk.export.stopMin") } }
    /// 記録を止める秒数（タイマーなしでも 20 分で止める）
    static func stopLimit(_ min: Int) -> Double { min > 0 ? Double(min) * 60 : 20 * 60 }
    func startRecording() {
        guard !recording, !rendering else { return }
        frames = []; lastRaw = []; aq.sync { audio = []; aClock = nil }
        audioFormat = HyperSound.shared.tapFormat()
        ensureTap()
        started = Date(); recording = true
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.started) > Self.stopLimit(self.stopMin) { self.stopRecording(note: self.stopMin > 0 ? "タイマー（\(self.stopMin) 分）で止めて、書き出しました。\n" : "記録は 20 分までなので、ここで止めました。\n") }
        }
    }
    /// 1 コマ分を覚える（右の超球の画面が描くたびに呼ぶ）。跡はふえた分だけ
    func capture(_ f0: RecFrame) {
        ensureTap()
        if keepLast { ringCapture(f0) }
        // 動いているか（1 秒に 0.02 rad より速い）。待機中は走り出しを待ち、自動の記録中は止まったのを見る
        let dtA = f0.t - armT, spd = armPos.map { simd_length(f0.walk.pos - $0) / max(1e-6, dtA) } ?? 0, usable = armPos != nil && dtA > 0 && dtA < 0.5
        armPos = f0.walk.pos; armT = f0.t
        if armed && usable && spd > 0.02 { armed = false; recFade = true; stillSince = nil; startRecording() }
        if recording && recFade {
            if spd > 0.02 { stillSince = nil }
            else if usable {
                let s0 = stillSince ?? f0.t; stillSince = s0
                if f0.t - s0 >= 0.3 + Double(Self.genFO) / 60 && !autoStopping {   // 止まってから 2 秒ぶん（フェードアウト）を記録して、真っ黒の所で終わる
                    autoStopping = true
                    DispatchQueue.main.async { self.stopRecording() }
                }
            }
        }
        guard recording else { return }
        if let l = frames.last {                                           // 走っている間の、まだ進んでいないコマは覚えない（同じ場所が続くと、書き出しで進みが飛ぶ）
            if l.walk.pos != f0.walk.pos { recMoveT = f0.t } else if f0.t - recMoveT < 0.3 { return }
        }
        var f = f0
        let raw = f.trailAdd
        if !lastRaw.isEmpty, raw.count >= lastRaw.count, raw[lastRaw.count - 1] == lastRaw[lastRaw.count - 1] {
            f.trailAdd = Array(raw[lastRaw.count...]); f.trailReset = false
        } else { f.trailAdd = raw; f.trailReset = true }
        lastRaw = raw
        frames.append(f)
        if proxy && !rendering, let l = frames.last, l.t - frames[0].t > 0.4 {   // 音の形式が決まるまで少し待ってから、裏で描き始める
            liveRun = true
            startRender("")
            if !rendering { liveRun = false; proxy = false; cancelRecording() }   // 始められなかった（空きが足りないなど）
        }
    }
    /// 記録をやめる（動画にしない）
    func cancelRecording() {
        guard recording else { return }
        recording = false; watch?.invalidate(); watch = nil
        if !keepLast { HyperSound.shared.untap() }
        proxy = false
        if liveRun { cancelRender(); return }
        frames = []; lastRaw = []
    }
    func stopRecording(note: String = "") {
        guard recording else { return }
        recording = false; watch?.invalidate(); watch = nil
        if !keepLast { HyperSound.shared.untap() }
        if liveRun { endLive(note); return }
        proxy = false
        guard frames.count >= 2 else { message = note + "記録が短すぎました（超球の窓を出して、少し走ってから止めてください）"; return }
        startRender(note)
    }

    // ---- 直前の走り：いつも裏で、動いている間の直前の動きと音を覚えておく（長さは keepMin 分。メモリは 1 分で約 40 MB）----
    //   止まっている間は数えない（含めない）。途切れ（アナ極へ戻る・遠くへ飛ぶ）があったら、そこから先だけにする。跡が消えただけなら続ける（1 周で跡を消す時も、周をまたいで覚える）
    @Published var keepLast = UserDefaults.standard.object(forKey: "s3walk.export.keepLast") as? Bool ?? true { didSet { UserDefaults.standard.set(keepLast, forKey: "s3walk.export.keepLast"); if !keepLast { ringClear(nil) } } }
    @Published private(set) var ringSeconds = 0.0
    @Published var keepMin = UserDefaults.standard.object(forKey: "s3walk.export.keepMin") as? Int ?? 5 { didSet { UserDefaults.standard.set(keepMin, forKey: "s3walk.export.keepMin"); ringKeep = Double(keepMin) * 60 } }   // 裏で覚える長さ（分。上限 10 分）
    fileprivate lazy var ringKeep = Double(keepMin) * 60
    @Published var lastLen = UserDefaults.standard.object(forKey: "s3walk.export.lastLen") as? Double ?? 30 { didSet { UserDefaults.standard.set(lastLen, forKey: "s3walk.export.lastLen") } }   // 直前の書き出しの長さ：秒。−1・−2 は 1 周・2 周ぶん
    /// 道を走っているか（周で選べるのは、この時だけ）
    var routeRunning: Bool { (HyperLabState.walkRendererGet?()?.pathMode ?? .none) != .none }
    var lastLenName: String { lastLen < 0 ? (routeRunning ? "\(Int(-lastLen)) 周ぶん" : "60 秒") : "\(Int(lastLen)) 秒" }
    fileprivate var ringFrames: [RecFrame] = [], ringBase: [SIMD4<Double>] = [], ringLastRaw: [SIMD4<Double>] = []
    private var ringAudio: [(b: AVAudioPCMBuffer, t: Double)] = []
    private var ringMoveT = -9.0, recMoveT = -9.0
    private var ringLastPos: SIMD4<Double>? = nil, ringLastDist: Double? = nil, ringLastReal: Double? = nil
    private func ringClear(_ raw: [SIMD4<Double>]?) {
        ringFrames = []; ringBase = raw ?? []; ringLastRaw = raw ?? []
        aq.async { self.ringAudio = []; self.aRingClock = nil }
        if ringSeconds != 0 { ringSeconds = 0 }
    }
    fileprivate func ringCapture(_ f0: RecFrame) {
        let now = f0.t, raw = f0.trailAdd
        let dtReal = ringLastReal.map { now - $0 } ?? 0; ringLastReal = now
        let pos = f0.walk.pos
        let moved = ringLastPos.map { acos(max(-1, min(1, simd_dot($0, pos)))) } ?? 0
        ringLastPos = pos
        // 途切れ・リセット：遠くへ飛んだ・歩いた道のりが戻った・跡が消えた（短くなった・最初が変わった）
        let trailCut = !ringLastRaw.isEmpty && (raw.count < ringLastRaw.count || raw[ringLastRaw.count - 1] != ringLastRaw[ringLastRaw.count - 1])
        let jump = moved > 0.3 || (ringLastDist.map { f0.walk.dist < $0 - 1e-6 } ?? false)
        ringLastDist = f0.walk.dist
        if jump { ringClear(raw) }
        let speed = dtReal > 1e-6 ? moved / dtReal : 0
        if speed > 0.004 { ringMoveT = now }
        ringMoving = now - ringMoveT < 0.3 && dtReal < 0.5                 // 歩く計算は別のコマで進むので、1 コマ動かなくても止まったとは見ない
        guard ringMoving else { return }                                   // 止まっている間は覚えない
        ringVT += min(dtReal, 0.1); ringVTReal = now
        if moved < 1e-10 && !ringFrames.isEmpty { return }                 // まだ進んでいないコマは時間だけ数える（同じ場所を覚えると、次のコマで進みが飛ぶ）
        var f = f0; f.t = ringVT
        if ringLastRaw.isEmpty { f.trailAdd = raw; f.trailReset = true; ringBase = [] }
        else if trailCut && !jump { f.trailAdd = raw; f.trailReset = true }  // 跡が消えた・古い跡が切られた：この時の跡をまるごと覚える
        else { f.trailAdd = Array(raw[min(raw.count, ringLastRaw.count)...]); f.trailReset = false }
        ringLastRaw = raw
        ringFrames.append(f)
        // 長さより前は 2 秒ぶんまとめて捨てる（捨てた分の跡は ringBase にまとめておく。1 コマずつだと、長い時に毎コマ全部を詰め直して重い）
        if let first = ringFrames.first, first.t < ringVT - ringKeep - 2 {
            let old = ringFrames.prefix { $0.t < ringVT - ringKeep }
            for g in old { if g.trailReset { ringBase = g.trailAdd } else { ringBase += g.trailAdd } }
            ringFrames.removeFirst(old.count)
        }
        let secs = (ringFrames.last?.t ?? 0) - (ringFrames.first?.t ?? 0)
        if abs(secs - ringSeconds) > 0.5 { ringSeconds = secs }
    }
    /// 直前の走りを書き出す（lastLen 秒、道を走っている時は 1 周・2 周ぶんも）
    func exportLast() {
        guard !recording, !rendering else { return }
        guard ringFrames.count >= 2 else { message = "まだ覚えている動きがありません（超球の窓を出して、少し走ってください）"; return }
        var from = 0, to = ringFrames.count
        if lastLen < 0 && routeRunning {                                   // 走り終えた周だけを、周の切れ目から切れ目まで
            let n = Int(-lastLen), cuts = ringFrames.indices.dropFirst().filter { ringFrames[$0].walk.lap != ringFrames[$0 - 1].walk.lap }
            guard cuts.count > n else { message = "まだ \(n) 周ぶん走っていません（覚えている周の切れ目 \(cuts.count) か所）。もう少し走ってから押してください"; return }
            from = cuts[cuts.count - 1 - n]; to = cuts[cuts.count - 1]
        } else {
            let t0 = ringFrames[ringFrames.count - 1].t - (lastLen < 0 ? 60 : lastLen)
            from = ringFrames.firstIndex { $0.t >= t0 } ?? 0
        }
        var base = ringBase
        for g in ringFrames[..<from] { if g.trailReset { base = g.trailAdd } else { base += g.trailAdd } }
        var fs = Array(ringFrames[from..<to])
        var first = fs[0]; first.trailAdd = (first.trailReset ? [] : base) + first.trailAdd; first.trailReset = true; fs[0] = first
        frames = fs
        let a0 = fs[0].t - 1, a1 = fs[fs.count - 1].t + 1
        let au = aq.sync { ringAudio.filter { $0.t >= a0 && $0.t <= a1 } }
        aq.sync { audio = au }
        if audioFormat == nil { audioFormat = HyperSound.shared.tapFormat() }
        if au.isEmpty { audioFormat = nil }
        startRender("")
    }

    // ---- ② 書き出し（再生して描き直す）----
    private var writer: AVAssetWriter? = nil, vIn: AVAssetWriterInput? = nil, aIn: AVAssetWriterInput? = nil, adaptor: AVAssetWriterInputPixelBufferAdaptor? = nil
    private var st2: HyperLabState? = nil, r2: HyperLabRenderer? = nil, cache: CVMetalTextureCache? = nil
    private var url: URL? = nil, outW = 1920, outH = 1080, nOut = 0, iOut = 0, jRec = 0, trail: [SIMD4<Double>] = [], appliedTo = -1
    private var lay = 0, force = true, glass: InsetGlass? = nil
    private var aIdx = 0, inFlight = 0, note = "", aList: [(b: AVAudioPCMBuffer, t: Double)] = [], failed = false
    private let wq = DispatchQueue(label: "s3walk.export.write")

    fileprivate func startRender(_ note0: String) {
        guard let live = HyperLabRenderer.liveMain else { message = note0 + "超球の窓が見つかりませんでした"; return }
        note = note0
        let second = pass == 2, dualNow = second || (dualOnce ?? dual)
        if liveRun && aq.sync(execute: { audio.isEmpty }) { audioFormat = nil }   // 音が出ていない時は、音なしの動画に（音を待ち続けないように）
        live.st.saveIfChanged()                                             // 今の設定を覚えてから、書き出し用の状態を同じ設定で作る
        let s2 = HyperLabState()
        s2.noSink = true                                                   // 書き出しの再生で、さんぽの窓の R の世界を変えない
        s2.diveSpin = live.st.diveSpin; s2.expandOn = live.st.expandOn; s2.stageView = live.st.stageView; s2.stageOnly = live.st.stageOnly
        s2.rOnly = live.st.rOnly; s2.rOnlyR = live.st.rOnlyR                // ダイブの回り方・拡張のステージ・この R だけ（書き出し始めの設定）
        genBall = live.st.show3D
        s2.heavy = heavy || live.st.heavy || CommandLine.arguments.contains("--heavy")
        if CommandLine.arguments.contains("--both") { s2.lowView = 2; s2.lowSwap = CommandLine.arguments.contains("--swap") }
        guard let r = HyperLabRenderer(side: .right, state: s2, view: nil) else { message = note + "書き出しの準備ができませんでした"; return }
        let u: URL
        #if os(macOS)
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("球面さんぽ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        u = dir.appendingPathComponent(fileName(dualNow))
        #else
        u = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(dualNow))
        #endif
        guard let wr = try? AVAssetWriter(outputURL: u, fileType: .mov) else { message = note + "動画を作り始められませんでした"; return }
        outW = uhd ? 3840 : 1920; outH = uhd ? 2160 : 1080
        let br = Int(mbps * 1_000_000)
        let nSec = gen != nil ? Double(genOut) / 60 : liveRun ? 60 : (frames[frames.count - 1].t - frames[0].t)   // プロキシは長さがまだ分からないので 1 分で見る
        // 空きが足りなければ始めない（書き出したあとも 5 GB 残す）
        if let free = (try? u.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           Double(free) < mbps / 8 * 1_000_000 * nSec * 1.1 * (dualNow && !second ? 2 : 1) + 5e9 {
            message = String(format: "空きが足りません（約 %.1f GB 必要）。画質を下げるか、空きを作ってください", mbps / 8 / 1000 * nSec * 1.1 * (dualNow && !second ? 2 : 1)); gen = nil; genSnd?.stop(); genSnd = nil; frames = []; return }
        var vs: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: outW, AVVideoHeightKey: outH,
                                 AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: br, AVVideoExpectedSourceFrameRateKey: 60, AVVideoMaxKeyFrameIntervalKey: 120,
                                                                   AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]]
        if quality == 2 { vs = [AVVideoCodecKey: AVVideoCodecType.proRes422HQ, AVVideoWidthKey: outW, AVVideoHeightKey: outH] }
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vs); vi.expectsMediaDataInRealTime = false
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vi, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH,
            kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        if wr.canAdd(vi) { wr.add(vi) }
        var ai: AVAssetWriterInput? = nil
        if let fmt = gen != nil ? genAFmt : audioFormat {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: fmt.sampleRate,
                                                                           AVNumberOfChannelsKey: min(2, Int(fmt.channelCount)), AVEncoderBitRateKey: 256_000])
            a.expectsMediaDataInRealTime = false
            if wr.canAdd(a) { wr.add(a); ai = a }
        }
        guard wr.startWriting() else { message = note + "動画を作り始められませんでした：\(wr.error?.localizedDescription ?? "")"; return }
        wr.startSession(atSourceTime: .zero)
        writer = wr; vIn = vi; aIn = ai; adaptor = ad; url = u; audioT0 = frames.first?.t
        pass = second ? 2 : dualNow ? 1 : 0
        st2 = s2; r2 = r; cache = nil; glass = InsetGlass(r.device)
        lay = dualNow ? 0 : layout; mapOn = withMap && !second               // 2 本の時はどちらも全面。超球の本に小さな地図はいらない
        let fd = forceDive && !liveRun                                      // プロキシは走った時のカメラのまま
        force = second ? false : dualNow ? gen != nil || fd || frames.contains { $0.f[0] < 0.999 } : fd   // ダイブの本は全部ダイブで（走った時の記録が全部ダイブなら、そのカメラのまま）
        if force { s2.diveOn = true; s2.diveThird = true; s2.diveT = 1; s2.thirdK = 1; s2.diveFade = 0 }
        var c: CVMetalTextureCache?; CVMetalTextureCacheCreate(nil, nil, r.device, nil, &c); cache = c
        let t0 = frames[0].t
        iOut = 0; fadeNow = gen == nil && recFade; introN = diveIn ? Self.introFrames : 0
        if liveRun { nOut = Int.max / 2 } else { countOut() }               // プロキシは走り終わるまでコマ数が決まらない
        jRec = 0; trail = []; appliedTo = -1; aIdx = 0; inFlight = 0; failed = false; if pass != 2 { dropN = 0 }
        colKey = nil; colPrev = nil; colOld = nil; colFade = 0; fullPrev = nil; fullOld = nil; fullFade = 0
        let al = aq.sync { aFed = audio.count; return audio }, makingSound = gen != nil && genSnd != nil; var intro: [(AVAudioPCMBuffer, Double)] = []                       // ダイブインの間の音：寄っていくのに合わせて、風の音がだんだん大きくなる
        if introN > 0, !second, let fmt = gen != nil ? genAFmt : audioFormat {
            let n: AVAudioFrameCount = 4096, step = Double(n) / fmt.sampleRate, cnt = Int(introSec / step), snd = HyperSound()   // 一度に作れるのは 4096 標本まで
            snd.spatial = live.st.soundSpatial
            let sf = snd.startOffline(rate: fmt.sampleRate), same = sf?.channelCount == fmt.channelCount && sf?.isInterleaved == fmt.isInterleaved
            for i in 0...cnt {
                let rest = Int((introSec * fmt.sampleRate).rounded()) - i * Int(n), len = min(Int(n), rest)   // 最後のひと切れで長さをぴったりに（走りの音とすき間を作らない）
                if len <= 0 { break }
                let p = Double(i) / Double(max(1, cnt)), ta = max(0, min(1, Double(cnt - i) * step / 0.3))   // 終わりの 0.3 秒で、走りの音へ渡す
                var b: AVAudioPCMBuffer? = nil
                if same {
                    snd.update(speed: 0.15 + 0.6 * p, zoom: p * p, volume: live.st.soundVol * min(1, p * 2.5) * ta)
                    snd.tune(height: 0, place: 0, bass: live.st.soundBass, rough: live.st.soundRough, phones: live.st.soundPhones, song: live.st.soundSong, wind: live.st.soundWind)
                    b = snd.renderOffline(len)
                }
                if b == nil, let z = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) {   // 作れない時は無音（音と絵は交互に書く決まりなので、無音も渡す）
                    z.frameLength = AVAudioFrameCount(len)
                    for c in 0..<Int(fmt.channelCount) { if let d = z.floatChannelData?[fmt.isInterleaved ? 0 : c] { memset(d, 0, Int(n) * MemoryLayout<Float>.size * (fmt.isInterleaved ? Int(fmt.channelCount) : 1)) } }
                    b = z
                }
                if let b { intro.append((b, t0 - audioD + Double(i) * step)) }
            }
            snd.stop()
        }
        if !second { introCount = intro.count }
        wq.sync { if !second { aList = intro + al }; audioDone = false; aLive = (makingSound || liveRun) && !second }   // 2 本目は 1 本目と同じ音の並びをそのまま使う                  // 記録した音（書き出し中は、書く糸の上だけで使う）
        r.walkOverride = { [weak self] in self?.curWalk ?? HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)) }
        progress = second ? 0.5 : 0; canceling = false; rendering = true
        DispatchQueue.main.async { if !self.liveRun { HyperLabState.walkRendererGet?()?.stopForExport() }; self.step() }   // 書き出しが始まったら、走るのを止める
    }
    private var drawFails = 0
    /// 走っている間にアプリが一瞬止まると、そこだけ記録の動きが遅くなる。歩いた道のりの進みを前後でならして、ならした道のりの所の記録を使う
    private func smoothedTime(_ tq: Double) -> Double {
        guard gen == nil, frames.count > 8 else { return tq }
        func dist(_ t: Double) -> Double {
            var a = 0, b = frames.count - 1
            while b - a > 1 { let m = (a + b) / 2; if frames[m].t <= t { a = m } else { b = m } }
            let fa = frames[a], fb = frames[b], k = fb.t > fa.t ? max(0, min(1, (t - fa.t) / (fb.t - fa.t))) : 0
            return fa.walk.dist + (fb.walk.dist - fa.walk.dist) * k
        }
        return Self.smoothTime(tq, t0: frames[0].t, t1: frames[frames.count - 1].t, dist)
    }
    /// 時刻 tq の代わりに使う時刻：前後 0.25 秒の道のりの平均に着く時刻（止まっている間と、はじめ・終わりは、ほぼそのまま）
    static func smoothTime(_ tq: Double, t0: Double, t1: Double, _ dist: (Double) -> Double) -> Double {
        let w = min(0.25, tq - t0, t1 - tq)
        guard w > 0.01 else { return tq }
        let lo = tq - w, hi = tq + w
        guard dist(hi) - dist(lo) > 1e-4 else { return tq }
        let to = (dist(lo) + dist(tq - w / 2) + dist(tq) + dist(tq + w / 2) + dist(hi)) / 5
        var a = lo, b = hi
        for _ in 0..<18 { let m = (a + b) / 2; if dist(m) < to { a = m } else { b = m } }
        return (a + b) / 2
    }
    /// 書き出しの全部のコマ数を、記録の長さから決める
    private func countOut() {
        nOut = gen != nil ? genOut : max(1, Int((frames[frames.count - 1].t - frames[0].t) * 60))
        if fadeNow { genOut = nOut }
        if introN > 0 { nOut += gen != nil ? introN - Self.introEase - Self.genFI : introN - Self.introEase / 2 }
    }
    /// プロキシ：記録した音のうち、まだ渡していない分を書く側へ
    private func pullAudio() {
        let more = aq.sync { () -> [(b: AVAudioPCMBuffer, t: Double)] in let m = Array(audio[min(aFed, audio.count)...]); aFed = audio.count; return m }
        if !more.isEmpty { wq.async { self.aList += more } }
    }
    /// プロキシ：走り終わった。ここからはコマ数が決まって、ふつうの書き出しと同じに最後まで描く
    private func endLive(_ note0: String) {
        pullAudio(); wq.sync { aLive = false }
        liveRun = false; proxy = false
        countOut()
        let done = Double(iOut) / Double(max(1, nOut)) * 100
        note = note0 + String(format: "走り終わった時に %.0f%% 描けていました。\n", done)
        print(String(format: "プロキシ：走り終わった時 %d / %d コマ（%.0f%%）", iOut, nOut, done))
        HyperLabState.walkRendererGet?()?.stopForExport()
    }
    /// 次のコマへ。プロキシの間は、1 コマ描くのにかかった時間と同じだけ空ける（同じ糸で走る計算と画面に、半分は必ず回す。走りが優先）
    private func next() {
        if liveRun { DispatchQueue.main.asyncAfter(deadline: .now() + max(0.006, CACurrentMediaTime() - stepT)) { self.step() } } else { DispatchQueue.main.async { self.step() } }
    }
    private var stepT = 0.0, dropN = 0                                   // dropN：間に合わず飛ばしたコマの数
    private var curWalk = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)), busySince = 0.0

    /// 1 コマ描いて、次へ（アプリが止まらないように、1 コマずつ順に）
    private func step() {
        guard rendering, let r = r2, let s2 = st2, let cache, let ad = adaptor, let vi = vIn else { return }
        if canceling { abortRender(); return }
        if iOut >= nOut || wq.sync(execute: { failed }) { finishRender(); return }
        if liveRun {
            pullAudio()
            if frames[frames.count - 1].t - (frames[0].t + recFrame(iOut) / 60) < Self.liveMargin {   // 記録に追いついた：記録が伸びるのを待つ
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { self.step() }; return
            }
        }
        let busyNow = wq.sync { inFlight >= (liveRun ? 2 : 3) || !vi.isReadyForMoreMediaData }
        if busyNow {
            // 待っている間も、音を少し先まで渡す（絵と音は交互に書く決まりなので、音が来ないと絵も受け取ってもらえない）
            if gen != nil && Double(frames.count) < recFrame(iOut) + 600 { for _ in 0..<6 { genFrame() } }   // 決まった道から作る時：待っている間に先へ歩いて、音を作り足す
            if busySince == 0 { busySince = CACurrentMediaTime() }
            let waited = CACurrentMediaTime() - busySince
            feedAudio(upTo: Double(iOut) / 60 + 1.0 + waited)                // 待つほど先まで渡す（4K は絵が重くて、受け取りが遅れることがある）
            // 絵が受け取ってもらえないまま 6 秒待ったら、音はあきらめて絵だけ最後まで（音の待ち合わせで止まらないように）。重くて時間がかかっているだけの時は、音を切らない
            if waited > 6 && !vi.isReadyForMoreMediaData && gen == nil {          // 決まった道から作る時は、音は先まであるので、あきらめない
                wq.sync {
                    if !audioDone, let ai = aIn {
                        note += "絵の書き込みが止まっていたので、音は途中までです。\n"
                        NSLog("S3Walk 書き出し：音を打ち切り（絵 %d/%d・音 %d/%d・絵の受け取り %d・音の受け取り %d）", iOut, nOut, aIdx, aList.count, vi.isReadyForMoreMediaData ? 1 : 0, ai.isReadyForMoreMediaData ? 1 : 0)
                        print("音を打ち切り：絵 \(iOut)/\(nOut)・音 \(aIdx)/\(aList.count)・待った \(waited) 秒")
                        audioDone = true; ai.markAsFinished()
                    }
                }
            }
            if waited > (gen != nil ? 45 : 12) {
                NSLog("S3Walk 書き出し：止まった（絵 %d/%d・送っている途中 %d・絵の受け取り %d・状態 %d）", iOut, nOut, wq.sync { inFlight }, vi.isReadyForMoreMediaData ? 1 : 0, writer?.status.rawValue ?? -1)
                wq.sync { failed = true }; note += "書き出しが進まなくなったので、途中で止めました。\n"; finishRender(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { self.step() }; return
        }
        busySince = 0
        guard let pool = ad.pixelBufferPool else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { self.step() }; return }
        if gen != nil && pass != 2 { while Double(frames.count) < recFrame(iOut) + 40 && frames.count < genOut { genFrame() } }   // 0.6 秒先まで歩いておく（音を絵より先に渡すため）
        stepT = CACurrentMediaTime()
        let t0 = frames[0].t, tq = smoothedTime(t0 + recFrame(iOut) / 60)
        while jRec + 1 < frames.count - 1 && frames[jRec + 1].t <= tq { jRec += 1 }
        // 跡：記録をたどって、ふえた分を足す
        while appliedTo < jRec + 1 && appliedTo + 1 < frames.count {
            appliedTo += 1; let fr = frames[appliedTo]
            if fr.trailReset { trail = fr.trailAdd } else { trail += fr.trailAdd }
            if appliedTo == jRec { break }
        }
        let a = frames[jRec], b = frames[min(frames.count - 1, jRec + 1)]
        let k = b.t > a.t ? max(0, min(1, (tq - a.t) / (b.t - a.t))) : 0
        let genWipe = gen != nil && pass != 2 && !force && s2.lowView == 2 && s2.walkView && a.f[0] == 0      // 決まった道は記録したカメラがないので、ダイブ画面のカメラは書き出しの中で動かす
        let dive0 = diveRec
        apply(s2, a, b, k, camera: !force && !genWipe && pass != 2)
        diveRec = s2.diveT
        if !force && !genWipe && pass != 2 && iOut > 0 && abs(diveRec - dive0) > 0.2, let p = fullPrev, fullFade == 0 { fullOld = p; fullPrev = nil; fullFade = Self.colFadeN }   // ぱっと切りかえた：全部の絵をリゾルブ
        s2.exWipeNow = genWipe
        if genWipe {
            s2.diveOn = false; s2.diveT = 0; s2.diveFade = 0; s2.thirdK = s2.diveThird ? 1 : 0
            s2.chaseDistS = s2.chaseDist; s2.chasePitchS = s2.chasePitch; s2.chaseYawS = s2.chaseYaw
        }
        if force {
            // ダイブしていなくても三人称のダイブで。カメラ（オートカメラ・ショーカメラ）は、書き出しの中で 1/60 秒ずつ動かす
            s2.diveOn = true; s2.diveT = 1; s2.thirdK = 1; s2.diveFade = 0
            s2.chaseDistS = s2.chaseDist; s2.chasePitchS = s2.chasePitch; s2.chaseYawS = s2.chaseYaw
        }
        if pass == 2 { s2.diveOn = false; s2.diveT = 0; s2.diveFade = 0; s2.thirdK = 0 }   // 超球の本：走った時にダイブしていても、全体を見たまま
        if iOut < introN { let u = Double(iOut) / Double(introN); s2.diveT = min(s2.diveT, pow(u, 2.2)); s2.diveFade = 0 }   // ダイブイン：超球の全体から、加速しながら寄っていく（寄り切る時にブレーキをかけない）
        var w = a.walk
        func nl(_ x: SIMD4<Double>, _ y: SIMD4<Double>) -> SIMD4<Double> { let m = x + (y - x) * k, l = simd_length(m); return l > 1e-9 ? m / l : y }
        w.pos = nl(a.walk.pos, b.walk.pos); w.fwd = nl(a.walk.fwd, b.walk.fwd); w.vR = nl(a.walk.vR, b.walk.vR); w.vU = nl(a.walk.vU, b.walk.vU); w.vL = nl(a.walk.vL, b.walk.vL)
        if let ha = a.walk.head, let hb = b.walk.head { w.head = nl(ha, hb) }
        w.dist = a.walk.dist + (b.walk.dist - a.walk.dist) * k; w.fov = a.walk.fov + (b.walk.fov - a.walk.fov) * k
        w.trail = Array(trail.prefix(max(0, trail.count - a.trailTrim)))
        curWalk = w
        r.clockOverride = t0 + Double(iOut) / 60; r.domOverride = a.dom + (b.dom - a.dom) * k
        if force || genWipe { r.autoCamForTest(1.0 / 60) }
        // 描く
        var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        var cvt: CVMetalTexture?
        guard let pb, CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, outW, outH, 0, &cvt) == kCVReturnSuccess,
              let cv = cvt, let dst = CVMetalTextureGetTexture(cv), let cb = r.queue.makeCommandBuffer(), drawLayout(r, cb, dst, a) else {
            drawFails += 1
            if drawFails < 200 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { self.step() }; return }   // 重くて描けなかったコマは飛ばさず、描き直す
            NSLog("S3Walk 書き出し：コマ %d が描けず飛ばした", iOut); wq.sync { dropN += 1 }
            drawFails = 0; iOut += 1; next(); return
        }
        drawFails = 0
        let i = iOut
        wq.sync { inFlight += 1 }
        cb.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            _ = cv
            self.wq.async {
                self.inFlight -= 1
                guard self.writer?.status == .writing else { self.failed = true; return }
                // 受け取れるまで待つ（その間に音も先に渡す。音と絵は交互に書く決まり）。受け取れないままなら、そのコマは飛ばす
                let tf = Double(i) / 60
                var tries = 0
                while !vi.isReadyForMoreMediaData && tries < 15000 { self.pumpAudio(upTo: tf + 0.5); usleep(1000); tries += 1 }
                if vi.isReadyForMoreMediaData { if !ad.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60)) { self.failed = self.writer?.status != .writing } }
                else { self.dropN += 1; NSLog("S3Walk 書き出し：コマ %d を飛ばした", i) }
            }
        }
        cb.commit()
        feedAudio(upTo: Double(iOut) / 60 + 0.25)
        iOut += 1
        if iOut % 6 == 0 { progress = (Double(iOut) / Double(nOut) + (pass == 2 ? 1 : 0)) / (pass == 0 ? 1 : 2) }
        next()
    }
    /// 書き出しの 1 コマを、レイアウトに合わせて描く
    private func drawLayout(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) -> Bool {
        // 決まった道から作る時：当たったチェックポイントの光は、裏のさんぽの記録で（描く間だけ差しかえる。時刻は今の時計に合わせる）
        var keep: [(p: V4, t: Double, pole: Int)]? = nil
        if gen != nil {
            let up = ProcessInfo.processInfo.systemUptime, tq = recFrame(iOut) / 60
            keep = Journey.hitPulse; if pass == 0 { genHits.removeAll { tq - $0.t > 3 } }   // 2 本の時は 2 本目でも使うので残す
            Journey.hitPulse = genHits.filter { $0.t <= tq && tq - $0.t <= 3 }.map { ($0.p, up - (tq - $0.t), $0.pole) }
        }
        defer { if let k = keep { Journey.hitPulse = k } }
        guard drawLayout0(r, cb, dst, rec) else { return false }
        if !force && pass != 2, let g = glass {                             // 切りかえの前のコマを重ねながら薄くしていく（文字は重ねない）
            if fullFade > 0, let o = fullOld {
                let u = 1 - Double(fullFade) / Double(Self.colFadeN)
                g.blend(cb, o, into: dst, x: 0, y: 0, w: outW, h: outH, a: Float(1 - u * u * (3 - 2 * u)), fromX: lay == 1 && gen == nil ? colW : 0)   // 左の窓は黒を通って入れかわるので、重ねない
                fullFade -= 1; if fullFade == 0 { fullOld = nil }
            }
            if fullPrev == nil {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: outW, height: outH, mipmapped: false)
                d.usage = .shaderRead; d.storageMode = .private; fullPrev = r.device.makeTexture(descriptor: d)
            }
            if let p = fullPrev, let b = cb.makeBlitCommandEncoder() {
                b.copy(from: dst, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: outW, height: outH, depth: 1),
                       to: p, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                b.endEncoding()
            }
        }
        if withText { drawHUD(r, cb, dst, rec) }
        if gen != nil || fadeNow || introN > 0, let g = glass { let b = videoBright(iOut); if b < 0.999 { g.fade(cb, dst, 1 - b) } }   // 決まった道から作る時：フェードイン・アウト
        return true
    }
    /// 窓の仕切りの太さ（窓の幅 2048 の 5）を、書き出しの幅に合わせて
    private var splitGap: Int { max(2, outW / 400) }
    /// 超球の窓のレイアウトで、地図の場所にダイブ画面を出すコマか（「両方」で、ダイブしていない）
    private func wipeHere(_ s2: HyperLabState, _ rec: RecFrame) -> Bool { !force && s2.lowView == 2 && s2.walkView && (gen != nil ? s2.diveT == 0 : rec.both) }
    /// そのコマで、左の下を Y-W 地図にするか
    /// 左上の窓：画面に 3D の球を出していた間は、動画にも 3D の球（決まった道から作る時は、ダイブしていない間）
    private func ballHere(_ s2: HyperLabState, _ rec: RecFrame) -> Bool { !force && (gen != nil ? genBall && s2.diveT == 0 : rec.ball) }
    private func mapsHere(_ s2: HyperLabState, _ rec: RecFrame) -> Bool { s2.map2 && (force || (gen != nil ? s2.diveT > 0 : rec.pane)) }
    /// そのコマで、景色の場所を一人称のダイブ画面にするか
    private func firstHere(_ s2: HyperLabState, _ rec: RecFrame) -> Bool { !force && (gen != nil ? s2.diveT == 0 && s2.lowFirst : rec.first) }
    /// さんぽの景色、または一人称のダイブ画面の絵
    private func sceneTexture(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ s2: HyperLabState, _ rec: RecFrame, _ w: Int, _ h: Int) -> MTLTexture? {
        firstHere(s2, rec) ? r.wipeTexture(cb, w, h, first: true) : r.walkSceneTexture(cb, w, h, cam: rec.walkCam)
    }
    /// そのコマで、上にさんぽの景色・下にダイブ画面にするか
    private func swapHere(_ s2: HyperLabState, _ rec: RecFrame) -> Bool { wipeHere(s2, rec) && (gen != nil ? s2.lowSwap : rec.swap) }
    private func drawLayout0(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) -> Bool {
        if lay == 0 { return r.renderExport(cb, into: dst, w: outW, h: outH, withMap: mapOn) }
        // 超球の窓のレイアウト：左の列（幅は仕切りの比率）の上に地図、下にさんぽの景色、右の残りに大きくダイブ画面。すき間は窓の仕切りと同じ色
        guard let s2 = st2, let g = glass else { return false }
        let gap = splitGap
        let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX))), th = max(64, min(outH - 64, Int(Double(outH) * s2.splitAt(s2.splitK))))
        let bh = outH - th - gap, rw = outW - lw - gap
        colW = lw
        g.clear(cb, dst)
        // 左の列の中身が変わる時（ダイブ ⇄ ダイブなし）：前のコマの列を薄くしながら重ねて、スーッと（画面の切りかえと同じ長さ）
        let key = [wipeHere(s2, rec), swapHere(s2, rec), mapsHere(s2, rec), firstHere(s2, rec), gen != nil ? s2.diveT > 0 : rec.pane]
        let cover = !force && gen == nil ? s2.paneCover : 0                 // 左の窓が黒い間に入れかえるので、重ねない
        if let k0 = colKey, k0 != key, let prev = colPrev, cover == 0 { colOld = prev; colPrev = nil; colFade = Self.colFadeN }
        colKey = key
        if wipeHere(s2, rec) {                                             // 両方：左の列にダイブ画面とさんぽの景色
            let sw = swapHere(s2, rec), lowY = th + gap
            if let d = r.wipeTexture(cb, lw, sw ? bh : th) { g.copy(cb, d, into: dst, x: 0, y: sw ? lowY : 0, w: lw, h: sw ? bh : th) }
            if let walk = sceneTexture(r, cb, s2, rec, lw, sw ? th : bh) { g.copy(cb, walk, into: dst, x: 0, y: sw ? 0 : lowY, w: lw, h: sw ? th : bh) }
        } else {
            if let map = ballHere(s2, rec) ? r.ballTexture(cb, lw, th) : r.overviewTexture(cb, lw, th) { g.copy(cb, map, into: dst, x: 0, y: 0, w: lw, h: th) }
            if mapsHere(s2, rec) {                                         // 地図 2 枚：左下はY-W 地図
                if let m2 = r.overviewTexture(cb, lw, bh, motion: true) { g.copy(cb, m2, into: dst, x: 0, y: th + gap, w: lw, h: bh) }
            } else if let walk = sceneTexture(r, cb, s2, rec, lw, bh) { g.copy(cb, walk, into: dst, x: 0, y: th + gap, w: lw, h: bh) }
        }
        if colFade > 0, let o = colOld {
            let u = 1 - Double(colFade) / Double(Self.colFadeN)
            g.blend(cb, o, into: dst, x: 0, y: 0, w: lw, h: outH, a: Float(1 - u * u * (3 - 2 * u)))
            colFade -= 1; if colFade == 0 { colOld = nil }
        }
        if colPrev == nil || colPrev!.width != lw || colPrev!.height != outH {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: lw, height: outH, mipmapped: false)
            d.usage = .shaderRead; d.storageMode = .private; colPrev = r.device.makeTexture(descriptor: d)
        }
        if let prev = colPrev, let b = cb.makeBlitCommandEncoder() {
            b.copy(from: dst, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: lw, height: outH, depth: 1),
                   to: prev, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            b.endEncoding()
        }
        if cover > 0 { g.fade(cb, dst, Float(cover), w: lw) }
        if let dive = r.paneTexture(rw, outH), r.renderExport(cb, into: dive, w: rw, h: outH, withMap: false) { g.copy(cb, dive, into: dst, x: lw + gap, y: 0, w: rw, h: outH) }
        if !force && gen == nil && s2.paneSeeA > 0,                         // シースルー：左の列に右の絵の続きを重ねる（画面と同じ粗さ）
           let t = r.seeTexture(cb, w: max(16, lw / 2), h: max(16, outH / 2), rw: Double(rw), rh: Double(outH), lw: Double(lw), gap: Double(gap), b: s2.paneSeeB) {
            g.blend(cb, t, into: dst, x: 0, y: 0, w: lw, h: outH, a: Float(s2.paneSeeA))
        }
        return true
    }
    private static let colFadeN = 42                                     // 0.7 秒（画面の切りかえと同じ）
    private var colKey: [Bool]? = nil, colPrev: MTLTexture? = nil, colOld: MTLTexture? = nil, colFade = 0
    private var diveRec = 0.0, fullPrev: MTLTexture? = nil, fullOld: MTLTexture? = nil, fullFade = 0, colW = 0
    /// 書き出しの絵の上の文字：画面と同じ見た目・同じ割合の大きさで（画面の点 → 書き出しの画素は、右の画面の高さの比）
    private var hud: ExportHUD? = nil, hudCoordT = -9.0, hudLapT = -9.0, hudAngT = -9.0, hudCoords = "", hudLap = "", hudAngles = "", hudP: SIMD4<Double>? = nil, hudSpd = 0.0, hudPass = PassCaption(), hudNote = 0.0
    private func drawHUD(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) {
        guard let s2 = st2, let g = glass else { return }
        if hud == nil || hud!.w != outW || hud!.h != outH { hud = ExportHUD(r.device, outW, outH); hudCoordT = -9; hudLapT = -9; hudAngT = -9; hudP = nil; hudSpd = 0; hudPass = PassCaption(); hudNote = 0 }
        guard let hud else { return }
        let tq = Double(iOut) / 60, w = curWalk, en = s2.poleEN
        // 走行中の座標（1 秒に 10 回）・周回と角度の読み（1 秒に 2 回）：超球の窓の updateLive と同じ
        if tq - hudCoordT >= 0.1 || tq < hudCoordT {
            var cs = ""
            if s2.coordOn && s2.walk {
                let p = w.pos, dtc = tq - hudCoordT
                if let p0 = hudP, dtc > 0 && dtc < 1 { let v = acos(max(-1, min(1, simd_dot(p, p0)))) / dtc; hudSpd += (v - hudSpd) * 0.35 }
                hudP = p
                let ana = acos(max(-1, min(1, p.w))) * 180 / .pi
                var bk = 0, bd = 9.0
                for (k, m) in FIXED.enumerated() { let d = acos(max(-1, min(1, simd_dot(p, m.c)))); if d < bd { bd = d; bk = k } }
                let pn = en ? MapRenderer.poleNameToEN(MapRenderer.poleName(FIXED[bk])) : MapRenderer.poleName(FIXED[bk])
                func f(_ v: Double) -> String { String(format: "%@%.3f", v < 0 ? "−" : "+", abs(v)) }
                cs = "S³  x \(f(p.x))  y \(f(p.y))  z \(f(p.z))  w \(f(p.w))\n"
                   + (en ? String(format: "from Ana %6.1f°   near %@ %5.1f°   v %.2f rad/s", ana, pn, bd * 180 / .pi, hudSpd)
                         : String(format: "アナ極から %6.1f°   近い極 %@ %5.1f°   速さ %.2f rad/s", ana, pn, bd * 180 / .pi, hudSpd))
            } else { hudP = nil }
            hudCoords = cs; hudCoordT = tq
        }
        if tq - hudLapT >= 0.5 || tq < hudLapT {
            hudLapT = tq
            hudAngles = String(format: "前後（Y-W）%+.0f°　左右（X-W）%+.0f°　面内（X-Y）%+.0f°　Z-W %+.0f°", s2.pitch * 180 / .pi, -s2.roll * 180 / .pi, s2.yaw * 180 / .pi, s2.zw * 180 / .pi)
            hudLap = (s2.marksOn && w.marks.count >= 2) || (w.marks.count < 2 && s2.polesMode > 0) || w.lap > 1 ? (en ? "Lap \(w.lap)" : "\(w.lap) 周目") : ""
        }
        hud.begin()
        var dive = CGRect(x: 0, y: 0, width: outW, height: outH)
        if lay == 1 {
            let gap = splitGap
            let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX)))
            dive = CGRect(x: lw + gap, y: 0, width: outW - lw - gap, height: outH)
        }
        // 文字の大きさ：画面の右の窓の幅と、動画の中のダイブ画面の幅の比（窓の幅に対して、画面と同じ大きさ。動画は 16:9 で高さの比は使えない）
        let k = dive.width / CGFloat(max(200, HyperLabRenderer.liveRightW)), ks = k * CGFloat(s2.uiScale)
        if lay == 1 {
            let gap = splitGap
            let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX))), th = max(64, min(outH - 64, Int(Double(outH) * s2.splitAt(s2.splitK))))
            var map = CGRect(x: 0, y: 0, width: lw, height: th), walk = CGRect(x: 0, y: th + gap, width: lw, height: outH - th - gap)
            if swapHere(s2, rec) { swap(&map, &walk) }                     // 「両方」の上下入れかえ：map の場所がダイブ画面
            // さんぽの景色の極（色の点と名前。さんぽの窓と同じ）。カメラは記録したさんぽのカメラ
            let two = mapsHere(s2, rec), dark = !force && gen == nil && s2.paneCover > 0.5   // 黒い間は、左の窓の文字も出さない
            if !dark, !two, !firstHere(s2, rec), let wr = gen ?? HyperLabState.walkRendererGet?() {
                let saved = wr.cam; if let c = rec.walkCam { wr.cam = c }
                var ls = wr.poleLabels(aspect: Double(walk.width / max(1, walk.height)))
                wr.cam = saved
                let pen = HyperLabState.poleENNow
                if pen { for i in ls.indices { ls[i].name = MapRenderer.poleNameToEN(ls[i].name) } }
                hud.poles(ls, in: walk, k: k, serif: pen)
            }
            if !dark { hud.caption(wipeHere(s2, rec) ? "【ダイブ画面】今いる所のまわり" : ballHere(s2, rec) ? "【操作側】3D の球（リングを積む）" : "自分地図\n自分が真ん中\n進む向きが上", in: map, k: k) }
            // 赤玉・紫玉の解説：上の地図の下に
            hudNote += ((s2.noteOn && (force || s2.diveT > 0.3) && acos(min(1, abs(w.pos.w))) < 0.75 ? 1 : 0) - hudNote) * 0.06
            if hudNote > 0.01 && !dark {
                let u = map.width / 620
                hud.box(HLNoteLabel.text, font: ExportHUD.font(map.width * 0.042, .semibold, name: PassCaption.fontName), color: ExportHUD.rgb(0.93, 0.9, 1, hudNote), x: map.minX + 8 * u, y: map.maxY - 8 * u,
                        padH: 12 * u, padV: 7 * u, lineGap: 3 * u, bg: ExportHUD.rgb(0, 0, 0, 0.55 * hudNote), radius: 8 * u, alignBottom: true)
            }
            if !dark { hud.caption(two ? s2.ovCaption : firstHere(s2, rec) ? "【ダイブ 1 人称】自分の目で見る" : "【さんぽの景色】今いる所から見た S³（歩くのはさんぽの窓・コントローラーで）", in: walk, k: k) }
            hud.caption("【観察側】4D の超球（球殻を積む）　ドラッグで見る向き", in: dive, k: k)
        }
        // 走行中の座標（左上）・周回（右上）・角度の読み（左下）。ダイブ画面だけで左上に地図がある時は、座標は地図の下へ
        var cy = dive.minY + 40 * ks
        if lay == 0 && mapOn { cy = max(cy, CGFloat(outW / 60 + outH / 4) + 12 * ks) }
        var passY = cy
        if !hudCoords.isEmpty {
            let sz = hud.box(hudCoords, font: ExportHUD.font(10.5 * ks, .medium, mono: true), color: ExportHUD.rgb(0.62, 0.92, 1.0), x: dive.minX + 12 * ks, y: cy,
                    padH: 9 * ks, padV: 6 * ks, lineGap: 2 * ks, bg: ExportHUD.rgb(0, 0, 0, 0.42), stroke: ExportHUD.rgb(0.4, 0.85, 1.0, 0.35), strokeW: ks, radius: 6 * ks,
                    glow: ExportHUD.rgb(0.3, 0.8, 1.0, 0.7), glowR: 3 * ks)
            passY = cy + sz.height + 8 * ks
        }
        if s2.meterOn && s2.meterVideo && s2.walk && (s2.coaster || s2.meriK > 0) {
            hud.meter(s2.meterM, s2.coastG, top: s2.topK, cx: dive.midX, y: dive.maxY - 40 * ks, k: ks)
        }
        // 極の通過のテロップ：スマホで見ても読める大きさ（画面の高さの 3.6%）
        let pc = hudPass.update(w.pos, tq, r: s2.worldR)
        if s2.passOn && pc.a > 0.01 && iOut >= introN {                      // ダイブインの間は走り出していないので、通過は出さない
            let u = dive.height / 1080, a = pc.a, c = pc.col, tc = PassCaption.textCol(c)
            func col(_ x: Double) -> CGColor { ExportHUD.rgb(Double(c.x), Double(c.y), Double(c.z), x) }
            hud.box(pc.text, font: ExportHUD.font(dive.height * 0.036, .semibold, name: PassCaption.fontName), color: ExportHUD.rgb(Double(tc.x), Double(tc.y), Double(tc.z), a), x: dive.minX + 12 * ks, y: passY,
                    padH: 16 * u, padV: 8 * u, bg: ExportHUD.rgb(Double(c.x) * 0.2, Double(c.y) * 0.2, Double(c.z) * 0.2, 0.56 * a), stroke: col(0.9 * a), strokeW: 2 * u, radius: 9 * u, glow: col(0.8 * a), glowR: 8 * u)
        }
        if !hudLap.isEmpty {
            hud.box(hudLap, font: ExportHUD.font(14 * ks, .semibold, serif: true), color: ExportHUD.rgb(0.85, 1.0, 0.75), x: dive.maxX - 12 * ks, y: dive.minY + 40 * ks,
                    padH: 11 * ks, padV: 5 * ks, bg: ExportHUD.rgb(0, 0, 0, 0.5), stroke: ExportHUD.rgb(0.64, 1.0, 0.24, 0.8), strokeW: 1.5 * ks, capsule: true, alignRight: true)
        }
        if lay == 1 {
            hud.box(hudAngles, font: ExportHUD.font(10 * k, .regular, mono: true), color: ExportHUD.rgb(0.92, 0.94, 0.97), x: dive.minX + 8 * k, y: dive.maxY - 8 * k,
                    padH: 6 * k, padV: 6 * k, bg: ExportHUD.rgb(0, 0, 0, 0.5), radius: 8 * k, alignBottom: true)
        }
        if let t = hud.finish() { g.over(cb, t, dst) }
    }
    /// 記録した動き（前のコマ a と次のコマ b の間 k）を、書き出し用の状態へ
    private func apply(_ s: HyperLabState, _ a: RecFrame, _ b: RecFrame, _ k: Double, camera: Bool) {
        var v = [Double](repeating: 0, count: a.f.count)
        let cut = abs(b.f[0] - a.f[0]) > 0.2                               // ぱっと切りかえた所は、間の値を作らない
        for i in 0..<a.f.count {
            var y = b.f[i]; let x = a.f[i]
            if cut && i < 3 { v[i] = x; continue }
            if y - x > .pi { y -= 2 * .pi } else if x - y > .pi { y += 2 * .pi }   // 角度のつなぎ目（±π）をまたぐ時は、近い方へ
            v[i] = x + (y - x) * k
        }
        if camera {
            s.diveT = v[0]; s.diveFade = v[1]; s.thirdK = v[2]; s.chaseDistS = v[3]; s.chasePitchS = v[4]; s.chaseYawS = v[5]
            s.autoYaw = v[6]; s.autoPitch = v[7]; s.autoT = v[8]; s.autoDyn = v[9]; s.showDist = v[10]; s.showRoll = v[11]
            s.diveYawOff = v[12]; s.divePitchOff = v[13]
            s.showFrame = a.showFrame + (b.showFrame - a.showFrame) * k
        }
        s.cometSpd = v[14]; s.cometNear = v[15]
        s.zw = v[16]; s.pitch = v[17]; s.roll = v[18]; s.yaw = v[19]; s.viewYaw = v[20]; s.viewPitch = v[21]; s.viewDist = v[22]; s.camW = v[23]
        s.cutPos = v[24]; s.cutPhi = v[25]; s.airLift = v[26]; s.coastG = v[27]; s.meterM = v[28]; s.paneCover = v[29]; s.paneSeeB = v.count > 31 ? v[30] : 0; s.paneSeeA = v.count > 31 ? v[31] : 0; s.demoGlass = v.count > 32 ? v[32] : 1; s.fillOn = v.count > 33 && v[33] >= 0; s.fillA = v.count > 33 ? max(0, v[33]) : 1
        if v.count > 40 {                                                  // 詰める数・内側の球層・内核の演出・R の世界・ドリル（書き出しは急がないので、自動の内側の球層は R ＝ 1 の層の数まで全部）
            s.noSink = true; s.fillAuto = false
            s.fillCount = Int(v[34].rounded()); s.fillLayers = b.f[35] < 0 || a.f[35] < 0 ? max(2, s.layers) : Int(v[35].rounded())
            s.chaosOn = v[36] > 0.5; s.worldR = v[37]; s.drillOn = false; s.drillK = v[38]; s.drillS = v[39]; s.drillR0 = v[40]
        }
        if a.tun.count >= 15 {                                             // トンネル：記録した彗星の場所・断面・穴（場所だけ次のコマとの間をなめらかに）
            let t = a.tun, u = b.tun.count >= 15 ? b.tun : a.tun
            let base = TunnelBase(a: SIMD4(t[3], t[4], t[5], t[6]), b: SIMD4(t[7], t[8], t[9], t[10]), c: SIMD4(t[11], t[12], t[13], t[14]))
            func at(_ q: [Double], _ i: Int) -> SIMD4<Double> { base.c * q[i] + base.a * q[i + 1] + base.b * q[i + 2] }
            let xa = at(t, 0), xb = at(u, 0), jump = simd_length(xb - xa) > 0.3
            s.tunForce = true; s.tunBase = base; s.tunOverride = jump ? xa : xa + (xb - xa) * k
            var hs: [TunnelHole] = []; var i = 15
            while i + 4 < t.count { let d = SIMD4(t[i + 1], t[i + 2], t[i + 3], 0); hs.append(TunnelHole(r: t[i], dir: base.c * d.x + base.a * d.y + base.b * d.z, open: t[i + 4])); i += 5 }
            s.tunHoles = hs
        } else { s.tunForce = nil; s.tunOverride = nil }
        if a.run.count >= 8 {                                              // ダイブ画面の超球ラン：記録した金色の線
            let q = a.run; s.runLine = true
            s.runPathOverride = stride(from: 0, to: q.count - 3, by: 4).map { SIMD4(q[$0], q[$0 + 1], q[$0 + 2], q[$0 + 3]) }
        } else { s.runLine = false; s.runPathOverride = nil }
        s.cometDir = a.cometDir + (b.cometDir - a.cometDir) * k
        if s.layers != a.layers { s.layers = a.layers }; if s.lzw != a.lzw { s.lzw = a.lzw }
        s.version = a.version; if camera { s.diveOn = a.diveOn; s.diveDragging = a.dragging }; s.padHolding = a.padHolding
        s.paneDive = a.pane                                                // 左の窓が入れかわるまで、地図の見え方を保つ
    }
    /// 音：書き出した絵の時刻より少し先まで、記録した音を足す
    private func feedAudio(upTo tRel: Double) { wq.async { self.pumpAudio(upTo: tRel) } }
    /// （書く糸の上で）受け取れる間、記録した音を tRel 秒まで足す
    private func pumpAudio(upTo tRel: Double) {
        guard let ai = aIn, let t0 = audioT0 else { return }
        while aIdx < aList.count, ai.isReadyForMoreMediaData {
            let (b, t) = aList[aIdx]
            let tv = t - t0 + audioD                                        // 動画の中の時刻
            if tv > tRel { break }
            aIdx += 1
            if tv < 0 || (aIdx > introCount && tv < introSec) { continue }  // ダイブインの音と重なる所は、はじめの走りの音を飛ばす
            if fadeNow, pass != 2, let d = b.floatChannelData {            // 2 本目は 1 本目で弱めた音をそのまま使う                       // 自動の記録：音も絵と一緒にフェード
                let g = introN > 0 ? genTail(max(0, Int((t - t0) * 60))) : genBright(max(0, Int((t - t0) * 60))), inter = b.format.isInterleaved, ch = Int(b.format.channelCount), n = Int(b.frameLength) * (inter ? ch : 1)
                if g < 0.999 { for c in 0..<(inter ? 1 : ch) { for i in 0..<n { d[c][i] *= g } } }
            }
            if let sb = Self.sampleBuffer(b, CMTime(seconds: tv, preferredTimescale: CMTimeScale(b.format.sampleRate))) { ai.append(sb) }
        }
        // 記録した音を全部渡したら、音はおしまいと知らせる（そうしないと、音の先の絵を待たせてしまう）
        if aIdx >= aList.count && !audioDone && !aLive { print("音の終わり：\(aIdx) 個・絵 \(iOut)"); audioDone = true; ai.markAsFinished() }
    }
    private var audioT0: Double? = nil, audioDone = false, aLive = false   // aLive：音をまだ作っている（決まった道から作る時。全部渡しても終わりにしない）
    private func finishRender() {
        // 描いている途中のコマ（GPU で走っているもの）が全部書き終わるまで待ってから閉じる
        if wq.sync(execute: { inFlight }) > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { self.finishRender() }; return }
        let ok0 = writer != nil && !wq.sync(execute: { failed })
        wq.async {
            self.aLive = false
            self.pumpAudio(upTo: .infinity)
            self.vIn?.markAsFinished(); if !self.audioDone { self.audioDone = true; self.aIn?.markAsFinished() }
            guard let wr = self.writer else { return }
            let n = self.nOut, u = self.url, note = self.note
            wr.finishWriting {
                let ok = wr.status == .completed && ok0, err = wr.error?.localizedDescription ?? ""
                DispatchQueue.main.async {
                    if ok && self.pass == 1 { self.startSecond(u); return }
                    let first = self.firstURL
                    self.clearRender(); self.progress = 1
                    self.saved(ok, err, n, u, note, first: first)
                }
            }
        }
    }
    /// 2 本の書き出し：1 本目ができたら、同じ記録と同じ音で超球の本を描く
    private func startSecond(_ first: URL?) {
        firstURL = first; pass = 2
        writer = nil; vIn = nil; aIn = nil; adaptor = nil; r2 = nil; st2 = nil; hud = nil
        startRender(note)
        if writer == nil {                                                  // 始められなかった：1 本目は残す
            let m = message ?? ""
            clearRender(); lastURL = first
            message = (first.map { "ダイブの本は保存しました：\($0.path)\n" } ?? "") + m
        }
    }
    /// 書き出しの後かたづけ
    private func clearRender() {
        if liveRun { liveRun = false; proxy = false; recording = false; watch?.invalidate(); watch = nil }   // プロキシの途中で止まった：記録も終わり
        pass = 0; firstURL = nil; hud = nil
        writer = nil; vIn = nil; aIn = nil; adaptor = nil; r2 = nil; st2 = nil
        frames = []; lastRaw = []; aq.sync { audio = [] }; gen = nil; fadeNow = false; recFade = false; genTpl = nil; genSt = nil; genSnd?.stop(); genSnd = nil; genHits = []
        rendering = false
    }
    /// 書き出しを中止する：次のコマの前で止めて、途中までの動画は残さない
    private var canceling = false
    func cancelRender() { if rendering { canceling = true } }
    private func abortRender() {
        if wq.sync(execute: { inFlight }) > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { self.abortRender() }; return }
        wq.async {
            self.aLive = false; self.audioDone = true
            self.writer?.cancelWriting()
            let u = self.url
            DispatchQueue.main.async {
                if let u { try? FileManager.default.removeItem(at: u) }       // この書き出しで作り始めたファイルだけ
                let first = self.firstURL, n = self.nOut
                self.clearRender(); self.canceling = false; self.progress = 0
                self.message = "書き出しを中止しました"
                if let first { self.saved(true, "", n, first, "超球の本は中止しました。\n") }   // 書き終えたダイブの本は残す
            }
        }
    }
    private func saved(_ ok: Bool, _ err: String, _ n: Int, _ u: URL?, _ note: String, first: URL? = nil) {
        lastURL = ok ? u : first
        guard ok, let u else { message = (first.map { note + "ダイブの本は保存しました：\($0.path)\n" } ?? note) + "動画を書き出せませんでした：\(err)"; return }
        #if os(macOS)
        message = note + (dropN > 0 ? "\(dropN) コマ飛びました。\n" : "") + "動画を\(first == nil ? "" : " 2 本")作りました（16:9・\(outW)×\(outH)・60 コマ・\(n) コマ）：\(first.map { $0.path + "\n" } ?? "")\(u.path)"
        if !CommandLine.arguments.contains("--exporttest") { NSWorkspace.shared.activateFileViewerSelecting([first, u].compactMap { $0 }) }
        #else
        if let first { saved(true, "", n, first, note) }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.message = note + "写真に保存する許可がありません（設定 → 球面さんぽ → 写真）" }
                return
            }
            PHPhotoLibrary.shared().performChanges({ _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: u) }) { ok2, e in
                DispatchQueue.main.async {
                    self.message = note + (ok2 ? "動画を写真に保存しました（16:9・\(self.outW)×\(self.outH)・60 コマ）" : "写真に保存できませんでした：\(e?.localizedDescription ?? "")")
                    try? FileManager.default.removeItem(at: u)
                }
            }
        }
        #endif
    }
    /// 確かめ（--exporttest）：画面なしで、ダイブして走る動きと音を作って記録し、最後まで書き出す。書き出した動画の場所を返す（だめなら nil）
    // ---- 決まった道から作る：さんぽを裏で、決まった道に 1/60 秒ずつ歩かせながら、そのまま描く（記録はいらない。音はなし）----
    //   道の最初の場所から。黒からフェードインして（その間は止まっている）、1 秒かけて走り出し、1 周したらフェードアウト（その間も走り続ける）して終わり
    static let genFI = 90, genFO = 120, genEase = 60.0
    /// 裏のさんぽを、コマ i（0 から）の分だけ進める
    ///   当たったチェックポイント（光とチリン）は、今のさんぽの記録（Journey.hitPulse）に混ぜずに返す
    @discardableResult private static func genAdvance(_ sim: Renderer, _ i: Int) -> [(p: V4, t: Double, pole: Int)] {
        guard i > genFI else { return [] }
        let u = min(1, Double(i - genFI) / genEase)
        let keep = Journey.hitPulse; Journey.hitPulse = []
        sim.step(u * u * (3 - 2 * u) / 60)
        let got = Journey.hitPulse; Journey.hitPulse = keep
        return got
    }
    /// 1 周したか（道ごとに、道の進み具合で数える）
    struct LapWatch {
        var laps = 1                                                        // 何周するか（1 周・2 周）
        var lastFlowS = 0.0, lastIn = true, seenZero = false, wraps = 0, arrived = 0
        /// 今の所から 1 周するには、done に何周と渡すか（道の途中からでも）
        func lapsFromNow(_ r: Renderer) -> Int {
            switch r.pathMode {
            case .spiral: return r.path.lap + 1
            case .ring: return Int(r.path.T / (2 * Double.pi)) + 1
            case .half: return Int(r.turn.T / (2 * Double.pi)) + 1
            case .tour, .cube, .cell24: return r.turn.leg / max(1, r.turn.tv.count) + 1
            default: return 1
            }
        }
        /// 角で曲がって戻る道（ターンで角を丸める）：最後の辺に入ったら、出発点にいちばん近づいた所で 1 周とする
        func lastLeg(_ r: Renderer) -> Bool {
            switch r.pathMode {
            case .half: return r.turn.T >= 2 * Double.pi * Double(laps - 1) + 1.5 * Double.pi
            case .tour, .cube, .cell24: return r.turn.leg >= r.turn.tv.count * laps - 1
            case .custom: return r.cr.flow == nil && seenZero && arrived == laps - 1
            default: return false
            }
        }
        mutating func done(_ r: Renderer) -> Bool {
            switch r.pathMode {
            case .spiral: return r.path.lap >= laps
            case .ring: return r.path.T >= 2 * Double.pi * Double(laps) + 0.002
            case .half: return r.turn.T >= 2 * Double.pi * Double(laps)     // アナ極 → カタ極 → アナ極
            case .tour, .cube, .cell24: return r.turn.leg >= r.turn.tv.count * laps   // 頂点を全部めぐって、最初の頂点に戻った
            case .custom:
                if r.cr.flow != nil {                                       // 素通り：曲線を 1 周（巻き戻ったら）
                    defer { lastFlowS = r.cr.flowS; lastIn = r.cr.flowIn != nil }
                    if !lastIn && r.cr.flowIn == nil && r.cr.flowS < lastFlowS - 1e-9 { wraps += 1 }
                    return wraps >= laps
                }
                if r.cr.to == 0 { seenZero = true; return false }           // ① へ向かい、① に着いて次へ
                if seenZero { seenZero = false; arrived += 1 }
                return arrived >= laps
            default: return true                                            // 道が終わった（1 点だけの道など）
            }
        }
    }
    /// 裏で歩くさんぽを作って、道の最初の場所から歩き出させる
    private func makeSim(_ dev: MTLDevice, _ set: Settings) -> (Renderer?, String?) {
        guard let sim = Renderer(device: dev) else { return (nil, "書き出しの準備ができませんでした") }
        sim.set = set; sim.set.gamepad = false; sim.set.haptics = false; sim.say = nil   // コントローラーを触っても、裏のさんぽは動かさない（震えもなし）
        let m = PathMode(rawValue: genPath) ?? .tour
        if m == .custom {
            guard let rt = RouteStore.shared.routes.first(where: { $0.id.uuidString == genRoute }) ?? RouteStore.shared.routes.first(where: { !$0.pts.isEmpty }),
                  let q = rt.pts.first(where: { $0.p.count == 4 }) else { return (nil, "自分の道に点がありません") }
            sim.cam.w.p = simd_normalize(SIMD4(q.p[0], q.p[1], q.p[2], q.p[3])); orthoFrame(&sim.cam.w)   // ① から出発
            sim.startCustom(rt)
        } else { sim.startPath(m) }
        guard sim.pathMode != .none else { return (nil, "この道は歩き出せませんでした") }
        if let st = HyperLabRenderer.liveMain?.st { sim.coastOn = st.coaster; sim.meriK = st.meriK; sim.topK = st.topK }   // 周の長さの見積もりも、動画と同じ速さの変化で
        return (sim, nil)
    }
    fileprivate(set) var genOut = 0
    /// 別のさんぽで歩いてみて、終わるコマ（1 周か、決めた長さ）を知る。info：道のりと、出発点との差（確かめ用）
    private func measure(_ dev: MTLDevice, _ set: Settings) -> ((end: Int, found: Bool, info: String, dist: Double)?, String?) {
        let (meas, e1) = makeSim(dev, set)
        guard let meas else { return (nil, e1) }
        let p0 = meas.cam.w.p
        let cap = Self.genFI + (genSeconds > 0 ? Int(genSeconds * 60) - Self.genFI - Self.genFO : 20 * 3600)
        var lw = LapWatch(); lw.laps = genSeconds < 0 ? 2 : 1
        var end = max(Self.genFI + 60, cap), found = false, prevD = 9.0
        var i = Self.genFI + 1
        while i <= cap {
            Self.genAdvance(meas, i)
            if meas.pathMode == .none || (genSeconds <= 0 && lw.done(meas)) { end = i; found = true; break }
            if genSeconds <= 0 && lw.lastLeg(meas) {
                let d = acos(max(-1, min(1, simd_dot(p0, meas.cam.w.p))))
                if d > prevD && prevD < 0.6 { end = i - 1; found = true; break }   // いちばん近づいたコマ
                prevD = d
            }
            i += 1
        }
        let info = String(format: "%d コマ・道のり %.3f・出発点との差 %.4f", end, meas.journey.dist, acos(max(-1, min(1, simd_dot(p0, meas.cam.w.p)))))
        return ((end, found, info, meas.journey.dist), nil)
    }
    /// 1 周の道のり（らくらく書き出し：周数をこの道のりに直して、小数の周でも止める）
    func lapDistance(_ dev: MTLDevice, _ set: Settings) -> (Double?, String?) {
        let keep = genSeconds; genSeconds = 0; defer { genSeconds = keep }
        let (m, e) = measure(dev, set)
        guard let m else { return (nil, e) }
        return m.found && m.dist > 1e-6 ? (m.dist, nil) : (nil, "この道の 1 周を測れませんでした")
    }
    /// 小数の周数まで走るコマを求める（あとから書き出す時）。0 なら使わない
    var genLaps = 0.0
    private func lapsEnd(_ dev: MTLDevice, _ set: Settings, _ L: Double) -> Int? {
        guard let m = makeSim(dev, set).0 else { return nil }
        var i = Self.genFI + 1
        while i < Self.genFI + 20 * 3600 {
            Self.genAdvance(m, i)
            if m.pathMode == .none || m.journey.dist >= L * genLaps { return i }
            i += 1
        }
        return nil
    }
    func exportRoute() {
        guard !recording, !rendering else { return }
        guard let live = HyperLabRenderer.liveMain, let tpl = live.recordFrame(), let wr = HyperLabState.walkRendererGet?() else {
            message = "超球の窓とさんぽが見つかりませんでした"; return }
        // 先に別のさんぽで歩いてみて、1 周（または決めた長さ）が何コマかを知る
        let (mm, e1) = measure(live.device, wr.set)
        guard let mm else { message = e1; return }
        var (end, found) = (mm.end, mm.found)
        if genLaps > 0, mm.dist > 1e-6, let e = lapsEnd(live.device, wr.set, mm.dist) { end = e; found = true }
        let (sim, e2) = makeSim(live.device, wr.set)
        guard let sim else { message = e2; return }
        genOut = end + Self.genFO
        gen = sim; genTpl = tpl; genCs = nil; genSpd = 0; genFreed = 0; appliedTo = -1; genLW = LapWatch(); genLapN = 1
        frames = []; lastRaw = []; aq.sync { audio = [] }
        live.st.saveIfChanged()
        let gs = HyperLabState(); gs.copyMotion(from: live.st); genSt = gs
        sim.coastOn = live.st.coaster; sim.meriK = live.st.meriK; sim.topK = live.st.topK; gsAir = AirSim()
        genSnd = nil; genAFmt = nil; gsPos = nil; gsPass = PolePass(); gsFwd = nil; gsTurn = 0; gsSpeed = 0; gsWobT = -9; gsIceT = -9; genHits = []
        if live.st.soundOn {                                                // 音：超球の窓で音を入れている時は、同じ音を作って入れる
            let snd = HyperSound(); snd.spatial = live.st.soundSpatial; gsVol = live.st.soundVol; gsPlace = live.st.soundPlace; gsLayerOn = live.st.soundLayer; gsRailK = live.st.soundRail; gsSong = live.st.soundSong; gsWind = live.st.soundWind; gsBass = live.st.soundBass; gsRough = live.st.soundRough
            if let f = snd.startOffline() { genSnd = snd; genAFmt = f }
        }
        genFrame(); genFrame()
        startRender(genSeconds <= 0 && !found ? "周回が 20 分で終わらなかったので、20 分で切りました。\n" : "")
    }
    /// 書き出しのコマ i の明るさ（フェードイン・フェードアウト）
    private func genBright(_ i: Int) -> Float {
        func ss(_ x: Double) -> Double { let u = max(0, min(1, x)); return u * u * (3 - 2 * u) }
        return Float(ss(Double(i) / Double(Self.genFI)) * ss(Double(genOut - 1 - i) / Double(Self.genFO)))
    }
    /// 記録のコマ i の音の大きさ（フェードアウトだけ。ダイブインの時は、はじめの音を弱めない）
    private func genTail(_ i: Int) -> Float {
        let u = max(0, min(1, Double(genOut - 1 - i) / Double(Self.genFO)))
        return Float(u * u * (3 - 2 * u))
    }
    /// 動画のコマ i の明るさ（ダイブインの時は、始めのフェードインが超球の全体になる）
    private func videoBright(_ i: Int) -> Float {
        func ss(_ x: Double) -> Double { let u = max(0, min(1, x)); return u * u * (3 - 2 * u) }
        return Float(ss(Double(i) / Double(Self.genFI)) * ss(Double(nOut - 1 - i) / Double(Self.genFO)))
    }
    /// 裏のさんぽを 1/60 秒進めて、1 コマ分を覚える
    private func genFrame() {
        guard pass != 2, let sim = gen, var f = genTpl else { return }
        let dt = 1.0 / 60
        let hits = Self.genAdvance(sim, frames.count)
        sim.frameCount += 1
        // 極で周回を数えられない道（螺旋・回る輪・半周・辺めぐり）は、1 周ごとに周回を進める（チェックをリセット。「1 周で跡を消す」も効かせる）
        if [.spiral, .ring, .half, .cube, .cell24].contains(sim.pathMode) && frames.count > Self.genFI {
            genLW.laps = genLapN
            if genLW.done(sim) {
                genLapN += 1; sim.journey.lap += 1; sim.journey.polesHit = []; sim.journey.marksHit = []
                if Journey.lapClearsTrail { sim.journey.trail = [sim.cam.w.p]; sim.journey.trail2 = [sim.journey.w2.p]; sim.journey.foot = []; sim.journey.foot2 = [] }
            }
        }                                                 // 予定の道は 1 コマに 1 回だけ作り直す決まり（コマを数えないと、最初の道のままになる）
        let w = sim.hyperWalk(), t = Double(frames.count) * dt
        if let p0 = genCs { let d = simd_length(w.pos - p0); genSpd += (min(1, ((d > 0.5 ? 0 : d / dt) / 1.4).squareRoot() * (st2?.feelK ?? 1)) - genSpd) * (1 - exp(-dt * 3)) }   // 彗星の速さ（超球の窓と同じ決め方）
        genCs = w.pos
        for h in hits { genHits.append((h.p, t, h.pole)) }
        if let gs = genSt {                                                 // 超球の向き：超球の窓と同じく、自動で回す・自分（裏のさんぽ）を追う
            gs.tick(dt); gs.tickCut(dt); gs.tickFollow(dt, walk: w)
            f.f[16] = gs.zw; f.f[17] = gs.pitch; f.f[18] = gs.roll; f.f[19] = gs.yaw; f.f[20] = gs.viewYaw; f.f[21] = gs.viewPitch; f.f[24] = gs.cutPos; f.version = gs.version
        }
        f.t = t; f.dom = genSound(w, t, hits) ?? t / 4; f.f[14] = genSpd; f.f[26] = Double(gsAir.lift); f.f[27] = max(-1, min(1, sim.coastA)); f.f[28] = sim.coastM; f.walkCam = sim.cam
        var wk = w; wk.trail = []; f.walk = wk; f.trailTrim = 0
        let raw = w.trail
        if !lastRaw.isEmpty, raw.count >= lastRaw.count, raw[lastRaw.count - 1] == lastRaw[lastRaw.count - 1] {
            f.trailAdd = Array(raw[lastRaw.count...]); f.trailReset = false
        } else { f.trailAdd = raw; f.trailReset = true }
        lastRaw = raw
        frames.append(f)
        while pass == 0 && genFreed < appliedTo - 1 { frames[genFreed].trailAdd = []; genFreed += 1 }   // 描き終えたコマの跡は手放す（長い道でもメモリがふえない）
    }
    /// 決まった道から作る時の音を 1/60 秒ぶん作る（超球の窓の tickSound と同じ決め方）。返すのは矢印の光の拍（音のうなり 6 つで 1 回）
    private func genSound(_ w: HyperLabState.Walk, _ t: Double, _ hits: [(p: V4, t: Double, pole: Int)]) -> Double? {
        guard let snd = genSnd, let fmt = genAFmt else { return nil }
        if frames.count >= genOut { if rendering { wq.async { self.aLive = false; self.pumpAudio(upTo: .infinity) } }; return nil }   // 絵の終わりで音も終わり（全部渡したら、おしまいと知らせる）
        let dt = 1.0 / 60
        var sp = 0.0, tr = 0.0
        if let p0 = gsPos { let d = simd_length(w.pos - p0); sp = d > 0.5 ? 0 : d / dt }
        gsPos = w.pos
        let hd = w.head ?? w.fwd
        var sw = 0.0
        if let f0 = gsFwd, simd_length(w.vR) > 0.5 { let df0 = hd - f0, df = df0 - w.pos * simd_dot(df0, w.pos); tr = simd_length(df) > 0.5 ? 0 : simd_dot(df, w.vR) / dt; sw = simd_length(df) > 0.5 ? 0 : simd_length(df) / dt }
        gsFwd = hd
        gsSwing += (sw - gsSwing) * (1 - exp(-dt * 6)); gsTurn += (tr - gsTurn) * (1 - exp(-dt * 4)); gsSpeed += (sp - gsSpeed) * (1 - exp(-dt * 6))
        let trn = max(-1, min(1, gsTurn / 1.2)), feel = (gsSpeed / 1.4).squareRoot() * (st2?.feelK ?? 1), spd01 = min(1, feel)
        let zoom = HyperLabRenderer.diveEase(forceDive ? 1 : (st2?.diveT ?? 1)).1
        if t - gsWobT > 1.2 && spd01 > 0.25 && (abs(trn) > 0.55 || Double.random(in: 0..<1) < dt * 0.12 * spd01) { snd.shellPass(); gsWobT = t }
        if zoom > 0.5 && t - gsIceT > 1.8 && spd01 > 0.3 && abs(trn) > 0.25 && Double.random(in: 0..<1) < dt * 0.9 * abs(trn) { snd.icePop(); gsIceT = t }
        let railGap = max(1e-4, HyperLabRenderer.railGap > 0 ? HyperLabRenderer.railGap : 0.03), railN = Int(w.dist / railGap)
        if zoom > 0.4 && railN > gsRailN && railN - gsRailN <= 4 { snd.railTick() }
        gsRailN = railN
        let farK = st2?.soundFarK ?? 0.2, farOn = st2?.soundFar ?? false      // ダイブの外でも小さく鳴らす（画面の音と同じ）
        snd.update(speed: feel, zoom: farOn ? 1 : zoom, turn: trn, swing: gsSwing / 1.2, near: st2?.cometNear ?? 0.5, volume: gsVol * Double(genBright(frames.count)), fade: farOn ? farK + (1 - farK) * zoom : 1)   // 音もフェードイン・アウト
        let aim = HyperSound.poleAim(w.pos, w.head ?? w.fwd)
        gsAim += (aim - gsAim) * (1 - exp(-dt * 3))
        if st2?.airOn ?? false { gsAir.tick(speed: Float(min(1, genSpd + 0.5 * gsFlyA)), cross: Float(max(-1, min(1, trn + 0.8 * gsFlyA * gsFlySide)))); snd.setAir(gsAir.gust); snd.setScan(gsAir.ring()) } else { snd.setAir(1) }
        gsRush = HyperSound.rushStep(gsRush, swing: gsSwing / 1.2, speed: spd01, aim: gsAim, dt: dt)
        snd.tune(height: w.pos.w, place: gsPlace, bass: gsBass, rough: gsRough, phones: st2?.soundPhones ?? false, rush: gsRush * (0.75 + 0.5 * gsAim) * (st2?.soundRush ?? 1), song: gsSong, wind: gsWind, rail: gsRailK)
        let ly = HyperLabRenderer.layerIndex(w.pos.w, st2?.layers ?? 10)
        if let l0 = gsLayer, l0 != ly, spd01 > 0.1, gsLayerOn { snd.layerPass() }
        gsLayer = ly
        var d = st2?.cometDir ?? SIMD3<Double>(0, 0, -1); d.x -= 0.7 * trn                 // 彗星の方向から（少し前のコマの向き）
        let dl = simd_length(d); if dl > 1e-6 { d /= dl }
        snd.setPosition(SIMD3<Float>(d * 1.5))
        var flyA = 0.0, flySide = 0.0
        if st2?.dopplerOn ?? false, simd_length(w.vR) > 0.5 {
            let f = HyperSound.flyPass(w.pos, head: w.head ?? w.fwd, right: w.vR, up: w.vU, feel: spd01)
            snd.setFly(hz: f.hz, amp: f.amp * (st2?.dopK ?? 1), at: f.at); flyA = f.amp; flySide = Double(f.at.x)
        } else { snd.setFly(hz: 200, amp: 0, at: SIMD3(0, 0, -1.5)) }
        gsFlyA = flyA; gsFlySide = flySide
        for h in hits where h.pole < 0 { snd.chime(pole: h.pole) }            // 目印のチリン
        if let k = gsPass.update(w.pos) { snd.chime(pole: k) }                  // 極のチリン：テロップと同じ瞬間に
        guard let b = snd.renderOffline(Int((fmt.sampleRate * dt).rounded())) else { return nil }
        if rendering { wq.async { self.aList.append((b, t)) } } else { aq.sync { audio.append((b, t)) } }   // 書き出しが始まる前の分は、始める時に渡す
        let bc = snd.beatClock()
        return bc.rate > 0.05 ? bc.cyc / 6 : nil
    }
    /// 確かめ（--exporttest --arm）：待機して 1 秒止まる → 4 秒走る → 止まる。走った所から始まって、止まってから 2 秒あまりで終わるか
    static func selfTestArm() -> URL? {
        let ex = VideoExport.shared
        let st = HyperLabState(); st.walk = true
        guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return nil }
        var w = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1))
        r.walkOverride = { w }
        HyperLabRenderer.liveMain = r
        ex.layout = 0; ex.forceDive = true; ex.uhd = false; ex.keepLast = false; ex.autoRec = true; ex.quality = 0
        ex.toggle()
        var a = 0.0, trail: [SIMD4<Double>] = [], n = 0
        let t0 = CACurrentMediaTime()
        for i in 0..<300 {
            let t = Double(i) / 30
            if t > 1 && !ex.recording && !ex.armed { break }
            if t >= 1 && t < 5 { a += 0.3 / 30 }
            let p = SIMD4(sin(a), 0, 0, cos(a)), f = SIMD4(cos(a), 0, 0, -sin(a)); if t >= 1 && t < 5 { trail.append(p) }
            w = HyperLabState.Walk(trail: trail, pos: p, head: f, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 1, 0), vL: f, dist: a)
            HyperLabState.walkSource = { w }
            if var fr = r.recordFrame() { fr.t = t0 + t; ex.capture(fr) }
            if ex.recording { n = ex.frames.count }
            RunLoop.main.run(until: Date().addingTimeInterval(0.0005))
        }
        print("自動の記録：\(n) コマぶん覚えた（30 コマで 4 秒走って、止まって 2.3 秒なので 190 コマくらいのはず）")
        let limit = Date().addingTimeInterval(120)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")")
        return ex.lastURL
    }
    /// 確かめ（--exporttest --ring）：直前 1 分の覚え方。走る → 止まる（含めない）→ 走る、途中で遠くへ飛ぶ（そこから先だけ）を作って、直前 1 分を書き出す
    static func selfTestRing() -> URL? {
        let ex = VideoExport.shared
        let st = HyperLabState(); st.walk = true; st.planOn = true
        guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return nil }
        var w = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1))
        r.walkOverride = { w }
        HyperLabRenderer.liveMain = r
        ex.keepLast = true; ex.layout = 0; ex.forceDive = true; ex.uhd = false
        var trail: [SIMD4<Double>] = [], a = 0.0, base = SIMD4<Double>(0, 0, 0, 1)
        let t0 = CACurrentMediaTime()
        for i in 0..<240 {                                                  // 30 コマで 8 秒：0〜2 秒 走る・2〜3 秒 止まる・3 秒で遠くへ飛ぶ・3〜8 秒 走る
            let t = Double(i) / 30
            if t >= 3 && t - 1.0 / 30 < 3 { base = SIMD4(1, 0, 0, 0); trail = []; a = 0 }   // 遠くへ飛ぶ（リセット）
            if !(t >= 2 && t < 3) { a += 0.3 / 30 }
            let p = simd_normalize(base * cos(a) + SIMD4(0, 0, 1, 0) * sin(a)), f = simd_normalize(SIMD4(0, 0, 1, 0) * cos(a) - base * sin(a))
            if !(t >= 2 && t < 3) { trail.append(p) }
            w = HyperLabState.Walk(trail: trail, pos: p, head: f, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 0, 1), vL: f,
                                   plan: (0..<60).map { k in let b = a + Double(k) * 0.02; return simd_normalize(base * cos(b) + SIMD4(0, 0, 1, 0) * sin(b)) }, dist: a)
            HyperLabState.walkSource = { w }
            if var fr = r.recordFrame() {
                fr.t = t0 + t; ex.ringCapture(fr)
                fr.t += 1.0 / 60; fr.trailAdd = []                         // 歩く計算より画面のコマが多い時：まだ進んでいないコマ
                var g = fr; g.trailAdd = trail; ex.ringCapture(g)
            }
        }
        do {
            var sp: [Double] = []
            for (a, b) in zip(ex.ringFrames, ex.ringFrames.dropFirst()) where b.t > a.t { sp.append(acos(max(-1, min(1, simd_dot(a.walk.pos, b.walk.pos)))) / (b.t - a.t)) }
            let so = sp.sorted(); if !so.isEmpty { print(String(format: "コマの速さのそろい：最小 %.3f・中央 %.3f・最大 %.3f rad/s", so[0], so[so.count / 2], so[so.count - 1])) }
        }
        print(String(format: "直前の走り：%.2f 秒ぶん・%d コマ（飛んだあとの 5 秒だけのはず）", ex.ringSeconds, ex.ringFrames.count))
        ex.exportLast()
        let limit = Date().addingTimeInterval(600)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")")
        return ex.lastURL
    }
    /// 確かめ（--exporttest --route）：極めぐりを 8 秒、超球の窓のレイアウトで（さんぽの景色も裏のさんぽで描く）
    static func selfTestRoute(seconds seconds0: Double = 0) -> URL? {
        let seconds = CommandLine.arguments.contains("--2laps") ? -1 : seconds0
        let ex = VideoExport.shared
        let st = HyperLabState(); st.walk = true; st.planOn = true
        guard let r = HyperLabRenderer(side: .right, state: st, view: nil), let wr = Renderer(device: r.device) else { return nil }
        let userset = CommandLine.arguments.contains("--userset")           // --userset：覚えた設定で（ユーザーと同じ条件で確かめる）
        if userset { Store.restore(wr) } else { wr.set = .plain }
        HyperLabState.walkRendererGet = { wr }; HyperLabState.walkSource = { wr.hyperWalk() }; HyperLabState.planWanted = true
        HyperLabRenderer.liveMain = r
        st.soundOn = true; st.followOn = true; st.coordOn = true            // 地図が自分を追って回るか・文字が入るかも見る
        if CommandLine.arguments.contains("--rail") { st.railOn = true; HyperLabState.railWanted = true }
        if CommandLine.arguments.contains("--cur0") { st.cursor = 0; st.ovCursor = 0 }
        if CommandLine.arguments.contains("--glintlog") { HyperLabRenderer.glintLog = true }
        if let i = CommandLine.arguments.firstIndex(of: "--quality") { ex.quality = Int(CommandLine.arguments[i + 1]) ?? 1 }
        ex.dual = CommandLine.arguments.contains("--dual")
        ex.diveIn = CommandLine.arguments.contains("--divein"); ex.uhd = CommandLine.arguments.contains("--4k"); ex.layout = 1; ex.forceDive = !CommandLine.arguments.contains("--both"); ex.genPath = PathMode.tour.rawValue; ex.genSeconds = seconds
        if !userset { wr.set.routeStart = CommandLine.arguments.contains("--slow") ? 1 : CommandLine.arguments.contains("--4k") ? 1.5 : 6 }
        for (m, n) in [(PathMode.tour, "極めぐり"), (.spiral, "螺旋"), (.ring, "回る輪"), (.half, "半周"), (.cube, "超立方体"), (.cell24, "二十四胞体")] {
            ex.genPath = m.rawValue
            print("1 周の確かめ・\(n)：\(ex.measure(r.device, wr.set).0?.info ?? "だめ")")
        }
        for (tf, ts) in [(true, false), (false, true)] {
            var s2 = wr.set; s2.tourFlow = tf; s2.tourShow = ts; ex.genPath = PathMode.tour.rawValue
            print("1 周の確かめ・極めぐり（\(tf ? "極を踏む" : "ショー")）：\(ex.measure(r.device, s2).0?.info ?? "だめ")")
        }
        let rt = CustomRoute(name: "確かめ", pts: [RoutePoint(p: [1, 0, 0, 0], name: "a"), RoutePoint(p: [0, 1, 0, 0], name: "b"), RoutePoint(p: [0, 0, 1, 0], name: "c")])
        RouteStore.shared.routes.append(rt); ex.genPath = PathMode.custom.rawValue; ex.genRoute = rt.id.uuidString
        for fl in [false, true] { var s2 = wr.set; s2.routeFlow = fl; print("1 周の確かめ・自分の道（\(fl ? "素通り" : "点で曲がる")）：\(ex.measure(r.device, s2).0?.info ?? "だめ")") }
        defer { RouteStore.shared.routes.removeAll { $0.id == rt.id } }
        ex.genPath = PathMode.tour.rawValue
        ex.genSeconds = -1; print("2 周の確かめ・極めぐり：\(ex.measure(r.device, wr.set).0?.info ?? "だめ")")
        for fl in [false, true] { var s2 = wr.set; s2.routeFlow = fl; ex.genPath = PathMode.custom.rawValue; print("2 周の確かめ・自分の道（\(fl ? "素通り" : "点で曲がる")）：\(ex.measure(r.device, s2).0?.info ?? "だめ")") }
        ex.genSeconds = seconds; ex.genPath = PathMode.tour.rawValue
        if CommandLine.arguments.contains("--lapdebug") {
            func trial(_ name: String, _ m: PathMode, _ set: Settings) {
                ex.genPath = m.rawValue
                guard let sim = ex.makeSim(r.device, set).0 else { print(name, "歩けない"); return }
                var hits: [String] = [], lap0 = 1, tr = 0, lw = LapWatch(); lw.laps = 2
                for i in 1...(40 * 3600) {
                    let hs = genAdvance(sim, i); if !hs.isEmpty { hits.append(contentsOf: hs.map { "\($0.pole)" }) }
                    if sim.journey.lap != lap0 { lap0 = sim.journey.lap; hits.append("｜"); tr = sim.journey.trail.count }
                    if sim.pathMode == .none || lw.done(sim) { break }
                }
                print("\(name)：周 \(sim.journey.lap)・周が変わった時の跡 \(tr) 点・チャイム \(hits.joined(separator: " "))")
            }
            var sf = wr.set; sf.tourFlow = true; sf.tourShow = false
            trial("極めぐり", .tour, wr.set); trial("極を踏む", .tour, sf)
            var rt2 = CustomRoute(name: "確かめ 2", pts: [0, 2, 4].map { RoutePoint(p: [RouteStore.poles[$0].1[0], RouteStore.poles[$0].1[1], RouteStore.poles[$0].1[2], RouteStore.poles[$0].1[3]], name: RouteStore.poles[$0].0) })
            rt2.name = "確かめ 2"; RouteStore.shared.routes.append(rt2); ex.genRoute = rt2.id.uuidString
            trial("極だけの自分の道", .custom, wr.set)
            var s3 = wr.set; s3.routeFlow = true; trial("極だけの自分の道（素通り）", .custom, s3)
            RouteStore.shared.routes.removeAll { $0.id == rt2.id }
            return nil
        }
        if CommandLine.arguments.contains("--twice") {                      // 続けて 2 回（2 回目だけ起きることを見る）
            ex.exportRoute()
            let l0 = Date().addingTimeInterval(600)
            while ex.rendering && Date() < l0 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            print("1 回目：\(ex.lastURL?.path ?? "なし")")
        }
        ex.exportRoute()
        if CommandLine.arguments.contains("--cancel") { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { ex.cancelRender() } }   // 確かめ：書き出しを途中で中止
        let limit = Date().addingTimeInterval(600)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("1 周：\(ex.genOut) コマ（フェードイン \(genFI)・アウト \(genFO)）")
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")・さんぽ本体は動いていない：\(wr.pathMode == .none && wr.journey.dist == 0)")
        return ex.lastURL
    }
    static func selfTest(uhd: Bool, seconds seconds0: Double, layout: Int = 0, force: Bool = false) -> URL? {
        let ex = VideoExport.shared
        let live = CommandLine.arguments.contains("--proxy"), seconds = live ? 12 : seconds0   // --proxy：走りと同じ速さで記録しながら描く
        ex.proxy = live
        let st = HyperLabState(); st.walk = true; st.diveOn = true; st.diveT = 1; st.diveThird = true; st.thirdK = 1; st.planOn = true; st.paneDive = true
        guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return nil }
        var w = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1))
        r.walkOverride = { w }
        HyperLabRenderer.liveMain = r
        ex.uhd = uhd; ex.withMap = true; ex.layout = layout; ex.forceDive = force; ex.dual = CommandLine.arguments.contains("--dual")
        if force { st.diveOn = false; st.diveT = 0; st.thirdK = 0 }                // 記録の間はダイブしていない（書き出しでダイブにする）
        ex.frames = []; ex.lastRaw = []; ex.recording = true
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        ex.audioFormat = fmt; ex.audio = []
        let t0 = CACurrentMediaTime(), n = Int(seconds * 30)
        var trail: [SIMD4<Double>] = [], tt = t0
        func feed(_ upTo: Double) {
            while tt < upTo {                                              // 音：440 Hz の正弦波
                let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!; b.frameLength = 1024
                for c in 0..<2 { for k in 0..<1024 { b.floatChannelData![c][k] = Float(0.2 * sin(2 * .pi * 440 * (tt - t0 + Double(k) / 48000))) } }
                ex.audio.append((b, tt)); tt += 1024.0 / 48000
            }
        }
        for i in 0...n {                                                   // 30 コマで記録（まばら）→ 書き出しは 60 コマ
            if let di = CommandLine.arguments.firstIndex(of: "--demopose") {     // 超球デモのその時刻の姿
                let p = HyperLabState.demoPose(Double(CommandLine.arguments[di + 1]) ?? 0).map { $0 * .pi / 180 }
                st.diveOn = false; st.diveT = 0; st.thirdK = 0; st.paneDive = false; st.polesMode = 2
                st.pitch = p[0]; st.roll = p[1]; st.yaw = p[2]; st.zw = p[3]; st.viewYaw = p[4]; st.viewPitch = p[5]; st.demoGlass = HyperLabState.demoGlassK(p[0], p[1])
            }
            if let di = CommandLine.arguments.firstIndex(of: "--fill") {         // 超球（試作）：--fill 内側の半径（0 で中心まで）
                st.fillOn = true; st.fillA = Double(CommandLine.arguments[di + 1]) ?? 0
                if CommandLine.arguments.contains("--fillcut") { st.cutOn = true; st.cutKind = 0; st.cutRef = 0; st.cutAngDeg = 45; st.cutWDeg = 110 }   // くさびで切って中を見る
            }
            if CommandLine.arguments.contains("--first") { st.diveThird = false; st.thirdK = 0 }   // 一人称で走る
            let scan = CommandLine.arguments.contains("--zoomscan")         // 同じ場所のまま、ズームだけ 1 → 0（途中で絵が飛ばないか）
            let a = scan ? 0.35 : Double(i) / 30 * 0.3, p = SIMD4(sin(a), 0, 0, cos(a)), f = SIMD4(cos(a), 0, 0, -sin(a))
            trail.append(p)
            if scan { st.diveT = 1 - Double(i) / Double(n) }
            if CommandLine.arguments.contains("--blackout") {               // 左を黒くして、黒い間に右と左が変わり、左が出る
                let u = Double(i) / Double(n)
                st.paneCover = u < 0.2 ? 0 : u < 0.25 ? (u - 0.2) / 0.05 : u < 0.7 ? 1 : max(0, 1 - (u - 0.7) / 0.1)
                st.diveOn = u < 0.25; st.diveT = max(0, min(1, (0.65 - u) / 0.4)); st.paneDive = u < 0.65
            }
            if CommandLine.arguments.contains("--seetest") {                // シースルー：黒 → 透かして変形 → 地図へ入れかえ
                let u = Double(i) / Double(n)
                st.diveOn = u < 0.15; st.diveT = max(0, min(1, (0.8 - u) / 0.65)); st.paneDive = u < 0.85
                st.paneCover = u < 0.1 ? 0 : u < 0.15 ? (u - 0.1) / 0.05 : u < 0.9 ? 1 : max(0, 1 - (u - 0.9) / 0.05)
                st.paneSeeA = u < 0.15 ? 0 : u < 0.9 ? 1 : max(0, 1 - (u - 0.9) / 0.1); st.paneSeeB = min(0.4, max(0, (u - 0.15) * 2))
            }
            if CommandLine.arguments.contains("--cutblack") {               // ぱっとやめる：右はすぐリゾルブ、左は黒を通って入れかわる
                let d = Double(i - n / 2) / 30
                st.paneCover = d < 0 ? 0 : d < 0.12 ? d / 0.12 : d < 0.2 ? 1 : max(0, 1 - (d - 0.2) / 0.15)
                if i == n / 2 { st.diveOn = false; st.diveT = 0; st.thirdK = 0 }
                if d >= 0.15 { st.paneDive = false }
            }
            if CommandLine.arguments.contains("--swapdive") && i == n / 2 { st.diveOn = false; st.diveT = 0; st.thirdK = 0; st.paneDive = false }   // 途中でぱっとダイブをやめる（全部のリゾルブを見る）
            w = HyperLabState.Walk(trail: trail, pos: p, head: f, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 1, 0), vL: f,
                                   plan: (0..<60).map { k in let b = a + Double(k) * 0.02; return SIMD4(sin(b), 0.2 * sin(b * 3), 0, cos(b)) }, dist: a)
            HyperLabState.walkSource = { w }
            if var fr = r.recordFrame() { fr.t = t0 + Double(i) / 30; ex.capture(fr) }
            if live {
                if CommandLine.arguments.contains("--cancelrun") && i == n / 2 { ex.cancelRecording() }   // 確かめ：走っている途中で中止
                feed(t0 + Double(i) / 30 + 0.1)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: max(0, t0 + Double(i + 1) / 30 - CACurrentMediaTime())))
            }
        }
        feed(t0 + seconds + 0.1)
        if live { ex.stopRecording() } else { ex.recording = false; ex.startRender("") }
        let limit = Date().addingTimeInterval(600)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")")
        return ex.lastURL
    }
    private(set) var lastURL: URL? = nil
    private static func sampleBuffer(_ b: AVAudioPCMBuffer, _ pts: CMTime) -> CMSampleBuffer? {
        var asbd = b.format.streamDescription.pointee
        var fmt: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt) == noErr, let fmt else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: fmt,
                                   sampleCount: CMItemCount(b.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb) == noErr, let sb else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(sb, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: b.audioBufferList) == noErr else { return nil }
        return sb
    }
}

/// 左上の地図の窓：ガラスのように重ねる（角の丸い窓。暗い所ほど透けて後ろのダイブ画面が見え、ふちにうっすら光る細い枠）
final class InsetGlass {
    private var pipe: MTLRenderPipelineState?
    init(_ device: MTLDevice) {
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct VO { float4 p [[position]]; float2 uv; };
        vertex VO insetV(uint vid [[vertex_id]]) {
            float2 q = float2((vid << 1) & 2, vid & 2);
            VO o; o.p = float4(q * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(q.x, 1.0 - q.y); return o;
        }
        fragment float4 plainF(VO in [[stage_in]], texture2d<float> t [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(t.sample(s, in.uv).rgb, 1.0);
        }
        fragment float4 overF(VO in [[stage_in]], texture2d<float> t [[texture(0)]]) {
            constexpr sampler s(filter::nearest, address::clamp_to_edge);
            return t.sample(s, in.uv);                                     // 文字の絵（色は α を掛けてある）
        }
        fragment float4 fadeF(VO in [[stage_in]], constant float4& k [[buffer(0)]]) { return float4(0.0, 0.0, 0.0, k.x); }
        fragment float4 blendF(VO in [[stage_in]], texture2d<float> t [[texture(0)]], constant float4& k [[buffer(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return float4(t.sample(s, in.uv).rgb, k.x);
        }
        fragment float4 insetF(VO in [[stage_in]], texture2d<float> t [[texture(0)]], constant float4& k [[buffer(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float3 c = t.sample(s, in.uv).rgb;
            float2 he = k.xy * 0.5, p = in.uv * k.xy - he;
            float r = 22.0;
            float2 qq = abs(p) - (he - r);
            float inside = -(length(max(qq, 0.0)) + min(max(qq.x, qq.y), 0.0) - r);   // 窓の内側への距離（ピクセル）
            float edge = smoothstep(0.0, 1.5, inside);
            float rim = (1.0 - smoothstep(0.0, 2.2, abs(inside - 1.8))) * edge;
            float lum = dot(c, float3(0.3, 0.59, 0.11));
            float a = (0.32 + 0.68 * smoothstep(0.03, 0.28, lum)) * edge * k.z;       // 暗い所は透ける（ガラス）
            float3 col = c + float3(0.55, 0.78, 1.0) * rim * 0.55;
            return float4(col, max(a, rim * 0.75));
        }
        """
        guard let lib = try? device.makeLibrary(source: src, options: nil) else { return }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "insetV"); d.fragmentFunction = lib.makeFunction(name: "insetF")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one; d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipe = try? device.makeRenderPipelineState(descriptor: d)
        d.fragmentFunction = lib.makeFunction(name: "fadeF"); fadeP = try? device.makeRenderPipelineState(descriptor: d)
        d.colorAttachments[0].sourceRGBBlendFactor = .one                   // 文字の絵：α を掛けた色をそのまま重ねる
        d.fragmentFunction = lib.makeFunction(name: "overF"); overP = try? device.makeRenderPipelineState(descriptor: d)
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        d.fragmentFunction = lib.makeFunction(name: "blendF"); blendP = try? device.makeRenderPipelineState(descriptor: d)
        d.fragmentFunction = lib.makeFunction(name: "plainF"); d.colorAttachments[0].isBlendingEnabled = false
        plain = try? device.makeRenderPipelineState(descriptor: d)
    }
    private var plain: MTLRenderPipelineState?, fadeP: MTLRenderPipelineState?, overP: MTLRenderPipelineState?, blendP: MTLRenderPipelineState?
    /// src を dst の (x, y) から w×h の所へ、濃さ a で重ねる（fromX：左からその幅は重ねない）
    func blend(_ cb: MTLCommandBuffer, _ src: MTLTexture, into dst: MTLTexture, x: Int, y: Int, w: Int, h: Int, a: Float, fromX: Int = 0) {
        guard let blendP else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        var k = SIMD4<Float>(a, 0, 0, 0)
        e.setRenderPipelineState(blendP)
        e.setViewport(MTLViewport(originX: Double(x), originY: Double(y), width: Double(w), height: Double(h), znear: 0, zfar: 1))
        e.setScissorRect(MTLScissorRect(x: x + fromX, y: y, width: w - fromX, height: h))
        e.setFragmentTexture(src, index: 0); e.setFragmentBytes(&k, length: 16, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    /// 文字の絵（同じ大きさ）を dst 全体に重ねる
    func over(_ cb: MTLCommandBuffer, _ src: MTLTexture, _ dst: MTLTexture) {
        guard let overP else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(overP); e.setFragmentTexture(src, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    /// dst 全体（w があれば左の w の幅）を黒へ a だけ近づける（フェード）
    func fade(_ cb: MTLCommandBuffer, _ dst: MTLTexture, _ a: Float, w: Int? = nil) {
        guard let fadeP else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        var k = SIMD4<Float>(a, 0, 0, 0)
        if let w { e.setScissorRect(MTLScissorRect(x: 0, y: 0, width: w, height: dst.height)) }
        e.setRenderPipelineState(fadeP); e.setFragmentBytes(&k, length: 16, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    /// src を dst の (x, y) から w×h の所へそのまま写す（大きさ・色の形式がちがっても）
    func copy(_ cb: MTLCommandBuffer, _ src: MTLTexture, into dst: MTLTexture, x: Int, y: Int, w: Int, h: Int) {
        guard let plain else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(plain)
        e.setViewport(MTLViewport(originX: Double(x), originY: Double(y), width: Double(w), height: Double(h), znear: 0, zfar: 1))
        e.setScissorRect(MTLScissorRect(x: x, y: y, width: w, height: h))
        e.setFragmentTexture(src, index: 0); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    /// dst を窓の仕切りの色で塗る（レイアウトのすき間）
    func clear(_ cb: MTLCommandBuffer, _ dst: MTLTexture) {
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.12, green: 0.16, blue: 0.23, alpha: 1); rp.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding()
    }
    /// src（小さな地図の絵）を、dst の (x, y) から w×h の所へガラスのように重ねる
    func draw(_ cb: MTLCommandBuffer, _ src: MTLTexture, into dst: MTLTexture, x: Int, y: Int, w: Int, h: Int) {
        guard let pipe else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(pipe)
        e.setViewport(MTLViewport(originX: Double(x), originY: Double(y), width: Double(w), height: Double(h), znear: 0, zfar: 1))
        e.setScissorRect(MTLScissorRect(x: x, y: y, width: w, height: h))
        var k = SIMD4<Float>(Float(w), Float(h), 0.92, 0)
        e.setFragmentTexture(src, index: 0); e.setFragmentBytes(&k, length: 16, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
}

/// 動画を作るボタン：🎬 動画を作る（記録）／ ■ 止めて書き出す（記録している間は赤く、経った時間）／ 書き出し中は進み具合と中止
struct ExportButton: View {
    @ObservedObject var ex = VideoExport.shared
    @State private var askCancel = false
    var body: some View {
        HStack(spacing: 6) {
            mainButton
            if ex.rendering {
                Button(role: .destructive) { askCancel = true } label: { Label("中止", systemImage: "xmark.circle") }
                    .font(.caption)
                    .help("書き出しをやめる。途中までの動画は残らない")
                    .alert("書き出しを中止しますか？", isPresented: $askCancel) {
                        Button("中止する", role: .destructive) { ex.cancelRender() }
                        Button("続ける", role: .cancel) { }
                    } message: { Text("途中までの動画は残りません") }
            }
        }
    }
    private var mainButton: some View {
        Button { ex.toggle() } label: {
            if ex.recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let s = Int(Date().timeIntervalSince(ex.started))
                    Label(String(format: "止めて書き出す %d:%02d", s / 60, s % 60) + (ex.stopMin > 0 ? String(format: "（あと %d:%02d）", max(0, ex.stopMin * 60 - s) / 60, max(0, ex.stopMin * 60 - s) % 60) : ""), systemImage: "stop.circle.fill").foregroundStyle(.red)
                }
            } else if ex.rendering {
                Label(String(format: "書き出し中 %.0f%%", ex.progress * 100), systemImage: "hourglass")
            } else if ex.armed {
                Label("走り出すのを待っています", systemImage: "hourglass.circle").foregroundStyle(.orange)
            } else {
                Label("動画を作る", systemImage: "film")
            }
        }
        .font(.caption).disabled(ex.rendering)
        .help("押すと記録を始める（走っている間は、動きと音だけを覚える）。もう一度押すと止めて、覚えた動きを描き直して動画にする（書き出しには少し時間がかかる）。Mac：ムービー／球面さんぽ。iPad・iPhone：写真")
        .alert(ex.message ?? "", isPresented: Binding(get: { ex.message != nil }, set: { if !$0 { ex.message = nil } })) { Button("OK") { ex.message = nil } }
    }
}

/// 記録のパネル：超球の窓のパネルの「記録」から開く小窓。録画（画面そのまま）と、動画の書き出し（記録 → 書き出し）の設定をまとめる
extension Renderer {
    /// 超球の窓へ渡す、さんぽの今（歩いた跡・今いる所・目印・見ている向き・予定の道）
    func hyperWalk() -> HyperLabState.Walk {
        let r = self
        return .init(trail: r.journey.trail, pos: r.cam.w.p, marks: r.journey.marks + r.journey.routePts, hit: r.journey.marks.map { r.journey.isHit($0) } + r.journey.routePts.map { r.journey.isRouteHit($0) }, poles: r.journey.polesHit, lap: r.journey.lap, head: r.cam.lookFrame().L, space: r.set.space, fwd: r.cam.w.f, vR: r.cam.viewFrame().R, vU: r.cam.viewFrame().U, vL: r.cam.viewFrame().L, fov: r.set.fov, plan: HyperLabState.planWanted ? r.plannedPath() : [], dist: r.journey.dist, rail: HyperLabState.railWanted ? (r.pathMode != .none ? r.railPath() : r.railCache.pts) : [], railGen: r.railGen)
    }
}

/// らくらく書き出し：道と周数を決めて押すだけ。再生しながら書き出す（いつもの記録 → 描き直し）・再生せずに書き出す（裏で走らせる）・キャプチャ（画面をそのまま録る）
@MainActor final class EasyExport: ObservableObject {
    static let shared = EasyExport()
    @Published var laps = UserDefaults.standard.object(forKey: "s3walk.easy.laps") as? Double ?? 1 { didSet { UserDefaults.standard.set(laps, forKey: "s3walk.easy.laps") } }
    @Published var view = UserDefaults.standard.object(forKey: "s3walk.easy.view") as? Int ?? 0 { didSet { UserDefaults.standard.set(view, forKey: "s3walk.easy.view") } }   // 0 ダイブ・1 ダイブなし・2 両方（タイムラインの通り）・3 2 本（ダイブの本と超球の本）
    @Published var zoom = UserDefaults.standard.object(forKey: "s3walk.easy.zoom") as? Bool ?? true { didSet { UserDefaults.standard.set(zoom, forKey: "s3walk.easy.zoom") } }   // 両方の時：ズームでつなぐ（切ると、ぱっと切りかえ）
    @Published var spans = (UserDefaults.standard.array(forKey: "s3walk.easy.spans") as? [[Double]])?.filter { $0.count == 2 } ?? [[0.5, 1]] { didSet { UserDefaults.standard.set(spans, forKey: "s3walk.easy.spans") } }   // 両方：ダイブする区間（全体を 0〜1 として）
    /// 区間を足して、重なりをまとめる
    nonisolated static func merged(_ spans: [[Double]], _ a: Double, _ b: Double) -> [[Double]] {
        var out: [[Double]] = []
        for x in (spans + [[a, b]]).sorted(by: { $0[0] < $1[0] }) {
            if let l = out.last, x[0] <= l[1] { out[out.count - 1][1] = max(l[1], x[1]) } else { out.append(x) }
        }
        return out
    }
    /// 区間を取りのぞく（ダイブなしを塗る時）
    nonisolated static func removed(_ spans: [[Double]], _ a: Double, _ b: Double) -> [[Double]] {
        spans.flatMap { s in [[s[0], min(s[1], a)], [max(s[0], b), s[1]]].filter { $0[1] - $0[0] > 0.005 } }
    }
    /// 押した所の区間の色を反対にする
    nonisolated static func flipped(_ spans: [[Double]], at f: Double) -> [[Double]] {
        if spans.contains(where: { $0[0] <= f && f <= $0[1] }) { return spans.filter { !($0[0] <= f && f <= $0[1]) } }
        return merged(spans, spans.map { $0[1] }.filter { $0 < f }.max() ?? 0, spans.map { $0[0] }.filter { $0 > f }.min() ?? 1)
    }
    func inDive(_ p: Double) -> Bool { spans.contains { p >= $0[0] && (p < $0[1] || (p >= 1 && $0[1] >= 1)) } }
    @Published var method = UserDefaults.standard.object(forKey: "s3walk.easy.method") as? Int ?? 0 { didSet { UserDefaults.standard.set(method, forKey: "s3walk.easy.method") } }   // 0 再生しながら書き出す・1 再生せずに書き出す・2 キャプチャ・3 テスト（同じ流れで走るだけ。録らない）・4 プロキシ（走りながら裏で描く）
    @Published private(set) var running = false
    @Published private(set) var progress = 0.0
    private var timer: Timer?, L = 1.0, armedT = 0.0, going = false
    private func setDive(_ on: Bool, cut: Bool, _ st: HyperLabState) { st.diveManual = false; st.diveOn = on; if cut { st.diveT = on ? 1 : 0 }; st.bump() }
    private func start(_ r: Renderer) {                                // 選んだ道を最初から
        let ex = VideoExport.shared
        if ex.genPath == PathMode.custom.rawValue, let rt = RouteStore.shared.routes.first(where: { $0.id.uuidString == ex.genRoute }) { r.pickRoute(rt); r.restartRoute() }
        else { r.lastMode = PathMode(rawValue: ex.genPath) ?? .tour; r.lastRoute = nil; r.restartRoute() }
    }
    /// 始める。始められなかった時は false（知らせは ex.message）
    @discardableResult func begin() -> Bool {
        let ex = VideoExport.shared
        guard !running, !ex.recording, !ex.rendering, let lv = HyperLabRenderer.liveMain, let wr = HyperLabState.walkRendererGet?() else { return false }
        ex.genLaps = 0
        let (d, e) = ex.lapDistance(lv.device, wr.set)
        guard let d else { ex.message = e; return false }
        L = d
        if method == 1 {                                                   // 再生せずに：裏で走らせて描く
            let keep = ex.forceDive
            if view == 1 { setDive(false, cut: true, lv.st) }
            ex.genLaps = laps; ex.forceDive = view == 0 || view == 3; ex.dualOnce = view == 3; lv.st.saveIfChanged()
            ex.exportRoute(); ex.genLaps = 0; ex.forceDive = keep; ex.dualOnce = nil
            return true
        }
        running = true; progress = 0; going = false; armedT = CACurrentMediaTime()
        setDive(view == 0 || view == 3 || (view == 2 && inDive(0)), cut: true, lv.st)
        lv.st.paneDive = lv.st.diveOn; lv.st.resolveArmed = view == 2 && !zoom
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if method == 0 || method == 4 {                                    // 再生しながら：いつもの記録。止まったら描き直す。プロキシ：描きながら記録する
            start(wr); ex.proxy = method == 4; ex.dualOnce = method == 4 ? view == 3 : nil; ex.startRecording(); going = true
        } else if method == 3 {                                            // テスト：見え方だけ確かめる
            start(wr); going = true
        } else {                                                           // キャプチャ：前の窓を録ってから走り出す
            start(wr); wr.stopWalking()
            #if os(macOS)
            HyperLabWindow.window?.makeKeyAndOrderFront(nil)
            #endif
            Task { @MainActor in try? await Task.sleep(nanoseconds: 400_000_000); if self.running { Recorder.shared.start() } }
        }
        return true
    }
    /// 途中でやめる（再生しながらの時は書き出さない。キャプチャはそこまでを保存）
    func cancel() {
        let m = method; finish()
        if m == 0 || m == 4 { VideoExport.shared.cancelRecording(); VideoExport.shared.dualOnce = nil } else if m == 2 && Recorder.shared.recording { Recorder.shared.stop() }
    }
    private func finish() { HyperLabRenderer.liveMain?.st.resolveArmed = false; timer?.invalidate(); timer = nil; running = false; HyperLabState.walkRendererGet?()?.stopWalking() }
    private func tick() {
        let rec = Recorder.shared, ex = VideoExport.shared, now = CACurrentMediaTime()
        guard let wr = HyperLabState.walkRendererGet?(), let st = HyperLabRenderer.liveMain?.st else { finish(); return }
        if !going {
            if rec.recording, now - armedT > 0.8 { start(wr); going = true }   // 録画が始まってから走り出す
            else if !rec.recording && !rec.busy && now - armedT > 2 { finish() }   // 録画を始められなかった
            return
        }
        guard method == 3 || (method == 0 || method == 4 ? ex.recording : rec.recording) else { finish(); ex.dualOnce = nil; return }   // 別のボタン・⌘⇧R で止めた時
        let p = wr.journey.dist / (L * max(0.01, laps)); progress = min(1, p)
        if view == 2 && inDive(min(1, p)) != st.diveOn { setDive(!st.diveOn, cut: !zoom, st); if !zoom { st.resolveT = now } }
        if p >= 1 || wr.pathMode == .none {
            let m = method; finish()
            if m == 0 {                                                    // 記録したダイブのまま描く（「ダイブで描く」の設定によらず）
                let keep = ex.forceDive; ex.forceDive = false; ex.dualOnce = view == 3; ex.stopRecording(); ex.forceDive = keep; ex.dualOnce = nil
            } else if m == 4 { ex.stopRecording(); ex.dualOnce = nil }
            else if m == 2 { rec.stop() }
        }
    }
}

/// 記録のパネル：らくらく書き出し
struct EasyExportRow: View {
    @ObservedObject var ez = EasyExport.shared
    @ObservedObject var ex = VideoExport.shared
    var close: () -> Void = {}
    private var busy: Bool { ez.running || ex.recording || ex.rendering }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("らくらく書き出し").font(.headline)
            HStack {
                GenRoutePicker()
                Text("周数").font(.caption)
                TextField("周数", value: Binding(get: { ez.laps }, set: { ez.laps = max(0.1, min(50, $0)) }), format: .number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder).frame(width: 52)
                Stepper("", value: Binding(get: { ez.laps }, set: { ez.laps = max(0.1, min(50, $0)) }), in: 0.1...50, step: 0.5).labelsHidden()
            }.disabled(busy)
            Picker("映像", selection: $ez.view) { Text("ダイブ").tag(0); Text("ダイブなし").tag(1); Text("両方").tag(2); Text("2 本").tag(3) }.pickerStyle(.segmented).disabled(busy)
                .onChange(of: ez.view) { _, v in if (v == 2 && ez.method == 1) || (v == 3 && ez.method == 2) { ez.method = 0 } }
                .help("2 本：ダイブの本と超球の本を、同じ走りから全面で書き出す（コマも音もそろう。編集ソフトで重ねて切りかえる用。時間と容量は 2 倍）。キャプチャでは使えない")
            if ez.view == 2 {
                DiveTimeline().disabled(busy)
                Toggle("移行アニメーション（ズームでつなぐ。切ると、ぱっと切りかえ）", isOn: $ez.zoom).font(.caption).disabled(busy)
            }
            Picker("書き出し方", selection: $ez.method) { Text("再生しながら").tag(0); Text("プロキシ").tag(4); Text("再生せず").tag(1); Text("キャプチャ").tag(2); Text("テスト").tag(3) }.pickerStyle(.menu).disabled(busy)
                .onChange(of: ez.method) { _, m in if (m == 1 && ez.view == 2) || (m == 2 && ez.view == 3) { ez.view = 0 } }
                .help("再生しながら：走る動きと音を覚えて、終わったらテロップや座標ごと描き直す（いつもの書き出し）。プロキシ：走っている間は画面を粗くして、本物の動画を裏で描く（待ち時間が短くなる。動画の画質は落ちない）。再生せず：画面で走らせず、裏で動画にする（「両方」は使えない）。キャプチャ：画面をそのまま録る。テスト：録らずに同じ流れで走って、見え方だけ確かめる")
            if ez.running {
                HStack { ProgressView(value: ez.progress); Button("止める") { ez.cancel() } }
            } else {
                Button { if ez.begin() { close() } } label: { Label(ez.method == 3 ? "テスト再生" : "書き出す", systemImage: "play.rectangle.fill") }.disabled(busy)
                    .help("道を最初から走って、周数ぶんで止める。小数の周は途中で終わる")
            }
        }
    }
}
/// 動画の全体のバー：色を選んでドラッグで塗る。はしを引くと長さを変え、押すと色が反対になる
struct DiveTimeline: View {
    @ObservedObject var ez = EasyExport.shared
    @State private var from: Double? = nil
    @State private var to = 0.0
    @State private var edge: (i: Int, k: Int)? = nil
    @State private var paintDive = true
    private let col = Color(red: 0.2, green: 0.55, blue: 1.0), off = Color(red: 0.95, green: 0.62, blue: 0.22)   // 青 ダイブ・橙 ダイブなし
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("塗る色").font(.caption)
                ForEach([(true, "ダイブ", col), (false, "ダイブなし", off)], id: \.0) { on, n, c in
                    Button { paintDive = on } label: {
                        Text(n).font(.caption).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(c.opacity(paintDive == on ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 4))
                    }.buttonStyle(.plain)
                }
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(off)
                    ForEach(ez.spans.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(col).frame(width: max(2, w * (ez.spans[i][1] - ez.spans[i][0]))).offset(x: w * ez.spans[i][0])
                    }
                    if let f = from { RoundedRectangle(cornerRadius: 3).fill((paintDive ? col : off).opacity(0.8)).frame(width: abs(to - f) * w).offset(x: min(f, to) * w) }
                    ForEach(Array(stride(from: 1.0, to: ez.laps, by: 1.0)), id: \.self) { k in      // 周の区切り
                        Rectangle().fill(Color.white).frame(width: 2).offset(x: w * k / ez.laps - 1)
                    }
                    if ez.running { Rectangle().fill(Color.red).frame(width: 2).offset(x: w * ez.progress - 1) }   // 今の位置
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let x = max(0, min(1, v.location.x / w)), x0 = max(0, min(1, v.startLocation.x / w))
                        if from == nil && edge == nil {
                            for (i, sp) in ez.spans.enumerated() { for k in 0..<2 where abs(sp[k] - x0) < 8 / w { edge = (i, k) } }
                            if edge == nil { from = x0 }
                        }
                        let sn = x < 0.02 ? 0 : x > 0.98 ? 1 : x
                        if let e = edge, e.i < ez.spans.count { ez.spans[e.i][e.k] = sn } else { to = sn }
                    }
                    .onEnded { v in
                        if edge != nil {                                    // 引いたはし：縮み切ったら消す。重なりはまとめる
                            let all = ez.spans.map { [min($0[0], $0[1]), max($0[0], $0[1])] }.filter { $0[1] - $0[0] > 0.005 }
                            ez.spans = all.reduce([]) { EasyExport.merged($0, $1[0], $1[1]) }
                        } else if let f = from {
                            let a = min(f, to), b = max(f, to)
                            let a2 = a < 0.02 ? 0 : a, b2 = b > 0.98 ? 1 : b
                            if b - a < 0.01 { ez.spans = EasyExport.flipped(ez.spans, at: f) }   // 押すと色が反対に
                            else if paintDive { ez.spans = EasyExport.merged(ez.spans, a2, b2) }
                            else { ez.spans = EasyExport.removed(ez.spans, a2, b2) }
                        }
                        from = nil; edge = nil
                    })
            }.frame(height: 20)
            Text("青 ダイブ・橙 ダイブなし・白線 周の区切り。色を選んでドラッグで塗る・はしを引いて長さを変える・押すと色が反対になる").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
/// 記録のパネルの道の選択（決まった道・自分の道）
struct GenRoutePicker: View {
    @ObservedObject var ex = VideoExport.shared
    @ObservedObject var store = RouteStore.shared
    var body: some View {
        Picker("道", selection: Binding(get: { ex.genPath == PathMode.custom.rawValue ? "r:" + ex.genRoute : "m:\(ex.genPath)" },
                                        set: { v in if v.hasPrefix("r:") { ex.genPath = PathMode.custom.rawValue; ex.genRoute = String(v.dropFirst(2)) } else { ex.genPath = Int(v.dropFirst(2)) ?? PathMode.tour.rawValue } })) {
            ForEach([(PathMode.tour, "極めぐり"), (.spiral, "螺旋"), (.ring, "回る輪"), (.half, "半周のターン"), (.cube, "超立方体の辺めぐり"), (.cell24, "二十四胞体の辺めぐり")], id: \.0.rawValue) { m, n in Text(n).tag("m:\(m.rawValue)") }
            ForEach(store.routes.filter { !$0.pts.isEmpty }) { rt in Text("自分の道「\(rt.name)」").tag("r:" + rt.id.uuidString) }
        }.labelsHidden().frame(maxWidth: 180)
    }
}

/// 記録のパネル：決まった道から、ひとりでにダイブの動画を作る
struct GenRouteRow: View {
    @ObservedObject var ex = VideoExport.shared
    @ObservedObject var store = RouteStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("決まった道から作る").font(.subheadline.weight(.semibold))
            HStack {
                GenRoutePicker()
                Picker("長さ", selection: $ex.genSeconds) { Text("1 周").tag(0.0); Text("2 周").tag(-1.0); ForEach([10.0, 20, 30, 40, 50, 60], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }.labelsHidden().frame(width: 80)
            }
            Button { ex.exportRoute() } label: { Label("この道で作る", systemImage: "wand.and.stars") }
                .font(.caption).disabled(ex.recording || ex.rendering)
                .help("さんぽを裏でこの道の最初の場所から歩かせて（今の設定・出発の速さで）、そのままダイブの動画に描く。黒からフェードインして走り出し、1 周（か決めた長さ）でフェードアウトして終わる。今のさんぽは動かさない。音は入らない")
        }
    }
}

struct RecordPanelButton: View {
    @ObservedObject var ex = VideoExport.shared
    @ObservedObject var rec = Recorder.shared
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            if ex.recording || rec.recording { Label("記録中", systemImage: "record.circle.fill").foregroundStyle(.red) }
            else if ex.rendering { Label(String(format: "書き出し中 %.0f%%", ex.progress * 100), systemImage: "hourglass") }
            else { Label("記録", systemImage: "film.stack") }
        }
        .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(Color(red: 0.75, green: 0.25, blue: 0.3))   // 目立つように
        .help("記録のパネル：画面の録画と、動画の書き出し（記録 → あとで高画質に描き直す）")
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                EasyExportRow(close: { open = false })
                Divider()
                Text("動画を作る（記録 → 書き出し）").font(.headline)
                Text("走っている間は動きと音だけを覚え、止めたあとで 60 コマ・最高の細かさで描き直します。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { ExportButton(); Spacer() }
                Picker("止めるタイマー", selection: $ex.stopMin) { Text("なし").tag(0); ForEach([1, 2, 3, 5, 10, 15, 20], id: \.self) { Text("\($0) 分").tag($0) } }
                    .frame(maxWidth: 200).help("「動画を作る」と画面の録画を、この時間で自動で止める（書き出しは止めたあと、いつも通り描き直す）。なしでも記録は 20 分で止まる")
                Toggle("ダイブイン（超球の全体から寄って走り出す）", isOn: $ex.diveIn).disabled(ex.recording || ex.rendering)
                    .help("動画の始めに 6 秒、超球の全体からフェードインして、走る所へ寄っていく。寄り切る時に走り出しがつながる。動画はそのぶん長くなる")
                Toggle("走り出しで始めて、止まったら黒く消して終わる", isOn: $ex.autoRec).disabled(ex.recording || ex.rendering || ex.armed)
                    .help("「動画を作る」を押すと待機する。走り出したら記録を始めてフェードイン（1.5 秒）、止まったらフェードアウト（2 秒）して、真っ黒になった所で記録が止まり、描き直しに進む。音も一緒にフェードする")
                HStack {
                    Button { ex.exportLast() } label: { Label("直前の \(ex.lastLenName)を書き出す", systemImage: "gobackward") }
                        .font(.caption).disabled(!ex.keepLast || ex.recording || ex.rendering || ex.ringSeconds < 1)
                        .help("裏でいつも覚えている直前の走り（止まっていた間は含めない）を、すぐ描き直して動画にする。周で選ぶと、走り終えた周だけを切れ目から切れ目まで書き出す")
                    Picker("長さ", selection: $ex.lastLen) {
                        ForEach([10.0, 20, 30, 40, 50, 60], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                        if ex.routeRunning { Text("1 周ぶん").tag(-1.0); Text("2 周ぶん").tag(-2.0) }
                    }.labelsHidden().frame(width: 90)
                    Spacer()
                }
                HStack {
                    Toggle("直前の走りをいつも覚えておく", isOn: $ex.keepLast).disabled(ex.rendering)
                        .help("超球の窓を出している間、動いている時の動きと音を、裏でいつも覚えておく（絵は描かないので軽い）")
                    Picker("長さ", selection: $ex.keepMin) { ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) 分").tag($0) } }.labelsHidden().frame(width: 70).disabled(!ex.keepLast || ex.rendering)
                        .help("上限は 10 分。メモリは 1 分で約 40 MB。長い道を 2 周ぶん残したい時は長めに")
                }
                Text(String(format: "覚えている走り %.0f 秒・メモリ 約 %.0f MB", ex.ringSeconds, ex.ringSeconds / 60 * 40)).font(.caption2).foregroundStyle(.secondary)
                GenRouteRow()
                Picker("レイアウト", selection: $ex.layout) { Text("ダイブ画面だけ").tag(0); Text("超球の窓のレイアウト").tag(1) }
                    .pickerStyle(.segmented).disabled(ex.recording || ex.rendering)
                    .help("ダイブ画面だけ：16:9 いっぱいにダイブ画面（左上に小さくガラスの窓の地図も選べる）。超球の窓のレイアウト：超球の窓と同じ仕切りの比率で、左上に地図（黒地のまま）、左下にさんぽの景色、残りに大きくダイブ画面")
                Picker("画質", selection: $ex.quality) {
                    Text("標準").tag(0); Text("高画質").tag(1)
                    #if os(macOS)
                    Text("最高（ProRes）").tag(2)
                    #endif
                }.pickerStyle(.segmented).disabled(ex.recording || ex.rendering)
                Text(String(format: "1 分で約 %.1f GB", ex.mbps * 60 / 8 / 1000)).font(.caption2).foregroundStyle(.secondary)
                Picker("大きさ", selection: $ex.uhd) { Text("フル HD（1920×1080）").tag(false); Text("4K（3840×2160）").tag(true) }
                    .pickerStyle(.segmented).disabled(ex.recording || ex.rendering)
                Toggle("ダイブしていなくても、ダイブで描く", isOn: $ex.forceDive).disabled(ex.recording || ex.rendering)
                    .help("書き出しはいつも三人称のダイブで描く（記録の間ダイブしていなくてもよい）。カメラ（オートカメラ・ショーカメラ）は書き出しの中で動かす")
                Toggle("ヘビーモードで描く（殻を細かく。書き出しに時間がかかる）", isOn: $ex.heavy).disabled(ex.recording || ex.rendering)
                Toggle("画面の文字も入れる（座標・周回・極の名前・見出し）", isOn: $ex.withText).disabled(ex.recording || ex.rendering)
                    .help("超球の窓の上に出ている文字（走行中の座標・周回・角度の読み・窓の見出し）と、さんぽの景色の極の点と名前を、画面と同じ見た目で動画にも描き込む")
                Toggle("左上に小さく地図（ダイブ画面だけの時）", isOn: $ex.withMap).disabled(ex.recording || ex.rendering || (ex.layout != 0 && !ex.dual))
                Toggle("ダイブと超球の 2 本に書き出す（編集ソフト用）", isOn: $ex.dual).disabled(ex.recording || ex.rendering)
                    .help("同じ走りから、全面のダイブの本と超球の本を順に書き出す。コマも音もそろうので、編集ソフトで重ねて切りかえられる。レイアウトの設定は使わない。時間と容量は 2 倍")
                Divider()
                Text("画面をそのまま録画").font(.headline)
                HStack { RecordButton(); Spacer() }
                #if os(macOS)
                Toggle("最高画質（ProRes 4444・ファイルが大きい）", isOn: $rec.prores).disabled(rec.recording)
                #endif
            }
            .padding(14).frame(width: 380)
        }
    }
}

#if os(macOS)
typealias HUDFont = NSFont
#else
typealias HUDFont = UIFont
#endif
/// 書き出しの絵の上の文字：CoreGraphics で透明な絵に描いて（上から下へ y）、Metal の絵にして重ねる。GPU が読んでいる間に描きかえないよう、絵は 4 枚を順に使う
final class ExportHUD {
    let w: Int, h: Int
    private let ctx: CGContext
    private var texs: [MTLTexture] = [], idx = 0, empty = true
    init?(_ dev: MTLDevice, _ w: Int, _ h: Int) {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx = c; self.w = w; self.h = h
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
        for _ in 0..<4 {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false); d.usage = .shaderRead
            #if os(macOS)
            d.storageMode = dev.hasUnifiedMemory ? .shared : .managed
            #else
            d.storageMode = .shared
            #endif
            guard let t = dev.makeTexture(descriptor: d) else { return nil }
            texs.append(t)
        }
    }
    func begin() { ctx.clear(CGRect(x: 0, y: 0, width: w, height: h)); empty = true }
    /// 描いた絵を Metal の絵に（何も描いていなければ nil）
    func finish() -> MTLTexture? {
        guard !empty, let p = ctx.data else { return nil }
        idx = (idx + 1) % texs.count
        texs[idx].replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: p, bytesPerRow: w * 4)
        return texs[idx]
    }
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    static func font(_ size: CGFloat, _ weight: HUDFont.Weight = .regular, mono: Bool = false, serif: Bool = false, name: String? = nil) -> CTFont {
        if let name, let f = HUDFont(name: name, size: size) { return f as CTFont }
        var f = mono ? HUDFont.monospacedSystemFont(ofSize: size, weight: weight) : HUDFont.systemFont(ofSize: size, weight: weight)
        if serif, let d = f.fontDescriptor.withDesign(.serif) {
            #if os(macOS)
            f = HUDFont(descriptor: d, size: size) ?? f
            #else
            f = HUDFont(descriptor: d, size: size)
            #endif
        }
        return f as CTFont
    }
    private func line(_ s: String, _ font: CTFont, _ color: CGColor) -> (CTLine, CGFloat, CGFloat, CGFloat) {
        let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        let l = CTLineCreateWithAttributedString(a)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let wd = CGFloat(CTLineGetTypographicBounds(l, &asc, &desc, &lead))
        return (l, wd, asc, desc)
    }
    /// 速度メーター（超球の窓の HLMeterLabel と同じ形）
    func meter(_ m: Double, _ a: Double, top: Double, cx: CGFloat, y: CGFloat, k: CGFloat) {
        empty = false
        let w = 190 * k, h = 7 * k, x = cx - (w + 43 * k) / 2, tp = top * 1.2, c = HLLive.meterRGB(m, a, top), col = ExportHUD.rgb(c.x, c.y, c.z)
        ctx.setFillColor(ExportHUD.rgb(0, 0, 0, 0.5))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)); ctx.fillPath()
        let fw = max(h, w * CGFloat(min(1, m / tp)))
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 4 * k, color: col); ctx.setFillColor(col)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: fw, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)); ctx.fillPath(); ctx.restoreGState()
        ctx.setFillColor(ExportHUD.rgb(1, 1, 1)); ctx.fill(CGRect(x: x + w / CGFloat(tp) - k, y: y - 3.5 * k, width: 2 * k, height: h + 7 * k))
        box(String(format: "×%.1f", m), font: ExportHUD.font(11 * k, .semibold, mono: true), color: col, x: x + w + 7 * k, y: y - 5 * k, padH: 0, padV: 0)
    }
    /// 文字の箱（複数行も）。(x, y) は箱の左上（alignRight の時は右上、alignBottom の時は左下）。箱の大きさを返す
    @discardableResult
    func box(_ text: String, font: CTFont, color: CGColor, x: CGFloat, y: CGFloat, padH: CGFloat, padV: CGFloat, lineGap: CGFloat = 0,
             bg: CGColor? = nil, stroke: CGColor? = nil, strokeW: CGFloat = 1, radius: CGFloat = 0, capsule: Bool = false,
             glow: CGColor? = nil, glowR: CGFloat = 0, alignRight: Bool = false, alignBottom: Bool = false) -> CGSize {
        let ls = text.components(separatedBy: "\n").map { line($0, font, color) }
        let tw = ls.map { $0.1 }.max() ?? 0, lh = ls.map { $0.2 + $0.3 }.reduce(0, +) + lineGap * CGFloat(max(0, ls.count - 1))
        let bw = ceil(tw + 2 * padH), bh = ceil(lh + 2 * padV)
        let r = CGRect(x: alignRight ? x - bw : x, y: alignBottom ? y - bh : y, width: bw, height: bh)
        let rad = capsule ? bh / 2 : radius
        let path = CGPath(roundedRect: r, cornerWidth: min(rad, bw / 2), cornerHeight: min(rad, bh / 2), transform: nil)
        if let bg { ctx.addPath(path); ctx.setFillColor(bg); ctx.fillPath() }
        if let stroke { ctx.addPath(path); ctx.setStrokeColor(stroke); ctx.setLineWidth(strokeW); ctx.strokePath() }
        ctx.saveGState()
        if let glow { ctx.setShadow(offset: .zero, blur: glowR * 2, color: glow) }
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        var ty = r.minY + padV
        for (l, _, asc, desc) in ls { ctx.textPosition = CGPoint(x: r.minX + padH, y: ty + asc); CTLineDraw(l, ctx); ty += asc + desc + lineGap }
        ctx.restoreGState()
        empty = false
        return r.size
    }
    /// 窓の見出し（超球の窓と同じ：11 点・角丸の暗い箱・外に 8 点）
    func caption(_ s: String, in pane: CGRect, k: CGFloat) {
        ctx.saveGState(); ctx.clip(to: pane); defer { ctx.restoreGState() }  // となりの窓へはみ出さない
        box(s, font: ExportHUD.font(11 * k), color: ExportHUD.rgb(0.93, 0.95, 0.98), x: pane.minX + 8 * k, y: pane.minY + 8 * k, padH: 10 * k, padV: 5 * k,
            bg: ExportHUD.rgb(0.06, 0.09, 0.16, 0.9), stroke: ExportHUD.rgb(0.2, 0.25, 0.33), strokeW: k, radius: 10 * k)
    }
    /// さんぽの景色の上の 8 つの極（PoleOverlay と同じ並べ方）：色の点（遠いほど小さく）と「名前 距離」を、空いている所へ
    func poles(_ ls: [Renderer.PoleLab], in pane: CGRect, k: CGFloat, serif: Bool) {
        let font = serif ? ExportHUD.font(11 * k, name: "Baskerville-SemiBold") : ExportHUD.font(11 * k, .bold)
        struct It { var k: Int; var x: CGFloat; var y: CGFloat; var lab: Renderer.PoleLab }
        var items = ls.prefix(8).enumerated().map { It(k: $0.offset, x: pane.minX + CGFloat(0.5 + 0.5 * $0.element.x) * pane.width, y: pane.minY + CGFloat(0.5 - 0.5 * $0.element.y) * pane.height, lab: $0.element) }
        items.sort { $0.lab.d < $1.lab.d }
        var shown: [It] = []
        ctx.saveGState(); ctx.clip(to: pane)
        for it in items.reversed() where !items.prefix(while: { $0.k != it.k }).contains(where: { hypot($0.x - it.x, $0.y - it.y) < 9 * k }) {   // 奥から描いて、手前を上に
            let q = min(1, it.lab.d / (Double.pi / 2)), rr = CGFloat(12 - 7 * q * q * (3 - 2 * q)) * k
            let c = CGRect(x: it.x - rr / 2, y: it.y - rr / 2, width: rr, height: rr)
            ctx.setFillColor(ExportHUD.rgb(Double(it.lab.col.x), Double(it.lab.col.y), Double(it.lab.col.z))); ctx.fillEllipse(in: c)
            ctx.setStrokeColor(ExportHUD.rgb(8 / 255, 12 / 255, 28 / 255, 0.85)); ctx.setLineWidth(2 * k); ctx.strokeEllipse(in: c.insetBy(dx: k, dy: k))
            shown.append(it); empty = false
        }
        var rects: [CGRect] = []
        for it in items.sorted(by: { ($0.lab.isN ? 0 : 1, $0.lab.d) < ($1.lab.isN ? 0 : 1, $1.lab.d) }) {
            let col = ExportHUD.rgb(Double(it.lab.col.x), Double(it.lab.col.y), Double(it.lab.col.z))
            let (l, tw, asc, _) = line(it.lab.name, font, col)
            let bw = ceil(tw) + 2 * k, bh = 14 * k
            for (dx, dy) in [(8 * k, -8 * k), (-8 * k - bw, -8 * k), (-bw / 2, -23 * k), (-bw / 2, 8 * k)] {
                let r = CGRect(x: it.x + dx, y: it.y + dy, width: bw, height: bh)
                if r.minX < pane.minX || r.maxX > pane.maxX || r.minY < pane.minY || r.maxY > pane.maxY { continue }
                if rects.contains(where: { $0.intersects(r) }) { continue }
                if shown.contains(where: { $0.k != it.k && $0.x > r.minX - 4 * k && $0.x < r.maxX + 4 * k && $0.y > r.minY - 4 * k && $0.y < r.maxY + 4 * k }) { continue }
                ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 4 * k, color: ExportHUD.rgb(0, 0, 0))
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1); ctx.textPosition = CGPoint(x: r.minX + k, y: r.minY + (bh - 11 * k) / 2 + asc * 0.95)
                CTLineDraw(l, ctx); ctx.restoreGState()
                rects.append(r); empty = false; break
            }
        }
        ctx.restoreGState()
    }
}
