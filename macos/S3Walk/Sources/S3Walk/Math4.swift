// 4 次元の計算：歩く人の体の枠と、大円に沿って進む（ウェブ版 s3walk.html の moveAlong・orthoFrame・lookFrame・viewFrame と同じ）
import Foundation
import simd

typealias V4 = SIMD4<Double>

@inline(__always) func dot4(_ a: V4, _ b: V4) -> Double { simd_dot(a, b) }
@inline(__always) func nrm(_ a: V4) -> V4 { simd_normalize(a) }
let d2r = Double.pi / 180

/// 歩く人：S³ の点 p と、体の枠（右 r・上 u・前 f）。4 つで 4 次元の正規直交の組
struct Walker {
    var p: V4, r: V4, u: V4, f: V4
    /// 出発点＝アナ極（w の＋、4 次元の北）。体の上は z、前は x
    static let north = Walker(p: [0, 0, 0, 1], r: [0, 1, 0, 0], u: [0, 0, 1, 0], f: [1, 0, 0, 0])
}

/// 点 p を動かした後、体の枠を p に直交・正規直交に直す（誤差がたまらないように）
func orthoFrame(_ X: inout Walker) {
    var r = X.r - X.p * dot4(X.r, X.p); r = nrm(r)
    var u = X.u - X.p * dot4(X.u, X.p); u -= r * dot4(u, r); u = nrm(u)
    var f = X.f - X.p * dot4(X.f, X.p); f -= r * dot4(f, r); f -= u * dot4(f, u); f = nrm(f)
    X.r = r; X.u = u; X.f = f
}

/// 大円に沿って s だけ進む。体の枠は平行移動（進む向き d の成分だけが、進んだ先の d へ回る）
func moveAlong(_ X: inout Walker, _ d: V4, _ s: Double) {
    let c = cos(s), sn = sin(s)
    let d2 = X.p * -sn + d * c                 // 進んだ先での d
    X.p = nrm(X.p * c + d * sn)
    func carry(_ t: V4) -> V4 { let a = dot4(t, d); return nrm(t - d * a + d2 * a) }
    X.r = carry(X.r); X.u = carry(X.u); X.f = carry(X.f)
    orthoFrame(&X)
}

/// 見ている向き L と、その右 R・上 U（どれも p に直交）
struct Look { var L: V4, R: V4, U: V4 }

/// カメラ：歩く人と、進む向き（方位 az・仰角 el）、頭だけの見回し（横 hy・縦 hp）。角度は度
struct Camera {
    var w = Walker.north
    var az = 30.0, el = 0.0      // 既定の方位 30°（0°・90° は経線の真上を歩くことになるため。ウェブ版と同じ）
    var hy = 0.0, hp = 0.0

    /// 進む向きの枠
    func lookFrame() -> Look {
        let ca = cos(az * d2r), sa = sin(az * d2r), ce = cos(el * d2r), se = sin(el * d2r)
        let h = w.f * ca + w.r * sa                 // 水平の前
        return Look(L: h * ce + w.u * se, R: w.f * -sa + w.r * ca, U: h * -se + w.u * ce)
    }
    /// 画面に写す向き：進む向きの枠から、頭だけを横 hy°・縦 hp° 回したもの
    func viewFrame() -> Look {
        let F = lookFrame(); if hy == 0 && hp == 0 { return F }
        let cy = cos(hy * d2r), sy = sin(hy * d2r), cp = cos(hp * d2r), sp = sin(hp * d2r)
        let hL = F.L * cy + F.R * sy, R = F.L * -sy + F.R * cy
        return Look(L: hL * cp + F.U * sp, R: R, U: hL * -sp + F.U * cp)
    }
    /// local＝[右, 上, 前] の割合（進む向きの枠で）。その向きの大円に沿って s 進む
    mutating func walk(_ local: SIMD3<Double>, _ s: Double) {
        let F = lookFrame()
        let d = nrm(F.R * local.x + F.U * local.y + F.L * local.z)
        moveAlong(&w, d, s)
    }
    /// 見回している向きを、進む向きにする（景色はそのまま、見回しを 0 に）
    mutating func headGo() {
        guard hy != 0 || hp != 0 else { return }
        let v = viewFrame().L
        az = atan2(dot4(v, w.r), dot4(v, w.f)) / d2r
        el = asin(max(-1, min(1, dot4(v, w.u)))) / d2r
        hy = 0; hp = 0
    }
    /// 向き v（p に直交）をまっすぐ見る（見回しは 0 に）
    mutating func face(_ v: V4) {
        az = atan2(dot4(v, w.r), dot4(v, w.f)) / d2r
        el = asin(max(-1, min(1, dot4(v, w.u)))) / d2r
        hy = 0; hp = 0
    }
    /// 体の枠を、今の進む向きの枠（前＝進む向き、上＝画面の上）に合わせ直す（方位・仰角は 0 に。景色も進む向きも変わらない）。
    ///   上下を 360° 回す時、真上・真下を越えても左右の回り方が画面どおりのままになるように
    mutating func rebase() { let F = lookFrame(); w.f = F.L; w.r = F.R; w.u = F.U; az = 0; el = 0 }
    /// free：上下も止めずに 360° 回す（宙返りのように。体の上下もいっしょに回る）。false ならウェブ版と同じく ±89° で止める
    mutating func clampAngles(free: Bool = false) {
        func wrap(_ a: Double) -> Double { var x = (a + 180).truncatingRemainder(dividingBy: 360); if x < 0 { x += 360 }; return x - 180 }
        az = wrap(az); hy = wrap(hy)
        if free { el = wrap(el); hp = wrap(hp) } else { el = max(-89, min(89, el)); hp = max(-89, min(89, hp)) }
    }
}

/// 光の道（大円）：γ(t) = cos t·P + sin t·v
@inline(__always) func geo(_ P: V4, _ v: V4, _ t: Double) -> V4 { P * cos(t) + v * sin(t) }

/// 目印の玉：中心（S³ の点）・色・半径（角度）
struct Marker {
    var c: V4
    var col: SIMD3<Float>
    var r: Double
    var label: String
    var pole = false
}

func hexRGB(_ h: UInt32) -> SIMD3<Float> {
    SIMD3(Float((h >> 16) & 255) / 255, Float((h >> 8) & 255) / 255, Float(h & 255) / 255)
}

/// 8 つの極の目印（ウェブ版の FIXED と同じ色・大きさ）。N＝アナ極（w の＋）、S＝カタ極
let FIXED: [Marker] = [
    Marker(c: [0, 0, 0, 1], col: [0.6, 0.95, 1], r: 0.13, label: "N", pole: true),
    Marker(c: [0, 0, 0, -1], col: hexRGB(0xfbbf24), r: 0.13, label: "S", pole: true),
    Marker(c: [1, 0, 0, 0], col: hexRGB(0xfb923c), r: 0.09, label: "東 +x", pole: true),
    Marker(c: [-1, 0, 0, 0], col: hexRGB(0xfacc15), r: 0.09, label: "西 −x", pole: true),
    Marker(c: [0, 1, 0, 0], col: hexRGB(0x4ade80), r: 0.09, label: "北 +y", pole: true),
    Marker(c: [0, -1, 0, 0], col: hexRGB(0x2dd4bf), r: 0.09, label: "南 −y", pole: true),
    Marker(c: [0, 0, 1, 0], col: hexRGB(0x60a5fa), r: 0.09, label: "天 +z", pole: true),
    Marker(c: [0, 0, -1, 0], col: hexRGB(0xf472b6), r: 0.09, label: "地 −z", pole: true),
]

// ---- S² の仲間（ウェブ版の W2）：同じ操作を、ふつうの球面 S² の上でした場合。上下（仰角）は S² には無い ----
typealias V3 = SIMD3<Double>
struct Walker2 {
    var p: V3, r: V3, f: V3
    static let north = Walker2(p: [0, 0, 1], r: [0, 1, 0], f: [1, 0, 0])
}
func moveAlong2(_ X: inout Walker2, _ d: V3, _ s: Double) {
    let c = cos(s), sn = sin(s)
    let d2 = X.p * -sn + d * c
    X.p = simd_normalize(X.p * c + d * sn)
    func carry(_ t: V3) -> V3 { let a = simd_dot(t, d); return simd_normalize(t - d * a + d2 * a) }
    var r = carry(X.r), f = carry(X.f)
    r = simd_normalize(r - X.p * simd_dot(r, X.p)); f = f - X.p * simd_dot(f, X.p); f = simd_normalize(f - r * simd_dot(f, r))
    X.r = r; X.f = f
}

// 前のコマと同じかを比べる（動いていない時は描き直さない。Renderer の FrameSig）
extension Camera: Equatable {}
extension Walker: Equatable {}
extension Walker2: Equatable {}
extension Marker: Equatable {}
