// 超球面拡張（試作）：超球の中身は、半径のちがう S³ の重なり。決まった半径の S³ をステージにして、ブラックホールから下のステージへ行く。
//   第 1 段階は外から見る絵だけ：右の超球の中にステージの S³ をうっすら重ね、各ステージのブラックホール（入口）・下のステージへの穴・出口（ホワイトホール）を描く
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabState {
    /// ステージの半径（外から順に。最後の 0.2 のブラックホールは中心へ）
    static let stageR: [Double] = [1, 0.8, 0.6, 0.4, 0.2]
    /// 各ステージのブラックホールの向き（単位の 4D の向き。半径 stageR[k] の S³ の上の点は stageR[k] 倍）。
    ///   入ると同じ向きのまま、1 つ下のステージへ落ちる（出口は stageR[k + 1] 倍の点）。ふだんの見る向きで見えるよう、どれもアナ極（+w）寄り
    static let blackHoles: [SIMD4<Double>] = [
        simd_normalize(SIMD4(0.55, 0.30, -0.35, 0.69)), simd_normalize(SIMD4(-0.60, 0.25, 0.45, 0.62)), simd_normalize(SIMD4(0.20, -0.70, 0.40, 0.55)),
        simd_normalize(SIMD4(-0.30, -0.35, -0.65, 0.60)), simd_normalize(SIMD4(0.45, 0.55, 0.50, 0.50))]
    /// 描く S³（半径・濃さ）：光らせるステージはふつうの濃さ、ほかはうっすら（ほかのステージを消す時は、光らせるステージだけ）
    func expandShells() -> [(r: Double, k: Float)] {
        if stageOnly { return [(Self.stageR[stageView], 1)] }
        return Self.stageR.enumerated().map { i, r in (r, i == stageView ? 1 : 0.3) }
    }
}

extension HyperLabRenderer {
    /// ブラックホール（黒い玉と光の輪）・下のステージへの穴（紫の光の線）・出口（白い輪）。奥の側にあるものは薄く
    func drawExpand(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        let (eye, Rv, Uv, _) = camBasis(), R3 = Self.R * Self.SCALE
        var tri: [HLVert] = []
        func v(_ p: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: c) }
        func ring(_ c: SIMD3<Double>, _ r0: Double, _ r1: Double, _ c0: SIMD4<Float>, _ c1: SIMD4<Float>) {
            let n = 40
            for i in 0..<n {
                let a0 = Double(i) / Double(n) * 2 * .pi, a1 = Double(i + 1) / Double(n) * 2 * .pi
                let d0 = Rv * cos(a0) + Uv * sin(a0), d1 = Rv * cos(a1) + Uv * sin(a1)
                tri += [v(c + d0 * r0, c0), v(c + d1 * r0, c0), v(c + d1 * r1, c1), v(c + d0 * r0, c0), v(c + d1 * r1, c1), v(c + d0 * r1, c1)]
            }
        }
        func line(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ w: Double, _ ca: SIMD4<Float>, _ cb: SIMD4<Float>) {
            var s = simd_cross(b - a, eye - a); let l = simd_length(s)
            guard l > 1e-9 else { return }
            s *= w / l
            tri += [v(a - s, ca), v(b - s, cb), v(b + s, cb), v(a - s, ca), v(b + s, cb), v(a + s, ca)]
        }
        let B = HyperLabState.blackHoles, Rs = HyperLabState.stageR
        for k in B.indices where !st.stageOnly || k == st.stageView {
            let r0 = Rs[k], r1 = k + 1 < Rs.count ? Rs[k + 1] : 0
            let (p0, f0) = walkPlace(B[k] * r0), (p1, f1) = walkPlace(B[k] * r1)
            let on: Float = k == st.stageView ? 1 : 0.55, a0 = on * Float(0.35 + 0.65 * f0), a1 = on * Float(0.35 + 0.65 * f1)
            let s = R3 * 0.04 * (0.55 + 0.45 * r0)
            line(p0, p1, R3 * 0.004, SIMD4(0.75, 0.45, 1.0, 0.9 * a0), SIMD4(0.75, 0.45, 1.0, 0.9 * a1))              // 下のステージへの穴
            ring(p0, s * 1.05, s * 2.0, SIMD4(1.0, 0.62, 0.22, 0.95 * a0), SIMD4(1.0, 0.35, 0.1, 0))              // 降着円盤（外へ消える光の輪）
            ring(p0, 0, s * 1.05, SIMD4(0, 0, 0, 0.97 * max(0.5, a0)), SIMD4(0.02, 0.0, 0.04, 0.97 * max(0.5, a0)))   // 黒い玉
            if r1 > 0 { ring(p1, s * 0.55, s * 0.8, SIMD4(1, 1, 1, 0.85 * a1), SIMD4(0.8, 0.9, 1, 0.85 * a1)) }   // 出口（ホワイトホール）
        }
        ring(walkPlace(.zero).0, 0, R3 * 0.012, SIMD4(1, 1, 1, 0.9), SIMD4(0.8, 0.7, 1, 0.9))                     // 中心（特異点）
        drawAxisTris(e, u0, tri, depthTest: false, flat: true)
    }
}
