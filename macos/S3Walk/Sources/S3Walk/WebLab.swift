// ウェブ版の数学アプリを、アプリの中の枠で開く（WKWebView）。サイトの一覧（index.html）に載っているもの全部と、超球の β 版。
//   ファイルはアプリの中の Web/ に入れてある（three.js・lucide・Tailwind も Web/vendor に。オフラインでも開ける）。元のファイルから作るのは tools/sync_web.py
//   Mac 版は別の窓（景色の横に並べられる。窓の場所は覚えておく）、iPad・iPhone 版は下から出るシート（半分の高さにすると景色と一緒に見られる）
import SwiftUI
import WebKit

enum WebLab {
    /// アプリに入っているウェブ版のページ（作っている時はソースの横の Web/ から）
    static func url(_ name: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Web") { return u }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Web/\(name).html")
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }
    static let hypersphereTitle = "超球（2 次元とのアナロジー）"
    /// ウェブ版の数学アプリ（サイトの一覧と同じ並び・まとまり）。id はファイルの名前
    struct App: Identifiable, Hashable { let id: String; let title: String; let group: String }
    static let apps: [App] = [
        App(id: "index", title: "一覧（高次元ビジュアルコレクション）", group: "入口"),
        App(id: "polygon", title: "n/m 角形エクスプローラー", group: "多角形"),
        App(id: "graph", title: "グラフ電卓", group: "関数とグラフ"), App(id: "vec3d", title: "空間ベクトル 3D", group: "関数とグラフ"),
        App(id: "euler", title: "オイラーの等式", group: "関数とグラフ"), App(id: "graph4d", title: "複素グラフ 4D", group: "関数とグラフ"),
        App(id: "hypercube", title: "超立方体（次元おりがみ）", group: "立方体の仲間"), App(id: "hypercube6d", title: "6 次元立方体（ヘキセラクト）", group: "立方体の仲間"),
        App(id: "ndim", title: "n 次元ビューア", group: "立方体の仲間"),
        App(id: "hypersphere", title: "3D / 4D 超球", group: "球の仲間"), App(id: "hypersphere_beta", title: "3D / 4D 超球 β（UI を整理した版）", group: "球の仲間"),
        App(id: "s3walk", title: "球面さんぽ（ウェブ版）", group: "球の仲間"), App(id: "hypersphere5d_ui", title: "5D 超球（S⁴）", group: "球の仲間"),
        App(id: "hypersphere5d_bubbles", title: "5 次元球とシャボン玉", group: "球の仲間"),
        App(id: "thurston", title: "空間めぐり（サーストンの 8 つの幾何）", group: "空間の仲間"),
        App(id: "buffon", title: "ビュフォンの針", group: "確率と実験"), App(id: "monty", title: "モンティ・ホール問題", group: "確率と実験"),
    ]
    static var groups: [String] { apps.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } } }
    /// ウェブの画面を作る（同じページの設定＝localStorage は、アプリの中で覚えておく）
    static func makeView(_ name: String) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        let v = WKWebView(frame: .zero, configuration: c)
        if #available(macOS 13.3, iOS 16.4, *) { v.isInspectable = true }   // Safari の開発メニューから中を見られるように
        #if os(macOS)
        v.setValue(false, forKey: "drawsBackground")                         // 読み込む間に白く光らない
        #else
        v.isOpaque = false; v.backgroundColor = .black; v.scrollView.backgroundColor = .black
        v.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        if let u = url(name) { v.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent()) }
        else { v.loadHTMLString("<body style='background:#030712;color:#e5e7eb;font:15px system-ui;padding:24px'>ページが見つからない：Web/\(name).html</body>", baseURL: nil) }
        return v
    }
}

#if os(macOS)
/// Mac：ウェブ版のページを別の窓で開く（もう開いていれば前に出す）
final class WebLabWindows {
    static let shared = WebLabWindows()
    private var windows: [String: NSWindow] = [:]
    func open(_ name: String, title: String) {
        if let w = windows[name] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        w.collectionBehavior = [.fullScreenPrimary, .managed]
        w.contentView = WebLab.makeView(name)
        w.setFrameAutosaveName("S3WalkWeb." + name)                         // 窓の場所と大きさを覚えておく
        if !w.setFrameUsingName("S3WalkWeb." + name) { w.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in self?.windows[name] = nil }
        windows[name] = w
        w.makeKeyAndOrderFront(nil)
    }
}
#else
/// iPad・iPhone：ウェブ版の数学アプリの一覧（シート）。選ぶと、その中でページを開く（左上の ＜ で一覧に戻る）
struct WebLabList: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(WebLab.groups, id: \.self) { g in
                    Section(g) {
                        ForEach(WebLab.apps.filter { $0.group == g }) { a in
                            NavigationLink(a.title) { WebPageView(name: a.id).ignoresSafeArea(edges: .bottom).navigationTitle(a.title).navigationBarTitleDisplayMode(.inline) }
                        }
                    }
                }
            }
            .navigationTitle("数学アプリ（ウェブ版）")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
/// iPad・iPhone：シートの中身（上に名前と閉じるボタン、下にページ）
struct WebLabSheet: View {
    let name: String, title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            WebPageView(name: name).ignoresSafeArea(edges: .bottom)
        }
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
    }
}
struct WebPageView: UIViewRepresentable {
    let name: String
    func makeUIView(context: Context) -> WKWebView { WebLab.makeView(name) }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
#endif
