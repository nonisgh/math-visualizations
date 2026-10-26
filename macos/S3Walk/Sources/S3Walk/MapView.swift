// 地図の窓：MTKView（MapRenderer）と、名前の札（文字の層）。ドラッグ・2 本指で回す、ピンチ・ホイールで近づく、ダブルクリックで元の向き。
//   Shift（か右）ドラッグで地図を動かすのは、設定の「地図を動かす」をオンにした時だけ（初めはオフ。右ドラッグも回す）
import SwiftUI
import AppKit
import MetalKit

final class MapMTKView: MTKView {
    weak var map: MapRenderer?
    private var last: NSPoint?
    private var panning = false
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { map?.home(); return }
        last = e.locationInWindow; panning = canPan && e.modifierFlags.contains(.shift)
    }
    override func rightMouseDown(with e: NSEvent) { last = e.locationInWindow; panning = canPan }
    private var canPan: Bool { map?.world.set.mapPan == true }
    override func mouseUp(with e: NSEvent) { last = nil }
    override func rightMouseUp(with e: NSEvent) { last = nil }
    override func mouseDragged(with e: NSEvent) { drag(e) }
    override func rightMouseDragged(with e: NSEvent) { drag(e) }
    private func drag(_ e: NSEvent) {
        guard let l = last, let m = map else { return }
        let p = e.locationInWindow; last = p
        let dx = Double(p.x - l.x), dy = Double(p.y - l.y)
        if panning { pan(dx, dy) } else { orbit(dx, dy) }
    }
    func orbit(_ dx: Double, _ dy: Double) {
        guard let m = map else { return }
        m.yaw -= dx * 0.008; m.pitch = max(-1.55, min(1.55, m.pitch - dy * 0.008))
    }
    func pan(_ dx: Double, _ dy: Double) {
        guard let m = map else { return }
        // 画面の右・上の向きに、注目点を動かす（距離に比例）
        let k = m.dist * 0.0016
        let r = SIMD3(-sin(m.yaw), cos(m.yaw), 0.0), up = SIMD3(-sin(m.pitch) * cos(m.yaw), -sin(m.pitch) * sin(m.yaw), cos(m.pitch))
        m.target -= r * dx * k + up * dy * k
    }
    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas {                         // トラックパッドの 2 本指：回す（Shift で動かす）
            if canPan && e.modifierFlags.contains(.shift) { pan(Double(e.scrollingDeltaX), -Double(e.scrollingDeltaY)) }
            else { orbit(Double(e.scrollingDeltaX), -Double(e.scrollingDeltaY)) }
        } else { zoom(1 - Double(e.scrollingDeltaY) * 0.05) }   // マウスのホイール：近づく・離れる
    }
    override func magnify(with e: NSEvent) { zoom(1 - Double(e.magnification)) }   // ピンチ
    func zoom(_ f: Double) { guard let m = map else { return }; m.dist = max(2, min(60, m.dist * f)) }
}

/// 地図の窓の中身（SwiftUI から使う）
struct MapPane: NSViewRepresentable {
    let model: AppModel
    var slot = 0
    func makeNSView(context: Context) -> NSView {
        let box = NSView(); box.wantsLayer = true
        let v = MapMTKView(frame: .zero, device: model.r.device)
        v.colorPixelFormat = .rgba16Float; v.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)   // EDR：1 より明るい色も出せる
        (v.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        v.depthStencilPixelFormat = .depth32Float; v.sampleCount = 4
        v.clearColor = MTLClearColor(red: 0x03 / 255.0, green: 0x07 / 255.0, blue: 0x12 / 255.0, alpha: 1)
        v.preferredFramesPerSecond = 60
        let m = model.renderer(slot)
        v.map = m; v.delegate = m
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        let labels = LabelLayerView(); labels.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(labels)
        for x in [v, labels] as [NSView] {
            NSLayoutConstraint.activate([x.leadingAnchor.constraint(equalTo: box.leadingAnchor), x.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                                         x.topAnchor.constraint(equalTo: box.topAnchor), x.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
        }
        m.onLabels = { [weak labels, weak v] ls in
            labels?.update(ls)
            if let s = v?.window?.backingScaleFactor { m.backingScale = s }
            if let v, let w = v.window { v.preferredFramesPerSecond = { let hz = max(60, w.screen?.maximumFramesPerSecond ?? 60); return hz / max(1, hz / 60) }() }
        }
        return box
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

extension MapLabel {
    /// 軸の名前の書体：KaTeX の数式用の斜体（TeX と同じ字形。次元おりがみ・ウェブ版と同じ）。無ければ STIX の斜体、Georgia の斜体
    static let axisFontName = NSFont(name: "KaTeX_Math-Italic", size: 12) != nil ? "KaTeX_Math-Italic" : NSFont(name: "STIXTwoText-Italic", size: 12) != nil ? "STIXTwoText-Italic" : "Georgia-Italic"
    static func axisFont(_ size: CGFloat) -> NSFont { NSFont(name: axisFontName, size: size) ?? NSFont.systemFont(ofSize: size) }
}
/// 名前の札：Core Animation の文字の層を、毎コマ動かす（マウスは下の地図へ通す）
final class LabelLayerView: NSView {
    private var pool: [CATextLayer] = []
    private var dots: [CALayer] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ ls: [(CGPoint, MapLabel, Bool)]) {
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = window?.backingScaleFactor ?? 2
        while pool.count < ls.count {
            let t = CATextLayer(); t.contentsScale = sc; t.alignmentMode = .center
            t.shadowColor = NSColor.black.cgColor; t.shadowOpacity = 0.9; t.shadowRadius = 2; t.shadowOffset = .zero
            let d = CALayer(); d.cornerRadius = 5; d.borderWidth = 2; d.borderColor = NSColor(srgbRed: 8 / 255, green: 12 / 255, blue: 28 / 255, alpha: 0.85).cgColor
            root.addSublayer(d); root.addSublayer(t); pool.append(t); dots.append(d)
        }
        for (i, t) in pool.enumerated() {
            let d = dots[i]
            guard i < ls.count, ls[i].2 else { t.isHidden = true; d.isHidden = true; continue }
            let (p, l, _) = ls[i]
            let col = NSColor(srgbRed: CGFloat(l.col.x), green: CGFloat(l.col.y), blue: CGFloat(l.col.z), alpha: 1).cgColor
            t.isHidden = false
            t.string = l.text
            t.foregroundColor = col
            t.opacity = l.dim ? 0.45 : 1
            if l.dot {                                                  // 極：直径 10 の色の点（暗いふち）と、右に名前（ウェブ版の mapDots）
                d.isHidden = false; d.backgroundColor = col; d.opacity = l.dim ? 0.45 : 1
                d.frame = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                t.backgroundColor = nil; t.cornerRadius = 0; t.shadowOpacity = 0.9; t.alignmentMode = .left
                t.font = NSFont.boldSystemFont(ofSize: l.size); t.fontSize = l.size
                t.frame = CGRect(x: p.x + 8, y: p.y - 8, width: 90, height: l.size + 6)
                continue
            }
            d.isHidden = true; t.alignmentMode = .center
            if l.bg {                                                   // 絵のモード：白い丸の上の絵文字
                let dd = l.size * 1.45
                t.backgroundColor = NSColor(white: 1, alpha: 0.85).cgColor; t.cornerRadius = dd / 2; t.shadowOpacity = 0.4
                t.frame = CGRect(x: p.x - dd / 2, y: p.y - dd / 2, width: dd, height: dd)
                t.font = NSFont(name: "Apple Color Emoji", size: l.size); t.fontSize = l.size
            } else if l.axis {
                // 軸の名前：ウェブ版と同じ数式の斜体（TeX のような STIX の斜体。無ければ Georgia の斜体）。窓のふちで切れないよう、窓の中に寄せる
                t.backgroundColor = nil; t.cornerRadius = 0; t.shadowOpacity = 0.9
                t.font = MapLabel.axisFont(l.size); t.fontSize = l.size
                let w: CGFloat = l.size * 1.4, h = l.size * 1.4, m: CGFloat = 4
                let x = min(max(p.x - w / 2, m), max(m, bounds.width - w - m)), y = min(max(p.y - h / 2, m), max(m, bounds.height - h - m))
                t.frame = CGRect(x: x, y: y, width: w, height: h)
            } else {
                t.backgroundColor = nil; t.cornerRadius = 0; t.shadowOpacity = 0.9
                t.font = NSFont.systemFont(ofSize: l.size, weight: .semibold); t.fontSize = l.size
                let w: CGFloat = 80, h = l.size + 6
                t.frame = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
            }
        }
        CATransaction.commit()
    }
}
