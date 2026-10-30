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
        init(t: Double, dom: Double, walk: HyperLabState.Walk, rawTrail: [SIMD4<Double>], f: [Double], cometDir: SIMD3<Double>, showFrame: SIMD2<Double>,
             layers: Int, lzw: Int, version: Int, diveOn: Bool, dragging: Bool, padHolding: Bool, walkCam: Camera?) {
            self.walkCam = walkCam
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
    @Published var forceDive = UserDefaults.standard.object(forKey: "s3walk.export.forceDive") as? Bool ?? true { didSet { UserDefaults.standard.set(forceDive, forKey: "s3walk.export.forceDive") } }
    @Published var message: String? = nil
    // 画面の上の文字も描き込む（窓の見出し・走行中の座標・周回・角度の読み・さんぽの景色の極）
    @Published var withText = UserDefaults.standard.object(forKey: "s3walk.export.text") as? Bool ?? true { didSet { UserDefaults.standard.set(withText, forKey: "s3walk.export.text") } }
    // 決まった道から作る：道（PathMode の番号。7 は自分の道 genRoute）と長さ（秒）
    @Published var genPath = UserDefaults.standard.object(forKey: "s3walk.export.genPath") as? Int ?? PathMode.tour.rawValue { didSet { UserDefaults.standard.set(genPath, forKey: "s3walk.export.genPath") } }
    @Published var genRoute = UserDefaults.standard.string(forKey: "s3walk.export.genRoute") ?? "" { didSet { UserDefaults.standard.set(genRoute, forKey: "s3walk.export.genRoute") } }
    @Published var genSeconds = UserDefaults.standard.object(forKey: "s3walk.export.genSec") as? Double ?? 0 { didSet { UserDefaults.standard.set(genSeconds, forKey: "s3walk.export.genSec") } }   // 0：1 周・−1：2 周
    /// 書き出しの間だけ：裏で道を歩く、もう一人のさんぽ（さんぽの景色もこれで描く）
    private(set) var gen: Renderer? = nil
    private var genTpl: RecFrame? = nil, genCs: SIMD4<Double>? = nil, genSpd = 0.0, genFreed = 0
    // 決まった道から作る時の音：画面に出さずに作る音（超球の窓の音と同じ作り方）と、その時の速さ・曲がり・チェックポイント
    private var genSnd: HyperSound? = nil, genAFmt: AVAudioFormat? = nil, gsVol = 0.7, gsPos: SIMD4<Double>? = nil, gsFwd: SIMD4<Double>? = nil
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

    func toggle() { recording ? stopRecording() : startRecording() }

    private func fileName() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd_HHmmss"
        return "球面さんぽ_ダイブ_\(f.string(from: Date())).mov"
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
                    while let f = self.ringAudio.first, f.t < vt - 62 { self.ringAudio.removeFirst() }
                }
            }
        }
    }

    // ---- ① 記録 ----
    func startRecording() {
        guard !recording, !rendering else { return }
        frames = []; lastRaw = []; aq.sync { audio = []; aClock = nil }
        audioFormat = HyperSound.shared.tapFormat()
        ensureTap()
        started = Date(); recording = true
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.started) > 20 * 60 { self.stopRecording(note: "記録は 20 分までなので、ここで止めました。\n") }
        }
    }
    /// 1 コマ分を覚える（右の超球の画面が描くたびに呼ぶ）。跡はふえた分だけ
    func capture(_ f0: RecFrame) {
        ensureTap()
        if keepLast { ringCapture(f0) }
        guard recording else { return }
        var f = f0
        let raw = f.trailAdd
        if !lastRaw.isEmpty, raw.count >= lastRaw.count, raw[lastRaw.count - 1] == lastRaw[lastRaw.count - 1] {
            f.trailAdd = Array(raw[lastRaw.count...]); f.trailReset = false
        } else { f.trailAdd = raw; f.trailReset = true }
        lastRaw = raw
        frames.append(f)
    }
    func stopRecording(note: String = "") {
        guard recording else { return }
        recording = false; watch?.invalidate(); watch = nil
        if !keepLast { HyperSound.shared.untap() }
        guard frames.count >= 2 else { message = note + "記録が短すぎました（超球の窓を出して、少し走ってから止めてください）"; return }
        startRender(note)
    }

    // ---- 直前の 1 分：いつも裏で、動いている間の直前 1 分ぶんの動きと音を覚えておく ----
    //   止まっている間は数えない（含めない）。途切れ・リセット（アナ極へ戻る・跡を消す・遠くへ飛ぶ）があったら、そこから先だけにする
    @Published var keepLast = UserDefaults.standard.object(forKey: "s3walk.export.keepLast") as? Bool ?? true { didSet { UserDefaults.standard.set(keepLast, forKey: "s3walk.export.keepLast"); if !keepLast { ringClear(nil) } } }
    @Published private(set) var ringSeconds = 0.0
    fileprivate var ringFrames: [RecFrame] = [], ringBase: [SIMD4<Double>] = [], ringLastRaw: [SIMD4<Double>] = []
    private var ringAudio: [(b: AVAudioPCMBuffer, t: Double)] = []
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
        if jump || trailCut { ringClear(raw) }
        let speed = dtReal > 1e-6 ? moved / dtReal : 0
        ringMoving = speed > 0.004 && dtReal < 0.5
        guard ringMoving else { return }                                   // 止まっている間は覚えない
        ringVT += min(dtReal, 0.1); ringVTReal = now
        var f = f0; f.t = ringVT
        if ringLastRaw.isEmpty { f.trailAdd = raw; f.trailReset = true; ringBase = [] }
        else { f.trailAdd = Array(raw[min(raw.count, ringLastRaw.count)...]); f.trailReset = false }
        ringLastRaw = raw
        ringFrames.append(f)
        // 1 分より前は捨てる（捨てた分の跡は ringBase にまとめておく）
        while let first = ringFrames.first, first.t < ringVT - 60 {
            if first.trailReset { ringBase = first.trailAdd } else { ringBase += first.trailAdd }
            ringFrames.removeFirst()
        }
        let secs = (ringFrames.last?.t ?? 0) - (ringFrames.first?.t ?? 0)
        if abs(secs - ringSeconds) > 0.5 { ringSeconds = secs }
    }
    /// 直前の 1 分を書き出す
    func exportLast() {
        guard !recording, !rendering else { return }
        guard ringFrames.count >= 2 else { message = "まだ覚えている動きがありません（超球の窓を出して、少し走ってください）"; return }
        var fs = ringFrames
        var first = fs[0]; first.trailAdd = (first.trailReset ? [] : ringBase) + first.trailAdd; first.trailReset = true; fs[0] = first
        frames = fs
        let au = aq.sync { ringAudio }
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
        live.st.saveIfChanged()                                             // 今の設定を覚えてから、書き出し用の状態を同じ設定で作る
        let s2 = HyperLabState()
        guard let r = HyperLabRenderer(side: .right, state: s2, view: nil) else { message = note + "書き出しの準備ができませんでした"; return }
        let u: URL
        #if os(macOS)
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("球面さんぽ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        u = dir.appendingPathComponent(fileName())
        #else
        u = FileManager.default.temporaryDirectory.appendingPathComponent(fileName())
        #endif
        guard let wr = try? AVAssetWriter(outputURL: u, fileType: .mov) else { message = note + "動画を作り始められませんでした"; return }
        outW = uhd ? 3840 : 1920; outH = uhd ? 2160 : 1080
        let br = Int(mbps * 1_000_000)
        let nSec = gen != nil ? Double(genOut) / 60 : (frames[frames.count - 1].t - frames[0].t)
        // 空きが足りなければ始めない（書き出したあとも 5 GB 残す）
        if let free = (try? u.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           Double(free) < mbps / 8 * 1_000_000 * nSec * 1.1 + 5e9 {
            message = String(format: "空きが足りません（約 %.1f GB 必要）。画質を下げるか、空きを作ってください", mbps / 8 / 1000 * nSec * 1.1); gen = nil; genSnd?.stop(); genSnd = nil; frames = []; return }
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
        st2 = s2; r2 = r; cache = nil; lay = layout; force = forceDive; glass = InsetGlass(r.device)
        if force { s2.diveOn = true; s2.diveThird = true; s2.diveT = 1; s2.thirdK = 1; s2.diveFade = 0 }
        var c: CVMetalTextureCache?; CVMetalTextureCacheCreate(nil, nil, r.device, nil, &c); cache = c
        let t0 = frames[0].t, t1 = frames[frames.count - 1].t
        nOut = gen != nil ? genOut : max(1, Int((t1 - t0) * 60)); iOut = 0; jRec = 0; trail = []; appliedTo = -1; aIdx = 0; inFlight = 0; failed = false
        let al = aq.sync { audio }, makingSound = gen != nil && genSnd != nil; wq.sync { aList = al; audioDone = false; aLive = makingSound }                  // 記録した音（書き出し中は、書く糸の上だけで使う）
        r.walkOverride = { [weak self] in self?.curWalk ?? HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)) }
        progress = 0; rendering = true
        DispatchQueue.main.async { self.step() }
    }
    private var curWalk = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)), busySince = 0.0

    /// 1 コマ描いて、次へ（アプリが止まらないように、1 コマずつ順に）
    private func step() {
        guard rendering, let r = r2, let s2 = st2, let cache, let ad = adaptor, let vi = vIn else { return }
        if iOut >= nOut || wq.sync(execute: { failed }) { finishRender(); return }
        let busyNow = wq.sync { inFlight >= 3 || !vi.isReadyForMoreMediaData }
        if busyNow {
            // 待っている間も、音を少し先まで渡す（絵と音は交互に書く決まりなので、音が来ないと絵も受け取ってもらえない）
            if gen != nil && frames.count < iOut + 600 { for _ in 0..<6 { genFrame() } }   // 決まった道から作る時：待っている間に先へ歩いて、音を作り足す
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
        if gen != nil { while frames.count < iOut + 40 { genFrame() } }   // 0.6 秒先まで歩いておく（音を絵より先に渡すため）
        let t0 = frames[0].t, tq = t0 + Double(iOut) / 60
        while jRec + 1 < frames.count - 1 && frames[jRec + 1].t <= tq { jRec += 1 }
        // 跡：記録をたどって、ふえた分を足す
        while appliedTo < jRec + 1 && appliedTo + 1 < frames.count {
            appliedTo += 1; let fr = frames[appliedTo]
            if fr.trailReset { trail = fr.trailAdd } else { trail += fr.trailAdd }
            if appliedTo == jRec { break }
        }
        let a = frames[jRec], b = frames[min(frames.count - 1, jRec + 1)]
        let k = b.t > a.t ? max(0, min(1, (tq - a.t) / (b.t - a.t))) : 0
        apply(s2, a, b, k, camera: !force)
        if force {
            // ダイブしていなくても三人称のダイブで。カメラ（オートカメラ・ショーカメラ）は、書き出しの中で 1/60 秒ずつ動かす
            s2.diveOn = true; s2.diveT = 1; s2.thirdK = 1; s2.diveFade = 0
            s2.chaseDistS = s2.chaseDist; s2.chasePitchS = s2.chasePitch; s2.chaseYawS = s2.chaseYaw
        }
        var w = a.walk
        func nl(_ x: SIMD4<Double>, _ y: SIMD4<Double>) -> SIMD4<Double> { let m = x + (y - x) * k, l = simd_length(m); return l > 1e-9 ? m / l : y }
        w.pos = nl(a.walk.pos, b.walk.pos); w.fwd = nl(a.walk.fwd, b.walk.fwd); w.vR = nl(a.walk.vR, b.walk.vR); w.vU = nl(a.walk.vU, b.walk.vU); w.vL = nl(a.walk.vL, b.walk.vL)
        if let ha = a.walk.head, let hb = b.walk.head { w.head = nl(ha, hb) }
        w.dist = a.walk.dist + (b.walk.dist - a.walk.dist) * k; w.fov = a.walk.fov + (b.walk.fov - a.walk.fov) * k
        w.trail = Array(trail.prefix(max(0, trail.count - a.trailTrim)))
        curWalk = w
        r.clockOverride = tq; r.domOverride = a.dom + (b.dom - a.dom) * k
        if force { r.autoCamForTest(1.0 / 60) }
        // 描く
        var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        var cvt: CVMetalTexture?
        guard let pb, CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, outW, outH, 0, &cvt) == kCVReturnSuccess,
              let cv = cvt, let dst = CVMetalTextureGetTexture(cv), let cb = r.queue.makeCommandBuffer(), drawLayout(r, cb, dst, a) else {
            iOut += 1; DispatchQueue.main.async { self.step() }; return
        }
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
                while !vi.isReadyForMoreMediaData && tries < 3000 { self.pumpAudio(upTo: tf + 0.5); usleep(1000); tries += 1 }
                if vi.isReadyForMoreMediaData { if !ad.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60)) { self.failed = self.writer?.status != .writing } }
            }
        }
        cb.commit()
        feedAudio(upTo: tq - t0 + 0.25)
        iOut += 1
        if iOut % 6 == 0 { progress = Double(iOut) / Double(nOut) }
        DispatchQueue.main.async { self.step() }
    }
    /// 書き出しの 1 コマを、レイアウトに合わせて描く
    private func drawLayout(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) -> Bool {
        // 決まった道から作る時：当たったチェックポイントの光は、裏のさんぽの記録で（描く間だけ差しかえる。時刻は今の時計に合わせる）
        var keep: [(p: V4, t: Double, pole: Int)]? = nil
        if gen != nil {
            let up = ProcessInfo.processInfo.systemUptime, tq = Double(iOut) / 60
            keep = Journey.hitPulse; genHits.removeAll { tq - $0.t > 3 }
            Journey.hitPulse = genHits.filter { $0.t <= tq }.map { ($0.p, up - (tq - $0.t), $0.pole) }
        }
        defer { if let k = keep { Journey.hitPulse = k } }
        guard drawLayout0(r, cb, dst, rec) else { return false }
        if withText { drawHUD(r, cb, dst, rec) }
        if gen != nil, let g = glass { let b = genBright(iOut); if b < 0.999 { g.fade(cb, dst, 1 - b) } }   // 決まった道から作る時：フェードイン・アウト
        return true
    }
    private func drawLayout0(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) -> Bool {
        if lay == 0 { return r.renderExport(cb, into: dst, w: outW, h: outH, withMap: withMap) }
        // 超球の窓のレイアウト：左の列（幅は仕切りの比率）の上に地図、下にさんぽの景色、右の残りに大きくダイブ画面。すき間は黒
        guard let s2 = st2, let g = glass else { return false }
        let gap = max(2, outW / 480)
        let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX))), th = max(64, min(outH - 64, Int(Double(outH) * s2.splitY)))
        let rw = outW - lw - gap, bh = outH - th - gap
        g.clear(cb, dst)
        if let dive = r.paneTexture(rw, outH), r.renderExport(cb, into: dive, w: rw, h: outH, withMap: false) { g.copy(cb, dive, into: dst, x: lw + gap, y: 0, w: rw, h: outH) }
        if let map = r.overviewTexture(cb, lw, th) { g.copy(cb, map, into: dst, x: 0, y: 0, w: lw, h: th) }
        if let walk = r.walkSceneTexture(cb, lw, bh, cam: rec.walkCam) { g.copy(cb, walk, into: dst, x: 0, y: th + gap, w: lw, h: bh) }
        return true
    }
    /// 書き出しの絵の上の文字：画面と同じ見た目・同じ割合の大きさで（画面の点 → 書き出しの画素は、右の画面の高さの比）
    private var hud: ExportHUD? = nil, hudCoordT = -9.0, hudLapT = -9.0, hudAngT = -9.0, hudCoords = "", hudLap = "", hudAngles = "", hudP: SIMD4<Double>? = nil, hudSpd = 0.0
    private func drawHUD(_ r: HyperLabRenderer, _ cb: MTLCommandBuffer, _ dst: MTLTexture, _ rec: RecFrame) {
        guard let s2 = st2, let g = glass else { return }
        if hud == nil || hud!.w != outW || hud!.h != outH { hud = ExportHUD(r.device, outW, outH); hudCoordT = -9; hudLapT = -9; hudAngT = -9; hudP = nil; hudSpd = 0 }
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
            let gap = max(2, outW / 480)
            let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX)))
            dive = CGRect(x: lw + gap, y: 0, width: outW - lw - gap, height: outH)
        }
        // 文字の大きさ：画面の右の窓の幅と、動画の中のダイブ画面の幅の比（窓の幅に対して、画面と同じ大きさ。動画は 16:9 で高さの比は使えない）
        let k = dive.width / CGFloat(max(200, HyperLabRenderer.liveRightW)), ks = k * CGFloat(s2.uiScale)
        if lay == 1 {
            let gap = max(2, outW / 480)
            let lw = max(64, min(outW - 64, Int(Double(outW) * s2.splitX))), th = max(64, min(outH - 64, Int(Double(outH) * s2.splitY)))
            let map = CGRect(x: 0, y: 0, width: lw, height: th), walk = CGRect(x: 0, y: th + gap, width: lw, height: outH - th - gap)
            // さんぽの景色の極（色の点と名前。さんぽの窓と同じ）。カメラは記録したさんぽのカメラ
            if let wr = gen ?? HyperLabState.walkRendererGet?() {
                let saved = wr.cam; if let c = rec.walkCam { wr.cam = c }
                var ls = wr.poleLabels(aspect: Double(walk.width / max(1, walk.height)))
                wr.cam = saved
                let pen = HyperLabState.poleENNow
                if pen { for i in ls.indices { ls[i].name = MapRenderer.poleNameToEN(ls[i].name) } }
                hud.poles(ls, in: walk, k: k, serif: pen)
            }
            hud.caption("【全体像】4D の超球（ダイブ中も、外から見た全体）　ドラッグで見る向き", in: map, k: k)
            hud.caption("【さんぽの景色】今いる所から見た S³（歩くのはさんぽの窓・コントローラーで）", in: walk, k: k)
            hud.caption("【観察側】4D の超球（球殻を積む）　ドラッグで見る向き", in: dive, k: k)
        }
        // 走行中の座標（左上）・周回（右上）・角度の読み（左下）。ダイブ画面だけで左上に地図がある時は、座標は地図の下へ
        var cy = dive.minY + 40 * ks
        if lay == 0 && withMap { cy = max(cy, CGFloat(outW / 60 + outH / 4) + 12 * ks) }
        if !hudCoords.isEmpty {
            hud.box(hudCoords, font: ExportHUD.font(10.5 * ks, .medium, mono: true), color: ExportHUD.rgb(0.62, 0.92, 1.0), x: dive.minX + 12 * ks, y: cy,
                    padH: 9 * ks, padV: 6 * ks, lineGap: 2 * ks, bg: ExportHUD.rgb(0, 0, 0, 0.42), stroke: ExportHUD.rgb(0.4, 0.85, 1.0, 0.35), strokeW: ks, radius: 6 * ks,
                    glow: ExportHUD.rgb(0.3, 0.8, 1.0, 0.7), glowR: 3 * ks)
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
        for i in 0..<a.f.count {
            var y = b.f[i]; let x = a.f[i]
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
        s.cutPos = v[24]; s.cutPhi = v[25]
        s.cometDir = a.cometDir + (b.cometDir - a.cometDir) * k
        if s.layers != a.layers { s.layers = a.layers }; if s.lzw != a.lzw { s.lzw = a.lzw }
        s.version = a.version; if camera { s.diveOn = a.diveOn; s.diveDragging = a.dragging }; s.padHolding = a.padHolding
    }
    /// 音：書き出した絵の時刻より少し先まで、記録した音を足す
    private func feedAudio(upTo tRel: Double) { wq.async { self.pumpAudio(upTo: tRel) } }
    /// （書く糸の上で）受け取れる間、記録した音を tRel 秒まで足す
    private func pumpAudio(upTo tRel: Double) {
        guard let ai = aIn, let t0 = audioT0 else { return }
        while aIdx < aList.count, ai.isReadyForMoreMediaData {
            let (b, t) = aList[aIdx]
            if t - t0 > tRel { break }
            aIdx += 1
            if t < t0 { continue }
            if let sb = Self.sampleBuffer(b, CMTime(seconds: t - t0, preferredTimescale: CMTimeScale(b.format.sampleRate))) { ai.append(sb) }
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
                    self.writer = nil; self.vIn = nil; self.aIn = nil; self.adaptor = nil; self.r2 = nil; self.st2 = nil
                    self.frames = []; self.lastRaw = []; self.aq.sync { self.audio = [] }; self.gen = nil; self.genTpl = nil; self.genSt = nil; self.genSnd?.stop(); self.genSnd = nil; self.genHits = []
                    self.rendering = false; self.progress = 1
                    self.saved(ok, err, n, u, note)
                }
            }
        }
    }
    private func saved(_ ok: Bool, _ err: String, _ n: Int, _ u: URL?, _ note: String) {
        lastURL = ok ? u : nil
        guard ok, let u else { message = note + "動画を書き出せませんでした：\(err)"; return }
        #if os(macOS)
        message = note + "動画を作りました（16:9・\(outW)×\(outH)・60 コマ・\(n) コマ）：\(u.path)"
        if !CommandLine.arguments.contains("--exporttest") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        #else
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
        return (sim, nil)
    }
    fileprivate(set) var genOut = 0
    /// 別のさんぽで歩いてみて、終わるコマ（1 周か、決めた長さ）を知る。info：道のりと、出発点との差（確かめ用）
    private func measure(_ dev: MTLDevice, _ set: Settings) -> ((end: Int, found: Bool, info: String)?, String?) {
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
        return ((end, found, info), nil)
    }
    func exportRoute() {
        guard !recording, !rendering else { return }
        guard let live = HyperLabRenderer.liveMain, let tpl = live.recordFrame(), let wr = HyperLabState.walkRendererGet?() else {
            message = "超球の窓とさんぽが見つかりませんでした"; return }
        // 先に別のさんぽで歩いてみて、1 周（または決めた長さ）が何コマかを知る
        let (mm, e1) = measure(live.device, wr.set)
        guard let mm else { message = e1; return }
        let (end, found) = (mm.end, mm.found)
        let (sim, e2) = makeSim(live.device, wr.set)
        guard let sim else { message = e2; return }
        genOut = end + Self.genFO
        gen = sim; genTpl = tpl; genCs = nil; genSpd = 0; genFreed = 0; appliedTo = -1; genLW = LapWatch(); genLapN = 1
        frames = []; lastRaw = []; aq.sync { audio = [] }
        live.st.saveIfChanged()
        let gs = HyperLabState(); gs.zw = live.st.zw; gs.pitch = live.st.pitch; gs.roll = live.st.roll; gs.yaw = live.st.yaw; gs.cutPos = live.st.cutPos
        gs.auto = live.st.auto; gs.followOn = live.st.followOn; gs.followSlack = live.st.followSlack; gs.followSpeed = live.st.followSpeed; gs.followHeading = live.st.followHeading; gs.followDrift = live.st.followDrift
        gs.cutOn = live.st.cutOn; gs.cutSweep = live.st.cutSweep; gs.cutKind = live.st.cutKind; genSt = gs
        genSnd = nil; genAFmt = nil; gsPos = nil; gsFwd = nil; gsTurn = 0; gsSpeed = 0; gsWobT = -9; gsIceT = -9; genHits = []
        if live.st.soundOn {                                                // 音：超球の窓で音を入れている時は、同じ音を作って入れる
            let snd = HyperSound(); snd.spatial = live.st.soundSpatial; gsVol = live.st.soundVol
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
    /// 裏のさんぽを 1/60 秒進めて、1 コマ分を覚える
    private func genFrame() {
        guard let sim = gen, var f = genTpl else { return }
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
        if let p0 = genCs { let d = simd_length(w.pos - p0); genSpd += (min(1, ((d > 0.5 ? 0 : d / dt) / 1.4).squareRoot()) - genSpd) * (1 - exp(-dt * 3)) }   // 彗星の速さ（超球の窓と同じ決め方）
        genCs = w.pos
        for h in hits { genHits.append((h.p, t, h.pole)) }
        if let gs = genSt {                                                 // 超球の向き：超球の窓と同じく、自動で回す・自分（裏のさんぽ）を追う
            gs.tick(dt); gs.tickCut(dt); gs.tickFollow(dt, walk: w)
            f.f[16] = gs.zw; f.f[17] = gs.pitch; f.f[18] = gs.roll; f.f[19] = gs.yaw; f.f[24] = gs.cutPos; f.version = gs.version
        }
        f.t = t; f.dom = genSound(w, t, hits) ?? t / 4; f.f[14] = genSpd; f.walkCam = sim.cam
        var wk = w; wk.trail = []; f.walk = wk; f.trailTrim = 0
        let raw = w.trail
        if !lastRaw.isEmpty, raw.count >= lastRaw.count, raw[lastRaw.count - 1] == lastRaw[lastRaw.count - 1] {
            f.trailAdd = Array(raw[lastRaw.count...]); f.trailReset = false
        } else { f.trailAdd = raw; f.trailReset = true }
        lastRaw = raw
        frames.append(f)
        while genFreed < appliedTo - 1 { frames[genFreed].trailAdd = []; genFreed += 1 }   // 描き終えたコマの跡は手放す（長い道でもメモリがふえない）
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
        if let f0 = gsFwd, simd_length(w.vR) > 0.5 { let df = hd - f0; tr = simd_length(df) > 0.5 ? 0 : simd_dot(df, w.vR) / dt }
        gsFwd = hd
        gsTurn += (tr - gsTurn) * (1 - exp(-dt * 4)); gsSpeed += (sp - gsSpeed) * (1 - exp(-dt * 6))
        let trn = max(-1, min(1, gsTurn / 1.2)), spd01 = min(1, (gsSpeed / 1.4).squareRoot())
        let zoom = HyperLabRenderer.diveEase(forceDive ? 1 : (st2?.diveT ?? 1)).1
        if t - gsWobT > 1.2 && spd01 > 0.25 && (abs(trn) > 0.55 || Double.random(in: 0..<1) < dt * 0.12 * spd01) { snd.shellPass(); gsWobT = t }
        if zoom > 0.5 && t - gsIceT > 1.8 && spd01 > 0.3 && abs(trn) > 0.25 && Double.random(in: 0..<1) < dt * 0.9 * abs(trn) { snd.icePop(); gsIceT = t }
        snd.update(speed: spd01, zoom: zoom, turn: trn, near: st2?.cometNear ?? 0.5, volume: gsVol * Double(genBright(frames.count)))   // 音もフェードイン・アウト
        var d = st2?.cometDir ?? SIMD3<Double>(0, 0, -1); d.x -= 0.7 * trn                 // 彗星の方向から（少し前のコマの向き）
        let dl = simd_length(d); if dl > 1e-6 { d /= dl }
        snd.setPosition(SIMD3<Float>(d * 1.5))
        for h in hits { snd.chime(pole: h.pole) }
        guard let b = snd.renderOffline(Int((fmt.sampleRate * dt).rounded())) else { return nil }
        if rendering { wq.async { self.aList.append((b, t)) } } else { aq.sync { audio.append((b, t)) } }   // 書き出しが始まる前の分は、始める時に渡す
        let bc = snd.beatClock()
        return bc.rate > 0.05 ? bc.cyc / 6 : nil
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
            if var fr = r.recordFrame() { fr.t = t0 + t; ex.ringCapture(fr) }
        }
        print(String(format: "直前の 1 分：%.2f 秒ぶん・%d コマ（飛んだあとの 5 秒だけのはず）", ex.ringSeconds, ex.ringFrames.count))
        ex.exportLast()
        let limit = Date().addingTimeInterval(600)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")")
        return ex.lastURL
    }
    /// 確かめ（--exporttest --route）：極めぐりを 8 秒、超球の窓のレイアウトで（さんぽの景色も裏のさんぽで描く）
    static func selfTestRoute(seconds: Double = 0) -> URL? {
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
        if let i = CommandLine.arguments.firstIndex(of: "--quality") { ex.quality = Int(CommandLine.arguments[i + 1]) ?? 1 }
        ex.uhd = CommandLine.arguments.contains("--4k"); ex.layout = 1; ex.forceDive = true; ex.genPath = PathMode.tour.rawValue; ex.genSeconds = seconds
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
        let limit = Date().addingTimeInterval(600)
        while ex.rendering && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        print("1 周：\(ex.genOut) コマ（フェードイン \(genFI)・アウト \(genFO)）")
        print("書き出しの確かめ：\(ex.message ?? "（知らせなし）")・さんぽ本体は動いていない：\(wr.pathMode == .none && wr.journey.dist == 0)")
        return ex.lastURL
    }
    static func selfTest(uhd: Bool, seconds: Double, layout: Int = 0, force: Bool = false) -> URL? {
        let ex = VideoExport.shared
        let st = HyperLabState(); st.walk = true; st.diveOn = true; st.diveT = 1; st.diveThird = true; st.thirdK = 1; st.planOn = true
        guard let r = HyperLabRenderer(side: .right, state: st, view: nil) else { return nil }
        var w = HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1))
        r.walkOverride = { w }
        HyperLabRenderer.liveMain = r
        ex.uhd = uhd; ex.withMap = true; ex.layout = layout; ex.forceDive = force
        if force { st.diveOn = false; st.diveT = 0; st.thirdK = 0 }                // 記録の間はダイブしていない（書き出しでダイブにする）
        ex.frames = []; ex.lastRaw = []; ex.recording = true
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        ex.audioFormat = fmt; ex.audio = []
        let t0 = CACurrentMediaTime(), n = Int(seconds * 30)
        var trail: [SIMD4<Double>] = []
        for i in 0...n {                                                   // 30 コマで記録（まばら）→ 書き出しは 60 コマ
            let a = Double(i) / 30 * 0.3, p = SIMD4(sin(a), 0, 0, cos(a)), f = SIMD4(cos(a), 0, 0, -sin(a))
            trail.append(p)
            w = HyperLabState.Walk(trail: trail, pos: p, head: f, fwd: f, vR: SIMD4(0, 1, 0, 0), vU: SIMD4(0, 0, 1, 0), vL: f,
                                   plan: (0..<60).map { k in let b = a + Double(k) * 0.02; return SIMD4(sin(b), 0.2 * sin(b * 3), 0, cos(b)) }, dist: a)
            HyperLabState.walkSource = { w }
            if var fr = r.recordFrame() { fr.t = t0 + Double(i) / 30; ex.capture(fr) }
        }
        var tt = t0
        while tt < t0 + seconds + 0.1 {                                    // 音：440 Hz の正弦波
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!; b.frameLength = 1024
            for c in 0..<2 { for k in 0..<1024 { b.floatChannelData![c][k] = Float(0.2 * sin(2 * .pi * 440 * (tt - t0 + Double(k) / 48000))) } }
            ex.audio.append((b, tt)); tt += 1024.0 / 48000
        }
        ex.recording = false
        ex.startRender("")
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
        d.fragmentFunction = lib.makeFunction(name: "plainF"); d.colorAttachments[0].isBlendingEnabled = false
        plain = try? device.makeRenderPipelineState(descriptor: d)
    }
    private var plain: MTLRenderPipelineState?, fadeP: MTLRenderPipelineState?, overP: MTLRenderPipelineState?
    /// 文字の絵（同じ大きさ）を dst 全体に重ねる
    func over(_ cb: MTLCommandBuffer, _ src: MTLTexture, _ dst: MTLTexture) {
        guard let overP else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        e.setRenderPipelineState(overP); e.setFragmentTexture(src, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    /// dst 全体を黒へ a だけ近づける（フェード）
    func fade(_ cb: MTLCommandBuffer, _ dst: MTLTexture, _ a: Float) {
        guard let fadeP else { return }
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .load; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        var k = SIMD4<Float>(a, 0, 0, 0)
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
    /// dst を黒で塗る（レイアウトのすき間）
    func clear(_ cb: MTLCommandBuffer, _ dst: MTLTexture) {
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1); rp.colorAttachments[0].storeAction = .store
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

/// 動画を作るボタン：🎬 動画を作る（記録）／ ■ 止めて書き出す（記録している間は赤く、経った時間）／ 書き出し中は進み具合
struct ExportButton: View {
    @ObservedObject var ex = VideoExport.shared
    var body: some View {
        Button { ex.toggle() } label: {
            if ex.recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let s = Int(Date().timeIntervalSince(ex.started))
                    Label(String(format: "止めて書き出す %d:%02d", s / 60, s % 60), systemImage: "stop.circle.fill").foregroundStyle(.red)
                }
            } else if ex.rendering {
                Label(String(format: "書き出し中 %.0f%%", ex.progress * 100), systemImage: "hourglass")
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
        return .init(trail: r.journey.trail, pos: r.cam.w.p, marks: r.journey.marks + r.journey.routePts, hit: r.journey.marks.map { r.journey.isHit($0) } + r.journey.routePts.map { r.journey.isRouteHit($0) }, poles: r.journey.polesHit, lap: r.journey.lap, head: r.cam.lookFrame().L, space: r.set.space, fwd: r.cam.w.f, vR: r.cam.viewFrame().R, vU: r.cam.viewFrame().U, vL: r.cam.viewFrame().L, fov: r.set.fov, plan: HyperLabState.planWanted ? r.plannedPath() : [], dist: r.journey.dist, rail: HyperLabState.railWanted ? r.railPath() : [])
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
                Picker("道", selection: Binding(get: { ex.genPath == PathMode.custom.rawValue ? "r:" + ex.genRoute : "m:\(ex.genPath)" },
                                                set: { v in if v.hasPrefix("r:") { ex.genPath = PathMode.custom.rawValue; ex.genRoute = String(v.dropFirst(2)) } else { ex.genPath = Int(v.dropFirst(2)) ?? PathMode.tour.rawValue } })) {
                    ForEach([(PathMode.tour, "極めぐり"), (.spiral, "螺旋"), (.ring, "回る輪"), (.half, "半周のターン"), (.cube, "超立方体の辺めぐり"), (.cell24, "二十四胞体の辺めぐり")], id: \.0.rawValue) { m, n in Text(n).tag("m:\(m.rawValue)") }
                    ForEach(store.routes.filter { !$0.pts.isEmpty }) { rt in Text("自分の道「\(rt.name)」").tag("r:" + rt.id.uuidString) }
                }.labelsHidden().frame(maxWidth: 200)
                Picker("長さ", selection: $ex.genSeconds) { Text("1 周").tag(0.0); Text("2 周").tag(-1.0); Text("30 秒").tag(30.0); Text("1 分").tag(60.0); Text("2 分").tag(120.0); Text("5 分").tag(300.0) }.labelsHidden().frame(width: 80)
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
                Text("動画を作る（記録 → 書き出し）").font(.headline)
                Text("走っている間は動きと音だけを覚え、止めたあとで 60 コマ・最高の細かさで描き直します。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { ExportButton(); Spacer() }
                HStack {
                    Button { ex.exportLast() } label: { Label(String(format: "直前の 1 分を書き出す（%.0f 秒ぶん）", ex.ringSeconds), systemImage: "gobackward.60") }
                        .font(.caption).disabled(!ex.keepLast || ex.recording || ex.rendering || ex.ringSeconds < 1)
                        .help("裏でいつも覚えている、直前 1 分ぶんの走り（止まっていた間は含めず、途切れ・リセットのあとだけ）を、すぐ描き直して動画にする")
                    Spacer()
                }
                Toggle("直前の 1 分をいつも覚えておく", isOn: $ex.keepLast).disabled(ex.rendering)
                GenRouteRow()
                    .help("超球の窓を出している間、動いている時の直前 1 分ぶんの動きと音を、裏でいつも覚えておく（絵は描かないので軽い。メモリを 40 MB ほど使う）")
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
                Toggle("画面の文字も入れる（座標・周回・極の名前・見出し）", isOn: $ex.withText).disabled(ex.recording || ex.rendering)
                    .help("超球の窓の上に出ている文字（走行中の座標・周回・角度の読み・窓の見出し）と、さんぽの景色の極の点と名前を、画面と同じ見た目で動画にも描き込む")
                Toggle("左上に小さく地図（ダイブ画面だけの時）", isOn: $ex.withMap).disabled(ex.recording || ex.rendering || ex.layout != 0)
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
