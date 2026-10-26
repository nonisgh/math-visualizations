// 絵の目印の表（ウェブ版の ATLAS）：8×8 のます目（1 ます 128 点）に絵文字を描き、右上に赤い点（上下・左右の向きが分かるように）
import Foundation
import CoreText
import Metal
import MetalKit

enum PIC {
    static let N = "⛄", S = "🌴", px = "🐰", nx = "🐢", py = "🦝", ny = "🐸", pz = "🐱", nz = "🐶", selfPic = "🙂", foot = "👣"
    static let marks = ["🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐭", "🐵", "🐧", "🦉", "🦄", "🐝", "🦋", "🐙", "🐬", "🐳", "🍎", "🍓", "🍉", "⚽", "🎸", "🚀", "⭐", "🍩", "🧸", "🎲"]
    /// 8 つの極の絵（FIXED と同じ順）
    static let poles = [N, S, px, nx, py, ny, pz, nz]
    static let list = poles + [selfPic, foot] + marks
    static func index(_ ch: String) -> Int { list.firstIndex(of: ch) ?? -1 }
    static func mark(_ i: Int) -> String { marks[i % marks.count] }
}

enum Atlas {
    static let n = 8, cell = 128
    /// 絵文字を、色のついた所の外わくの真ん中が (cx, cy) に来るように描く（ウェブ版の fillCentered。字体ごとのずれをなくす）
    static func drawCentered(_ ctx: CGContext, _ ch: String, _ cx: CGFloat, _ cy: CGFloat) {
        // Core Text で描く（Mac と iPad・iPhone で同じ）
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 96, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: ch, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let lb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        // いったん別の紙に描いて外わくを数える
        let W = 192
        var buf = [UInt8](repeating: 0, count: W * W * 4)
        let g = CGContext(data: &buf, width: W, height: W, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        g.textPosition = CGPoint(x: (CGFloat(W) - lb.width) / 2 - lb.minX, y: (CGFloat(W) - lb.height) / 2 - lb.minY)
        CTLineDraw(line, g)
        var x0 = W, y0 = W, x1 = -1, y1 = -1
        for y in 0..<W { for x in 0..<W where buf[(y * W + x) * 4 + 3] > 16 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        guard x1 >= 0, let img = g.makeImage() else { return }
        // buf の行 0 は上。外わくの真ん中（上から mx, my）を (cx, cy)（上から）へ
        let mx = CGFloat(x0 + x1 + 1) / 2, my = CGFloat(y0 + y1 + 1) / 2
        ctx.saveGState()
        ctx.translateBy(x: cx - mx, y: cy - my + CGFloat(W)); ctx.scaleBy(x: 1, y: -1)   // ctx は上から下の向きにしてある
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: W))
        ctx.restoreGState()
    }
    /// 表を作って Metal のテクスチャに（行 0 が上。ミップマップつき）
    static func make(_ device: MTLDevice) -> MTLTexture? {
        let S = n * cell
        var px = [UInt8](repeating: 0, count: S * S * 4)
        guard let ctx = CGContext(data: &px, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(S)); ctx.scaleBy(x: 1, y: -1)                      // 上から下へ（行 0 が上）
        for (i, ch) in PIC.list.enumerated() {
            let x0 = CGFloat((i % n) * cell), y0 = CGFloat((i / n) * cell), C = CGFloat(cell)
            drawCentered(ctx, ch, x0 + C / 2, y0 + C / 2)
            // 右上に赤い点（玉の表面に写る範囲の内側）
            let r: CGFloat = 10, c = CGPoint(x: x0 + 0.74 * C, y: y0 + 0.26 * C)
            ctx.setFillColor(CGColor(srgbRed: 0xef / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        // 色は「かけ合わせ前」に戻す（シェーダーは mix(下地, 絵, a) で使う）
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]); if a > 0 && a < 255 { for k in 0..<3 { px[i + k] = UInt8(min(255, Double(px[i + k]) * 255 / a)) } }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: S, height: S, mipmapped: true)
        d.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, S, S), mipmapLevel: 0, withBytes: px, bytesPerRow: S * 4)
        if let q = device.makeCommandQueue(), let cb = q.makeCommandBuffer(), let bl = cb.makeBlitCommandEncoder() {
            bl.generateMipmaps(for: tex); bl.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
        return tex
    }
}
