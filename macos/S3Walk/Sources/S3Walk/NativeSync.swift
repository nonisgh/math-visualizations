// 設定の同期（Supabase）：Mac 版と iPad・iPhone 版で、ほぼ全部の状態をそろえる。ウェブ版と同じ表 mathviz_state・同じログイン（メールとパスワード）で、行は別（app ＝ s3walk-native）。
//   起動したら（ログインしてあれば）まず読む。前の同期の後に Supabase 側が変わっていれば、手元を「控え」に取ってから Supabase の設定にそろえる。
//   Supabase 側が変わっていなくて手元だけ変わっていれば（オフラインで変えた分など）、手元を上げる。読み込みが済むまでは自動で上げない。
//   そろえるもの：設定の値・自分の道・キー・ゲームパッドの大きさなど（どの端末も共通）、画面の構成（パネルの並び・地図の置き方など。Mac 同士・iPad／iPhone 同士で別々）、
//   今いる所と目印（起動した時の読み込みでそろえる。動いている間に、ほかの端末の位置は当てない＝歩いている途中で飛ばない）。描く細かさと歩いた跡はそろえない
//   変えたら 3 秒ほどで上げる（今いる所だけが変わった時は 15 秒ごと）。20 秒ごとにほかの端末の変更を見に行く。控えは 10 個まで（パネルから戻せる）
import SwiftUI
import Security

final class NativeSync: ObservableObject {
    static let shared = NativeSync()
    #if os(macOS)
    static let platform = "mac"
    #else
    static let platform = "ios"
    #endif

    // ---- アプリとのつなぎ（AppModel・MobileModel が決める）----
    /// どの端末でも共通の状態（今いる所は入れない）
    var core: () -> [String: Any] = { [:] }
    /// 今いる所・向き・目印
    var position: () -> [String: Any] = { [:] }
    /// Supabase（か控え）の状態を当てる。withPosition：今いる所も当てる
    var apply: ([String: Any], Bool) -> Void = { _, _ in }

    // ---- 見える状態 ----
    @Published var email = ""
    @Published var loggedIn = false
    @Published var enabled = true { didSet { saveState() } }
    @Published var status = "ログインしていない"
    @Published var lastUp: Date? = nil
    @Published var lastDown: Date? = nil
    @Published var backups: [Backup] = []
    struct Backup: Codable, Identifiable { var id = UUID(); var t: Date; var reason: String; var json: String }

    // ---- 覚えておくこと ----
    private var userId = "", access = "", expiresAt = 0.0
    private var lastSynced: Int64 = 0          // そろえた Supabase の saved_at
    private var baseline = ""                  // そろえた時の共通の状態（JSON）
    private var lastPos = "", lastPosUp = 0.0
    private var ready = false                  // 起動した時の読み込みが済んだ
    private var foreign: [String: Any] = [:]   // ほかの種類の端末の画面の構成（ui_mac か ui_ios）。上げる時にそのまま残す
    private var busy = false, lastPull = 0.0
    let device: String
    private var timer: Timer?
    static let stateKey = "s3walk.sync.v1", backupKey = "s3walk.sync.backups", kcService = "io.github.nonisgh.s3walk.supabase"

    init() {
        let d = UserDefaults.standard.dictionary(forKey: NativeSync.stateKey) ?? [:]
        device = (d["device"] as? String) ?? UUID().uuidString
        email = d["email"] as? String ?? ""; userId = d["user"] as? String ?? ""
        enabled = d["enabled"] as? Bool ?? true
        lastSynced = (d["synced"] as? NSNumber)?.int64Value ?? 0; baseline = d["baseline"] as? String ?? ""
        if let b = UserDefaults.standard.data(forKey: NativeSync.backupKey), let v = try? JSONDecoder().decode([Backup].self, from: b) { backups = v }
        loggedIn = !userId.isEmpty && NativeSync.keychain(get: "refresh") != nil
        if !loggedIn { status = "ログインしていない" }
    }
    private func saveState() {
        UserDefaults.standard.set(["device": device, "email": email, "user": userId, "enabled": enabled, "synced": NSNumber(value: lastSynced), "baseline": baseline], forKey: NativeSync.stateKey)
    }

    /// アプリが起動した時：ログインしてあれば、まず読む。3 秒ごとに見回る
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        if loggedIn { Task { @MainActor in await self.readFirst() } }
    }

    /// Supabase の状態を、この端末の分（共通・自分の種類の画面の構成）と、ほかの種類の端末の画面の構成に分ける（今いる所 pos は外す）
    static func split(_ d: [String: Any]) -> (own: [String: Any], foreign: [String: Any]) {
        var own: [String: Any] = [:], fo: [String: Any] = [:]
        for (k, v) in d where k != "pos" { if k.hasPrefix("ui_") && k != "ui_" + platform { fo[k] = v } else { own[k] = v } }
        return (own, fo)
    }
    // ---- 共通の状態（Mac 版と iPad・iPhone 版で同じ）：設定の値（描く細かさは外す）・自分の道・キー・ゲームパッドの大きさ・座標の簡易入力 ----
    static func commonCore(_ r: Renderer) -> [String: Any] {
        var s = r.set.dict(); s["scale"] = nil; s["gamepad"] = nil
        s["quiet"] = nil; s["quietScale"] = nil                     // 静かモードは端末ごと（Mac はファン、iPad は電池）
        let ud = UserDefaults.standard
        return ["set": s, "routes": RouteStore.shared.export(), "keys": Keymap.shared.export(),
                "prefs": ["padScale": ud.object(forKey: "s3walk.vpad.scale") as? Double ?? 1.0, "coordSimple": ud.object(forKey: "s3walk.coord.simple") as? Bool ?? true]]
    }
    static func applyCommon(_ r: Renderer, _ d: [String: Any], _ withPosition: Bool) {
        if let s = d["set"] as? [String: Any] { r.set.load(s) }
        if let o = d["routes"] { RouteStore.shared.load(o) }
        if let k = d["keys"] as? [String: [String]] { Keymap.shared.load(k) }
        if let p = d["prefs"] as? [String: Any] {
            if let v = p["padScale"] as? Double { UserDefaults.standard.set(v, forKey: "s3walk.vpad.scale") }
            if let v = p["coordSimple"] as? Bool { UserDefaults.standard.set(v, forKey: "s3walk.coord.simple") }
        }
        if withPosition, let p = d["pos"] as? [String: Any] { Store.applyPosition(r, p) }
    }
    /// 今いる所・向き・目印（Store.snapshot の set 以外）
    static func position(_ r: Renderer) -> [String: Any] { var d = Store.snapshot(r); d["set"] = nil; return d }

    // ---- JSON ----
    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
    private var coreJSON: String { NativeSync.json(core()) }

    // ---- ログイン（Supabase Auth：メールとパスワード）----
    @MainActor func signIn(email: String, password: String) async {
        status = "ログインしています…"
        do {
            let o = try await auth("password", ["email": email, "password": password])
            self.email = email; take(o)
            status = "ログインした。読み込んでいます…"
            ready = false; lastSynced = 0; baseline = ""; saveState()
            await readFirst()
        } catch { status = "ログインできない：" + NativeSync.msg(error) }
    }
    @MainActor func signOut() {
        NativeSync.keychain(set: "refresh", nil)
        userId = ""; access = ""; loggedIn = false; ready = false; lastSynced = 0; baseline = ""
        status = "ログアウトした（手元の設定はそのまま）"; saveState()
    }
    private func take(_ o: [String: Any]) {
        access = o["access_token"] as? String ?? ""
        if let r = o["refresh_token"] as? String { NativeSync.keychain(set: "refresh", r) }
        expiresAt = Date().timeIntervalSince1970 + ((o["expires_in"] as? Double) ?? 3600)
        if let u = o["user"] as? [String: Any] { userId = u["id"] as? String ?? userId; if let e = u["email"] as? String { email = e } }
        loggedIn = !userId.isEmpty
    }
    private func auth(_ grant: String, _ body: [String: Any]) async throws -> [String: Any] {
        var q = URLRequest(url: URL(string: SupaConfig.url + "/auth/v1/token?grant_type=" + grant)!)
        q.httpMethod = "POST"; q.setValue(SupaConfig.anonKey, forHTTPHeaderField: "apikey"); q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        q.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, res) = try await URLSession.shared.data(for: q)
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw SyncError.server((o["error_description"] ?? o["msg"] ?? o["message"] ?? "答え \((res as? HTTPURLResponse)?.statusCode ?? 0)") as? String ?? "") }
        return o
    }
    /// 鍵が切れそうなら新しくする
    private func token() async throws -> String {
        if !access.isEmpty && Date().timeIntervalSince1970 < expiresAt - 60 { return access }
        guard let r = NativeSync.keychain(get: "refresh") else { throw SyncError.server("ログインし直してください") }
        let o = try await auth("refresh_token", ["refresh_token": r]); take(o)
        return access
    }
    enum SyncError: Error { case server(String) }
    static func msg(_ e: Error) -> String { if case SyncError.server(let s) = e { return s }; return e.localizedDescription }

    // ---- 表 mathviz_state ----
    private func rest(_ method: String, _ path: String, _ body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        let tk = try await token()
        var q = URLRequest(url: URL(string: SupaConfig.url + "/rest/v1/" + path)!)
        q.httpMethod = method
        q.setValue(SupaConfig.anonKey, forHTTPHeaderField: "apikey"); q.setValue("Bearer " + tk, forHTTPHeaderField: "Authorization")
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { q.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { q.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (d, res) = try await URLSession.shared.data(for: q)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { access = ""; expiresAt = 0 }
        guard (200..<300).contains(code) else { throw SyncError.server("表の答え \(code)：" + String(decoding: d.prefix(200), as: UTF8.self)) }
        return d
    }
    private struct Row { var data: [String: Any]; var saved: Int64; var device: String }
    private func fetch() async throws -> Row? {
        let d = try await rest("GET", "mathviz_state?app=eq.\(SupaConfig.app)&select=data,saved_at,device")
        guard let a = try JSONSerialization.jsonObject(with: d) as? [[String: Any]], let o = a.first else { return nil }
        return Row(data: o["data"] as? [String: Any] ?? [:], saved: (o["saved_at"] as? NSNumber)?.int64Value ?? 0, device: o["device"] as? String ?? "")
    }
    @MainActor private func upload() async {
        let c = core(), p = position(), cj = NativeSync.json(c)
        var data = c; data["pos"] = p
        for (k, v) in foreign { data[k] = v }                       // ほかの種類の端末の画面の構成は、そのまま残す
        let saved = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            _ = try await rest("POST", "mathviz_state?on_conflict=user_id,app",
                               ["user_id": userId, "app": SupaConfig.app, "data": data, "build": "native-\(NativeSync.platform)", "saved_at": NSNumber(value: saved), "device": device],
                               prefer: "resolution=merge-duplicates,return=minimal")
            baseline = cj; lastSynced = saved; lastPos = NativeSync.json(p); lastPosUp = Date().timeIntervalSince1970
            lastUp = Date(); status = "同期している（上げた）"; saveState()
        } catch { status = "上げられない：" + NativeSync.msg(error) }
    }

    /// 起動した時・ログインした時：まず読む
    @MainActor func readFirst() async {
        guard loggedIn, !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let row = try await fetch() else {                // Supabase にまだない：手元を上げる
                ready = true; await upload(); status = "Supabase にまだ無かったので、手元の設定を上げた"; return
            }
            let local = coreJSON
            let (rc, fo) = NativeSync.split(row.data); foreign = fo
            let remote = NativeSync.json(rc)
            if lastSynced != 0 && row.saved == lastSynced {
                // Supabase は前にそろえた時のまま：手元で変えた分があれば上げる
                ready = true
                if local != baseline { await upload(); status = "手元で変えた分を上げた（Supabase は前のまま）" } else { status = "同期している（変わりなし）" }
                return
            }
            if remote != local || NativeSync.json(row.data["pos"] ?? [:]) != NativeSync.json(position()) {
                backup("Supabase から読み込む前の手元の設定")
                apply(row.data, true)
                status = "Supabase の設定にそろえた（前の手元の設定は控えに）"
            } else { status = "同期している（同じだった）" }
            baseline = coreJSON; lastSynced = row.saved; lastPos = NativeSync.json(position()); lastDown = Date(); ready = true; saveState()
        } catch { status = "読めない：" + NativeSync.msg(error) + "（読めるまで自動では上げない）" }
    }

    /// 3 秒ごと：変わっていたら上げる。20 秒ごと：ほかの端末の変更を見に行く
    private func tick() {
        guard loggedIn, enabled else { return }
        if !ready { if !busy { Task { @MainActor in await self.readFirst() } }; return }
        guard !busy else { return }
        let now = Date().timeIntervalSince1970
        if coreJSON != baseline || (now - lastPosUp > 15 && NativeSync.json(position()) != lastPos) {
            busy = true; Task { @MainActor in await self.upload(); self.busy = false }
            return
        }
        if now - lastPull > 20 {
            lastPull = now; busy = true
            Task { @MainActor in await self.pull(); self.busy = false }
        }
    }
    /// ほかの端末の変更を当てる（今いる所は当てない）
    @MainActor private func pull() async {
        do {
            guard let row = try await fetch(), row.saved > lastSynced, row.device != device else { return }
            foreign = NativeSync.split(row.data).foreign
            if coreJSON != baseline { backup("ほかの端末の変更を当てる前の手元の設定（両方で変えていた）") }
            apply(row.data, false)
            baseline = coreJSON; lastSynced = row.saved; lastDown = Date(); status = "ほかの端末の変更を当てた"; saveState()
        } catch { status = "読めない：" + NativeSync.msg(error) }
    }
    /// 今すぐ上げる・今すぐ読む（パネルのボタン）
    @MainActor func pushNow() async { guard loggedIn else { return }; ready = true; await upload() }
    @MainActor func pullNow() async { guard loggedIn else { return }; lastSynced = 0; ready = false; await readFirst() }

    // ---- 控え ----
    func backup(_ reason: String) {
        var d = core(); d["pos"] = position()
        backups.insert(Backup(t: Date(), reason: reason, json: NativeSync.json(d)), at: 0)
        if backups.count > 10 { backups.removeLast(backups.count - 10) }
        if let b = try? JSONEncoder().encode(backups) { UserDefaults.standard.set(b, forKey: NativeSync.backupKey) }
    }
    /// 控えに戻す（戻す前の今の設定も控えに。ログイン中なら、戻した設定を上げる）
    func restore(_ b: Backup) {
        guard let d = b.json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        backup("控えに戻す前の設定")
        apply(o, true)
        status = "控え（\(NativeSync.timeText(b.t))）に戻した" + (loggedIn ? "。次の見回りで上げる" : "")
    }
    static func timeText(_ t: Date) -> String { let f = DateFormatter(); f.dateFormat = "M/d HH:mm:ss"; return f.string(from: t) }

    // ---- キーチェーン（ログインの鍵だけ。パスワードは覚えない）----
    static func keychain(get k: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: kcService, kSecAttrAccount as String: k, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func keychain(set k: String, _ v: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: kcService, kSecAttrAccount as String: k]
        SecItemDelete(q as CFDictionary)
        guard let v else { return }
        var a = q; a[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(a as CFDictionary, nil)
    }
}

/// 同期のパネル
struct NativeSyncPanel: View {
    @ObservedObject var sync = NativeSync.shared
    @State private var mail = ""
    @State private var pass = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(sync.status).font(.caption).foregroundStyle(sync.status.contains("できない") || sync.status.contains("読めない") || sync.status.contains("上げられない") ? Color.orange : Space.sky)
                .fixedSize(horizontal: false, vertical: true)
            if sync.loggedIn {
                Text("ログイン中：\(sync.email)").font(.callout)
                Toggle("自動で同期する（変えたら 3 秒ほどで上げ、20 秒ごとにほかの端末の変更を見る）", isOn: $sync.enabled)
                HStack(spacing: 6) {
                    Button("今すぐ上げる") { Task { await sync.pushNow() } }
                    Button("今すぐ読む") { Task { await sync.pullNow() } }
                    Button("ログアウト") { sync.signOut() }
                }
                if let t = sync.lastUp { Text("最後に上げた：\(NativeSync.timeText(t))").font(.caption2).foregroundStyle(Space.slate) }
                if let t = sync.lastDown { Text("最後に読んだ：\(NativeSync.timeText(t))").font(.caption2).foregroundStyle(Space.slate) }
            } else {
                TextField("メールアドレス", text: $mail).textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    #endif
                SecureField("パスワード", text: $pass).textFieldStyle(.roundedBorder)
                Button("ログイン（ウェブ版と同じアカウント）") { let m = mail, p = pass; pass = ""; Task { await sync.signIn(email: m, password: p) } }
                    .disabled(mail.isEmpty || pass.isEmpty)
            }
            Text("控え（Supabase から読み込む前の手元の設定など、新しい順に 10 個まで）").font(.caption.bold()).foregroundStyle(Space.lilac).padding(.top, 4)
            if sync.backups.isEmpty { Text("まだ無い").font(.caption).foregroundStyle(Space.slate) }
            ForEach(sync.backups) { b in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NativeSync.timeText(b.t)).font(.system(size: 11, design: .monospaced))
                        Text(b.reason).font(.caption2).foregroundStyle(Space.slate).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button("この控えに戻す") { sync.restore(b) }.controlSize(.small)
                }
            }
            Text("起動したら、まず Supabase から読み込みます。Supabase 側が前の同期から変わっていれば、手元の設定を控えに取ってからそろえます（変わっていなければ手元の変更を上げます）。設定の値・自分の道・キーなどはどの端末も共通、パネルの並びや地図の置き方は Mac どうし・iPad／iPhone どうしで別々。今いる所は起動した時だけそろえます。描く細かさ・歩いた跡はそろえません。パスワードは覚えません（ログインの鍵だけキーチェーンに）")
                .font(.caption).foregroundStyle(Space.slate).fixedSize(horizontal: false, vertical: true)
        }
    }
}
