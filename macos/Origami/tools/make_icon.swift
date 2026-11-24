// 次元おりがみのアイコン（フラットデザイン）：超立方体の展開図「ダリの十字架」を、等角図の積み木で。
//   面はベタぬり（上・左・右で明るさ 3 段）、光・ぼかし・グラデーションなし。
//   使い方：swift tools/make_icon.swift 出力フォルダ [案の番号]
//   出力：AppIcon-mac-1024.png（Mac：角の丸い四角＋まわりは透明）・AppIcon-ios-1024.png（iPad：四角いっぱい、OS が角を丸める）
import AppKit

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let variant = args.count > 2 ? Int(args[2]) ?? 6 : 6                      // 決めたのは 6（最初の等角図・折らない。2026-11-24 ユーザーが選んだ）
// 案：(横の向き°, 見下ろす°, 積み木のすき間)
let variants: [(Double, Double, Double, Double)] = [(20, 24, 0.07, 0), (20, 24, 0.07, 35), (20, 24, 0.07, 55), (30, 28, 0.07, 35), (30, 28, 0.07, 55), (15, 18, 0.07, 45), (45, 35.26, 0.06, 0)]   // 4 つ目：ふたの折れ角（°）。6 が決めた案（ふつうの等角図・折らない）

func hex(_ h: UInt32) -> (Double, Double, Double) { (Double((h >> 16) & 255) / 255, Double((h >> 8) & 255) / 255, Double(h & 255) / 255) }
func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> CGColor {
    CGColor(srgbRed: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: 1)
}
let white = (1.0, 1.0, 1.0), black = (0.0, 0.0, 0.08)
// アプリの胞の色：w 紫・y 緑・x 赤・z 水色
let W = hex(0x9333ea), Y = hex(0x10b981), X = hex(0xf43f5e), Z = hex(0x38bdf8)
// ダリの十字架：縦に 4 つ（下から y−・真ん中・y+・ふた）、真ん中のまわりに x± と z±
var cubes: [([Int], (Double, Double, Double))] = [
    ([0, 0, 0], Y), ([0, 1, 0], W), ([0, 2, 0], Y), ([0, 3, 0], W),
    ([1, 1, 0], X), ([-1, 1, 0], X), ([0, 1, 1], Z), ([0, 1, -1], Z),
]

func draw(_ ctx: CGContext, _ S: Double, mac: Bool) {
    let bg = hex(0x111827)
    // 下地
    if mac {
        // Mac：1024 の中の 824 の角丸（Apple の決まりの大きさ）。まわりは透明
        let m = S * 100 / 1024, r = S * 185 / 1024
        let p = CGPath(roundedRect: CGRect(x: m, y: m, width: S - 2 * m, height: S - 2 * m), cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(p); ctx.setFillColor(mix(bg, bg, 0)); ctx.fillPath()
        ctx.addPath(p); ctx.clip()
    } else {
        ctx.setFillColor(mix(bg, bg, 0)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }
    // 見る向き：y の軸のまわりに az、上から el だけ見下ろす（ふつうの等角図は az 45°・el 35.3°）
    let (azD, elD, gap, foldD) = variants[min(variant, variants.count - 1)]
    let az = azD * .pi / 180, el = elD * .pi / 180
    func rot(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let x1 = cos(az) * x - sin(az) * z, z1 = sin(az) * x + cos(az) * z
        return (x1, cos(el) * y - sin(el) * z1 * -1 * -1 + 0 * x1, sin(el) * y + cos(el) * z1)   // (画面の右, 画面の上, 手前)
    }
    func pr(_ x: Double, _ y: Double, _ z: Double) -> CGPoint { let r = rot(x, y, z); return CGPoint(x: r.0, y: r.1) }
    var lo = CGPoint(x: 1e9, y: 1e9), hi = CGPoint(x: -1e9, y: -1e9)
    func Tb(_ i: Int, _ v: (Double, Double, Double)) -> (Double, Double, Double) {
        guard i == 3, foldD != 0 else { return v }
        let a = -foldD * .pi / 180, dx = v.0 - 1, dy = v.1 - 3
        return (1 + dx * cos(a) - dy * sin(a), 3 + dx * sin(a) + dy * cos(a), v.2)
    }
    for (i, (c, _)) in cubes.enumerated() { for dx in 0...1 { for dy in 0...1 { for dz in 0...1 {
        let q = Tb(i, (Double(c[0] + dx), Double(c[1] + dy), Double(c[2] + dz)))
        let p = pr(q.0, q.1, q.2); lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
    } } } }
    let inner = mac ? 0.72 : 0.84
    let k = S * inner / max(hi.x - lo.x, hi.y - lo.y)
    let ox = S / 2 - (lo.x + hi.x) / 2 * k, oy = S / 2 - (lo.y + hi.y) / 2 * k
    func P(_ v: (Double, Double, Double)) -> CGPoint { let p = pr(v.0, v.1, v.2); return CGPoint(x: ox + p.x * k, y: oy + p.y * k) }
    // ふた（いちばん上、3 番）は、右上の辺（x ＝ 1・y ＝ 3）をちょうつがいに、右へパタンと折れかけ
    let fa = -foldD * .pi / 180
    func T(_ i: Int, _ v: (Double, Double, Double)) -> (Double, Double, Double) {
        guard i == 3, foldD != 0 else { return v }
        let dx = v.0 - 1, dy = v.1 - 3
        return (1 + dx * cos(fa) - dy * sin(fa), 3 + dx * sin(fa) + dy * cos(fa), v.2)
    }
    func TN(_ i: Int, _ n: (Double, Double, Double)) -> (Double, Double, Double) {
        guard i == 3, foldD != 0 else { return n }
        return (n.0 * cos(fa) - n.1 * sin(fa), n.0 * sin(fa) + n.1 * cos(fa), n.2)
    }
    // 奥から手前へ（積み木の真ん中の「手前」の値が小さい順）
    let order = cubes.indices.sorted { rot(Double(cubes[$0].0[0]) + 0.5, Double(cubes[$0].0[1]) + 0.5, Double(cubes[$0].0[2]) + 0.5).2 < rot(Double(cubes[$1].0[0]) + 0.5, Double(cubes[$1].0[1]) + 0.5, Double(cubes[$1].0[2]) + 0.5).2 }
    // 面：外向きの向き n と 4 つの角。目の方を向く面だけ、上は明るく・横は向きで 2 段
    let faces: [((Double, Double, Double), [(Double, Double, Double)])] = [
        ((0, 1, 0), [(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)]), ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
        ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]), ((-1, 0, 0), [(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)]),
        ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]), ((0, 0, -1), [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]),
    ]
    for i in order {
        let (c, col) = cubes[i], e = 1 - 2 * gap
        for (n, q) in faces {
            let wn = TN(i, n), rn = rot(wn.0, wn.1, wn.2)
            guard rn.2 > 1e-6 else { continue }
            // 3 段のベタぬり：上を向く面は明るく、画面の右を向く面はそのまま、左を向く面は暗く（最初の案と同じ）
            let shade = wn.1 > 0.55 ? mix(col, white, 0.28) : (rn.0 < 0 ? mix(col, black, 0.32) : mix(col, black, 0.0))
            let pts = q.map { P(T(i, (Double(c[0]) + gap + $0.0 * e, Double(c[1]) + gap + $0.1 * e, Double(c[2]) + gap + $0.2 * e))) }
            ctx.beginPath(); ctx.addLines(between: pts); ctx.closePath(); ctx.setFillColor(shade); ctx.fillPath()
        }
    }
}

func write(_ name: String, mac: Bool) {
    let S = 1024
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    ctx.setShouldAntialias(true)
    draw(ctx, Double(S), mac: mac)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
write("AppIcon-mac-1024.png", mac: true)
write("AppIcon-ios-1024.png", mac: false)
print("書いた：\(outDir)")
