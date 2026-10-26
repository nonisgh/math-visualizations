// 宇宙の着せ替え（ウェブ版の見た目に合わせる）：深い紺のガラスのパネル（rgba(15,23,42,0.93)・白 12% のふち）、
//   見出しはすみれ色、スライダーなどは空色（#38bdf8）、オン・オフはウェブ版のボタンのような丸い札、パネルの後ろに星と淡い星雲
import SwiftUI

enum Space {
    static let bg = Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255)            // #030712
    static let panel = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)       // #0f172a
    static let edge = Color.white.opacity(0.12)
    static let sky = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)       // #38bdf8
    static let violet = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255)   // #a78bfa
    static let lilac = Color(red: 196 / 255, green: 181 / 255, blue: 253 / 255)    // #c4b5fd（見出し）
    static let amber = Color(red: 253 / 255, green: 230 / 255, blue: 138 / 255)    // #fde68a（HUD の数字）
    static let slate = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)    // #94a3b8（説明）
    static let line = Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255)       // #334155
    static let chip = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)       // #1e293b
}

/// パネルの後ろの宇宙：決まった並びの星（小さい点、ときどき明るい星）と、すみれ色・空色の淡い星雲
struct SpaceBackground: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Space.bg))
            let g1 = Gradient(colors: [Space.violet.opacity(0.16), .clear]), g2 = Gradient(colors: [Space.sky.opacity(0.10), .clear])
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(g1, center: CGPoint(x: size.width * 0.2, y: size.height * 0.18), startRadius: 0, endRadius: max(size.width, 260) * 0.9))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(g2, center: CGPoint(x: size.width * 0.9, y: size.height * 0.72), startRadius: 0, endRadius: max(size.width, 260) * 0.8))
            var x: UInt64 = 0x2545F4914F6CDD1D
            func rnd() -> CGFloat { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return CGFloat(x % 100_000) / 100_000 }
            let n = Int(size.width * size.height / 900)
            for _ in 0..<min(n, 2400) {
                let p = CGPoint(x: rnd() * size.width, y: rnd() * size.height), b = rnd(), r = b > 0.97 ? 1.3 : b > 0.85 ? 0.9 : 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.18 + 0.6 * Double(b * b))))
            }
        }
        .ignoresSafeArea()
    }
}

/// オン・オフ：ウェブ版の .btn のような丸い札（オンはすみれ色に光る）。左に小さなつまみ
struct SpaceToggleStyle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Capsule().fill(c.isOn ? Space.violet : Space.chip).frame(width: 24, height: 13)
                    .overlay(Circle().fill(.white.opacity(c.isOn ? 0.95 : 0.55)).frame(width: 9, height: 9).offset(x: c.isOn ? 5.5 : -5.5))
                    .overlay(Capsule().stroke(c.isOn ? Space.violet : Space.line, lineWidth: 1))
                    .shadow(color: c.isOn ? Space.violet.opacity(0.6) : .clear, radius: 4)
                c.label.foregroundStyle(c.isOn ? Color.white : Color.white.opacity(0.78))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// パネル 1 枚の見た目（ガラスの紺・白 12% のふち・うっすら光る上の縁）
struct SpaceCard: ViewModifier {
    var lit = false
    func body(content: Content) -> some View {
        content
            .background(Space.panel.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(lit ? Space.violet.opacity(0.7) : Space.edge, lineWidth: 1))
            .overlay(alignment: .top) { LinearGradient(colors: [Space.violet.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1).padding(.horizontal, 10) }
    }
}
extension View {
    func spaceCard(lit: Bool = false) -> some View { modifier(SpaceCard(lit: lit)) }
    /// パネルの中身の色づけ（スライダーなどは空色、オン・オフは丸い札）
    func spaceControls() -> some View { self.tint(Space.sky).toggleStyle(SpaceToggleStyle()) }
}
