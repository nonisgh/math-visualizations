/*!
 * nd-geom.js — n 次元の計算（共通の部品）
 *
 * 次元おりがみ（hypercube.html）・6次元アプリ（hypercube6d.html）・n次元ビューア（ndim.html）が
 * それぞれ持っている「n 次元の回転・3D への写し方・形・展開図」を、どのアプリでも使えるように取り出したもの。
 * 使い方・仕様・3 つのアプリの式のちがいは、同じフォルダの README.md を参照。
 *
 *   const R  = NDGeom.rotation(5, [[0, 3, a], [1, 4, b]]);      // 回転面 (i,j) と角度（ラジアン）→ 5×5 の行列
 *   const pj = NDGeom.projector(5, { preset: 'okami', R });     // 4 本目から先を 1 本ずつ遠近で 3D に
 *   const K  = pj.project(p, out);                              // out = [x,y,z]、K＝見かけの縮み（visual-fx の cellDepth などへ）
 *   const C  = NDGeom.cube(5);                                  // 頂点・辺・正方形。cubeCells・simplex・cross も
 *   const net = NDGeom.cubeNet(5); net.fold(0.5);               // 立方体の展開図を半分折る（net.V に n 次元の位置）
 *
 * 依存なし（three.js も要らない）。数は Float64Array・Int32Array などのふつうの配列で返す。
 */
(function (global) {
    'use strict';

    const VERSION = '1.0.1';   // 1.0.1：rotatePoint が { a, b, ang } の並びも受け取る（次元おりがみの 6次元の窓）
    const AXES = ['x', 'y', 'z', 'w', 'v', 'u', 't', 's', 'r', 'q'];   // 軸の名前（visual-fx・ndim.html と同じ並び）
    const HALF_PI = Math.PI / 2;
    const clamp01 = t => (t < 0 ? 0 : t > 1 ? 1 : t);
    const EASE = {   // 折りたたみの進み方（0〜1 → 0〜1）
        linear: t => clamp01(t),                                                          // n次元ビューア
        smooth: t => { t = clamp01(t); return t * t * (3 - 2 * t); },                     // 6次元アプリ
        smoother: t => { t = clamp01(t); return t * t * t * (t * (t * 6 - 15) + 10); },   // 次元おりがみ（smootherstep）
    };
    const easeOf = e => (typeof e === 'function' ? e : EASE[e] || EASE.smooth);
    function binom(a, b) {
        if (b < 0 || b > a) return 0;
        let r = 1;
        for (let i = 1; i <= b; i++) r = r * (a - b + i) / i;
        return Math.round(r);
    }

    // ======================================================================
    // 1. 回転（n×n の行列。行優先の Float64Array、R[r*n + c]）
    // ======================================================================
    // 回転面の一覧（i < j、辞書の順）。n 次元で n(n−1)/2 枚
    function planes(n) {
        const p = [];
        for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) p.push([i, j]);
        return p;
    }
    const planeKey = (i, j) => `${Math.min(i, j)}-${Math.max(i, j)}`;
    function identity(n) {
        const R = new Float64Array(n * n);
        for (let i = 0; i < n; i++) R[i * n + i] = 1;
        return R;
    }
    // 今の回転 R の「あと」に、回転面 (i,j) を角度 a だけ回す（R ← G·R）。x_i' = cos·x_i − sin·x_j、x_j' = sin·x_i + cos·x_j
    function rotatePlane(R, n, i, j, a) {
        if (!a) return R;
        const c = Math.cos(a), s = Math.sin(a);
        for (let col = 0; col < n; col++) {
            const p = R[i * n + col], q = R[j * n + col];
            R[i * n + col] = c * p - s * q; R[j * n + col] = s * p + c * q;
        }
        return R;
    }
    // 回し方の書き方をそろえて、(i, j, 角度) を回す順に呼ぶ
    //   [[i, j, a], …]・[{ a: i, b: j, ang }, …]（書いた順に回す）
    //   { '0-3': a, … }・[a0, a1, …]（planes(n) の並び＝辞書の順に回す）
    function eachPlane(n, spec, fn) {
        if (!spec) return;
        if (Array.isArray(spec) || ArrayBuffer.isView(spec)) {
            if (spec.length && typeof spec[0] === 'number') { planes(n).forEach(([i, j], k) => fn(i, j, spec[k] || 0)); return; }
            for (const q of spec) {
                if (Array.isArray(q)) fn(q[0], q[1], q[2] || 0);
                else if (q) fn(q.a !== undefined ? q.a : q.i, q.b !== undefined ? q.b : q.j, q.ang !== undefined ? q.ang : q.angle || 0);
            }
            return;
        }
        planes(n).forEach(([i, j]) => fn(i, j, spec[planeKey(i, j)] || 0));
    }
    // 回転の行列。o.deg：角度が度。o.out：書きこむ行列（使い回し）
    function rotation(n, spec, o) {
        const k = o && o.deg ? Math.PI / 180 : 1;
        let R = o && o.out;
        if (R) { R.fill(0); for (let i = 0; i < n; i++) R[i * n + i] = 1; } else R = identity(n);
        eachPlane(n, spec, (i, j, a) => {
            if (i === j || i < 0 || j < 0 || i >= n || j >= n) return;   // その次元に無い面は飛ばす
            rotatePlane(R, n, i, j, a * k);
        });
        return R;
    }
    // 点を回す：out = R·p（p・out はふつうの配列でも型付き配列でも。si・oi は読み書きを始める位置）
    function apply(R, n, p, out, si, oi) {
        si = si || 0; oi = oi || 0; out = out || new Float64Array(n);
        const t = apply._t.length >= n ? apply._t : (apply._t = new Float64Array(n));
        for (let r = 0; r < n; r++) { let s = 0; for (let c = 0; c < n; c++) s += R[r * n + c] * p[si + c]; t[r] = s; }
        for (let r = 0; r < n; r++) out[oi + r] = t[r];   // p と out が同じでもよい
        return out;
    }
    apply._t = new Float64Array(16);
    // 行列のかけ算 A·B（B を先に、A をあとに回す）
    function multiply(A, B, n, out) {
        const C = new Float64Array(n * n);
        for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) { let s = 0; for (let k = 0; k < n; k++) s += A[r * n + k] * B[k * n + c]; C[r * n + c] = s; }
        if (out) { out.set(C); return out; }
        return C;
    }
    function transpose(R, n) {   // 回転の逆向き
        const T = new Float64Array(n * n);
        for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) T[c * n + r] = R[r * n + c];
        return T;
    }
    // 軸 k（の ±向き）を回した先＝R の k 列目×sign（胞の外向き・光の計算に）
    function axisImage(R, n, k, sign, out) {
        out = out || new Float64Array(n); const s = sign === undefined ? 1 : sign;
        for (let r = 0; r < n; r++) out[r] = R[r * n + k] * s;
        return out;
    }
    // 軸 k が x・y・z に残っている割合（4 本目から先へ回った分だけ消える）。n次元ビューアの axisFade
    function axisVisible(R, n, k) {
        let h = 0;
        for (let m = 3; m < n; m++) h += R[m * n + k] * R[m * n + k];
        return Math.max(0, 1 - h);
    }
    // 行列を作らずに点を直接回す（6次元アプリの rot6 と同じ。回す面が少ない時用）。list は [[i, j, a], …] か [{ a: i, b: j, ang }, …]
    function rotatePoint(p, list) {
        for (const q of list) {
            const arr = Array.isArray(q), i = arr ? q[0] : q.a, j = arr ? q[1] : q.b, a = arr ? q[2] : q.ang; if (!a) continue;
            const c = Math.cos(a), s = Math.sin(a), x = p[i], y = p[j];
            p[i] = c * x - s * y; p[j] = s * x + c * y;
        }
        return p;
    }

    // ======================================================================
    // 2. 3D への写し方（4 本目から先を、いちばん上の次元から 1 本ずつ遠近で）
    // ======================================================================
    //   段 m（m = n−1, n−2, …, 3）ごとに：k_m = 1 / (1 − q_m / D_m)、q_0 … q_{m−1} を k_m 倍
    //   見かけの縮み K = k_{n−1} × … × k_3（大きいほど手前。visual-fx の cellDepth・innerAmount・shadeFace へ）
    //   はさみ方：margin を決めると q_m を D_m − margin 以下に（both なら −D_m + margin 以上にも）。kMax を決めると k_m ≤ kMax
    //   blend（0＝遠近、1＝平行）：k_m を 1 + (k_m − 1)(1 − blend) に（次元おりがみの「平行投影」との間）
    // 距離 D の比（w を 1 として）。次元おりがみ：v は ×1.4、u は ×1.9。その先は 0.5 ずつ（作った値。どのアプリにも無い）
    const okamiRatio = m => (m <= 3 ? 1 : m === 4 ? 1.4 : 1.9 + 0.5 * (m - 5));
    const PRESETS = {
        okami: {    // 次元おりがみ（4D・5D・6次元の窓）：頂点 ±0.9、D_w＝4.5（設定の CAMERA_W）
            size: 0.9, dist: (m, n, o) => (o.w || 4.5) * okamiRatio(m), margin: 0.5, both: true, scale: 1,
            fold: { timing: 'stagger', armEnd: 0.60, capStart: 0.45, ease: 'smoother', capAxis: 1, center: true },
        },
        hex6app: {  // 6次元アプリ：頂点 ±1、D＝7・9.8・13.7（その先は 3.9 ずつ）、最後に 0.75 倍
            size: 1, dist: [0, 0, 0, 7, 9.8, 13.7], margin: 0.6, both: true, scale: 0.75,
            fold: { timing: 'stagger', armEnd: 0.62, capStart: 0.38, ease: 'smooth', capAxis: 1, center: false },
        },
        ndim: {     // n次元ビューア：頂点 ±1/√n、D＝2.4 / 遠近の強さ pk（既定 0.45）、全部の段で同じ。k ≤ 4
            size: n => 1 / Math.sqrt(n), dist: (m, n, o) => 2.4 / (o.pk === undefined ? 0.45 : o.pk), margin: null, both: false, kMax: 4, scale: 1,
            fold: { timing: 'together', ease: 'linear', capAxis: 0, center: false },
        },
        example: {  // visual-fx の見本：頂点 ±0.9、D＝3.4(1＋0.45(m−3))(1＋0.3·max(0, n−6))。手前側だけはさむ
            size: 0.9, dist: (m, n) => 3.4 * (1 + 0.45 * (m - 3)) * (1 + 0.3 * Math.max(0, n - 6)), margin: 0.5, both: false, scale: 1,
            fold: { timing: 'stagger', ease: 'smooth', capAxis: 0, center: true },
        },
    };
    // 距離の書き方（数・配列・関数）から段 m の D を
    function distOf(spec, m, n, o) {
        if (typeof spec === 'function') return spec(m, n, o);
        if (Array.isArray(spec) || ArrayBuffer.isView(spec)) {
            if (spec[m] !== undefined && spec[m] > 0) return spec[m];
            let L = spec.length - 1; while (L > 0 && !(spec[L] > 0)) L--;   // 書いていない先は、最後の 2 つの差で伸ばす
            const d = L > 0 && spec[L - 1] > 0 ? spec[L] - spec[L - 1] : 0;
            return spec[L] + (m - L) * d;
        }
        return +spec;
    }
    // 写すもの（使い回しの入れ物を持つ）。o：preset・dist・margin・both・kMax・scale・blend・R（回転）・pre（回す前に軸ごとにかける倍率）
    function projector(n, o) {
        o = o || {};
        const P = PRESETS[o.preset || 'okami'] || PRESETS.okami;
        const pick = (k, d) => (o[k] !== undefined ? o[k] : P[k] !== undefined ? P[k] : d);
        const D = new Float64Array(n), dist = pick('dist', 4.5);
        for (let m = 3; m < n; m++) D[m] = distOf(dist, m, n, o);
        const q = new Float64Array(n);
        const pj = {
            n, D, q,
            margin: pick('margin', null), both: pick('both', true), kMax: pick('kMax', 0), scale: pick('scale', 1),
            blend: pick('blend', 0), R: o.R || null, pre: o.pre || null,
            size: typeof P.size === 'function' ? P.size(n) : P.size,   // そのプリセットのアプリの頂点の大きさ（cube(n, { size }) に渡す用）
            K: 1, w: 0,
            setRotation(R) { pj.R = R; return pj; },
            // src の si 番目から n 個（n 次元の点）を回して写し、out の oi 番目から [x, y, z] を書く。返り値＝見かけの縮み K
            project(src, out, oi, si) {
                oi = oi || 0; si = si || 0;
                const R = pj.R, pre = pj.pre;
                if (R) {
                    for (let r = 0; r < n; r++) {
                        let s = 0;
                        if (pre) for (let c = 0; c < n; c++) s += R[r * n + c] * src[si + c] * pre[c];
                        else for (let c = 0; c < n; c++) s += R[r * n + c] * src[si + c];
                        q[r] = s;
                    }
                } else for (let c = 0; c < n; c++) q[c] = src[si + c] * (pre ? pre[c] : 1);
                const mg = pj.margin, both = pj.both, kMax = pj.kMax, bl = pj.blend;
                let K = 1;
                for (let m = n - 1; m >= 3; m--) {
                    const Dm = D[m];
                    let x = q[m];
                    if (mg !== null && mg !== undefined) { if (x > Dm - mg) x = Dm - mg; if (both && x < -Dm + mg) x = -Dm + mg; }
                    let d = 1 - x / Dm;
                    if (kMax && d < 1 / kMax) d = 1 / kMax;
                    let k = 1 / d;
                    if (bl) k = 1 + (k - 1) * (1 - bl);
                    for (let t = 0; t < m; t++) q[t] *= k;
                    K *= k;
                }
                pj.K = K; pj.w = n > 3 ? q[3] : 0;   // w：ほかの段で縮めたあとの w（線の濃さなどに）
                const sc = pj.scale;
                if (out) { out[oi] = q[0] * sc; out[oi + 1] = q[1] * sc; out[oi + 2] = q[2] * sc; }
                return K;
            },
            // 全部の頂点（V：nv×n の並び）を写す。P：nv×3、Kout：nv（無くてもよい）
            projectAll(V, Pout, Kout) {
                const nv = Math.floor(V.length / n);
                Pout = Pout || new Float32Array(nv * 3);
                for (let i = 0; i < nv; i++) { const K = pj.project(V, Pout, i * 3, i * n); if (Kout) Kout[i] = K; }
                return Pout;
            },
        };
        return pj;
    }

    // ======================================================================
    // 3. 形（頂点・辺・面・胞）
    // ======================================================================
    // 頂点の番号：立方体は「ビット k が 1 ＝ 軸 k が ＋」（3 つのアプリとも同じ）
    // n 次元立方体 [−size, size]^n：頂点 2^n・辺 n·2^(n−1)・正方形 C(n,2)·2^(n−2)
    function cube(n, o) {
        const h = o && o.size !== undefined ? o.size : 1, nv = 1 << n;
        const V = new Float64Array(nv * n);
        for (let i = 0; i < nv; i++) for (let k = 0; k < n; k++) V[i * n + k] = ((i >> k) & 1 ? 1 : -1) * h;
        const E = [], EA = [];
        for (let i = 0; i < nv; i++) for (let k = 0; k < n; k++) if (!((i >> k) & 1)) { E.push(i, i | (1 << k)); EA.push(k); }
        const Q = [], QA = [];
        for (let a = 0; a < n; a++) for (let b = a + 1; b < n; b++) for (let i = 0; i < nv; i++) {
            if ((i >> a) & 1 || (i >> b) & 1) continue;
            Q.push(i, i | (1 << a), i | (1 << a) | (1 << b), i | (1 << b)); QA.push(a, b);   // まわる順（p, q, r, s）
        }
        return { kind: 'cube', n, size: h, nv, V, edges: Int32Array.from(E), edgeAxis: Uint8Array.from(EA), squares: Int32Array.from(Q), squareAxes: Uint8Array.from(QA), ne: EA.length, nq: QA.length / 2 };
    }
    // 立方体の胞（±各軸の (n−1) 次元立方体、2n 個。並び＝軸 0 の＋、軸 0 の−、軸 1 の＋ …）。
    //   verts：その胞の頂点（立方体の番号）、quads：その胞の正方形（4 つずつ）、edges：その胞の辺（2 つずつ）、
    //   center：いちばん上の次元の −側（展開図の真ん中）、normal：外向き（n 次元）
    function cubeCells(n) {
        const nv = 1 << n, cells = [];
        for (let k = 0; k < n; k++) for (const sg of [1, -1]) {
            const o = [];
            for (let d = 0; d < n; d++) if (d !== k) o.push(d);
            const fix = sg > 0 ? 1 << k : 0, verts = [];
            for (let i = 0; i < nv; i++) if ((i & (1 << k)) === fix) verts.push(i);
            const quads = [];
            for (let a = 0; a < o.length; a++) for (let b = a + 1; b < o.length; b++) {
                const rest = o.filter((_, j) => j !== a && j !== b), A = 1 << o[a], B = 1 << o[b];
                for (let m = 0; m < (1 << rest.length); m++) {
                    let base = fix; rest.forEach((d, j) => { if ((m >> j) & 1) base |= 1 << d; });
                    quads.push(base, base | A, base | A | B, base | B);
                }
            }
            const edges = [];
            verts.forEach(v => o.forEach(d => { if (!(v & (1 << d))) edges.push(v, v | (1 << d)); }));
            const normal = new Float64Array(n); normal[k] = sg;
            cells.push({ axis: k, sign: sg, center: k === n - 1 && sg < 0, free: o, verts: Int32Array.from(verts), quads: Int32Array.from(quads), edges: Int32Array.from(edges), normal });
        }
        return cells;
    }
    // 立方体の k 次元の面（k＝1 で辺、2 で正方形、n−1 で胞）。C(n,k)·2^(n−k) 個。
    //   並び：自由な軸の組 free を辞書の順に、その中で fixed（ほかの軸の ±1）をビットの順に。6次元アプリの「ばらし」と同じ並び
    //   verts：頂点（立方体の番号）を free のビットの順に、fixed：軸ごとに 0（自由）・±1
    function cubeFaces(n, k) {
        const out = [], subsets = [];
        (function rec(st, a) {
            if (a.length === k) { subsets.push(a.slice()); return; }
            for (let i = st; i < n; i++) { a.push(i); rec(i + 1, a); a.pop(); }
        })(0, []);
        subsets.forEach(F => {
            const G = []; for (let i = 0; i < n; i++) if (!F.includes(i)) G.push(i);
            for (let sg = 0; sg < (1 << G.length); sg++) {
                const fixed = new Int8Array(n); let base = 0;
                G.forEach((g, j) => { if ((sg >> j) & 1) { fixed[g] = 1; base |= 1 << g; } else fixed[g] = -1; });
                const verts = new Int32Array(1 << k);
                for (let i = 0; i < (1 << k); i++) { let v = base; F.forEach((f, j) => { if ((i >> j) & 1) v |= 1 << f; }); verts[i] = v; }
                out.push({ free: F, fixed, verts });
            }
        });
        return out;
    }
    // 正単体：頂点 n+1 個（e_0 … e_{n−1} と (1−√(n+1))/n·(1,…,1) を、重心を原点に・半径 size に）。n次元ビューアと同じ
    //   頂点 i（i < n）は軸 i の向き寄り、頂点 n は (−1,…,−1) の向き。辺・三角形は全部の組
    function simplex(n, o) {
        const r0 = o && o.size !== undefined ? o.size : 1, nv = n + 1;
        const pts = [];
        for (let i = 0; i < n; i++) { const v = new Array(n).fill(0); v[i] = 1; pts.push(v); }
        pts.push(new Array(n).fill((1 - Math.sqrt(n + 1)) / n));
        const cen = new Array(n).fill(0); pts.forEach(p => p.forEach((x, k) => { cen[k] += x / nv; }));
        const r = Math.hypot(...pts[0].map((x, k) => x - cen[k]));
        const V = new Float64Array(nv * n);
        pts.forEach((p, i) => p.forEach((x, k) => { V[i * n + k] = (x - cen[k]) / r * r0; }));
        const E = [], T = [];
        for (let a = 0; a < nv; a++) for (let b = a + 1; b < nv; b++) E.push(a, b);
        for (let a = 0; a < nv; a++) for (let b = a + 1; b < nv; b++) for (let c = b + 1; c < nv; c++) T.push(a, b, c);
        return { kind: 'simplex', n, size: r0, nv, V, edges: Int32Array.from(E), tris: Int32Array.from(T), ne: E.length / 2, nt: T.length / 3 };
    }
    // 正単体の胞：頂点 i の向かいの (n−1) 次元単体（n+1 個）。normal＝−(頂点 i の向き)
    function simplexCells(n, S) {
        S = S || simplex(n);
        const cells = [];
        for (let i = 0; i <= n; i++) {
            const verts = []; for (let v = 0; v <= n; v++) if (v !== i) verts.push(v);
            const normal = new Float64Array(n); let l = 0;
            for (let c = 0; c < n; c++) { normal[c] = -S.V[i * n + c]; l += normal[c] * normal[c]; }
            l = Math.sqrt(l) || 1; for (let c = 0; c < n; c++) normal[c] /= l;
            const tris = [];
            for (let a = 0; a < verts.length; a++) for (let b = a + 1; b < verts.length; b++) for (let c = b + 1; c < verts.length; c++) tris.push(verts[a], verts[b], verts[c]);
            cells.push({ opposite: i, axis: i < n ? i : -1, verts: Int32Array.from(verts), tris: Int32Array.from(tris), normal });
        }
        return cells;
    }
    // 正軸体：頂点 ±size·e_k（番号 2k が＋、2k+1 が−）。向かい合う 2 点以外は全部つながる
    function cross(n, o) {
        const h = o && o.size !== undefined ? o.size : 1, nv = 2 * n;
        const V = new Float64Array(nv * n);
        for (let k = 0; k < n; k++) { V[(2 * k) * n + k] = h; V[(2 * k + 1) * n + k] = -h; }
        const E = [], T = [];
        for (let a = 0; a < nv; a++) for (let b = a + 1; b < nv; b++) if ((a >> 1) !== (b >> 1)) E.push(a, b);
        for (let a = 0; a < nv; a++) for (let b = a + 1; b < nv; b++) for (let c = b + 1; c < nv; c++)
            if ((a >> 1) !== (b >> 1) && (b >> 1) !== (c >> 1) && (a >> 1) !== (c >> 1)) T.push(a, b, c);
        return { kind: 'cross', n, size: h, nv, V, edges: Int32Array.from(E), tris: Int32Array.from(T), ne: E.length / 2, nt: T.length / 3 };
    }
    // 正軸体の胞：軸ごとに ＋か−の頂点を 1 つずつ選んだ (n−1) 次元単体（2^n 個）。signs のビット k が 1 ＝ 軸 k は −
    function crossCells(n) {
        const cells = [];
        for (let m = 0; m < (1 << n); m++) {
            const verts = new Int32Array(n), normal = new Float64Array(n), s = 1 / Math.sqrt(n);
            for (let k = 0; k < n; k++) { const neg = (m >> k) & 1; verts[k] = 2 * k + neg; normal[k] = neg ? -s : s; }
            cells.push({ signs: m, verts, normal });
        }
        return cells;
    }
    // 面の数の表 f_0（頂点）… f_{n−1}（胞）
    function fvector(kind, n) {
        const f = [];
        for (let k = 0; k < n; k++) {
            if (kind === 'cube') f.push(binom(n, k) * Math.pow(2, n - k));
            else if (kind === 'simplex') f.push(binom(n + 1, k + 1));
            else if (kind === 'cross') f.push(Math.pow(2, k + 1) * binom(n, k + 1));
        }
        return f;
    }

    // ======================================================================
    // 4. 立方体の展開図（n−1 次元の立方体 2n 個を、いちばん上の軸の向きへ折りたたむ）
    // ======================================================================
    //   N＝n−1（いちばん上の軸）。真ん中＝軸 N の −側、腕＝±軸 k（k < N）、ふた＝軸 N の＋側（腕 +capAxis の先につく）
    //   角度 θ：0＝平ら（展開図）、π/2＝折りたたみ済み。腕は軸 k ごと、ふたは腕に対してさらに θcap
    //   どの胞の頂点も「組み上がった時の位置」p（±1、p[胞の軸]＝胞の向き）から、今の位置を作る
    // 折る角度。f：0（平ら）〜1（組み上がり）。o.timing：
    //   'together'＝全部いっしょ、'stagger'＝腕が先・ふたが少しあと（armEnd・capStart）、'seq'＝腕を 1 本ずつ順に、最後にふた
    function foldAngles(f, n, o, out) {
        o = o || {};
        const N = n - 1, E = easeOf(o.ease), tm = o.timing || 'stagger';
        out = out || { arm: new Float64Array(N), cap: 0 };
        if (tm === 'seq') {
            const T = N + 1;
            for (let k = 0; k < N; k++) out.arm[k] = E(f * T - k) * HALF_PI;
            out.cap = E(f * T - N) * HALF_PI;
        } else if (tm === 'together') {
            const a = E(f) * HALF_PI; out.arm.fill(a); out.cap = a;
        } else {
            const ae = o.armEnd !== undefined ? o.armEnd : 0.62, cs = o.capStart !== undefined ? o.capStart : 0.38;
            out.arm.fill(E(Math.min(1, f / ae)) * HALF_PI);
            out.cap = E(Math.max(0, (f - cs) / (1 - cs))) * HALF_PI;
        }
        return out;
    }
    // 1 点を折る。cell：{ kind: 'center'|'arm'|'cap', axis, sign }、p：組み上がりの位置（±1 の単位）、ang：foldAngles の結果
    //   capAxis：ふたがつく腕の軸、shift：最後に軸 N に足す量（真ん中を原点に寄せる時）
    function foldPoint(cell, p, ang, out, n, capAxis, shift, si) {
        si = si || 0; out = out || new Float64Array(n);
        const N = n - 1;
        for (let k = 0; k < n; k++) out[k] = p[si + k];
        if (cell.kind === 'arm') {   // 蝶番：x_a = s, x_N = −1。x_N + 1 の分が、軸 a の外向き（平ら）→ 軸 N の向き（組み上がり）へ
            const a = cell.axis, s = cell.sign, th = ang.arm[a], d = p[si + N] + 1;
            out[a] = s * (1 + d * Math.cos(th)); out[N] = -1 + d * Math.sin(th);
        } else if (cell.kind === 'cap') {   // 腕 +capAxis の先（長さ 2）を蝶番に、腕の向きからさらに θcap
            const c = capAxis || 0, t1 = ang.arm[c], g = t1 + ang.cap, e = 1 - p[si + c];
            out[c] = 1 + 2 * Math.cos(t1) + e * Math.cos(g); out[N] = -1 + 2 * Math.sin(t1) + e * Math.sin(g);
        }
        if (shift) out[N] += shift;
        return out;
    }
    // 展開図を作る。o：size（頂点の大きさ）・capAxis（0＝n次元ビューア、1＝次元おりがみ・6次元アプリ）・
    //   center（true：組み上がりの中心が原点、平らの時は真ん中の胞が x_N = 0 ＝ 次元おりがみ／false：真ん中の胞は x_N = −1 のまま）・
    //   timing・armEnd・capStart・ease（foldAngles へ）・preset（'okami'・'hex6app'・'ndim'＝そのアプリと同じ折り方）
    //   胞の並び：真ん中、腕 +軸0、−軸0、+軸1 … −軸(N−1)、ふた（n次元ビューア・6次元アプリと同じ）
    function cubeNet(n, o) {
        o = o || {};
        const PR = o.preset && PRESETS[o.preset];   // preset：そのアプリの折り方・頂点の大きさ（書いたものが勝つ）
        o = Object.assign({}, PR ? PR.fold : null, PR ? { size: typeof PR.size === 'function' ? PR.size(n) : PR.size } : null, o);
        const N = n - 1, nl = 1 << N, h = o.size !== undefined ? o.size : 1, capAxis = o.capAxis || 0;
        const cells = [{ kind: 'center', axis: N, sign: -1 }];
        for (let k = 0; k < N; k++) for (const sg of [1, -1]) cells.push({ kind: 'arm', axis: k, sign: sg });
        cells.push({ kind: 'cap', axis: N, sign: 1 });
        const E = [], EA = [], Q = [], QC = [], QA = [];
        cells.forEach((C, ci) => {
            C.index = ci; C.off = ci * nl;
            C.free = []; for (let j = 0; j < n; j++) if (j !== C.axis) C.free.push(j);
            C.normal = new Float64Array(n); C.normal[C.axis] = C.sign;
            C.base = new Float64Array(nl * n);   // 組み上がりの位置（±1 の単位）
            for (let v = 0; v < nl; v++) { C.base[v * n + C.axis] = C.sign; C.free.forEach((ax, b) => { C.base[v * n + ax] = (v >> b) & 1 ? 1 : -1; }); }
            for (let v = 0; v < nl; v++) for (let b = 0; b < N; b++) if (!((v >> b) & 1)) { E.push(C.off + v, C.off + (v | (1 << b))); EA.push(C.free[b]); }
            for (let a = 0; a < N; a++) for (let b = a + 1; b < N; b++) for (let v = 0; v < nl; v++) {
                if ((v >> a) & 1 || (v >> b) & 1) continue;
                Q.push(C.off + v, C.off + (v | (1 << a)), C.off + (v | (1 << a) | (1 << b)), C.off + (v | (1 << b))); QC.push(ci); QA.push(C.free[a], C.free[b]);
            }
        });
        const nv = cells.length * nl, V = new Float64Array(nv * n), tmp = new Float64Array(n);
        const net = {
            kind: 'net', n, N, nl, nv, size: h, capAxis, center: !!o.center, cells, V, opts: o,
            edges: Int32Array.from(E), edgeAxis: Uint8Array.from(EA), squares: Int32Array.from(Q), squareCell: Uint16Array.from(QC), squareAxes: Uint8Array.from(QA),
            angles: { arm: new Float64Array(N), cap: 0 }, f: 1,
            // 角度を決めて V に置く
            place(ang) {
                let shift = 0;
                if (net.center) { let s = 0; for (let k = 0; k < N; k++) s += ang.arm[k]; shift = 1 - (s / N) / HALF_PI; }
                cells.forEach(C => {
                    for (let v = 0; v < nl; v++) {
                        foldPoint(C, C.base, ang, tmp, n, capAxis, shift, v * n);
                        const oo = (C.off + v) * n;
                        for (let k = 0; k < n; k++) V[oo + k] = tmp[k] * h;
                    }
                });
                return V;
            },
            // 折り具合 f（0＝平ら、1＝組み上がり）で置く。t：timing などをその時だけ変える
            fold(f, t) { net.f = f; foldAngles(f, n, t ? Object.assign({}, o, t) : o, net.angles); return net.place(net.angles); },
        };
        net.fold(o.f !== undefined ? o.f : 1);
        return net;
    }

    // ======================================================================
    // 公開
    // ======================================================================
    global.NDGeom = {
        version: VERSION, AXES, EASE, PRESETS, binom,
        planes, planeKey, identity, rotatePlane, rotation, apply, multiply, transpose, axisImage, axisVisible, rotatePoint,
        projector, distOf,
        cube, cubeCells, cubeFaces, simplex, simplexCells, cross, crossCells, fvector,
        foldAngles, foldPoint, cubeNet,
    };
    if (typeof module !== 'undefined' && module.exports) module.exports = global.NDGeom;
})(typeof window !== 'undefined' ? window : globalThis);
