// 4D 球アナロジーの音：音の素材は使わず、その場で合成する。
//   風切り音：宇宙に空気はないけれど、空気を押し切って進むように。雑音から 4 つの層を作る。
//     圧（低いうなり）：前の空気を押す重い音。速さの 2 乗で大きくなる（空気抵抗は速さの 2 乗）。
//     流れ（中の帯）：体のまわりを流れる空気。速いほど高く。
//     乱れ（高いシュー）：ちぎれる渦。ゆっくり変わる突風（ゆらぎ）で大きさと高さがふらつく。
//     曲がり：向きを変える速さで、流れの高さが滑るように上がり、曲がる側（外側）へ音が寄って、ひと吹き強まる（翼が空気をつかむように）。
//     揺さぶり：走る車の窓を少し開けた時の「ボボボ」。低い流れを 9〜20 Hz で脈打たせる（速いほど速く・強く、少しずつずれる）。
//     ゴーッ：桃色寄りの重い雑音（低い方が強い）。速さで太くなる。
//     隕石らしさ：表面が焼けてはじける「パチパチ」（まばらな小さな破裂。速さの 2 乗で増える）と、熱い空気の「ジリジリ」（高いざらつき）。
//   ズーム（ダイブ）で寄るほど大きく近く、外から眺めている時は控えめ。
//   チリン：チェックポイントに当たった瞬間に、短いベルの音（極ごとに音の高さを変える。目印は高い音）。
//   場所の音：w の高さで音色が変わる（アナ極の側は明るく軽く、カタ極の側は暗く重く）。入れていれば、球層を横切るたびに小さく「スッ」と鳴る。
//   低音：圧・ゴーッ・ばたつき・エンジンの低い音をまとめて強める（1 が元のまま）。
//   ひねり：上下・左右のどちらへでも、向きが変わる速さに合わせて、風の帯が上がって大きくなる（すっと強まって、ゆっくり戻る）。
//   ガラララッ：荒れた路面を走るような、不ぞろいな連打の風切り。速さの 2 乗で強く、カーブで強まる（荒さで大きさを変える）。
//   描く側（毎コマ）から update・chime で目標を渡し、音を作る側（音の糸）はそれをなめらかに追う。
//   空間オーディオ（spatial）：1 つの音（モノ）にして、AVAudioEnvironmentNode の頭の伝達関数（HRTF）で、彗星のいる方向から聞こえるように。
//     左右だけでなく上下・前後も分かる（ヘッドホンで）。広い場所の残響を少し。切ると、前の左右のステレオ。
import AVFoundation
import QuartzCore

final class HyperSound {
    static let shared = HyperSound()
    private var engine: AVAudioEngine?
    private var node: AVAudioSourceNode?
    private var envNode: AVAudioEnvironmentNode?
    private var flyNode: AVAudioSourceNode?                            // 極のドップラーの音（風とは別の場所から鳴らす）
    /// 空間オーディオで鳴らす（切りかえたら、鳴らし直す）
    var spatial = true { didSet { if spatial != oldValue && running { stop(); start() } } }
    /// 描く側が書き、音の糸が読む目標（Float の読み書きだけ。少し古い値を読んでも音は崩れない）
    private final class Target { var phones: Float = 0; var rush: Float = 0; var gain: Float = 0; var cutoff: Float = 400; var turn: Float = 0; var press: Float = 0; var vol: Float = 0.8; var near: Float = 1; var zoom: Float = 0; var height: Float = 0; var layer = 0; var bass: Float = 1; var rough: Float = 1; var swing: Float = 0; var kick = 0; var ice = 0; var air: Float = 1; var flyA: Float = 0; var flyF: Float = 200; var song: Float = 0; var wind: Float = 1; var railK: Float = 0; var rail = 0; var scan = [Float](repeating: 0, count: 64); var chimes: [(f: Float, a: Float)] = []; var beatCyc = 0.0; var beatRate = 0.0; var beatStamp = 0.0; let lock = NSLock() }
    private let tgt = Target()
    private(set) var running = false

    /// 鳴らし始める（入れた時）。失敗しても黙って何もしない
    func start() {
        guard !running else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])   // ほかの音楽と一緒に鳴る・消音スイッチに従う
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let e = AVAudioEngine()
        let sr = e.outputNode.outputFormat(forBus: 0).sampleRate
        guard let (n, fmt) = makeNode(Float(sr > 0 ? sr : 48000), mono: spatial) else { return }
        e.attach(n)
        if spatial { envNode = attachSpatial(e, n, fmt) } else { e.connect(n, to: e.mainMixerNode, format: fmt) }
        attachFly(e, Float(sr > 0 ? sr : 48000))
        do { try e.start() } catch { return }
        engine = e; node = n; running = true
    }
    /// 空間オーディオ：音 → 環境（HRTF・広い場所の残響を少し）→ 出力。距離で小さくするのは自分でやるので、環境では減らさない
    private func attachSpatial(_ e: AVAudioEngine, _ n: AVAudioSourceNode, _ fmt: AVAudioFormat) -> AVAudioEnvironmentNode {
        let env = AVAudioEnvironmentNode()
        e.attach(env)
        e.connect(n, to: env, format: fmt)
        e.connect(env, to: e.mainMixerNode, format: nil)
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.distanceAttenuationParameters.rolloffFactor = 0
        env.reverbParameters.enable = true; env.reverbParameters.loadFactoryReverbPreset(.largeHall2); env.reverbParameters.level = -8
        n.renderingAlgorithm = .HRTFHQ
        if #available(macOS 13.0, iOS 16.0, *) { n.sourceMode = .pointSource }
        n.reverbBlend = 0.22
        n.position = AVAudio3DPoint(x: 0, y: 0, z: -1.5)
        return env
    }
    /// 極のドップラーの音をつなぐ（空間オーディオなら環境へ、切っていれば左右の振り分けで）
    private func attachFly(_ e: AVAudioEngine, _ rate: Float) {
        guard let (n, fmt) = makeFly(rate) else { return }
        e.attach(n)
        if let env = envNode {
            e.connect(n, to: env, format: fmt)
            n.renderingAlgorithm = .HRTFHQ
            if #available(macOS 13.0, iOS 16.0, *) { n.sourceMode = .pointSource }
            n.reverbBlend = 0.35
        } else { e.connect(n, to: e.mainMixerNode, format: fmt) }
        flyNode = n
    }
    /// ドップラーの音：高さ hz・大きさ amp（0 で無音）・聞く人から見た場所
    func setFly(hz: Double, amp: Double, at p: SIMD3<Float>) {
        tgt.lock.lock(); tgt.flyF = Float(hz); tgt.flyA = Float(amp); tgt.lock.unlock()
        guard let n = flyNode else { return }
        if spatial { n.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z) } else { n.pan = max(-1, min(1, p.x)) }
    }
    /// 極を通り過ぎる音の計算。pos：今いる所、head：進む向き、right・up：聞く人の右と上、feel：勢い（0〜1）。
    ///   いちばん近い極の方向へ進む速さから高さを決める（近づくと高く、離れると低く）。本当は極は鳴らないのでエンタメ。
    ///   カタ星だけは前後を反対に置いて、後ろから追いかけてきて追い抜くように聞かせる（高さの変わり方は同じ）
    static func flyPass(_ pos: SIMD4<Double>, head: SIMD4<Double>, right: SIMD4<Double>, up: SIMD4<Double>, feel: Double) -> (hz: Double, amp: Double, at: SIMD3<Float>) {
        var best: (d: Double, c: SIMD4<Double>)? = nil
        for m in FIXED { let d = acos(max(-1, min(1, simd_dot(pos, m.c)))); if best == nil || d < best!.d { best = (d, m.c) } }
        guard let b = best else { return (200, 0, SIMD3(0, 0, -1.5)) }
        let rel = b.c - pos * simd_dot(pos, b.c), l = simd_length(rel), dir = l > 1e-6 ? rel / l : head
        let closing = max(-1, min(1, simd_dot(head, dir)))
        let kata = b.c.w < -0.9, wPole = abs(b.c.w) > 0.9
        let ratio = max(0.6, min(1.7, 1 / (1 - 0.45 * closing * min(1, feel))))
        let t = max(0, min(1, (b.d - 0.1) / 0.65)), q = 1 - t * t * (3 - 2 * t)
        let amp = q * q * min(1, feel * 1.6) * (wPole ? 1 : 0.55)
        let r = 0.4 + 1.1 * min(1, b.d / 0.5)
        let x = simd_dot(dir, right), y = simd_dot(dir, up), z = -simd_dot(dir, head) * (kata ? -1 : 1)
        return ((kata ? 150 : wPole ? 240 : 320) * ratio, amp, SIMD3<Float>(Float(x * r), Float(y * r), Float(z * r)))
    }
    /// 通り過ぎる音を作る節：空気だけの帯（音程のあるうなりを混ぜると、通り過ぎるバイクに聞こえるので入れない）
    private func makeFly(_ rate: Float) -> (AVAudioSourceNode, AVAudioFormat)? {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1) else { return nil }
        var a: Float = 0, f: Float = 200, lo: Float = 0, bd: Float = 0, seed: UInt32 = 0x51D7A3C1
        let t = tgt, dt = 1 / rate
        let ka = 1 - exp(-dt * 12), kf = 1 - exp(-dt * 7)                     // 大きさはすっと、高さはなめらかに滑る
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 1, let L = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            t.lock.lock(); let ta = t.flyA * t.vol, tf = t.flyF; t.lock.unlock()
            for i in 0..<Int(frames) {
                a += (ta - a) * ka; f += (tf - f) * kf
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let wn = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                let fb = min(0.9, 2 * sin(Float.pi * f * 6 / rate))
                lo += fb * bd; let hi = wn - lo - 0.3 * bd; bd += fb * hi
                L[i] = tanh(bd * 0.5 * a)
            }
            for b in bufs.dropFirst() { if let R = b.mData?.assumingMemoryBound(to: Float.self) { for i in 0..<Int(frames) { R[i] = L[i] } } }
            return noErr
        }
        return (n, fmt)
    }
    /// 動画の書き出し用：出口の手前（ミキサー）の音の形。鳴っていない時は nil
    func tapFormat() -> AVAudioFormat? { guard running, let e = engine else { return nil }; return e.mainMixerNode.outputFormat(forBus: 0) }
    /// 動画の書き出し用：出口の手前の音を写し取る（止めるまで）
    func tap(_ f: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        guard let e = engine else { return }
        let m = e.mainMixerNode; m.removeTap(onBus: 0)
        m.installTap(onBus: 0, bufferSize: 2048, format: m.outputFormat(forBus: 0)) { b, t in f(b, t) }
        tapped = true
    }
    func untap() { engine?.mainMixerNode.removeTap(onBus: 0); tapped = false }
    private(set) var tapped = false
    /// エンジンの低いうなりのリズム（何回目か・速さ Hz・知らせた時刻）。音が鳴っていない時は時刻が古いまま
    func beatClock() -> (cyc: Double, rate: Double, stamp: Double) {
        tgt.lock.lock(); defer { tgt.lock.unlock() }
        return (tgt.beatCyc, tgt.beatRate, tgt.beatStamp)
    }
    /// 空間オーディオの音の場所（聞く人から見て：x 右・y 上・−z 前。長さは 1 くらい）
    func setPosition(_ p: SIMD3<Float>) {
        guard spatial, let n = node else { return }
        n.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
    }
    /// 音を作る節（シュー・チリン）。rate は 1 秒の標本の数
    ///   mono：空間オーディオ用に 1 つの音で（左右の振り分けは環境がする）
    private func makeNode(_ rate: Float, mono: Bool = false) -> (AVAudioSourceNode, AVAudioFormat)? {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: mono ? 1 : 2) else { return nil }
        // 音の糸の中だけで使う状態
        var g: Float = 0, fc: Float = 400, tn: Float = 0, pr: Float = 0, ht: Float = 0, bs: Float = 1, rg: Float = 1, sw: Float = 0   // ht：w の高さ（−1〜1）、bs：低音の倍率、rg：荒さ、sw：ひねり
        var lyT: Float = 9, lyL: Float = 0, lyB: Float = 0                      // 球層を横切る「スッ」（鳴り始めからの時間・帯域）
        var rtPh: Float = 0, rtA: Float = 1, rt1: Float = 0, rt2: Float = 0    // ガラララッ（連打の位相・1 打の強さ・2 段の低域）
        var jr1: Float = 0, jr2: Float = 0, jtLo: Float = 0, jtB: Float = 0     // 直線の突進音（低いゴォォ・空気の帯）
        var rtL: Float = 0, hpK: Float = 0, rsK: Float = 0                                     // ヘッドホン用：ガラララッの低い所を抜く分・効き（0〜1）
        var low: Float = 0, band: Float = 0, low2: Float = 0, band2: Float = 0      // 流れ（2 段の帯域）
        var hl: Float = 0, hb: Float = 0                                       // 乱れ（高い帯域）
        var rl1: Float = 0, rl2: Float = 0                                     // 圧（低い 2 段の低域）
        var gust: Float = 0, gust2: Float = 0, flut: Float = 0                 // 突風（ゆっくり）・はためき（速め）のゆらぎ
        var buf: Float = 0, rr1: Float = 0, rr2: Float = 0, rr3: Float = 0     // 揺さぶりの位相・ゴーッ（3 段の低域）
        var crk: Float = 0, crkEnv: Float = 0, cl: Float = 0, cb: Float = 0, sizz: Float = 0   // パチパチ（破裂の大きさ・減り・帯域）・ジリジリ
        var wob: Float = 0, wobPh: Float = 0                                   // 低音のゆらぎ（1 → 0）
        var en1: Float = 0, en2: Float = 0, en3: Float = 0, enS: Float = 0, enPrev: Float = 0, enAcc: Float = 0   // 宇宙船のエンジン（3 つの位相・ならした速さ・加速）
        var beat = 0.0, beatF: Float = 0                                       // エンジンの 2 つの低い音のうなり（何回目か。整数の時が山）・うなりの速さ（Hz）
        var bf1: Float = 0, bf2: Float = 0, btm: Float = 0, btm2: Float = 0    // 窓から顔を出した時の風：耳にぶつかる低いばたつき（2 段の低域・不規則な揺れ 2 つ）
        var seed: UInt32 = 0x9E3779B9, ph: Float = 0, wa: Float = 0, wb: Float = 1.7, nr: Float = 0   // wa・wb：寄せては返す波の位相、nr：近さ（チリンの大きさ）
        var voices: [(f: Float, a: Float, p: Float, t: Float)] = []
        // シュパッ（氷がはじける）：高い風切り（帯の高さが下がる）→ 小さな破裂と、氷のかけらのきらめき（高い音がいくつか、すぐ消える）
        var airG: Float = 1
        var rlT: Float = 9, rlA: Float = 0, rlF: Float = 1500, rlL: Float = 0, rlB: Float = 0   // 線路の音（鳴り始めからの時間・大きさ・高さ・帯域）
        // 渦の歌：流体の渦を 1 周読んだ形を波形にして、低い和音で鳴らす（tA → tB を 1 回の間になめらかにつなぐ）
        var scA = [Float](repeating: 0, count: 65), scB = scA, scT = [Float](repeating: 0, count: 64), scP = [Float](repeating: 0, count: 6)
        var sg: Float = 0, wd: Float = 1, soL: Float = 0, soB: Float = 0, soL2: Float = 0, soB2: Float = 0
        var scSaw = [Float](repeating: 0, count: 64)                            // 流れが静かな時も鳴る芯（のこぎりの波）
        for k in 0..<64 { for h in 1...12 { let a: Float = 2 * Float.pi * Float(k * h) / 64; scSaw[k] += sin(a) / Float(h) } }
        let scRatio: [Float] = [1, 1.5, 2.004, 3.006, 3.994, 6.01], scGain: [Float] = [0.8, 0.55, 0.9, 0.6, 0.45, 0.3]
        var iceT: Float = 9, iceL: Float = 0, iceB: Float = 0, iceF: [Float] = [], iceP: [Float] = []
        let t = tgt
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 1, let L = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let R = bufs.count >= 2 ? bufs[1].mData?.assumingMemoryBound(to: Float.self) : nil   // nil：空間オーディオ（1 つの音）
            t.lock.lock(); let tg = t.gain * t.vol, tc = t.cutoff, tt = t.turn, tp = t.press * t.vol, vol = t.vol, tnr = t.near, tzm = t.zoom, tht = t.height, tbs = t.bass, trg = t.rough, tph = t.phones, trs = t.rush, tsw = t.swing, tair = t.air, tsg = t.song, twd = t.wind; for k in 0..<64 { scT[k] = t.scan[k] }; let kicks = t.kick; t.kick = 0; let rails = t.rail; t.rail = 0; let trk = t.railK; let lays = t.layer; t.layer = 0; let ices = t.ice; t.ice = 0; let new = t.chimes; t.chimes = []; t.lock.unlock()
            for c in new where voices.count < 8 { voices.append((c.f, c.a * vol, 0, 0)) }
            if kicks > 0 { wob = 1 }
            if lays > 0 { lyT = 0 }
            if rails > 0 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; rlT = 0; rlA = 0.7 + 0.3 * Float(seed & 0xFF) / 255; rlF = 1300 + 700 * Float((seed >> 8) & 0xFF) / 255 }
            if ices > 0 {
                iceT = 0; iceF = []; iceP = []
                for _ in 0..<4 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; iceF.append(2800 + 4200 * Float(seed & 0xFFFF) / 65535); iceP.append(0) }
            }
            let kg = 1 - exp(-1 / (rate * 0.12)), kc = 1 - exp(-1 / (rate * 0.09)), kt = 1 - exp(-1 / (rate * 0.18))   // なめらかに追う（風は急には変わらない）
            let dt = 1 / rate
            let kScan = 1 - exp(-Float(frames) * dt * 14)                     // 渦の形は 60 コマで変わるので、音の中でなめらかに追う
            for k in 0..<64 { scA[k] = scB[k]; scB[k] += (0.5 * scSaw[k] + 0.9 * scT[k] - scB[k]) * kScan }
            scA[64] = scA[0]; scB[64] = scB[0]
            let kSwUp = 1 - exp(-dt * 12), kSwDn = 1 - exp(-dt * 2.5)   // ひねり：すっと強まって、ゆっくり戻る
            let kAir = 1 - exp(-dt * 40)                                      // 空気の力は速く追う（渦のゆれが聞こえるように）
            let kGust = 1 - exp(-dt * 1.3), kGust2 = 1 - exp(-dt * 0.35), kFlut = 1 - exp(-dt * 9)
            var sL: Float = 0, sR: Float = 0
            for i in 0..<Int(frames) {
                airG += (tair - airG) * kAir
                sg += (tsg - sg) * kg; wd += (twd - wd) * kg
                g += (tg - g) * kg; fc += (tc - fc) * kc; tn += (tt - tn) * kt; pr += (tp - pr) * kg; ht += (tht - ht) * kc; bs += (tbs - bs) * kg; rg += (trg - rg) * kg; hpK += (tph - hpK) * kg; rsK += (trs - rsK) * kg; sw += (tsw - sw) * (tsw > sw ? kSwUp : kSwDn)
                // 白い雑音（xorshift）
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let wn = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                // 突風・はためき：雑音をゆっくりならしたゆらぎ（0 のまわり）
                gust += (wn * 3.2 - gust) * kGust; gust2 += (wn * 6 - gust2) * kGust2; flut += (wn - flut) * kFlut
                let gw = max(0.35, 1 + 0.45 * gust + 0.35 * gust2)             // 突風の強さ（1 のまわり）
                let at = abs(tn)                                                // 曲がる速さ（0〜1）
                // 寄せては返す波：ゆっくりした 2 つの波（約 8 秒・5 秒）と突風を重ねる（0〜1）。シューの高さと大きさがゆらぐ
                wa += 2 * Float.pi * 0.13 * dt; wb += 2 * Float.pi * 0.21 * dt
                if wa > 2 * Float.pi { wa -= 2 * Float.pi }; if wb > 2 * Float.pi { wb -= 2 * Float.pi }
                // ズームで寄るほど波は消えて一定に（迫力。引きの絵の時だけ波がある）
                let wv0 = max(0, min(1, 0.5 + 0.3 * sin(wa) + 0.2 * sin(wb) + 0.15 * gust2)), wv = wv0 + (0.5 - wv0) * tzm
                nr += (tnr - nr) * kg
                // 流れ：帯の高さは速さ＋曲がり＋突風で滑る
                // 低音のゆらぎ（きついカーブ・ときどき）：低いうなりが大きく揺れて、0.7 秒ほどで戻る（高さは少しだけ）
                wob *= exp(-dt * 4); wobPh += 2 * Float.pi * 5 * dt; if wobPh > 2 * Float.pi { wobPh -= 2 * Float.pi }
                let wq = wob * sin(wobPh)
                let bh = bs * (1 - 0.35 * ht)                                     // 低い音は、カタ極の側ほど重く
                let fcm0 = fc * (1 + 0.35 * ht) * (1 + 0.55 * at + 1.3 * sw + 0.12 * gust) * (0.7 + 0.55 * wv) * (1 + 0.06 * wq)   // 波で高さが上下する
                let fcm: Float = fcm0 * (1 + 0.35 * rsK)                          // 直線の伸び：風も高く
                let f1 = min(0.95, 2 * sin(Float.pi * fcm / rate)), q: Float = 0.9 - 0.35 * at   // 曲がる時は帯が細く鋭く（空気をつかむ）
                low += f1 * band; let high = wn - low - q * band; band += f1 * high
                let f2 = min(0.95, 2 * sin(Float.pi * fcm * 0.5 / rate))
                low2 += f2 * band2; let high2 = band - low2 - q * band2; band2 += f2 * high2
                // 乱れ：高いシュー（流れの 3 倍あたり）。はためきで細かくふるえる
                let f3 = min(0.95, 2 * sin(Float.pi * min(rate * 0.4, fcm * 2.2) / rate))   // 乱れも低めに
                hl += f3 * hb; let hh = wn - hl - 0.6 * hb; hb += f3 * hh
                // 圧：前の空気を押す重いうなり（雑音を 2 段で低く。60〜140 Hz あたり）
                let fr = min(0.5, 2 * sin(Float.pi * (60 + 80 * min(1, pr * 2)) / rate))
                rl1 += (wn - rl1) * fr; rl2 += (rl1 - rl2) * fr
                let flow = (band2 * 0.9 + band * 0.25) * g * (1 + 1.2 * sw) * 0.6 * gw * (q / 0.9) * (q / 0.9) * (1 + 0.25 * at) * (0.55 + 0.75 * wv)   // 帯を鋭くした分の響き（2 段なので q の 2 乗）は打ち消す
                let hiss = hb * g * (1 + 2.5 * sw) * 0.14 * gw * (0.8 + 0.6 * flut) * (1 + 0.5 * at) * (0.4 + 0.9 * wv)   // 高いシューは控えめに、波に合わせて
                let press = rl2 * pr * 4.1 * bh * (0.8 + 0.4 * gw) * (1 + 0.75 * wq) * airG   // 低いうなりは強めに（ゆらぐ時は大きく揺れる）
                // 揺さぶり（ボボボ）：速いほど速く強く脈打つ。脈の速さは突風で少しずれる
                let spd = min(1, pr * 2.2)                                       // 速さの目安（0〜1）
                let thHz: Float = 9 + 11 * spd + 1.5 * gust
                buf += 2 * Float.pi * thHz * dt; if buf > 2 * Float.pi { buf -= 2 * Float.pi }
                let throb = 0.5 + 0.5 * sin(buf), throbAmt = 0.55 * spd * (1 - 0.8 * min(1, rsK))   // 直線では脈打たない（一定の脈はエンジンに聞こえる）
                // ゴーッ：3 段の低域（250〜700 Hz より上を落とす）。揺さぶりで脈打つ
                let fro = min(0.5, 2 * sin(Float.pi * (250 + 450 * spd) / rate))
                rr1 += (wn - rr1) * fro; rr2 += (rr1 - rr2) * fro; rr3 += (rr2 - rr3) * fro
                let roar = rr3 * pr * 4.5 * bh * gw * (1 - throbAmt + throbAmt * 2 * throb * throb)
                // パチパチ：まばらに小さな破裂（1 秒に 0〜40 回、速さの 2 乗で増える）。高めの帯で、すぐ消える
                let rate2 = 40 * spd * spd
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                if Float(seed & 0xFFFFFF) / Float(0xFFFFFF) < rate2 * dt { crkEnv = 0.4 + 0.6 * Float((seed >> 8) & 0xFF) / 255 }
                crkEnv *= exp(-dt * 140)
                crk = wn * crkEnv
                let fcr = min(0.95, 2 * sin(Float.pi * 3200 / rate))
                cl += fcr * cb; let ch = crk - cl - 0.5 * cb; cb += fcr * ch
                let crackle = cb * pr * 0                                       // パチパチ（キチキチ）は消した（耳ざわり）
                // 窓から顔を出した時の風（ボボボッ）：低い雑音（120〜320 Hz）を、不規則な速い揺れ（6〜15 Hz あたり）でばたつかせる。
                //   空気抵抗（速さの 2 乗）で強く、カーブの時はさらに強く（風がまともに当たる）
                let fbf = min(0.5, 2 * sin(Float.pi * (120 + 200 * spd) / rate))
                bf1 += (wn - bf1) * fbf; bf2 += (bf1 - bf2) * fbf
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let wn2 = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                btm += (wn2 * 9 - btm) * (1 - exp(-dt * (40 + 50 * spd))); btm2 += (wn2 * 4 - btm2) * (1 - exp(-dt * 6))
                let flap = min(1.6, max(0, 0.55 + 0.7 * btm + 0.35 * btm2))   // ばたつき（大きくなりすぎない）
                let buffet = bf2 * pr * bh * flap * (0.55 + 0.7 * at) * (0.6 + 0.4 * gw)
                // ガラララッ：低めの雑音（180〜440 Hz）を、1 秒に 24〜44 回の不ぞろいな連打で叩く
                let rtTempo: Float = (24 + 20 * spd) * (1 + 0.2 * gust)
                rtPh += 2 * Float.pi * rtTempo * dt
                if rtPh > 2 * Float.pi { rtPh -= 2 * Float.pi; rtA = 0.35 + 0.65 * Float((seed >> 8) & 0xFF) / 255 }
                let rtHz: Float = (180 + 260 * spd) * (1 + 0.8 * hpK)
                let frt: Float = min(0.5, 2 * sin(Float.pi * rtHz / rate))
                rt1 += (wn - rt1) * frt; rt2 += (rt1 - rt2) * frt
                let frl: Float = min(1, 2 * Float.pi * 250 / rate)
                rtL += (rt2 - rtL) * frl
                // ヘッドホン用：低音に隠れないよう、音の帯を上げて低い所を抜き、強めて、打つ瞬間だけ低音を下げる（スピーカーの時は今まで通り）
                let hit: Float = max(0, sin(rtPh)), hit3: Float = hit * hit * hit
                let rtCore: Float = rt2 - hpK * rtL, rtAmp: Float = hit3 * rtA * pr * rg * 6
                let rtBoost: Float = (1 + 0.35 * at + 0.8 * sw) * (1 + 1.6 * hpK) * (1 - 0.75 * min(1, rsK))   // 直線の連打は引く（速まる連打はバイクに聞こえる）
                let rattle: Float = rtCore * rtAmp * rtBoost
                let rtHit: Float = min(1, hit3 * rtA * 1.5), rtDuck: Float = 1 - hpK * 0.55 * min(1, rg) * rtHit
                // ジリジリ：とても高いざらつき（熱い空気）。速い時だけ
                sizz += (wn - sizz) * 0.6
                let sizzle = (wn - sizz) * pr * 0.25 * spd * (0.7 + 0.5 * flut)
                // 宇宙船のエンジン（シュイーン）：低いうなり（少しずらした 2 つの音）と高い鳴き（6 倍あたり）。速いほど高く大きく、
                //   加速する時は鳴きが強まって音が上がる。曲がる時は高さが少し揺れる
                enS += (spd - enS) * (1 - exp(-dt * 2.5))
                enAcc += (max(0, (enS - enPrev) / dt) * 4 - enAcc) * (1 - exp(-dt * 3)); enPrev = enS
                let fe: Float = 140                                               // 背景の唸りは、速さや場所で変えず一定の高さ
                en1 += 2 * Float.pi * fe * dt; en2 += 2 * Float.pi * fe * 1.007 * dt; en3 += 2 * Float.pi * fe * 6.03 * dt
                beatF = fe * 0.007; beat += Double(beatF * dt)                  // 2 つの音の位相の差が 0 にそろう所（整数）が、うなりの山
                if en1 > 2 * Float.pi { en1 -= 2 * Float.pi }; if en2 > 2 * Float.pi { en2 -= 2 * Float.pi }; if en3 > 2 * Float.pi { en3 -= 2 * Float.pi }
                let ea: Float = 0.26 * min(1, g * 5)                              // 背景のプープーという機械の音。走っている間は一定の大きさ。雰囲気の芯なので、直線でも引かず、空気のゆれにも通さない
                let enLow: Float = (sin(en1) * 0.5 + sin(en2) * 0.35 + sin(en1 * 2) * 0.12) * ea * 0.16 * bs
                let enHigh: Float = sin(en3) * ea * 0.012
                let engine: Float = enLow + enHigh
                // 線路の音：光の矢印を通るたびに、遠くの線路のつなぎ目のように「カタン」とかすかに鳴る（2 回の小さな音と、ごく低い響き）
                var rail: Float = 0
                if rlT < 0.1 {
                    rlT += dt
                    let fr: Float = min(0.9, 2 * sin(Float.pi * rlF / rate))
                    rlL += fr * rlB; let rh: Float = wn - rlL - 0.6 * rlB; rlB += fr * rh
                    let e1: Float = exp(-rlT * 170), e2: Float = rlT > 0.05 ? 0.6 * exp(-(rlT - 0.05) * 170) : 0
                    rail = (rlB * (e1 + e2) + sin(2 * Float.pi * 150 * rlT) * exp(-rlT * 60) * 0.5) * rlA * trk * vol * 0.2
                }
                // 渦の歌：真空に風は無いので、彗星のガスの流れそのものを楽器にする。流体の渦の形が音色で、速いほど高く、直線でさらに伸びて開く
                var soOutL: Float = 0, soOutR: Float = 0
                if sg > 0.001 {
                    let rk: Float = min(1, rsK), so0: Float = 65.41 * pow(2, 0.75 * enS + 0.25 * rk), mix: Float = Float(i) / Float(frames)
                    var l: Float = 0, r: Float = 0
                    for v in 0..<6 {
                        scP[v] += so0 * scRatio[v] * dt; if scP[v] >= 1 { scP[v] -= 1 }
                        let x = scP[v] * 64, j = Int(x), f = x - Float(j)
                        let a0 = scA[j] + (scA[j + 1] - scA[j]) * f, b0 = scB[j] + (scB[j + 1] - scB[j]) * f, val = (a0 + (b0 - a0) * mix) * scGain[v]
                        if v & 1 == 0 { l += val; r += val * 0.6 } else { l += val * 0.6; r += val }
                    }
                    let fs: Float = 350 + 3000 * enS * enS + 1800 * rk + 1500 * at + 900 * sw   // 速いほど、直線ほど、音が開く
                    let ff: Float = min(0.9, 2 * sin(Float.pi * min(rate * 0.4, fs) / rate))
                    let dl: Float = tanh(l * 0.7), dr: Float = tanh(r * 0.7)
                    soL += ff * soB; soB += ff * (dl - soL - 0.7 * soB)
                    soL2 += ff * soB2; soB2 += ff * (dr - soL2 - 0.7 * soB2)
                    let sa: Float = sg * pow(max(0, g), 0.75) * (0.4 + 0.5 * enS) * (1 + 0.6 * rk) * (1 + 0.5 * at) * (0.7 + 0.3 * airG)
                    soOutL = (soL + 0.5 * soB) * sa; soOutR = (soL2 + 0.5 * soB2) * sa
                }
                // 直線の突進音：ジェットの噴流。音程のない低いゴォォと、伸びるほど上がる空気の帯（シャーー）。カーブでは消えるので、風切りの音と分かれる
                let jtK: Float = min(1.5, rsK), thA: Float = pr * 1.9 * jtK * jtK.squareRoot()
                let jrF: Float = min(0.5, 2 * sin(Float.pi * (110 + 90 * jtK) / rate))
                jr1 += (wn - jr1) * jrF; jr2 += (jr1 - jr2) * jrF
                let jtF: Float = min(0.9, 2 * sin(Float.pi * (900 + 2400 * jtK) / rate))
                jtLo += jtF * jtB; let jtHi: Float = wn - jtLo - 0.9 * jtB; jtB += jtF * jtHi
                let thrust: Float = (jr2 * 5.4 * bh + jtB * 0.38) * thA             // 噴射の帯（シューッ）は控えめに
                let flowMix: Float = flow * (1 - 0.15 * min(1, rsK))              // 直線は風を少し引いて、カーブの風切りを際立たせる（引きすぎると中音の疾走感が消える）
                // 球層を横切る「スッ」：短い高めの風（0.15 秒ほど）
                var pass: Float = 0
                if lyT < 0.15 {
                    lyT += dt
                    let fl = min(0.95, 2 * sin(Float.pi * (2600 - 1400 * lyT / 0.15) / rate))
                    lyL += fl * lyB; let lh = wn - lyL - 0.5 * lyB; lyB += fl * lh
                    pass = lyB * exp(-lyT * 26) * min(1, lyT / 0.01) * 0.3 * vol
                }
                let roarMix: Float = roar * 0.66 * (1 + 0.5 * wq) * rtDuck, bufMix: Float = buffet * rtDuck
                var s: Float = (pass + flowMix + hiss + roarMix + crackle + sizzle + bufMix + rattle + thrust) * (1 + 0.1 * wq)   // ゴーッ（低い）も強めに
                // チリン（ベル：基音と 2.76 倍の部分音、すぐ減る）
                var bell: Float = 0, bellE: Float = 0                           // bellE：ベルの大きさ（鳴っている間、風を少し下げる）
                for v in voices.indices {
                    voices[v].p += 2 * Float.pi * voices[v].f * dt; voices[v].t += dt
                    let env = voices[v].a * exp(-voices[v].t * 3.2) * nr          // 遠くから眺めている時は、かすかに
                    bellE += env
                    bell += env * (sin(voices[v].p) + 0.35 * sin(voices[v].p * 2.76) * exp(-voices[v].t * 6))
                }
                // シュパッ：0.04 秒で立ち上がる「シュ」（帯は 8 kHz から 2.5 kHz へ下がる）→ 「パッ」と小さな破裂、氷のかけらのきらめき
                var ice: Float = 0
                if iceT < 0.7 {
                    iceT += dt
                    let env = iceT < 0.04 ? iceT / 0.04 : exp(-(iceT - 0.04) * 16)
                    let fi = min(0.95, 2 * sin(Float.pi * (2500 + 5500 * exp(-iceT * 9)) / rate))
                    iceL += fi * iceB; let ih = wn - iceL - 0.35 * iceB; iceB += fi * ih
                    ice = iceB * env * 0.55
                    if iceT > 0.045 {
                        let te = iceT - 0.045
                        for v in iceF.indices { iceP[v] += 2 * Float.pi * iceF[v] * dt; ice += sin(iceP[v]) * exp(-te * (10 + 3 * Float(v))) * 0.07 }
                    }
                }
                bell += ice * 2.2
                // 左右：ゆっくり揺れて、曲がる時は外側へ寄る（右へ曲がると、左の耳に風が当たる）
                ph += 2 * Float.pi * 0.17 * dt; if ph > 2 * Float.pi { ph -= 2 * Float.pi }
                let pan = max(0.08, min(0.92, 0.5 + 0.12 * sin(ph) + 0.06 * gust - 0.32 * tn))
                s = max(-1, min(1, s * airG)) * wd + engine                  // 機械の音は風の丸め・空気のゆれのあとで足す
                // 左右で少しずらす（広がり）。圧は真ん中
                sL += (s - sL) * 0.7; sR += (s - sR) * 0.55
                // 端はやわらかく丸める（割れない）。チリンは丸める外で足す（風が強くても埋もれない）
                let duck = 1 - min(0.5, bellE * 0.7), bl = tanh(bell * 0.55) * 0.75
                if let R {
                    L[i] = tanh(sL * (1 - pan) * 2.6 + press * wd + soOutL) * duck + bl + rail
                    R[i] = tanh(sR * pan * 2.6 + press * wd + soOutR) * duck + bl + rail
                } else {
                    L[i] = tanh(sL * 1.6 + press * wd + 0.5 * (soOutL + soOutR)) * duck + bl + rail   // 空間オーディオ：方向は環境が付ける
                }
            }
            voices.removeAll { $0.t > 2.2 }
            if t.lock.try() { t.beatCyc = beat; t.beatRate = Double(beatF); t.beatStamp = CACurrentMediaTime(); t.lock.unlock() }   // 音の糸は待たない（取れない時は次の回に）
            return noErr
        }
        return (n, fmt)
    }
    /// 確かめ用：画面も音も出さずに seconds 秒ぶん作って、平均の大きさ（RMS）といちばん大きい値を返す
    ///   at：空間オーディオで、この場所から鳴らす（nil ならステレオ）。rmsR：右の耳の大きさ
    func renderTest(seconds: Double, speed: Double, zoom: Double, turn: Double = 0, chimeAt: Double? = nil, iceAt: Double? = nil, wav: String? = nil, at: SIMD3<Float>? = nil, fade: Double = 1, fly: Double = 0) -> (rms: Float, peak: Float, rmsR: Float) {
        let e = AVAudioEngine(), rate: Float = 48000
        guard let (n, fmt) = makeNode(rate, mono: at != nil), let outFmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2) else { return (0, 0, 0) }
        e.attach(n)
        do { try e.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 4800) } catch { return (0, 0, 0) }
        var flyTest: AVAudioSourceNode?
        if let p = at { _ = attachSpatial(e, n, fmt); n.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z) } else { e.connect(n, to: e.mainMixerNode, format: fmt) }
        if fly > 0, let (fn, ff) = makeFly(rate) { e.attach(fn); e.connect(fn, to: e.mainMixerNode, format: ff); flyTest = fn; tgt.lock.lock(); tgt.flyA = Float(fly); tgt.flyF = 240; tgt.lock.unlock() }
        do { try e.start() } catch { return (0, 0, 0) }
        update(speed: speed, zoom: zoom, turn: turn, volume: 1, fade: fade)
        guard let buf = AVAudioPCMBuffer(pcmFormat: e.manualRenderingFormat, frameCapacity: 4800) else { return (0, 0, 0) }
        let file = wav.flatMap { try? AVAudioFile(forWriting: URL(fileURLWithPath: $0), settings: e.manualRenderingFormat.settings) }   // 聞いて確かめる用の音のファイル
        var sum: Double = 0, sumR: Double = 0, cnt = 0, peak: Float = 0, done = 0.0, rung = false, popped = false
        while done < seconds {
            if let c = chimeAt, !rung, done >= c { chime(pole: 2); rung = true }
            if let c = iceAt, !popped, done >= c { icePop(); popped = true }
            guard (try? e.renderOffline(4800, to: buf)) == .success, let L = buf.floatChannelData?[0] else { break }
            try? file?.write(from: buf)
            let Rch = (buf.format.channelCount > 1 ? buf.floatChannelData?[1] : nil) ?? L
            for i in 0..<Int(buf.frameLength) { let v = L[i], w = Rch[i]; sum += Double(v * v); sumR += Double(w * w); cnt += 1; peak = max(peak, abs(v), abs(w)) }
            done += 0.1
        }
        _ = flyTest; e.stop(); tgt.lock.lock(); tgt.gain = 0; tgt.flyA = 0; tgt.lock.unlock()
        return (Float((sum / Double(max(1, cnt))).squareRoot()), peak, Float((sumR / Double(max(1, cnt))).squareRoot()))
    }
    /// 動画の書き出し用：鳴らさずに、手で少しずつ音を作る（決まった道から作る動画の音。shared とは別に作って使う）
    func startOffline(rate: Double = 48000) -> AVAudioFormat? {
        guard !running, let outFmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2), let (n, fmt) = makeNode(Float(rate), mono: spatial) else { return nil }
        let e = AVAudioEngine()
        e.attach(n)
        do { try e.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 4096) } catch { return nil }
        if spatial { envNode = attachSpatial(e, n, fmt) } else { e.connect(n, to: e.mainMixerNode, format: fmt) }
        attachFly(e, Float(rate))
        do { try e.start() } catch { return nil }
        engine = e; node = n; running = true
        return e.manualRenderingFormat
    }
    /// 書き出し用：次の frames 標本ぶんの音を作る
    func renderOffline(_ frames: Int) -> AVAudioPCMBuffer? {
        guard let e = engine, e.isInManualRenderingMode, let b = AVAudioPCMBuffer(pcmFormat: e.manualRenderingFormat, frameCapacity: AVAudioFrameCount(frames)),
              (try? e.renderOffline(AVAudioFrameCount(frames), to: b)) == .success else { return nil }
        return b
    }
    func stop() {
        guard running else { return }
        engine?.stop(); if let n = node { engine?.detach(n) }; if let n = flyNode { engine?.detach(n) }; if let v = envNode { engine?.detach(v) }
        engine = nil; node = nil; flyNode = nil; envNode = nil; running = false; tapped = false
        tgt.lock.lock(); tgt.flyA = 0; tgt.gain = 0; tgt.press = 0; tgt.turn = 0; tgt.height = 0; tgt.chimes = []; tgt.lock.unlock()
    }
    /// 毎コマ：速さ（0〜1）・ズーム（0〜1）・曲がる速さ（−1〜1、＋は右へ）・音量から、風の大きさ・高さ・圧・曲がり
    /// near：引きの絵で、彗星が手前（1）か奥（0）か。奥へ行くと小さく、回り込んで手前に来ると少し大きく
    /// fade：走る音だけの大きさ（チリンなどは下げない）。ダイブの外で小さく鳴らす時に使う
    func update(speed: Double, zoom: Double, turn: Double = 0, swing: Double = 0, near cn: Double = 0.5, volume: Double, fade: Double = 1) {
        let s = Float(max(0, min(1, speed))), z = Float(max(0, min(1, zoom))), tr = Float(max(-1, min(1, turn)))
        let zp = pow(z, 1.3), far = 0.012 + 0.07 * pow(Float(max(0, min(1, cn))), 1.6)   // 外から眺めている時は、聞こえるか聞こえないか（奥で消えそう・手前で少し）
        let near = far * (1 - zp) + zp                                 // ズームで寄るほど大きく
        // 寄った時（ダイブ）は、ふつうの速さでも迫力が出るよう、速さの効き方をゆるく（遅めでも大きく）
        let sEff = pow(s, 1.5 - 0.6 * zp)
        let gain = sEff * near * (1 + 0.25 * abs(tr)) * Float(fade)  // 曲がる時は、ひと吹き強まる
        let press = pow(s, 2 - 0.7 * zp) * near * 0.5 * Float(fade)   // 空気抵抗（速さの 2 乗）を押し切る重さ。寄った時は強め
        let cutoff = 260 + 1500 * s * (0.6 + 0.4 * z)                 // 速いほど高い（ゆっくりの時もこもらないように）
        tgt.lock.lock(); tgt.gain = gain; tgt.press = press; tgt.cutoff = cutoff; tgt.turn = tr * s; tgt.swing = Float(max(0, min(1, swing))) * s.squareRoot(); tgt.vol = Float(volume); tgt.zoom = z; tgt.near = 1;   // チリンはいつもはっきり（チェックポイントの通過は聞こえた方がいい）
        tgt.lock.unlock()
        logValues(s, z, gain, press, cutoff)
    }
    /// 確かめ用（環境変数 S3_SND_LOG にファイルの場所）：1 秒ごとに、音へ渡した値を書く（動いている時と書き出しの時を比べる）
    private static let logPath = ProcessInfo.processInfo.environment["S3_SND_LOG"]
    private var logT = 0.0
    private func logValues(_ s: Float, _ z: Float, _ gain: Float, _ press: Float, _ cutoff: Float) {
        guard let p = Self.logPath else { return }
        let now = CACurrentMediaTime(); if now - logT < 1 { return }; logT = now
        let line = String(format: "%@ 伸び %.2f 速さ %.3f 寄り %.3f 風 %.3f 圧 %.3f 高さ %.0f 空間 %d\n", engine?.isInManualRenderingMode == true ? "書き出し" : "動作中", tgt.rush, s, z, gain, press, cutoff, spatial ? 1 : 0)
        if let d = line.data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: nil) }
            if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(d); h.closeFile() }
        }
    }
    /// 毎コマ：今の w の高さ（−1〜1）と場所の音の強さ（0〜1）、低音の倍率、荒さ
    /// 直線の伸び（0〜1）：まっすぐ走り続けるほど約 4 秒で 1 へ上がり（極へ向かう時はもっと速く）、曲がると 1 秒ほどで戻る。swing：向きの変わる速さ（1 で強いカーブ）、speed：速さ 0〜1
    static func rushStep(_ r: Double, swing: Double, speed: Double, aim: Double = 0, dt: Double) -> Double {
        let v = speed > 0.3 && swing < 0.14 ? (0.06 + 0.4 * (1 - r)) * (1 + aim) : -(0.5 + 2.5 * min(1, swing))
        return max(0, min(1, r + v * dt))
    }
    /// アナ極・カタ極へまっすぐ向かっている度合い（0〜1）。pos：今いる所、head：進む向き
    static func poleAim(_ pos: SIMD4<Double>, _ head: SIMD4<Double>) -> Double {
        let d = 1 - pos.w * pos.w
        guard d > 1e-4 else { return 0 }
        return pow(min(1, abs(head.w) / d.squareRoot()), 6)
    }
    func tune(height: Double, place: Double, bass: Double, rough: Double = 1, phones: Bool = false, rush: Double = 0, song: Double = 0, wind: Double = 1, rail: Double = 0) {
        tgt.lock.lock(); tgt.railK = Float(rail); tgt.song = Float(song); tgt.wind = Float(wind); tgt.rush = Float(rush); tgt.height = Float(height * place); tgt.bass = Float(bass); tgt.rough = Float(rough); tgt.phones = phones ? 1 : 0; tgt.lock.unlock()
    }
    /// 空気の計算からの音の大きさの倍率（渦のゆれ。1 でそのまま）
    func setAir(_ g: Double) { tgt.lock.lock(); tgt.air = Float(g); tgt.lock.unlock() }
    /// 光の矢印を通った時の「カタン」
    func railTick() { tgt.lock.lock(); tgt.rail += 1; tgt.lock.unlock() }
    /// 渦の歌の波形（AirSim.ring、64 個）
    func setScan(_ r: [Float]) { tgt.lock.lock(); tgt.scan = r; tgt.lock.unlock() }
    /// 球層を横切った時の「スッ」
    func layerPass() { tgt.lock.lock(); tgt.layer += 1; tgt.lock.unlock() }
    /// シュパッ（氷がはじけるような音。カーブの揺れの時にときどき）
    func icePop() { tgt.lock.lock(); tgt.ice += 1; tgt.lock.unlock() }
    /// 低音をゆらす（きついカーブ・ときどき）
    func shellPass() { tgt.lock.lock(); tgt.kick += 1; tgt.lock.unlock() }
    /// チリン：極は番号ごとの音（ペンタトニック）、目印は高い音
    func chime(pole k: Int) {
        let scale: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.7, 1318.5]
        let f = k >= 0 ? scale[k % scale.count] : 1567.98
        tgt.lock.lock(); tgt.chimes.append((f, 1)); tgt.lock.unlock()
    }
}

/// 空気：彗星のまわりの断面（2 次元）で、非圧縮のナビエ・ストークス方程式を解く（Stam の Stable Fluids に渦の補強）。
///   彗星が止まっていて風が左から来る向きで見る。speed：風の速さ 0〜1、cross：横風（曲がると横から当たる。−1〜1）
///   1 回で 1/60 秒ぶん。結果：drag 抗力、lift 揚力（カルマン渦で＋−にゆれる）、turb 後ろの乱れ
final class AirSim {
    static let nx = 96, ny = 48, cx = 22, cy = 24, rad = 5
    private var u: [Float], v: [Float], u2: [Float], v2: [Float], p: [Float], dv: [Float], w: [Float], solid: [Bool]
    private(set) var drag: Float = 0, lift: Float = 0, turb: Float = 0
    private var liftS: Float = 0, turbS: Float = 0, dragS: Float = 0
    init() {
        let n = Self.nx * Self.ny
        u = .init(repeating: 0, count: n); v = u; u2 = u; v2 = u; p = u; dv = u; w = u
        solid = .init(repeating: false, count: n)
        for j in 0..<Self.ny { for i in 0..<Self.nx { let a = i - Self.cx, b = j - Self.cy; solid[j * Self.nx + i] = a * a + b * b <= Self.rad * Self.rad } }
    }
    func step(speed: Float, cross: Float) {
        let nx = Self.nx, ny = Self.ny
        let ug = speed > 0.005 ? 0.35 + 2.1 * min(1, speed) : 0, vg = ug * 0.7 * max(-1, min(1, cross))
        u.withUnsafeMutableBufferPointer { U in v.withUnsafeMutableBufferPointer { V in
        u2.withUnsafeMutableBufferPointer { A in v2.withUnsafeMutableBufferPointer { B in
        p.withUnsafeMutableBufferPointer { P in dv.withUnsafeMutableBufferPointer { D in
        w.withUnsafeMutableBufferPointer { W in solid.withUnsafeBufferPointer { S in
            // 入口と上下は外の風、出口は流れ出すまま
            for j in 0..<ny { U[j * nx] = ug; V[j * nx] = vg; U[j * nx + nx - 1] = U[j * nx + nx - 2]; V[j * nx + nx - 1] = V[j * nx + nx - 2] }
            for i in 0..<nx { U[i] = ug; V[i] = vg; U[(ny - 1) * nx + i] = ug; V[(ny - 1) * nx + i] = vg }
            // 移流（セミラグランジュ）
            for j in 1..<(ny - 1) { for i in 1..<(nx - 1) {
                let k = j * nx + i
                if S[k] { A[k] = 0; B[k] = 0; continue }
                let x = max(0.5, min(Float(nx) - 1.5, Float(i) - U[k])), y = max(0.5, min(Float(ny) - 1.5, Float(j) - V[k]))
                let i0 = Int(x), j0 = Int(y), s = x - Float(i0), t = y - Float(j0), q = j0 * nx + i0
                A[k] = (1 - t) * ((1 - s) * U[q] + s * U[q + 1]) + t * ((1 - s) * U[q + nx] + s * U[q + nx + 1])
                B[k] = (1 - t) * ((1 - s) * V[q] + s * V[q + 1]) + t * ((1 - s) * V[q + nx] + s * V[q + nx + 1])
            } }
            // 粘性と渦の補強（数値の拡散で消える細かい渦を戻す）
            let nu: Float = 0.015
            for j in 1..<(ny - 1) { for i in 1..<(nx - 1) { let k = j * nx + i; W[k] = (B[k + 1] - B[k - 1] - A[k + nx] + A[k - nx]) * 0.5 } }
            for j in 2..<(ny - 2) { for i in 2..<(nx - 2) {
                let k = j * nx + i
                if S[k] { U[k] = 0; V[k] = 0; continue }
                let gx = abs(W[k + 1]) - abs(W[k - 1]), gy = abs(W[k + nx]) - abs(W[k - nx]), l = (gx * gx + gy * gy).squareRoot() + 1e-5
                let e = 0.35 * W[k]
                U[k] = A[k] + nu * (A[k + 1] + A[k - 1] + A[k + nx] + A[k - nx] - 4 * A[k]) + gy / l * e
                V[k] = B[k] + nu * (B[k + 1] + B[k - 1] + B[k + nx] + B[k - nx] - 4 * B[k]) - gx / l * e
            } }
            // 圧力で「縮まない」にする（ヤコビ法。前のコマの圧力から始める）
            for j in 1..<(ny - 1) { for i in 1..<(nx - 1) { let k = j * nx + i; D[k] = (U[k + 1] - U[k - 1] + V[k + nx] - V[k - nx]) * 0.5 } }
            for it in 0..<22 {
                let red = it & 1
                for j in 1..<(ny - 1) { var i = 1 + (j + red) & 1; while i < nx - 1 {
                    let k = j * nx + i
                    if !S[k] {
                        let a = S[k + 1] ? P[k] : P[k + 1], b = S[k - 1] ? P[k] : P[k - 1], e = S[k + nx] ? P[k] : P[k + nx], f = S[k - nx] ? P[k] : P[k - nx]
                        P[k] = (a + b + e + f - D[k]) * 0.25
                    }
                    i += 2
                } }
                for j in 0..<ny { P[j * nx + nx - 1] = 0; P[j * nx] = P[j * nx + 1] }
                for i in 0..<nx { P[i] = P[nx + i]; P[(ny - 1) * nx + i] = P[(ny - 2) * nx + i] }
            }
            for j in 1..<(ny - 1) { for i in 1..<(nx - 1) {
                let k = j * nx + i
                if S[k] { continue }
                U[k] -= ((S[k + 1] ? P[k] : P[k + 1]) - (S[k - 1] ? P[k] : P[k - 1])) * 0.5
                V[k] -= ((S[k + nx] ? P[k] : P[k + nx]) - (S[k - nx] ? P[k] : P[k - nx])) * 0.5
            } }
            // 彗星のまわりの圧力で力を測る。後ろの乱れは渦の強さの平均
            var fx: Float = 0, fy: Float = 0, ens: Float = 0, n: Float = 0
            let r = Self.rad + 2
            for j in (Self.cy - r)...(Self.cy + r) { for i in (Self.cx - r)...(Self.cx + r) {
                let k = j * nx + i, a = Float(i - Self.cx), b = Float(j - Self.cy), l = (a * a + b * b).squareRoot()
                if !S[k] && l <= Float(r) { fx -= P[k] * a / l; fy -= P[k] * b / l }
            } }
            var j = 6; while j < ny - 6 { var i = Self.cx + 8; while i < nx - 8 { ens += abs(W[j * nx + i]); n += 1; i += 3 }; j += 3 }
            let q = max(0.02, ug * ug)
            self.dragS = fx / q * 0.05; self.liftS = fy / q * 0.05; self.turbS = n > 0 ? ens / n / max(0.05, ug) * 3 : 0
        } } } } } } } }
        let on = min(1, ug / 0.6)                                          // 止まっている時は力も止まる（0 で割らない）
        drag = dragS * on; lift = max(-2, min(2, liftS * on)); turb = turbS * on
    }
    /// 1/60 秒ぶん。速いほど同じ時間に多く流れて、渦の周期が短くなる（渦の周波数は風の速さに比例）
    func tick(speed: Float, cross: Float) { for _ in 0..<(1 + Int(min(1, speed) * 2.99)) { step(speed: speed, cross: cross) } }
    /// 渦の歌の波形：彗星とカルマン渦の並ぶ所を囲む楕円を 1 周、渦の強さを読む（平均を引いて、ゆっくり大きさをそろえる）
    private var ringPeak: Float = 0.05
    func ring() -> [Float] {
        let n = 64, nx = Self.nx
        var o = [Float](repeating: 0, count: n)
        for k in 0..<n {
            let a = 2 * Float.pi * Float(k) / Float(n), x = Float(Self.cx + 20) + 30 * cos(a), y = Float(Self.cy) + 9 * sin(a)
            let i = Int(x), j = Int(y), s = x - Float(i), t = y - Float(j), q = j * nx + i
            o[k] = (1 - t) * ((1 - s) * w[q] + s * w[q + 1]) + t * ((1 - s) * w[q + nx] + s * w[q + nx + 1])
        }
        let m = o.reduce(0, +) / Float(n)
        var f = [Float](repeating: 0, count: n), top: Float = 0
        for k in 0..<n { let v: Float = (o[(k + n - 1) % n] + 2 * o[k] + o[(k + 1) % n]) * 0.25 - m; f[k] = v; top = max(top, abs(v)) }
        ringPeak = max(ringPeak * 0.97, top, 0.05)
        for k in 0..<n { f[k] /= ringPeak }
        return f
    }
    /// 音の大きさの倍率：渦のゆれと乱れで、風が息をする
    var gust: Double { Double(max(0.55, min(1.7, 1 + 0.4 * abs(lift) + 0.5 * (turb - 0.4)))) }
}
