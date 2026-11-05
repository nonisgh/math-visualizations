// 超球の窓の画面の入れ物：さんぽの景色・シースルー・左右の画面（Mac は NSView、iPad は UIView）
import SwiftUI
import MetalKit
import CoreVideo

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
        if (r.frameCount == lastFrame && sz == lastSize && now - sizeT > 0.6) || VideoExport.shared.proxyNow || HyperLabState.paneFreezeNow { return }
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
/// シースルーの絵を出す窓（描くのは右の窓の renderer。同じコマで出す）
private func makeSeeView() -> MTKView {
    let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice()); v.colorPixelFormat = .bgra8Unorm; v.isPaused = true; v.enableSetNeedsDisplay = false
    v.framebufferOnly = true; HyperLabRenderer.seeView = v; return v
}
#if os(macOS)
struct SeePane: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeSeeView() }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct SeePane: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeSeeView() }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif
#if os(macOS)
struct HyperPane: NSViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState; var overview = false; var motion = false; var wipe = false; var wipeMain = false; var wipeFirst = false
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); context.coordinator.r?.overview = overview; context.coordinator.r?.ovMotion = motion; context.coordinator.r?.diveWipe = wipe; context.coordinator.r?.wipeMain = wipeMain; context.coordinator.r?.wipeFirst = wipeFirst; v.delegate = context.coordinator.r; return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct HyperPane: UIViewRepresentable {
    let side: HyperLabRenderer.Side; let st: HyperLabState; var overview = false; var motion = false; var wipe = false; var wipeMain = false; var wipeFirst = false
    final class Holder { var r: HyperLabRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = HyperLabRenderer(side: side, state: st, view: v); context.coordinator.r?.overview = overview; context.coordinator.r?.ovMotion = motion; context.coordinator.r?.diveWipe = wipe; context.coordinator.r?.wipeMain = wipeMain; context.coordinator.r?.wipeFirst = wipeFirst; v.delegate = context.coordinator.r; return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif
