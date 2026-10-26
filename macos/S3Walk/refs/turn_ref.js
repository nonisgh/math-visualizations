const TAU = Math.PI * 2;
const dot = (a, b) => a.reduce((s, x, i) => s + x * b[i], 0);
const add = (a, b, t) => a.map((x, i) => x + b[i] * (t === undefined ? 1 : t));
const scl = (a, k) => a.map(x => x * k);
const nrm = a => { const l = Math.sqrt(dot(a, a)) || 1; return a.map(x => x / l); };
const d2r = Math.PI / 180;
const [mode, style, N, ds, every] = [process.argv[2], process.argv[3], +process.argv[4], +process.argv[5], +process.argv[6]];
const S = { fillMode: mode, turnStyle: style, az: 0, el: 0 };
let W = {}, W2 = {};
const FIXED = [], poleName = () => '?', say = () => {}, req = () => {}, starOn = () => false;
function resetNorth() { Object.assign(W, { p: [0, 0, 0, 1], r: [0, 1, 0, 0], u: [0, 0, 1, 0], f: [1, 0, 0, 0], trail: [] }); Object.assign(W2, { p: [0, 0, 1], r: [0, 1, 0], f: [1, 0, 0], trail: [] }); }
function step(d, d2, s) { moveAlong(W, d, s); if (d2) moveAlong(W2, d2, s); }
function moveAlong(X, d, s) {
    const c = Math.cos(s), sn = Math.sin(s);
    const d2 = add(scl(X.p, -sn), d, c);                 // 進んだ先での d
    X.p = nrm(add(scl(X.p, c), d, sn));
    for (const k of ['r', 'u', 'f']) { if (!X[k]) continue; const t = X[k]; const a = dot(t, d); X[k] = nrm(add(add(t, d, -a), d2, a)); }
    // 直交を保つ（誤差がたまらないように）
    for (const k of ['r', 'u', 'f']) { if (!X[k]) continue; let t = add(X[k], X.p, -dot(X[k], X.p)); for (const j of ['r', 'u', 'f']) { if (j === k) break; if (X[j]) t = add(t, X[j], -dot(t, X[j])); } X[k] = nrm(t); }
}
function orthoFrame(X) {   // 点 p を動かした後、体の枠を p に直交・正規直交に直す
    for (const k of ['r', 'u', 'f']) { if (!X[k]) continue; let t = add(X[k], X.p, -dot(X[k], X.p)); for (const j of ['r', 'u', 'f']) { if (j === k) break; if (X[j]) t = add(t, X[j], -dot(t, X[j])); } X[k] = nrm(t); }
}
// ---- ターン（地図の軌跡で球を埋め尽くす）：アナ極から大円で 1 周して戻ったら、向きを変えてまた 1 周。向きは「今までの道からいちばん離れた向き」（いちばん大きいすきま）を順に選ぶ
//   左の S²：0° → 90° → 45° → 135° → 22.5° …（すきまを半分ずつ。アナ極を通る大円は 180° で同じ輪なので 0〜180°）
//   S³：アナ極で進める向きは球面 S²（x, y, z）。反対向き（−d）は同じ大円なので、向きどうしの角は acos|d·e|。候補（八面体を細かく分けた点、粗い順）から、
//   今までの向きとのいちばん小さい角がいちばん大きいものを選ぶ（同じなら粗い方）＝ 軸 3 本 → 面の真ん中 → 辺の真ん中 → …
const FILL = { T: 0, lapSaid: 0, dirs: [], gaps: [], sg3: [1], sg2: [1], turn: null, half: false, dirsH: [], gapsH: [], phH: [] };
// 半周 180°（S.fillMode === 'half'）：アナ極→カタ極、カタ極→アナ極と半円（経線）ずつ進み、両方の極で双曲線で曲がる。
//   半円なので、向きは反対向き（−d）も別の経線＝全部の向き（S² は 0〜360°、S³ は球面全体）から選ぶ（半分の向きだけだと、球の半分にしか道が来ない）。
//   次の経線：すきまが十分大きい候補（いちばん大きいすきまの 3/4 以上）のうち、前の経線にいちばん直角に近いもの（＝極でいつもしっかり曲がる。真反対を選ぶと極をまっすぐ通り抜けてしまう）。
//   曲がる向き：アナ極とカタ極では左右が裏返しなので、カタ極ではアナ極と逆（東西逆）に曲がると、経線が同じ回り方で順に進む。
//   S³ では左右の代わりに、曲がる回転の軸 a×b（a＝着く向き、b＝出る向き）を前のターンとそろえる
function fillBuildHalf(N) {
    const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    const pick = (cand, d0, N, ang, crossOf) => {   // 共通：cand（単位ベクトル）、ang(c, d)＝角、crossOf(a, b)＝回転の軸（2 次元は数 1 つ）
        const dirs = [d0], gaps = [180], best = cand.map(c => ang(c, d0)); let kPrev = null;
        while (dirs.length < N) {
            let mx = 0; for (const v of best) if (v > mx) mx = v;
            if (mx < 1e-6) break;
            const prev = dirs[dirs.length - 1], a = scl(prev, -1); let bi = -1, bs = Infinity;
            for (let i = 0; i < cand.length; i++) {
                if (best[i] < 0.75 * mx - 1e-9) continue;
                const c = cand[i]; let sc = Math.abs(dot(prev, c)) - 0.15 * best[i] / mx;
                if (kPrev !== null) { const k = crossOf(a, c); if ((Array.isArray(k) ? dot(k, kPrev) : k * kPrev) < 0) sc += 0.5; }
                if (sc < bs) { bs = sc; bi = i; }
            }
            const c = cand[bi]; dirs.push(c); gaps.push(best[bi] / d2r);
            const k = crossOf(scl(prev, -1), c); if (Array.isArray(k) ? Math.hypot(...k) > 1e-6 : Math.abs(k) > 1e-6) kPrev = Array.isArray(k) ? nrm(k) : Math.sign(k);
            for (let i = 0; i < cand.length; i++) best[i] = Math.min(best[i], ang(cand[i], c));
        }
        return { dirs, gaps };
    };
    const c3 = [], seen = new Set();
    for (const n of [1, 2, 3, 4, 6, 8, 12, 16]) for (let i = -n; i <= n; i++) for (let j = -n; j <= n; j++) {
        const k0 = n - Math.abs(i) - Math.abs(j); if (k0 < 0) continue;
        for (const k of k0 ? [k0, -k0] : [0]) { const v = nrm([i, j, k]), key = v.map(x => Math.round(x * 1e6)).join(','); if (!seen.has(key)) { seen.add(key); c3.push(v); } }
    }
    const A = (c, d) => Math.acos(Math.max(-1, Math.min(1, dot(c, d))));
    const r3 = pick(c3, [1, 0, 0], N, A, cross);
    const c2 = []; for (let i = 0; i < 720; i++) { const t = i * Math.PI / 360; c2.push([Math.cos(t), Math.sin(t)]); }
    const r2 = pick(c2, [1, 0], N, A, (a, b) => a[0] * b[1] - a[1] * b[0]);
    FILL.dirsH = r3.dirs; FILL.gapsH = r3.gaps; FILL.phH = r2.dirs.map(v => Math.atan2(v[1], v[0]));
}
function fillBuild(N) {
    const cand = [], seen = new Set();
    for (const n of [1, 2, 3, 4, 6, 8, 12, 16, 24]) for (let i = -n; i <= n; i++) for (let j = -n; j <= n; j++) for (const k of [n - Math.abs(i) - Math.abs(j)]) {
        if (k < 0) continue;
        let v = nrm([i, j, k]); const f = v.find(x => Math.abs(x) > 1e-9); if (f < 0) v = scl(v, -1);   // 反対向きは同じ輪なので、最初の 0 でない成分を＋にそろえる
        const key = v.map(x => Math.round(x * 1e6)).join(','); if (seen.has(key)) continue; seen.add(key); cand.push(v);
    }
    const dirs = [[1, 0, 0]], gaps = [90], best = cand.map(c => Math.acos(Math.min(1, Math.abs(dot(c, dirs[0])))));
    while (dirs.length < N) {
        let bi = -1, bv = -1; for (let i = 0; i < cand.length; i++) if (best[i] > bv + 1e-9) { bv = best[i]; bi = i; }
        if (bi < 0 || bv < 1e-6) break;
        const d = cand[bi]; dirs.push(d); gaps.push(bv / d2r);
        for (let i = 0; i < cand.length; i++) best[i] = Math.min(best[i], Math.acos(Math.min(1, Math.abs(dot(cand[i], d)))));
    }
    FILL.dirs = dirs; FILL.gaps = gaps;
}
const vdc = k => { let x = 0, b = 0.5; while (k > 0) { if (k & 1) x += b; k >>= 1; b /= 2; } return x; };   // 0, 1/2, 1/4, 3/4, 1/8, 5/8 …（すきまを半分ずつ）
// lap 本目の向き。反対向きも同じ大円なので、曲がる角が小さくなる側（sg3・sg2 が −1 なら反対向き）から入る（周の始めに次の周の側を決める）
const fillU = lap => FILL.half ? FILL.dirsH[lap % FILL.dirsH.length] : scl(FILL.dirs[lap % FILL.dirs.length], FILL.sg3[lap] || 1);
const fillPh = lap => FILL.half ? FILL.phH[lap % FILL.phH.length] : vdc(lap) * Math.PI + ((FILL.sg2[lap] || 1) < 0 ? Math.PI : 0);
const fillPer = () => FILL.half ? Math.PI : TAU;   // 1 本の長さ（半円か大円）
const fillGap = lap => (FILL.half ? FILL.gapsH : FILL.gaps)[lap % (FILL.half ? FILL.gapsH : FILL.gaps).length];
const fillPhDeg = lap => ((fillPh(lap) / d2r) % 360 + 360) % 360;
const fillU2 = lap => [Math.cos(fillPh(lap)), Math.sin(fillPh(lap))];
function fillSigns(lap) {   // 次の周（lap）の入る側を、前の周の向きに近い方に
    if (FILL.half || FILL.sg3[lap] !== undefined) return;
    const a = fillU(lap - 1), raw = FILL.dirs[lap % FILL.dirs.length]; FILL.sg3[lap] = dot(raw, a) < 0 ? -1 : 1;
    let dph = ((vdc(lap) * Math.PI - fillPh(lap - 1)) % TAU + TAU) % TAU; if (dph > Math.PI) dph -= TAU;
    FILL.sg2[lap] = Math.abs(dph) > Math.PI / 2 ? -1 : 1;
}
function fillPoint(T) {
    const per = fillPer(), lap = Math.max(0, Math.floor(T / per)), th = T - lap * per, sn = Math.sin(th), cs = Math.cos(th) * (FILL.half && lap % 2 ? -1 : 1);   // カタ極からの半円は w を逆に
    const u = fillU(lap), ph = fillPh(lap);
    return { p: [sn * u[0], sn * u[1], sn * u[2], cs], p2: [sn * Math.cos(ph), sn * Math.sin(ph), cs], lap };
}
// アナ極のまわりのターン（双曲線）：来た道（向き a でアナ極へ向かう大円）と次の道（向き b でアナ極から出る大円）を漸近線にした双曲線で曲がる。
//   アナ極のまわりを「アナ極からの向き×距離」の平らな地図（正距方位）で考える（アナ極を通る大円はこの地図でまっすぐ）。
//   x(τ) = √k (e^{−τ}(−a) + e^{τ} b)：反比例 u·v = k と同じ形。遠くでは道にほとんど重なり、少しずつ曲がり始め、
//   いちばんアナ極に近づく所（τ = 0）でアナ極から FILL_DV、また少しずつまっすぐに戻る。アナ極そのものは通らない。
//   アナ極から L 手前で入り、L 先で抜ける（そこで道にぴったり合うよう、残りのごくわずかなずれを smoothstep で消す）
const FILL_DV = 0.1;
// いちばん近づく距離：曲がる角 θ が 90° をこえると双曲線の先がとがる（先の曲率半径＝距離×tan²((180°−θ)/2)）ので、先の半径が FILL_DV より小さくならないよう遠めを通る
const hypDV = th => { const t = Math.tan((Math.PI - th) / 2); return FILL_DV / Math.min(1, t * t); };
function hypTable(a, b, L, n) {   // a・b：単位ベクトル（2 次元か 3 次元）→ 長さで並べた点の表
    const c = Math.max(-1, Math.min(1, dot(a, b))), th = Math.acos(c), pts = [];
    for (let i = 0; i <= n; i++) {
        const f = i / n;
        if (th < 1e-3) { pts.push(scl(a, -L + 2 * L * f)); continue; }
        const sk = hypDV(th) / (2 * Math.sin(th / 2)), t0 = Math.log(Math.max(1.0001, L / sk)), kL = sk * sk / L, tau = -t0 + 2 * t0 * f, sm = f * f * (3 - 2 * f);
        let x = add(scl(a, -sk * Math.exp(-tau)), b, sk * Math.exp(tau));
        x = add(add(x, b, -kL * (1 - sm)), a, kL * sm);
        pts.push(x);
    }
    const cum = [0]; for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(...add(pts[i], pts[i - 1], -1)));
    return { pts, cum, len: cum[cum.length - 1] };
}
// 直角（S.turnStyle === 'sharp'）：角までまっすぐ進み、角でその場で向きを変えて、まっすぐ出る（道は角でぴったり曲がる）。表は角の手前 L から角、角から L 先までの 2 本の線
function cornerTable(a, b, L, n) {
    const pts = []; for (let i = 0; i <= n; i++) { const s = -L + 2 * L * i / n; pts.push(s < 0 ? scl(a, s) : scl(b, s)); }
    const cum = [0]; for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(...add(pts[i], pts[i - 1], -1)));
    return { pts, cum, len: cum[cum.length - 1] };
}
const turnTable = (a, b, L, n) => S.turnStyle === 'sharp' ? cornerTable(a, b, L, n) : hypTable(a, b, L, n);
// ターンを 1 歩すすめる（全周・半周・90°・極めぐりで共通）。to3・to2＝平らな地図の点 → S³・S² の点。終わったら true
//   直角では、角（f＝0.5）でいったん止まり、その場で向きを回す（tu.pv）。回す面は「着く向き」と「出る向き」の面、長さは曲がる角に合わせる
function turnStep(tu, ds, to3, to2) {
    if (tu.pv) {
        const pv = tu.pv; pv.t = Math.min(1, pv.t + ds / pv.len); const e = pv.t * pv.t * (3 - 2 * pv.t);
        const rot = (v, A, B, th) => { const c1 = dot(v, A), c2 = dot(v, B), co = Math.cos(th * e) - 1, si = Math.sin(th * e); return add(add(v, A, c1 * co - c2 * si), B, c1 * si + c2 * co); };
        W.f = rot(pv.F.f, pv.A3, pv.B3, pv.th3); W.r = rot(pv.F.r, pv.A3, pv.B3, pv.th3); W.u = rot(pv.F.u, pv.A3, pv.B3, pv.th3); orthoFrame(W);
        W2.f = rot(pv.G.f, pv.A2, pv.B2, pv.th2); W2.r = rot(pv.G.r, pv.A2, pv.B2, pv.th2); orthoFrame(W2);
        S.az = 0; S.el = 0;
        if (pv.t >= 1) { tu.pv = null; tu.pvDone = true; }
        return false;
    }
    let f = Math.min(1, tu.f + ds / Math.max(1e-6, tu.h3.len));
    if (tu.sharp && !tu.pvDone && f >= 0.5) {   // 角に着いた：ちょうど角まで進んで、向きを回し始める
        tu.f = 0.5; fillGo(to3(hypAt(tu.h3, 0.5)), to2(hypAt(tu.h2, 0.5)));
        const plane = (P, Q, d) => { const t = nrm(add(Q, P, -dot(Q, P))); const A = nrm(add(d, P, -dot(d, P))), B0 = add(t, A, -dot(t, A)), bl = Math.hypot(...B0); return { A, B: bl > 1e-6 ? scl(B0, 1 / bl) : A, th: Math.acos(Math.max(-1, Math.min(1, dot(A, t)))) }; };
        const p3 = plane(W.p, to3(hypAt(tu.h3, 0.52)), W.f), p2 = plane(W2.p, to2(hypAt(tu.h2, 0.52)), W2.f);
        tu.pv = { t: 0, len: 0.12 + 0.3 * Math.max(p3.th, p2.th) / (Math.PI / 2), F: { f: W.f.slice(), r: W.r.slice(), u: W.u.slice() }, G: { f: W2.f.slice(), r: W2.r.slice() }, A3: p3.A, B3: p3.B, th3: p3.th, A2: p2.A, B2: p2.B, th2: p2.th };
        return false;
    }
    tu.f = f; fillGo(to3(hypAt(tu.h3, f)), to2(hypAt(tu.h2, f)));
    return f >= 1;
}
function hypAt(tb, f) {   // 長さの割合 f（0〜1）の点
    const s = Math.max(0, Math.min(1, f)) * tb.len; let lo = 0, hi = tb.cum.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (tb.cum[m] <= s) lo = m; else hi = m; }
    const seg = tb.cum[hi] - tb.cum[lo], w = seg > 0 ? (s - tb.cum[lo]) / seg : 0;
    return add(scl(tb.pts[lo], 1 - w), tb.pts[hi], w);
}
// 入る距離 L：双曲線が道に十分近づく（ずれの角が 1° ほど）まで。S² と S³ で同じ L（同じ時に入って同じ時に抜ける）
const hypL = (a, b) => { const th = Math.acos(Math.max(-1, Math.min(1, dot(a, b)))); return th < 1e-3 ? 0.3 : Math.max(0.45, hypDV(th) / (2 * Math.sin(th / 2)) / 0.15); };
function fillPlan(nx) {   // nx 本目へのターンを用意する
    fillSigns(nx);
    const lap = nx - 1, sa = FILL.half ? -1 : 1;   // 着く向き：大円なら u のまま、半円なら極へ向かうので −u
    const a3 = scl(fillU(lap), sa), b3 = fillU(nx), a2 = scl(fillU2(lap), sa), b2 = fillU2(nx), L = Math.min(1.3, Math.max(hypL(a3, b3), hypL(a2, b2)));
    FILL.plan = { lap: nx, L, a3, b3, a2, b2, psg: FILL.half && nx % 2 ? -1 : 1, h3: turnTable(a3, b3, L, 240), h2: turnTable(a2, b2, L, 240), sharp: S.turnStyle === 'sharp' };
}
const expN = (x, sg = 1) => { const r = Math.hypot(...x); if (r < 1e-12) return x.length === 3 ? [0, 0, 0, sg] : [0, 0, sg]; const s = Math.sin(r) / r; return [...x.map(v => v * s), sg * Math.cos(r)]; };   // sg＝−1 ならカタ極のまわり
function fillStart() {
    if (S.fillMode === 'ctour') { ctStart(); return; }
    if (S.fillMode === 'star') { starStart(); return; }
    if (S.fillMode === 'q' || S.fillMode === 'tour') { fqStart(); return; }
    FILL.half = S.fillMode === 'half';
    if (!FILL.dirs.length) fillBuild(300);
    if (FILL.half && !FILL.dirsH.length) fillBuildHalf(300);
    resetNorth(); FILL.T = 0.002; FILL.lapSaid = 0; FILL.sg3 = [1]; FILL.sg2 = [1]; FILL.turn = null; fillPlan(1);
    const q = fillPoint(FILL.T); W.p = q.p.slice(); W2.p = q.p2.slice(); orthoFrame(W); orthoFrame(W2); req(3);
}
function fillGo(qp, qp2) {   // qp・qp2 へ進む（体は進む向きにそろえる＝前を向いたまま曲がる。S² も同じ）
    const d = nrm(add(qp, W.p, -dot(qp, W.p))), d2 = nrm(add(qp2, W2.p, -dot(qp2, W2.p)));
    const s3 = Math.acos(Math.max(-1, Math.min(1, dot(qp, W.p))));
    if (!(s3 > 1e-9) || !isFinite(d[0]) || !isFinite(d2[0])) return;
    const p0 = W.p.slice(), p02 = W2.p.slice(), s2 = Math.acos(Math.max(-1, Math.min(1, dot(qp2, W2.p))));
    step(d, d2, s3);
    W.p = qp.slice(); W2.p = qp2.slice();
    // 着いた所での進む向き（大円に沿って運んだ d）
    const dd = nrm(add(add(scl(p0, -Math.sin(s3)), d, Math.cos(s3)), W.p, 0)), dd2 = nrm(add(scl(p02, -Math.sin(s2)), d2, Math.cos(s2)));
    const g = (v, P, others) => { let t = add(v, P, -dot(v, P)); for (const o of others) t = add(t, o, -dot(t, o)); return nrm(t); };
    W.f = dd; W.r = g(W.r, W.p, [W.f]); W.u = g(W.u, W.p, [W.f, W.r]);
    W2.f = dd2; W2.r = g(W2.r, W2.p, [W2.f]);
    S.az = 0; S.el = 0;
}
// ---- 90°（S.fillMode === 'q'）：大円を 90° 進むごとにターン。極には戻らず、まだ通っていない方へさまよって広がる。
//   ターンする点 Q（今の 90° の道の終わり）から出られる向きのうち、その先の 90° の道が今までの軌跡からいちばん離れている向きを選ぶ
//   （候補は S³ では Q で進める向きの球面の 160 方向、S² では 5° ごと。曲がる角は 40〜120°（ほぼまっすぐ・ほぼ逆戻りは選ばない））。
//   Q のまわりも「Q からの向き×距離」の平らな地図で考えて、極の時と同じ双曲線で曲がる
const FQ = { leg: 0, P: null, b: null, P2: null, b2: null, s: 0, plan: null, turn: null };
const FQ_LEN = Math.PI / 2;
function fqBasis(Q, a) {   // Q での接ベクトルの正規直交の組（1 本目は着く向き a）
    const E = [a]; for (const v of [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]].map(v => v.slice(0, Q.length))) {
        if (E.length >= Q.length - 1) break;
        let t = add(v, Q, -dot(v, Q)); for (const e of E) t = add(t, e, -dot(t, e)); if (Math.hypot(...t) > 1e-3) E.push(nrm(t));
    }
    return E;
}
const fqFromFlat = (Q, E, x) => { const r = Math.hypot(...x); if (r < 1e-12) return Q.slice(); let t = scl(Q, 0); x.forEach((xi, i) => { t = add(t, E[i], xi); }); return add(scl(Q, Math.cos(r)), t, Math.sin(r) / r); };
function fqChoose(Q, a, hist, dim) {   // まだ通っていない方：候補の道の点と、今までの軌跡の点との最小距離の平均がいちばん大きい向き
    const E = fqBasis(Q, a), cands = [], st = Math.max(3, Math.floor(hist.length / 500));   // 軌跡の点は 500 個ほどに間引いて比べる
    if (dim === 3) { const n = 160; for (let i = 0; i < n; i++) { const z = 1 - 2 * (i + 0.5) / n, r = Math.sqrt(1 - z * z), t = i * 2.399963; cands.push([z, r * Math.cos(t), r * Math.sin(t)]); } }
    else for (let d = -175; d <= 180; d += 5) cands.push([Math.cos(d * d2r), Math.sin(d * d2r)]);
    let best = null, bv = -1;
    for (const u of cands) {
        const th = Math.acos(Math.max(-1, Math.min(1, u[0]))) / d2r; if (th < 40 || th > 120) continue;
        let c = scl(Q, 0); u.forEach((ui, i) => { c = add(c, E[i], ui); });
        let sum = 0; for (const sk of [0.35, 0.6, 0.85, 1.1, 1.35, 1.57]) { const R = add(scl(Q, Math.cos(sk)), c, Math.sin(sk)); let m = -1; for (let j = 0; j < hist.length; j += st) { const h = hist[j]; let d = 0; for (let k = 0; k < R.length; k++) d += R[k] * h[k]; if (d > m) m = d; } sum += Math.acos(Math.max(-1, Math.min(1, m))); }
        const v = sum + 1e-4 * Math.random(); if (v > bv) { bv = v; best = { u, c, th }; }
    }
    return Object.assign(best, { E, nov: bv / 6 });
}
// 極めぐり（S.fillMode === 'tour'）：アナ極から、となり合う極（90° はなれている）だけをたどって 8 つ全部を回り、アナ極に戻る。
//   どの極へも 90° より近くは行けないので、90° × 8 本 ＝ 4π がいちばん短い 1 周。毎回 90° の双曲線ターン。S² は 6 つの極を同じように回る
const FQ_R3 = [[0, 0, 0, 1], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, -1], [-1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, 0]];   // アナ・東・北・天・カタ・西・南・地
const FQ_R2 = [[0, 0, 1], [1, 0, 0], [0, 1, 0], [0, 0, -1], [-1, 0, 0], [0, -1, 0]];   // アナ・東・北・カタ・西・南
function fqToward(Q, a, T) {   // 極 Q から、となりの極 T へ（Q と T は直交なので、出る向きは T そのもの）
    const E = fqBasis(Q, a), u = E.map(e => dot(T, e)), th = Math.acos(Math.max(-1, Math.min(1, u[0]))) / d2r;
    return { u, c: T.slice(), th, E, nov: 0 };
}
const fqPoleName = p => { const m = FIXED.find(f => (p.length === 4 ? f.p : f.p2) && dot(p.length === 4 ? f.p : f.p2, p) > 0.999); return m ? poleName(m) : '?'; };
function fqPlan() {   // 今の 90° の道の終わりでのターンを決める（道をほとんど通った所で。今の道も軌跡に入っているように）
    const Q = add(scl(FQ.P, Math.cos(FQ_LEN)), FQ.b, Math.sin(FQ_LEN)), a = nrm(add(scl(FQ.P, -Math.sin(FQ_LEN)), FQ.b, Math.cos(FQ_LEN)));
    const Q2 = add(scl(FQ.P2, Math.cos(FQ_LEN)), FQ.b2, Math.sin(FQ_LEN)), a2 = nrm(add(scl(FQ.P2, -Math.sin(FQ_LEN)), FQ.b2, Math.cos(FQ_LEN)));
    const c3 = S.fillMode === 'tour' ? fqToward(Q, a, FQ_R3[(FQ.leg + 2) % FQ_R3.length]) : fqChoose(Q, a, W.trail, 3);
    const c2 = S.fillMode === 'tour' ? fqToward(Q2, a2, FQ_R2[(FQ.leg + 2) % FQ_R2.length]) : fqChoose(Q2, a2, W2.trail, 2);
    const f3 = [1, 0, 0], f2 = [1, 0], L = Math.min(0.75, Math.max(hypL(f3, c3.u), hypL(f2, c2.u)));
    FQ.plan = { Q, Q2, c3, c2, L, h3: turnTable(f3, c3.u, L, 240), h2: turnTable(f2, c2.u, L, 240), sharp: S.turnStyle === 'sharp' };
}
function fqStart() {
    resetNorth(); Object.assign(FQ, { leg: 0, P: [0, 0, 0, 1], b: [1, 0, 0, 0], P2: [0, 0, 1], b2: [1, 0, 0], s: 0.002, plan: null, turn: null });
    W.p = add(scl(FQ.P, Math.cos(FQ.s)), FQ.b, Math.sin(FQ.s)); W2.p = add(scl(FQ.P2, Math.cos(FQ.s)), FQ.b2, Math.sin(FQ.s)); orthoFrame(W); orthoFrame(W2); req(3);
}
function fqStep(ds) {
    if (FQ.turn) {
        const tu = FQ.turn;
        if (turnStep(tu, ds, x => fqFromFlat(tu.Q, tu.c3.E, x), x => fqFromFlat(tu.Q2, tu.c2.E, x))) { FQ.turn = null; FQ.leg++; FQ.P = tu.Q; FQ.b = tu.c3.c; FQ.P2 = tu.Q2; FQ.b2 = tu.c2.c; FQ.s = tu.L; FQ.plan = null; }
        return;
    }
    FQ.s += ds;
    if (!FQ.plan && FQ.s >= FQ_LEN - 0.75) fqPlan();
    if (FQ.plan && FQ_LEN - FQ.s <= FQ.plan.L) {   // ターンに入る
        FQ.s = FQ_LEN - FQ.plan.L;
        fillGo(add(scl(FQ.P, Math.cos(FQ.s)), FQ.b, Math.sin(FQ.s)), add(scl(FQ.P2, Math.cos(FQ.s)), FQ.b2, Math.sin(FQ.s)));
        FQ.turn = Object.assign({ f: 0 }, FQ.plan);
        if (S.fillMode === 'tour') say(`${fqPoleName(FQ.plan.Q)}で ${FQ.plan.c3.th.toFixed(0)}° ターン → ${fqPoleName(FQ.plan.c3.c)}へ（S² では ${fqPoleName(FQ.plan.Q2)} → ${fqPoleName(FQ.plan.c2.c)}）`);
        else say(`${FQ.leg + 2} 本目へ：${FQ.plan.c3.th.toFixed(0)}° ターン（S² では ${FQ.plan.c2.th.toFixed(0)}°）。まだ通っていない方へ（その先の道と今までの軌跡の間 平均 ${(FQ.plan.c3.nov / d2r).toFixed(0)}°）`);
        return;
    }
    fillGo(add(scl(FQ.P, Math.cos(FQ.s)), FQ.b, Math.sin(FQ.s)), add(scl(FQ.P2, Math.cos(FQ.s)), FQ.b2, Math.sin(FQ.s)));
}
function fillStep(ds) {
    if (S.fillMode === 'ctour') { ctStep(ds); return; }
    if (S.fillMode === 'star') { let r = ds * (S.starFF ? S.starK : 1); while (r > 1e-9) { const h = Math.min(r, 0.02); starStep(h); r -= h; } return; }   // 早送りでも細かく刻む（軌跡の点が 0.02 おきに残るように）
    if (S.fillMode === 'q' || S.fillMode === 'tour') { fqStep(ds); return; }
    if (FILL.turn) {   // ターン中：双曲線の上を進む（S³ の長さで進み具合を決め、S² も同じ割合）
        const tu = FILL.turn;
        if (turnStep(tu, ds, x => expN(x, tu.psg), x => expN(x, tu.psg))) { FILL.turn = null; FILL.T = tu.lap * fillPer() + tu.L; fillPlan(tu.lap + 1); }
        return;
    }
    const per = fillPer(), lap = Math.floor(FILL.T / per);
    FILL.T += ds;   // 大円の上は T がそのまま進んだ距離
    if (!FILL.plan || FILL.plan.lap !== lap + 1) fillPlan(lap + 1);
    if ((lap + 1) * per - FILL.T <= FILL.plan.L) {   // 極の手前 L：ターンに入る
        const nx = lap + 1, P = FILL.plan, a3 = P.a3, b3 = P.b3, a2 = P.a2, b2 = P.b2;
        FILL.turn = Object.assign({ f: 0 }, P);
        FILL.T = nx * per - P.L;
        const q = fillPoint(FILL.T); fillGo(q.p, q.p2);
        const th = Math.acos(Math.max(-1, Math.min(1, dot(a3, b3)))) / d2r, th2 = Math.acos(Math.max(-1, Math.min(1, dot(a2, b2)))) / d2r;
        say(`${nx + 1} 本目へ：${P.psg < 0 ? 'カタ極' : 'アナ極'}をよけて ${th.toFixed(1)}° ターン（S² では ${th2.toFixed(1)}°、双曲線）。すきまの大きい向きへ（今までの道から ${fillGap(nx).toFixed(1)}°）`);
        FILL.lapSaid = nx;
        return;
    }
    const q = fillPoint(FILL.T); fillGo(q.p, q.p2);
}
resetNorth(); fillStart();
const out = [];
for (let i = 1; i <= N; i++) { fillStep(ds); if (i % every === 0) out.push([...W.p, ...W2.p, ...W.f]); }
console.log(JSON.stringify(out));
