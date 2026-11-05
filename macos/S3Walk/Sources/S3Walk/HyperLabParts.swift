// 超球の窓の小さな部品：スライダー・さんぽのメニュー・パネルの並べ方・画面の上の文字
import SwiftUI
import MetalKit
import CoreVideo

/// スライダー：ドラッグ・矢印キー（スライダーを押してから。← → ↑ ↓、Shift で 10 倍）・数字の入力（右の欄に打って Return）
struct HLSlider: View {
    let name: String
    @Binding var value: Double
    let lo: Double, hi: Double, fmt: String
    @State private var text = ""
    @FocusState private var editing: Bool
    @FocusState private var focused: Bool
    /// 1 回のキーで動く量：表示のけた（%.0f なら 1、%.1f なら 0.1、%.2f なら 0.01）
    static func step(_ fmt: String) -> Double {
        if let r = fmt.range(of: #"\.(\d)f"#, options: .regularExpression), let d = Int(fmt[r].dropFirst().dropLast()) { return pow(10, -Double(d)) }
        return 1
    }
    /// 打った文字を数に（全角・−・°・% などは読み飛ばす。範囲の外は端に）。読めなければ nil
    static func parse(_ s: String, _ lo: Double, _ hi: Double) -> Double? {
        let a = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        let b = a.replacingOccurrences(of: "−", with: "-").filter { "0123456789.-+".contains($0) }
        guard let x = Double(b) else { return nil }
        return min(hi, max(lo, x))
    }
    /// 矢印キー k 回ぶん（k は ±1 か ±10）。けたにそろえて範囲の中に
    static func nudged(_ v: Double, _ k: Double, _ fmt: String, _ lo: Double, _ hi: Double) -> Double {
        let s = step(fmt)
        return min(hi, max(lo, ((v + k * s) / s).rounded() * s))
    }
    private var shown: String { String(format: fmt, value) }
    private func commit() {
        if let x = Self.parse(text, lo, hi) { value = x }
        text = shown
    }
    private func nudge(_ k: Double) { value = Self.nudged(value, k, fmt, lo, hi); text = shown }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name).font(.caption)
                Spacer(minLength: 2)
                TextField("", text: $text)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain).frame(width: 52).focused($editing)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .onSubmit { commit() }
                    .onChange(of: editing) { _, e in if !e { commit() } }
                    .help("数字を打って Return で決める")
            }
            Slider(value: $value, in: lo...hi)
                .focusable().focused($focused)
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if !focused { focused = true } })
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { p in
                    let down = p.key == .leftArrow || p.key == .downArrow
                    nudge((down ? -1 : 1) * (p.modifiers.contains(.shift) ? 10 : 1)); return .handled
                }
        }
        .onAppear { text = shown }
        .onChange(of: value) { _, _ in if !editing { text = shown } }
    }
}
/// さんぽメニュー：超球の窓に浮かぶ、さんぽの操作の小窓（さんぽの窓へ行かなくても歩ける）。半秒ごとに今の様子を読む
struct HLWalkMenu: View {
    let r: Renderer
    var close: () -> Void
    var openPanels: () -> Void = {}
    var panelsOn = false
    var toggleBar: () -> Void = {}
    var barOn = true
    @State private var tick = 0
    @State private var folded = false
    @State private var saving = false
    @State private var saveName = ""
    @ObservedObject private var store = RouteStore.shared
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk").foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
                Text("さんぽ").font(.caption.weight(.semibold))
                Text(r.walking || r.pathMode != .none || r.roaming ? "歩いている" : "止まっている").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if HyperLabState.mainBar != nil {
                    Button { toggleBar() } label: { Image(systemName: "menubar.rectangle") }.buttonStyle(.plain)
                        .foregroundStyle(barOn ? Color(red: 0.55, green: 0.8, blue: 1.0) : .secondary).help(barOn ? "メインメニューを隠す" : "メインメニューを出す")
                }
                Button { openPanels() } label: { Image(systemName: panelsOn ? "slider.horizontal.3" : "slider.horizontal.below.rectangle") }.buttonStyle(.plain)
                    .foregroundStyle(panelsOn ? Color(red: 0.55, green: 0.8, blue: 1.0) : .secondary).help("さんぽの設定（さんぽの窓のパネル全部。記録した道も）を出す・隠す")
                Button { folded.toggle() } label: { Image(systemName: folded ? "chevron.down" : "chevron.up") }.buttonStyle(.plain).help(folded ? "ひらく" : "たたむ")
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("さんぽメニューを隠す（パネルの「さんぽメニュー」でまた出す）")
            }
            if !folded {
                HStack(spacing: 6) {
                    Button("▶︎ 歩く") { r.walkFromHere(); tick &+= 1 }.help("道の設定に入っている道を、今いる所から作り直して歩く。道がなければ、ただ歩く")
                    Button("■ 停止") { r.stopWalking(); tick &+= 1 }.help("止まる。道の設定は残るので、「歩く」でその場から続けられる")
                    Button("⏮ 最初から") { r.restartRoute(); tick &+= 1 }.help("道の設定に入っている道を、最初の点から走り直す。跡と周回も初めから")
                    Button("縦横無尽") { r.roaming.toggle(); r.walking = r.roaming; r.pathMode = .none; tick &+= 1 }.help("歩き続けながら、向きがゆっくり変わる")
                }
                HStack(spacing: 4) {
                    Text("道").font(.caption2).foregroundStyle(.secondary)
                    Picker("道", selection: Binding<UUID?>(get: { let id = r.lastRoute?.id ?? (r.lastMode == .none ? store.sel : nil); return store.routes.contains { $0.id == id } ? id : nil },
                                                           set: { id in if let rt = store.routes.first(where: { $0.id == id }) { store.sel = rt.id; r.pickRoute(rt) }; tick &+= 1 })) {
                        Text(r.savableRoute == nil ? "道なし" : "保存していない道").tag(UUID?.none)
                        ForEach(store.routes.filter { !$0.pts.isEmpty }) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.labelsHidden().frame(width: 150).help("保存した道を呼び出す。「歩く」で今いる所から、「最初から」で最初の点から走る")
                    Button("保存") { saveName = r.savableRoute?.name ?? ""; saving = true }.disabled(r.savableRoute == nil).help("今の道に名前をつけて保存する。同じ名前があれば入れかえる")
                        .popover(isPresented: $saving) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("道の名前").font(.caption)
                                TextField("道の名前", text: $saveName).textFieldStyle(.roundedBorder).frame(width: 220)
                                Button("保存") {
                                    let n = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !n.isEmpty, let rt = r.savableRoute { r.pickRoute(store.saveAs(n, rt)) }
                                    saving = false; tick &+= 1
                                }.disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }.padding(12)
                        }
                }
                HStack(spacing: 4) {
                    Text("速さ").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { r.set.cruise }, set: { r.set.cruise = $0; if r.walking { r.autoSpeed = $0 }; tick &+= 1 }), in: 0.2...8).frame(width: 120)
                    Text(String(format: "×%.1f", r.set.cruise)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    Button("目印を置く") { r.addMark(); tick &+= 1 }
                    Button("跡を消す") { r.clearTrail(); tick &+= 1 }
                    Button("アナ極へ") { r.resetNorth(); tick &+= 1 }.help("出発点（アナ極）に戻る。目印は残す")
                }
                HStack(spacing: 4) {
                    // 道の速さ：歩いている道の今の速さと、次に歩き始める時の速さ（出発の速さ）をいっしょに
                    Text("道の速さ").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { r.pathMode != .none ? r.pathSpeed : r.set.routeStart }, set: { v in r.set.routeStart = v; if r.pathMode != .none { r.pathSpeed = v }; tick &+= 1 }), in: 0.2...16).frame(width: 100)
                        .help("決まった道・自分の道の速さ。次に歩き始める時も、この速さから")
                    Text(String(format: "×%.1f", r.pathMode != .none ? r.pathSpeed : r.set.routeStart)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                HStack(spacing: 4) {
                    Text("決まった道").font(.caption2).foregroundStyle(.secondary)
                    ForEach([(PathMode.spiral, "螺旋"), (.ring, "回る輪"), (.tour, "極めぐり")], id: \.0.rawValue) { m, name in
                        let on = m == .tour ? r.tourActive : r.pathMode == m
                        Button(name) { if on { r.pathMode = .none } else { r.startPath(m) }; tick &+= 1 }
                            .tint(on ? Color(red: 0.55, green: 0.8, blue: 1.0) : nil)
                    }
                }
            }
        }
        .controlSize(.small).font(.caption)
        .padding(10).frame(width: 250, alignment: .leading)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
        .onReceive(timer) { _ in tick &+= 1 }
    }
}
/// さんぽの設定：さんぽの窓のパネル（歩く・決まった道（記録した自分の道も）・目印・球層・見え方…）を、そのまま浮かぶ窓に。上のタブで切りかえ
struct HLWalkPanels: View {
    @ObservedObject var st: HyperLabState
    var body: some View {
        let titles = HyperLabState.walkPanelTitles
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("さんぽの設定").font(.caption.weight(.semibold))
                Spacer()
                Button { st.walkPanelOn = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("さんぽの設定を隠す")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(titles.indices, id: \.self) { i in
                        Button(titles[i]) { st.walkPanelSel = i }
                            .buttonStyle(.plain).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3)
                            .background((st.walkPanelSel == i ? Color(red: 0.25, green: 0.4, blue: 0.65) : Color.white.opacity(0.06)), in: Capsule())
                    }
                }
            }
            ScrollView { (HyperLabState.walkPanel?(min(st.walkPanelSel, max(0, titles.count - 1))) ?? AnyView(EmptyView())).padding(.trailing, 6) }
                .frame(maxHeight: 420)
        }
        .controlSize(.small).font(.caption)
        .padding(10).frame(width: 330, alignment: .leading)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
    }
}
/// パネルを s 倍の大きさで（幅は窓に合わせ、中身を 1/s の幅で並べてから s 倍に。高さは中身に合わせる。はみ出したら横にスクロール）
struct HLScaled<C: View>: View {
    let s: CGFloat
    var maxH: CGFloat = .infinity                                     // 見せる高さの上限（窓の高さの 4 割ほど。超球の画面を必ず残す）
    @ViewBuilder let content: () -> C
    @State private var h: CGFloat = 100
    var body: some View {
        // パネルは窓を押し広げない：横にはみ出した分も、上限より高い分も、スクロールして見る（全画面・iPad で端が切れない）
        let vis = min(h * s, max(80, maxH))
        GeometryReader { g in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                content().environment(\.hlPanelW, g.size.width / s).frame(minWidth: g.size.width / s, alignment: .topLeading).fixedSize(horizontal: true, vertical: true)
                    .background(GeometryReader { q in Color.clear.preference(key: HLHeightKey.self, value: q.size.height) })
            }
            .frame(width: g.size.width / s, height: vis / s, alignment: .topLeading)
            .scaleEffect(s, anchor: .topLeading)
        }
        .frame(height: vis)
        .onPreferenceChange(HLHeightKey.self) { v in if abs(v - h) > 0.5 { h = v } }
    }
}
/// パネルの中身を並べる幅（HLScaled が入れる。折り返す段 HLWrap が使う）
private struct HLPanelWKey: EnvironmentKey { static let defaultValue: CGFloat = .infinity }
extension EnvironmentValues { var hlPanelW: CGFloat { get { self[HLPanelWKey.self] } set { self[HLPanelWKey.self] = newValue } } }
/// 横に並べて、幅を越える所で次の行へ折り返す（各行は縦の真ん中でそろえる）
struct HLFlow: Layout {
    var spacing: CGFloat = 8, lineSpacing: CGFloat = 6, maxW: CGFloat = .infinity
    private func lines(_ sv: Subviews, _ w: CGFloat) -> [[(Int, CGSize)]] {
        var out: [[(Int, CGSize)]] = [[]], x: CGFloat = 0
        for (i, v) in sv.enumerated() {
            let sz = v.sizeThatFits(.unspecified)
            if !out[out.count - 1].isEmpty && x + spacing + sz.width > w { out.append([]); x = 0 }
            x += (out[out.count - 1].isEmpty ? 0 : spacing) + sz.width
            out[out.count - 1].append((i, sz))
        }
        return out
    }
    private func width(_ p: ProposedViewSize) -> CGFloat { min(maxW, p.width ?? .infinity) }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ls = lines(subviews, width(proposal))
        var w: CGFloat = 0, h: CGFloat = 0
        for l in ls {
            var lw: CGFloat = 0, lh: CGFloat = 0
            for (_, sz) in l { lw += sz.width; lh = max(lh, sz.height) }
            lw += spacing * CGFloat(max(0, l.count - 1))
            w = max(w, lw); h += lh
        }
        h += lineSpacing * CGFloat(max(0, ls.count - 1))
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for l in lines(subviews, width(proposal)) {
            var lh: CGFloat = 0
            for (_, sz) in l { lh = max(lh, sz.height) }
            var x = bounds.minX
            for (i, sz) in l { subviews[i].place(at: CGPoint(x: x, y: y + (lh - sz.height) / 2), proposal: ProposedViewSize(sz)); x += sz.width + spacing }
            y += lh + lineSpacing
        }
    }
}
/// パネルの 1 段：パネルの幅に収まらない時は、次の行へ折り返す（右の端が見切れて触れなくならないように）
struct HLWrap<C: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> C
    @Environment(\.hlPanelW) private var pw
    var body: some View { HLFlow(spacing: spacing, maxW: max(300, pw - 28)) { content() } }
}
struct HLHeightKey: PreferenceKey { static var defaultValue: CGFloat = 0; static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) } }
/// 画面の仕切り（ドラッグで動かす。位置は仕切りの並ぶ範囲の中の座標で渡す）
struct HLSplitBar: View {
    let vertical: Bool                                                // true：左右を分ける縦の仕切り
    let onDrag: (CGFloat) -> Void, onReset: () -> Void
    @State private var hover = false
    var body: some View {
        Rectangle().fill(hover ? Color(red: 0.35, green: 0.55, blue: 0.85) : Color(red: 0.12, green: 0.16, blue: 0.23))
            .frame(width: vertical ? 5 : nil, height: vertical ? nil : 5)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("hlsplit")).onChanged { v in onDrag(vertical ? v.location.x : v.location.y) })
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
            .onHover { h in
                hover = h
                #if os(macOS)
                if h { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                #endif
            }
            .help("ドラッグで画面の大きさを変える（ダブルクリックで半分に）")
    }
}
/// コマ数の表示（1 秒ごとに変わる。ここだけ描き直す）
final class HLStats: ObservableObject { @Published var text = "" }
/// 動いている間に変わる表示（角度の読み・景色の重ねぐあい）。パネル全体を描き直すと 40 ms ほど止まってカクつくので、ここだけ描き直す
final class HLLive: ObservableObject { @Published var angles = ""; @Published var fade = 0.0; @Published var lap = ""; @Published var coords = ""; @Published var pass = ""; @Published var passA = 0.0; @Published var passCol = SIMD3<Float>(1, 1, 1); @Published var noteA = 0.0; @Published var meter = 1.0; @Published var meterA = 0.0; @Published var meterShow = false; @Published var meterTop = 1.6
    /// 速度メーターの色：ふだん青緑、加速で明るく、減速で赤、上限で金
    static func meterRGB(_ m: Double, _ a: Double, _ top: Double) -> SIMD3<Double> {
        m >= top * 0.97 ? SIMD3(1, 0.82, 0.32) : a < -0.04 ? SIMD3(1, 0.36, 0.34) : a > 0.03 ? SIMD3(0.55, 1, 0.9) : SIMD3(0.3, 0.8, 0.86)
    }
}
/// 速度メーター（右の画面の下）：バーが今の速さ、白い印が平均、×は平均の何倍か
struct HLMeterLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        if live.meterShow {
            let w = 190 * scale, h = 7 * scale, top = live.meterTop * 1.2, c = HLLive.meterRGB(live.meter, live.meterA, live.meterTop), col = Color(red: c.x, green: c.y, blue: c.z)
            HStack(spacing: 7 * scale) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.5)).overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    Capsule().fill(col).frame(width: w * CGFloat(min(1, live.meter / top))).shadow(color: col.opacity(0.8), radius: 4 * scale)
                    Rectangle().fill(Color.white).frame(width: 2 * scale, height: h + 7 * scale).offset(x: w / CGFloat(top) - scale)
                }.frame(width: w, height: h)
                Text(String(format: "×%.1f", live.meter)).font(.system(size: 11 * scale, weight: .semibold, design: .monospaced)).foregroundStyle(col).frame(width: 36 * scale, alignment: .leading)
            }.padding(.bottom, 34 * scale).allowsHitTesting(false)
        }
    }
}
/// 赤玉・紫玉の交差で、左の列の仕切りをゆっくり下げる量（0〜1）。パネル全体を描き直さないよう、ここだけ見る
final class HLSplitAnim: ObservableObject { @Published var k = 0.0 }
struct HLSplitK<C: View>: View {
    @ObservedObject var a: HLSplitAnim
    let c: (Double) -> C
    init(a: HLSplitAnim, @ViewBuilder c: @escaping (Double) -> C) { self.a = a; self.c = c }
    var body: some View { c(a.k) }
}
/// 周回（右の画面の隅に小さく）
struct HLLapLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        if !live.lap.isEmpty {
            Text(live.lap).font(.system(size: 14 * scale, weight: .semibold, design: .serif)).foregroundStyle(Color(red: 0.85, green: 1.0, blue: 0.75))
                .padding(.horizontal, 11).padding(.vertical, 5).background(Color.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.64, green: 1.0, blue: 0.24).opacity(0.8), lineWidth: 1.5))   // 周回は蛍光の縁で目立たせる
                .padding(.top, 40).padding(.trailing, 12).allowsHitTesting(false)
        }
    }
}
/// 走行中の座標（右の画面の左上。計器のように 1 秒に 10 回書きかわる）
struct HLCoordLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        if !live.coords.isEmpty {
            Text(live.coords).font(.system(size: 10.5 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.62, green: 0.92, blue: 1.0)).lineSpacing(2)
                .shadow(color: Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.7), radius: 3)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.4, green: 0.85, blue: 1.0).opacity(0.35), lineWidth: 1))
                .padding(.top, 40).padding(.leading, 12).allowsHitTesting(false)
        }
    }
}
/// 極の通過のテロップ：スマホで見ても読める大きさ（画面の高さの 3.6%）。座標の下に出す
struct HLPassLabel: View {
    @ObservedObject var live: HLLive
    var scale: CGFloat = 1
    var body: some View {
        GeometryReader { g in
            if live.passA > 0.01 {
                let c = Color(red: Double(live.passCol.x), green: Double(live.passCol.y), blue: Double(live.passCol.z)), u = g.size.height / 1080, tc = PassCaption.textCol(live.passCol)
                Text(live.pass).font(PassCaption.fontName.map { .custom($0, size: g.size.height * 0.036) } ?? .system(size: g.size.height * 0.036, weight: .semibold)).foregroundStyle(Color(red: Double(tc.x), green: Double(tc.y), blue: Double(tc.z))).shadow(color: c.opacity(0.8), radius: 8 * u)
                    .padding(.horizontal, 16 * u).padding(.vertical, 8 * u)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 9 * u))
                    .background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 9 * u))   // 枠の中に、薄い同系色
                    .overlay(RoundedRectangle(cornerRadius: 9 * u).stroke(c.opacity(0.9), lineWidth: max(1, 2 * u)))
                    .padding(.top, (live.coords.isEmpty ? 40 : 100) * scale).padding(.leading, 12 * scale)
                    .opacity(live.passA).animation(.linear(duration: 0.1), value: live.passA)
            }
        }.allowsHitTesting(false)
    }
}
/// 赤玉・紫玉の解説のテロップ：上の地図の下に。玉へ近づいた時だけ（大きさは地図の幅の 4.2%）
struct HLNoteLabel: View {
    static let text = "赤と紫は正反対の点\n奥行きをつぶした地図では重なる"
    @ObservedObject var live: HLLive
    var body: some View {
        GeometryReader { g in
            if live.noteA > 0.01 {
                let u = g.size.width / 620, sz = g.size.width * 0.042
                Text(Self.text).font(PassCaption.fontName.map { .custom($0, size: sz) } ?? .system(size: sz, weight: .semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.9, blue: 1)).lineSpacing(3 * u)
                    .padding(.horizontal, 12 * u).padding(.vertical, 7 * u)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8 * u))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8 * u)
                    .opacity(live.noteA).animation(.linear(duration: 0.1), value: live.noteA)
            }
        }.allowsHitTesting(false)
    }
}
/// 極をいちばん近くで通った瞬間を見つける（テロップとチャイムで同じ。そばを通り過ぎ始めた時。何周目でも、何度通っても。はじめから極にいる時は数えない）
struct PolePass {
    private var inside = -1, best = -2.0, armed = false, first = true
    mutating func update(_ p: SIMD4<Double>) -> Int? {
        var bk = 0, bd = -2.0
        for (k, m) in FIXED.enumerated() { let d = simd_dot(p, m.c); if d > bd { bd = d; bk = k } }
        defer { first = false }
        if bd > 0.975 {
            if inside != bk { inside = bk; best = bd; armed = !first; return nil }
            if bd > best { best = bd } else if armed && bd < best - 1e-7 { armed = false; return bk }
        } else if bd < 0.9 { inside = -1; armed = false }
        else if armed { armed = false; return inside >= 0 ? inside : nil }           // とても速くて、近づく間に遠ざかった時
        return nil
    }
}
/// 極の通過のテロップの動き：極のそばに入ったら、3 秒ほど出す（画面と書き出しで同じ動き）
struct PassCaption {
    private var pass = PolePass(), shown = 0, t0 = -99.0
    /// 字幕のような丸文字：筑紫 A 丸ゴシック。ない時（iPad など）はヒラギノ丸ゴシック、それもなければ太字のシステム文字
    /// 文字の色：極の色を白へ寄せた、けばけばしくない同系色
    static func textCol(_ c: SIMD3<Float>) -> SIMD3<Float> { c * 0.38 + SIMD3<Float>(repeating: 0.62) }
    static let fontName: String? = ["TsukuARdGothic-Bold", "HiraMaruProN-W4"].first { HUDFont(name: $0, size: 12) != nil }
    mutating func update(_ p: SIMD4<Double>, _ t: Double, r: Double = 1) -> (text: String, col: SIMD3<Float>, a: Double) {   // r：今いる R の世界（R0.2 などを添える）
        if t < t0 { t0 = -99; pass = PolePass() }
        if let k = pass.update(p) { shown = k; t0 = t }
        let e = t - t0, m = FIXED[shown], en = MapRenderer.poleNameEN(m), a = min(1, max(0, e / 0.2)) * (1 - max(0, min(1, (e - 2.6) / 0.5)))
        let wt = MapRenderer.worldTag(r)
        return ("\(en == "Zenith" || en == "Nadir" ? en : en + " Pole")（\(MapRenderer.poleName(m))）\(wt.isEmpty ? "" : wt + " ")通過", MapRenderer.poleDotCol(shown), a)
    }
}
struct HLAnglesLabel: View {
    @ObservedObject var live: HLLive
    var body: some View {
        Text(live.angles).font(.system(size: 10, design: .monospaced)).padding(6)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct HLDiveOverlay: View {
    @ObservedObject var live: HLLive
    var body: some View { if live.fade > 0 { WalkScenePane(big: true).opacity(live.fade).allowsHitTesting(false) } }
}
struct HLHandoffNote: View {
    @ObservedObject var live: HLLive
    var body: some View {
        if live.fade > 0.99 {
            Text("景色は右の大きな画面へ（ダイブ中）").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.6)).allowsHitTesting(false)
        }
    }
}
struct HLStatsLabel: View {
    @ObservedObject var stats: HLStats
    var body: some View { Text(stats.text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
}
