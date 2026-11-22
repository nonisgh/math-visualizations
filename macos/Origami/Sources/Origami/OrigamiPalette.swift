// 胞の色のパレット（ウェブ版 hypercube.html の「胞の色（パレット）」と同じ決まり）。
//   各面・胞は、向いている方向の色になる：3D＝立方体の面（±X・±Y・中心 −Z・蓋 +Z）、4D＝超立方体の胞（±X・±Y・±Z・中心 −W・蓋 +W）
//   補色モード：−の色を＋の色の補色（色相を 180° 回す）に自動で。中心だけ補色：中心の色を蓋の色の補色に。
//   軸の色を立体に合わせる：x・y・z・w の座標軸の色を、選んだ側（＋か−）の立体の色にそろえる（立体の色は変えない）
import SwiftUI
import simd

extension OrigamiState {
    static let palKeys = ["px", "nx", "py", "ny", "pz", "nz", "pw", "nw"]
    static let palDef3: [String: UInt32] = ["px": 0xf43f5e, "nx": 0xf43f5e, "py": 0x10b981, "ny": 0x10b981, "pz": 0x0284c7, "nz": 0x0284c7, "pw": 0x9333ea, "nw": 0x9333ea]
    static let palDef4: [String: UInt32] = ["px": 0xf43f5e, "nx": 0xf43f5e, "py": 0x10b981, "ny": 0x10b981, "pz": 0x38bdf8, "nz": 0x38bdf8, "pw": 0x9333ea, "nw": 0x9333ea]
    /// 面・胞の番号 → パレットのどの色か（0 番は中心、最後は蓋）
    static let palSlots3 = ["nz", "py", "ny", "px", "nx", "pz"]
    static let palSlots4 = ["nw", "py", "ny", "px", "nx", "pz", "nz", "pw"]

    /// 補色（色相を 180° 回す。明るさと鮮やかさはそのまま＝ウェブ版の compHex と同じ考え）
    static func compHex(_ c: UInt32) -> UInt32 {
        let r = Double((c >> 16) & 255) / 255, g = Double((c >> 8) & 255) / 255, b = Double(c & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        if d < 1e-6 { return c }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double = mx == r ? (g - b) / d + (g < b ? 6 : 0) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
        h = (h / 6 + 0.5).truncatingRemainder(dividingBy: 1)
        func f(_ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }; if t < 0.5 { return q }; if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }; return p
        }
        let R = UInt32((f(h + 1.0 / 3) * 255).rounded()), G = UInt32((f(h) * 255).rounded()), B = UInt32((f(h - 1.0 / 3) * 255).rounded())
        return (R << 16) | (G << 8) | B
    }
    /// 実際に使うパレット（補色モードなら −は＋の補色）
    func effPal(_ d: Int) -> [String: UInt32] {
        var P = d == 3 ? pal3 : pal4
        if palComp { for a in ["x", "y", "z", "w"] { if let c = P["p" + a] { P["n" + a] = Self.compHex(c) } } }
        return P
    }
    /// 面（立方体）・胞（超立方体）の色を、番号の順に
    func cellColors(_ n: Int) -> [UInt32] {
        let E = effPal(n), S = n == 3 ? Self.palSlots3 : Self.palSlots4
        return S.enumerated().map { i, k in
            if i == 0 && palCompCenter { return Self.compHex(E[S[S.count - 1]] ?? 0x888888) }
            return E[k] ?? 0x888888
        }
    }
    /// 座標軸の色（x・y・z・w）。「軸の色を立体に合わせる」なら、その窓の立体の色（＋側か−側）
    func axisColor(_ ax: Int, _ n: Int) -> SIMD3<Float> {
        guard axisSyncOn else { return Self.axisCol[ax] }
        let key = (axisSyncMinus ? "n" : "p") + ["x", "y", "z", "w"][min(ax, 3)]
        return Self.rgb(effPal(n)[key] ?? 0x888888)
    }
    func axisColorUI(_ ax: Int, _ n: Int) -> Color { let c = axisColor(ax, n); return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)) }
    static func hexString(_ c: UInt32) -> String { String(format: "#%06x", c) }
    static func parseHex(_ s: String) -> UInt32? { UInt32(s.replacingOccurrences(of: "#", with: ""), radix: 16) }
}

/// パレットの画面：行 ±X〜±W × 列 4D・3D の枠。枠を選んで、色の見本・好きな色で塗る
struct PaletteEditor: View {
    @ObservedObject var st: OrigamiState
    // 色の見本：色相ごとに 濃・標準・薄 の 3 段（ウェブ版と同じ）
    static let hues: [(String, [UInt32])] = [("赤", [0xbe123c, 0xf43f5e, 0xfda4af]), ("橙", [0xc2410c, 0xf97316, 0xfdba74]), ("琥珀", [0xb45309, 0xf59e0b, 0xfcd34d]), ("黄", [0xa16207, 0xfacc15, 0xfde047]),
        ("黄緑", [0x4d7c0f, 0xa3e635, 0xbef264]), ("緑", [0x047857, 0x10b981, 0x6ee7b7]), ("青緑", [0x0f766e, 0x2dd4bf, 0x99f6e4]), ("水色", [0x0369a1, 0x38bdf8, 0x7dd3fc]),
        ("青", [0x1d4ed8, 0x3b82f6, 0x93c5fd]), ("藍", [0x4338ca, 0x6366f1, 0xa5b4fc]), ("紫", [0x7e22ce, 0xa855f7, 0xd8b4fe]), ("桃", [0xbe185d, 0xec4899, 0xf9a8d4]), ("灰", [0x334155, 0x94a3b8, 0xf1f5f9])]
    static let rows: [(String, String)] = [("px", "+X"), ("nx", "−X"), ("py", "+Y"), ("ny", "−Y"), ("pz", "+Z"), ("nz", "−Z"), ("pw", "+W"), ("nw", "−W")]
    func note(_ d: Int, _ k: String) -> String { d == 3 ? (k == "pz" ? "蓋" : k == "nz" ? "中心" : "") : (k == "pw" ? "蓋" : k == "nw" ? "中心" : "") }
    func used(_ d: Int, _ k: String) -> Bool { d == 4 || k.last != "w" }
    var selD: Int { st.palSel.hasPrefix("3") ? 3 : 4 }
    var selK: String { String(st.palSel.dropFirst(2)) }
    func setSel(_ c: UInt32) {
        var k = selK; if st.palComp && k.first == "n" { k = "p" + String(k.last!) }
        if selD == 3 { st.pal3[k] = c } else { st.pal4[k] = c }
    }
    static func color(_ c: UInt32) -> Color { Color(red: Double((c >> 16) & 255) / 255, green: Double((c >> 8) & 255) / 255, blue: Double(c & 255) / 255) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 表：行 ±X〜±W、列 4D（超立方体）・3D（立方体の面）
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
                GridRow { Text(""); Text("4D（超立方体）").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.sub); Text("3D（立方体の面）").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.sub) }
                ForEach(Self.rows, id: \.0) { k, L in
                    GridRow {
                        Text(L).font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.text)
                        ForEach([4, 3], id: \.self) { d in
                            if used(d, k) {
                                let E = st.effPal(d), auto = st.palComp && k.first == "n", on = st.palSel == "\(d):\(k)"
                                Button { st.palSel = "\(d):\(k)" } label: {
                                    HStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 3).fill(Self.color(E[k] ?? 0)).frame(width: 16, height: 16).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2)))
                                        Text(note(d, k)).font(.system(size: 10)).foregroundStyle(UIC.sub)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 5).padding(.vertical, 2).frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? UIC.cyan : UIC.line, lineWidth: on ? 1.5 : 1))
                                }.buttonStyle(.plain).focusable(false).disabled(auto).opacity(auto ? 0.75 : 1)
                                .help("\(d)D の \(L)" + (note(d, k).isEmpty ? "" : "（\(note(d, k))）") + (auto ? "：補色モードで自動" : ""))
                            } else {
                                Text("（使わない）").font(.system(size: 10)).foregroundStyle(UIC.sub.opacity(0.5))
                            }
                        }
                    }
                }
            }
            // 色の見本（濃・標準・薄 × 13 色）
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(Self.hues.indices, id: \.self) { h in
                            let c = Self.hues[h].1[r]
                            Button { setSel(c) } label: { RoundedRectangle(cornerRadius: 2).fill(Self.color(c)).frame(height: 15).overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.15))) }
                                .buttonStyle(.plain).focusable(false).help("\(Self.hues[h].0)（\(["濃", "標準", "薄"][r])）\(OrigamiState.hexString(c))")
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ColorPicker("好きな色", selection: Binding(get: { Self.color(st.effPal(selD)[selK] ?? 0) }, set: { c in
                    #if os(macOS)
                    let n = NSColor(c).usingColorSpace(.sRGB) ?? .gray
                    let v = (UInt32(n.redComponent * 255) << 16) | (UInt32(n.greenComponent * 255) << 8) | UInt32(n.blueComponent * 255)
                    #else
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
                    let v = (UInt32(max(0, min(1, r)) * 255) << 16) | (UInt32(max(0, min(1, g)) * 255) << 8) | UInt32(max(0, min(1, b)) * 255)
                    #endif
                    setSel(v)
                }), supportsOpacity: false).font(.system(size: 11))
                Btn("±をそろえる") {
                    let o = (selK.first == "p" ? "n" : "p") + String(selK.last!)
                    if selD == 3 { st.pal3[o] = st.pal3[selK] } else { st.pal4[o] = st.pal4[selK] }
                }.help("選んでいる枠の色を、同じ軸の反対側（＋と−）にも入れる")
                Btn("既定に戻す") { st.pal3 = OrigamiState.palDef3; st.pal4 = OrigamiState.palDef4 }.help("パレットを最初の色に戻す")
            }
            HStack(spacing: 6) {
                Btn("補色モード", on: st.palComp) { st.palComp.toggle() }.help("−の色を、＋の色の補色（色相を反対に回した色）に自動で決める。−の枠は選べなくなる")
                Btn("中心だけ補色", on: st.palCompCenter) { st.palCompCenter.toggle() }.help("中心の色を、その図形の蓋の色の補色にする（立方体＝+Z の補色、超立方体＝+W の補色）")
            }
            HStack(spacing: 6) {
                Btn("軸の色を立体に合わせる", on: st.axisSyncOn) { st.axisSyncOn.toggle() }.help("x・y・z・w の座標軸（線・矢じり・名前）の色を、選んだ側の立体の色にする。立体の色は変わらない")
                Btn("＋側", on: st.axisSyncOn && !st.axisSyncMinus) { st.axisSyncMinus = false; st.axisSyncOn = true }.help("x 軸＝+X、y 軸＝+Y、z 軸＝+Z、w 軸＝+W（蓋）の色")
                Btn("−側", on: st.axisSyncOn && st.axisSyncMinus) { st.axisSyncMinus = true; st.axisSyncOn = true }.help("x 軸＝−X、y 軸＝−Y、z 軸＝−Z（立方体は中心）、w 軸＝−W（中心）の色")
            }
        }
    }
}
