// 超球の窓の音へのつなぎ：極の通過・層・場所の音
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    /// w の高さが何番目の層の間か（球層を横切ったかを見る）
    static func layerIndex(_ w: Double, _ layers: Int) -> Int { w.isFinite ? Int(((w + 1) / 2 * Double(max(1, layers))).rounded(.down)) : 0 }
    /// 音のズーム：ダイブの出入りでぱっと変わらないよう、0.7 秒ほどかけて追いかける（音のリゾルブ）
    static func soundFollow(_ z: Double, to: Double, _ dt: Double) -> Double { z + (to - z) * (1 - exp(-dt / 0.2)) }
    func tickSound(_ dt: Double) {
        let snd = HyperSound.shared
        guard st.soundOn else { if snd.running { snd.stop() }; return }
        if !snd.running { snd.start(); sndPulseT = ProcessInfo.processInfo.systemUptime }
        var sp = 0.0
        if let w = (wsrc)?() {
            if let p0 = sndPos, dt > 0 { let d = simd_length(w.pos - p0); sp = d > 0.5 ? 0 : d / dt }   // 飛んだ時（初めに戻した時など）は数えない
            sndPos = w.pos
            let ly = Self.layerIndex(w.pos.w, st.layers)
            if let l0 = sndLayer, l0 != ly, sndSpeed > 0.02, st.soundLayer { snd.layerPass() }
            sndLayer = ly
            // 曲がる速さ：進む向きが、右の向き（景色の右）へ毎秒どれだけ変わったか（＋で右へ曲がる）
            var tr = 0.0
            let hd = w.head ?? w.fwd
            var sw = 0.0                                                  // 上下も含めて、向きが変わる速さ
            if let f0 = sndFwd, dt > 0, simd_length(w.vR) > 0.5 { let df0 = hd - f0, df = df0 - w.pos * simd_dot(df0, w.pos); tr = simd_length(df) > 0.5 ? 0 : simd_dot(df, w.vR) / dt; sw = simd_length(df) > 0.5 ? 0 : simd_length(df) / dt }   // 球面をまっすぐ進むだけでも向きの 4 次元の値は変わるので、その分（今いる所の向き）は数えない
            sndFwd = hd
            sndTurn += (tr - sndTurn) * (1 - exp(-dt * 4)); sndSwing += (sw - sndSwing) * (1 - exp(-dt * 6))
        }
        sndSpeed += (sp - sndSpeed) * (1 - exp(-dt * 6))
        let trn = max(-1, min(1, sndTurn / 1.2))
        // 低音のゆらぎ：きついカーブの時と、走っている間にときどき（不定期に。続けて起きないよう 1.2 秒あける）
        let nowS = ProcessInfo.processInfo.systemUptime, feel = (sndSpeed / 1.4).squareRoot() * st.feelK, spd01 = min(1, feel)
        if nowS - sndWobT > 1.2 && spd01 > 0.25 && (abs(trn) > 0.55 || Double.random(in: 0..<1) < dt * 0.12 * spd01) { snd.shellPass(); sndWobT = nowS }
        // シュパッ：ダイブ中、曲がっている時にときどき（カメラが揺れる時と同じころ。続けて鳴らないよう 1.8 秒あける）
        if Self.diveEase(st.diveT).1 > 0.5 && nowS - sndIceT > 1.8 && spd01 > 0.3 && abs(trn) > 0.25 && Double.random(in: 0..<1) < dt * 0.9 * abs(trn) { snd.icePop(); sndIceT = nowS }
        var aim = 0.0
        if let w = (wsrc)?() { aim = HyperSound.poleAim(w.pos, w.head ?? w.fwd) }
        sndAim += (aim - sndAim) * (1 - exp(-dt * 3))
        sndRush = HyperSound.rushStep(sndRush, swing: sndSwing / 1.2, speed: spd01, aim: sndAim, dt: dt)
        sndZ = Self.soundFollow(sndZ, to: Self.diveEase(st.diveT).1, dt)
        let sndZoom = sndZ
        snd.update(speed: feel, zoom: st.soundFar ? 1 : sndZoom, turn: trn, swing: sndSwing / 1.2, near: st.cometNear, volume: st.soundVol, fade: st.soundFar ? st.soundFarK + (1 - st.soundFarK) * sndZoom : 1)
        snd.tune(height: (wsrc)?().pos.w ?? 0, place: st.soundPlace, bass: st.soundBass, rough: st.soundRough, phones: st.soundPhones, rush: sndRush * (0.75 + 0.5 * sndAim) * st.soundRush, song: st.soundSong, wind: st.soundWind, rail: st.soundRail)
        // 空間オーディオ：彗星の方向から。一人称で寄り切った時は自分＝彗星なので、前から。曲がる時は外側の耳へ寄せる
        if snd.spatial != st.soundSpatial { snd.spatial = st.soundSpatial }
        let first = Self.diveEase(st.diveT).1 * (1 - st.thirdK)
        var d = st.cometDir * (1 - first) + SIMD3<Double>(0, 0, -1) * first; d.x -= 0.7 * trn
        let dl = simd_length(d); if dl > 1e-6 { d /= dl }
        snd.setPosition(SIMD3<Float>(d * 1.5))
        if st.dopplerOn, let w = (wsrc)?(), simd_length(w.vR) > 0.5 {      // 極のドップラー
            let f = HyperSound.flyPass(w.pos, head: w.head ?? w.fwd, right: w.vR, up: w.vU, feel: spd01)
            snd.setFly(hz: f.hz, amp: f.amp * st.dopK, at: f.at); st.flyA = f.amp; st.flySide = Double(f.at.x)
        } else { snd.setFly(hz: 200, amp: 0, at: SIMD3(0, 0, -1.5)); st.flyA = 0 }
        for h in Journey.hitPulse where h.t > sndPulseT && h.pole < 0 { snd.chime(pole: h.pole) }   // 目印のチリン
        if let w = (wsrc)?(), let k = sndPass.update(w.pos) { snd.chime(pole: k) }   // 極のチリン：テロップと同じ瞬間に、何度通っても
        if let last = Journey.hitPulse.last?.t, last > sndPulseT { sndPulseT = last }
    }
    func resolvePass(_ cb: MTLCommandBuffer, _ view: MTKView, _ dst: MTLTexture) {
        guard !overview && !diveWipe else { return }
        if view.framebufferOnly == st.resolveArmed { view.framebufferOnly = !st.resolveArmed }   // 絵を読むのは、この時だけ
        guard st.resolveArmed || CACurrentMediaTime() - st.resolveT < 0.7 else { snapTex = nil; return }
        let u = (CACurrentMediaTime() - st.resolveT) / 0.7
        if u >= 0 && u < 1 {
            if exGlass == nil { exGlass = InsetGlass(device) }
            if let s = snapTex { exGlass?.blend(cb, s, into: dst, x: 0, y: 0, w: dst.width, h: dst.height, a: Float(1 - u * u * (3 - 2 * u))) }
            return
        }
        guard !dst.isFramebufferOnly else { return }
        if snapTex?.width != dst.width || snapTex?.height != dst.height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: dst.width, height: dst.height, mipmapped: false)
            d.usage = .shaderRead; d.storageMode = .private; snapTex = device.makeTexture(descriptor: d)
        }
        if let s = snapTex, let b = cb.makeBlitCommandEncoder() {
            b.copy(from: dst, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: dst.width, height: dst.height, depth: 1),
                   to: s, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            b.endEncoding()
        }
    }
}
