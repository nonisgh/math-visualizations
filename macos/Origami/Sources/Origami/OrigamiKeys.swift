// ショートカット（ウェブ版 hypercube.html のキーから。ウェブ版のキーはまだ暫定なので、アプリの中で好きに変えられる）
//   キーの書き方はウェブ版と同じ：「F」「Shift+F」「Alt+W」「Space」「Enter」「1」。同じキーを別の機能に付けると、前の機能からは外れる。
//   今はこのアプリに保存（UserDefaults）。あとで Firebase（apps/origami/users/{uid}/settings/shortcuts）へ移せるように、
//   中身は「機能の名前 → キー」の辞書だけ。まだ移していない機能（垂直軸・5 次元など）は、移した時に足す
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ShortcutAction: Identifiable {
    let id: String, label: String, def: String
    let run: (OrigamiState) -> Void
}

final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    static let key = "origami.shortcuts"
    @Published var keys: [String: String] = [:]          // 機能の名前 → キー（既定と違うものだけでなく、全部）
    @Published var capturing: String? = nil              // キーを登録中の機能（次に押したキーを付ける）
    @Published var show = false                          // 設定の画面
    init() {
        var k = Dictionary(uniqueKeysWithValues: Self.actions.map { ($0.id, $0.def) })
        if let d = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] { for (a, v) in d where k[a] != nil { k[a] = v } }
        keys = k
    }
    func save() { guard !SaveGuard.off else { return }; UserDefaults.standard.set(keys, forKey: Self.key) }
    /// 保存から読み直す（同期でほかの機械の分をもらった時）
    func reload() {
        var k = Dictionary(uniqueKeysWithValues: Self.actions.map { ($0.id, $0.def) })
        if let d = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] { for (a, v) in d where k[a] != nil { k[a] = v } }
        if k != keys { keys = k }
    }
    /// 機能 a にキー v を付ける（ほかの機能に同じキーがあれば外す）
    func assign(_ a: String, _ v: String) {
        for (other, ov) in keys where other != a && ov == v { keys[other] = "" }
        keys[a] = v; save()
    }
    func resetAll() { keys = Dictionary(uniqueKeysWithValues: Self.actions.map { ($0.id, $0.def) }); save() }
    func action(for v: String) -> ShortcutAction? {
        guard !v.isEmpty, let id = keys.first(where: { $0.value == v })?.key else { return nil }
        return Self.actions.first { $0.id == id }
    }

    /// 90° 回す（ウェブ版の「90°回す X-W」など）：今の角度から 90° 先へなめらかに
    static func step90(_ st: OrigamiState, _ k: Int) {
        // 押すたびに 90° をためて、ばねのように回し切る（回っている途中に押しても止まらず、もう 90° 足される）
        st.stepPlane(k, 90)
    }
    static let actions: [ShortcutAction] = [
        ShortcutAction(id: "both", label: "表示トグル（両方 → 右上ミニ → 超立方体だけ → 立方体だけ）", def: "1") { $0.displayMode = ($0.displayMode + 1) % 4 },
        ShortcutAction(id: "panel", label: "操作パネル 表示／非表示", def: "Space") { $0.panelOpen.toggle() },
        ShortcutAction(id: "tab_fold", label: "タブ：折りたたみ", def: "Shift+1") { $0.panelOpen = true; $0.panelTab = 0 },
        ShortcutAction(id: "tab_rot", label: "タブ：回転", def: "Shift+2") { $0.panelOpen = true; $0.panelTab = 1 },
        ShortcutAction(id: "tab_view", label: "タブ：見え方", def: "Shift+3") { $0.panelOpen = true; $0.panelTab = 2 },
        ShortcutAction(id: "tab_pts", label: "タブ：点", def: "Shift+4") { $0.panelOpen = true; $0.panelTab = 3 },
        ShortcutAction(id: "tab_int", label: "タブ：積分", def: "Shift+5") { $0.panelOpen = true; $0.panelTab = 4 },
        ShortcutAction(id: "tab_next", label: "タブ：次へ（順に切りかえ）", def: "N") { $0.panelOpen = true; $0.panelTab = ($0.panelTab + 1) % OrigamiPanel.tabs.count },
        ShortcutAction(id: "allSpins", label: "W(X,Y,Z) 入／切（X-W・Y-W・Z-W を回し続ける）", def: "Enter") { $0.toggleWAll() },
        ShortcutAction(id: "fold", label: "組み上げる", def: "F") { $0.playFold() },
        ShortcutAction(id: "unfold", label: "展開する", def: "U") { $0.playUnfold() },
        ShortcutAction(id: "foldToggle", label: "組み立て ⇔ 展開 トグル", def: "C") { $0.toggleFold() },
        ShortcutAction(id: "axis", label: "座標軸 表示／非表示", def: "A") { $0.showAxes.toggle() },
        ShortcutAction(id: "origin", label: "リセット（回転を止めて 6 面とも 0）", def: "O") { $0.resetAll() },
        ShortcutAction(id: "snap", label: "補正（z 軸を画面に垂直へ。回転は止めない）", def: "S") { $0.snap() },
        ShortcutAction(id: "straight", label: "まっすぐ（画面の中の 2 本の軸を、いちばん近い縦・横に）", def: "Shift+S") { $0.straighten() },
        ShortcutAction(id: "reset", label: "初期化（開いた時の姿へ）", def: "R") { $0.resetAll(); $0.progress = 1; $0.playing = false; $0.loop = false; $0.explodeRaw = 0; $0.xpAnim = nil },
        ShortcutAction(id: "play", label: "回転アニメ 再生", def: "P") { $0.playRotAnim() },
        ShortcutAction(id: "preset_cell", label: "どこから見る：胞から", def: "H") { $0.goView(0, animated: true) },
        ShortcutAction(id: "preset_face", label: "どこから見る：面から", def: "Shift+F") { $0.goView(1, animated: true) },
        ShortcutAction(id: "preset_edge", label: "どこから見る：辺から", def: "E") { $0.goView(2, animated: true) },
        ShortcutAction(id: "preset_vertex", label: "どこから見る：頂点から", def: "T") { $0.goView(3, animated: true) },
        ShortcutAction(id: "persp", label: "投影 切りかえ（平行投影 ⇔ 遠近投影）", def: "J") { $0.perspMode.toggle() },
        ShortcutAction(id: "loop", label: "往復再生（組み立て⇔展開）入／切", def: "L") { $0.toggleLoop() },
        ShortcutAction(id: "pingPong", label: "角度の往復 スタート／ストップ", def: "G") { $0.ppToggle() },
        ShortcutAction(id: "ppOnce", label: "角度の片道（A→B／B→A を交互に 1 回）", def: "Shift+G") { $0.ppOnce() },
        ShortcutAction(id: "zoom", label: "自動ズーム 入／切", def: "3") { $0.autoZoom.toggle() },
        ShortcutAction(id: "mesh", label: "メッシュ表示", def: "M") { $0.wireOnly = false },
        ShortcutAction(id: "wire", label: "ワイヤー表示", def: "Shift+M") { $0.wireOnly = true },
        ShortcutAction(id: "step_xw", label: "90° 回す X-W", def: "X") { step90($0, 0) },
        ShortcutAction(id: "step_yw", label: "90° 回す Y-W", def: "Y") { step90($0, 1) },
        ShortcutAction(id: "step_zw", label: "90° 回す Z-W", def: "Z") { step90($0, 2) },
        ShortcutAction(id: "spin_xw", label: "回し続ける X-W", def: "4") { $0.spinX.toggle() },
        ShortcutAction(id: "spin_yw", label: "回し続ける Y-W", def: "5") { $0.spinY.toggle() },
        ShortcutAction(id: "spin_zw", label: "回し続ける Z-W", def: "6") { $0.spinZW.toggle() },
        ShortcutAction(id: "spin_xy", label: "回し続ける X-Y", def: "7") { $0.spinXY.toggle() },
        ShortcutAction(id: "spin_xz", label: "回し続ける X-Z", def: "8") { $0.spinXZ.toggle() },
        ShortcutAction(id: "spin_yz", label: "回し続ける Y-Z", def: "9") { $0.spinYZ.toggle() },
        ShortcutAction(id: "spin_w2", label: "W(X,Y) 入／切（X-W・Y-W）", def: "Shift+Enter") { $0.toggleW2() },
        ShortcutAction(id: "dice", label: "超立方体サイコロを振る", def: "Shift+0") { $0.rollDice() },
        ShortcutAction(id: "spin_3d", label: "3D 入／切（X-Y・X-Z・Y-Z）", def: "D") { $0.toggle3D() },
        ShortcutAction(id: "spin_6", label: "全て 入／切（6 面すべて）", def: "Shift+A") { $0.toggle6() },
        ShortcutAction(id: "sideSwap", label: "パネルの左右 切りかえ", def: "B") { $0.panelLeft.toggle() },
        ShortcutAction(id: "viewSwap", label: "立方体と超立方体の左右 入れかえ", def: "Shift+B") { $0.swapViews.toggle() },
        ShortcutAction(id: "left3d", label: "立方体の 3D 回転 切りかえ（X-Y だけ ⇔ 全部）", def: "Shift+D") { $0.left3DAll.toggle() },
        ShortcutAction(id: "explode", label: "分解（バラす ⇔ くっつける）", def: "Shift+E") { st in if st.counting { st.endCount() }; st.startXp(st.apart ? 0 : 1) },
        ShortcutAction(id: "count", label: "分解して 1 個ずつ数える", def: "Shift+C") { st in if st.counting { st.endCount() } else { st.startCount() } },
        ShortcutAction(id: "cycle", label: "どこから見る：周回 入／切", def: "") { $0.toggleCycle() },
        ShortcutAction(id: "keys", label: "ショートカットの設定を開く", def: "Shift+K") { _ in ShortcutStore.shared.show = true },
    ]

    #if os(macOS)
    /// 押したキーを「Shift+F」の形に（Shift で文字が変わるキーも、もとのキーの名前で）
    static func name(of e: NSEvent) -> String? {
        let base: String
        switch e.keyCode {
        case 49: base = "Space"
        case 36, 76: base = "Enter"
        case 48: base = "Tab"
        case 53: base = "Escape"
        case 123: base = "Left"
        case 124: base = "Right"
        case 125: base = "Down"
        case 126: base = "Up"
        default:
            guard let c = e.characters(byApplyingModifiers: []), let ch = c.first, !ch.isWhitespace else { return nil }
            base = String(ch).uppercased()
        }
        var mods: [String] = []
        if e.modifierFlags.contains(.control) { mods.append("Ctrl") }
        if e.modifierFlags.contains(.option) { mods.append("Alt") }
        if e.modifierFlags.contains(.shift) { mods.append("Shift") }
        return (mods + [base]).joined(separator: "+")
    }
    /// キーを受け取る：登録中ならその機能に付ける、そうでなければ機能を動かす。動かしたら true（キーを食べる）
    func handle(_ e: NSEvent, _ st: OrigamiState) -> Bool {
        if e.modifierFlags.contains(.command) { return false }           // ⌘ はメニュー用
        guard let v = Self.name(of: e) else { return false }
        if let a = capturing {
            if v != "Escape" { assign(a, v) }
            capturing = nil; return true
        }
        guard let act = action(for: v) else { return false }
        // 押しっぱなしの「くり返し入力」は動かさない（食べるだけ）：Z を押しっぱなしにすると 90° が何回も足されたり、
        //   入／切の機能が入ったり切れたりをくり返して途中で止まったりした。今の動きは最後まで続く
        if e.isARepeat { return true }
        act.run(st); return true
    }
    #endif
}

/// ショートカットの設定の画面（ウェブ版の「キー設定」）
struct ShortcutSheet: View {
    @ObservedObject var ks = ShortcutStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("ショートカット", systemImage: "keyboard").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("既定に戻す") { ks.resetAll() }
                Button("閉じる") { ks.capturing = nil; ks.show = false }.keyboardShortcut(.cancelAction)
            }
            Text("「変更」を押してから、付けたいキーを押す（Esc でやめる）。同じキーがほかの機能にあれば、そちらからは外れる。ウェブ版のキーをもとにしている").font(.caption).foregroundStyle(UIC.sub)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(ShortcutStore.actions) { a in
                        HStack {
                            Text(a.label).font(.system(size: 12)).foregroundStyle(UIC.text)
                            Spacer()
                            let k = ks.keys[a.id] ?? ""
                            Text(ks.capturing == a.id ? "キーを押す…" : (k.isEmpty ? "なし" : k))
                                .font(.system(size: 12, weight: .semibold).monospaced())
                                .foregroundStyle(ks.capturing == a.id ? UIC.amber : (k.isEmpty ? UIC.sub : UIC.cyan)).frame(minWidth: 110, alignment: .trailing)
                            Button("変更") { ks.capturing = a.id }.controlSize(.small)
                            Button { ks.keys[a.id] = ""; ks.save() } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).foregroundStyle(UIC.sub).help("キーを外す")
                        }
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .background(ks.capturing == a.id ? UIC.amber.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(14).frame(width: 560, height: 560).background(UIC.panel).preferredColorScheme(.dark)
    }
}
