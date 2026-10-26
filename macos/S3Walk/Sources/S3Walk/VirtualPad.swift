// 画面のゲームパッド：コントローラー（Switch の Pro コントローラーの並び）と同じスティックとボタンを、景色の真ん中に出す。押すとコントローラーと同じ働き。
//   本体（すき間）をドラッグで動かせる。L・R・ZL・ZR・L3 は 2 回続けて押すと押したまま（黄色の枠。もう一度押すと離す）：マウスでも「ZL を押しながら右スティック」ができる。
//   Mac 版と iPad・iPhone 版の両方で使う（GameInput の vLeft・vRight・vPress へ入れる）
import SwiftUI
import QuartzCore

struct VirtualPad: View {
    let game: GameInput
    var close: () -> Void
    @State private var offset = CGSize.zero
    @State private var dragStart: CGSize? = nil
    @State private var held: Set<String> = []            // 指・マウスで押している（見た目）
    @State private var locked: Set<String> = []          // 2 回押しで押したまま
    @State private var lastPress: [String: Double] = [:]
    @State private var lk = CGSize.zero
    @State private var rk = CGSize.zero
    static let latchable: Set<String> = ["L", "R", "ZL", "ZR", "L3"]
    let R: CGFloat = 40                                     // スティックの半径

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                key("ZL", "ZL", "見回しだけ", w: 54, h: 26)
                key("L", "L", "下へ", w: 54, h: 26)
                Spacer(minLength: 12)
                key("options", "−", "地図", w: 30, h: 26)
                Image(systemName: "line.3.horizontal").foregroundStyle(Space.slate).frame(width: 34, height: 26).help("ここをドラッグで動かす")
                key("menu", "＋", "設定", w: 30, h: 26)
                Spacer(minLength: 12)
                key("R", "R", "上へ", w: 54, h: 26)
                key("ZR", "ZR", "速く", w: 54, h: 26)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    stick(left: true)
                    HStack(spacing: 6) { key("L3", "L3", "跡を消す", w: 38, h: 24) }
                }
                dpad.padding(.top, 70)
                Spacer(minLength: 10)
                VStack(spacing: 8) {
                    abxy
                }
                VStack(spacing: 8) {
                    stick(left: false).padding(.top, 70)
                    key("R3", "R3", "前を見る", w: 38, h: 24)
                }
            }
            Text("L・R・ZL・ZR・L3 は 2 回押すと押したまま（黄色の枠、もう一度で離す）").font(.system(size: 9)).foregroundStyle(Space.slate)
        }
        .padding(12)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 28).fill(Space.panel.opacity(0.62)))
        .background(RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial).opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Space.line))
        .overlay(alignment: .topTrailing) {
            Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Space.slate) }
                .buttonStyle(.plain).offset(x: 6, y: -6).help("画面のゲームパッドを隠す")
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .gesture(DragGesture(minimumDistance: 2).onChanged { g in     // 本体のすき間をドラッグで動かす
            if dragStart == nil { dragStart = offset }
            offset = CGSize(width: dragStart!.width + g.translation.width, height: dragStart!.height + g.translation.height)
        }.onEnded { _ in dragStart = nil })
        .offset(offset)
        .onDisappear { game.vClear() }
    }

    // ---- 十字（上下：殻の見える距離・速さ、右：ターボ）----
    var dpad: some View {
        VStack(spacing: 2) {
            key("up", "▲", nil, w: 32, h: 30, round: false)
            HStack(spacing: 2) {
                key("left", "◀", nil, w: 32, h: 30, round: false)
                Color.clear.frame(width: 30, height: 30)
                key("right", "▶", nil, w: 32, h: 30, round: false)
            }
            key("down", "▼", nil, w: 32, h: 30, round: false)
            Text("↑↓ 殻の距離・速さ　→ ターボ").font(.system(size: 9)).foregroundStyle(Space.slate).fixedSize()
        }
    }
    // ---- A・B・X・Y（任天堂の並び：上 X・左 Y・右 A・下 B）----
    var abxy: some View {
        VStack(spacing: 0) {
            key("X", "X", "縦横無尽", w: 40, h: 40)
            HStack(spacing: 34) {
                key("Y", "Y", "前を見る", w: 40, h: 40)
                key("A", "A", "ターボ", w: 40, h: 40)
            }
            key("B", "B", "歩き続ける", w: 40, h: 40)
        }
    }

    // ---- スティック：丸の中をドラッグ（はしまで倒すと 1）----
    func stick(left: Bool) -> some View {
        let knob = left ? lk : rk
        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(Space.chip.opacity(0.85)).overlay(Circle().stroke(Space.line))
                Circle().fill((knob == .zero ? Space.sky.opacity(0.7) : Space.sky)).frame(width: 40, height: 40).offset(knob)
            }
            .frame(width: R * 2, height: R * 2)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                var d = g.translation; let l = hypot(d.width, d.height)
                if l > R { d = CGSize(width: d.width / l * R, height: d.height / l * R) }
                let v = SIMD2(Double(d.width / R), Double(-d.height / R))
                if left { lk = d; game.vLeft = v } else { rk = d; game.vRight = v }
            }.onEnded { _ in
                if left { lk = .zero; game.vLeft = .zero } else { rk = .zero; game.vRight = .zero }
            })
            Text(left ? "左スティック 歩く" : "右スティック 向き").font(.system(size: 9)).foregroundStyle(Space.slate).fixedSize()
        }
    }

    // ---- ボタン：押している間だけ（2 回押しで押したままになるものも）----
    func key(_ k: String, _ label: String, _ cap: String?, w: CGFloat, h: CGFloat, round: Bool = true) -> some View {
        let on = held.contains(k) || locked.contains(k), lock = locked.contains(k)
        let shape = RoundedRectangle(cornerRadius: round ? h / 2 : 6)
        return VStack(spacing: 2) {
            Text(label).font(.system(size: h > 30 ? 16 : 12, weight: .bold)).frame(width: w, height: h)
                .foregroundStyle(on ? Space.bg : .white)
                .background(on ? Space.sky : Space.chip.opacity(0.92), in: shape)
                .overlay(shape.stroke(lock ? Space.amber : Space.line, lineWidth: lock ? 2 : 1))
                .contentShape(shape)
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !held.contains(k) { press(k) } }.onEnded { _ in release(k) })
            if let cap { Text(cap).font(.system(size: 9)).foregroundStyle(Space.slate).fixedSize() }
        }
    }
    func press(_ k: String) {
        held.insert(k)
        let now = CACurrentMediaTime()
        if VirtualPad.latchable.contains(k) {
            if locked.contains(k) { locked.remove(k); game.vPress(k, false); lastPress[k] = 0; return }   // 押したままを離す
            if now - (lastPress[k] ?? 0) < 0.35 { locked.insert(k) }
            lastPress[k] = now
        }
        game.vPress(k, true)
    }
    func release(_ k: String) {
        held.remove(k)
        if !locked.contains(k) && game.vHeld.contains(k) { game.vPress(k, false) }
    }
}
