// 景色のすみの小さな地図（Mac 版・iPad・iPhone 版の両方）：S³ の地図を景色の 4 すみのどこかに小さく重ねる。
//   見出しの 4 つのます（田の字）を押すと、そのすみへ。−・＋ で大きさ（景色の短い辺の 18〜60%）。大きさとすみは設定に保存（mapCorner・mapMini）
import SwiftUI

struct CornerMap<Map: View>: View {
    @Binding var corner: Int                  // 0 左上・1 右上・2 右下・3 左下
    @Binding var size: Double                 // 景色の短い辺に対する割合
    var home: () -> Void                      // 地図を元の向きに
    var dock: () -> Void                      // 景色の横に並べる
    @ViewBuilder var map: Map

    static func alignment(_ c: Int) -> Alignment { [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading][max(0, min(3, c))] }

    var body: some View {
        GeometryReader { geo in
            let side = max(150, min(geo.size.width, geo.size.height) * size)
            VStack(spacing: 0) {
                header
                map.frame(width: side, height: side)
            }
            .frame(width: side)                                  // 見出しも地図の幅に（Spacer で横いっぱいに広がらないように）
            .background(Space.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Space.line))
            .shadow(color: .black.opacity(0.5), radius: 8)
            .padding(10)
            .frame(width: geo.size.width, height: geo.size.height, alignment: CornerMap.alignment(corner))
            .animation(.easeOut(duration: 0.2), value: corner)
        }
    }

    var header: some View {
        HStack(spacing: 6) {
            Text("S³ の地図").font(.system(size: 11, weight: .bold)).foregroundStyle(Space.lilac).lineLimit(1)
            Spacer(minLength: 4)
            // 4 すみ：押したますのすみへ（今いるすみは空色）
            VStack(spacing: 2) {
                HStack(spacing: 2) { cell(0); cell(1) }
                HStack(spacing: 2) { cell(3); cell(2) }
            }
            .help("押したすみへ地図を動かす")
            iconButton("minus.magnifyingglass", "地図を小さく") { size = max(0.18, size / 1.15) }
            iconButton("plus.magnifyingglass", "地図を大きく") { size = min(0.6, size * 1.15) }
            iconButton("scope", "地図を元の向きに") { home() }
            iconButton("rectangle.split.2x1", "地図を景色の横に並べる") { dock() }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Space.panel.opacity(0.95))
    }
    func cell(_ c: Int) -> some View {
        Button { corner = c } label: {
            RoundedRectangle(cornerRadius: 2).fill(c == corner ? Space.sky : Space.chip)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Space.line))
                .frame(width: 11, height: 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    func iconButton(_ icon: String, _ tip: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Space.slate).frame(width: 20, height: 18).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(tip)
    }
}

/// 地図の明るさのボタン（太陽）：押すと、殻の線の明るさのスライダーが出る（設定の「殻の線の明るさ」と同じ値）
struct MapBrightButton: View {
    @ObservedObject var model: AppModel
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: { Image(systemName: "sun.max") }
            .help("地図の明るさ（殻の線の明るさ）")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("地図の明るさ").font(.caption.bold())
                        Spacer()
                        Text(String(format: "×%.2f", model.r.set.mapBright)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "sun.min").font(.caption).foregroundStyle(.secondary)
                        Slider(value: model.b(\.mapBright), in: 0.2...2)
                        Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("元に戻す（×1）") { model.r.set.mapBright = 1; model.changed() }.controlSize(.small)
                }
                .padding(12).frame(width: 240)
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }
    }
}
