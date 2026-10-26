// パネルのドッキング（Photoshop のような画面）の 1 段階目：設定を 1 枚ずつのパネルにして、右のドックに積む。
//   見出しのドラッグで並べかえ、見出しのクリックでたたむ、Tab で全部隠す（AppModel.toggleAllPanels）。並びとたたみは保存。
//   スライダーは Photoshop 風のスクラブ式：名前の上を左右にドラッグで値を変える（⇧ で 10 倍・⌥ で 0.1 倍の刻み）、
//   数字をクリックして直接入力、名前を ⌥クリックで初めの値に。案の全体は DOCKING_PLAN.md
import SwiftUI
import AppKit

/// パネルの種類（今のところ右のドックに積む）
enum PanelID: String, CaseIterable, Codable {
    case walk, path, marks, shell, view, lines, map, map2, mac, screen
    var title: String {
        switch self {
        case .walk: return "歩く"
        case .path: return "決まった道"
        case .marks: return "目印"
        case .shell: return "球層"
        case .view: return "見え方"
        case .lines: return "線の見え方と光"
        case .map: return "S³ の地図"
        case .map2: return "地図 2"
        case .mac: return "コントローラーと触覚"
        case .screen: return "画面"
        }
    }
    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .path: return "tornado"
        case .marks: return "mappin.and.ellipse"
        case .shell: return "circle.circle"
        case .view: return "eye"
        case .lines: return "sparkles"
        case .map: return "map"
        case .map2: return "map.fill"
        case .mac: return "gamecontroller"
        case .screen: return "display"
        }
    }
}

/// 浮いた窓 1 つ：タブでまとめたパネルと、選んでいるタブ
struct FloatGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var tabs: [PanelID]
    var selected: PanelID
}

/// ドックの並び・たたみ・浮いた窓（UserDefaults に保存）
final class DockState: ObservableObject {
    static let key = "s3walk.dock.v1"
    @Published var order: [PanelID] = PanelID.allCases { didSet { save() } }
    @Published var collapsed: Set<PanelID> = [] { didSet { save() } }
    @Published var floating: [FloatGroup] = [] { didSet { save() } }
    var frames: [UUID: CGRect] = [:]                       // 浮いた窓の場所（動かすたびに書く。画面は作り直さない）
    /// ドックにあるパネル（浮いているものを除く）
    var docked: [PanelID] { order.filter { p in !floating.contains { $0.tabs.contains(p) } } }
    init() {
        guard let d = UserDefaults.standard.dictionary(forKey: DockState.key) else { return }
        if let o = d["order"] as? [String] {
            var ids = o.compactMap(PanelID.init(rawValue:))
            for p in PanelID.allCases where !ids.contains(p) { ids.append(p) }   // 新しく増えたパネルは最後に
            order = ids
        }
        if let c = d["collapsed"] as? [String] { collapsed = Set(c.compactMap(PanelID.init(rawValue:))) }
        if let f = d["floating"] as? Data, let g = try? JSONDecoder().decode([FloatGroup].self, from: f) { floating = g.filter { !$0.tabs.isEmpty } }
        if let fr = d["frames"] as? [String: [Double]] {
            for (k, v) in fr where v.count == 4 { if let u = UUID(uuidString: k) { frames[u] = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) } }
        }
    }
    func save() {
        var d: [String: Any] = ["order": order.map(\.rawValue), "collapsed": collapsed.map(\.rawValue)]
        if let f = try? JSONEncoder().encode(floating) { d["floating"] = f }
        d["frames"] = Dictionary(uniqueKeysWithValues: frames.filter { k, _ in floating.contains { $0.id == k } }.map { ($0.key.uuidString, [$0.value.minX, $0.value.minY, $0.value.width, $0.value.height]) })
        UserDefaults.standard.set(d, forKey: DockState.key)
    }
    func group(of p: PanelID) -> FloatGroup? { floating.first { $0.tabs.contains(p) } }
    /// 浮いた窓からパネルを外す（窓が空になったら消す）
    func detach(_ p: PanelID) {
        var f = floating
        for i in f.indices.reversed() where f[i].tabs.contains(p) {
            f[i].tabs.removeAll { $0 == p }
            if f[i].tabs.isEmpty { f.remove(at: i) } else if f[i].selected == p { f[i].selected = f[i].tabs[0] }
        }
        if f != floating { floating = f }
    }
    /// パネルを新しい浮いた窓へ
    func floatPanel(_ p: PanelID, frame: CGRect? = nil) {
        detach(p)
        let g = FloatGroup(tabs: [p], selected: p)
        if let frame { frames[g.id] = frame }
        floating.append(g)
    }
    /// パネルをドックへ（target の前。nil なら最後）
    func dockPanel(_ p: PanelID, before target: PanelID?) { detach(p); move(p, before: target) }
    /// パネルを浮いた窓 gid のタブに加える
    func addTab(_ p: PanelID, to gid: UUID, before target: PanelID? = nil) {
        if let g = group(of: p), g.id == gid {                   // 同じ窓の中での並べかえ
            guard let i = floating.firstIndex(where: { $0.id == gid }) else { return }
            var t = floating[i].tabs; t.removeAll { $0 == p }
            if let target, let k = t.firstIndex(of: target) { t.insert(p, at: k) } else { t.append(p) }
            floating[i].tabs = t; floating[i].selected = p; return
        }
        detach(p)
        guard let i = floating.firstIndex(where: { $0.id == gid }) else { return }
        if let target, let k = floating[i].tabs.firstIndex(of: target) { floating[i].tabs.insert(p, at: k) } else { floating[i].tabs.append(p) }
        floating[i].selected = p
    }
    func select(_ p: PanelID, in gid: UUID) { if let i = floating.firstIndex(where: { $0.id == gid }) { floating[i].selected = p } }
    /// 浮いた窓のパネルを全部ドックへ戻す
    func dockGroup(_ gid: UUID) { floating.removeAll { $0.id == gid }; frames[gid] = nil }
    /// パネル id を target の前へ（target が nil なら最後へ）
    func move(_ id: PanelID, before target: PanelID?) {
        guard id != target, let from = order.firstIndex(of: id) else { return }
        var o = order; o.remove(at: from)
        if let target, let to = o.firstIndex(of: target) { o.insert(id, at: to) } else { o.append(id) }
        order = o
    }
    func toggle(_ id: PanelID) { if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) } }
    func reset() { floating = []; order = PanelID.allCases; collapsed = [] }
}

/// Photoshop 風のスライダー：名前の上を左右にドラッグ（スクラブ）・スライダー・数字（クリックで直接入力）
struct ScrubRow: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var fmt = "%.2f"
    var def: Double? = nil
    var step: Double? = nil                 // 整数の時など、丸める刻み
    @State private var start: Double? = nil
    @State private var editing = false
    @State private var text = ""
    @State private var hover = false
    @FocusState private var focused: Bool

    func clampRound(_ v: Double) -> Double {
        var x = min(range.upperBound, max(range.lowerBound, v))
        if let step { x = (x / step).rounded() * step }
        return x
    }
    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .frame(width: 104, alignment: .leading)
                .foregroundStyle(hover ? Color.accentColor : Color.primary)
                .contentShape(Rectangle())
                .onHover { h in hover = h; if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    if start == nil { start = value }
                    let m = NSEvent.modifierFlags, k = m.contains(.shift) ? 10.0 : m.contains(.option) ? 0.1 : 1.0
                    value = clampRound(start! + Double(g.translation.width) * (range.upperBound - range.lowerBound) / 300 * k)
                }.onEnded { _ in start = nil })
                .onTapGesture { if NSEvent.modifierFlags.contains(.option), let def { value = def } }
                .help("左右にドラッグで値を変える（⇧ 粗く・⌥ 細かく）。⌥クリックで初めの値に")
            Slider(value: Binding(get: { value }, set: { value = clampRound($0) }), in: range)
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder).frame(width: 52).focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    .onExitCommand { editing = false }
            } else {
                Text(String(format: fmt, value)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { text = String(format: "%g", value); editing = true; DispatchQueue.main.async { focused = true } }
                    .help("クリックして数字を入力")
            }
        }
    }
    func commit() {
        let s = text.filter { "0123456789.-".contains($0) }
        if let v = Double(s) { value = clampRound(v) }
        editing = false
    }
}

/// ドックの列：パネルを縦に積む
struct DockColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var dock: DockState
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(dock.docked, id: \.self) { id in PanelCard(model: model, dock: dock, id: id) }
                // 最後の所へ落とす場所
                DropTail(dock: dock)
                HStack {
                    Button("すべてたたむ") { dock.collapsed = Set(PanelID.allCases) }
                    Button("すべてひらく") { dock.collapsed = [] }
                    Button("並びを元に") { dock.reset() }
                }
                .controlSize(.small).buttonStyle(.borderless).foregroundStyle(.secondary)
                Text("見出しをドラッグで並べかえ・クリックでたたむ・⧉ で浮かせる・Tab で全部隠す。浮いた窓のタブへドラッグするとタブでまとまり、ここへドラッグすると戻る").font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .padding(8)
        }
        .controlSize(.small)
    }
}

struct DropTail: View {
    @ObservedObject var dock: DockState
    @State private var targeted = false
    var body: some View {
        Rectangle().fill(targeted ? Color.accentColor : Color.clear).frame(height: targeted ? 3 : 12)
            .dropDestination(for: String.self) { items, _ in
                if let s = items.first, let id = PanelID(rawValue: s) { withAnimation(.easeOut(duration: 0.15)) { dock.dockPanel(id, before: nil) } }
                return true
            } isTargeted: { targeted = $0 }
    }
}

/// パネル 1 枚：見出し（ドラッグで並べかえ・クリックでたたむ）と中身
struct PanelCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var dock: DockState
    let id: PanelID
    @State private var targeted = false
    var body: some View {
        let open = !dock.collapsed.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(targeted ? Color.accentColor : Color.clear).frame(height: 3).padding(.bottom, 2)   // ここに落とすと、このパネルの前へ
            HStack(spacing: 6) {
                Image(systemName: id.icon).frame(width: 16).foregroundStyle(.secondary)
                Text(id.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { dock.floatPanel(id) } label: { Image(systemName: "macwindow.on.rectangle").font(.system(size: 10)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("このパネルを浮かせる（浮いた窓のタブの所へドラッグすると、タブでまとまる）")
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { dock.toggle(id) } }
            .contextMenu {
                Button("このパネルを浮かせる") { dock.floatPanel(id) }
                Button(dock.collapsed.contains(id) ? "ひらく" : "たたむ") { dock.toggle(id) }
                Divider()
                Button("すべてたたむ") { dock.collapsed = Set(PanelID.allCases) }
                Button("すべてひらく") { dock.collapsed = [] }
                Button("並びを元に戻す") { dock.reset() }
            }
            .draggable(id.rawValue) {
                Label(id.title, systemImage: id.icon).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            if open {
                Divider().opacity(0.5)
                PanelContent(model: model, id: id).padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
        .dropDestination(for: String.self) { items, _ in
            if let s = items.first, let from = PanelID(rawValue: s) { withAnimation(.easeOut(duration: 0.15)) { dock.dockPanel(from, before: id) } }
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// パネルの中身（前のインスペクターの欄ごと）
struct PanelContent: View {
    @ObservedObject var model: AppModel
    let id: PanelID
    func row(_ name: String, _ kp: WritableKeyPath<Settings, Double>, _ lo: Double, _ hi: Double, _ fmt: String = "%.2f") -> some View {
        ScrubRow(name: name, value: model.b(kp), range: lo...hi, fmt: fmt, def: Settings()[keyPath: kp])
    }
    func irow(_ name: String, _ kp: WritableKeyPath<Settings, Int>, _ lo: Int, _ hi: Int) -> some View {
        let b = model.b(kp)
        return ScrubRow(name: name, value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) }),
                        range: Double(lo)...Double(hi), fmt: "%.0f", def: Double(Settings()[keyPath: kp]), step: 1)
    }
    func note(_ s: String) -> some View { Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }

    var body: some View {
        let r = model.r
        VStack(alignment: .leading, spacing: 7) {
            switch id {
            case .walk:
                Toggle("歩き続ける（K）", isOn: model.rb(\.walking))
                Toggle("縦横無尽（U）", isOn: model.rb(\.roaming))
                row("速さ", \.spd, 0.1, 2)
                row("曲がり", \.roamK, 0.2, 2)
                HStack {
                    Button("アナ極へ戻る") { r.resetNorth(); model.changed() }
                    Button("見回しを戻す") { r.cam.hy = 0; r.cam.hp = 0; model.changed() }
                }
            case .path:
                Picker("道", selection: Binding(get: { r.pathMode.rawValue }, set: { v in
                    if v == 0 { r.pathMode = .none } else { r.startPath(PathMode(rawValue: v)!) }; model.changed() })) {
                    Text("なし").tag(0); Text("螺旋").tag(1); Text("回る輪").tag(2)
                }.pickerStyle(.segmented)
                if r.pathMode != .ring {
                    row("巻き数", \.turns, 1, 12, "%.1f")
                    row("傾き", \.tilt, 0, 1)
                    row("歳差（度／周）", \.prec, 0, 45, "%.0f")
                }
                if r.pathMode != .spiral {
                    Picker("輪の軸", selection: model.b(\.ringAxis)) { Text("x").tag(0); Text("y").tag(1); Text("z").tag(2); Text("w").tag(3); Text("全部").tag(4) }.pickerStyle(.segmented)
                    row("1 周で回す角", \.ringStep, 2, 45, "%.0f°")
                }
                note("キーかスティックで歩くと、決まった道はやめる")
            case .marks:
                Picker("見せ方（P）", selection: model.b(\.mk)) { Text("玉").tag(0); Text("絵").tag(1); Text("色の点").tag(2); Text("なし").tag(3) }.pickerStyle(.segmented)
                if r.set.mk == 1 || r.set.mk == 2 { row("線の濃さ", \.picLine, 0, 1) }
                if r.set.mk == 1 { Toggle("遠回りの像を、絵の裏から見た形に", isOn: model.b(\.ghostBack)) }
                Toggle("8 つの極の目印", isOn: model.b(\.poles))
                Toggle("反対側の相棒を隠す", isOn: model.b(\.hidePair))
                Toggle("足あと（F）", isOn: model.b(\.foot))
                Toggle("置いた目印", isOn: model.b(\.marksOn))
                Toggle("自分の玉（2π 先に自分の背中）", isOn: model.b(\.selfBall))
                Toggle("向きの赤い点（O）", isOn: model.b(\.orient))
                HStack {
                    Button("ここに目印を置く") { r.addMark(); model.changed() }
                    Button("目印を消す") { r.journey.marks = []; r.journey.marks2 = []; model.changed() }.disabled(r.journey.marks.isEmpty)
                }
            case .shell:
                Toggle("球層（L）", isOn: model.b(\.shell))
                Picker("色", selection: model.b(\.shAxis)) { Text("レインボー").tag(false); Text("軸の色").tag(true) }.pickerStyle(.segmented)
                if r.set.shAxis {
                    HStack(spacing: 10) {
                        Text("囲む軸").font(.caption).foregroundStyle(.secondary)
                        Toggle("x", isOn: model.b(\.shAxX)); Toggle("y", isOn: model.b(\.shAxY)); Toggle("z", isOn: model.b(\.shAxZ)); Toggle("w", isOn: model.b(\.shAxW))
                    }.toggleStyle(.button).controlSize(.small)
                    note("選んだ軸の極を囲む殻（その軸の成分＝一定の球面）を、その軸の色で。＋の極のそばは明るく、−の極のそばは少し暗い。極の点も軸の色に（ウェブ版の軸色と同じ）")
                }
                Toggle("立体の殻（T）", isOn: model.b(\.shellSolid))
                if r.set.shellSolid { row("立体の網目の明るさ", \.solidWire, 0, 1.5) }
                Toggle("網目なし（B）", isOn: model.b(\.shellBare))
                Toggle("壮大（G）", isOn: model.b(\.grand))
                irow("層数", \.shellN, 3, 21)
                row("透明度", \.shellOp, 0.05, 0.75)
                row("裏側", \.shellBack, 0, 1)
                row("暗い色の持ち上げ", \.shellLum, 0, 0.75)
                row("殻の見える距離", \.shellRange, 0.3, 25.15)
            case .view:
                Picker("背景（N）", selection: model.b(\.space)) { Text("深海（もや）").tag(false); Text("宇宙（星）").tag(true) }.pickerStyle(.segmented)
                Toggle("映画のような光（HDR・あふれる光・色の締め）", isOn: model.b(\.cine))
                if r.set.cine {
                    row("あふれる光", \.bloom, 0, 2)
                    row("露出", \.expo, 0.3, 3)
                    row("フィルムの粒", \.grain, 0, 1)
                }
                if r.set.space {
                    row("星の明るさ", \.stars, 0, 3)
                    row("天の川", \.band, 0, 3)
                    Toggle("星雲（S³ に浮かぶ色のついたガス）", isOn: model.b(\.nebula))
                    if r.set.nebula { row("星雲の濃さ", \.nebK, 0, 3) }
                    note("星は S³ の決まった点。近い星ほど歩くと速く動き、ちょうど反対側（距離 π）の星は光がまた集まって明るい。どの星も、反対向きにもう 1 つ（遠回りの像）見える")
                }
                Toggle("軽い線：緯度経度の殻（J）", isOn: model.b(\.lite))
                Toggle("赤道の膜（Y）", isOn: model.b(\.eq))
                Toggle("経線・赤道の輪（管）", isOn: model.b(\.circ))
                Toggle("120 胞体の部屋の辺（管・重い）", isOn: model.b(\.room))
                Picker("レンズ", selection: Binding(get: { r.set.lens }, set: { v in
                    r.set.lens = v
                    if v == 1 && r.set.fov < 150 { r.set.fov = 180 }       // ウェブ版と同じ：魚眼にしたら 180°、ふつうに戻したら 110° まで
                    if v == 0 && r.set.fov > 150 { r.set.fov = 110 }
                    model.changed() })) { Text("ふつう").tag(0); Text("魚眼").tag(1); Text("360°").tag(2) }.pickerStyle(.segmented)
                if r.set.lens != 2 { row("視野角", \.fov, 30, r.set.lens == 1 ? 360 : 150, "%.0f°") }
                row("光の距離", \.maxD, 1, 6.4)
                row("もや", \.fog, 0, 0.6)
                row("透け", \.fade, 0, 1)
                row("線の遠近感", \.depth, 0, 1)
            case .lines:
                Picker("線の見え方（C）", selection: model.b(\.lineCrisp)) { Text("やわらか（標準）").tag(false); Text("くっきり").tag(true) }.pickerStyle(.segmented)
                note(r.set.lineCrisp ? "網目の線・玉のふちを画面で決まった太さに。すぐそばの殻の線もぼやけない" : "線は殻の上で決まった角度の太さ。近くの線ほど太くやわらかく、遠くの線ほど細く、遠近感がよく分かる")
                if r.set.lineCrisp { row("線の太さ（画素）", \.lineW, 0.5, 4, "%.1f") }
                row("にじみ", \.glow, 0, 1)
                Toggle("EDR の画面では線を明るく光らせる", isOn: model.b(\.edrOn))
                note(r.edrHead > 1.01 ? String(format: "この画面の明るさの余白：%.1f 倍", r.edrHead) : "この画面は EDR なし（にじみだけ）。HDR の画面や MacBook Pro の画面なら明るく光る")
            case .map:
                Picker("置き方", selection: Binding(get: { model.mapMode }, set: { model.setMap($0) })) {
                    Text("隠す").tag(MapMode.hidden); Text("並べる").tag(MapMode.docked); Text("浮かせる").tag(MapMode.floating)
                }.pickerStyle(.segmented)
                if model.mapMode == .docked {
                    Picker("並べる側", selection: model.b(\.mapLeft)) { Text("景色の左").tag(true); Text("景色の右").tag(false) }.pickerStyle(.segmented)
                }
                Toggle("2 枚目の地図", isOn: model.b(\.map2On))
                Toggle("S² の仲間（同じ操作を、ふつうの球面で）", isOn: model.b(\.s2On))
                Toggle("自分を真ん中に（体の向きのまま写す）", isOn: model.b(\.mapFollow))
                Group {
                    row("X-W", \.mapXW, -180, 180, "%.0f°")
                    row("Y-W", \.mapYW, -180, 180, "%.0f°")
                    row("Z-W", \.mapZW, -180, 180, "%.0f°")
                }.disabled(r.set.mapFollow)
                row("遠近 D", \.mapD, 1.2, 6, "%.1f")
                Toggle("軸（矢印）（X）", isOn: model.b(\.mapAxes))
                Toggle("歩いた跡", isOn: model.b(\.mapTrail))
                HStack {
                    Button("地図を元の向きに") { model.mapRenderer.home(); model.mapRenderer2.home(); model.s2Renderer.home() }
                    Button("跡を消す（L3）") { r.clearTrail(); model.changed() }
                }
            case .map2:
                Toggle("自分を真ん中に", isOn: model.b(\.map2Follow))
                Group {
                    row("X-W", \.map2XW, -180, 180, "%.0f°")
                    row("Y-W", \.map2YW, -180, 180, "%.0f°")
                    row("Z-W", \.map2ZW, -180, 180, "%.0f°")
                }.disabled(r.set.map2Follow)
            case .mac:
                Toggle("トラックパッドの触覚（赤道・極で「コツン」、殻ごとに「カチ」）", isOn: model.b(\.haptics))
                Toggle("ゲームコントローラーで歩く", isOn: model.b(\.gamepad))
                Toggle("ゲームのような操作（少し倒すとゆっくり・速めに回る・慣性つき）", isOn: model.b(\.padGame))
                Toggle("右スティックの左右を反転", isOn: model.b(\.padInvX))
                Toggle("右スティックの上下を反転", isOn: model.b(\.padInvY))
                if !r.game.names.isEmpty {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        note("押しているボタン：" + r.game.pressedNames() + (r.padLookOnly ? "（見回しだけ）" : ""))
                    }
                }
                note(r.game.names.isEmpty ? "コントローラー：つながっていない（Joy-Con などを Bluetooth でつなぐと使える）" : "コントローラー：" + r.game.names.joined(separator: "・"))
                note("右スティック 進む向き・ZL＋右スティック 見回しだけ（地図は回らず水色の円すい。ZL を押して離すだけで前を見る）・左スティック 進む向きへ歩く・Y 前を見る（進む向きは変えない）・ZL＋Y この向きへ進む（Enter）・右スティック押し込み 前を見る（もう一度で水平）・左スティック押し込み（L3） 軌跡を消す・L/R 上下・ZR 速く・A 目印・B 歩き続ける・X 縦横無尽・十字 殻の距離")
            case .screen:
                Toggle("60 fps 前後（144Hz の画面では 72）（V）", isOn: model.b(\.fps60))
                Toggle("足りない時だけ細かさを下げる", isOn: model.b(\.autoQ))
                row("描く細かさ", \.scale, 0.3, 1, "%.2f")
                Button("初めの見え方に戻す") { let s = r.set.scale; r.set = Settings(); r.set.scale = s; model.changed() }
            }
        }
    }
}

/// 浮いた窓の中身：上にタブ（ドラッグで並べかえ・ほかの窓やドックへ移す）、下に選んだパネル
struct FloatGroupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var dock: DockState
    let gid: UUID
    @State private var barTargeted = false
    var body: some View {
        if let g = dock.floating.first(where: { $0.id == gid }) {
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(g.tabs, id: \.self) { p in FloatTab(dock: dock, gid: gid, p: p, selected: p == g.selected) }
                    Spacer(minLength: 4)
                    Button { dock.dockGroup(gid) } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(.borderless).help("この窓のパネルをドックへ戻す")
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(barTargeted ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.15))
                .dropDestination(for: String.self) { items, _ in
                    if let s = items.first, let p = PanelID(rawValue: s) { dock.addTab(p, to: gid) }
                    return true
                } isTargeted: { barTargeted = $0 }
                Divider()
                ScrollView { PanelContent(model: model, id: g.selected).padding(10) }
            }
            .controlSize(.small)
        } else {
            Color.clear
        }
    }
}
struct FloatTab: View {
    @ObservedObject var dock: DockState
    let gid: UUID, p: PanelID, selected: Bool
    @State private var targeted = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: p.icon).font(.system(size: 10))
            Text(p.title).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(selected ? Color.white.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) { if targeted { Rectangle().fill(Color.accentColor).frame(width: 2) } }
        .contentShape(Rectangle())
        .onTapGesture { dock.select(p, in: gid) }
        .contextMenu {
            Button("ドックへ戻す") { dock.dockPanel(p, before: nil) }
            Button("別の窓に浮かせる") { dock.floatPanel(p) }
        }
        .draggable(p.rawValue) { Label(p.title, systemImage: p.icon).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)) }
        .dropDestination(for: String.self) { items, _ in
            if let s = items.first, let q = PanelID(rawValue: s) { dock.addTab(q, to: gid, before: p) }
            return true
        } isTargeted: { targeted = $0 }
    }
}
