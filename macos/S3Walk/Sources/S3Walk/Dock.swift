// パネルのドッキング（Photoshop のような画面）の 1 段階目：設定を 1 枚ずつのパネルにして、右のドックに積む。
//   見出しのドラッグで並べかえ、見出しのクリックでたたむ、Tab で全部隠す（AppModel.toggleAllPanels）。並びとたたみは保存。
//   スライダーは Photoshop 風のスクラブ式：名前の上を左右にドラッグで値を変える（⇧ で 10 倍・⌥ で 0.1 倍の刻み）、
//   数字をクリックして直接入力、名前を ⌥クリックで初めの値に。案の全体は DOCKING_PLAN.md
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// パネルの種類（今のところ右のドックに積む）
enum PanelID: String, CaseIterable, Codable {
    case walk, path, marks, shell, view, lines, map, map2, mac, screen, keys
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
        case .keys: return "ショートカットキー"
        }
    }
    /// この機械で出すパネル（iPad・iPhone はキーボードのショートカットなし）
    var shown: Bool {
        #if os(macOS)
        return true
        #else
        return self != .keys
        #endif
    }
    static var dockHint: String {
        #if os(macOS)
        return "見出しをドラッグで並べかえ・クリックでたたむ・⧉ で浮かせる・Tab で全部隠す。浮いた窓のタブへドラッグするとタブでまとまり、ここへドラッグすると戻る"
        #else
        return "見出しを長押しでドラッグして並べかえ・タップでたたむ。スライダーは名前を左右になぞっても動く。数字をタップで直接入力"
        #endif
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
        case .keys: return "keyboard"
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
/// キーボードで動かすスライダー：名前かつまみをクリックすると選ばれる（青い枠）。← → ↑ ↓ で動かす（⇧ 10 倍・⌥ 0.1 倍）、
///   数字を打つか Return で直接入力、Esc か景色をクリックで外れる
final class SliderFocus: ObservableObject {
    static let shared = SliderFocus()
    @Published var key: String? = nil
    var nudge: ((Double) -> Void)?
    var edit: ((String?) -> Void)?
    func clear() { key = nil; nudge = nil; edit = nil }
}

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
    @ObservedObject private var sel = SliderFocus.shared
    private var key: String { name + "|\(range.lowerBound)|\(range.upperBound)" }
    /// このスライダーを、キーボードで動かすものに選ぶ
    func select() {
        let span = range.upperBound - range.lowerBound, st = step ?? span / 100
        sel.key = key
        sel.nudge = { k in value = clampRound(value + k * st) }
        sel.edit = { s in text = s ?? String(format: "%g", value); editing = true; DispatchQueue.main.async { focused = true } }
    }

    func clampRound(_ v: Double) -> Double {
        var x = min(range.upperBound, max(range.lowerBound, v))
        if let step { x = (x / step).rounded() * step }
        return x
    }
    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .frame(width: 104, alignment: .leading)
                .foregroundStyle(hover ? Space.sky : Color.white.opacity(0.85))
                .contentShape(Rectangle())
                #if os(macOS)
                .onHover { h in hover = h; if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                #endif
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    if start == nil { start = value }
                    let k = ScrubRow.fineness()
                    value = clampRound(start! + Double(g.translation.width) * (range.upperBound - range.lowerBound) / 300 * k)
                }.onEnded { _ in start = nil })
                .onTapGesture { if ScrubRow.option(), let def { value = def } else { select() } }
                .help("左右にドラッグで値を変える（⇧ 粗く・⌥ 細かく）。クリックで選ぶと ← → で動かせ、数字を打つと直接入力。⌥クリックで初めの値に")
            Slider(value: Binding(get: { value }, set: { value = clampRound($0) }), in: range, onEditingChanged: { if $0 { select() } })
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder).frame(width: 52).focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    #if os(macOS)
                    .onExitCommand { editing = false }
                    #endif
            } else {
                Text(String(format: fmt, value)).monospacedDigit().foregroundStyle(Space.sky.opacity(0.9))
                    .frame(width: 52, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { select(); text = String(format: "%g", value); editing = true; DispatchQueue.main.async { focused = true } }
                    .help("クリックして数字を入力")
            }
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor.opacity(sel.key == key ? 0.9 : 0), lineWidth: 1.5))
    }
    /// ⇧ で 10 倍・⌥ で 0.1 倍の刻み（iPad・iPhone は 1 倍のまま）
    static func fineness() -> Double {
        #if os(macOS)
        let m = NSEvent.modifierFlags; return m.contains(.shift) ? 10.0 : m.contains(.option) ? 0.1 : 1.0
        #else
        return 1
        #endif
    }
    static func option() -> Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.option)
        #else
        return false
        #endif
    }
    func commit() {
        let s = text.filter { "0123456789.-".contains($0) }
        if let v = Double(s) { value = clampRound(v) }
        editing = false
    }
}

/// ドックの列：パネルを縦に積む
/// 設定の検索：⌘F か上の欄に打つと、項目の名前・説明から探して、押すとそのパネルへ飛んで光らせる
final class SettingSearch: ObservableObject {
    static let shared = SettingSearch()
    @Published var query = ""
    @Published var focusTick = 0                      // ⌘F で欄にカーソルを置く
    @Published var flash: PanelID? = nil              // 飛んだ先のパネルを少しの間光らせる
    struct Hit: Identifiable { let id = UUID(); let panel: PanelID; let kind: String; let text: String }
    /// 探す：パネルの名前・項目の名前・説明・ショートカットキーの操作。空白で区切ると、全部を含むもの
    func hits() -> [Hit] {
        func norm(_ s: String) -> String { (s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s).lowercased() }
        let words = norm(query).split(whereSeparator: { $0 == " " || $0 == "　" }).map(String.init)
        guard !words.isEmpty else { return [] }
        func ok(_ s: String) -> Bool { let l = norm(s); return words.allSatisfy { l.contains($0) } }
        var out: [Hit] = []
        for p in PanelID.allCases where ok(p.title) { out.append(Hit(panel: p, kind: "panel", text: p.title)) }
        for (p, k, t) in searchIndex where ok(t) || ok(p.title + " " + t) { out.append(Hit(panel: p, kind: k, text: t)) }
        for a in KeyAction.allCases where ok(a.title) || ok("キー " + a.title) { out.append(Hit(panel: .keys, kind: "set", text: a.title + "（キー " + (Keymap.shared.label(a).isEmpty ? "なし" : Keymap.shared.label(a)) + "）")) }
        // 項目を先に、説明は後に
        out = out.filter { $0.panel.shown }
        return out.filter { $0.kind != "note" } + out.filter { $0.kind == "note" }
    }
}

struct SearchBar: View {
    @ObservedObject var s = SettingSearch.shared
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Space.sky)
            TextField("設定を探す（⌘F）", text: $s.query).textFieldStyle(.plain).focused($focused)
                #if os(macOS)
                .onExitCommand { s.query = ""; focused = false }
                #endif
            if !s.query.isEmpty { Button { s.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .spaceCard(lit: focused)
        .onChange(of: s.focusTick) { _, _ in focused = true }
    }
}

struct DockColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var dock: DockState
    @ObservedObject var search = SettingSearch.shared
    /// 見つけたパネルへ：浮いた窓にあればそのタブを選ぶ、ドックにあればひらいてそこまで動かす。少しの間光らせる
    func reveal(_ p: PanelID, _ proxy: ScrollViewProxy) {
        if let g = dock.group(of: p) { dock.select(p, in: g.id) }
        else {
            dock.collapsed.remove(p)
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(p, anchor: .top) } }
        }
        search.flash = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if search.flash == p { search.flash = nil } }
    }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 8) {
                SearchBar()
                if !search.query.isEmpty {
                    let hits = search.hits()
                    VStack(alignment: .leading, spacing: 2) {
                        if hits.isEmpty { Text("見つからない").font(.caption).foregroundStyle(Space.slate).padding(6) }
                        ForEach(hits.prefix(40)) { h in
                            Button { reveal(h.panel, proxy) } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: h.panel.icon).frame(width: 14).foregroundStyle(Space.sky)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(h.kind == "note" ? "説明：" + String(h.text.prefix(60)) + (h.text.count > 60 ? "…" : "") : h.text)
                                            .foregroundStyle(h.kind == "note" ? Space.slate : .white).font(h.kind == "note" ? .caption : .callout)
                                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                        Text(h.panel.title + (dock.group(of: h.panel) != nil ? "（浮いた窓）" : "")).font(.caption2).foregroundStyle(Space.lilac)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if hits.count > 40 { Text("ほか \(hits.count - 40) 件（言葉を足して絞る）").font(.caption2).foregroundStyle(Space.slate).padding(4) }
                    }
                    .padding(4).spaceCard()
                }
                ForEach(dock.docked.filter(\.shown), id: \.self) { id in PanelCard(model: model, dock: dock, id: id).id(id) }
                // 最後の所へ落とす場所
                DropTail(dock: dock)
                HStack {
                    Button("すべてたたむ") { dock.collapsed = Set(PanelID.allCases) }
                    Button("すべてひらく") { dock.collapsed = [] }
                    Button("並びを元に") { dock.reset() }
                }
                .controlSize(.small).buttonStyle(.borderless).foregroundStyle(.secondary)
                Text(PanelID.dockHint).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .padding(8)
        }
        }
        .scrollContentBackground(.hidden)
        .background(SpaceBackground())
        .spaceControls()
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
    @ObservedObject private var search = SettingSearch.shared
    var body: some View {
        let open = !dock.collapsed.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(targeted ? Color.accentColor : Color.clear).frame(height: 3).padding(.bottom, 2)   // ここに落とすと、このパネルの前へ
            HStack(spacing: 6) {
                Image(systemName: id.icon).frame(width: 16).foregroundStyle(Space.sky)
                Text(id.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Space.lilac)
                Spacer()
                #if os(macOS)
                Button { dock.floatPanel(id) } label: { Image(systemName: "macwindow.on.rectangle").font(.system(size: 10)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("このパネルを浮かせる（浮いた窓のタブの所へドラッグすると、タブでまとまる）")
                #endif
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary).font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { dock.toggle(id) } }
            .contextMenu {
                #if os(macOS)
                Button("このパネルを浮かせる") { dock.floatPanel(id) }
                #endif
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
        .spaceCard(lit: targeted || search.flash == id)
        .shadow(color: search.flash == id ? Space.violet.opacity(0.8) : .clear, radius: 10)
        .animation(.easeOut(duration: 0.3), value: search.flash)
        .dropDestination(for: String.self) { items, _ in
            if let s = items.first, let from = PanelID(rawValue: s) { withAnimation(.easeOut(duration: 0.15)) { dock.dockPanel(from, before: id) } }
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// パネルの中身（前のインスペクターの欄ごと）
struct PanelContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var km = Keymap.shared
    let id: PanelID
    func row(_ name: String, _ kp: WritableKeyPath<Settings, Double>, _ lo: Double, _ hi: Double, _ fmt: String = "%.2f", step: Double? = nil) -> some View {
        ScrubRow(name: name, value: model.b(kp), range: lo...hi, fmt: fmt, def: Settings()[keyPath: kp], step: step)
    }
    func irow(_ name: String, _ kp: WritableKeyPath<Settings, Int>, _ lo: Int, _ hi: Int) -> some View {
        let b = model.b(kp)
        return ScrubRow(name: name, value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) }),
                        range: Double(lo)...Double(hi), fmt: "%.0f", def: Double(Settings()[keyPath: kp]), step: 1)
    }
    func note(_ s: String) -> some View { Text(s).font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true) }

    var body: some View {
        let r = model.r
        VStack(alignment: .leading, spacing: 7) {
            switch id {
            case .walk:
                Toggle("歩き続ける" + km.hint(.walk), isOn: model.rb(\.walking))
                Toggle("縦横無尽" + km.hint(.roam), isOn: model.rb(\.roaming))
                Toggle("上下も 360° 回す（宙返り）", isOn: model.b(\.free360)).help("オフにすると、ウェブ版と同じく上下は ±89° で止まる")
                row("速さ", \.spd, 0.1, 2)
                row("曲がり", \.roamK, 0.2, 2)
                HStack {
                    Button("アナ極へ戻る") { r.resetNorth(); model.changed() }
                    Button("見回しを戻す") { r.cam.hy = 0; r.cam.hp = 0; model.changed() }
                }
            case .path:
                Picker("道", selection: Binding(get: { r.pathMode.rawValue }, set: { v in
                    if v == 0 { r.pathMode = .none } else { r.startPath(PathMode(rawValue: v)!) }; model.changed() })) {
                    Text("なし").tag(0); Text("螺旋").tag(1); Text("回る輪").tag(2); Text("半周 180°").tag(3); Text("極めぐり").tag(4)
                }.pickerStyle(.segmented)
                if r.pathMode == .none || r.pathMode == .half || r.pathMode == .tour {
                    Picker("曲がり方", selection: model.b(\.turnSharp)) { Text("スムーズ").tag(false); Text("直角").tag(true) }.pickerStyle(.segmented)
                    note("半周 180°：アナ極→カタ極→アナ極と経線を進み、両方の極でターン（すきまの大きい向きへ。地図の軌跡がだんだん球を埋める）。極めぐり：となりの極だけをたどって 8 つの極を回る（アナ→東→北→天→カタ→西→南→地）。スムーズは双曲線で極を少しよけ、直角は極でその場で向きを変える（次の曲がり角から）")
                }
                if r.pathMode == .none || r.pathMode == .spiral {
                    row("巻き数", \.turns, 1, 12, "%.1f")
                    row("傾き", \.tilt, 0, 1)
                    row("歳差（度／周）", \.prec, 0, 45, "%.0f")
                }
                if r.pathMode == .none || r.pathMode == .ring {
                    Picker("輪の軸", selection: model.b(\.ringAxis)) { Text("x").tag(0); Text("y").tag(1); Text("z").tag(2); Text("w").tag(3); Text("全部").tag(4) }.pickerStyle(.segmented)
                    row("1 周で回す角", \.ringStep, 2, 45, "%.0f°")
                }
                note("キーかスティックで歩くと、決まった道はやめる。コントローラーの十字の上・下を押し続けると、道の速さがだんだん速く・遅く（1 秒で 2 倍・半分、最高は自走の最高速まで）")
            case .marks:
                Picker("見せ方" + km.hint(.markStyle), selection: model.b(\.mk)) { Text("玉").tag(0); Text("絵").tag(1); Text("色の点").tag(2); Text("なし").tag(3); Text("模型").tag(4) }.pickerStyle(.segmented)
                if r.set.mk == 4 {
                    Picker("模型", selection: model.b(\.modelKind)) {
                        Text("いろいろ（目印ごとに順に）").tag(3); Divider()
                        Text("怪獣").tag(0); Text("タツノオトシゴの竜").tag(1); Text("うんこ").tag(2)
                        Text("いぬ").tag(4); Text("ねこ").tag(5); Text("たぬき").tag(6); Text("きつね").tag(7); Text("たこ").tag(8); Text("いか").tag(9)
                    }.pickerStyle(.menu)
                    row("模型の大きさ", \.modelSize, 0.4, 3)
                    HStack(spacing: 10) {
                        Text("模型にする").font(.caption).foregroundStyle(.secondary)
                        Toggle("極", isOn: model.b(\.modelPoles)); Toggle("置いた目印", isOn: model.b(\.modelMarks)); Toggle("自分", isOn: model.b(\.modelSelf))
                    }.toggleStyle(.button).controlSize(.small)
                    Toggle("ついてくる仲間（自分の後ろを追いかけてくる）", isOn: model.b(\.follower))
                    if r.set.follower { row("仲間との距離", \.followD, 0.3, 2.5).padding(.leading, 14) }
                    note("極を惑星にしている時は、模型が惑星の上に立つ。模型を消すには、見せ方を「玉」などに（P キー）か、ここで外す")
                    note("極・置いた目印・自分の玉を 3D の模型に（怪獣・竜・うんこ・いぬ・ねこ・たぬき・きつね・たこ・いか）。向きは目印ごとに決まっているので、まわりを歩くと横や後ろも見える。遠回りの像（反対側を回ってきた光）では、模型の向こう側の面が見える。体の色は目印の色に少し染まる")
                }
                if r.set.mk == 1 || r.set.mk == 2 { row("線の濃さ", \.picLine, 0, 1) }
                if r.set.mk == 1 { Toggle("遠回りの像を、絵の裏から見た形に", isOn: model.b(\.ghostBack)) }
                Toggle("8 つの極の目印", isOn: model.b(\.poles))
                if r.set.poles { Toggle("極を惑星に（透けて光る大きな玉。極の色・軸色の時は軸の色）", isOn: model.b(\.polePlanet)).padding(.leading, 14) }
                if r.set.poles && r.set.polePlanet { row("惑星の大きさ", \.planetSize, 0.03, 0.4, "%.3f").padding(.leading, 14) }
                Toggle("反対側の相棒を隠す", isOn: model.b(\.hidePair))
                Toggle("足あと" + km.hint(.foot), isOn: model.b(\.foot))
                Toggle("置いた目印", isOn: model.b(\.marksOn))
                Toggle("自分の玉（2π 先に自分の背中）", isOn: model.b(\.selfBall))
                Toggle("向きの赤い点" + km.hint(.orient), isOn: model.b(\.orient))
                HStack {
                    Button("ここに目印を置く") { r.addMark(); model.changed() }
                    Button("真ん中の星に置く") { r.markAtStar(); model.changed() }.help("画面の真ん中にいちばん近く見える明るい星に目印（模型のモードなら模型）を置く。星と同じ点なので、星といっしょに動き、反対側に近づくといっしょに広がって見える")
                    Button("目印を消す") { r.journey.marks = []; r.journey.marks2 = []; model.changed() }.disabled(r.journey.marks.isEmpty)
                }
                Text("体験（遠回りの光の像）").font(.caption.bold()).foregroundStyle(Space.lilac).padding(.top, 4)
                HStack {
                    Button("ついてくる仲間") { r.experience("self"); model.changed() }.help("模型が自分の後ろを追いかけてくる。振り返ると顔、前を見ると、反対側を回ってきた光で仲間の後ろ姿が上下・左右逆に見える。見やすいよう、もやを薄く・球層と極を隠す")
                    Button("上下反転の像") { r.experience("flip"); model.changed() }.help("ここに目印を置いて 1.2 進む。前に、反対側から回ってきた目印の像（上下・左右が逆、向こう側の面）が見える")
                    if r.expSaved != nil { Button("元の見え方に戻す") { r.endExperience(); model.changed() } }
                }
                HStack(spacing: 6) {
                    Text("背中が迫ってくる").font(.caption).foregroundStyle(.secondary)
                    ForEach([(0, "怪獣"), (1, "竜"), (7, "たこ"), (8, "いか")], id: \.0) { k, n in Button(n) { r.backDemo(k, n); model.changed() } }
                }.controlSize(.small)
                note("ここに模型を同じ向きで置いて、前へ歩き続ける。前を見ると、反対側を回ってきた光で背中が上下・左右逆に見える。はじめは小さくなり、π/2 を過ぎると大きく迫ってきて、π で空いっぱいに。振り返ると顔が遠ざかる。止めるのは B、元に戻すのは「元の見え方に戻す」")
            case .shell:
                Toggle("球層" + km.hint(.shell), isOn: model.b(\.shell))
                Picker("色", selection: model.b(\.shAxis)) { Text("レインボー").tag(false); Text("軸の色").tag(true) }.pickerStyle(.segmented)
                if !r.set.shAxis { Toggle("4 方向レインボー（x・y・z・w の 4 方向に殻を重ねる・重い）", isOn: model.b(\.rainbow4)) }
                if !r.set.shAxis && r.set.rainbow4 { irow("重ねる殻の数", \.shCap, 8, 60) }
                if r.set.shAxis {
                    HStack(spacing: 10) {
                        Text("囲む軸").font(.caption).foregroundStyle(.secondary)
                        Toggle("x", isOn: model.b(\.shAxX)); Toggle("y", isOn: model.b(\.shAxY)); Toggle("z", isOn: model.b(\.shAxZ)); Toggle("w", isOn: model.b(\.shAxW))
                    }.toggleStyle(.button).controlSize(.small)
                    irow("重ねる殻の数", \.shCap, 8, 60)
                    note("軸色は組が多いぶん重いので、手前からこの枚数で打ち切る（多いほど奥まで見えるが重い。宇宙の時は殻がうすいので効きやすい）")
                    note("選んだ軸の極を囲む殻（その軸の成分＝一定の球面）を、その軸の色で。＋の極のそばは明るく、−の極のそばは少し暗い。極の点も軸の色に（ウェブ版の軸色と同じ）")
                }
                Toggle("立体の殻" + km.hint(.solid), isOn: model.b(\.shellSolid))
                if r.set.shellSolid { row("立体の網目の明るさ", \.solidWire, 0, 1.5) }
                row("網目の色の鮮やかさ", \.lineViv, 0, 1.5)
                Toggle("網目なし" + km.hint(.bare), isOn: model.b(\.shellBare))
                if !r.set.shellBare {
                    row("網目の傾き", \.gridTilt, 0, 180, "%.0f°", step: 1)
                    row("網目の傾きの向き", \.gridAz, -180, 180, "%.0f°", step: 1)
                    HStack {
                        Toggle("網目を自転", isOn: model.b(\.gridSpin))
                        Button("網目の向きを戻す") { r.set.gridTilt = 0; r.set.gridAz = 0; r.gridSpinAng = 0; model.changed() }
                    }
                    if r.set.gridSpin { row("網目の自転の速さ（回／分）", \.gridSpinRate, -30, 30, "%.1f") }
                    note("網目（緯線・経線）の極を z から倒す・回す（殻そのものは同じ w ＝ 一定の球面。景色と地図の両方）。経線が集まる所（ふだんは天極・地極のそば）を動かせる")
                }
                Toggle("壮大" + km.hint(.grand), isOn: model.b(\.grand))
                irow("層数", \.shellN, 3, 21)
                row("透明度", \.shellOp, 0.05, 0.75)
                row("裏側", \.shellBack, 0, 1)
                row("暗い色の持ち上げ", \.shellLum, 0, 0.75)
                row("殻の見える距離", \.shellRange, 0.3, 25.15)
                row("目印の線", \.wireFloor, 0, 1)
                note("宇宙を大きくすると出てくる、殻の色の細い線（CG ソフトの補助線のよう）。もやの向こうの殻も形がわかる。×1 では出ず、×10 で全部。0 で出さない")
            case .view:
                Picker("背景" + km.hint(.space), selection: model.b(\.space)) { Text("深海（もや）").tag(false); Text("宇宙（星）").tag(true) }.pickerStyle(.segmented)
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
                Toggle("軽い線：緯度経度の殻" + km.hint(.lite), isOn: model.b(\.lite))
                Toggle("赤道の膜" + km.hint(.eq), isOn: model.b(\.eq))
                Toggle("経線・赤道の輪（管）", isOn: model.b(\.circ))
                Toggle("120 胞体の部屋の辺（管・重い）", isOn: model.b(\.room))
                Picker("レンズ", selection: Binding(get: { r.set.lens }, set: { v in
                    r.set.lens = v
                    if v == 1 && r.set.fov < 150 { r.set.fov = 180 }       // ウェブ版と同じ：魚眼にしたら 180°、ふつうに戻したら 110° まで
                    if v == 0 && r.set.fov > 150 { r.set.fov = 110 }
                    model.changed() })) { Text("ふつう").tag(0); Text("魚眼").tag(1); Text("360°").tag(2) }.pickerStyle(.segmented)
                if r.set.lens != 2 { row("視野角", \.fov, 30, r.set.lens == 1 ? 360 : 150, "%.0f°") }
                row("光の距離", \.maxD, 1, 6.4)
                row("宇宙の大きさ（log₁₀ R）", \.uniL, 0, 3)
                if r.set.uniL > 0.01 { note(String(format: "半径 ×%@・1 周 2πR ≈ %.0f。場所は角度のまま、同じ速さで進む角度は 1/R、目印は 1/R に小さく見え、もやは決まった距離でかかる。殻の網目の太さは変わらない（ウェブ版と同じ）", r.set.uniR < 10 ? String(format: "%.1f", r.set.uniR) : String(format: "%.0f", r.set.uniR), 2 * Double.pi * r.set.uniR)) }
                row("もや", \.fog, 0, 0.6)
                if !r.set.space { row("もやの明るさ", \.hazeK, 0, 1) }
                row("透け", \.fade, 0, 1)
                row("線の遠近感", \.depth, 0, 1)
            case .lines:
                Picker("線の見え方" + km.hint(.crisp), selection: model.b(\.lineCrisp)) { Text("やわらか（標準）").tag(false); Text("くっきり").tag(true) }.pickerStyle(.segmented)
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
                if r.set.mapFollow { Toggle("自分の矢印は立体の三角錐（オフで平たい三角形）", isOn: model.b(\.cursor3D)).padding(.leading, 14) }
                Group {
                    row("X-W", \.mapXW, -180, 180, "%.0f°", step: 1)
                    row("Y-W", \.mapYW, -180, 180, "%.0f°", step: 1)
                    row("Z-W", \.mapZW, -180, 180, "%.0f°", step: 1)
                }.disabled(r.set.mapFollow)
                row("遠近 D", \.mapD, 1.2, 6, "%.1f")
                row("殻の線の明るさ", \.mapBright, 0.2, 2)
                note("深海の時は「もやの明るさ」に合わせて、宇宙の時はレインボーの殻を、景色の暗さに合わせて暗くしてある。その上にかける明るさ")
                row("空間の膨張", \.mapExpand, 0, 0.3)
                note("宇宙の大きさを 10 倍にするごとに、地図をこの割合で広げる（どの殻の間も同じ割合で離れる。×1000・0.1 で 1.3 倍）。目印の玉と線の太さはそのまま")
                Toggle("地図を動かす（Shift・右ドラッグ）", isOn: model.b(\.mapPan)).help("オフの時は、ドラッグ・右ドラッグ・2 本指はどれも地図を回す")
                Toggle("軸（矢印）" + km.hint(.mapAxes), isOn: model.b(\.mapAxes))
                Toggle("歩いた跡", isOn: model.b(\.mapTrail))
                if r.set.mapTrail { Toggle("跡を光の線に（ほうき星の尾・流れる光）", isOn: model.b(\.trailLight)).padding(.leading, 14) }
                if r.set.mapTrail { row("残す軌跡（×π）", \.trailKeep, 0, 20, "%.2f").padding(.leading, 14); note("歩いた跡を、新しい方から x·π の長さだけ残し、古い所から消えていく（0 で全部残す。小数も可）") }
                HStack {
                    Button("地図を元の向きに") { model.mapRenderer.home(); model.mapRenderer2.home(); model.s2Renderer.home() }
                    Button("跡を消す（L3）") { r.clearTrail(); model.changed() }
                }
            case .map2:
                Toggle("自分を真ん中に", isOn: model.b(\.map2Follow))
                Group {
                    row("X-W", \.map2XW, -180, 180, "%.0f°", step: 1)
                    row("Y-W", \.map2YW, -180, 180, "%.0f°", step: 1)
                    row("Z-W", \.map2ZW, -180, 180, "%.0f°", step: 1)
                }.disabled(r.set.map2Follow)
            case .mac:
                Toggle("トラックパッドの触覚（赤道・極で「コツン」、殻ごとに「カチ」）", isOn: model.b(\.haptics))
                Toggle("画面のゲームパッド（景色の真ん中に、コントローラーと同じボタン）", isOn: $model.showPad)
                Toggle("ゲームコントローラーで歩く", isOn: model.b(\.gamepad))
                Toggle("ゲームのような操作（少し倒すとゆっくり・速めに回る・慣性つき）", isOn: model.b(\.padGame))
                Toggle("右スティックの左右を反転", isOn: model.b(\.padInvX))
                Toggle("右スティックの上下を反転", isOn: model.b(\.padInvY))
                row("自走のアクセル", \.autoAccelK, 0.2, 2)
                row("自走の最高速（倍）", \.autoMax, 1, 50, "%.1f")
                Picker("ターボ（Z・A・十字の右）", selection: model.b(\.turboHold)) { Text("押すたびに切りかえ").tag(false); Text("押している間だけ").tag(true) }.pickerStyle(.segmented)
                row("自走の最低速（倍）", \.autoMin, 0, 10, "%.1f")
                note("ブレーキで落とすのは最低速まで。0 なら止まって、まだ手前へ倒していると巻き戻し（最低速が 0 より大きい時は巻き戻さない）")
                Toggle("自走で手前へ倒し続けると巻き戻し", isOn: model.b(\.autoRewind))
                note("歩き続ける（コントローラーの B）の時：十字の上・下を押し続けるとだんだん速く・遅く（1 秒で 2 倍・半分、離すとその速さのまま）。左スティックの前もアクセル（ブレーキの 0.8 倍くらいの強さ、倒し始めはゆっくり）、左右は横歩き、手前へ倒すとブレーキ、止まってもまだ倒していると通ってきた軌跡を逆にたどる（倒し続けるほど速く）")
                if !r.game.names.isEmpty {
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        note("押しているボタン：" + r.game.pressedNames() + (r.padLookOnly ? "（見回しだけ）" : ""))
                    }
                }
                note(r.game.names.isEmpty ? "コントローラー：つながっていない（Joy-Con などを Bluetooth でつなぐと使える）" : "コントローラー：" + r.game.names.joined(separator: "・"))
                note("右スティック 進む向き・ZL＋右スティック 見回しだけ（地図は回らず水色の円すい。ZL を押して離すだけで前を見る）・左スティック 進む向きへ歩く・Y 前を見る（進む向きは変えない）・ZL＋Y この向きへ進む（Enter）・右スティック押し込み 前を見る（もう一度で水平）・左スティック押し込み（L3） 軌跡を消す・L/R 上下・ZR 速く・A ターボ・B 歩き続ける・X 縦横無尽・十字の上下 殻の見える距離（歩き続ける・決まった道の間は、押し続けて速く・遅く）・十字の右 ターボ（いきなり最高速、もう一度で戻る）・＋ 設定・− 地図を出す・隠す")
            case .screen:
                Toggle("60 fps 前後（144Hz の画面では 72）" + km.hint(.fps), isOn: model.b(\.fps60))
                Toggle("足りない時だけ細かさを下げる", isOn: model.b(\.autoQ))
                Toggle("動いていない時は描き直さない（止まったら 1 回だけ細かく描く）", isOn: model.b(\.idleReuse))
                note("映画のような光の時は、殻の景色だけ「描く細かさ」で描き、星と仕上げは画面の細かさで描く")
                row("描く細かさ", \.scale, 0.3, 1, "%.2f")
                Button("初めの見え方に戻す") { let s = r.set.scale; r.set = Settings(); r.set.scale = s; model.changed() }
            case .keys:
                KeymapPanel()
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
                .background(barTargeted ? Space.violet.opacity(0.3) : Space.panel.opacity(0.9))
                .dropDestination(for: String.self) { items, _ in
                    if let s = items.first, let p = PanelID(rawValue: s) { dock.addTab(p, to: gid) }
                    return true
                } isTargeted: { barTargeted = $0 }
                Divider()
                ScrollView { PanelContent(model: model, id: g.selected).padding(10).spaceCard().padding(8) }.scrollContentBackground(.hidden)
            }
            .background(SpaceBackground())
            .spaceControls()
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
        .foregroundStyle(selected ? Space.lilac : Color.white.opacity(0.7))
        .background(selected ? Space.violet.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
