// 点のタブ（ウェブ版の「座標を指定して点を置く」「頂点のプリセット」「注目点のプリセット」「置いた点」）。
//   座標は「頂点が ±1」の単位（描く時に half＝0.9 を掛けて実寸にする）。1 より大きい入力は小数に直す（443→0.443）。
//   超立方体：4D 座標 (x,y,z,w) に置く。どれかの座標が ±1（＝境界）の点は、その座標が一定の胞についていくので、
//     展開図でも・バラしても、その胞の同じ場所（頂点・辺の中点・面の中心など）にいる。中の点は組み上がった時だけ。
//   立方体：対応する (x, y, w) に置く（立方体の z は超立方体の w）。
//   v は 5 次元の座標（あとで 5 次元体を作る時の準備。今は v ≠ 0 の点は描かない）
import SwiftUI

struct UPoint: Identifiable, Equatable {
    var id = UUID()
    var c: [Double]                 // x y z w v（5 つ。v は 5 次元の準備）
    var color: UInt32 = 0xffd54a
    var label = ""
    var show = true
    var lock = false
    var x: Double { c[0] }; var y: Double { c[1] }; var z: Double { c[2] }; var w: Double { c[3] }; var v: Double { c.count > 4 ? c[4] : 0 }
}

extension OrigamiState {
    static let ptSwatches: [UInt32] = [0xffd54a, 0xff5d6c, 0x3ddc84, 0x56a8ff, 0xb07cff, 0xff44dd, 0x33e5ff, 0x50c878, 0xffffff]
    static let ptAxisCol: [UInt32] = [0xff5d6c, 0x3ddc84, 0x56a8ff, 0xb07cff]      // x y z w

    /// 入力を座標に（1 より大きい数は小数に：443→0.443、12→0.12、2→0.2。数でなければ 0）
    static func normPt(_ s: String) -> Double {
        let t = s.replacingOccurrences(of: "−", with: "-").filter { "0123456789.eE+-".contains($0) }
        guard var v = Double(t), v.isFinite else { return 0 }
        let a = abs(v)
        if a > 1 { let digits = floor(log10(floor(a))) + 1; v /= pow(10, digits) }
        return (v * 1e6).rounded() / 1e6
    }
    static func fmtPt(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.3f", r); while s.hasSuffix("0") { s.removeLast() }
        return s
    }
    static func ptCoordText(_ p: UPoint) -> String { "(" + p.c.prefix(p.v != 0 ? 5 : 4).map(fmtPt).joined(separator: ", ") + ")" }
    static func ptLabelText(_ p: UPoint) -> String { p.label.isEmpty ? ptCoordText(p) : p.label }
    /// −1・0・1 だけでできた点の種類（0 の数で決まる）
    static func ptKind(_ p: UPoint) -> String {
        let v = Array(p.c.prefix(4))
        guard v.allSatisfy({ $0 == 1 || $0 == 0 || $0 == -1 }), p.v == 0 else { return "" }
        let z = v.filter { $0 == 0 }.count
        if z == 1 && p.w == 0 { return "w=0 の断面" }
        return ["頂点", "辺の中点", "面の中心", "胞の中心", "中心"][z]
    }

    // ---- 置く・消す ----
    @discardableResult
    func addPt(_ c: [Double], _ color: UInt32, _ label: String = "", lock: Bool = false) -> UPoint {
        var cc = c.map { max(-1, min(1, $0)) }; while cc.count < 5 { cc.append(0) }
        let p = UPoint(c: cc, color: color, label: label, lock: lock)
        userPts.append(p)
        return p
    }
    func removePt(_ id: UUID) {
        guard let i = userPts.firstIndex(where: { $0.id == id }) else { return }
        if userPts[i].lock { ptStatus = "ロック中なので消せません（🔓 を押すと外せます）"; return }
        userPts.remove(at: i)
    }
    /// ロックしていない点を全部消す
    func clearPts() {
        let nLock = userPts.filter(\.lock).count
        userPts.removeAll { !$0.lock }
        ptStatus = nLock > 0 ? "消しました（ロックした \(nLock) 個は残しました）" : "全部消しました"
    }
    func lockAllPts() {
        guard !userPts.isEmpty else { ptStatus = "ロックする点がありません"; return }
        let all = !userPts.allSatisfy(\.lock)
        for i in userPts.indices { userPts[i].lock = all }
        ptStatus = all ? "置いた点を全部ロックしました（\(userPts.count) 個）" : "ロックを全部外しました"
    }
    /// 16 頂点ぜんぶ（＋＋＋＋と−−−−は手前・奥の目印がいるので、残りの 14）。w が＋は暖色、−は寒色
    func addAllVertices() {
        var list: [[Double]] = []
        for i in 1..<15 { list.append([8, 4, 2, 1].map { i & $0 != 0 ? -1 : 1 }) }
        addPresetPts(list, { $0[3] > 0 ? 0xffb347 : 0x56c8ff }, "16 頂点（＋＋＋＋と−−−−は手前・奥の目印）")
    }
    /// −1・0・1 の 81 通り（x y z w）
    static let pt81: [[Double]] = (0..<81).map { i in
        var n = i, v: [Double] = []
        for _ in 0..<4 { v.insert([1, 0, -1][n % 3], at: 0); n /= 3 }
        return v
    }
    /// 注目点：0 の数で選ぶ。同じ座標の点がもうあれば、増やさずに色だけ変える
    func addPresetPts(_ list: [[Double]], _ colorOf: ([Double]) -> UInt32, _ name: String) {
        var added = 0, recol = 0
        var pts = userPts
        for v in list {
            let c = colorOf(v)
            if let j = pts.firstIndex(where: { Array($0.c.prefix(4)) == v && $0.v == 0 }) {
                if pts[j].color != c || !pts[j].show { pts[j].color = c; pts[j].show = true; recol += 1 }
            } else { pts.append(UPoint(c: v + [0], color: c)); added += 1 }
        }
        userPts = pts
        ptStatus = "\(name)：\(added) 個 置きました" + (recol > 0 ? "（\(recol) 個は置いてあった点の色を変えました）" : "")
    }
    static func zeros(_ v: [Double]) -> Int { v.filter { $0 == 0 }.count }
    func addEdgeMids() { addPresetPts(Self.pt81.filter { Self.zeros($0) == 1 }, { Self.ptAxisCol[$0.firstIndex(of: 0)!] }, "辺の中点") }
    func addFaceCtrs() { addPresetPts(Self.pt81.filter { Self.zeros($0) == 2 }, { $0[3] == 0 ? 0xd9a6ff : 0xffd54a }, "面の中心") }
    func addCellCtrs() { addPresetPts(Self.pt81.filter { Self.zeros($0) == 3 }, { Self.ptAxisCol[$0.firstIndex(where: { $0 != 0 })!] }, "胞の中心") }
    func addW0Slice() { addPresetPts(Self.pt81.filter { $0[3] == 0 && Self.zeros($0) == 1 }, { _ in 0x7dffcf }, "w=0 の断面") }

    // ---- 描く位置 ----
    /// 置いた点の今の位置（景色の座標）と、どの胞についていくか（中の点は −1）。描かない時は nil。
    //   n＝4：(x,y,z,w)。n＝3：(x,y,w)
    func ptPosition(_ p: UPoint, _ n: Int) -> ([Double], Int)? {
        guard p.show, p.v == 0 else { return nil }
        let q: [Double] = n == 4 ? Array(p.c.prefix(4)) : [p.x, p.y, p.w]
        let cells = Self.cells(n)
        for (ci, cell) in cells.enumerated() {
            let (fa, fv) = Self.fixed(cell, n)
            if abs(q[fa] - fv) < 1e-6 { return (fold(cell, q, n), ci) }
        }
        // 中の点：組み上がっていて、バラしていない時だけ
        guard progress >= 0.999, explodeE < 0.02 else { return nil }
        return (q.map { $0 * Self.half }, -1)
    }

    // ---- 保存（設定の辞書に入れる） ----
    var ptsSnapshot: [[String: Any]] {
        userPts.map { ["c": $0.c, "color": Self.hexString($0.color), "label": $0.label, "show": $0.show, "lock": $0.lock] }
    }
    func applyPts(_ a: Any?) {
        guard let a = a as? [[String: Any]] else { return }
        userPts = a.compactMap { d in
            guard var c = d["c"] as? [Double], c.count >= 4, c.allSatisfy({ $0.isFinite }) else { return nil }
            while c.count < 5 { c.append(0) }
            return UPoint(c: c, color: (d["color"] as? String).flatMap(Self.parseHex) ?? 0xffd54a, label: d["label"] as? String ?? "",
                          show: d["show"] as? Bool ?? true, lock: d["lock"] as? Bool ?? false)
        }
    }
}

// ---- パネル ----
func hexColorBinding(_ get: @escaping () -> UInt32, _ set: @escaping (UInt32) -> Void) -> Binding<Color> {
    Binding(get: { Color(OrigamiState.rgbColor(get())) }, set: { c in set(OrigamiState.colorHex(c)) })
}
extension OrigamiState {
    static func rgbColor(_ h: UInt32) -> Color { let c = rgb(h); return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z)) }
    static func colorHex(_ c: Color) -> UInt32 {
        #if os(macOS)
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
        let r = n.redComponent, g = n.greenComponent, b = n.blueComponent
        #else
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func u(_ x: CGFloat) -> UInt32 { UInt32(max(0, min(255, (x * 255).rounded()))) }
        return u(r) << 16 | u(g) << 8 | u(b)
    }
}

/// 座標を指定して点を置く
struct PointAdder: View {
    @ObservedObject var st: OrigamiState
    @State private var tx = ["0", "0", "0", "0"]
    @State private var name = ""
    @State private var color: UInt32 = 0xffd54a
    @FocusState private var focus: Int?
    var vals: [Double] { tx.map(OrigamiState.normPt) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("頂点が ±1 の座標です（中心が 0）。1 より大きい数は小数に直します：443→0.443、12→0.12、2→0.2").font(.caption2).foregroundStyle(UIC.sub)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { k in
                    HStack(spacing: 2) {
                        Text(["x", "y", "z", "w"][k]).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(OrigamiState.rgbColor(OrigamiState.ptAxisCol[k]))
                        TextField("0", text: $tx[k]).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                            .frame(minWidth: 40).focused($focus, equals: k).onSubmit(add)
                    }
                }
            }
            Text("→ 置く位置 (" + vals.map(OrigamiState.fmtPt).joined(separator: ", ") + ")").font(.system(size: 10, design: .monospaced)).foregroundStyle(UIC.sub)
            HStack(spacing: 4) {
                ColorPicker("色", selection: hexColorBinding({ color }, { color = $0 })).fixedSize()
                ForEach(OrigamiState.ptSwatches, id: \.self) { c in
                    RoundedRectangle(cornerRadius: 3).fill(OrigamiState.rgbColor(c)).frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(c == color ? Color.white : Color.gray.opacity(0.5), lineWidth: c == color ? 2 : 1))
                        .onTapGesture { color = c }
                }
            }
            HStack {
                TextField("名前（なくても可）", text: $name).textFieldStyle(.roundedBorder).font(.system(size: 11)).focused($focus, equals: 9).onSubmit(add)
                Btn("追加", add)
            }
            if !st.ptStatus.isEmpty { Text(st.ptStatus).font(.caption2).foregroundStyle(.green.opacity(0.85)) }
        }
    }
    func add() {
        st.addPt(vals, color, name.trimmingCharacters(in: .whitespaces))
        st.ptStatus = "点を置きました"
        name = ""
        let i = OrigamiState.ptSwatches.firstIndex(of: color) ?? -1
        color = OrigamiState.ptSwatches[(i + 1) % OrigamiState.ptSwatches.count]   // 追加するたびに次の色へ
    }
}

/// 頂点のプリセット（16 個）：押すとその頂点に点を置く。色は「座標を指定して点を置く」の次の色（黄）
struct VertexGrid: View {
    @ObservedObject var st: OrigamiState
    func vbtn(_ i: Int) -> some View {
        let sg: [Double] = [8, 4, 2, 1].map { i & $0 != 0 ? -1 : 1 }
        return Button {
            st.addPt(sg, 0xffd54a); st.ptStatus = "頂点 (" + sg.map(OrigamiState.fmtPt).joined(separator: ", ") + ") に点を置きました"
        } label: {
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { k in Text(sg[k] > 0 ? "+" : "−").foregroundStyle(OrigamiState.rgbColor(OrigamiState.ptAxisCol[k])) }
            }.font(.system(size: 12, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity)
        }.focusable(false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("押すとその頂点に点を置きます（並びは x y z w）。頂点の点は折りたたみ中も、その頂点を追いかけます").font(.caption2).foregroundStyle(UIC.sub)
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 4) { ForEach(0..<4, id: \.self) { col in vbtn(row * 4 + col) } }
                }
            }
            Btn("16 頂点ぜんぶ") { st.addAllVertices() }
                .help("16 頂点すべてに点を置く（w が＋は暖色、−は寒色）。＋＋＋＋と−−−−は手前・奥の目印がいるので、残りの 14 頂点に置きます")
        }
    }
}

/// 注目点のプリセット
struct FocusPresets: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("座標を −1・0・1 で作ると、0 の数で種類が決まります：0 個＝頂点、1 個＝辺の中点、2 個＝面の中心、3 個＝胞の中心。どれも折りたたみ中も、その場所を追いかけます").font(.caption2).foregroundStyle(UIC.sub)
            HStack {
                Btn("辺の中点 32 個") { st.addEdgeMids() }.help("0 が 1 個の点。色は辺の向き：x＝赤、y＝緑、z＝青、w＝紫")
                Btn("面の中心 24 個") { st.addFaceCtrs() }.help("0 が 2 個の点。w を含む面（xw・yw・zw）は薄紫、含まない面（xy・xz・yz）は黄色")
            }
            HStack {
                Btn("胞の中心 8 個") { st.addCellCtrs() }.help("0 が 3 個の点。色は胞が垂直に立つ軸：x＝赤、y＝緑、z＝青、w＝紫。(0,0,0,±1) が外側と内側の立方体の中心")
                Btn("w=0 の断面 8 個") { st.addW0Slice() }.help("(±1, ±1, ±1, 0) の 8 点。内側と外側の立方体をつなぐ 8 本の辺の中点で、つなぐと w=0 で切った断面の立方体になる（ミント色）")
            }
            Text("同じ座標の点がもうあれば、増やさずに色だけプリセットの色に変えます").font(.caption2).foregroundStyle(UIC.sub)
        }
    }
}

/// 置いた点の一覧
struct PointList: View {
    @ObservedObject var st: OrigamiState
    @State private var showAll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(st.userPts.count) 個").font(.caption).foregroundStyle(UIC.sub)
                Spacer()
                let allLocked = !st.userPts.isEmpty && st.userPts.allSatisfy { $0.lock }
                Btn(allLocked ? "🔓 全部解除" : "🔒 全部ロック") { st.lockAllPts() }
                    .help("置いた点をまとめてロック／解除（ロックした点は「消す」でも「全部消す」でも消えません）")
                Btn("全部消す") { st.clearPts() }.help("ロックしていない点を全部消す")
            }
            if st.userPts.isEmpty {
                Text("まだありません。上で座標を入れるか、頂点のプリセットを押してください").font(.caption2).foregroundStyle(UIC.sub)
            }
            // 行が多いとパネルが重くなるので、初めは 15 行まで（「全部見る」で全部）
            let shown = showAll ? st.userPts.count : min(15, st.userPts.count)
            ForEach($st.userPts[0..<shown]) { $p in PtRow(st: st, p: $p) }
            if st.userPts.count > 15 {
                Btn(showAll ? "15 行までにする" : "全部見る（あと \(st.userPts.count - 15) 個）") { showAll.toggle() }
            }
            Toggle("名前（座標）を出す", isOn: $st.ptLabels)
            Toggle("立方体にも出す（立方体の (x, y, w)）", isOn: $st.ptLeft)
                .help("立方体にも、対応する位置 (x, y, w) に点を出す（立方体の z は超立方体の w に対応。超立方体の z は超立方体だけの軸）")
            LiveRead(live: st.live) { NumRow("大きさ", $st.ptSize, 0.25...1.2, "×%.2f", scale: 1) }
            Text("置いた点はアプリの中に自動で保存されます。手前（ピンク）・奥（水色）の目印は別の点で、色と大きさは上の「手前と奥の目印」で変えられます").font(.caption2).foregroundStyle(UIC.sub)
        }
    }
}

/// 置いた点の 1 行：色・座標（と種類）・隠す・ロック・消す
struct PtRow: View {
    @ObservedObject var st: OrigamiState
    @Binding var p: UPoint
    var text: String {
        let kind = OrigamiState.ptKind(p), head = p.label.isEmpty ? "" : p.label + "  "
        return head + OrigamiState.ptCoordText(p) + (kind.isEmpty ? "" : "  " + kind)
    }
    var body: some View {
        HStack(spacing: 6) {
            PtSwatch(color: $p.color)
            Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(p.show ? UIC.text : UIC.sub).lineLimit(2)
            Spacer(minLength: 2)
            Btn(p.show ? "隠す" : "表示") { p.show.toggle() }
            Btn(p.lock ? "🔓" : "🔒") { p.lock.toggle() }.help(p.lock ? "押すとロックを外す（今はロック中で消せません）" : "押すとロック（消せなくなる）")
            Btn("消す") { st.removePt(p.id) }.disabled(p.lock)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).stroke(p.lock ? Color.orange.opacity(0.45) : Color.gray.opacity(0.25)))
    }
}

/// 点の色の小さな見本：押すと見本の色と色選びを出す（色選びの部品は重いので、1 行ずつには置かない）
struct PtSwatch: View {
    @Binding var color: UInt32
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            RoundedRectangle(cornerRadius: 3).fill(OrigamiState.rgbColor(color)).frame(width: 18, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.6)))
        }
        .buttonStyle(.plain).focusable(false).help("色を変える")
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(OrigamiState.ptSwatches, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 3).fill(OrigamiState.rgbColor(c)).frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(c == color ? Color.white : Color.gray.opacity(0.5), lineWidth: c == color ? 2 : 1))
                            .onTapGesture { color = c }
                    }
                }
                ColorPicker("ほかの色", selection: hexColorBinding({ color }, { color = $0 }))
            }
            .padding(10)
        }
    }
}
