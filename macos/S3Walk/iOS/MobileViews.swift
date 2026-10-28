// iPad・iPhone の画面：横長（iPad の横向きなど）は 地図｜景色｜設定のパネル（Mac 版のパネルを縮めて）、細長い（iPhone など）は 景色の上に小さな地図と、下からの設定。
//   景色：1 本指のドラッグで進む向き、2 本指のドラッグで見回し（頭だけ）、左下の丸いスティックで歩く。地図：ドラッグで回す・ピンチで近づく・2 回タップで元の向き
import SwiftUI
import MetalKit
import UIKit

struct MobileRoot: View {
    @ObservedObject var model: MobileModel
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15 && geo.size.width > 700
            // 横長の時：地図｜景色｜パネル（Mac 版と同じ並び）。パネルは Mac 版の大きさ 330 を uiScale で縮める
            let panelW = min(geo.size.width * 0.34, 330 * model.uiScale)
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                HStack(spacing: 0) {
                    if wide && model.mapMode == .docked {
                        MapsColumn(model: model).frame(width: geo.size.width * (model.showPanel ? 0.3 : 0.36)); Divider()
                    }
                    ZStack(alignment: .topTrailing) {
                        SceneBox(model: model)
                        // すみの小さな地図（細長い画面で「並べる」の時も、すみに）
                        if model.mapMode == .corner || (!wide && model.mapMode == .docked) {
                            CornerMap(corner: model.b(\.mapCorner), size: model.b(\.mapMini), home: { model.mapRenderer.home() }, dock: { model.setMap(.docked) }) {
                                MapViewIOS(model: model, slot: 0)
                            }
                        }
                        if model.showPad {
                            VirtualPad(game: model.r.game) { model.showPad = false }.spaceControls()
                                .padding(.bottom, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)   // 景色の下の方に
                        }
                    }
                    if wide && model.showPanel {
                        Divider()
                        PanelColumn(model: model).frame(width: panelW)
                    }
                }
            }
        }
        // 細長い画面（iPhone・iPad の縦向き）：パネルは下からのシート
        // 試作：選んで全画面（右上の × で閉じる）
        .confirmationDialog("試作", isPresented: $model.askProto) {
            Button("超球アナロジー（Metal 版）") { model.proto = "hyper" }
            Button("次元おりがみ（光で描く）") { model.proto = "tess" }
            Button("次元おりがみ（ネイティブ版）") { model.proto = "origami" }
        }
        .fullScreenCover(isPresented: Binding(get: { model.proto != nil }, set: { if !$0 { model.proto = nil } })) {
            ZStack(alignment: .topTrailing) {
                if model.proto == "tess" { TessLabView() } else if model.proto == "origami" { OrigamiView() } else { HyperLabView() }
                Button { model.proto = nil } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8)) }.padding(14)
            }
        }
        // ウェブ版の数学アプリ：下からのシートに一覧。選ぶとその中で開く（半分の高さにすると、景色と一緒に見られる）
        .sheet(isPresented: $model.showWeb) {
            WebLabList().presentationDetents([.large, .medium]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: Binding(get: { model.showPanel && !MobileRoot.isWide() }, set: { if !$0 { model.showPanel = false } })) {
            PanelColumn(model: model).presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
    static func isWide() -> Bool {
        let b = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.bounds.size ?? UIScreen.main.bounds.size
        return b.width > b.height * 1.15 && b.width > 700
    }
}

/// Mac 版の設定のパネル（Dock.swift の DockColumn）を、uiScale で縮めて入れる
struct PanelColumn: View {
    @ObservedObject var model: MobileModel
    var body: some View {
        let k = CGFloat(model.uiScale)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("設定").font(.headline).foregroundStyle(Space.lilac)
                Spacer()
                Image(systemName: "textformat.size.smaller").foregroundStyle(Space.slate)
                Slider(value: $model.uiScale, in: 0.6...1.3).frame(maxWidth: 110).tint(Space.sky)
                Image(systemName: "textformat.size.larger").foregroundStyle(Space.slate)
                Button { model.showPanel = false } label: { Image(systemName: "xmark.circle.fill").font(.title3) }.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ScaledBox(k: k) {
                VStack(spacing: 6) {
                    HStack {
                        Button("Mac の見え方に") { model.loadMacLook() }.fixedSize()
                        Spacer()
                        Picker("地図", selection: Binding(get: { model.mapMode }, set: { model.setMap($0) })) {
                            Text("地図なし").tag(MapMode.hidden); Text("並べる").tag(MapMode.docked); Text("すみに").tag(MapMode.corner)
                        }.pickerStyle(.segmented).fixedSize()
                    }
                    .padding(.horizontal, 8).padding(.top, 6)
                    DockColumn(model: model, dock: model.dock)
                }
            }
        }
        .background(SpaceBackground().ignoresSafeArea())
    }
}

/// 中身を 1/k の大きさで並べてから k 倍に縮める（Mac 版のパネルの大きさのまま、狭い画面に入れる）。指で触る所も一緒に縮む
struct ScaledBox<C: View>: View {
    let k: CGFloat
    @ViewBuilder var content: C
    var body: some View {
        GeometryReader { g in
            content.frame(width: g.size.width / k, height: g.size.height / k)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
    }
}

/// 地図の列：S³ の地図、2 枚目の地図、S² の仲間（設定でオンのものを縦に）
struct MapsColumn: View {
    @ObservedObject var model: MobileModel
    var body: some View {
        VStack(spacing: 1) {
            MapBox(model: model, slot: 0)
            if model.r.set.map2On { MapBox(model: model, slot: 1) }
            if model.r.set.s2On { MapBox(model: model, slot: 2) }
        }
    }
}

/// 景色と、その上の操作（スティック・ボタン・表示・知らせ）
struct SceneBox: View {
    @ObservedObject var model: MobileModel
    var body: some View {
        ZStack {
            SceneView(model: model).ignoresSafeArea()               // 景色は画面いっぱい、表示とボタンは切り欠き・角を避ける
            VStack(alignment: .leading, spacing: 6) {
                Text(model.hudText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Space.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                if !model.notice.isEmpty {
                    Text(model.notice).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Space.panel.opacity(0.88), in: Capsule())
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Joystick(model: model)
                    Spacer()
                    VStack(spacing: 10) {
                        RoundButton(icon: model.r.walking ? "pause.fill" : "figure.walk", on: model.r.walking) { model.r.walking.toggle(); model.r.roaming = false; model.changed() }
                        RoundButton(icon: "bolt.fill", on: false) { model.r.turbo(); model.changed() }
                        RoundButton(icon: "scope", on: false) { model.r.cam.hy = 0; model.r.cam.hp = 0; model.changed() }
                        RoundButton(icon: "house", on: false) { model.r.resetNorth(); model.say("アナ極に戻った"); model.changed() }
                        RoundButton(icon: "square.grid.2x2", on: model.showWeb) { model.showWeb = true }   // ウェブ版の数学アプリの一覧（シート）
                        RoundButton(icon: "flask", on: model.proto != nil) { model.askProto = true }   // 試作（Metal で描き直しているもの）を選んで全画面で
                        RoundButton(icon: "gamecontroller", on: model.showPad) { model.showPad.toggle() }
                        RoundButton(icon: "map", on: model.mapMode != .hidden) { model.pad("options") }   // コントローラーの − と同じ（前の置き方で出す）
                        RoundButton(icon: "slider.horizontal.3", on: model.showPanel) { model.showPanel.toggle() }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 18)
        }
    }
}

struct RoundButton: View {
    let icon: String; let on: Bool; let act: () -> Void
    var body: some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                .foregroundStyle(on ? Space.bg : .white)
                .background(on ? Space.sky : Space.panel.opacity(0.75), in: Circle())
                .overlay(Circle().stroke(Space.line))
        }
    }
}

/// 歩くスティック（コントローラーの左スティックと同じ：上で前、下で後ろ、左右で横歩き）
struct Joystick: View {
    @ObservedObject var model: MobileModel
    @State private var knob = CGSize.zero
    let R: CGFloat = 56
    var body: some View {
        ZStack {
            Circle().fill(Space.panel.opacity(0.55)).overlay(Circle().stroke(Space.line))
            Circle().fill(Space.sky.opacity(0.85)).frame(width: 46, height: 46).offset(knob)
        }
        .frame(width: R * 2, height: R * 2)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            var d = g.translation; let l = hypot(d.width, d.height)
            if l > R { d = CGSize(width: d.width / l * R, height: d.height / l * R) }
            knob = d
            model.r.game.fake = (SIMD3(Double(d.width / R), 0, Double(-d.height / R)), .zero, false, false, false)
        }.onEnded { _ in
            knob = .zero; model.r.game.fake = nil
        })
    }
}

// ---- 景色の MTKView：1 本指で進む向き、2 本指で見回し ----
final class SceneMTK: MTKView {
    weak var r: Renderer?
    @objc func pan1(_ g: UIPanGestureRecognizer) {
        guard let r else { return }
        let d = g.translation(in: self); g.setTranslation(.zero, in: self)
        r.cam.az += Double(d.x) * 0.25; r.cam.el -= Double(d.y) * 0.25
        r.cam.clampAngles(free: r.set.free360)
    }
    @objc func pan2(_ g: UIPanGestureRecognizer) {
        guard let r else { return }
        let d = g.translation(in: self); g.setTranslation(.zero, in: self)
        r.cam.hy += Double(d.x) * 0.25; r.cam.hp -= Double(d.y) * 0.25
        r.cam.clampAngles(free: r.set.free360)
    }
}
struct SceneView: UIViewRepresentable {
    let model: MobileModel
    func makeUIView(context: Context) -> SceneMTK {
        let v = SceneMTK(frame: .zero, device: model.r.device)
        v.r = model.r; v.delegate = model.r
        v.colorPixelFormat = .bgra8Unorm                      // 0〜1 の色は Mac 版・ウェブ版と同じ（sRGB のまま）
        v.preferredFramesPerSecond = 60
        v.framebufferOnly = true
        v.contentScaleFactor = UIScreen.main.scale            // 画面は細かく（景色だけ sceneScale で粗く）
        let p1 = UIPanGestureRecognizer(target: v, action: #selector(SceneMTK.pan1(_:))); p1.maximumNumberOfTouches = 1
        let p2 = UIPanGestureRecognizer(target: v, action: #selector(SceneMTK.pan2(_:))); p2.minimumNumberOfTouches = 2
        v.addGestureRecognizer(p1); v.addGestureRecognizer(p2)
        // 景色の上の 8 つの極（色の点と「名前 距離」。Mac 版の PoleOverlay と同じ）
        let po = PoleOverlayIOS(frame: v.bounds); po.autoresizingMask = [.flexibleWidth, .flexibleHeight]; po.isUserInteractionEnabled = false; v.addSubview(po)
        model.r.onPoles = { [weak po] ls in po?.update(ls) }
        model.sceneView = v
        DispatchQueue.main.async { model.applyScale() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.r.prewarm() }
        return v
    }
    func updateUIView(_ v: SceneMTK, context: Context) {}
}

/// 景色の上の 8 つの極（Mac 版の PoleOverlay と同じ）：直径 12 の色の点（暗いふち、遠いほど小さく 5 まで）と、右に「名前 距離」。
///   点が重なる時は手前の点だけ。名前はアナ極を先に、あとは手前から順に、点の右・左・上・下で空いている所へ（どこも空いていなければ隠す）
final class PoleOverlayIOS: UIView {
    private var dots: [CALayer] = [], labs: [CATextLayer] = []
    func update(_ ls: [Renderer.PoleLab]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = window?.screen.scale ?? 2, font = UIFont.boldSystemFont(ofSize: 11)
        while dots.count < 8 {
            let d = CALayer(); d.borderWidth = 2; d.borderColor = UIColor(red: 8 / 255, green: 12 / 255, blue: 28 / 255, alpha: 0.85).cgColor
            let t = CATextLayer(); t.contentsScale = sc; t.font = font; t.fontSize = 11; t.alignmentMode = .left
            t.shadowColor = UIColor.black.cgColor; t.shadowOpacity = 1; t.shadowRadius = 2; t.shadowOffset = .zero
            layer.addSublayer(d); layer.addSublayer(t); dots.append(d); labs.append(t)
        }
        let w = bounds.width, h = bounds.height
        struct It { var k: Int; var x: CGFloat; var y: CGFloat; var lab: Renderer.PoleLab }
        var items = ls.prefix(8).enumerated().map { It(k: $0.offset, x: CGFloat(0.5 + 0.5 * $0.element.x) * w, y: CGFloat(0.5 - 0.5 * $0.element.y) * h, lab: $0.element) }
        items.sort { $0.lab.d < $1.lab.d }
        for i in 0..<8 { dots[i].isHidden = true; labs[i].isHidden = true }
        var shown: [It] = []
        for (z, it) in items.enumerated() {
            let d = dots[it.k], col = UIColor(red: CGFloat(it.lab.col.x), green: CGFloat(it.lab.col.y), blue: CGFloat(it.lab.col.z), alpha: 1).cgColor
            d.zPosition = CGFloat(100 - z); labs[it.k].zPosition = CGFloat(200 - z)
            if shown.contains(where: { hypot($0.x - it.x, $0.y - it.y) < 9 }) { continue }
            let q = min(1, it.lab.d / (Double.pi / 2)), r = CGFloat(12 - 7 * q * q * (3 - 2 * q))   // 距離 0 で 12、90° で 5
            d.isHidden = false; d.backgroundColor = col; d.cornerRadius = r / 2; d.frame = CGRect(x: it.x - r / 2, y: it.y - r / 2, width: r, height: r)
            shown.append(it)
        }
        var rects: [CGRect] = []
        for it in items.sorted(by: { ($0.lab.isN ? 0 : 1, $0.lab.d) < ($1.lab.isN ? 0 : 1, $1.lab.d) }) {
            let t = labs[it.k], bw = ceil((it.lab.name as NSString).size(withAttributes: [.font: font]).width) + 2, bh: CGFloat = 14
            for (dx, dy) in [(CGFloat(8), CGFloat(-8)), (-8 - bw, -8), (-bw / 2, -23), (-bw / 2, 8)] {
                let r = CGRect(x: it.x + dx, y: it.y + dy, width: bw, height: bh)
                if r.minX < 0 || r.maxX > w || r.minY < 0 || r.maxY > h { continue }
                if rects.contains(where: { $0.intersects(r) }) { continue }
                if shown.contains(where: { $0.k != it.k && $0.x > r.minX - 4 && $0.x < r.maxX + 4 && $0.y > r.minY - 4 && $0.y < r.maxY + 4 }) { continue }
                t.isHidden = false; t.string = it.lab.name
                t.foregroundColor = UIColor(red: CGFloat(it.lab.col.x), green: CGFloat(it.lab.col.y), blue: CGFloat(it.lab.col.z), alpha: 1).cgColor
                t.frame = r.insetBy(dx: 0, dy: -1); rects.append(r); break
            }
        }
        CATransaction.commit()
    }
}

// ---- 地図の MTKView：ドラッグで回す、ピンチで近づく、2 回タップで元の向き ----
final class MapMTK: MTKView {
    weak var map: MapRenderer?
    @objc func pan(_ g: UIPanGestureRecognizer) {
        guard let m = map else { return }
        let d = g.translation(in: self); g.setTranslation(.zero, in: self)
        m.yaw -= Double(d.x) * 0.008; m.pitch = max(-1.55, min(1.55, m.pitch + Double(d.y) * 0.008))
    }
    @objc func pinch(_ g: UIPinchGestureRecognizer) {
        guard let m = map else { return }
        m.dist = max(2, min(60, m.dist / Double(g.scale))); g.scale = 1
    }
    @objc func tap2() { map?.home() }
}
struct MapBox: View {
    @ObservedObject var model: MobileModel
    let slot: Int
    var body: some View {
        ZStack(alignment: .topLeading) {
            MapViewIOS(model: model, slot: slot)
            HStack(spacing: 6) {
                Text(["S³ の地図", "地図 2", "S² の仲間"][slot]).font(.caption.weight(.bold)).foregroundStyle(Space.lilac)
                Button { model.renderer(slot).home() } label: { Image(systemName: "scope").font(.caption) }.foregroundStyle(Space.sky)
                if slot == 0 { MapBrightButton(model: model).font(.caption).foregroundStyle(Space.sky) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Space.panel.opacity(0.85), in: Capsule()).padding(8)
        }
    }
}
struct MapViewIOS: UIViewRepresentable {
    let model: MobileModel
    let slot: Int
    func makeUIView(context: Context) -> UIView {
        let box = UIView(); box.backgroundColor = UIColor(red: 0x03 / 255, green: 0x07 / 255, blue: 0x12 / 255, alpha: 1)
        let v = MapMTK(frame: .zero, device: model.r.device)
        v.colorPixelFormat = .bgra8Unorm; v.depthStencilPixelFormat = .invalid; v.sampleCount = 1   // 地図は自分で 2 倍に描いて縮める（MapRenderer.encodeSS）
        v.clearColor = MTLClearColor(red: 0x03 / 255.0, green: 0x07 / 255.0, blue: 0x12 / 255.0, alpha: 1)
        v.preferredFramesPerSecond = 60
        let m = model.renderer(slot); m.backingScale = UIScreen.main.scale
        v.map = m; v.delegate = m
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        let labels = LabelLayerIOS(); labels.translatesAutoresizingMaskIntoConstraints = false; labels.isUserInteractionEnabled = false
        box.addSubview(labels)
        for x in [v, labels] as [UIView] {
            NSLayoutConstraint.activate([x.leadingAnchor.constraint(equalTo: box.leadingAnchor), x.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                                         x.topAnchor.constraint(equalTo: box.topAnchor), x.bottomAnchor.constraint(equalTo: box.bottomAnchor)])
        }
        m.onLabels = { [weak labels, weak v] ls in
            labels?.update(ls)
            let want = m.world.set.quiet ? 20 : 60                   // 静かモードの地図は 20 fps
            m.superSample = m.world.set.quiet ? 1 : 2                // 静かモードは縮めずにそのまま（軽く）
            if let v, v.preferredFramesPerSecond != want { v.preferredFramesPerSecond = want }
        }
        v.addGestureRecognizer(UIPanGestureRecognizer(target: v, action: #selector(MapMTK.pan(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: v, action: #selector(MapMTK.pinch(_:))))
        let t2 = UITapGestureRecognizer(target: v, action: #selector(MapMTK.tap2)); t2.numberOfTapsRequired = 2; v.addGestureRecognizer(t2)
        return box
    }
    func updateUIView(_ v: UIView, context: Context) {}
}

/// 地図の名前の札（Mac 版の LabelLayerView と同じ：極は色の点と名前、軸は数式の斜体）
final class LabelLayerIOS: UIView {
    private var pool: [CATextLayer] = [], dots: [CALayer] = []
    static let axisFont: UIFont = UIFont(name: "KaTeX_Math-Italic", size: 20) ?? UIFont.italicSystemFont(ofSize: 20)
    func update(_ ls: [(CGPoint, MapLabel, Bool)]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = window?.screen.scale ?? 2
        while pool.count < ls.count {
            let t = CATextLayer(); t.contentsScale = sc; t.alignmentMode = .center
            t.shadowColor = UIColor.black.cgColor; t.shadowOpacity = 0.9; t.shadowRadius = 2; t.shadowOffset = .zero
            let d = CALayer(); d.cornerRadius = 5; d.borderWidth = 2; d.borderColor = UIColor(red: 8 / 255, green: 12 / 255, blue: 28 / 255, alpha: 0.85).cgColor
            layer.addSublayer(d); layer.addSublayer(t); pool.append(t); dots.append(d)
        }
        for (i, t) in pool.enumerated() {
            let d = dots[i]
            guard i < ls.count, ls[i].2 else { t.isHidden = true; d.isHidden = true; continue }
            let (p, l, _) = ls[i]
            let col = UIColor(red: CGFloat(l.col.x), green: CGFloat(l.col.y), blue: CGFloat(l.col.z), alpha: 1).cgColor
            t.isHidden = false; t.string = l.text; t.foregroundColor = col; t.opacity = l.dim ? 0.45 : 1
            if let img = l.img {                                        // 模型の小さな絵：丸く切って、ふちは目印の色
                t.isHidden = true; d.isHidden = false; d.contents = img; d.contentsGravity = .resizeAspectFill; d.masksToBounds = true
                d.backgroundColor = UIColor.black.cgColor; d.borderColor = col; d.opacity = l.dim ? 0.5 : 1
                d.cornerRadius = l.size / 2; d.frame = CGRect(x: p.x - l.size / 2 + l.dx, y: p.y - l.size / 2, width: l.size, height: l.size)
                continue
            }
            d.contents = nil; d.masksToBounds = false; d.cornerRadius = 5; d.borderColor = UIColor(red: 8 / 255, green: 12 / 255, blue: 28 / 255, alpha: 0.85).cgColor
            if l.dot {
                d.isHidden = false; d.backgroundColor = col; d.opacity = l.dim ? 0.45 : 1
                d.frame = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                t.alignmentMode = .left; t.font = UIFont.boldSystemFont(ofSize: l.size); t.fontSize = l.size
                t.frame = CGRect(x: p.x + 8, y: p.y - 8, width: 90, height: l.size + 6); continue
            }
            d.isHidden = true; t.alignmentMode = .center
            if l.axis { t.font = LabelLayerIOS.axisFont; t.fontSize = l.size }
            else { t.font = UIFont.systemFont(ofSize: l.size, weight: .semibold); t.fontSize = l.size }
            let w: CGFloat = l.axis ? l.size * 1.4 : 80, h = l.axis ? l.size * 1.4 : l.size + 6
            t.frame = CGRect(x: min(max(p.x - w / 2, 4), max(4, bounds.width - w - 4)), y: min(max(p.y - h / 2, 4), max(4, bounds.height - h - 4)), width: w, height: h)
        }
        CATransaction.commit()
    }
}
