// 次元おりがみ：Google でログインして、設定を Firebase（プロジェクト nonis-apps）でそろえる（Mac・iPad・iPhone）
//   Firebase の SDK は入れず、インターネットで直接やりとりする（ビルドを速いままに）：
//   ① Google のログイン（ブラウザの小さな窓。PKCE つき。iOS の種類のクライアントなので秘密の鍵は無い）
//   ② その ID トークンで Firebase にログイン（Identity Toolkit）→ 自分の番号（uid）はウェブのアプリと同じ
//   ③ Firestore の apps/origami/users/{uid}/settings/state に、設定・プリセット・ショートカットをまとめて 1 つの文書で
//   守りは Firestore の決まり（apps/{アプリ}/users/{本人}/** は本人だけ）。API キーとクライアント ID は公開の識別子で、秘密ではない
import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum CloudConf {
    static let apiKey = "AIzaSyDEH-m5Wx31Azw3aHAO3-IEK6NyAGpP9_k"
    static let project = "nonis-apps", app = "origami"
    #if os(macOS)
    static let clientID = "331956814281-vbm56g75e0shbv16drnostr9d78j21ui.apps.googleusercontent.com"
    static let device = "Mac"
    #else
    static let clientID = "331956814281-3dcqckjj13n60dkbor0gfe4t3l37nle5.apps.googleusercontent.com"
    static var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    #endif
    /// 戻り先：クライアント ID を逆さにした名前（Google の iOS の決まり）
    static var scheme: String { "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "") }
    static var redirect: String { scheme + ":/oauth2redirect" }
}

struct CloudErr: LocalizedError { let msg: String; var errorDescription: String? { msg } }

/// ログインの鍵（Firebase のリフレッシュトークン）のしまい場所
///   Mac：~/Library/Application Support/Origami/cloud.json（本人だけ読める 0600）。署名の無いビルドは作り直すたびに、
///        キーチェーンが「使ってよいか」を聞いてくるので（firebase のコマンドと同じく、ファイルにしまう）
///   iPad・iPhone：キーチェーン
enum TokenStore {
    #if os(macOS)
    static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Origami", isDirectory: true).appendingPathComponent("cloud.json")
    }
    static func save(_ d: [String: String]?) {
        guard let u = url else { return }
        guard let d, let data = try? JSONSerialization.data(withJSONObject: d) else { try? FileManager.default.removeItem(at: u); return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: u.path, contents: data, attributes: [.posixPermissions: 0o600])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
    }
    static func load() -> [String: String]? {
        guard let u = url, let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
    #else
    static let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.nonisapps.origami.cloud", kSecAttrAccount as String: "firebase"]
    static func save(_ d: [String: String]?) {
        SecItemDelete(q as CFDictionary)
        guard let d, let data = try? JSONSerialization.data(withJSONObject: d) else { return }
        var a = q; a[kSecValueData as String] = data; a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
    static func load() -> [String: String]? {
        var a = q; a[kSecReturnData as String] = true; a[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(a as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
    #endif
}

/// インターネットのやりとり（JSON か フォームを送って、JSON を受け取る）
enum Net {
    static func form(_ d: [String: String]) -> Data {
        var ok = CharacterSet.alphanumerics; ok.insert(charactersIn: "-._~")
        return d.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: ok) ?? "")" }.joined(separator: "&").data(using: .utf8)!
    }
    /// 送って、(状態の番号, JSON) を返す。allow に無い 400 番台・500 番台は、サーバーの言葉でエラーに
    static func call(_ url: URL, method: String = "POST", json: [String: Any]? = nil, form f: [String: String]? = nil, bearer: String? = nil, allow: Set<Int> = []) async throws -> (Int, [String: Any]) {
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 20
        if let json { r.httpBody = try JSONSerialization.data(withJSONObject: json); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let f { r.httpBody = form(f); r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        if let bearer { r.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code >= 400 && !allow.contains(code) {
            let e = obj["error"]
            let m = (e as? [String: Any])?["message"] as? String ?? (e as? String) ?? (obj["error_description"] as? String) ?? "エラー \(code)"
            throw CloudErr(msg: m)
        }
        return (code, obj)
    }
}

/// Google でログイン → Firebase にログイン。ログインの鍵はしまっておき、開くたびにログインし直さなくてよい
@MainActor final class CloudAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = CloudAuth()
    @Published var uid: String?
    @Published var email: String?
    @Published var busy = false
    @Published var message = ""
    private var refresh: String?, idToken: String?, exp = Date.distantPast
    private var web: ASWebAuthenticationSession?

    override init() {
        super.init()
        if let d = TokenStore.load(), let r = d["refresh"], let u = d["uid"] { refresh = r; uid = u; email = d["email"] }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
            #else
            let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            return ws.first { $0.isKeyWindow } ?? ws.first ?? ASPresentationAnchor()
            #endif
        }
    }

    static func rand(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n); _ = SecRandomCopyBytes(kSecRandomDefault, n, &b); return b64u(Data(b))
    }
    static func b64u(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func signIn() async {
        busy = true; message = ""; defer { busy = false }
        do {
            // ① Google：ブラウザの小さな窓でログイン（PKCE：手順の途中を横取りされても使えないように）
            let verifier = Self.rand(32), state = Self.rand(16)
            let challenge = Self.b64u(Data(SHA256.hash(data: Data(verifier.utf8))))
            var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            c.queryItems = [.init(name: "client_id", value: CloudConf.clientID), .init(name: "redirect_uri", value: CloudConf.redirect),
                            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
                            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                            .init(name: "state", value: state), .init(name: "prompt", value: "select_account")]
            let back: URL = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: CloudConf.scheme) { url, err in
                    if let url { cont.resume(returning: url) } else { cont.resume(throwing: err ?? CloudErr(msg: "ログインできませんでした")) }
                }
                s.presentationContextProvider = self
                s.prefersEphemeralWebBrowserSession = false
                web = s
                if !s.start() { web = nil; cont.resume(throwing: CloudErr(msg: "ログインの窓を開けませんでした")) }
            }
            web = nil
            let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func item(_ n: String) -> String? { items.first { $0.name == n }?.value }
            if let e = item("error") { throw CloudErr(msg: "Google：\(e)") }
            guard item("state") == state, let code = item("code") else { throw CloudErr(msg: "ログインの返事がおかしい（state）") }
            let (_, tok) = try await Net.call(URL(string: "https://oauth2.googleapis.com/token")!, form: [
                "code": code, "client_id": CloudConf.clientID, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": CloudConf.redirect])
            guard let gid = tok["id_token"] as? String else { throw CloudErr(msg: "Google の ID トークンがありません") }
            // ② Firebase：Google の ID トークンでログイン（ウェブのアプリと同じ uid になる）
            let (_, fb) = try await Net.call(URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(CloudConf.apiKey)")!, json: [
                "postBody": "id_token=\(gid)&providerId=google.com", "requestUri": "http://localhost", "returnIdpCredential": true, "returnSecureToken": true])
            guard let t = fb["idToken"] as? String, let r = fb["refreshToken"] as? String, let u = fb["localId"] as? String else { throw CloudErr(msg: "Firebase のログインの返事がおかしい") }
            idToken = t; refresh = r; uid = u; email = fb["email"] as? String
            exp = Date().addingTimeInterval((Double(fb["expiresIn"] as? String ?? "3600") ?? 3600) - 120)
            TokenStore.save(["refresh": r, "uid": u, "email": email ?? ""])
            CloudSync.shared.signedIn()
        } catch {
            web = nil
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { message = "" }
            else { message = "ログインできませんでした：\(error.localizedDescription)" }
        }
    }

    func signOut() {
        refresh = nil; idToken = nil; uid = nil; email = nil; exp = .distantPast
        TokenStore.save(nil); CloudSync.shared.signedOut()
    }

    /// 使える Firebase の ID トークン（1 時間で切れるので、切れていたらリフレッシュトークンで取り直す）
    func token() async throws -> String {
        if let t = idToken, Date() < exp { return t }
        guard let r = refresh else { throw CloudErr(msg: "ログインしていません") }
        do {
            let (_, d) = try await Net.call(URL(string: "https://securetoken.googleapis.com/v1/token?key=\(CloudConf.apiKey)")!, form: ["grant_type": "refresh_token", "refresh_token": r])
            guard let t = d["id_token"] as? String else { throw CloudErr(msg: "トークンを取り直せませんでした") }
            idToken = t; exp = Date().addingTimeInterval((Double(d["expires_in"] as? String ?? "3600") ?? 3600) - 120)
            if let nr = d["refresh_token"] as? String, nr != r { refresh = nr; TokenStore.save(["refresh": nr, "uid": uid ?? "", "email": email ?? ""]) }
            return t
        } catch let e as CloudErr where ["TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "USER_DISABLED", "USER_NOT_FOUND"].contains(where: { e.msg.contains($0) }) {
            signOut(); message = "ログインが切れました。もう一度ログインしてください"; throw e
        }
    }
}

/// 設定を Firestore でそろえる：変えたら 2 秒ほどで上げる・開いた時と 45 秒ごとに見に行き、ほかの機械で変えた分があればもらう
///   1 つの文書 apps/origami/users/{uid}/settings/state：data（設定などを plist の文字で）・updatedAt（ミリ秒）・device
///   新しい方が勝つ（ほかの機械の変更より後に、こちらで変えていたら、こちらを上げる）
@MainActor final class CloudSync: ObservableObject {
    static let shared = CloudSync()
    @Published var lastSync: Date?
    @Published var status = ""
    weak var st: OrigamiState?
    /// そろえる保存（UserDefaults の名前）。設定のほかに、プリセット・基本・往復・ショートカット
    static let keys = [AsmPreset.key, AsmBasic.key, AnglePreset.key, PingPongPreset.key, ShortcutStore.key]
    /// 機械ごとにちがってよい設定（そろえない）：つまんだ倍率・描く細かさ
    static let localOnly = ["zoom", "renderScale"]
    private var baseline: NSDictionary?, dirtyAt: Date?, quietUntil = Date.distantPast, running = false, lastPull = Date.distantPast
    private var timer: Timer?
    private var lastRemoteAt: Double {
        get { UserDefaults.standard.double(forKey: "origami.cloud.lastRemoteAt") }
        set { UserDefaults.standard.set(newValue, forKey: "origami.cloud.lastRemoteAt") }
    }

    func attach(_ s: OrigamiState) {
        st = s
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in Task { @MainActor in CloudSync.shared.tick() } }
        #if os(macOS)
        let note = NSApplication.didBecomeActiveNotification
        #else
        let note = UIApplication.didBecomeActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: note, object: nil, queue: .main) { _ in Task { @MainActor in await CloudSync.shared.sync() } }
        if CloudAuth.shared.uid != nil { Task { await sync() } }
    }
    func signedIn() { lastRemoteAt = 0; baseline = nil; dirtyAt = nil; Task { await sync() } }
    func signedOut() { lastRemoteAt = 0; baseline = nil; dirtyAt = nil; lastSync = nil; status = "" }

    /// 今の手元の中身（そろえる分だけ）
    func payload() -> NSDictionary {
        var d: [String: Any] = [:]
        let ud = UserDefaults.standard
        if var set = ud.dictionary(forKey: OrigamiState.settingsKey) { for k in Self.localOnly { set.removeValue(forKey: k) }; d["settings"] = set }
        for k in Self.keys { if let v = ud.object(forKey: k) { d[k] = v } }
        return d as NSDictionary
    }

    func tick() {
        guard CloudAuth.shared.uid != nil, !running else { return }
        let local = payload()
        if Date() < quietUntil { baseline = local; return }      // もらった直後：手元の保存が落ち着くまで（もらった分を、変えた分と思わないように）
        guard let base = baseline else { return }                 // まだ一度もそろえていない（sync が決める）
        if !local.isEqual(base) && dirtyAt == nil { dirtyAt = Date() }
        if let d = dirtyAt, Date().timeIntervalSince(d) > 2 { Task { await push() } }
        else if Date().timeIntervalSince(lastPull) > 45 { Task { await sync() } }
    }

    private var docURL: URL? {
        guard let u = CloudAuth.shared.uid else { return nil }
        return URL(string: "https://firestore.googleapis.com/v1/projects/\(CloudConf.project)/databases/(default)/documents/apps/\(CloudConf.app)/users/\(u)/settings/state")
    }

    /// 見に行く：ほかの機械の新しい分があればもらい、手元が新しければ上げる
    func sync() async {
        guard !running, let url = docURL else { return }
        running = true; lastPull = Date()
        do {
            let t = try await CloudAuth.shared.token()
            let (code, doc) = try await Net.call(url, method: "GET", bearer: t, allow: [404])
            let f = doc["fields"] as? [String: Any] ?? [:]
            func fv(_ k: String) -> [String: Any]? { f[k] as? [String: Any] }
            let at = (fv("updatedAt")?["doubleValue"] as? Double) ?? Double(fv("updatedAt")?["integerValue"] as? String ?? "") ?? 0
            let text = fv("data")?["stringValue"] as? String
            running = false
            if code != 404, let text, at > lastRemoteAt,
               let pl = try? PropertyListSerialization.propertyList(from: Data(text.utf8), options: [], format: nil) as? NSDictionary {
                if let d = dirtyAt, d.timeIntervalSince1970 * 1000 > at { await push(); return }   // 手元の変更の方が新しい
                apply(pl); lastRemoteAt = at; dirtyAt = nil; baseline = nil; quietUntil = Date().addingTimeInterval(3)
                lastSync = Date(); status = "\(fv("device")?["stringValue"] as? String ?? "ほかの機械") の設定をもらいました"
            } else if code == 404 || baseline == nil || dirtyAt != nil {
                await push()                                      // まだ文書が無い・初めて・手元に変更あり
            } else { lastSync = Date() }
        } catch {
            running = false; status = "同期できませんでした：\(error.localizedDescription)"
        }
    }

    /// 上げる（文書をまるごと置きかえ）
    func push() async {
        guard !running, let url = docURL else { return }
        running = true; defer { running = false }
        let local = payload()
        do {
            let xml = try PropertyListSerialization.data(fromPropertyList: local, format: .xml, options: 0)
            let at = (Date().timeIntervalSince1970 * 1000).rounded()
            let t = try await CloudAuth.shared.token()
            _ = try await Net.call(url, method: "PATCH", json: ["fields": [
                "data": ["stringValue": String(decoding: xml, as: UTF8.self)], "updatedAt": ["doubleValue": at], "device": ["stringValue": CloudConf.device]]], bearer: t)
            lastRemoteAt = at; baseline = local; dirtyAt = nil; lastSync = Date(); status = "上げました"
        } catch { status = "上げられませんでした：\(error.localizedDescription)" }
    }

    /// もらった中身を手元に：設定はそのまま当てはめ（保存は 1 秒ごとの保存が書く）、ほかは保存してから読み直す
    func apply(_ d: NSDictionary) {
        let ud = UserDefaults.standard
        if let s = st, let set = d["settings"] as? [String: Any] { s.applySettings(set) }
        for k in Self.keys { if let v = d[k] { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } }
        if let s = st { s.asmPresets = AsmPreset.load(); s.asmBasic = AsmBasic.load(); s.presets = AnglePreset.load(); s.ppPresets = PingPongPreset.load() }
        ShortcutStore.shared.reload()
    }
}

/// パネルの「同期（Google でログイン）」の欄
struct CloudSection: View {
    @ObservedObject var auth = CloudAuth.shared
    @ObservedObject var sync = CloudSync.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let u = auth.uid {
                Text("ログイン中：\(auth.email.flatMap { $0.isEmpty ? nil : $0 } ?? u)").font(.caption).foregroundStyle(UIC.text)
                HStack {
                    Btn("今すぐそろえる") { Task { await sync.sync() } }
                    Btn("ログアウト") { auth.signOut() }
                }
                if let t = sync.lastSync { Text("最後にそろえた時刻：\(t.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(UIC.sub) }
            } else {
                Btn(auth.busy ? "ログイン中…" : "Google でログイン") { Task { await auth.signIn() } }.disabled(auth.busy)
            }
            Text("ログインすると、設定・プリセット・ショートカットが、Mac・iPad・iPhone でそろいます（Firebase の、自分だけが読み書きできる場所に保存）。つまんだ倍率と描く細かさは、機械ごとのまま").font(.caption2).foregroundStyle(UIC.sub)
            if !auth.message.isEmpty { Text(auth.message).font(.caption2).foregroundStyle(.orange) }
            if !sync.status.isEmpty { Text(sync.status).font(.caption2).foregroundStyle(UIC.sub) }
        }
    }
}
