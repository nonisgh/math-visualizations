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
    /// 空間オーディオで鳴らす（切りかえたら、鳴らし直す）
    var spatial = true { didSet { if spatial != oldValue && running { stop(); start() } } }
    /// 描く側が書き、音の糸が読む目標（Float の読み書きだけ。少し古い値を読んでも音は崩れない）
    private final class Target { var gain: Float = 0; var cutoff: Float = 400; var turn: Float = 0; var press: Float = 0; var vol: Float = 0.8; var near: Float = 1; var zoom: Float = 0; var kick = 0; var ice = 0; var chimes: [(f: Float, a: Float)] = []; var beatCyc = 0.0; var beatRate = 0.0; var beatStamp = 0.0; let lock = NSLock() }
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
        var g: Float = 0, fc: Float = 400, tn: Float = 0, pr: Float = 0
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
        var iceT: Float = 9, iceL: Float = 0, iceB: Float = 0, iceF: [Float] = [], iceP: [Float] = []
        let t = tgt
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 1, let L = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let R = bufs.count >= 2 ? bufs[1].mData?.assumingMemoryBound(to: Float.self) : nil   // nil：空間オーディオ（1 つの音）
            t.lock.lock(); let tg = t.gain * t.vol, tc = t.cutoff, tt = t.turn, tp = t.press * t.vol, vol = t.vol, tnr = t.near, tzm = t.zoom; let kicks = t.kick; t.kick = 0; let ices = t.ice; t.ice = 0; let new = t.chimes; t.chimes = []; t.lock.unlock()
            for c in new where voices.count < 8 { voices.append((c.f, c.a * vol, 0, 0)) }
            if kicks > 0 { wob = 1 }
            if ices > 0 {
                iceT = 0; iceF = []; iceP = []
                for _ in 0..<4 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; iceF.append(2800 + 4200 * Float(seed & 0xFFFF) / 65535); iceP.append(0) }
            }
            let kg = 1 - exp(-1 / (rate * 0.12)), kc = 1 - exp(-1 / (rate * 0.09)), kt = 1 - exp(-1 / (rate * 0.18))   // なめらかに追う（風は急には変わらない）
            let dt = 1 / rate
            let kGust = 1 - exp(-dt * 1.3), kGust2 = 1 - exp(-dt * 0.35), kFlut = 1 - exp(-dt * 9)
            var sL: Float = 0, sR: Float = 0
            for i in 0..<Int(frames) {
                g += (tg - g) * kg; fc += (tc - fc) * kc; tn += (tt - tn) * kt; pr += (tp - pr) * kg
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
                let fcm = fc * (1 + 0.55 * at + 0.12 * gust) * (0.7 + 0.55 * wv) * (1 + 0.06 * wq)   // 波で高さが上下する
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
                let flow = (band2 * 0.9 + band * 0.25) * g * 0.6 * gw * (q / 0.9) * (q / 0.9) * (1 + 0.25 * at) * (0.55 + 0.75 * wv)   // 帯を鋭くした分の響き（2 段なので q の 2 乗）は打ち消す
                let hiss = hb * g * 0.1 * gw * (0.8 + 0.6 * flut) * (1 + 0.5 * at) * (0.4 + 0.9 * wv)   // 高いシューは控えめに、波に合わせて
                let press = rl2 * pr * 5.2 * (0.8 + 0.4 * gw) * (1 + 0.75 * wq)   // 低いうなりは強めに（ゆらぐ時は大きく揺れる）
                // 揺さぶり（ボボボ）：速いほど速く強く脈打つ。脈の速さは突風で少しずれる
                let spd = min(1, pr * 2.2)                                       // 速さの目安（0〜1）
                buf += 2 * Float.pi * (9 + 11 * spd + 1.5 * gust) * dt; if buf > 2 * Float.pi { buf -= 2 * Float.pi }
                let throb = 0.5 + 0.5 * sin(buf), throbAmt = 0.55 * spd
                // ゴーッ：3 段の低域（250〜700 Hz より上を落とす）。揺さぶりで脈打つ
                let fro = min(0.5, 2 * sin(Float.pi * (250 + 450 * spd) / rate))
                rr1 += (wn - rr1) * fro; rr2 += (rr1 - rr2) * fro; rr3 += (rr2 - rr3) * fro
                let roar = rr3 * pr * 4.5 * gw * (1 - throbAmt + throbAmt * 2 * throb * throb)
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
                let buffet = bf2 * pr * flap * (0.55 + 0.7 * at) * (0.6 + 0.4 * gw)
                // ジリジリ：とても高いざらつき（熱い空気）。速い時だけ
                sizz += (wn - sizz) * 0.6
                let sizzle = (wn - sizz) * pr * 0.25 * spd * (0.7 + 0.5 * flut)
                // 宇宙船のエンジン（シュイーン）：低いうなり（少しずらした 2 つの音）と高い鳴き（6 倍あたり）。速いほど高く大きく、
                //   加速する時は鳴きが強まって音が上がる。曲がる時は高さが少し揺れる
                enS += (spd - enS) * (1 - exp(-dt * 2.5))
                enAcc += (max(0, (enS - enPrev) / dt) * 4 - enAcc) * (1 - exp(-dt * 3)); enPrev = enS
                let up = min(1, enAcc), fe = (70 + 230 * enS + 90 * up) * (1 + 0.04 * tn * sin(wa * 9))
                en1 += 2 * Float.pi * fe * dt; en2 += 2 * Float.pi * fe * 1.007 * dt; en3 += 2 * Float.pi * fe * 6.03 * dt
                beatF = fe * 0.007; beat += Double(beatF * dt)                  // 2 つの音の位相の差が 0 にそろう所（整数）が、うなりの山
                if en1 > 2 * Float.pi { en1 -= 2 * Float.pi }; if en2 > 2 * Float.pi { en2 -= 2 * Float.pi }; if en3 > 2 * Float.pi { en3 -= 2 * Float.pi }
                let ea = pow(max(0, g), 0.7) * (0.25 + 0.75 * enS)
                let engine = (sin(en1) * 0.5 + sin(en2) * 0.35 + sin(en1 * 2) * 0.12) * ea * 0.16 + sin(en3) * ea * (0.012 + 0.05 * up)
                var s = (flow + hiss + roar * 0.85 * (1 + 0.5 * wq) + crackle + sizzle + buffet + engine) * (1 + 0.1 * wq)   // ゴーッ（低い）も強めに
                // チリン（ベル：基音と 2.76 倍の部分音、すぐ減る）
                var bell: Float = 0
                for v in voices.indices {
                    voices[v].p += 2 * Float.pi * voices[v].f * dt; voices[v].t += dt
                    let env = voices[v].a * exp(-voices[v].t * 3.2) * nr          // 遠くから眺めている時は、かすかに
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
                s = max(-1, min(1, s))
                // 左右で少しずらす（広がり）。圧は真ん中
                sL += (s - sL) * 0.7; sR += (s - sR) * 0.55
                // 端はやわらかく丸める（割れない）
                if let R {
                    L[i] = tanh(sL * (1 - pan) * 2.6 + press + bell * 0.22)
                    R[i] = tanh(sR * pan * 2.6 + press + bell * 0.22)
                } else {
                    L[i] = tanh(sL * 1.6 + press + bell * 0.22)                 // 空間オーディオ：方向は環境が付ける
                }
            }
            voices.removeAll { $0.t > 2.2 }
            t.lock.lock(); t.beatCyc = beat; t.beatRate = Double(beatF); t.beatStamp = CACurrentMediaTime(); t.lock.unlock()
            return noErr
        }
        return (n, fmt)
    }
    /// 確かめ用：画面も音も出さずに seconds 秒ぶん作って、平均の大きさ（RMS）といちばん大きい値を返す
    ///   at：空間オーディオで、この場所から鳴らす（nil ならステレオ）。rmsR：右の耳の大きさ
    func renderTest(seconds: Double, speed: Double, zoom: Double, turn: Double = 0, chimeAt: Double? = nil, iceAt: Double? = nil, wav: String? = nil, at: SIMD3<Float>? = nil) -> (rms: Float, peak: Float, rmsR: Float) {
        let e = AVAudioEngine(), rate: Float = 48000
        guard let (n, fmt) = makeNode(rate, mono: at != nil), let outFmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2) else { return (0, 0, 0) }
        e.attach(n)
        do { try e.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 4800) } catch { return (0, 0, 0) }
        if let p = at { _ = attachSpatial(e, n, fmt); n.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z) } else { e.connect(n, to: e.mainMixerNode, format: fmt) }
        do { try e.start() } catch { return (0, 0, 0) }
        update(speed: speed, zoom: zoom, turn: turn, volume: 1)
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
        e.stop(); tgt.lock.lock(); tgt.gain = 0; tgt.lock.unlock()
        return (Float((sum / Double(max(1, cnt))).squareRoot()), peak, Float((sumR / Double(max(1, cnt))).squareRoot()))
    }
    func stop() {
        guard running else { return }
        engine?.stop(); if let n = node { engine?.detach(n) }; if let v = envNode { engine?.detach(v) }
        engine = nil; node = nil; envNode = nil; running = false
        tgt.lock.lock(); tgt.gain = 0; tgt.press = 0; tgt.turn = 0; tgt.chimes = []; tgt.lock.unlock()
    }
    /// 毎コマ：速さ（0〜1）・ズーム（0〜1）・曲がる速さ（−1〜1、＋は右へ）・音量から、風の大きさ・高さ・圧・曲がり
    /// near：引きの絵で、彗星が手前（1）か奥（0）か。奥へ行くと小さく、回り込んで手前に来ると少し大きく
    func update(speed: Double, zoom: Double, turn: Double = 0, near cn: Double = 0.5, volume: Double) {
        let s = Float(max(0, min(1, speed))), z = Float(max(0, min(1, zoom))), tr = Float(max(-1, min(1, turn)))
        let zp = pow(z, 1.3), far = 0.012 + 0.07 * pow(Float(max(0, min(1, cn))), 1.6)   // 外から眺めている時は、聞こえるか聞こえないか（奥で消えそう・手前で少し）
        let near = far * (1 - zp) + zp                                 // ズームで寄るほど大きく
        // 寄った時（ダイブ）は、ふつうの速さでも迫力が出るよう、速さの効き方をゆるく（遅めでも大きく）
        let sEff = pow(s, 1.5 - 0.6 * zp)
        let gain = sEff * near * (1 + 0.25 * abs(tr))  // 曲がる時は、ひと吹き強まる
        let press = pow(s, 2 - 0.7 * zp) * near * 0.5   // 空気抵抗（速さの 2 乗）を押し切る重さ。寄った時は強め
        let cutoff = 150 + 1300 * s * (0.6 + 0.4 * z)                 // 速いほど高い（低めのトーン）
        tgt.lock.lock(); tgt.gain = gain; tgt.press = press; tgt.cutoff = cutoff; tgt.turn = tr * s; tgt.vol = Float(volume); tgt.zoom = z; tgt.near = 1;   // チリンはいつもはっきり（チェックポイントの通過は聞こえた方がいい）
        tgt.lock.unlock()
    }
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
