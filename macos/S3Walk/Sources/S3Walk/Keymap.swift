// ショートカットキー：景色の操作のうち、キー 1 つで切りかえるもの。どのキーにするかは設定の「ショートカットキー」で変えられる（UserDefaults に保存）。
//   歩く・向きのキー（W A S D Q E・矢印）とマウスは決まったまま。⌘・⌃ の付いたキーはメニューのまま
import SwiftUI

enum KeyAction: String, CaseIterable, Identifiable {
    case walk, roam, headGo, lookReset, home, mark, turbo
    case shell, solid, bare, grand, rangeDown, rangeUp
    case space, lite, eq, crisp, orient, foot, markStyle, mapAxes
    case panel, allPanels, hud, help, fps, scaleDown, scaleUp
    var id: String { rawValue }
    /// 設定の一覧と説明で使う名前
    var title: String {
        switch self {
        case .walk: return "歩き続ける"
        case .roam: return "縦横無尽"
        case .headGo: return "見回した向きへ進む"
        case .lookReset: return "見回しを戻す"
        case .home: return "アナ極へ戻る"
        case .mark: return "ここに目印を置く"
        case .turbo: return "ターボ（いきなり最高速）"
        case .shell: return "球層"
        case .solid: return "立体の殻"
        case .bare: return "網目なし"
        case .grand: return "壮大"
        case .rangeDown: return "殻の見える距離 −"
        case .rangeUp: return "殻の見える距離 ＋"
        case .space: return "背景（深海 ⇄ 宇宙）"
        case .lite: return "軽い線"
        case .eq: return "赤道の膜"
        case .crisp: return "線の見え方"
        case .orient: return "向きの赤い点"
        case .foot: return "足あと"
        case .markStyle: return "目印の見せ方"
        case .mapAxes: return "地図の軸"
        case .panel: return "設定のパネル"
        case .allPanels: return "パネルと地図を全部隠す"
        case .hud: return "表示（左上の数字）"
        case .help: return "操作の説明"
        case .fps: return "60fps 前後 ⇄ 画面の速さ"
        case .scaleDown: return "描く細かさ −"
        case .scaleUp: return "描く細かさ ＋"
        }
    }
    var group: String {
        switch self {
        case .walk, .roam, .headGo, .lookReset, .home, .mark, .turbo: return "歩く"
        case .shell, .solid, .bare, .grand, .rangeDown, .rangeUp: return "球層"
        case .space, .lite, .eq, .crisp, .orient, .foot, .markStyle, .mapAxes: return "見え方"
        case .panel, .allPanels, .hud, .help, .fps, .scaleDown, .scaleUp: return "画面"
        }
    }
    /// 初めのキー（今までのキーのまま）。小文字で。" " は Space、"\t" は Tab、"\r" は Return
    var defaults: [String] {
        switch self {
        case .walk: return ["k"]
        case .roam: return ["u"]
        case .headGo: return ["\r"]
        case .lookReset: return ["h"]
        case .home: return ["r"]
        case .mark: return ["m"]
        case .turbo: return ["z"]
        case .shell: return ["l"]
        case .solid: return ["t"]
        case .bare: return ["b"]
        case .grand: return ["g"]
        case .rangeDown: return ["-"]
        case .rangeUp: return ["=", "+"]
        case .space: return ["n"]
        case .lite: return ["j"]
        case .eq: return ["y"]
        case .crisp: return ["c"]
        case .orient: return ["o"]
        case .foot: return ["f"]
        case .markStyle: return ["p"]
        case .mapAxes: return ["x"]
        case .panel: return [" "]
        case .allPanels: return ["\t"]
        case .hud: return ["i"]
        case .help: return ["?", "/"]
        case .fps: return ["v"]
        case .scaleDown: return ["["]
        case .scaleUp: return ["]"]
        }
    }
}

final class Keymap: ObservableObject {
    static let shared = Keymap()
    static let store = "s3walk.keys.v1"
    /// 歩く・向きのキー（変えられない）
    static let fixed: Set<String> = ["w", "a", "s", "d", "q", "e"]
    @Published private(set) var keys: [KeyAction: [String]] = [:]
    /// キーを待っている操作（設定でキーの札を押した後、次に押したキーがその操作のキーになる）
    @Published var recording: KeyAction? = nil
    /// false：保存しない（確かめ用）
    let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        let d = persist ? UserDefaults.standard.dictionary(forKey: Keymap.store) as? [String: [String]] ?? [:] : [:]
        for a in KeyAction.allCases { keys[a] = d[a.rawValue] ?? a.defaults }
    }
    func save() { guard persist else { return }; UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) }), forKey: Keymap.store) }

    func action(for k: String) -> KeyAction? { KeyAction.allCases.first { keys[$0]?.contains(k) == true } }
    /// a のキーを k だけにする。k をほかの操作が使っていたら、そちらから外す（外した操作を返す）
    @discardableResult func assign(_ k: String, to a: KeyAction) -> KeyAction? {
        var lost: KeyAction? = nil
        for b in KeyAction.allCases where b != a && keys[b]?.contains(k) == true { keys[b]?.removeAll { $0 == k }; lost = b }
        keys[a] = [k]; save()
        return lost
    }
    func clear(_ a: KeyAction) { keys[a] = []; save() }
    func reset() { for a in KeyAction.allCases { keys[a] = a.defaults }; save() }
    var isDefault: Bool { KeyAction.allCases.allSatisfy { keys[$0] == $0.defaults } }

    /// キーの見せ方（L・Space・Tab・Return など）
    static func label(_ k: String) -> String {
        switch k {
        case " ": return "Space"
        case "\t": return "Tab"
        case "\r": return "Return"
        default: return k.uppercased()
        }
    }
    /// a のキー（「L」、2 つなら「= / +」。なしなら空）
    func label(_ a: KeyAction) -> String { (keys[a] ?? []).map(Keymap.label).joined(separator: " / ") }
    /// 名前の後ろに付ける「（L）」。キーがなければ付けない
    func hint(_ a: KeyAction) -> String { let s = label(a); return s.isEmpty ? "" : "（\(s)）" }

    /// 操作の説明（? で出る）。決まったキーの後ろに、今のキーを並べる
    func helpText() -> String {
        var lines = ["W/S 前・後　A/D 右・左　Q/E 上・下（Shift で 3 倍）　←→ 方位　↑↓ 仰角　ドラッグ・2 本指 見回し（Shift＋ドラッグ 進む向き）"]
        let items = KeyAction.allCases.compactMap { a -> String? in let s = label(a); return s.isEmpty ? nil : "\(s) \(a.title)" }
        stride(from: 0, to: items.count, by: 8).forEach { lines.append(items[$0..<min(items.count, $0 + 8)].joined(separator: "　")) }
        lines.append("⌘1・⌘2・⌘3 地図を隠す・並べる・浮かせる　⌃F（⌃⌘F）全画面　キーは設定の「ショートカットキー」で変えられる")
        return lines.joined(separator: "\n")
    }
}

/// 設定の「ショートカットキー」：操作ごとにキーの札。札を押して次のキーを押すとそのキーに（Esc でやめる、⌫ でキーなし）
struct KeymapPanel: View {
    @ObservedObject var km = Keymap.shared
    var body: some View {
        let groups = ["歩く", "球層", "見え方", "画面"]
        VStack(alignment: .leading, spacing: 5) {
            ForEach(groups, id: \.self) { g in
                Text(g).font(.caption.bold()).foregroundStyle(Space.lilac).padding(.top, g == groups[0] ? 0 : 4)
                ForEach(KeyAction.allCases.filter { $0.group == g }) { a in
                    HStack {
                        Text(a.title).foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 6)
                        let rec = km.recording == a, s = km.label(a)
                        Button { km.recording = rec ? nil : a } label: {
                            Text(rec ? "キーを押す…" : s.isEmpty ? "なし" : s)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(rec ? Space.bg : s.isEmpty ? Space.slate : .white)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .frame(minWidth: 54)
                                .background(rec ? Space.amber : Space.chip, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(rec ? Space.amber : Space.line))
                        }
                        .buttonStyle(.plain)
                        .help("押してから新しいキーを押す（Esc でやめる、⌫ でキーなし）")
                    }
                    .font(.callout)
                }
            }
            HStack {
                Button("初めのキーに戻す") { km.recording = nil; km.reset() }.disabled(km.isDefault)
            }.padding(.top, 4)
            Text("W A S D Q E と矢印（歩く・向き）は変えられない。ほかの操作で使っているキーを選ぶと、そちらからは外れる")
                .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
        }
    }
}
