// 組み上がりの向き：組み立てる時に、選んだ向きへ回しながら着地する。展開する時は、そのまま開くか W 消失にもどしながら開くか。
//   向き：そのまま・胞から・面から・辺から・頂点から（等角）・自由（6 つの角度）。
//   消失軸：4 次元の奥行きになる軸（W がいつもの「W 消失の絵」。X にすると x の軸が奥へ消える「X 消失の絵」）。向きと組み合わせる。
//   向き × 消失軸 の 4 次元の回転 M を作って、アプリの角度（X-W・Y-W・Z-W と X-Y・X-Z・Y-Z）に分け直す：
//     m4 ＝ c3（3D の回転、w を動かさない）・r4a（X-W → Y-W → Z-W）なので、M の w の行 ＝ r4a の w の行 から X-W・Y-W・Z-W が決まり、
//     残り c3 ＝ M・r4aᵀ を 3D の角度に分ける。
//   展開図は 4 次元の中の 3 次元の平ら（w ＝ −1）に広がるので、X-W・Y-W・Z-W が 0 でないと写した展開図はゆがむ（紙をななめから見るのと同じ）。
//   展開の向き：開きながら回して、開き終わった時の向きを選ぶ。そのまま・W 消失にもどす（X-W・Y-W・Z-W だけ 0、3D は残す）・
//     W 正面 Z 正面（全部 0＝いちばん基本の正面）・3D の見る向き（上から・横から・ななめ上から。どれも W 消失＝ゆがみなし）・自由（6 つの角度）
import Foundation
import simd
import SwiftUI

/// 組み上がりの向きのプリセット
struct AsmPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var pose: Int                             // 0 そのまま・1 胞・2 面・3 辺・4 頂点・5 自由
    var vanish: Int                           // 消失軸 0 x・1 y・2 z・3 w
    var free: [Double]                        // 自由の角度（度）：X-W・Y-W・Z-W・X-Y・X-Z・Y-Z
    var toW: Bool                             // （前の形）展開は W 消失にもどす
    var unf: Int? = nil                       // 展開の向き（無ければ toW から）
    var unfFree: [Double]? = nil              // 展開の向きの自由の角度（度）
    var net: NetDef? = nil                    // 展開図の種類
    var snap: [Double]? = nil                 // その時の状態：形の向き（6 つの角度、ラジアン）。あれば「状態のプリセット」
    var prog: Double? = nil                   // その時の状態：組み具合（0 展開図 〜 1 組み上がり）
    var lock: Bool? = nil
    var unfPose: Int { unf ?? (toW ? 1 : 0) }
    var locked: Bool { lock ?? false }
    static let key = "origami.asmPresets"
    static func load() -> [AsmPreset] {
        guard let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode([AsmPreset].self, from: d) else { return [] }
        return a
    }
    static func save(_ a: [AsmPreset]) { if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) } }
}

/// 自分で決めた「基本」（↺ 基本にもどす で、この設定と形の向きへ）。無ければ最初の基本（そのまま・W 消失・展開は W 正面 Z 正面・角度 0）
struct AsmBasic: Codable, Equatable {
    var pose: Int, vanish: Int, free: [Double], unf: Int, unfFree: [Double]
    var ang: [Double]                         // 形の向き（6 つの角度、ラジアン）
    static let key = "origami.asmBasic"
    static func load() -> AsmBasic? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AsmBasic.self, from: d)
    }
    static func save(_ b: AsmBasic?) {
        if let b, let d = try? JSONEncoder().encode(b) { UserDefaults.standard.set(d, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// 着地の途中（組み立て＝up、展開＝down）
struct AsmLand { var from: [Double]; var to: [Double]; var p0: Double; var up: Bool; var par: Double? }

extension OrigamiState {
    static let asmPoseNames = ["向きを保つ", "胞から", "面から", "辺から", "頂点から（等角）", "自由"]
    static let unfPoseNames = ["向きを保つ", "まっすぐ開く（ゆがみなし）", "正面から", "上から（Y）", "横から（X）", "ななめ上から", "自由"]
    /// 展開の向きの 3D の見る向き（X-Y・X-Z・Y-Z）：上から＝y を手前へ・横から＝x を手前へ・ななめ上から＝少し右へ回して上から見下ろす
    static let unfViews3: [[Double]] = [[0, 0, .pi / 2], [0, .pi / 2, 0], [0, -0.62, 0.5]]
    /// 展開の行き先（そのままなら無し）
    func unfTarget() -> [Double]? {
        switch unfPose {
        case 1: return [0, 0, 0, xy, xz, yz]
        case 2: return [0, 0, 0, 0, 0, 0]
        case 3, 4, 5: let v = Self.unfViews3[unfPose - 3]; return [0, 0, 0, v[0], v[1], v[2]]
        case 6: return unfFree.count == 6 ? unfFree.map { $0 * .pi / 180 } : nil
        default: return nil
        }
    }
    static let axisNames = ["X", "Y", "Z", "W"]
    var cur6: [Double] { [ax, ay, zw, xy, xz, yz] }

    /// 4 次元の回転 M を、アプリの 6 つの角度に分け直す（prev3：今の 3D の角度＝近いほうの解を選ぶ）
    static func decompose4(_ M: simd_double4x4, prev3: [Double]) -> [Double] {
        let v = SIMD4<Double>(M[0][3], M[1][3], M[2][3], M[3][3])                 // w の行
        let zw = asin(max(-1, min(1, v.z))), cz = cos(zw)
        var ay = 0.0, ax = 0.0
        if cz > 1e-6 { ay = atan2(v.y, hypot(v.x, v.w)); ax = atan2(v.x, v.w) }
        let r4 = R(2, 3, zw) * R(1, 3, ay) * R(0, 3, ax)
        let d = decompose(M * r4.transpose, prev3)
        return [ax, ay, zw, d[0], d[1], d[2]]
    }
    /// 角度 6 つ → 4 次元の回転
    static func rot6(_ a: [Double]) -> simd_double4x4 { R(1, 2, a[5]) * R(0, 2, a[4]) * R(0, 1, a[3]) * R(2, 3, a[2]) * R(1, 3, a[1]) * R(0, 3, a[0]) }
    /// 選んだ向き × 消失軸の行き先（そのまま × W なら無し）
    func asmTarget(pose: Int? = nil, vanish: Int? = nil) -> (ang: [Double], par: Double?)? {
        let pose = pose ?? asmPose, vanish = vanish ?? asmVanish
        guard pose != 0 || vanish != 3 else { return nil }
        // 奥へ消える軸が W のままなら、角度をそのまま使う（回転の行列から分け直すと、同じ向きでも別の角度の組＝180° 回した組などになり、
        //   着地の時に余分な回転が入るため）
        if vanish == 3 {
            if (1...4).contains(pose) { let v = Self.views[pose - 1]; return ([v.a, v.b, v.c, 0, 0, 0], viewPar(v.par)) }
            if pose == 5, asmFree.count == 6 { return (asmFree.map { $0 * .pi / 180 }, nil) }
        }
        var M: simd_double4x4, par: Double? = nil
        switch pose {
        case 1...4: let v = Self.views[pose - 1]; M = Self.rot6([v.a, v.b, v.c, 0, 0, 0]); par = viewPar(v.par)
        case 5: M = Self.rot6(asmFree.map { $0 * .pi / 180 })
        default: M = Self.rot6(cur6)
        }
        if vanish != 3 { M = M * Self.R(vanish, 3, .pi / 2) }                     // 消失軸を w の役に（その軸が奥へ消える）
        return (Self.decompose4(M, prev3: [xy, xz, yz]), par)
    }
    /// 組み立て・展開の進みに合わせて回す（1 コマごと。進みが変わった時だけ）
    func asmTick() {
        let p = progress
        defer { asmLastP = p }
        if p >= 0.999 && asmLand == nil { asmSeenUp = cur6 }               // 今の往復をおぼえる（組み上がった向き・開いた向き）
        if p <= 0.001 && asmLand == nil { asmSeenDown = cur6 }
        guard asmLastP >= 0, diceRoll == nil, pp == nil, !cycling else { asmLand = nil; return }
        let dp = p - asmLastP
        if dp > 1e-9 && asmLand?.up != true && p < 0.999, let tg = asmTarget() {
            stopSpins(); tween = nil; pend = [0, 0, 0, 0, 0]; stepRemain = [0, 0, 0]; stepVel = [0, 0, 0]
            asmLand = AsmLand(from: cur6, to: tg.ang, p0: asmLastP, up: true, par: tg.par)
        } else if dp < -1e-9 && asmLand?.up != false && p > 0.001, let to = unfTarget(), zip(to, cur6).contains(where: { abs(Self.wrapPi($0 - $1)) > 1e-4 }) {
            tween = nil; pend = [0, 0, 0, 0, 0]; stepRemain = [0, 0, 0]; stepVel = [0, 0, 0]; stopSpins()
            asmLand = AsmLand(from: cur6, to: to, p0: asmLastP, up: false, par: 0)
        }
        guard let L = asmLand, abs(dp) > 1e-9 || p >= 0.999 || p <= 0.001 else { return }
        // 組み立て：後ろ 3/4 で回る（はじめは折りが見えるように）。展開：はじめ 7 割で W 消失へ（開き終わる前にゆがみが取れる）
        let u = L.up ? (p - L.p0) / max(1e-6, 1 - L.p0) : (L.p0 - p) / max(1e-6, L.p0)
        let f = L.up ? Self.smoother((u - 0.25) / 0.75) : Self.smoother(u / 0.7)
        let a = (0..<6).map { L.from[$0] + Self.wrapPi(L.to[$0] - L.from[$0]) * f }
        ax = a[0]; ay = a[1]; zw = a[2]; xy = a[3]; xz = a[4]; yz = a[5]
        if (L.up && p >= 0.999) || (!L.up && p <= 0.001) || f >= 1 {
            ax = Self.wrapPi(L.to[0]); ay = Self.wrapPi(L.to[1]); zw = Self.wrapPi(L.to[2]); xy = Self.wrapPi(L.to[3]); xz = Self.wrapPi(L.to[4]); yz = Self.wrapPi(L.to[5])
            if L.up { presetPar = L.par; presetHold = SIMD3(ax, ay, zw); viewSel = (1...4).contains(asmPose) && asmVanish == 3 ? asmPose - 1 : -1 } else { presetPar = nil; viewSel = -1 }
            asmLand = nil
        }
        rotRev += 1; updateMats()
    }
    /// 基本にもどす：自分で決めた基本があれば、その設定と形の向きへ。無ければ最初の基本（組み上がり そのまま・W 消失、展開 W 正面・Z 正面、角度 0）
    func asmResetBasic() {
        let b = asmBasic
        asmPose = b?.pose ?? 0; asmVanish = b?.vanish ?? 3; unfPose = b?.unf ?? 0
        if let f = b?.free, f.count == 6 { asmFree = f }
        if let f = b?.unfFree, f.count == 6 { unfFree = f }
        cycling = false; stopSpins(); asmLand = nil; pend = [0, 0, 0, 0, 0]
        let to = (b?.ang.count == 6 ? b!.ang : [0, 0, 0, 0, 0, 0])
        tween = (cur6, to, 0, 1.2, projBlend, 0); presetPar = nil; viewSel = -1
    }
    /// 今の設定と形の向きを「基本」として覚える
    func asmSaveBasic() {
        asmBasic = AsmBasic(pose: asmPose, vanish: asmVanish, free: asmFree, unf: unfPose, unfFree: unfFree, ang: cur6)
        AsmBasic.save(asmBasic)
    }
    /// 最初の基本にもどす（覚えた基本を消して、最初の基本へ）
    func asmFactoryBasic() { asmBasic = nil; AsmBasic.save(nil); asmResetBasic() }
    /// 最初の設定（向きを保つ）と正面（角度 0）にもどす。覚えた ⭐ は消さない
    func asmResetFactory() {
        asmPose = 0; asmVanish = 3; unfPose = 0
        cycling = false; stopSpins(); asmLand = nil; pend = [0, 0, 0, 0, 0]
        tween = (cur6, [0, 0, 0, 0, 0, 0], 0, 1.2, projBlend, 0); presetPar = nil; viewSel = -1
    }
    /// よく使う 3 つのモード：0 向きを保つ・1 開くとまっすぐ・2 自分の基本（⭐）・−1 くわしくで決めたほか
    var asmMode: Int {
        if asmBasic != nil && asmIsBasic { return 2 }
        if asmPose == 0 && asmVanish == 3 { if unfPose == 0 { return 0 }; if unfPose == 1 { return 1 } }
        return -1
    }
    /// 次に C（組み立て ⇔ 展開）を押すと何が起きるか
    var nextCText: String {
        if progress > 0.5 {
            let d = ["向きを保ったまま", "まっすぐ（ゆがみなし・3D の向きは保つ）", "正面から見る向きへ", "上から見る向きへ", "横から見る向きへ", "ななめ上から見る向きへ", "自由の角度へ"][max(0, min(6, unfPose))]
            return "次の C：開く → " + d
        }
        if asmPose == 0 && asmVanish == 3 { return "次の C：組む → 向きを保ったまま" }
        let v = asmVanish == 3 ? "" : "・\(Self.axisNames[asmVanish]) が奥へ消える"
        return "次の C：組む → \(asmPose == 5 ? "決めた角度" : Self.asmPoseNames[max(0, min(5, asmPose))])\(v) に着地"
    }
    /// 今の往復（組み上がった向きと、開いた向き）をそのままプリセットに
    /// 今の状態をまるごとプリセットに：形の向き・展開図の種類・組み具合・開いた時に W 消失させるか（まっすぐ）。多段階の設定は入れない
    func saveSnapshotPreset() {
        let n = asmPresetName.trimmingCharacters(in: .whitespaces), u = unfPose == 1 ? 1 : 0
        asmPresets.append(AsmPreset(name: n.isEmpty ? "状態 \(asmPresets.count + 1)" : n, pose: 0, vanish: 3, free: [0, 0, 0, 0, 0, 0], toW: u == 1, unf: u, unfFree: nil, net: net, snap: cur6, prog: progress))
        asmPresetName = ""; AsmPreset.save(asmPresets)
    }
    /// 状態のプリセットを呼び出す：その時の向き・展開図・組み具合にもどし、あとは今の向きのまま往復（組む・開くで回さない。開いた時に W 消失させるかだけ）
    func loadSnapshot(_ ang: [Double], net d: NetDef?, prog: Double?, unf: Int) {
        asmPose = 0; asmVanish = 3; unfPose = unf == 1 ? 1 : 0
        cycling = false; stopSpins(); asmLand = nil; pend = [0, 0, 0, 0, 0]; presetPar = nil; viewSel = -1
        let sideNow = progress >= 0.5, sideTo = (prog ?? progress) >= 0.5
        if let d, d != net, OrigamiState.validNet(d.p4, 4), OrigamiState.validNet(d.p3, 3) {
            if sideNow == sideTo { switchNet(d) } else { netMorph = nil; net = d }
        }
        if sideNow == sideTo {
            tween = (cur6, ang, 0, 1.0, projBlend, projBlend)            // 同じ組み具合なら、なめらかにその向きへ
        } else {                                                          // 組み具合がちがえば、その状態へそのまま
            playing = false; loop = false; tween = nil
            progress = prog ?? progress; asmLastP = progress
            ax = ang[0]; ay = ang[1]; zw = ang[2]; xy = ang[3]; xz = ang[4]; yz = ang[5]; rotRev += 1; updateMats()
        }
    }
    var asmIsBasic: Bool {
        if let b = asmBasic { return asmPose == b.pose && asmVanish == b.vanish && unfPose == b.unf && (asmPose != 5 || asmFree == b.free) && (unfPose != 6 || unfFree == b.unfFree) }
        return asmPose == 0 && asmVanish == 3 && unfPose == 0
    }
    /// 基本の中身（説明用）
    var asmBasicText: String {
        let p = asmBasic?.pose ?? 0, v = asmBasic?.vanish ?? 3, u = asmBasic?.unf ?? 0
        return "組む \(Self.asmPoseNames[max(0, min(5, p))])" + (v == 3 ? "" : "・\(Self.axisNames[max(0, min(3, v))]) が奥へ") + "・開く \(Self.unfPoseNames[max(0, min(6, u))])" + (asmBasic == nil ? "（最初の設定）" : "・形の向きも覚えている")
    }
    /// 今の形を、選んだ展開の向きへなめらかに回す（展開したあとでも）
    func unfApplyNow() {
        guard let to = unfTarget() else { return }
        cycling = false; stopSpins(); asmLand = nil; pend = [0, 0, 0, 0, 0]
        tween = (cur6, to, 0, 1.2, projBlend, 0); presetPar = nil; viewSel = -1
    }
    /// 今の形を、選んだ向きへなめらかに回す（組み上がったあとでも）
    func asmApplyNow() {
        guard let tg = asmTarget() else { return }
        cycling = false; stopSpins(); asmLand = nil; pend = [0, 0, 0, 0, 0]
        tween = (cur6, tg.ang, 0, 1.2, projBlend, tg.par ?? projBlend)
        presetPar = tg.par; presetHold = SIMD3(tg.ang[0], tg.ang[1], tg.ang[2])
    }
    // ---- プリセット ----
    func saveAsmPreset() {
        let n = asmPresetName.trimmingCharacters(in: .whitespaces)
        asmPresets.append(AsmPreset(name: n.isEmpty ? "向き \(asmPresets.count + 1)" : n, pose: asmPose, vanish: asmVanish, free: asmFree, toW: unfPose == 1, unf: unfPose, unfFree: unfFree))
        asmPresetName = ""; AsmPreset.save(asmPresets)
    }
    func loadAsmPreset(_ p: AsmPreset) {
        if let a = p.snap, a.count == 6 { loadSnapshot(a, net: p.net, prog: p.prog, unf: p.unfPose); return }
        // 前に「今の往復を保存」で作ったもの（自由 × 自由 ＋ 展開図）：状態のプリセットとして、今の組み具合の側の向きへ
        if p.pose == 5 && p.unfPose == 6 && p.net != nil, p.free.count == 6, let uf = p.unfFree, uf.count == 6 {
            let a = (progress >= 0.5 ? p.free : uf).map { $0 * .pi / 180 }
            loadSnapshot(a, net: p.net, prog: nil, unf: 0); return
        }
        if let d = p.net, OrigamiState.validNet(d.p4, 4), OrigamiState.validNet(d.p3, 3) { switchNet(d) }
        asmPose = p.pose; asmVanish = p.vanish; asmFree = p.free.count == 6 ? p.free : [0, 0, 0, 0, 0, 0]; unfPose = p.unfPose; if let f = p.unfFree, f.count == 6 { unfFree = f }
        // 呼び出したら、すぐ保存した時の画面の向きへ（組み上がっていれば組んだ時の向き、開いていれば開いた時の向き）。次の C で余分に回らない
        if progress >= 0.5 { if asmTarget() != nil { asmApplyNow() } } else if unfTarget() != nil { unfApplyNow() }
    }
    func deleteAsmPreset(_ p: AsmPreset) { if p.locked { return }; asmPresets.removeAll { $0.id == p.id }; AsmPreset.save(asmPresets) }
    func toggleLockAsm(_ p: AsmPreset) { if let i = asmPresets.firstIndex(where: { $0.id == p.id }) { asmPresets[i].lock = !asmPresets[i].locked; AsmPreset.save(asmPresets) } }
}

/// 次に C を押すと何が起きるかの 1 行（再生の欄・超立方体の窓のすみ）
struct NextCLine: View {
    @ObservedObject var st: OrigamiState
    var small = false
    var body: some View {
        LiveRead(live: st.live) {
            Text(st.nextCText).font(.system(size: small ? 10 : 11, weight: .semibold)).foregroundStyle(UIC.cyan.opacity(small ? 0.8 : 1)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 折りたたみタブの「組み上がりの向き」の欄：よく使う 3 つのモードを上に。細かい設定は「くわしく」の中
struct AsmPoseSection: View {
    @ObservedObject var st: OrigamiState
    @AppStorage("asmDetailOpen") var detail = false
    func unfB(_ i: Int) -> Binding<Double> { Binding(get: { st.unfFree.indices.contains(i) ? st.unfFree[i] : 0 }, set: { v in if st.unfFree.indices.contains(i) { st.unfFree[i] = v } }) }
    func freeB(_ i: Int) -> Binding<Double> { Binding(get: { st.asmFree.indices.contains(i) ? st.asmFree[i] : 0 }, set: { v in if st.asmFree.indices.contains(i) { st.asmFree[i] = v } }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // よく使う 3 つ
            HStack(spacing: 6) {
                Btn("🔁 向きを保つ", on: st.asmMode == 0) { st.asmPose = 0; st.asmVanish = 3; st.unfPose = 0 }
                    .help("組んでも開いても、今の向きのまま（前からの往復と同じ）")
                Btn("📐 開くとまっすぐ", on: st.asmMode == 1) { st.asmPose = 0; st.asmVanish = 3; st.unfPose = 1 }
                    .help("組む時は向きを保ち、開く時だけ 4 次元のかたむきを取る（ゆがみのない展開図。3D の向きは保つ）")
            }
            HStack(spacing: 6) {
                Btn("⭐ 自分の基本", on: st.asmMode == 2) { if st.asmBasic != nil { st.asmResetBasic() } }
                    .help(st.asmBasic == nil ? "まだ覚えていない：「今の設定と形を ⭐ に覚える」を先に押す" : "覚えた設定にして、形も覚えた向きへ回す")

                Btn("今の設定と形を ⭐ に覚える") { st.asmSaveBasic() }.help("今の 組む・開く の設定と、今の形の向き（6 つの角度）を ⭐ として覚える（閉じても忘れない）")
            }
            Text("⭐＝" + st.asmBasicText).font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            NextCLine(st: st)
            // くわしく（たたむ）
            Button { detail.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: detail ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                    Text("くわしく（向き・奥へ消える軸・開く向き・プリセット）").font(.system(size: 11, weight: .semibold))
                }.foregroundStyle(UIC.text).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if detail { details }
        }
    }
    @ViewBuilder var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Btn("↺ 最初の設定と正面にもどす") { st.asmResetFactory() }.help("組む・開く を「向きを保つ」に、形を正面（6 つの角度 0）へ。⭐ は消さない")
                if st.asmBasic != nil { Btn("⭐ を消す") { st.asmBasic = nil; AsmBasic.save(nil) } }
            }
            poseBlock
            unfBlock
            presetBlock
        }
        .padding(8).background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
    @ViewBuilder var poseBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(UIC.line)
            Text("組み上がりの向き（組み終わった時）").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
            HStack(spacing: 6) { ForEach(0..<3, id: \.self) { k in Btn(OrigamiState.asmPoseNames[k], on: st.asmPose == k) { st.asmPose = k } } }
            HStack(spacing: 6) { ForEach(3..<6, id: \.self) { k in Btn(OrigamiState.asmPoseNames[k], on: st.asmPose == k) { st.asmPose = k } } }
            if st.asmPose == 5 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<6, id: \.self) { i in NumRow(["X-W", "Y-W", "Z-W", "X-Y", "X-Z", "Y-Z"][i], freeB(i), -180...180, "%.0f°") }
                    Btn("今の向きを入れる") { st.asmFree = st.cur6.map { ($0 * 180 / .pi).rounded() } }.help("今の 6 つの角度を、自由の角度にうつす")
                }
                .padding(8).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 6) {
                Text("奥へ消える軸").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                ForEach([3, 0, 1, 2], id: \.self) { a in
                    Btn(OrigamiState.axisNames[a], on: st.asmVanish == a) { st.asmVanish = a }
                        .help(a == 3 ? "いつもの形（w の軸が 4 次元の奥へ消える＝W 消失）" : "\(OrigamiState.axisNames[a]) の軸が 4 次元の奥へ消える（外と内の立方体が ±\(OrigamiState.axisNames[a]) の胞になる）")
                }
            }
            Btn("今の形をこの向きに") { st.asmApplyNow() }.help("組み上がっている今の形を、選んだ向き × 奥へ消える軸へなめらかに回す")
        }
    }
    @ViewBuilder var unfBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(UIC.line)
            Text("開く向き（開き終わった時）").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
            HStack(spacing: 6) { ForEach(0..<2, id: \.self) { k in Btn(OrigamiState.unfPoseNames[k], on: st.unfPose == k) { st.unfPose = k } } }
            HStack(spacing: 6) { ForEach(2..<5, id: \.self) { k in Btn(OrigamiState.unfPoseNames[k], on: st.unfPose == k) { st.unfPose = k } } }
            HStack(spacing: 6) { ForEach(5..<7, id: \.self) { k in Btn(OrigamiState.unfPoseNames[k], on: st.unfPose == k) { st.unfPose = k } } }
            if st.unfPose == 6 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<6, id: \.self) { i in NumRow(["X-W", "Y-W", "Z-W", "X-Y", "X-Z", "Y-Z"][i], unfB(i), -180...180, "%.0f°") }
                    Btn("今の向きを入れる") { st.unfFree = st.cur6.map { ($0 * 180 / .pi).rounded() } }.help("今の 6 つの角度を、開く向きの自由の角度にうつす")
                }
                .padding(8).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            Btn("今の展開図をこの向きに") { st.unfApplyNow() }.help("今の形を、選んだ開く向きへなめらかに回す")
            Text("組む時は後半で回りながら選んだ向きに着地し、開く時は開きながら選んだ向きへ回る。4 次元のかたむき（X-W・Y-W・Z-W）が残っていると、展開図はゆがんで見える（4 次元の中の平らな展開図を、ななめから見ているため。紙をななめから見ると正方形が平行四辺形に見えるのと同じ）")
                .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder var presetBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(UIC.line)
            // プリセット
            Text("プリセット").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
            HStack(spacing: 6) {
                TextField("プリセットの名前", text: $st.asmPresetName).textFieldStyle(.roundedBorder).font(.system(size: 11))
                Btn("今の状態を保存") { st.saveSnapshotPreset() }.help("今の画面の状態をまるごと保存：形の向き・展開図の種類・組み具合・開いた時に W 消失させるか（まっすぐ）。呼び出したあとは、その向きのまま C で往復（多段階の設定は入れない）")
            }
            ForEach(st.asmPresets) { p in
                HStack(spacing: 6) {
                    Button { st.loadAsmPreset(p) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                            Text(p.snap != nil ? "状態：\((p.prog ?? 1) >= 0.5 ? "組み上がり" : "展開図")・開くと \(p.unfPose == 1 ? "まっすぐ" : "向きを保つ")" + (p.net.map { "・\($0.name)" } ?? "")
                                 : "組む \(OrigamiState.asmPoseNames[max(0, min(5, p.pose))])" + (p.vanish == 3 ? "" : "・\(OrigamiState.axisNames[max(0, min(3, p.vanish))]) が奥へ") + "・開く \(OrigamiState.unfPoseNames[max(0, min(6, p.unfPose))])" + (p.net.map { "・\($0.name)" } ?? ""))
                                .font(.system(size: 9)).foregroundStyle(UIC.sub)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("このプリセットを呼び出す")
                    Button { st.toggleLockAsm(p) } label: { Image(systemName: p.locked ? "lock.fill" : "lock.open") }.buttonStyle(.plain).foregroundStyle(p.locked ? UIC.amber : UIC.sub).help("ロック（消せないように）")
                    Button { st.deleteAsmPreset(p) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(p.locked ? UIC.sub.opacity(0.3) : UIC.sub).disabled(p.locked).help("消す")
                }
                .padding(.vertical, 3).padding(.horizontal, 6).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
