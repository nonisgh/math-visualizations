// 超球の窓の画面の外での描き方：シースルー・書き出し・記録・小窓の絵・GPU の時間・確かめの絵
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    func exAlloc(_ w: Int, _ h: Int) {
        guard exMS?.width != w || exMS?.height != h else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; exOut = device.makeTexture(descriptor: d)
        d.textureType = .type2DMultisample; d.sampleCount = 4; exMS = device.makeTexture(descriptor: d)
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = [.renderTarget]; dd.storageMode = .private; dd.textureType = .type2DMultisample; dd.sampleCount = 4; exDep = device.makeTexture(descriptor: dd)
    }
    /// 右の窓の絵は最後に左右反転する（ダイブの鏡）。反転した後の左の続きは、反転する前の右の続きなので、そちらを描いて反転する
    /// dst へ描く。rw・rh：右の窓の大きさ、lw：左の窓の幅、gap：仕切りの太さ（同じ単位）、b：明るさ
    func seeRender(_ cb: MTLCommandBuffer, _ dst: MTLTexture, _ w: Int, _ h: Int, rw: Double, rh: Double, lw: Double, gap: Double, b: Double) -> Bool {
        if seeMS?.width != w || seeMS?.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; seeOut = device.makeTexture(descriptor: d)
            d.textureType = .type2DMultisample; d.sampleCount = 4; seeMS = device.makeTexture(descriptor: d)
            let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
            dd.usage = [.renderTarget]; dd.storageMode = .private; dd.textureType = .type2DMultisample; dd.sampleCount = 4; seeDep = device.makeTexture(descriptor: dd)
        }
        guard let ms = seeMS, let dep = seeDep, let out = seeOut else { return false }
        let km = diveMirror, flip = km >= 0.5, c = Self.seeClipX(rw: rw, lw: lw, gap: gap, flip: flip)
        seeAsp = Float(rw / rh); seeClip = simd_float4x4(rows: [SIMD4(Float(c.a), 0, 0, Float(c.b)), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)])
        defer { seeAsp = nil; seeClip = matrix_identity_float4x4 }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = out
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        rp.depthAttachment.texture = dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return false }
        encode(e, CGSize(width: w, height: h)); e.endEncoding()
        let fp = MTLRenderPassDescriptor()
        fp.colorAttachments[0].texture = dst; fp.colorAttachments[0].loadAction = .dontCare; fp.colorAttachments[0].storeAction = .store
        guard let f = cb.makeRenderCommandEncoder(descriptor: fp) else { return false }
        // 鏡が右の窓の端を通る間だけ、いったん暗くして、描く側を入れかえる
        let dip = Float(smoothstep(0.03, 0.12, abs(km - 0.5)))
        var k = SIMD4<Float>(flip ? 2 : -1, 0, 1, Float(b) * dip)
        f.setRenderPipelineState(mirPipe); f.setFragmentTexture(out, index: 0); f.setFragmentBytes(&k, length: 16, index: 0)
        f.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); f.endEncoding()
        return true
    }
    /// 右の窓の x（−1〜1）→ 左の窓の絵の x（a x ＋ b）。反転する時は右の続きを、左端が仕切りのそばになるように
    static func seeClipX(rw: Double, lw: Double, gap: Double, flip: Bool) -> (a: Double, b: Double) {
        let a = rw / lw, e = 1 + 2 * gap / rw
        return flip ? (a, -1 - a * e) : (a, 1 + a * e)
    }
    /// 書き出し：シースルーの絵（画面と同じ）
    func seeTexture(_ cb: MTLCommandBuffer, w: Int, h: Int, rw: Double, rh: Double, lw: Double, gap: Double, b: Double) -> MTLTexture? {
        if seeDst?.width != w || seeDst?.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; seeDst = device.makeTexture(descriptor: d)
        }
        guard let t = seeDst, seeRender(cb, t, w, h, rw: rw, rh: rh, lw: lw, gap: gap, b: b) else { return nil }
        return t
    }
    func exPass(_ cb: MTLCommandBuffer, _ resolve: MTLTexture, _ w: Int, _ h: Int) -> Bool {
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
        var rec = VideoExport.RecFrame(t: now, dom: Self.domClock(now), walk: w, rawTrail: raw?.trail ?? w.trail,
            f: [st.diveT, st.diveFade, st.thirdK, st.chaseDistS, st.chasePitchS, st.chaseYawS, st.autoYaw, st.autoPitch, st.autoT, st.autoDyn,
                st.showDist, st.showRoll, st.diveYawOff, st.divePitchOff, st.cometSpd, st.cometNear, st.zw, st.pitch, st.roll, st.yaw,
                st.viewYaw, st.viewPitch, st.viewDist, st.camW, st.cutPos, st.cutPhi, st.airLift, st.coastG, st.meterM, st.paneCover, st.paneSeeB, st.paneSeeA, st.demoGlass, st.fillOn ? st.fillA : -1,
                Double(st.fillCount), st.fillAuto ? -1 : Double(st.fillLayers), st.chaosOn ? 1 : 0, st.worldR, st.drillK, st.drillS, st.drillR0],   // 詰める数・内側の球層（自動は −1）・内核の演出・R の世界・ドリル
            cometDir: st.cometDir, showFrame: st.showFrame, layers: st.layers, lzw: st.lzw, version: st.version,
            diveOn: st.diveOn, dragging: st.diveDragging, padHolding: st.padHolding, walkCam: HyperLabState.walkRendererGet?()?.cam, both: st.paneBoth, swap: st.lowSwap, first: st.paneFirst, pane: st.paneDive, ball: st.show3D && !st.paneBoth && !(st.diveOverview && st.paneDive))
        if st.tunnelNow, let b = st.tunBase, let x = st.tunnelPos() {       // トンネル：断面の向きの座標で（右 c・上 a・前 b）
            func loc(_ v: SIMD4<Double>) -> [Double] { [simd_dot(v, b.c), simd_dot(v, b.a), simd_dot(v, b.b)] }
            var t = loc(x) + [b.a.x, b.a.y, b.a.z, b.a.w, b.b.x, b.b.y, b.b.z, b.b.w, b.c.x, b.c.y, b.c.z, b.c.w]
            for h in st.tunHoles where h.open > 0.005 { t += [h.r] + loc(h.dir) + [h.open] }
            rec.tun = t
        } else if st.runLine && st.drillK > 0.01 {                          // ダイブ画面の超球ラン：金色の線の点（多い時は間引く）
            let p = st.runPathPoints(), m = 160
            let pick = p.count > m ? (0..<m).map { p[$0 * (p.count - 1) / (m - 1)] } : p
            rec.run = pick.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        }
        return rec
    }
    func paneTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        if let t = exPaneTex, t.width == w, t.height == h { return t }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; exPaneTex = device.makeTexture(descriptor: d); return exPaneTex
    }
    func wipeTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int, first: Bool = false) -> MTLTexture? {
        if exWipe == nil { exWipe = HyperLabRenderer(side: .right, state: st, view: nil); exWipe?.diveWipe = true }
        if first && exWipe1 == nil { exWipe1 = HyperLabRenderer(side: .right, state: st, view: nil); exWipe1?.diveWipe = true; exWipe1?.wipeFirst = true }
        guard let v = first ? exWipe1 : exWipe, let t = v.paneTexture(w, h) else { return nil }
        v.walkOverride = walkOverride; v.clockOverride = clockOverride; v.domOverride = domOverride
        return v.renderExport(cb, into: t, w: w, h: h, withMap: false) ? t : nil
    }
    /// 書き出し：外から見た超球の全体像（地図）を w×h に描いた絵（黒地のまま）
    func overviewTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int, motion: Bool = false) -> MTLTexture? {
        if exOverview == nil { exOverview = HyperLabRenderer(side: .right, state: st, view: nil); exOverview?.overview = true }
        if motion && exOverview2 == nil { exOverview2 = HyperLabRenderer(side: .right, state: st, view: nil); exOverview2?.overview = true; exOverview2?.ovMotion = true }
        guard let ov = motion ? exOverview2 : exOverview else { return nil }
        ov.walkOverride = walkOverride; ov.clockOverride = clockOverride; ov.domOverride = domOverride; ov.renderKOverride = 1
        return ov.renderInsetTexture(cb, w, h)
    }
    func ballTexture(_ cb: MTLCommandBuffer, _ w: Int, _ h: Int) -> MTLTexture? {
        if exBall == nil { exBall = HyperLabRenderer(side: .left, state: st, view: nil) }
        guard let b = exBall, let t = b.paneTexture(w, h) else { return nil }
        b.walkOverride = walkOverride; b.clockOverride = clockOverride; b.domOverride = domOverride; b.renderKOverride = 1
        b.renderLeft(cb, into: t); return t
    }
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
    /// 1 コマの GPU の時間を測って、ならして覚える（コマ数を決めるのに使う）
    func timeGPU(_ cb: MTLCommandBuffer) {
        let left = side == .left, s = st
        cb.addCompletedHandler { c in
            let ms = (c.gpuEndTime - c.gpuStartTime) * 1000
            guard ms > 0 && ms < 200 else { return }
            DispatchQueue.main.async { if left { s.gpuL = s.gpuL * 0.9 + ms * 0.1 } else { s.gpuR = s.gpuR * 0.9 + ms * 0.1 } }
        }
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
    func readImage(_ out: MTLTexture, _ w: Int, _ h: Int) -> CGImage? {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        out.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return ctx?.makeImage()
    }
}
