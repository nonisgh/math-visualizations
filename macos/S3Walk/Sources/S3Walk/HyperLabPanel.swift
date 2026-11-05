// 超球の窓のパネル：いつも見える段（デモ・回転・視点切りかえ…）と、9 つのタブの中身
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabView {
    var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // いつも見える段：タブと、よく使うボタン（タブの名前は仮）
            HLWrap(spacing: 8) {
                Picker("", selection: $st.panelTab) { Text("基本").tag(0); Text("見た目").tag(1); Text("切る").tag(2); Text("道").tag(3); Text("目印").tag(4); Text("地図").tag(5); Text("ダイブ").tag(6); Text("音・操作").tag(7); Text("重さ").tag(8); Text("テスト").tag(9) }
                    .pickerStyle(.segmented).frame(width: 580).labelsHidden()
                    Button(st.demoOn ? "■ デモを止める" : "▶ 超球デモ") { st.toggleDemo() }.disabled(st.diveOn)
                        .help("W 消失の真正面で、超球の中に閉じ込められた赤玉を見せ、4D の回転で表へ出す約 1 分のデモ。終わると元の向きへ戻る")
                    Button(st.shotOn ? "■ 視点切りかえを止める" : "▶ 視点切りかえ") { st.shotOn.toggle() }.disabled(st.diveOn || st.demoOn)
                        .help("左下の地図のように、Y・X・Z・W の消失の見え方へ、ぱっ、ぱっと切りかえるデモ。「回転」の 2 重回転や Z-W 回転と一緒に使える。Z-W を回している間は Z 消失を飛ばす")
                    if st.shotOn {
                        Picker("", selection: $st.shotCurve) { Text("ぱっ").tag(false); Text("カーブ").tag(true) }
                            .pickerStyle(.segmented).frame(width: 110).labelsHidden()
                            .help("つなぎ方。ぱっ：間隔ごとに切りかえる。カーブ：見え方を順に通るなめらかな曲線の上を、止まらずに流れる")
                        if st.shotCurve {
                            slider("間隔", $st.shotCurveEvery, 0.4, 10, fmt: "%.1f 秒").frame(width: 170).help("1 つの見え方から次の見え方まで")
                        } else {
                            slider("間隔", $st.shotEvery, 0.4, 5, fmt: "%.1f 秒").frame(width: 170)
                            slider("つなぎ", $st.shotEase, 0, 0.6, fmt: "%.2f 秒").frame(width: 170).help("0 にすると、1 コマで切りかわる")
                        }
                        Toggle("3D の向きも", isOn: $st.shotCam).toggleStyle(.switch).font(.caption).fixedSize()
                            .help("切りかえの時に、3D のカメラの向きも変える。切ると 4D の見え方だけが変わる")
                        Text(st.shotName).font(.caption).frame(minWidth: 84, alignment: .leading)
                    }
                    Button(st.diveOn ? "⤴ 戻る" : "⤵ ダイブ") { st.diveManual = false; st.diveOn.toggle(); st.bump() }
                        .disabled(HyperLabState.walkSource == nil)
                        .help("超ズームで、今いる所へ飛び込んで、さんぽの景色に入る（ゆっくり約 5 秒）。もう一度押すと外へ出る。キーの D でも（ほかのキー：スペースでパネルを隠す・出す、4 で球層の色を 4 方向 ⇄ レインボー）")
                Menu {
                    Toggle("4D 回転（w のからむ回転で、超球の姿を変え続ける）", isOn: $st.auto)
                    Toggle("3D 回転（今の 4D の姿のまま、3D でぐるぐる回す）", isOn: $st.spin3D)
                    Toggle("2 重回転（X-Y と Z-W の 2 つの面を同時に回す）", isOn: $st.rot2Both)
                    Toggle("Z-W 回転だけ（Z-W を回し続けて、ほかは自分で動かす）", isOn: $st.rot2ZWOnly)
                    Divider()
                    Picker("自分を追う", selection: Binding(get: { st.followKind }, set: { st.followKind = $0 })) {
                        Text("追わない").tag(0); Text("自分を追う（xyz のみ）").tag(1); Text("自分を追う（xyzw）").tag(2)
                    }.pickerStyle(.inline)
                    Divider()
                    Button("全部止める") { st.auto = false; st.spin3D = false; st.rot2On = false; st.followKind = 0 }
                } label: { Text(st.auto || st.spin3D || st.rot2On || st.followKind != 0 ? "回転中" : "回転") }.menuIndicator(.hidden).fixedSize()
                    .help("自動の回転は 4 つ：4D 回転（w のからむ回転。左の 3D の球の傾きと同じ角度）・3D 回転（4D の角度はそのままで、右の 3D のカメラを回す）・2 重回転（X-Y と Z-W の面を同時に回す。下の欄で速さを変えられる）・自分を追う（xyz のみ：超球の姿はそのままで、カメラが自分の見える側へ回り込む。xyzw：w もからめて超球を回す）。動画に撮る時は「全部止める」")
                if st.rot2On {
                    slider("X-Y の速さ", $st.rot2XY, -90, 90, fmt: "%+.0f°/秒").frame(width: 190)
                    slider("Z-W の速さ", $st.rot2ZW, -90, 90, fmt: "%+.0f°/秒").frame(width: 190)
                    HStack(spacing: 2) {
                        Button("1 : 1") { st.rot2Ratio(1) }.help("同じ速さ：クリフォード回転。全部の点が同じ速さで大円を回る")
                        Button("1 : −1") { st.rot2Ratio(-1) }.help("同じ速さで逆向き：クリフォード回転のもう一方のねじれ")
                        Button("1 : 2") { st.rot2Ratio(2) }.help("Z-W が 2 倍：X-Y が 1 周する間に Z-W が 2 周して、元の姿に戻る")
                        Button("1 : φ") { st.rot2Ratio((1 + 5.0.squareRoot()) / 2) }.help("黄金比：いつまでたっても元の姿に戻らない")
                        Button("1 : 0") { st.rot2Ratio(0) }.help("Z-W を止める：ふつうの回転。Z-W の円は動かない")
                        Button("0 : 1") { st.rot2ZWOnly = true }.help("X-Y を止める：Z-W だけを回し続ける。ほかは左の球のドラッグ（前後・左右）と面内のスライダーで動かす")
                    }
                    Picker("", selection: $st.rot2Swing) { Text("回す").tag(false); Text("ゆらす").tag(true) }
                        .pickerStyle(.segmented).frame(width: 110).labelsHidden()
                        .help("ゆらす：単振動。面内と Z-W の角度を sin で行ったり来たりさせる（真ん中は始めた時の角度。1 往復は 360 ÷ 速さ 秒、30°/秒なら 12 秒）")
                    if st.rot2Swing { slider("ゆれ幅", $st.rot2Amp, 10, 180, fmt: "%.0f°").frame(width: 170) }
                    Toggle("3D 回転", isOn: $st.spin3D).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("今の 4D の姿のまま、3D のカメラをろくろのように回す。2 重回転と一緒に使える")
                    Toggle("2 つの円", isOn: $st.rot2Rings).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("回る 2 つの面の円。だいだいが X-Y（東・北・西・南）、桃色が Z-W（アナ・天・カタ・地）。円の形は動かず、点線が円に沿って流れる")
                    if st.rot2ZWOnly {
                        slider("面内", Binding(get: { st.yaw * 180 / .pi }, set: { st.yaw = $0 * .pi / 180; st.bump() }), -180, 180).frame(width: 170)
                    }
                    Text(st.rot2Kind).font(.caption)
                }
                Button("初期位置") { st.reset() }
                RecordPanelButton()
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Button("A−") { st.zoomUI(-1) }.help("パネルを小さく（⌘−）")
                    Text(String(format: "%.0f%%", st.uiScale * 100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
                        .onTapGesture(count: 2) { st.zoomUI(0) }.help("パネルの大きさ（ダブルクリック・⌘0 で 100%）")
                    Button("A＋") { st.zoomUI(1) }.help("パネルを大きく（⌘＋）")
                }
                Button { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden = true } } label: { Label("パネルを隠す", systemImage: "rectangle.bottomthird.inset.filled") }
                    .help("パネルを隠して、画面いっぱいに超球と景色だけ（右下の「パネル」か ⌘⌥P で戻す）")
                HLStatsLabel(stats: st.stats).frame(width: 250, alignment: .trailing)   // 幅を決めておく（数字が変わってもパネルの並びを動かさない）
            }
            Group {
                switch st.panelTab {
                case 0: panelTab0
                case 1: panelTab1
                case 2: panelTab2
                case 3: panelTab3
                case 4: panelTab4
                case 5: panelTab5
                case 6: panelTab6
                case 7: panelTab7
                case 8: panelTab8
                case 9: panelTab9
                default: EmptyView()
                }
            }.frame(minHeight: 92, alignment: .topLeading)   // タブを変えても、画面の大きさが動かないように
        }
        .padding(10)
        .background(Color(red: 0.04, green: 0.06, blue: 0.11))
        .controlSize(.small)
        .onAppear {
            HyperLabState.walkShut = st.shutWalk; HyperLabState.shutAuto = st.shutAuto; HyperLabState.opModeNow = st.opMode
            // 超球の窓のショートカットキー：4 球層の色を 4 方向レインボー ⇄ レインボー、D ダイブ（自動で寄る）⇄ 戻る、スペース パネルを隠す ⇄ 出す、O 操作モード、K ナイフモード、B ドリル
            let hs = st
            HyperLabState.worldRFromWalk = { [weak hs] v in if let st = hs, abs(st.worldR - v) > 1e-9 { st.worldR = v } }
            HyperLabState.padAction = { [weak hs] a in
                guard let st = hs else { return }
                switch a {
                case "diveOn": guard HyperLabState.walkSource != nil else { return }; st.diveManual = false; st.diveOn = true
                case "diveOff": st.diveManual = false; st.diveOn = false
                case "drill": st.startDrill()
                default: return
                }
                st.bump()
            }
            HyperLabState.hyperKey = { [weak hs] c in
                guard let st = hs else { return false }
                switch c {
                case "4": st.shellMode = st.shellModeNow == 1 ? 0 : 1; return true
                case "d", "D": guard HyperLabState.walkSource != nil else { return false }; st.diveManual = false; st.diveOn.toggle(); st.bump(); return true
                case " ": st.panelHidden.toggle(); return true
                case "o", "O": st.opMode.toggle(); return true
                case "b", "B": st.startDrill(); return true
                case "k", "K": st.knifeOn.toggle(); if !st.knifeOn { st.knifeLon = nil; st.knifeDown = false }; st.bump(); return true
                default: return false
                }
            }
        }
        .onChange(of: st.shutAuto) { _, v in
            HyperLabState.shutAuto = v
            if !v { HyperLabState.walkShut = st.shutWalk; HyperLabState.hyperIdle = false }
        }
        .onChange(of: st.shutWalk) { _, v in
            guard !st.shutAuto else { return }
            HyperLabState.walkShut = v
            // 窓を勝手に前へ出すことはしない（どちらの窓でも好きに使えるように）
        }
        .onAppear { HyperLabState.wipeLow = st.wipeLow; HyperLabState.poleENNow = st.poleEN; Journey.lapClearsTrail = st.lapClear }
        .onChange(of: st.lapClear) { _, v in Journey.lapClearsTrail = v }
        .onChange(of: st.poleEN) { _, v in HyperLabState.poleENNow = v }
        .onChange(of: st.wipeLow) { _, v in HyperLabState.wipeLow = v }
        // 窓を閉じた（iPad は全画面を閉じた）：さんぽはまた描く・音も止める
        .onChange(of: st.opMode) { _, v in HyperLabState.opModeNow = v }
        .onDisappear { HyperLabState.opModeNow = false; HyperLabState.walkShut = false; HyperLabState.shutAuto = false; HyperLabState.hyperIdle = false; HyperSound.shared.stop() }
    }
    /// 基本：向き・層・座標軸
    var panelTab0: some View {
        HLWrap(spacing: 10) {
                slider("前後傾き", Binding(get: { st.pitch * 180 / .pi }, set: { st.pitch = $0 * .pi / 180; st.bump() }), -180, 180).frame(width: 170)
                slider("左右傾き", Binding(get: { st.roll * 180 / .pi }, set: { st.roll = $0 * .pi / 180; st.bump() }), -180, 180).frame(width: 170)
                slider("Z-W 傾き", Binding(get: { st.zw * 180 / .pi }, set: { st.zw = $0 * .pi / 180; st.bump() }), -180, 180).frame(width: 170)
                slider("層数", Binding(get: { Double(st.layers) }, set: { st.setLayers(Int($0.rounded())) }), 3, 61, fmt: "%.0f").frame(width: 170)
                    Toggle("球層の数をさんぽと同じに", isOn: Binding(get: { st.layersLink }, set: { on in st.layersLink = on; if on, let w = HyperLabState.walkShells { st.setLayers(w.get()) } }))
                        .toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkShells == nil)
                        .help("入れると、球層の数を球面さんぽと同じにする。さんぽで増やす・減らすとこちらも、こちらで変えるとさんぽも変わる（3〜21）")
                Picker("", selection: Binding(get: { st.mode }, set: { st.mode = $0; st.bump() })) { Text("ハイブリッド").tag(0); Text("ワイヤー").tag(1); Text("半透明").tag(2) }
                    .pickerStyle(.segmented).frame(width: 240).labelsHidden()
                Picker("", selection: Binding(get: { st.hemi }, set: { st.hemi = $0; st.bump() })) { Text("全球").tag(0); Text("北").tag(1); Text("南").tag(2) }
                    .pickerStyle(.segmented).frame(width: 140).labelsHidden()
                Picker("球層", selection: Binding(get: { st.shellMode }, set: { st.shellMode = $0; st.bump() })) {
                    Text("レインボー").tag(0); Text("4 方向").tag(1); Text("軸の色").tag(2); Text("さんぽと同じ").tag(3) }
                    .pickerStyle(.segmented).frame(width: 330).font(.caption)
                    .help("球層の色と向き。レインボー：w の向きに積んだ殻（ふだん）。4 方向：x・y・z・w のそれぞれの向きに殻を重ねる（レインボー）。軸の色：同じく 4 方向に、囲む軸の色で（x 赤・y 緑・z 青・w 紫）。左の球は z を落とすので x・y・z(w) の 3 方向。さんぽと同じ：球面さんぽの球層の色に合わせる。4 方向・軸の色は重い。キーの 4 で 4 方向 ⇄ レインボー")
                Toggle("座標軸", isOn: Binding(get: { st.axes }, set: { st.axes = $0; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("座標の矢印。左は x・y・z（z は右の w に当たるので紫）、右は x・y・z・w を超球と一緒に 4D で回す")
                Toggle("ズーム中も", isOn: Binding(get: { st.axesDive }, set: { st.axesDive = $0; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.axes)
                    .help("ダイブ（超ズーム）で寄っていく間も、座標軸と軸の名前を出す")
                Toggle("＋のみ", isOn: $st.axPlus).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.axes)
                    .help("座標軸をプラスの向きだけにする")
                Picker("", selection: $st.axThin) { Text("線").tag(true); Text("立体").tag(false) }
                    .pickerStyle(.segmented).frame(width: 90).labelsHidden().disabled(!st.axes)
                    .help("線：細い軸線と平たい矢じり。立体：つやのある管と円すいの矢印")
        }
    }
    /// 見た目：光・線・宇宙・4D の遠近
    var panelTab1: some View {
        HLWrap(spacing: 10) {
                slider("光沢", Binding(get: { st.gloss }, set: { st.gloss = $0 }), 0, 1.5, fmt: "%.2f").frame(width: 170)
                Toggle("グレア", isOn: $st.glare).toggleStyle(.switch).font(.caption).fixedSize()
                Toggle("強い反射をよける", isOn: $st.glareAuto).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("地図の殻の向きで照り返しが白いかたまりになったら、1 秒あまりテカーッと見せてから、さっと切る。その向きにいる間も、ときどきテカーッと光る。弱くなったら戻す（自動）。ダイブ画面はいつもよける")
                slider("線の太さ（ダイブ）", Binding(get: { st.wireW }, set: { st.wireW = $0 }), 0.6, 4, fmt: "%.1f").frame(width: 170)
                    .help("ダイブ画面などのワイヤー（網目の線）の太さ（画面の画素）。細いと色が薄く見え、太いと鮮やかに")
                slider("線の太さ（地図）", Binding(get: { st.wireWMap > 0 ? st.wireWMap : st.wireW }, set: { st.wireWMap = $0 }), 0.6, 4, fmt: "%.1f").frame(width: 170)
                    .help("2 枚の地図のワイヤーの太さ（画面の画素）")
                slider("線の透明度", Binding(get: { st.wireT }, set: { st.wireT = $0 }), 0, 1, fmt: "%.2f").frame(width: 170)
                    .help("ワイヤー（網目の線）の透明度。0 はそのまま、1 で見えなくなる（ダイブ画面と地図の両方）")
                Toggle("線の自動整理", isOn: $st.wireAuto).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("ダイブ画面で、線が密な所と遠い線を自動で薄くして、遠い殻を溶かし、赤星・紫星までの視線を開ける。切ると、全部の線をそのまま見せる")
                Picker("宇宙", selection: $st.spaceMode) { Text("さんぽと同じ").tag(0); Text("入").tag(1); Text("切").tag(2) }
                    .pickerStyle(.segmented).frame(width: 200).font(.caption).fixedSize()
                    .help("宇宙モード：球面さんぽと同じ 12000 個の星を超球に（右は S³ の上、左は影で球の中）、背景は宇宙、網目は光る線。さんぽと同じ：さんぽで宇宙の背景を入れている時に入る")
                slider("星の数", Binding(get: { st.starsPct }, set: { st.starsPct = $0 }), 5, 100, fmt: "%.0f%%").frame(width: 90).disabled(!st.spaceNow && st.spaceMode != 1)
                slider("星の遠近", Binding(get: { st.starDepth }, set: { st.starDepth = $0 }), 0, 1, fmt: "%.2f").frame(width: 90).disabled(!st.spaceNow && st.spaceMode != 1)
                    .help("引きの絵で、超球の向こう側の遠い星ほど透明に・ぼかす（0 で今まで通り）。半透明の時などに。ズームで寄った時は、いつも遠い星を透明に")
                Toggle("4D の遠近", isOn: $st.depth4On).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("右の超球で、4 次元で遠い所ほど、かすませる・ぼかす")
                Picker("", selection: $st.depth4) { Text("かすみ").tag(1); Text("ぼかし").tag(2); Text("両方").tag(3) }
                    .pickerStyle(.segmented).frame(width: 170).labelsHidden().disabled(!st.depth4On)
                    .help("右の超球で、4 次元で遠い所ほど：かすみ＝背景の色へ溶けて淡く、ぼかし＝網目の線が太くやわらかく淡く（ピンぼけのように）・星は大きくぼんやり。奥行きは物体の w 軸ではなく、見る人の 4 次元の視線（w′）で測る（4D で回すと、x・y・z・w の混ざった向きになる）")
                slider("強さ", Binding(get: { st.depth4K }, set: { st.depth4K = $0 }), 0, 1, fmt: "%.2f").frame(width: 90).disabled(!st.depth4On)
        }
    }
    /// 切る：断面カット・Z-W の見せ方
    var panelTab2: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("断面カット", isOn: Binding(get: { st.cutOn }, set: { on in
                    st.cutOn = on; if on && st.cutKind == 0 && st.cutRef == 2 { st.polyArm &+= 1 }; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("超球を切って中をのぞく。くさび（キャベツを切るように）・平面（輪切り）・4D（超平面で切った 3D の切り口）")
                Picker("", selection: Binding(get: { st.cutKind }, set: { k in st.cutKind = k; st.cutOn = true; if k == 0 && st.cutRef == 2 { st.polyArm &+= 1 }; st.bump() })) {
                    Text("くさび").tag(0); Text("平面").tag(1); Text("4D").tag(2) }
                    .pickerStyle(.segmented).frame(width: 170).labelsHidden()
                    .help("くさび：くさび形に切り欠く。平面：1 枚の平面より手前を消す（輪切り）。4D：見る人に固定の超平面 w′ ＝ 一定で切った 3D の切り口だけを見る（左は平面 z′ ＝ 一定と、輪がそれを貫く点）")
                if st.cutKind == 0 {
                    Picker("", selection: Binding(get: { st.cutRef }, set: { r in
                        st.cutRef = r; if r == 2 { st.polyArm &+= 1; st.cutOn = true; st.cutWDeg = 90 }; st.bump() })) { Text("画面に固定").tag(0); Text("物体に固定").tag(1); Text("ポリゴンカット").tag(2) }
                        .pickerStyle(.segmented).frame(width: 300).labelsHidden()
                        .help("画面に固定：見る人から見て同じ側を切る。物体に固定：超球の経度で切る（回すと切り口も動く）。ポリゴンカット：すいかを切るように、殻ごとの経度（y 軸のまわり）で、押した時に手前を向いている経度を中心に 90°（開き具合）ぶん切り取る。どの殻も同じ経度で切る（次に押すまで超球に固定。4D で回しても同じ 1 切れ）")
                    slider("切り欠きの位置", Binding(get: { st.cutRef == 2 ? (st.cutPhi * 180 / .pi).truncatingRemainder(dividingBy: 360) + (st.cutPhi < 0 ? 360 : 0) : st.cutAngDeg },
                                                   set: { if st.cutRef == 2 { st.cutPhi = $0 * .pi / 180; st.bump() } else { st.cutAngDeg = $0 } }), 0, 360, fmt: "%.0f°").disabled(!st.cutOn)   // ポリゴンカットは中心の経度
                    slider("開き具合", Binding(get: { st.cutWDeg }, set: { st.cutWDeg = $0.rounded() }), 10, 300, fmt: "%.0f°").disabled(!st.cutOn)
                } else {
                    if st.cutKind == 1 {
                        Picker("", selection: $st.planeDir) { Text("手前").tag(0); Text("右").tag(1); Text("上").tag(2); Text("x").tag(3); Text("y").tag(4); Text("z").tag(5) }
                            .pickerStyle(.segmented).frame(width: 250).labelsHidden()
                            .help("切る平面の向き。手前・右・上：画面に固定（見る人から見て、その側を消す）。x・y・z：物体に固定（その軸のプラス側を消す。左は球と一緒に傾く）")
                    }
                    if st.cutKind == 2 {
                        Picker("", selection: $st.cut4Axis) { Text("x′").tag(0); Text("y′").tag(1); Text("z′").tag(2); Text("w′").tag(3) }
                            .pickerStyle(.segmented).frame(width: 150).labelsHidden()
                            .help("4D で切る向き（超平面に垂直な軸）。w′：見る人の 4 次元の奥行きの向き。x′・y′・z′：層を積んだ向きと直角に切るので、殻が円になって積み重なる（左の輪を積んだ球のアナロジー）。4D で回すと斜めの切断にも")
                    }
                    slider(st.cutKind == 1 ? "切り口の位置" : ["x′", "y′", "z′", "w′"][st.cut4Axis] + " の位置", Binding(get: { st.cutPos }, set: { st.cutPos = $0; st.cutSweep = false; st.bump() }), -1, 1, fmt: "%+.2f")
                    Toggle("自動で動かす", isOn: $st.cutSweep).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("切り口をゆっくり行ったり来たりさせる（MRI の輪切りのように）")
                }
            }
            HStack(spacing: 10) {
                Toggle("ナイフ（K）", isOn: Binding(get: { st.knifeOn }, set: { st.knifeOn = $0; if !$0 { st.knifeLon = nil; st.knifeDown = false }; st.bump() })).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("ナイフモード：右の超球をドラッグすると、y 軸のまわりにその経度から切れていく（ポリゴンカットと同じ、どの殻も同じ経度）。その間ドラッグで見る向きは回さない。もう一度 K で戻る")
                Picker("", selection: $st.knifeMove) { Text("引いて広げる").tag(false); Text("付いてくる").tag(true) }
                    .pickerStyle(.segmented).frame(width: 190).labelsHidden().disabled(!st.knifeOn)
                    .help("引いて広げる：押した所からドラッグした所までが切れていく。付いてくる：開き具合ぶんの切り欠きがナイフと一緒に動く")
            }
            HStack(spacing: 10) {
                Text("Z-W を左の球で").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { st.lzw }, set: { st.lzw = $0; st.bump() })) { Text("断面").tag(0); Text("影（投影）").tag(1); Text("両方").tag(2) }
                    .pickerStyle(.segmented).frame(width: 210).labelsHidden()
                    .help("断面：z′＝0 で切った円（断面と交わらなくなると消える）。影：z の向きから見た影。輪は消えず、各層が平たい楕円体（パンケーキ）に。両方：断面の輪＋影を薄く")
            }
        }
    }
    /// 道：歩いた跡・予定の道・今いる所の印
    var panelTab3: some View {
        HLWrap(spacing: 10) {
                    Toggle("歩いた跡", isOn: $st.walk).toggleStyle(.switch).font(.caption).fixedSize()
                    Picker("", selection: $st.trailCol) { Text("桃色").tag(0); Text("白い光").tag(1); Text("軸の色").tag(2); Text("青緑").tag(3) }
                        .pickerStyle(.segmented).frame(width: 220).labelsHidden().disabled(!st.walk)
                        .help("歩いた跡の色。桃色：古い所は桃色、新しい所は白。白い光：青白から白。軸の色：その場所がいちばん近い軸の色（x 赤・y 緑・z 青・w 紫）。青緑：青緑のにじみに白っぽい芯（彗星の色）")
                    slider("跡の太さ", Binding(get: { st.trailW }, set: { st.trailW = $0 }), 0.2, 2, fmt: "×%.1f").frame(width: 90).disabled(!st.walk)
                    Toggle("光の回り込み", isOn: $st.lightWrap).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("アナ極・カタ極の近くで、光が超球を回って自分へ届く道を見せる。自分から全方向へ出た光は反対側の 1 点に集まるので、その極の色が視界いっぱいに追い上げて見える")
                        .help("球面さんぽで歩いた跡と今いる所を、右の超球（S³ そのもの）と左の球（影）に描く")
                    Toggle("1 周で跡を消す", isOn: $st.lapClear).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("1 周したら、チェックと一緒に歩いた跡も消す（その周の跡だけ残る）。1 周＝置いた目印（2 つ以上）を全部通る。目印がなければ 8 つの極を全部通る。周回は右上の隅とさんぽの窓に小さく出る")
                    Toggle("前方の跡を消す", isOn: $st.clearAhead).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("同じ道をまた通る時、今いる所（彗星）の前とすぐそばの古い跡を一時的に薄くして、今いる所を目立たせる。通り過ぎるとまた見える")
                    Toggle("予定の道", isOn: $st.planOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("決まった道（螺旋・回る輪・極めぐりなど）や自分の道（巡回）を歩いている時、これから進む道を光の点線で出す（点は進む向きへゆっくり流れ、先へ行くほど淡く）")
                    Toggle("先に道を描く", isOn: $st.railOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("決まった道・自分の道の 1 周ぶんを、歩く前から薄赤の線で描く（太さは跡の太さ）。彗星はこの上を走り、歩いた所は白っぽい青緑に塗りかわる。「1 周で跡を消す」が入っていれば、1 周で薄赤へ戻る")
                    Toggle("粗密", isOn: $st.planDense).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn)
                        .help("予定の道の矢印の間隔を、まっすぐな所は広く、カーブでは密に（急なカーブで 2.5 倍ほど）。矢印は道の上に止まったまま")
                    Toggle("道を全部", isOn: $st.planLong).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn)
                        .help("ダイブで寄った時も、左上の地図と同じように予定の道の終わりまで矢印を出す（遠くは 4D の遠近で小さく詰まって見える）。切ると、彗星の先のほどよい長さまで")
                    // 回り方は「拍・進路A・進路B」の 3 つに整理（カーブ・両方・波・らせんは選べないようにした。仕組みは残してある）
                    Picker("", selection: Binding(get: { [0, 5, 6].contains(st.spinMode) ? st.spinMode : 0 }, set: { st.spinMode = $0 })) { Text("拍").tag(0); Text("進路A").tag(5); Text("進路B").tag(6) }
                        .pickerStyle(.segmented).frame(width: 170).labelsHidden().disabled(!st.walk || !st.planOn || st.planMark != 0)
                        .help("立体の矢印の回り方。拍：彗星の音（エンジンの低いうなり）に合わせて、手前から順にドミノのように回る。カーブ：道が曲がっている所の矢印が、曲がる向きへ自分から回り続ける（右へ曲がる所は右回り、左は左回り。急なほど速く。まっすぐな所は止まる）。両方：その両方。波：傾きがサインカーブの波になって手前から先へ伝わる（拍に合わせて）。らせん：1 枚ごとにねじれて並び、鎖全体が拍に合わせて回り続ける。進路A：今走っている向きと矢印の向きの角度で、平行なら立って薄く、直角なら寝て面が見える（まっすぐ先ほど薄く）。進路B：その逆で、直角なら立って線に見える（遠くでカーブしている板ほどひねったテープのように薄く）。どちらも進むにつれて次々に寝たり起き上がったりする（回らない。ゆがんだ矢印のスピード感を生かす）。回っている間は光る")
                    Toggle("球殻の色に染まる", isOn: $st.planShell).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk || !st.planOn || st.planMark != 0)
                        .help("立体の矢印を、その場所の球殻の色にほんのり染める（緑の所なら半透明の緑）。切ると、手前から奥へ軸の 4 色のグラデーション")
                    Picker("", selection: $st.planMark) { Text("立体の矢印").tag(0); Text("楕円の光").tag(1); Text("金平糖").tag(2) }
                        .pickerStyle(.segmented).frame(width: 190).labelsHidden().disabled(!st.walk || !st.planOn)
                        .help("予定の道の目印。立体の矢印：厚みのある「»」、青白にほんのり軸の色。向きは S³ の上で道に沿って平行移動で運ぶ（まっすぐな所でそろい、道のねじれに合わせてねじれる）。楕円の光：暖かい白、まっすぐな所で進む向きに伸びる。金平糖：青白にほんのり軸の色、くるくる回る")
                    Picker("", selection: $st.cursor) { Text("さんぽ").tag(0); Text("彗星").tag(1); Text("大彗星").tag(4); Text("巨大彗星").tag(3); Text("線の彗星").tag(2) }
                        .pickerStyle(.segmented).frame(width: 310).labelsHidden().disabled(!st.walk)
                        .help("今いる所の印。さんぽ：青緑と白の三重の輪。彗星：光で描く（白く飛んだ核と青緑のコマ、ぼけてすじの流れる尾）。大彗星：引きの絵では大きな光の玉の中に、白い頭と尾のふつうの彗星（どこにいるかひと目でわかる）。巨大彗星：光の玉をさらに大きく（ダイブ中の全体像でも目立つ）。大彗星・巨大彗星もダイブで寄るとふつうの彗星。線の彗星：線で描いた前の形")
        }
    }
    /// 目印：目印・極・座標
    var panelTab4: some View {
        HLWrap(spacing: 10) {
                    Toggle("通過のテロップ", isOn: $st.passOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("極のそばを通ると、左上に「Ana Pole（アナ極）通過」のように 3 秒ほど出す。スマホで動画を見ても読める大きさ。動画にも入る")
                    Toggle("解説のテロップ", isOn: $st.noteOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("赤玉・紫玉へ近づいた時に、上の地図の下へ短い解説を出す。動画にも入る")
                    Toggle("目印", isOn: $st.marksOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("球面さんぽで置いた目印。歩いて通った目印（チェックポイント）は塗りつぶしと ✓、まだの目印は輪")
                    Toggle("光で描く", isOn: $st.symGlow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.marksOn && st.polesMode == 0)
                        .help("極と目印を光る星で描く（通った所は白く光る星に極の色がほんのり、十字のきらめき。まだの所は光の輪。ゆっくりまたたく）。切ると前の丸と輪")
                    Picker("極", selection: $st.polesMode) { Text("出さない").tag(0); Text("通ると出る").tag(1); Text("いつも").tag(2) }
                        .pickerStyle(.segmented).frame(width: 210).font(.caption)
                        .help("8 つの極（アナ極・カタ極・東西南北・天・地）。通ると出る：歩いて通った極だけ ✓ つきで出てくる。いつも：全部出し、通った極は ✓")
                    Toggle("英語", isOn: $st.poleEN).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("極の名前を英語に（セリフ体で小さく）：Ana・Kata・North・South・East・West・Zenith・Nadir。さんぽの景色の画面も")
                    Toggle("座標", isOn: $st.coordOn).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("走行中の座標を右の画面の左上に（S³ の上の x・y・z・w、アナ極からの角度、いちばん近い極、速さ）。計器のように書きかわる")
        }
    }
    /// 地図：画面の並び・2 枚の地図
    var panelTab5: some View {
        HLWrap(spacing: 10) {
                    Toggle("自分が真ん中", isOn: $st.naviCenter).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの間、上の地図を車のナビのように：自分がいつも真ん中で背景が動き、進む向きが上。赤い玉へ向かうと赤い玉が近づき、裏から紫の玉が寄ってくる。赤い玉・紫の玉のそばを通る間は、間の球層が透けて重なる所が見える（ほかの極星は軽く）")
                    Toggle("重なりの光", isOn: $st.overlapGlow).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("地図で赤玉と紫玉が重なる時に、2 つの色の光の円が近づいて、重なった所が白く光る。切ると、殻をそのまま見せる")
                    Toggle("カーソルのまわりを抜く", isOn: $st.holeOn).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("上の地図で、カーソルのまわりの円に収まる網目を、奥行きの全部にわたってポリゴンごと抜く")
                Toggle("地図 2 枚", isOn: $st.map2).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの間、さんぽの景色の場所を下の地図にする（上は自分地図：自分を追う。下は軸を消失させた地図）。切ると、さんぽの景色に戻す")
                    Toggle("さんぽの景色", isOn: $st.walkView).toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("さんぽの窓と同じ景色（今いる所から見た S³）を、画面を割って出す")
                    Picker("", selection: $st.wipeLow) { Text("低負荷").tag(true); Text("きれい").tag(false) }
                        .pickerStyle(.segmented).frame(width: 120).labelsHidden().disabled(!st.walkView)
                        .help("さんぽの景色の画面（ワイプ）の描き方。低負荷：画素は半分（超球の方に力を回す）。きれい：画面の細かさ。どちらも 1 秒 60 コマ")
                    Picker("", selection: $st.lowView) { Text("さんぽの景色").tag(0); Text("ダイブ画面").tag(1); Text("両方").tag(2) }
                        .pickerStyle(.segmented).frame(width: 240).labelsHidden().disabled(!st.walkView)
                        .help("ダイブしていない間に出す画面。ダイブ画面：景色の場所にダイブの絵を出す。両方：上にダイブ画面、下にさんぽの景色（3D の球はその間消える。超球の窓のレイアウトの動画にも入る）。どちらも少し重くなる。ダイブ中は今まで通り")
                    Toggle("上下を入れかえ", isOn: $st.lowSwap).toggleStyle(.switch).font(.caption).fixedSize().disabled(st.lowView != 2)
                        .help("両方の時に、上にさんぽの景色、下にダイブ画面を出す")
                    Toggle("3D の球", isOn: $st.show3D).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("左の 3D の球（リングを積む）を出す。切ると、さんぽの景色と 4D の超球だけの並びに")
                    Button("⟳ 並び") { let o = st.order; st.order = [o[2], o[0], o[1]] }
                        .help("3 つの画面（3D の球・さんぽの景色・4D の超球）の置き場所を順に回す（左上 → 左下 → 右）")
                    Toggle("下の地図の動き", isOn: $st.ovShow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.walk)
                        .help("下の地図の演出。いつも水平（アナ極が上、球層は横に重なる）で、奥へ向かう動きや上り下りには、カメラがゆっくり回り込む。w に沿って中を上り下りする間は、間の殻を消して、赤玉・紫玉の側だけを残す。地図の奥深くを横へ通る時は、ときどき手前を切って中を見せる。玉の近くを w に沿って上り下りする時は、ときどき地球の断面図のように 90° 開いて中を見せる")
                    Toggle("ダイブ中は全体像", isOn: $st.diveOverview).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブしている間、3D の球の場所に、外から見た超球の全体像を出す（どこを走っているかを見ながらダイブできる）。3D の球を出している時だけ")
                    Picker("", selection: $st.ovCursor) { Text("同じ").tag(-1); Text("さんぽ").tag(0); Text("彗星").tag(1); Text("大").tag(4); Text("巨大").tag(3); Text("線").tag(2) }
                        .pickerStyle(.segmented).frame(width: 245).labelsHidden().disabled(!st.diveOverview)
                        .help("全体像の今いる所の印。同じ：ふつうと同じ。さんぽ：青緑と白の三重の輪（遠くからでも見つけやすい）。彗星・線：光の彗星・線の彗星")
        }
    }
    /// ダイブ：自分を追う・カメラ
    var panelTab6: some View {
        HLWrap(spacing: 10) {
                    Menu(st.followXYZ ? "自分を追う（xyz のみ）" : st.followOn ? (st.followSlack < 1 ? "追う：いつも中心" : String(format: "追う：遊び %.0f°", st.followSlack)) : "自分を追う") {
                        Button("いつも中心（さんぽの自分中心と同じ）") { st.followOn = true; st.followSlack = 0; st.followHeading = true }
                        Button("奥に行ったら回す（手前の半分は自由）") { st.followOn = true; st.followSlack = 90; st.followHeading = false }
                        Button("自分を追う（xyz のみ：カメラが回り込む）") { st.followXYZ = true }
                        Button("自由（追わない）") { st.followKind = 0 }
                        Divider()
                        Toggle("進む向きも合わせる", isOn: $st.followHeading)
                    }.fixedSize().help("さんぽで歩く自分を、超球の手前に保つ。遊び：真ん中からどこまで自由に動けるか。0° ならいつも中心、90° なら奥（4D の裏）へ行きかけた時だけ回す")
                    if st.followKind != 0 {
                        slider("遊び", Binding(get: { st.followSlack }, set: { st.followSlack = $0.rounded() }), 0, 150, fmt: "%.0f°").frame(width: 120)
                        slider("戻す速さ", Binding(get: { st.followSpeed }, set: { st.followSpeed = $0 }), 0.2, 3, fmt: "%.1f").frame(width: 120)
                        slider("ゆるく回す", Binding(get: { st.followDrift }, set: { st.followDrift = $0 }), 0, 1, fmt: "%.2f").frame(width: 120)
                            .help("遊びの中でも、弱い力で少しずつ自分の方へ回り続ける。0 で遊びの中は止まる")
                    }
                    slider("ズーム", Binding(get: { st.diveT }, set: { st.diveManual = true; st.diveT = $0; st.diveOn = $0 > 0.5; st.bump() }), 0, 1, fmt: "%.2f").frame(width: 120)
                    Picker("", selection: Binding(get: { st.diveThird }, set: { st.diveThird = $0; st.bump() })) { Text("一人称").tag(false); Text("三人称").tag(true) }
                        .pickerStyle(.segmented).frame(width: 120).labelsHidden()
                        .help("ダイブの行き先。一人称：自分の目へ（さんぽの景色）。三人称：斜め後ろの少し上で止まって、走る自分（彗星）を追う")
                    Picker("", selection: Binding(get: { st.diveSpin }, set: { st.diveSpin = $0; st.bump() })) { Text("ふつう").tag(0); Text("くるくる").tag(1); Text("ぐるぐる").tag(2) }
                        .pickerStyle(.segmented).frame(width: 190).labelsHidden()
                        .help("ダイブの回り方。くるくる：入る間に、画面の右と 4 次元の奥の面でもう 1 周回って入る（4 次元をくるっと宙返り）。ぐるぐる：2 周。寄り切った時の向きはふつうと同じ")
                    if st.diveThird {
                        slider("後ろ", Binding(get: { st.chaseDist }, set: { st.chaseDist = $0; st.bump() }), 0.1, 2, fmt: "%.2f").frame(width: 100)
                        slider("見下ろす", Binding(get: { st.chasePitch }, set: { st.chasePitch = $0; st.bump() }), -70, 80, fmt: "%+.0f°").frame(width: 100)
                            .help("上から見下ろす角度。マイナスにすると、下から見上げる")
                        slider("斜め", Binding(get: { st.chaseYaw }, set: { st.chaseYaw = $0; st.bump() }), -90, 90).frame(width: 100)
                    }
                    slider("勢い", Binding(get: { st.feelK }, set: { st.feelK = $0 }), 1, 3, fmt: "×%.1f").frame(width: 100)
                        .help("本当の速さは変えず、音・尾・揺れ・彗星の派手さだけ、この倍率の速さのように見せる。×1 で本当の速さのまま")
                    Toggle("空気", isOn: $st.airOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("彗星のまわりの空気をナビエ・ストークス方程式で解く（2 次元の断面）。渦のゆれが音の息づかいとカメラの揺れになる。切ると今までの音と揺れ")
                    Toggle("コースター", isOn: $st.coaster).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("アナ極を高い所、カタ極を低い所として、下りで加速・上りで減速する。道の形は同じで、1 周の時間だけ変わる")
                    Toggle("星の音", isOn: $st.dopplerOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("極に近づくと高く、通り過ぎると低くなるドップラーの音。カタ星は後ろから追いかけてきて追い抜く。本当は鳴らないのでエンタメ")
                    slider("星の大きさ", Binding(get: { st.dopK }, set: { st.dopK = $0 }), 0.2, 2, fmt: "%.1f").frame(width: 100).disabled(!st.dopplerOn)
                    slider("メリハリ", Binding(get: { st.meriK }, set: { st.meriK = $0 }), 0, 1, fmt: "%.1f").frame(width: 100)
                        .help("設定の速さを全体の平均にして、直線で速く、カーブで遅くする。0 で一定の速さ")
                    slider("上限", Binding(get: { st.topK }, set: { st.topK = $0 }), 1.2, 2.5, fmt: "×%.1f").frame(width: 100).disabled(st.meriK == 0)
                        .help("直線で平均の何倍まで速くなるか。近づくほど加速がゆるむ（空気の抵抗）ので、長い直線でも上がり続けない")
                    Toggle("メーター", isOn: $st.meterOn).toggleStyle(.switch).font(.caption).fixedSize()
                    Toggle("動画にも", isOn: $st.meterVideo).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.meterOn)
                    slider("揺れ", Binding(get: { st.shakeK }, set: { st.shakeK = $0 }), 0, 3, fmt: "×%.1f").frame(width: 100).disabled(!st.diveThird)
                        .help("ズーム（三人称）で疾走している時のカメラの揺れ。速いほど細かく震えて、きついカーブでは強く揺れる。×0 でなし")
                    Toggle("シースルー", isOn: $st.seeThrough).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブ ⇄ 超球の変形の間、左の窓を暗く透かして、右の絵の続きを見せる")
                    Toggle("オートカメラ", isOn: $st.autoCam).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird)
                        .help("ズーム（三人称）の時、よく見える角度へ自動で：ゆっくり周りを漂い、曲がる時は外側へ回り込む。きついカーブや垂直に近い動きの時は、水平の目線から真上近くへ大きく展開して、曲がる道すじ全体を見せる（ダイナミック）。ドラッグで回すとその間は止まる")
                    Toggle("ショーカメラ", isOn: $st.camShow).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird || !st.autoCam)
                        .help("オートカメラの仲間：カーブが近づくと彗星の真後ろの低い所へ回り込んで、ターンを後ろから見せる。まっすぐな所では 7 秒ごとにランダムに、大きく引いた全体も交えて、斜め右上（傾ける）・右の真横・真上の近く・斜め左上（傾ける）・左の真横・高く引いた全体・低い斜め後ろ、と角度を切りかえる。下から見上げて、彗星を画面の左上・右上に置く構図も（極めぐりのショーと相性がいい）")
                    Picker("", selection: $st.showMode) { Text("A").tag(0); Text("B").tag(1) }
                        .pickerStyle(.segmented).frame(width: 70).labelsHidden().disabled(!st.diveThird || !st.autoCam || !st.camShow)
                        .help("ショーカメラの演出。A：いろいろな構図を順に回して、カーブでは真後ろの斜めに構える。B：ジェットコースターのように、先の落ち込み・昇り・急カーブを読んで先回りする（落ち込みでは前の高い所へ舞い上がり、向かってくる彗星を見下ろす）。どちらもゆっくり落ち着いて動く")
                    Toggle("景色に溶かす", isOn: $st.diveBlend).toggleStyle(.switch).font(.caption).fixedSize()
                        .disabled(st.diveThird).help("ダイブの最後に、さんぽの景色へ溶け込ませる（一人称の時）。切ると、寄ったまま超球の網目（4D の外から見た姿）で見続けられる（左下の景色と見比べに）")
        }
    }
    /// 音・操作
    var panelTab7: some View {
        HLWrap(spacing: 10) {
                    Toggle("音", isOn: $st.soundOn).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("音を出す：彗星が空気を押し切って走る風切り音（速いほど高く大きく・重く、曲がる時は外側へ風が流れてひと吹き強まる、ズームで寄るほど大きく）と、チェックポイントに当たった時の「チリン」")
                    slider("音量", Binding(get: { st.soundVol }, set: { st.soundVol = $0 }), 0, 1, fmt: "%.2f").frame(width: 80).disabled(!st.soundOn)
                    slider("場所の音", Binding(get: { st.soundPlace }, set: { st.soundPlace = $0 }), 0, 1, fmt: "%.2f").frame(width: 120).disabled(!st.soundOn)
                        .help("w の高さで音色が変わる（アナ極の側は明るく軽く、カタ極の側は暗く重く）。0 でなし")
                    Toggle("ダイブの外でも走る音", isOn: $st.soundFar).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.soundOn)
                        .help("ダイブしていない時も、彗星が走る音を小さく鳴らす。切ると、ダイブの外はほとんど聞こえない")
                    slider("外の大きさ", Binding(get: { st.soundFarK }, set: { st.soundFarK = $0 }), 0.05, 0.6, fmt: "%.2f").frame(width: 120).disabled(!st.soundOn || !st.soundFar)
                    Toggle("球層を横切る音", isOn: $st.soundLayer).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.soundOn)
                        .help("球層を横切るたびに、小さく「スッ」と鳴る")
                    slider("線路の音", Binding(get: { st.soundRail }, set: { st.soundRail = $0 }), 0, 2, fmt: "×%.1f").frame(width: 120).disabled(!st.soundOn)
                        .help("光の矢印を通るたびに、線路のつなぎ目のように「カタン」とかすかに鳴る。矢印が見えるダイブの間だけ")
                    slider("渦の歌", Binding(get: { st.soundSong }, set: { st.soundSong = $0 }), 0, 2, fmt: "×%.1f").frame(width: 120).disabled(!st.soundOn)
                        .help("彗星のまわりのナビエ・ストークスの渦を波形にして鳴らす。速いほど高く、直線でさらに伸びる。カーブでは渦が崩れて音色が荒れる")
                    slider("風の音", Binding(get: { st.soundWind }, set: { st.soundWind = $0 }), 0, 1, fmt: "×%.1f").frame(width: 120).disabled(!st.soundOn)
                        .help("ゴーッ・シューなどの風の音の大きさ。×1.0 が今までの風。プープーの機械の音はこのままで鳴る")
                    slider("低音", Binding(get: { st.soundBass }, set: { st.soundBass = $0 }), 0.3, 3, fmt: "×%.1f").frame(width: 120).disabled(!st.soundOn)
                        .help("低いうなり・ゴーッ・ばたつき・エンジンの低い音をまとめて強める。×1.0 が元のまま")
                    slider("荒さ", Binding(get: { st.soundRough }, set: { st.soundRough = $0 }), 0, 2.5, fmt: "×%.1f").frame(width: 120).disabled(!st.soundOn)
                    slider("直線の加速", Binding(get: { st.soundRush }, set: { st.soundRush = $0 }), 0, 2, fmt: "×%.1f").frame(width: 130).disabled(!st.soundOn)
                        .help("まっすぐ走り続けるほど突進音が強まり、エンジンの音が上がり、ガラララが速くなる。アナ極・カタ極へまっすぐ向かう時はもっと強く。曲がると消えて風切りの音になる。0 で切る")
                    Toggle("ヘッドホン用", isOn: $st.soundPhones).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.soundOn)
                        .help("ガラララを少し高い音にして強め、打つ瞬間だけ低音を下げる。ヘッドホンの低音に隠れにくくなる。スピーカーで聞く時は切る")
                        .help("疾走する時の「ガラララッ」という荒い連打の音。速いほど強く、カーブで強まる。×0 でなし")
                    Toggle("空間オーディオ", isOn: $st.soundSpatial).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.soundOn)
                        .help("彗星のいる方向から音が聞こえる（ヘッドホンだと左右だけでなく上下・前後も。広い場所の残響を少し）。切ると左右だけのステレオ")
                    Toggle("さんぽメニュー", isOn: $st.walkMenu).toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("この窓に、さんぽの操作の小窓を浮かべる（歩く・止まる・速さ・目印・跡を消す・アナ極へ・決まった道）。✕ で隠す")
                    Toggle("ゲームパッド", isOn: Binding(get: { st.padOn }, set: { on in st.padOn = on; if !on { HyperLabState.walkRendererGet?()?.game.vClear() } }))
                        .toggleStyle(.switch).font(.caption).fixedSize().disabled(HyperLabState.walkRendererGet?() == nil)
                        .help("画面のゲームパッドを出す（さんぽの窓と同じ。押すとコントローラーと同じ働きで歩く）。パネルを隠していても出る")
                    Toggle("操作モード", isOn: $st.opMode).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ダイブの画面を見ながら、さんぽの窓と同じように歩く（キーの W・A・S・D・矢印、コントローラーのスティック・ボタンがみんな歩く操作に。スティックでカメラは回さない）。キーの O で入る（操作モードの間は、D・O などのキーはさんぽの操作なので、切るのはこのスイッチで）")
                    Toggle("カメラをコントローラーで", isOn: $st.padCam).toggleStyle(.switch).font(.caption).fixedSize().disabled(!st.diveThird)
                        .help("ズーム（三人称）の間、コントローラーのスティックで自分（彗星）のまわりのカメラを回す（離すとゆっくり元の角度へ）。オートカメラ・ショーカメラは止めず、その上に足す。そのスティックは歩くのには使わない")
                    Picker("", selection: $st.padCamStick) { Text("左").tag(0); Text("右").tag(1); Text("両方").tag(2) }
                        .pickerStyle(.segmented).frame(width: 110).labelsHidden().disabled(!st.padCam || !st.diveThird)
                        .help("カメラを回すスティック（手で持った時の左右）")
        }
    }
    /// 重さ：画質・止める窓
    var panelTab8: some View {
        HLWrap(spacing: 10) {
                Toggle("ヘビー", isOn: $st.heavy).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("ヘビーモード：色はそのままで、ダイブの殻を細かく描く（網目を 2 倍に・地平線のふちを画素ごとに・画質を自動で下げない）。GPU をたくさん使う")
                Picker("静かさ", selection: $st.hyperQ) { Text("さんぽに合わせる").tag(0); Text("静か").tag(1); Text("高画質").tag(2) }
                    .pickerStyle(.segmented).frame(width: 280).font(.caption)
                    .help("この窓の描き方。さんぽに合わせる：さんぽの静かモードの時だけ静か。静か：いつも静か（コマ数を少し下げる。144Hz の画面なら 72 → 48。さんぽの景色の画面は 30 コマ。描く画素は減らさないので、色や線の見え方は変わらない）。高画質：さんぽが静かモードでも、この窓はいつもなめらかに")
                Picker("画質", selection: $st.quality) { Text("自動").tag(0); Text("高").tag(1); Text("中").tag(2); Text("低").tag(3) }
                    .pickerStyle(.segmented).frame(width: 190).font(.caption)
                    .help("描く画素の数。自動：コマ数が目標に届かない時は下げ、余裕が戻ったら上げる（なめらかさ優先）")
                Toggle("省電力", isOn: $st.adaptive).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("止まっている間は 1 秒 10 コマに落とし、動かすとすぐ画面のいちばん速いコマ数に戻す（iPhone の ProMotion のように）")
                Toggle("前の窓だけ描く（自動）", isOn: $st.shutAuto).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("今前にある窓の景色と地図だけを描く：超球の窓が前なら、さんぽの窓はオフ（真っ暗）。さんぽの窓が前なら、さんぽの景色と地図を描いて、この窓はオフ（真っ暗）。窓を選ぶと瞬時に切りかわる")
                Toggle("さんぽの窓は止める（この窓だけで描く）", isOn: $st.shutWalk).toggleStyle(.switch).font(.caption).fixedSize().disabled(st.shutAuto)
                    .help("重い時に。（歩くキーはこの窓でそのまま効く）。さんぽの窓（景色・地図）は真っ黒にして描かず、GPU をこの窓（超球・さんぽの景色の画面・ダイブ）だけに使う。この窓も 1 秒 72 コマ（120Hz の画面は 60）までにして静かに。この窓を閉じると、さんぽはまた描く。歩く計算・跡・目印・自分を追うはそのまま（コントローラーで歩ける）")
        }
    }
    func slider(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, fmt: String = "%+.0f°") -> some View {
        HLSlider(name: name, value: v, lo: lo, hi: hi, fmt: fmt)
    }
    /// テスト：試作の置き場（超球を詰める・超球面拡張）
    var panelTab9: some View {
        HLWrap(spacing: 10) {
                Button(st.fillOn ? "■ 超球をやめる" : "▶ 超球を詰める（試作）") { st.toggleFill() }.disabled(st.diveOn)
                    .help("半径のちがう超球面を 10 枚、外から中心へ敷き詰めて、超球の中身まで見せる試作。殻の数だけ重くなる")
                if st.fillOn {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text(String(format: "体積 %.2f / %.2f（%.1f%%）", HyperLabState.fillVolume(st.fillA), HyperLabState.fillVolume(0), (1 - pow(st.fillA, 4)) * 100)).font(.caption.monospacedDigit())
                    }
                }
                if st.fillOn {
                    slider("詰める数", Binding(get: { Double(st.fillCount) }, set: { st.fillCount = Int($0.rounded()); st.bump() }), 2, 30, fmt: "%.0f")
                        .help("外の R ＝ 1 から中心へ、等しい間隔で何枚の超球面を詰めるか（ふつう 10 枚）。重さは「詰める数 × 内側の球層」。内側の球層を自動にしておくと、詰める数を増やしても重さが同じくらいになるよう、内側の球層が減る")
                }
                if st.fillOn || st.expandOn {
                    slider("内側の球層", Binding(get: { Double(st.fillLayers) }, set: { st.fillLayers = Int($0.rounded()); st.fillAuto = false; st.bump() }), 1, Double(max(2, st.layers)), fmt: "%.0f")
                        .help("内側の超球（詰める・拡張のステージ）を、R ＝ 1 の層の数のうち何層ぶん描くか。いちばん右で R ＝ 1 と同じ。多いほど重い。動かすと自動は切れる")
                    Toggle("自動", isOn: $st.fillAuto).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("内側の球層を自動で（VBR）：重くてコマ数が落ちる時は 1 枚ずつ減らし、コマ数・画質がいっぱいで GPU に 4 割の余裕があれば、R ＝ 1 の層の数まで 1 枚ずつ増やす")
                }
                Button(st.expandOn ? "■ 拡張をやめる" : "▶ 超球面拡張（試作）") { st.expandOn.toggle(); st.bump() }.disabled(st.diveOn)
                    .help("超球の中の小さい S³（ステージ：半径 0.8・0.6・0.4・0.2）と、下のステージへの入口のブラックホールを見せる。黒い玉が入口、紫の線が下のステージへの穴、白い輪が出口。第 1 段階は外から見る絵だけ")
                if st.expandOn {
                    Picker("光らせるステージ", selection: $st.stageView) { ForEach(0..<HyperLabState.stageR.count, id: \.self) { i in Text(i == 0 ? "外 R 1" : String(format: "R %.1f", HyperLabState.stageR[i])).tag(i) } }
                        .pickerStyle(.segmented).frame(width: 330).font(.caption)
                        .help("どのステージを光らせるか（第 2 段階で、彗星が今いるステージになる）")
                    Toggle("ほかのステージを消す", isOn: $st.stageOnly).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("光らせるステージの S³ とブラックホールだけを描く。内側のステージも、外の超球と同じに全部の層と網目で描くので、1 つのステージの形がよく見える")
                }
                Picker("いる世界", selection: Binding(get: { HyperLabState.stageR.indices.min(by: { abs(HyperLabState.stageR[$0] - st.worldR) < abs(HyperLabState.stageR[$1] - st.worldR) }) ?? 0 },
                                                   set: { i in st.worldR = HyperLabState.stageR[i]; st.stageView = i; st.bump() })) {
                    ForEach(0..<HyperLabState.stageR.count, id: \.self) { i in Text(i == 0 ? "外 R 1" : String(format: "R %.1f", HyperLabState.stageR[i])).tag(i) } }
                    .pickerStyle(.segmented).frame(width: 380).font(.caption)
                    .help("R の世界へ行く：超球の中の半径 R の S³ を歩く。自分の大きさはそのままなので、R が小さいほど速く 1 周し、さんぽの景色の目印・極の惑星が近く大きく見える。超球の窓の彗星・跡・目印もその S³ の上に")
                slider("いる世界の R", Binding(get: { st.worldR }, set: { st.worldR = ($0 * 1000).rounded() / 1000; st.bump() }), 0.05, 1, fmt: "%.3f").disabled(st.drillOn)
                HStack(spacing: 6) {
                    Button("▼ 降りる") { st.glideDir = st.glideDir == -1 ? 0 : -1 }.tint(st.glideDir == -1 ? Color(red: 1, green: 0.6, blue: 0.3) : nil)
                        .help("R の小さい世界へ、なめらかに降りていく（歩きながらだと、らせん階段のように）。もう一度押すと止まる。いちばん下（R 0.05）では減速して着地")
                    Button("▲ 上る") { st.glideDir = st.glideDir == 1 ? 0 : 1 }.tint(st.glideDir == 1 ? Color(red: 0.4, green: 0.8, blue: 1) : nil)
                        .help("外の世界（R 1）へ、なめらかに上っていく。もう一度押すと止まる")
                    Button("■") { st.glideDir = 0 }.help("その R で、すっと減速して止まる")
                    slider("速さ", Binding(get: { st.glideSpeed }, set: { st.glideSpeed = $0 }), 0.2, 3, fmt: "×%.1f").frame(width: 100)
                    if st.glideDir != 0 { Text(String(format: "%@ R %.3f", st.glideDir < 0 ? "降下中" : "上昇中", st.worldR)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }.disabled(st.drillOn)
                Button(st.drillOn ? "ドリル中…" : "▶ ドリル（B）") { st.startDrill() }.disabled(st.drillOn || st.runOn)
                    .help("今いる所から超球の中心をまっすぐ通って、反対側の点まで掘り進む（R は今の R → 0.05 → 今の R）。中心（特異点）で反対側の点へ抜ける。ダイブ中は少し引いて、殻のあいだを落ちていくのを見せる。掘っている間は歩かない")
                Picker("ドリルの道", selection: $st.drillTour) { Text("なし").tag(0); Text("往復ドリル").tag(1); Text("D の字めぐり").tag(2) }
                    .pickerStyle(.segmented).frame(width: 270).font(.caption).disabled(st.runOn)
                    .help("往復ドリル：中心を通って反対側へ抜け、少し止まって、また中心を通って戻る（ふりこのように行ったり来たり）。D の字めぐり：中心を通るドリル（長さ 2）で反対側へ、地表をまっすぐ半周（π）歩いて元の所へ。1 回りで D の字をかく。なしで止める")
                HStack(spacing: 10) {
                    Button(st.runOn ? "■ 超球ランを止める" : "▶ 超球ラン") { st.runOn.toggle() }.disabled(st.drillOn && !st.runOn)
                        .tint(st.runOn ? Color(red: 1, green: 0.6, blue: 0.3) : nil)
                        .help("スター・ウォーズのように：外の殻の表面すれすれを飛び、穴から殻と殻のすき間（トンネル）へ、すき間を飛んでまた次の穴へ、…、中心の炉を抜けて反対側へまっすぐ脱出、をくり返す。自分を通る 4D の断面（上下・前後・左右）で見るので、中心の向きがそのまま画面の下")
                    Toggle("トンネルで見る（ラン・ドリル）", isOn: $st.tunnelView).toggleStyle(.switch).font(.caption).fixedSize()
                        .help("ドリル・往復ドリル・D の字めぐりも、超球ランと同じトンネル（自分を通る 4D の断面）で見る。通る殻に穴があく")
                }
                Toggle("鏡の世界", isOn: $st.drillMirror).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("ドリルで中心を抜ける時に、体を回さずに（体の向きのまま）つきぬける。反対側では、世界に対して自分が鏡写しになって、さんぽの景色の右と左が入れかわる。もう一度抜けると元にもどる。切っている時は、4 次元で 180° 宙返りして抜けるので鏡写しにならない")
                Toggle("内核の演出", isOn: $st.chaosOn).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("R が小さい殻ほど、地球の内核のように焼けた鉄の色（明るさはそのまま）・かげろうのようにゆらぐ網目・脈打つ明るさに。R の世界・ドリル・この R だけ・拡張のステージで効く")
                Toggle("この R だけ表示", isOn: $st.rOnly).toggleStyle(.switch).font(.caption).fixedSize()
                    .help("つまみで選んだ半径 R の S³ だけを描く（ステージのほかの R も見られる）")
                if st.rOnly {
                    slider("R", Binding(get: { st.rOnlyR }, set: { st.rOnlyR = max(0.05, $0); st.bump() }), 0.05, 1, fmt: "%.2f")
                }
        }
    }
}
