// 確かめ用（--smooth）：少しずつ 4D に回しながら超立方体を描き、となりのコマとのちがい（画素の明るさの差の平均）を並べる。
//   なめらかなら差は回した量に比例してそろう。ポンと切りかわる所があると、その 1 コマだけ差がはね上がる（とび）
#if os(macOS)
import Foundation
import Metal
import CoreGraphics
import ImageIO

extension OrigamiRenderer {
    static func smoothTest() {
        guard let d = MTLCreateSystemDefaultDevice() else { return }
        let st = OrigamiState()
        guard let r4 = OrigamiRenderer(n: 4, state: st, device: d) else { return }
        let w = 600, h = 560
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false); td.usage = [.renderTarget, .shaderRead]; td.storageMode = .managed
        let t = d.makeTexture(descriptor: td)!
        func frame() -> [UInt8] {
            let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = t; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
            let cb = r4.queue.makeCommandBuffer()!; r4.encode(cb, rpd, w, h, now: 12.3, dt: 0.3)
            let bl = cb.makeBlitCommandEncoder()!; bl.synchronize(resource: t); bl.endEncoding()
            cb.commit(); cb.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: w * h * 4)
            t.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            return px
        }
        let sweeps: [(String, (OrigamiState, Double) -> Void)] = [
            ("X-W を回す", { $0.ax = $1 * 3.2; $0.ay = 0.5 }),
            ("Y-W と 3D を回す", { $0.ay = $1 * 3.2; $0.ax = 0.3; $0.xz = 0.55 + $1 * 1.5 }),
            ("Z-W を回す", { $0.zw = $1 * 3.2; $0.ax = 0.4; $0.ay = 0.2 }),
        ]
        for (name, f) in sweeps {
            st.reset(); st.progress = 1; st.spaceMode = 2; st.raster = true; st.xz = 0.55; st.yz = -0.4
            // 確かめ：SMOOTH_OFF に名前（カンマ区切り）で、その効果を切る
            let off = Set((ProcessInfo.processInfo.environment["SMOOTH_OFF"] ?? "").split(separator: ",").map(String.init))
            if off.contains("glass") { st.glass4 = 0 }; if off.contains("mul") { st.mul4 = 0 }; if off.contains("squash") { st.squash4 = 0 }; if off.contains("slant") { st.slant3 = 0 }
            if off.contains("line") { st.line4 = 0 }; if off.contains("glow") { st.glow4 = 0 }; if off.contains("refl") { st.reflSelf = 0 }; if off.contains("depth") { st.depth3 = 0 }
            if off.contains("net") { st.netMul = 0 }
            f(st, 0); st.updateMats(); for _ in 0..<4 { _ = frame() }
            var prev = frame(), diffs: [Double] = []
            let N = 240
            for i in 1...N {
                f(st, Double(i) / Double(N)); st.updateMats()
                let cur = frame()
                var s = 0
                for k in stride(from: 0, to: cur.count, by: 4) { s += abs(Int(cur[k]) - Int(prev[k])) + abs(Int(cur[k + 1]) - Int(prev[k + 1])) + abs(Int(cur[k + 2]) - Int(prev[k + 2])) }
                diffs.append(Double(s) / Double(w * h))
                prev = cur
            }
            // とび：となり 4 コマの真ん中の値（中央値）の何倍か。なめらかなら 1 に近い
            var jumps: [Double] = []
            for i in diffs.indices {
                let nb = (max(0, i - 4)...min(diffs.count - 1, i + 4)).filter { $0 != i }.map { diffs[$0] }.sorted()
                jumps.append(diffs[i] / max(nb[nb.count / 2], 0.05))
            }
            let big = jumps.filter { $0 > 1.6 }.count
            print(String(format: "なめらかさ（%@）：差の平均 %.2f・いちばん大きなとび ×%.2f・×1.6 をこえたコマ %d / %d", name, diffs.reduce(0, +) / Double(diffs.count), jumps.max() ?? 0, big, N))
            // SMOOTH_DUMP（出力先）：いちばん大きなとびの前後 2 コマと、差の絵（明るいほど変わった所）を書き出す
            if let dir = ProcessInfo.processInfo.environment["SMOOTH_DUMP"], let im = jumps.indices.max(by: { jumps[$0] < jumps[$1] }) {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                f(st, Double(im) / Double(N)); st.updateMats(); let a = frame()
                f(st, Double(im + 1) / Double(N)); st.updateMats(); let b = frame()
                var df = [UInt8](repeating: 255, count: a.count)
                for k in stride(from: 0, to: a.count, by: 4) { for c in 0..<3 { df[k + c] = UInt8(min(255, abs(Int(a[k + c]) - Int(b[k + c])) * 6)) } }
                for (tag, px) in [("前", a), ("後", b), ("差", df)] { writePNG(px, w, h, dir + "/" + name + "_" + String(im) + "_" + tag + ".png") }
                print("  とびのコマ：\(im)（\(String(format: "%.3f", Double(im + 1) / Double(N) * 3.2)) ラジアンのあたり）・とびの大きい順 " + jumps.indices.sorted { jumps[$0] > jumps[$1] }.prefix(6).map { "\($0)" }.joined(separator: ","))
            }
        }
    }
}
func writePNG(_ px: [UInt8], _ w: Int, _ h: Int, _ path: String) {
    var p = px
    guard let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), let img = ctx.makeImage(),
          let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
#endif
