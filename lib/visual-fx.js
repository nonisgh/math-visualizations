/*!
 * visual-fx.js — 次元おりがみの視覚効果（共通の部品）
 *
 * 次元おりがみ（hypercube.html）と 6次元の窓に入れた見た目の工夫を、どのアプリでも使えるように取り出したもの。
 * 使い方・仕様は同じフォルダの README.md を参照。
 *
 *   VisualFX.requestRender = n => requestRender(n);   // 描き直しが要る時に呼ばれる（無ければ毎フレーム描くアプリはそのままでよい）
 *   const P = VisualFX.palette();                      // パレット（補色モード込み）。P.px … P.nu
 *   const shine = VisualFX.shineRig({ scene, camera: () => camera, target: () => controls.target, ambient });
 *   const faces = VisualFX.sortedFaces(1000);          // 半透明の面を奥から並べて 1 つのメッシュに
 *   const lbl = VisualFX.makeLabel('w', VisualFX.axisCss('w'));   // 軸の名前の札
 *   VisualFX.mountUI(document.getElementById('fx-box'));          // 設定の欄（ON・OFF・目盛り・パレット）
 *
 * 設定は、全部のアプリで共通の localStorage キー（vfxShine・vfxLight・vfxDeep …）に入る。
 * 依存は three.js r128 だけ（THREE をグローバルに読み込んでおく）。
 */
(function (global) {
    'use strict';

    const VERSION = '1.1.1';   // 1.1.1：照り返しの不透明は、もとの濃さが 0 の面（隠した面）には足さない。   // 1.1.0：軸を 10 本（10 次元）まで
    const ls = {
        get(k) { try { const v = localStorage.getItem(k); return v === null ? null : v; } catch (_) { return null; } },
        set(k, v) { try { if (v === null || v === undefined) localStorage.removeItem(k); else localStorage.setItem(k, String(v)); } catch (_) {} },
    };
    const clamp01 = v => Math.max(0, Math.min(1, v));
    const sm = t => t * t * (3 - 2 * t);
    const hexCss = v => '#' + (v >>> 0).toString(16).padStart(6, '0');
    let _need = () => {};   // requestRender（下の api に入れたものを呼ぶ）
    const need = n => { try { _need(n); } catch (_) {} };

    // ======================================================================
    // 1. 設定（全部のアプリで共通の localStorage キー）
    // ======================================================================
    // 軸は 10 本（10 次元）まで。名前と色は n次元ビューア（ndim.html）と同じ並び：x 赤・y 緑・z 青・w 紫・v 黄・u 青緑・t ピンク・s 黄緑・r オレンジ・q 白
    const AXES = ['x', 'y', 'z', 'w', 'v', 'u', 't', 's', 'r', 'q'];
    const AXIS_HEX = { x: 0xff5d6c, y: 0x3ddc84, z: 0x56a8ff, w: 0xb07cff, v: 0xfbbf24, u: 0x2dd4bf, t: 0xf472b6, s: 0xa3e635, r: 0xfb923c, q: 0xe2e8f0 };   // 座標軸のいつもの色
    const PAL_DEF = {   // 胞・面の色（次元おりがみの 5D の列 ＋ 6次元の窓の u ＋ t〜q は軸の色を少し濃くしたもの）。p＝＋側、n＝−側
        px: 0xf43f5e, nx: 0xf43f5e, py: 0x10b981, ny: 0x10b981, pz: 0x38bdf8, nz: 0x38bdf8,
        pw: 0xa855f7, nw: 0xa855f7, pv: 0xf59e0b, nv: 0xf59e0b, pu: 0x2dd4bf, nu: 0x2dd4bf,
        pt: 0xec4899, nt: 0xec4899, ps: 0x84cc16, ns: 0x84cc16, pr: 0xf97316, nr: 0xf97316, pq: 0xcbd5e1, nq: 0xcbd5e1,
    };
    const PAL_KEYS = Object.keys(PAL_DEF);
    const KEY = {
        palette: 'vfxPalette', palComp: 'vfxPalComp', palCompCenter: 'vfxPalCompCenter', axisSync: 'vfxAxisSync',
        shine: 'vfxShine', light: 'vfxLight', deep: 'vfxDeep', inner: 'vfxInner', texFont: 'vfxTexFont', axisFit: 'vfxAxisFit',
        labelCase: 'vfxLabelCase',   // 軸の名前の札を小文字（'lower'）か大文字（'upper'）で描く
    };
    const NAME_OF_KEY = Object.fromEntries(Object.entries(KEY).map(([n, k]) => [k, n]));
    const DEF = {
        palette: Object.assign({}, PAL_DEF), palComp: false, palCompCenter: false, axisSync: { on: false, side: 'plus' },
        shine: false, light: false, deep: 0.5, inner: 0.5, texFont: true, axisFit: true, labelCase: 'lower',
    };
    const BOOLS = ['palComp', 'palCompCenter', 'shine', 'light', 'texFont', 'axisFit'];
    const NUMS = ['deep', 'inner'];

    function norm(name, v) {   // 壊れた値・古い値でも落ちないように形をそろえる
        if (BOOLS.includes(name)) return !!v;
        if (NUMS.includes(name)) { v = +v; return isFinite(v) ? clamp01(v) : DEF[name]; }
        if (name === 'axisSync') return { on: !!(v && v.on), side: v && v.side === 'minus' ? 'minus' : 'plus' };
        if (name === 'labelCase') return v === 'upper' ? 'upper' : 'lower';
        if (name === 'palette') {
            const P = Object.assign({}, PAL_DEF);
            if (v && typeof v === 'object') PAL_KEYS.forEach(k => {
                const s = v[k];
                if (typeof s === 'number' && isFinite(s)) P[k] = s & 0xffffff;
                else if (/^#?[0-9a-f]{6}$/i.test(String(s))) P[k] = parseInt(String(s).replace('#', ''), 16);
            });
            return P;
        }
        return v;
    }
    function read(name) {
        const raw = ls.get(KEY[name]);
        if (raw === null) return norm(name, DEF[name]);
        if (BOOLS.includes(name)) return raw === '1';
        if (NUMS.includes(name)) return norm(name, parseFloat(raw));
        try { return norm(name, JSON.parse(raw)); } catch (_) { return norm(name, DEF[name]); }
    }
    function write(name, v) {
        if (BOOLS.includes(name)) ls.set(KEY[name], v ? '1' : '0');
        else if (NUMS.includes(name)) ls.set(KEY[name], String(v));
        else if (name === 'palette') ls.set(KEY[name], JSON.stringify(Object.fromEntries(PAL_KEYS.map(k => [k, hexCss(v[k])]))));
        else ls.set(KEY[name], JSON.stringify(v));
    }
    const S = {};
    Object.keys(KEY).forEach(n => { S[n] = read(n); });

    const subs = new Set();
    function emit(name) {
        if (name === 'texFont' || name === 'labelCase' || name === '*') { if (S.texFont) loadTexFont(); redrawLabels(); }
        subs.forEach(fn => { try { fn(name, name === '*' ? null : get(name)); } catch (e) { console.warn('[visual-fx]', e); } });
        need(30);
    }
    function get(name) {
        const v = S[name];
        return v && typeof v === 'object' ? JSON.parse(JSON.stringify(v)) : v;
    }
    function set(name, v) {
        if (!(name in KEY)) throw new Error('[visual-fx] 知らない設定：' + name);
        if (name === 'palette') v = Object.assign({}, S.palette, v);   // 一部だけ渡してもよい
        S[name] = norm(name, v); write(name, S[name]); emit(name);
    }
    function reset(name) {
        (name ? [name] : Object.keys(KEY)).forEach(n => { S[n] = norm(n, DEF[n]); ls.set(KEY[n], null); });
        emit(name || '*');
    }
    function onChange(fn) { subs.add(fn); return () => subs.delete(fn); }
    // ほかのタブ・ほかのアプリで変えた時も、すぐこちらに反映（同じサイトのアプリは localStorage を共有している）
    if (global.addEventListener) global.addEventListener('storage', e => {
        if (e.key === null) { Object.keys(KEY).forEach(n => { S[n] = read(n); }); emit('*'); return; }
        const n = NAME_OF_KEY[e.key]; if (!n) return;
        S[n] = read(n); emit(n);
    });
    // 次元おりがみの今までのキーから、まだ vfx のキーが無い設定だけを写す（次元おりがみを乗りかえる時に 1 回呼ぶ）
    function importFrom(app) {
        if (app !== 'hypercube') return 0;
        const M = { shine: 'hypercubeShine', light: 'hypercubeLight5', deep: 'hypercubeDeep5b', inner: 'hypercubeInner5c', texFont: 'hypercubeTexFont',
            axisFit: 'hypercubeAxisFit', palComp: 'hypercubePalComp', palCompCenter: 'hypercubePalCompCenter', axisSync: 'hypercubeAxisSync' };
        let n = 0;
        Object.entries(M).forEach(([name, old]) => {
            if (ls.get(KEY[name]) !== null) return;
            const raw = ls.get(old); if (raw === null) return;
            let v; if (BOOLS.includes(name)) v = raw === '1'; else if (NUMS.includes(name)) v = parseFloat(raw); else { try { v = JSON.parse(raw); } catch (_) { return; } }
            S[name] = norm(name, v); write(name, S[name]); n++;
        });
        if (ls.get(KEY.palette) === null) {
            try { const o = JSON.parse(ls.get('hypercubeCellPalette2') || 'null'); if (o && o.d5) { S.palette = norm('palette', o.d5); write('palette', S.palette); n++; } } catch (_) {}
        }
        if (n) emit('*');
        return n;
    }

    // ======================================================================
    // 2. パレットと色の計算
    // ======================================================================
    function compHex(v) {   // 補色（色相を 180° 回す。彩度・明るさはそのまま）
        const THREE = global.THREE, c = new THREE.Color(v), h = {};
        c.getHSL(h); c.setHSL((h.h + 0.5) % 1, h.s, h.l); return c.getHex();
    }
    function palette() {   // 実際に使うパレット（補色モードなら −は＋の補色）
        const P = Object.assign({}, S.palette);
        if (S.palComp) AXES.forEach(a => { P['n' + a] = compHex(P['p' + a]); });
        return P;
    }
    const axName = a => typeof a === 'number' ? AXES[a] : a;
    // 胞・面の色。axis＝'x'〜'u' か 0〜5、sign＝+1／−1。center＝「中心」の胞（いちばん上の次元の −側）なら true（中心だけ補色の時に効く）
    function cellHex(axis, sign, center) {
        const a = axName(axis), P = palette();
        if (center && S.palCompCenter) return compHex(P['p' + a]);
        return P[(sign < 0 ? 'n' : 'p') + a];
    }
    function axisHex(axis) {   // 軸の色（軸の色を立体に合わせる ON なら、選んだ側の胞の色）
        const a = axName(axis);
        if (!S.axisSync.on) return AXIS_HEX[a];
        return palette()[(S.axisSync.side === 'minus' ? 'n' : 'p') + a];
    }
    const axisCss = axis => hexCss(axisHex(axis));
    // 色を濃く（彩度を上げて少し暗く）。C・out は {r,g,b}（THREE.Color でもよい）。t＝0 でそのまま
    function deepen(C, t, out) {
        out = out || { r: 0, g: 0, b: 0 };
        if (!(t > 0)) { out.r = C.r; out.g = C.g; out.b = C.b; return out; }
        const Y = 0.299 * C.r + 0.587 * C.g + 0.114 * C.b, sat = 1 + 1.0 * t, dk = Math.max(0.18, 1 - 0.45 * t), f = c => clamp01((Y + (c - Y) * sat) * dk);
        const r = f(C.r), g = f(C.g), b = f(C.b); out.r = r; out.g = g; out.b = b; return out;
    }

    // ======================================================================
    // 3. 照り返しライト
    // ======================================================================
    //   いつもの光に、白い主光（カメラから見て左上・手前）と逆光（右うしろ上）を足し、面を少しなめらかにして照り返しを鋭く。
    //   シェーダー uShine で鏡面反射を色そのまま＋白で約 3 倍に強め、照り返しのところだけ不透明にする（透明な面でもキラッと見える）。
    const shineU = { value: S.shine ? 1 : 0 };   // 全部の材質で 1 つを共有
    function patchShine(m) {   // MeshStandardMaterial のシェーダーに「照り返しのところは不透明に」を足す（1 回だけ）
        if (!m || m.userData.shinePatched || m.type !== 'MeshStandardMaterial') return;
        m.userData.shinePatched = true;
        const prev = m.onBeforeCompile;
        m.onBeforeCompile = function (sh, r) {
            if (prev) prev.call(this, sh, r);
            sh.uniforms.uShine = shineU;
            sh.fragmentShader = 'uniform float uShine;\n' + sh.fragmentShader.replace('gl_FragColor = vec4( outgoingLight, diffuseColor.a );',
                'float shOn = uShine * clamp(diffuseColor.a * 40.0, 0.0, 1.0); vec3 shS = reflectedLight.directSpecular; float shSp = max(max(shS.r, shS.g), shS.b);\n\tgl_FragColor = vec4( outgoingLight + shOn * (shS * 3.0 + vec3(shSp * 2.6)), clamp( diffuseColor.a + shOn * shSp * 3.0, 0.0, 1.0 ) );');
        };
        m.needsUpdate = true;
    }
    // シーンごとに 1 つ。camera・target は関数でも物でもよい（target はカメラが見ている点。OrbitControls なら controls.target）
    function shineRig(o) {
        const THREE = global.THREE;
        const fn = v => typeof v === 'function' ? v : () => v;
        const camF = fn(o.camera), tgtF = fn(o.target || null);
        const key = new THREE.PointLight(0xffffff, 1.0, 0), rim = new THREE.PointLight(0xdbeafe, 0.8, 0);   // 主光：左上・手前／逆光：右うしろ上（縁が光る）
        if (o.scene) o.scene.add(key, rim);
        const ambients = (o.ambient ? [].concat(o.ambient) : []).map(a => ({ a, i0: a.intensity }));
        const mats = [];
        const _R = new THREE.Vector3(), _U = new THREE.Vector3(), _T = new THREE.Vector3(), _C = new THREE.Vector3();
        function apply() {
            const on = S.shine;
            key.visible = rim.visible = on; shineU.value = on ? 1 : 0;
            ambients.forEach(x => { x.a.intensity = on ? x.i0 * (0.8 / 0.9) : x.i0; });   // 全体は明るくしない（光を足すぶん少しだけ下げる）
            mats.forEach(m => { const [r0, m0] = m.userData.shine0; m.roughness = on ? r0 * 0.8 : r0; m.metalness = m0; });   // 少しなめらかに＝キラッが鋭く小さく
        }
        function addMaterial(...ms) {
            ms.flat().forEach(m => {
                if (!m || m.roughness === undefined || mats.includes(m)) return;
                if (m.userData.shine0 === undefined) m.userData.shine0 = [m.roughness, m.metalness];
                patchShine(m); mats.push(m);
            });
            apply();
        }
        function update() {   // 描く直前に呼ぶ：光をカメラから見た左上へ（回してもいつも照り返しが見える）
            if (!S.shine) return;
            const cam = camF(); if (!cam) return;
            const t = tgtF(); _T.set(0, 0, 0); if (t) _T.copy(t);
            const D = cam.position.distanceTo(_T) || 10;
            _R.set(1, 0, 0).applyQuaternion(cam.quaternion); _U.set(0, 1, 0).applyQuaternion(cam.quaternion);
            _C.copy(cam.position).sub(_T);
            key.position.copy(_T).addScaledVector(_C, 0.55).addScaledVector(_U, D * 0.42).addScaledVector(_R, -D * 0.32);
            rim.position.copy(_T).addScaledVector(_C, -0.6).addScaledVector(_U, D * 0.35).addScaledVector(_R, D * 0.55);
        }
        const off = onChange(n => { if (n === 'shine' || n === '*') apply(); });
        apply();
        return { key, rim, addMaterial, update, apply, dispose() { off(); key.removeFromParent(); rim.removeFromParent(); } };
    }

    // ======================================================================
    // 4. 軸の名前の札（書体・大きさを保つ・軸の見切れ防止）
    // ======================================================================
    let texFontState = 'none';   // none → loading → ready / failed（オフラインなどで読めなければ、いつもの書体のまま）
    const labels = [];           // 書体を切り替えた時に描き直すため、作った札を覚えておく
    function labelFont(text) {
        if (!S.texFont) return '500 44px system-ui, -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif';
        if (texFontState === 'ready') return 'italic 48px TeXMath, Georgia, serif';
        // TeX の書体が読めない時：z だけは Georgia の斜体だと大文字 Z に見えるので、下がくるっと巻いた小文字らしい z の書体にする
        return text === 'z' && S.labelCase !== 'upper' ? 'italic 46px "Hoefler Text", Didot, Georgia, serif' : 'italic 42px Georgia, "Times New Roman", serif';
    }
    function labelText(text) { return S.labelCase === 'upper' ? String(text).toUpperCase() : String(text).toLowerCase(); }   // 軸の名前を、設定の小文字／大文字で
    function drawLabel(cv, text, css) {
        const ctx = cv.getContext('2d'); ctx.clearRect(0, 0, cv.width, cv.height);
        ctx.font = labelFont(text); ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        const t = labelText(text);   // 小文字／大文字の設定（札に覚えている名前はそのまま）
        ctx.lineWidth = 5; ctx.strokeStyle = 'rgba(2,6,18,0.9)'; ctx.strokeText(t, 32, 34);
        ctx.fillStyle = css; ctx.fillText(t, 32, 34);
    }
    function loadTexFont() {   // KaTeX の数式用斜体（TeX の cmmi と同じ字形）。読めたら札を描き直す
        if (texFontState !== 'none' || typeof FontFace === 'undefined') return;
        texFontState = 'loading';
        new FontFace('TeXMath', 'url(https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/fonts/KaTeX_Math-Italic.woff2) format("woff2")', { style: 'italic' }).load()
            .then(f => { document.fonts.add(f); texFontState = 'ready'; redrawLabels(); })
            .catch(() => { texFontState = 'failed'; });
    }
    function redrawLabels() {
        labels.forEach(L => { drawLabel(L.cv, L.text, L.css); L.tex.needsUpdate = true; });
        need(10);
    }
    // 軸が手前にせり出しても文字が大きくならないように：描く直前に、親（図形の中心）と同じ奥行きにある時の大きさへ直す
    //   （カメラのズームで大きさが変わるのは今まで通り。奥へ行っても小さくならない）
    let _lblV = null, _lblO = null;
    function keepLabelSize(sp, cam, base) {
        if (!cam || !cam.isPerspectiveCamera || !sp.parent) return;
        const THREE = global.THREE; if (!_lblV) { _lblV = new THREE.Vector3(); _lblO = new THREE.Vector3(); }
        _lblV.setFromMatrixPosition(sp.matrixWorld).applyMatrix4(cam.matrixWorldInverse);
        _lblO.setFromMatrixPosition(sp.parent.matrixWorld).applyMatrix4(cam.matrixWorldInverse);
        const d = -_lblV.z, d0 = -_lblO.z;
        if (!(d > 0.05) || !(d0 > 0.05)) return;
        sp.scale.setScalar(base * d / d0);
        sp.updateMatrix(); sp.matrixWorld.multiplyMatrices(sp.parent.matrixWorld, sp.matrix);   // この描画にすぐ反映
    }
    function makeLabel(text, css, opt) {
        const o = Object.assign({ scale: 0.52, keepSize: true }, opt || {});
        const THREE = global.THREE;
        if (S.texFont) loadTexFont();
        const cv = document.createElement('canvas'); cv.width = 64; cv.height = 64;
        drawLabel(cv, text, css);
        const tex = new THREE.CanvasTexture(cv);
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true }));
        sp.scale.setScalar(o.scale); sp.renderOrder = 1001;
        if (o.keepSize) sp.onBeforeRender = (r, sc, cam) => keepLabelSize(sp, cam, o.scale);
        const L = { cv, tex, text, css, sp };
        labels.push(L); sp.userData.vfxLabel = L;
        return sp;
    }
    function recolorLabel(sp, css) {   // 札の字の色を変える（同じ色なら何もしない）
        const L = sp && sp.userData && sp.userData.vfxLabel; if (!L || L.css === css) return;
        L.css = css; drawLabel(L.cv, L.text, css); L.tex.needsUpdate = true; need(10);
    }
    function disposeLabel(sp) {
        const i = labels.findIndex(L => L.sp === sp); if (i < 0) return;
        const L = labels.splice(i, 1)[0]; L.tex.dispose(); sp.material.dispose();
    }

    // 軸の見切れ防止：軸の先（名前の位置）が画面の枠からはみ出しそうなら、軸を縮める倍率を返す（やわらかく枠に近づく）
    const AXFIT = { MX: 0.88, MT: 0.8, MB: 0.74, LK: 1.2, SOFT: 0.75, TAU: 0.22 };
    let _fitV = null;
    function axisFitTarget(tip, root, cam) {
        if (!S.axisFit || !root || !cam) return 1;
        if (!_fitV) _fitV = new global.THREE.Vector3();
        const ratio = k => {   // 名前の位置が、枠に対してどこまで来ているか（1＝ちょうど枠）。カメラの後ろなら大きい値
            _fitV.set(tip[0] * k, tip[1] * k, tip[2] * k); root.localToWorld(_fitV); _fitV.project(cam);
            if (!(_fitV.z < 1)) return 99;
            return Math.max(Math.abs(_fitV.x) / AXFIT.MX, _fitV.y >= 0 ? _fitV.y / AXFIT.MT : -_fitV.y / AXFIT.MB);
        };
        _fitV.set(0, 0, 0); root.localToWorld(_fitV); _fitV.project(cam);
        if (!(_fitV.z < 1) || Math.abs(_fitV.x) > 1 || Math.abs(_fitV.y) > 1) return 1;   // 原点が画面の外なら縮めない
        const r = ratio(AXFIT.LK);
        if (r <= AXFIT.SOFT) return 1;
        // やわらかい枠：r を、SOFT から先は 1 に近づくだけの位置 q に置きかえる（つなぎ目もなめらか）
        const s0 = AXFIT.SOFT, q = s0 + (1 - s0) * (1 - Math.exp(-(r - s0) / (1 - s0)));
        let lo = 0.2, hi = 1;
        if (ratio(lo * AXFIT.LK) > q) return lo;
        for (let it = 0; it < 12; it++) { const m = (lo + hi) / 2; if (ratio(m * AXFIT.LK) <= q) lo = m; else hi = m; }
        return lo;
    }
    const _fitCur = new Map();   // 軸ごとの今の縮み具合（時間でならす）
    // tip＝root の中での軸の先 [x,y,z]。key を渡すと約 0.2 秒かけてなめらかに縮む・戻る。縮めた先を返す
    function fitTip(tip, root, cam, key) {
        const target = axisFitTarget(tip, root, cam);
        let k = target;
        if (key !== undefined && key !== null) {
            const now = performance.now(), st = _fitCur.get(key);
            if (st) {
                const dt = Math.min(0.5, Math.max(0, (now - st.t) / 1000));
                k = st.k + (target - st.k) * (1 - Math.exp(-dt / AXFIT.TAU));
                if (Math.abs(target - k) > 0.003) need(3);   // 止まったあとも、追いつくまでは描く
                else k = target;
            }
            _fitCur.set(key, { k, t: now });
        }
        return k < 0.9999 ? [tip[0] * k, tip[1] * k, tip[2] * k] : tip;
    }
    function axisFitPrep(root, cam) { if (root) root.updateMatrixWorld(); if (cam) cam.updateMatrixWorld(); }   // fitTip の前に 1 回

    // ======================================================================
    // 5. 半透明の面を奥から並べて 1 つのメッシュにまとめる（RGBA の頂点カラー）
    // ======================================================================
    //   毎フレーム clear() → quad()/tri() で面を入れる → commit(camera)。全部の面を「全体で」遠い順に並べて描くので、
    //   重なった胞・入れ子の胞も三角形単位で正しく前後が合成される（真上から見ても色が混ざる）
    function sortedFaces(maxQuads, opt) {
        const THREE = global.THREE, o = opt || {};
        const N = Math.max(1, maxQuads | 0);
        // 面のデータ（頂点 4 つ）は入れた順のまま置き、描く順番の表（インデックス）だけを遠い順に並べかえる＝毎コマ書き写す量が少ない
        const g = new THREE.BufferGeometry();
        const pos = new Float32Array(N * 4 * 3), col = new Float32Array(N * 4 * 4), nrm = new Float32Array(N * 4 * 3);
        const index = new THREE.BufferAttribute(N * 4 > 65535 ? new Uint32Array(N * 6) : new Uint16Array(N * 6), 1);
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('color', new THREE.BufferAttribute(col, 4));   // RGB＋アルファ（面ごとの濃さ）
        g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));  // 面の向き（面ごとに 1 回だけ計算）
        g.setIndex(index);
        g.setDrawRange(0, 0);
        const mat = new THREE.MeshStandardMaterial(Object.assign({ vertexColors: true, transparent: true, opacity: 1, roughness: 0.15, metalness: 0.5, side: THREE.DoubleSide, depthWrite: false }, o.material || {}));
        const mesh = new THREE.Mesh(g, mat);
        mesh.frustumCulled = false;
        mesh.renderOrder = o.renderOrder !== undefined ? o.renderOrder : -1;   // 面は線より先に描く＝手前の線が面に薄められず、くっきり乗る
        // 並べかえは「近さ（30 ビットまで）× 2^IB ＋ 面の番号」の数を、ブラウザ組みこみの数の並べかえで（比べる関数を使わないので速い）
        const KEY = new Float64Array(N), IB = Math.max(1, Math.ceil(Math.log2(N + 1))), SH = Math.pow(2, IB), QMAX = Math.pow(2, Math.min(30, 52 - IB)) - 1;
        const ix = index.array;
        let n = 0, warned = false;
        const _cam = new THREE.Vector3();
        const one = c => (c && c.length === 4 && typeof c[0] !== 'number') ? c : null;   // 頂点ごとの色 [c0,c1,c2,c3] か、全体で 1 色か
        function rgba(c, k, j) {   // c＝[r,g,b,a] か {r,g,b,a}
            const per = one(c), x = per ? per[j] : c;
            if (Array.isArray(x) || ArrayBuffer.isView(x)) { col[k] = x[0]; col[k + 1] = x[1]; col[k + 2] = x[2]; col[k + 3] = x[3] === undefined ? 1 : x[3]; }
            else { col[k] = x.r; col[k + 1] = x.g; col[k + 2] = x.b; col[k + 3] = x.a === undefined ? 1 : x.a; }
        }
        function quad(a, b, c, d, color) {   // 四角形（a→b→c→d の順）。color＝1 色か、頂点ごとの 4 色
            if (n >= N) { if (!warned) { warned = true; console.warn('[visual-fx] sortedFaces の数が足りません', N); } return; }
            const p = n * 12, q = n * 16;
            pos[p] = a[0]; pos[p + 1] = a[1]; pos[p + 2] = a[2]; pos[p + 3] = b[0]; pos[p + 4] = b[1]; pos[p + 5] = b[2];
            pos[p + 6] = c[0]; pos[p + 7] = c[1]; pos[p + 8] = c[2]; pos[p + 9] = d[0]; pos[p + 10] = d[1]; pos[p + 11] = d[2];
            // 面の向き＝(c−b)×(a−b)（computeVertexNormals と同じ向き）
            const ux = c[0] - b[0], uy = c[1] - b[1], uz = c[2] - b[2], vx = a[0] - b[0], vy = a[1] - b[1], vz = a[2] - b[2];
            let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
            const nl = Math.hypot(nx, ny, nz) || 1; nx /= nl; ny /= nl; nz /= nl;
            for (let j = 0; j < 4; j++) { nrm[p + j * 3] = nx; nrm[p + j * 3 + 1] = ny; nrm[p + j * 3 + 2] = nz; rgba(color, q + j * 4, j); }
            n++;
        }
        function tri(a, b, c, color) {   // 三角形。color＝1 色か、頂点ごとの 3 色
            const per = Array.isArray(color) && color.length === 3 && typeof color[0] !== 'number';
            quad(a, b, c, c, per ? [color[0], color[1], color[2], color[2]] : color);
        }
        function commit(camera, sort) {   // sort＝false で並べかえない（入れた順に描く。比べる時用）
            mesh.updateWorldMatrix(true, false);
            camera.getWorldPosition(_cam); mesh.worldToLocal(_cam);
            const keys = KEY.subarray(0, n);
            if (sort === false) { for (let i = 0; i < n; i++) keys[i] = i; }
            else {
                let dMax = 1e-12;
                for (let i = 0; i < n; i++) {   // 面の真ん中とカメラの距離（2 乗）
                    const p = i * 12;
                    const x = (pos[p] + pos[p + 3] + pos[p + 6] + pos[p + 9]) / 4 - _cam.x, y = (pos[p + 1] + pos[p + 4] + pos[p + 7] + pos[p + 10]) / 4 - _cam.y, z = (pos[p + 2] + pos[p + 5] + pos[p + 8] + pos[p + 11]) / 4 - _cam.z;
                    const d = x * x + y * y + z * z; keys[i] = d; if (d > dMax) dMax = d;
                }
                for (let i = 0; i < n; i++) keys[i] = Math.floor((1 - keys[i] / dMax) * QMAX) * SH + i;   // 遠いほど小さい数
                keys.sort();   // 遠い面を先に描く
            }
            for (let s = 0, w = 0; s < n; s++) {
                const kk = keys[s], v = (kk - Math.floor(kk / SH) * SH) * 4;
                ix[w++] = v; ix[w++] = v + 1; ix[w++] = v + 2; ix[w++] = v; ix[w++] = v + 2; ix[w++] = v + 3;
            }
            g.setDrawRange(0, n * 6);
            index.needsUpdate = true;
            for (const k of ['position', 'color', 'normal']) { const at = g.attributes[k]; at.needsUpdate = true; at.updateRange.offset = 0; at.updateRange.count = n * 4 * at.itemSize; }   // 使っている所だけ GPU へ
        }
        return { mesh, material: mat, geometry: g, quad, tri, commit, clear() { n = 0; }, get count() { return n; }, max: N };
    }

    // ======================================================================
    // 6. 高い次元の光（4Dライト・6次元の光）
    // ======================================================================
    //   n 次元空間に固定した光。各胞の外向きの向き（n 次元）を今の回し方で回したものと、光との内積で胞ごとの明るさを出す
    //   ＝3D の影が同じでも、4 次元目・5 次元目で回すと光の当たる胞が入れかわる（高い次元で回っていることが光で分かる）
    const LIGHT_BASE = [0.35, 0.9, 0.5, 0.9, 0.7, 0.8];   // w・v・u 成分を強めに（5 次元＝LIGHT5、6 次元＝LIGHT6 と同じ）。7 本目から先は 0.8
    const LIGHT_AMB = 0.32;                                // 光が当たらない胞の明るさ
    const _lightDir = {};
    function lightDir(n) {
        if (_lightDir[n]) return _lightDir[n];
        const v = [...Array(n)].map((_, i) => i < LIGHT_BASE.length ? LIGHT_BASE[i] : 0.8), l = Math.hypot(...v);
        return (_lightDir[n] = v.map(a => a / l));
    }
    // 回したあとの外向きの向き nRot（長さ n の配列）→ 明るさ LIGHT_AMB〜1。設定が OFF なら 1
    function light(nRot, force) {
        if (!S.light && !force) return 1;
        const L = lightDir(nRot.length); let d = 0;
        for (let k = 0; k < L.length; k++) d += nRot[k] * L[k];
        return LIGHT_AMB + (1 - LIGHT_AMB) * Math.max(0, d);
    }
    // 外向きの向きを作る：axis 番目の軸の sign 側（0〜n−1）。rotate を渡すと回したものを返す
    function axisNormal(n, axis, sign, rotate) {
        const v = new Array(n).fill(0); v[axis] = sign < 0 ? -1 : 1;
        return rotate ? rotate(v) : v;
    }

    // ======================================================================
    // 7. 奥の胞を濃く・入れ子の内側を濃く
    // ======================================================================
    //   K＝頂点ごとの「見かけの縮み」（遠近で何倍に写っているか。大きいほど手前）。高い次元の遠近を何段か掛けたもの（例 su*sv*sw）
    //   正面図の入れ子の四角は w・v の遠近で小さく見えている（カメラからの距離はほぼ同じ）ので、距離ではなく見かけの縮みで測る
    function cellDepth(K) {   // K[胞][頂点] → 胞ごとの奥行き 0（いちばん手前）〜1（いちばん奥）
        const m = K.map(a => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i]; return s / Math.max(1, a.length); });
        const lo = Math.min(...m), sp = Math.max(Math.max(...m) - lo, 1e-6);
        return m.map(x => 1 - (x - lo) / sp);
    }
    function innerAmount(faceK, faceCell) {   // 面ごとの見かけの縮みと胞の番号 → 各胞の中で 0（外側の面）〜1（入れ子のいちばん内側の面）
        const lo = [], hi = [], m = faceK.length, out = new Array(m);
        for (let i = 0; i < m; i++) { const c = faceCell[i], k = faceK[i]; if (!(lo[c] <= k)) lo[c] = k; if (!(hi[c] >= k)) hi[c] = k; }
        for (let i = 0; i < m; i++) { const c = faceCell[i]; out[i] = clamp01((hi[c] - faceK[i]) / Math.max(hi[c] - lo[c], 1e-6)); }
        return out;
    }
    // 面の色と濃さ。C＝もとの色 {r,g,b}、o.deep＝胞の奥行き 0〜1、o.inner＝入れ子の内側ぐあい 0〜1、o.lit＝光の明るさ、o.alpha＝もとの濃さ
    //   返り値 out＝{r,g,b,a}（sortedFaces の quad にそのまま渡せる）
    function shadeFace(C, o, out) {
        out = out || { r: 0, g: 0, b: 0, a: 1 };
        const kD = 2 * S.deep, kI = 3.75 * S.inner;   // 効き：奥＝目盛り×2、内側＝目盛り×3.75（50% がユーザーの好んだ強さ）
        const deep = clamp01(o.deep || 0), tIn = kI * sm(clamp01(o.inner || 0)), lit = o.lit === undefined ? 1 : o.lit;
        deepen(C, kD * sm(deep) * 0.8, out); deepen(out, tIn, out);   // 奥ほど・内側ほど鮮やかに少し暗く＝「濃い」色
        out.r *= lit; out.g *= lit; out.b *= lit;
        const a0 = o.alpha === undefined ? 1 : o.alpha;
        out.a = Math.min(o.maxAlpha || 0.95, a0 * Math.max(0.12, 1 - 0.45 * kD + 1.05 * kD * deep) * (1 + 1.4 * tIn));   // 手前の胞は薄く、奥の胞は濃く＝奥の濃い色が手前を透かして見える
        return out;
    }
    // 線（辺）の色：手前ほど明るく、光の当たらない胞は暗く（6次元の窓と同じ式）
    function shadeLine(C, o, out) {
        out = out || { r: 0, g: 0, b: 0 };
        const br = (0.55 + 0.45 * (1 - clamp01(o.deep || 0))) * (0.4 + 0.6 * (o.lit === undefined ? 1 : o.lit));
        out.r = Math.min(1, (C.r * 0.75 + 0.25) * br); out.g = Math.min(1, (C.g * 0.75 + 0.25) * br); out.b = Math.min(1, (C.b * 0.75 + 0.25) * br);
        return out;
    }

    // ======================================================================
    // 8. 設定の欄
    // ======================================================================
    const CSS = `
.vfx-box{font:12px/1.5 system-ui,-apple-system,'Hiragino Sans',sans-serif;color:#cbd5e1}
.vfx-title{font-weight:700;color:#bae6fd;margin-bottom:4px}
.vfx-note{font-size:11px;color:#64748b;margin:2px 0 6px}
.vfx-row{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:6px}
.vfx-lab{min-width:118px;color:#94a3b8}
.vfx-btn{background:#1e293b;border:1px solid #475569;border-radius:7px;color:#cbd5e1;padding:4px 10px;font-size:12px;cursor:pointer;white-space:nowrap}
.vfx-btn:hover{background:#334155}
.vfx-btn.on{background:rgba(12,74,110,.55);border-color:#38bdf8;color:#e0f2fe;font-weight:700}
.vfx-rng{flex:1;min-width:110px;accent-color:#38bdf8}
.vfx-val{font:600 12px ui-monospace,Menlo,monospace;min-width:40px;text-align:right}
.vfx-pal{display:grid;grid-template-columns:auto 1fr 1fr;gap:4px 8px;align-items:center;margin-top:6px}
.vfx-pal span{font:italic 15px Georgia,serif;text-align:center}
.vfx-pal input{width:100%;height:24px;border:1px solid #334155;border-radius:5px;background:#0f172a;padding:1px}
.vfx-pal input:disabled{opacity:.5}
.vfx-pal .h{font:11px system-ui,sans-serif;color:#64748b;text-align:center}`;
    // el の中に設定の欄を作る。o.axes＝パレットに出す軸（既定 'xyzwv'）、o.title＝見出し（空なら出さない）
    function mountUI(el, opt) {
        if (!el) return null;
        const o = Object.assign({ axes: 'xyzwv', title: '見た目の効果' }, opt || {});
        const axes = String(o.axes).split('').filter(a => AXES.includes(a));
        if (!document.getElementById('vfx-style')) { const st = document.createElement('style'); st.id = 'vfx-style'; st.textContent = CSS; document.head.appendChild(st); }
        el.classList.add('vfx-box');
        const tog = (name, label) => `<div class="vfx-row"><span class="vfx-lab">${label}</span><button type="button" class="vfx-btn" data-t="${name}"></button></div>`;
        const rng = (name, label) => `<div class="vfx-row"><span class="vfx-lab">${label}</span><input class="vfx-rng" type="range" min="0" max="1" step="0.01" data-r="${name}"><span class="vfx-val" data-v="${name}"></span></div>`;
        el.innerHTML = (o.title ? `<div class="vfx-title">${o.title}</div>` : '') +
            `<div class="vfx-note">この設定は同じサイトのアプリ全部で共通です（このブラウザに保存）。</div>` +
            tog('shine', '照り返しライト') + tog('light', '高い次元の光') +
            rng('deep', '奥の胞を濃く') + rng('inner', '入れ子の内側を濃く') +
            `<div class="vfx-row"><span class="vfx-lab">軸の名前の書体</span><button type="button" class="vfx-btn" data-f="1">TeX の斜体</button><button type="button" class="vfx-btn" data-f="0">サンセリフ</button></div>` +
            tog('axisFit', '軸の見切れ防止') +
            `<div class="vfx-row"><span class="vfx-lab">軸の色を立体に合わせる</span><button type="button" class="vfx-btn" data-s="off">OFF</button><button type="button" class="vfx-btn" data-s="plus">＋側</button><button type="button" class="vfx-btn" data-s="minus">−側</button></div>` +
            tog('palComp', '補色モード（−＝＋の補色）') + tog('palCompCenter', '中心だけ補色') +
            `<div class="vfx-pal"><b class="h"></b><b class="h">＋側</b><b class="h">−側</b>${axes.map(a => `<span style="color:${hexCss(AXIS_HEX[a])}">${a}</span><input type="color" data-p="p${a}"><input type="color" data-p="n${a}">`).join('')}</div>` +
            `<div class="vfx-row"><button type="button" class="vfx-btn" data-a="palReset">パレットを既定に戻す</button><button type="button" class="vfx-btn" data-a="allReset">全部を既定に戻す</button></div>`;
        const q = s => el.querySelectorAll(s);
        q('[data-t]').forEach(b => b.onclick = () => set(b.dataset.t, !S[b.dataset.t]));
        q('[data-r]').forEach(r => r.oninput = () => set(r.dataset.r, parseFloat(r.value)));
        q('[data-f]').forEach(b => b.onclick = () => set('texFont', b.dataset.f === '1'));
        q('[data-s]').forEach(b => b.onclick = () => set('axisSync', b.dataset.s === 'off' ? { on: false, side: S.axisSync.side } : { on: true, side: b.dataset.s }));
        q('[data-p]').forEach(i => i.oninput = () => set('palette', { [i.dataset.p]: i.value }));
        el.querySelector('[data-a=palReset]').onclick = () => reset('palette');
        el.querySelector('[data-a=allReset]').onclick = () => { if (confirm('見た目の効果の設定を全部、既定に戻しますか？（ほかのアプリにも効きます）')) reset(); };
        function render() {
            q('[data-t]').forEach(b => { const on = S[b.dataset.t]; b.textContent = on ? 'ON' : 'OFF'; b.classList.toggle('on', on); });
            q('[data-r]').forEach(r => { if (document.activeElement !== r) r.value = S[r.dataset.r]; });
            q('[data-v]').forEach(v => { v.textContent = Math.round(S[v.dataset.v] * 100) + '%'; });
            q('[data-f]').forEach(b => b.classList.toggle('on', (b.dataset.f === '1') === S.texFont));
            q('[data-s]').forEach(b => b.classList.toggle('on', b.dataset.s === 'off' ? !S.axisSync.on : S.axisSync.on && S.axisSync.side === b.dataset.s));
            const P = palette();
            q('[data-p]').forEach(i => { if (document.activeElement !== i) i.value = hexCss(P[i.dataset.p]); i.disabled = S.palComp && i.dataset.p[0] === 'n'; });
        }
        const off = onChange(render);
        render();
        return { render, dispose() { off(); el.innerHTML = ''; } };
    }

    const api = {
        version: VERSION,
        // 設定
        get, set, reset, onChange, importFrom, keys: Object.assign({}, KEY), defaults: JSON.parse(JSON.stringify(DEF)),
        // 色
        AXES, AXIS_HEX: Object.assign({}, AXIS_HEX), PAL_DEF: Object.assign({}, PAL_DEF), palette, compHex, cellHex, axisHex, axisCss, hexCss, deepen,
        // 照り返し
        shineRig, patchShine, shineUniform: shineU,
        // 札・軸
        makeLabel, recolorLabel, redrawLabels, disposeLabel, drawLabel, labelFont, labelText, loadTexFont, keepLabelSize, axisFitTarget, fitTip, axisFitPrep,
        // まとめメッシュ
        sortedFaces,
        // 高い次元の光
        light, lightDir, axisNormal, LIGHT_AMB,
        // 奥・内側を濃く
        cellDepth, innerAmount, shadeFace, shadeLine, smooth: sm,
        // 欄
        mountUI,
    };
    Object.defineProperty(api, 'requestRender', { get: () => _need, set: f => { _need = typeof f === 'function' ? f : () => {}; } });
    Object.defineProperty(api, 'settings', { get: () => Object.fromEntries(Object.keys(KEY).map(n => [n, get(n)])) });
    if (S.texFont && typeof document !== 'undefined') loadTexFont();
    global.VisualFX = api;
})(typeof window !== 'undefined' ? window : this);
