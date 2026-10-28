// 4D 球アナロジーの音：音の素材は使わず、その場で合成する。
//   風切り音：宇宙に空気はないけれど、空気を押し切って進むように。雑音から 4 つの層を作る。
//     圧（低いうなり）：前の空気を押す重い音。速さの 2 乗で大きくなる（空気抵抗は速さの 2 乗）。
//     流れ（中の帯）：体のまわりを流れる空気。速いほど高く。
//     乱れ（高いシュー）：ちぎれる渦。ゆっくり変わる突風（ゆらぎ）で大きさと高さがふらつく。
//     曲がり：向きを変える速さで、流れの高さが滑るように上がり、曲がる側（外側）へ音が寄って、ひと吹き強まる（翼が空気をつかむように）。
//   ズーム（ダイブ）で寄るほど大きく近く、外から眺めている時は控えめ。
//   チリン：チェックポイントに当たった瞬間に、短いベルの音（極ごとに音の高さを変える。目印は高い音）。
//   描く側（毎コマ）から update・chime で目標を渡し、音を作る側（音の糸）はそれをなめらかに追う。
import AVFoundation

final class HyperSound {
    static let shared = HyperSound()
    private var engine: AVAudioEngine?
    private var node: AVAudioSourceNode?
    /// 描く側が書き、音の糸が読む目標（Float の読み書きだけ。少し古い値を読んでも音は崩れない）
    private final class Target { var gain: Float = 0; var cutoff: Float = 400; var turn: Float = 0; var press: Float = 0; var vol: Float = 0.8; var chimes: [(f: Float, a: Float)] = []; let lock = NSLock() }
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
        guard let (n, fmt) = makeNode(Float(sr > 0 ? sr : 48000)) else { return }
        e.attach(n); e.connect(n, to: e.mainMixerNode, format: fmt)
        do { try e.start() } catch { return }
        engine = e; node = n; running = true
    }
    /// 音を作る節（シュー・チリン）。rate は 1 秒の標本の数
    private func makeNode(_ rate: Float) -> (AVAudioSourceNode, AVAudioFormat)? {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2) else { return nil }
        // 音の糸の中だけで使う状態
        var g: Float = 0, fc: Float = 400, tn: Float = 0, pr: Float = 0
        var low: Float = 0, band: Float = 0, low2: Float = 0, band2: Float = 0      // 流れ（2 段の帯域）
        var hl: Float = 0, hb: Float = 0                                       // 乱れ（高い帯域）
        var rl1: Float = 0, rl2: Float = 0                                     // 圧（低い 2 段の低域）
        var gust: Float = 0, gust2: Float = 0, flut: Float = 0                 // 突風（ゆっくり）・はためき（速め）のゆらぎ
        var seed: UInt32 = 0x9E3779B9, ph: Float = 0
        var voices: [(f: Float, a: Float, p: Float, t: Float)] = []
        let t = tgt
        let n = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 2, let L = bufs[0].mData?.assumingMemoryBound(to: Float.self), let R = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            t.lock.lock(); let tg = t.gain * t.vol, tc = t.cutoff, tt = t.turn, tp = t.press * t.vol, vol = t.vol; let new = t.chimes; t.chimes = []; t.lock.unlock()
            for c in new where voices.count < 8 { voices.append((c.f, c.a * vol, 0, 0)) }
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
                // 流れ：帯の高さは速さ＋曲がり＋突風で滑る
                let fcm = fc * (1 + 0.55 * at + 0.12 * gust)
                let f1 = min(0.95, 2 * sin(Float.pi * fcm / rate)), q: Float = 0.9 - 0.35 * at   // 曲がる時は帯が細く鋭く（空気をつかむ）
                low += f1 * band; let high = wn - low - q * band; band += f1 * high
                let f2 = min(0.95, 2 * sin(Float.pi * fcm * 0.5 / rate))
                low2 += f2 * band2; let high2 = band - low2 - q * band2; band2 += f2 * high2
                // 乱れ：高いシュー（流れの 3 倍あたり）。はためきで細かくふるえる
                let f3 = min(0.95, 2 * sin(Float.pi * min(rate * 0.4, fcm * 3.1) / rate))
                hl += f3 * hb; let hh = wn - hl - 0.6 * hb; hb += f3 * hh
                // 圧：前の空気を押す重いうなり（雑音を 2 段で低く。60〜140 Hz あたり）
                let fr = min(0.5, 2 * sin(Float.pi * (60 + 80 * min(1, pr * 2)) / rate))
                rl1 += (wn - rl1) * fr; rl2 += (rl1 - rl2) * fr
                let flow = (band2 * 0.9 + band * 0.25) * g * 0.6 * gw * (q / 0.9) * (q / 0.9) * (1 + 0.25 * at)   // 帯を鋭くした分の響き（2 段なので q の 2 乗）は打ち消す
                let hiss = hb * g * 0.16 * gw * (0.8 + 0.6 * flut) * (1 + 0.5 * at)
                let press = rl2 * pr * 3.2 * (0.8 + 0.4 * gw)
                var s = flow + hiss
                // チリン（ベル：基音と 2.76 倍の部分音、すぐ減る）
                var bell: Float = 0
                for v in voices.indices {
                    voices[v].p += 2 * Float.pi * voices[v].f * dt; voices[v].t += dt
                    let env = voices[v].a * exp(-voices[v].t * 3.2)
                    bell += env * (sin(voices[v].p) + 0.35 * sin(voices[v].p * 2.76) * exp(-voices[v].t * 6))
                }
                // 左右：ゆっくり揺れて、曲がる時は外側へ寄る（右へ曲がると、左の耳に風が当たる）
                ph += 2 * Float.pi * 0.17 * dt; if ph > 2 * Float.pi { ph -= 2 * Float.pi }
                let pan = max(0.08, min(0.92, 0.5 + 0.12 * sin(ph) + 0.06 * gust - 0.32 * tn))
                s = max(-1, min(1, s))
                // 左右で少しずらす（広がり）。圧は真ん中
                sL += (s - sL) * 0.7; sR += (s - sR) * 0.55
                // 端はやわらかく丸める（割れない）
                L[i] = tanh(sL * (1 - pan) * 2.6 + press + bell * 0.22)
                R[i] = tanh(sR * pan * 2.6 + press + bell * 0.22)
            }
            voices.removeAll { $0.t > 2.2 }
            return noErr
        }
        return (n, fmt)
    }
    /// 確かめ用：画面も音も出さずに seconds 秒ぶん作って、平均の大きさ（RMS）といちばん大きい値を返す
    func renderTest(seconds: Double, speed: Double, zoom: Double, turn: Double = 0, chimeAt: Double? = nil, wav: String? = nil) -> (rms: Float, peak: Float) {
        let e = AVAudioEngine(), rate: Float = 48000
        guard let (n, fmt) = makeNode(rate) else { return (0, 0) }
        e.attach(n); e.connect(n, to: e.mainMixerNode, format: fmt)
        do { try e.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4800); try e.start() } catch { return (0, 0) }
        update(speed: speed, zoom: zoom, turn: turn, volume: 1)
        guard let buf = AVAudioPCMBuffer(pcmFormat: e.manualRenderingFormat, frameCapacity: 4800) else { return (0, 0) }
        let file = wav.flatMap { try? AVAudioFile(forWriting: URL(fileURLWithPath: $0), settings: fmt.settings) }   // 聞いて確かめる用の音のファイル
        var sum: Double = 0, cnt = 0, peak: Float = 0, done = 0.0, rung = false
        while done < seconds {
            if let c = chimeAt, !rung, done >= c { chime(pole: 2); rung = true }
            guard (try? e.renderOffline(4800, to: buf)) == .success, let L = buf.floatChannelData?[0] else { break }
            try? file?.write(from: buf)
            for i in 0..<Int(buf.frameLength) { let v = L[i]; sum += Double(v * v); cnt += 1; peak = max(peak, abs(v)) }
            done += 0.1
        }
        e.stop(); tgt.lock.lock(); tgt.gain = 0; tgt.lock.unlock()
        return (Float((sum / Double(max(1, cnt))).squareRoot()), peak)
    }
    func stop() {
        guard running else { return }
        engine?.stop(); if let n = node { engine?.detach(n) }
        engine = nil; node = nil; running = false
        tgt.lock.lock(); tgt.gain = 0; tgt.press = 0; tgt.turn = 0; tgt.chimes = []; tgt.lock.unlock()
    }
    /// 毎コマ：速さ（0〜1）・ズーム（0〜1）・曲がる速さ（−1〜1、＋は右へ）・音量から、風の大きさ・高さ・圧・曲がり
    func update(speed: Double, zoom: Double, turn: Double = 0, volume: Double) {
        let s = Float(max(0, min(1, speed))), z = Float(max(0, min(1, zoom))), tr = Float(max(-1, min(1, turn)))
        let near = 0.3 + 0.7 * z                                       // ズームで寄るほど大きく（外から見ている時は控えめ）
        let gain = pow(s, 1.5) * near * (1 + 0.25 * abs(tr))            // 曲がる時は、ひと吹き強まる
        let press = s * s * near * 0.5                                 // 空気抵抗（速さの 2 乗）を押し切る重さ
        let cutoff = 200 + 2400 * s * (0.55 + 0.45 * z)                // 速いほど高い
        tgt.lock.lock(); tgt.gain = gain; tgt.press = press; tgt.cutoff = cutoff; tgt.turn = tr * s; tgt.vol = Float(volume); tgt.lock.unlock()
    }
    /// チリン：極は番号ごとの音（ペンタトニック）、目印は高い音
    func chime(pole k: Int) {
        let scale: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.7, 1318.5]
        let f = k >= 0 ? scale[k % scale.count] : 1567.98
        tgt.lock.lock(); tgt.chimes.append((f, 1)); tgt.lock.unlock()
    }
}
