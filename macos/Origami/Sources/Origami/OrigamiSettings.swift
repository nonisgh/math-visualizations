// 設定の保存：パネルで変えた値（大きさ・見え方・表示・往復など）をアプリの中に保存して、次に開いた時にもどす。
//   1 秒ごとに今の値をまとめて、前に保存した時と違ったら保存する（つまみを動かしている間は、まとめて 1 回）。
//   まとめた形は JSON にできる辞書なので、あとで Firebase（apps/origami/users/{自分}/settings/layout）にもそのまま送れる。
//   角度・組み立て具合・回し続けるかどうかなど、その時だけの動きは保存しない（開いた時はいつもの初めの形から）
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 確かめで動かしている間は、使っている人の保存に書かない（MacApp が確かめの引数を見て入れる）
enum SaveGuard { static var off = false }

extension OrigamiState {
    static let settingsKey = "origami.settings.v1"

    // 保存する値の表（名前 → どの値か）。足す時はここに 1 行
    static let settingsDoubles: [(String, ReferenceWritableKeyPath<OrigamiState, Double>)] = [
        ("zfNet", \.zfNet), ("zfAsm", \.zfAsm), ("zfXp", \.zfXp),
        ("depth3", \.depth3), ("depthDeep", \.depthDeep), ("slantSheen", \.slantSheen), ("line3W", \.line3W), ("line3K", \.line3K), ("mul4", \.mul4), ("glow4", \.glow4), ("glass4", \.glass4), ("line4K", \.line4K), ("lineWidthNet", \.lineWidthNet), ("lineWidthSolid", \.lineWidthSolid), ("inSphereWireW", \.inSphereWireW), ("inSphereDepth", \.inSphereDepth), ("inSphereTone", \.inSphereTone), ("line4W", \.line4W),
        ("reflSelf", \.reflSelf), ("waterSwirl", \.waterSwirl), ("waterVort1", \.waterVort), ("waterSlicePos", \.waterSlicePos), ("waterSlosh", \.waterSlosh), ("waterNu", \.waterNu), ("ballR38", \.ballR), ("ballG", \.ballG), ("waterG", \.waterG), ("waterPourRate", \.waterPourRate), ("waterPourX", \.waterPourX), ("waterPourY", \.waterPourY), ("waterPourZ", \.waterPourZ), ("squash4", \.squash4), ("slant3", \.slant3), ("lineTint", \.lineTint), ("netSolid", \.netSolid), ("fantasy", \.fantasy), ("warmth", \.warmth), ("netMul", \.netMul), ("softMul", \.softMul), ("smartLine", \.smartLine), ("secPos", \.secPos), ("intN", \.intN), ("intAmount", \.intAmount), ("stripK", \.stripK), ("unfoldK", \.unfoldK), ("speed", \.speed), ("cyclePeriod", \.cyclePeriod),
        ("ehWidthNear", \.ehWidthNear), ("ehWidthFar", \.ehWidthFar), ("ehWidthOther", \.ehWidthOther),
        ("ppSec", \.ppSec), ("ppSine", \.ppSine), ("ppSpring", \.ppSpring), ("ppTurn", \.ppTurn),
        ("renderScale", \.renderScale), ("split", \.split), ("camW", \.camW),
        ("shineK", \.shineK), ("shineSpread", \.shineSpread), ("shineAz", \.shineAz), ("shineEl", \.shineEl),
        ("glare", \.glare), ("vivid", \.vivid), ("envK", \.envK), ("deep", \.deep), ("inner", \.inner),
        ("starsPct", \.starsPct), ("gridN", \.gridN), ("xpDistK", \.xpDistK), ("ptSize", \.ptSize), ("markSize", \.markSize), ("inSphereSpinSpeed", \.inSphereSpinSpeed), ("inSphereDiff", \.inSphereDiff),
    ]
    static let settingsBools: [(String, ReferenceWritableKeyPath<OrigamiState, Bool>)] = [
        ("foldStagger", \.foldStagger), ("autoZoom", \.autoZoom), ("perspMode", \.perspMode), ("left3DAll", \.left3DAll),
        ("swapViews", \.swapViews), ("wireOnly", \.wireOnly), ("ehOn", \.ehOn), ("ehNearOn", \.ehNearOn), ("ehFarOn", \.ehFarOn), ("ppCycle", \.ppCycle),
        ("showAxes", \.showAxes), ("panelOpen", \.panelOpen), ("panelLeft", \.panelLeft), ("raster", \.raster),
        ("shine", \.shine), ("bgSpace", \.bgSpace), ("meshOn", \.meshOn), ("xpStagger", \.xpStagger),
        ("ptLabels", \.ptLabels), ("ptLeft", \.ptLeft), ("panPad", \.panPad), ("secOn", \.secOn), ("inSphere", \.inSphere), ("diceFaces", \.diceFaces), ("diceOneShot", \.diceOneShot), ("netAnim", \.netAnim), ("inSphereGlass", \.inSphereGlass), ("inSphereLon", \.inSphereLon), ("inSphereCone", \.inSphereCone), ("inSphereLat", \.inSphereLat), ("inSphereFilm", \.inSphereFilm), ("inSphere120", \.inSphere120), ("inSphereTouch", \.inSphereTouch), ("inSphereDent", \.inSphereDent), ("inSphereDentSharp", \.inSphereDentSharp), ("sep4", \.sep4), ("sep3", \.sep3), ("intExact", \.intExact), ("waterReal", \.waterReal), ("waterNS", \.waterNS), ("waterFree", \.waterFree), ("waterLidSet", \.waterLidSet), ("waterBottomSet", \.waterBottomSet), ("holesBuilt", \.holesBuilt), ("holesOpenSet", \.holesOpenSet), ("waterVent", \.waterVent), ("intOnce", \.intOnce),  ("foldCourse", \.foldCourse), ("courseFromB", \.courseFromB), ("intOutOpp", \.intOutOpp), ("intFly", \.intFly), ("intBallSpin", \.intBallSpin), ("markShowNear", \.markShowNear), ("markShowFar", \.markShowFar), ("markGlue", \.markGlue), ("markSame", \.markSame), ("markMagnet", \.markMagnet), ("markFlash", \.markFlash), ("inSphereHopf", \.inSphereHopf), ("inSphereFlash", \.inSphereFlash),
    ]
    static let settingsInts: [(String, ReferenceWritableKeyPath<OrigamiState, Int>)] = [
        ("line4", \.line4), ("autoMode", \.autoMode), ("inSphereSpin", \.inSphereSpin), ("lineTintMode", \.lineTintMode), ("inSphereTouchCol", \.inSphereTouchCol), ("inSphereRatio", \.inSphereRatio), ("unf4", \.unf4), ("unf3", \.unf3), ("asm4", \.asm4), ("asm3", \.asm3), ("inSphereColor", \.inSphereColor), ("inSphereLayers", \.inSphereLayers), ("asmPose", \.asmPose), ("asmVanish", \.asmVanish), ("unfPose", \.unfPose), ("foldMaxStages", \.foldMaxStages), ("diceMode", \.diceMode), ("intPace", \.intPace), ("intAxes", \.intAxes), ("intMethod", \.intMethod), ("intShape", \.intShape), ("intView", \.intView), ("intLidMode", \.intLidMode), ("waterNSRes", \.waterNSRes), ("waterSlice", \.waterSlice), ("waterGravMode2", \.waterGravMode), ("ballGravMode", \.ballGravMode),   // 2026-11-24：初めを +W→−W にしたので、前に保存した値は読まない（名前を変えた）
        ("drainMode", \.drainMode), ("intColor", \.intColor), ("intStars", \.intStars), ("intLook", \.intLook), ("viewProj", \.viewProj), ("faceSide", \.faceSide), ("displayMode", \.displayMode), ("panelTab", \.panelTab), ("look", \.look), ("spaceMode", \.spaceMode),
    ]

    /// 今の設定（JSON にできる辞書）
    var settingsSnapshot: [String: Any] {
        var d: [String: Any] = [:]
        for (k, p) in Self.settingsDoubles { d[k] = self[keyPath: p] }
        for (k, p) in Self.settingsBools { d[k] = self[keyPath: p] }
        for (k, p) in Self.settingsInts { d[k] = self[keyPath: p] }
        d["ehNear"] = [Double(ehNear.x), Double(ehNear.y), Double(ehNear.z)]
        d["asmFree"] = asmFree; d["unfFree"] = unfFree; d["unfPoseV3"] = true
        if let m = memUp { d["memUp"] = m }; if let m = memDown { d["memDown"] = m }
        d["ehFar"] = [Double(ehFar.x), Double(ehFar.y), Double(ehFar.z)]
        d["ehCells"] = ehCells.mapValues { [Double($0.x), Double($0.y), Double($0.z)] }
        d["markNear"] = [Double(markNear.x), Double(markNear.y), Double(markNear.z)]; d["markFar"] = [Double(markFar.x), Double(markFar.y), Double(markFar.z)]
        d["ppEase"] = ppEase
        d["netName"] = net.name; d["net4"] = net.p4; d["net3"] = net.p3
        // パレット（#rrggbb の文字）と、補色・軸の色合わせ
        d["pal3"] = pal3.mapValues { OrigamiState.hexString($0) }; d["pal4"] = pal4.mapValues { OrigamiState.hexString($0) }
        d["palComp"] = palComp; d["palCompCenter"] = palCompCenter; d["axisSyncOn"] = axisSyncOn; d["axisSyncMinus"] = axisSyncMinus
        d["ppStops"] = ppStops
        d["points"] = ptsSnapshot                                            // 置いた点（点のタブ）
        d["zoom"] = zoom                                                       // つまんで寄った倍率（左・右の窓）
        return d
    }

    /// 設定をもどす（知らない名前・形の違う値は飛ばす＝古い保存や新しい項目があっても大丈夫）
    func applySettings(_ d: [String: Any]) {
        for (k, p) in Self.settingsDoubles { if let v = d[k] as? Double, v.isFinite { self[keyPath: p] = v } }
        for (k, p) in Self.settingsBools { if let v = d[k] as? Bool { self[keyPath: p] = v } }
        for (k, p) in Self.settingsInts { if let v = d[k] as? Int { self[keyPath: p] = v } }
        func f3(_ a: Any?) -> SIMD3<Float>? { guard let a = a as? [Double], a.count == 3 else { return nil }; return SIMD3(Float(a[0]), Float(a[1]), Float(a[2])) }
        if let c = f3(d["ehNear"]) { ehNear = c }
        if let a = d["asmFree"] as? [Double], a.count == 6 { asmFree = a }
        if let a = d["unfFree"] as? [Double], a.count == 6 { unfFree = a }
        memUp = (d["memUp"] as? [Double]).flatMap { $0.count == 6 ? $0 : nil }; memDown = (d["memDown"] as? [Double]).flatMap { $0.count == 6 ? $0 : nil }
        // 前の保存（線の 4D の奥行きは濃さと太さがいっしょだった。手前が 1 ＋ 0.7 × 強さ 倍）→ 太さを別の数に（2026-11-24）
        if d["lineWidthNet"] == nil, let v = d["lineWidthK"] as? Double, v.isFinite { lineWidthNet = v; lineWidthSolid = v }   // 線の太さが 1 つだった時の保存
        if d["line4W"] == nil, d["line4"] != nil { line4W = line4 == 1 ? -0.7 * line4K : line4 == 2 ? 0.7 * line4K : 0 }
        if d["unfPose"] == nil, let b = d["unfoldToW"] as? Bool { unfPose = b ? 1 : 0 }   // 前の形（展開は W 消失にもどす）
        // 前の保存（覚える 1 つ・組む／開くの覚える・まっすぐ）→ 表の 4 マス（2026-11-23）
        if d["unf4"] == nil {
            let pm = d["poseMemory"] as? Bool ?? true
            let mA = d["memAsm"] as? Bool ?? pm, mU = d["memUnf"] as? Bool ?? pm, sA = d["asmStraight"] as? Bool ?? false
            asm4 = sA ? 2 : (mA ? 1 : 0); asm3 = mA ? 1 : 0; unf4 = unfPose == 1 ? 2 : (mU ? 1 : 0); unf3 = mU ? 1 : 0
        }
        if unfPose == 1 { unfPose = 0; unf4 = 2 }                         // 前の「まっすぐ」は表の 4D ゼロへ
        if d["autoMode"] == nil, let b = d["asmAuto"] as? Bool { autoMode = b ? 1 : 0 }   // 前のおまかせ（入・切）
        if d["unfPoseV3"] == nil && unfPose == 2 { unfPose = 0 }                       // 前の既定（正面から）→ 向きを保つ（C の往復で向きがもどらないように）
        if let c = f3(d["ehFar"]) { ehFar = c }
        if let m = d["ehCells"] as? [String: Any] { ehCells = m.compactMapValues { f3($0) } }
        if let c = f3(d["markNear"]) { markNear = c }; if let c = f3(d["markFar"]) { markFar = c }
        if let s = d["ppEase"] as? String { ppEase = s }
        if let a = d["net4"] as? [Int], let b = d["net3"] as? [Int], OrigamiState.validNet(a, 4), OrigamiState.validNet(b, 3) { net = NetDef(name: d["netName"] as? String ?? "", p4: a, p3: b) }
        func pal(_ a: Any?, _ def: [String: UInt32]) -> [String: UInt32]? {
            guard let m = a as? [String: String] else { return nil }
            var P = def; for (k, v) in m where def[k] != nil { if let c = OrigamiState.parseHex(v) { P[k] = c } }; return P
        }
        if let P = pal(d["pal3"], OrigamiState.palDef3) { pal3 = P }
        if let P = pal(d["pal4"], OrigamiState.palDef4) { pal4 = P }
        if let v = d["palComp"] as? Bool { palComp = v }
        if let v = d["palCompCenter"] as? Bool { palCompCenter = v }
        if let v = d["axisSyncOn"] as? Bool { axisSyncOn = v }
        if let v = d["axisSyncMinus"] as? Bool { axisSyncMinus = v }
        if let a = d["ppStops"] as? [[Double]], !a.isEmpty, a.allSatisfy({ $0.count == 6 }) { ppStops = a }
        if d["points"] != nil { applyPts(d["points"]) }
        if let z = d["zoom"] as? [Double], z.count == 2, z.allSatisfy({ $0.isFinite && $0 > 0 }) { zoom = z }
    }

    // ---- 画面の状態（ウェブ版の「画面の状態をそのまま覚える」）：角度 6 つ・回し続けている面・組み立て具合・往復・分解・周回／角度の往復の再生中。
    //   3 秒ごと（変わっていたら）と閉じる時に保存して、次に開いた時に同じ画面へもどす ----
    static let sessionKey = "origami.session.v1"
    var sessionSnapshot: [String: Any] {
        let r5 = { (x: Double) -> Double in (x * 1e5).rounded() / 1e5 }
        return [
            "v": 1,
            "ang": [ax, ay, zw, xy, xz, yz].map(r5),
            "spins": [spinX, spinY, spinZW, spinXY, spinXZ, spinYZ],
            "prog": r5(progress), "loop": loop,
            "explode": r5(explodeRaw),
            "cycle": cycling, "pp": pp != nil && !(pp?.once ?? true),
            "pan": [pan[0].x, pan[0].y, pan[1].x, pan[1].y].map(r5),
        ]
    }
    func applySession(_ d: [String: Any]) {
        guard (d["v"] as? Int) == 1 else { return }
        if let p = d["prog"] as? Double, p.isFinite { progress = max(0, min(1, p)); target = progress >= 0.5 ? 1 : 0 }
        if let a = d["ang"] as? [Double], a.count == 6, a.allSatisfy({ $0.isFinite }) {
            ax = a[0]; ay = a[1]; zw = a[2]; xy = a[3]; xz = a[4]; yz = a[5]; updateMats()
        }
        if let e = d["explode"] as? Double, e.isFinite { explodeRaw = max(0, min(1, e)) }
        if let p = d["pan"] as? [Double], p.count == 4, p.allSatisfy({ $0.isFinite && abs($0) < 100 }) { pan = [SIMD2(p[0], p[1]), SIMD2(p[2], p[3])] }
        if let s = d["spins"] as? [Bool], s.count == 6 { spinX = s[0]; spinY = s[1]; spinZW = s[2]; spinXY = s[3]; spinXZ = s[4]; spinYZ = s[5] }
        if (d["loop"] as? Bool) == true { loop = true; loopDir = progress >= 1 ? -1 : 1 }
        // 動いている途中のもの：周回・角度の往復は、もう一度始める（往復の止まる所は設定に保存してある）
        if (d["cycle"] as? Bool) == true { toggleCycle() }
        else if (d["pp"] as? Bool) == true, ppStops.count >= 2 { startPP(ppStops, once: false) }
    }
    func saveSession() { UserDefaults.standard.set(NSDictionary(dictionary: sessionSnapshot), forKey: Self.sessionKey) }

    /// 開いた時に 1 回：保存してあった設定をもどし、1 秒ごとに変わっていたら保存する
    /// 確かめ（--perftest の ORIGAMI_USERSET）：保存してある設定と画面の状態を読むだけ（書かない・同期しない）
    func loadSettingsReadOnly() {
        if let d = UserDefaults.standard.dictionary(forKey: Self.settingsKey) { applySettings(d) }
        if let d = UserDefaults.standard.dictionary(forKey: Self.sessionKey) { applySession(d) }
    }
    func startSettings() {
        guard !SaveGuard.off else { return }                             // 確かめの時は、保存を読みも書きもしない（同期もしない）
        if let d = UserDefaults.standard.dictionary(forKey: Self.settingsKey) { applySettings(d) }
        if let d = UserDefaults.standard.dictionary(forKey: Self.sessionKey) { applySession(d) }
        // 1 回だけ：辺の強調を初め切にした（2026-11-14）ので、前に保存された「入」も切にする（このあと入れれば、それが保存される）
        if !UserDefaults.standard.bool(forKey: "origami.migr.ehOff1") { ehOn = false; UserDefaults.standard.set(true, forKey: "origami.migr.ehOff1") }
        var last = NSDictionary(dictionary: settingsSnapshot), lastS = NSDictionary(dictionary: sessionSnapshot), tick = 0
        settingsTimer?.invalidate()
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = NSDictionary(dictionary: self.settingsSnapshot)
            if now != last { last = now; UserDefaults.standard.set(now, forKey: Self.settingsKey) }
            tick += 1
            if tick % 3 == 0 { let s = NSDictionary(dictionary: self.sessionSnapshot); if s != lastS { lastS = s; UserDefaults.standard.set(s, forKey: Self.sessionKey) } }
        }
        MainActor.assumeIsolated { CloudSync.shared.attach(self) }                                    // ログインしていれば、Firebase で設定をそろえる（OrigamiCloud.swift）
        // 閉じる時にも保存（3 秒のあいだに変えた分も残す）
        #if os(macOS)
        let note = NSApplication.willTerminateNotification
        #else
        let note = UIApplication.willResignActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(NSDictionary(dictionary: self.settingsSnapshot), forKey: Self.settingsKey); self.saveSession()
        }
    }
}
