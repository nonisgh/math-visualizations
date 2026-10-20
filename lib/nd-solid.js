/*!
 * nd-solid.js — 高い次元の立体を「物」らしく見せる質感（共通の部品）
 *
 * 次元おりがみの 5 次元（展開図の折りたたみもふくむ）を、線にたよらず、ガラス・結晶・樹脂のような立体に見せるための描き方。
 * 6 次元より上にもそのまま使える。使い方・仕様は同じフォルダの README.md を参照。
 *
 *   const faces = NDSolid.faces(maxQuads, 'glass', renderer);   // 半透明の面（visual-fx の sortedFaces ＋ ガラスの材質）
 *   const rods  = NDSolid.rods(maxEdges, maxVerts, renderer);    // 辺を管に、頂点を玉に（光と影がつく）
 *   NDSolid.tint(color, 'glass', out);                           // 質感ごとの色の整え方
 *   const lit = NDSolid.planeShade(R, n, V, i0, i1, i3, L);      // n 次元の中での面の向きと光の角度から、面ごとの明るさ
 *
 * 依存：three.js r128 と visual-fx.js（sortedFaces・色）。n 次元の計算は nd-geom.js を使うと楽（なくてもよい）。
 */
(function (global) {
    'use strict';

    const VERSION = '1.2.2';   // 1.2.2：「もとの濃さ」は照り返しで足される前の diffuseColor.a で見る（照り返しライト ON の時も隠した面が光らない）。   // 1.2.1：もとの濃さが 0 の面（隠した胞など）には、フレネル・縁の光・照り返しの不透明を足さない（前は隠した胞が光って残った）。   // 1.2.0：ビビッド。   // 1.1.0：透明プラスチック（乗算）・ホログラム（加算）、色と濃さをシェーダーの中でも（inShader）
    const T = () => global.THREE;
    const VFX = () => global.VisualFX;

    // ======================================================================
    // 1. 質感
    // ======================================================================
    //   base：面 1 枚の濃さ（shadeFace の alpha に渡す）。fresA・fresP：斜めから見るほど濃く・光る（フレネル）。
    //   rim・rimK：縁の光の色と強さ。lumT・lumK：照り返し（鏡のような反射・映り込み）が明るいところは不透明に（本物のガラスのキラッ）。
    //   rough・metal・env：面のなめらかさ・金属っぽさ・周りの映り込みの強さ。sat・lift：色の鮮やかさ・明るさの整え方。
    //   k5：今までの濃さに掛ける割合（無ければ base ÷ 0.16）。面がとても多く重なる時（次元おりがみの 5次元）に、乗算・加算で黒・白につぶれないように弱くする
    const LOOKS = {
        classic: { name: '今まで', base: 0.16, fresA: 0, fresP: 2, rim: [1, 1, 1], rimK: 0, lumT: 2, lumK: 0, rough: 0.15, metal: 0.5, env: 0, sat: 1, lift: 0, rods: false },
        glass: { name: '擦りガラス', base: 0.07, fresA: 0.62, fresP: 2.4, rim: [0.82, 0.9, 1.0], rimK: 0.42, lumT: 0.5, lumK: 1.8, rough: 0.04, metal: 0.0, env: 1.5, sat: 0.6, lift: 0.06, rods: true,
            rod: { rough: 0.12, metal: 0.25, env: 1.1, r: 0.022, ball: 0.042 } },
        crystal: { name: '結晶', base: 0.12, fresA: 0.5, fresP: 1.8, rim: [1.0, 0.97, 0.92], rimK: 0.3, lumT: 0.45, lumK: 1.5, rough: 0.07, metal: 0.12, env: 1.7, sat: 1.2, lift: 0, rods: true,
            rod: { rough: 0.1, metal: 0.5, env: 1.3, r: 0.02, ball: 0.04 } },
        resin: { name: '樹脂', base: 0.26, fresA: 0.18, fresP: 1.4, rim: [1, 1, 1], rimK: 0.12, lumT: 0.85, lumK: 0.6, rough: 0.5, metal: 0.0, env: 0.45, sat: 0.8, lift: 0.14, rods: true,
            rod: { rough: 0.45, metal: 0.0, env: 0.5, r: 0.026, ball: 0.048 } },
        // ビビッド：面を濃いめ・色を鮮やかに、つやのあるプラスチック（ふつうの重ね方）。線にたよらず、色の面で胞の形を見せる。
        //   金属っぽさ 0（光が色そのものに当たる＝今までの metalness 0.5 より色が明るく鮮やか）、映り込みと照り返しは控えめ（白く飛ばない）
        vivid: { name: 'ビビッド', base: 0.34, fresA: 0.12, fresP: 2.2, rim: [1, 1, 1], rimK: 0, lumT: 0.95, lumK: 0.4, rough: 0.42, metal: 0.0, env: 0.12, sat: 1.35, lift: 0, rods: true,
            rod: { rough: 0.3, metal: 0.2, env: 0.6, r: 0.016, ball: 0.032 } },
        // 透明プラスチック（乗算）：色つきのセロハンを重ねたように、後ろの色に面の色を掛ける＝重なるほど色が深くなる。明るい背景（bg）で見る。
        //   斜めの面ほど濃く（フレネル）＝縁が自然に締まる。掛け算なので描く順番に関係なく正しく混ざる。何十枚も重なるので 1 枚ずつはごく淡く（強いと黒くつぶれる）
        film: { name: '透明プラスチック', blend: 'multiply', bg: 0xeef1f6, base: 0.17, k5: 0.17, fresA: 0.22, fresP: 2.2, rim: [1, 1, 1], rimK: 0, lumT: 2, lumK: 0, rough: 0.3, metal: 0.0, env: 0, sat: 1.3, lift: 0.32, rods: true,
            rod: { rough: 0.35, metal: 0.05, env: 0.6, r: 0.016, ball: 0.032 } },
        // ホログラム（加算）：暗い背景で、重なるほど光が足されて明るくなる。縁がふわっと光る。これも描く順番に関係なし。1 枚ずつはごく弱く（強いと白くとぶ）。照り返し（鏡の反射）が積み重なると白い筋になるので、ざらざら（rough 1）にして照り返しを出さない
        holo: { name: 'ホログラム', blend: 'add', base: 0.05, k5: 0.045, fresA: 0.18, fresP: 1.8, rim: [0.65, 0.88, 1.0], rimK: 0.3, lumT: 2, lumK: 0, rough: 1.0, metal: 0.0, env: 0, sat: 1.6, lift: 0, rods: true,
            rod: { rough: 0.3, metal: 0.2, env: 0.4, r: 0.012, ball: 0.026 } },
    };
    const lookOf = l => (typeof l === 'string' ? LOOKS[l] : l) || LOOKS.glass;

    // 色を質感に合わせて整える（ガラスは淡く、結晶は鮮やかに、樹脂は明るいパステルに）。C・out は {r,g,b}
    function tint(C, look, out) {
        const L = lookOf(look); out = out || { r: 0, g: 0, b: 0 };
        const Y = 0.299 * C.r + 0.587 * C.g + 0.114 * C.b, f = c => Math.max(0, Math.min(1, (Y + (c - Y) * L.sat) * (1 - L.lift) + L.lift));
        out.r = f(C.r); out.g = f(C.g); out.b = f(C.b); return out;
    }

    // ======================================================================
    // 2. 周りの映り込み（その場で作るスタジオ。画像の読み込みは要らない）
    // ======================================================================
    //   上が明るく下が暗い空＋ふわっとした白い照明 3 枚を、PMREM でぼかした映り込みの絵にする。つやのある面に周りの光が映り、物らしくなる
    const _env = new WeakMap();
    function envMap(renderer) {
        if (_env.has(renderer)) return _env.get(renderer);
        const THREE = T(), sc = new THREE.Scene();
        const g = new THREE.SphereGeometry(50, 32, 16), col = [], pos = g.attributes.position;
        for (let i = 0; i < pos.count; i++) {
            const y = pos.getY(i) / 50, t = (y + 1) / 2;   // 下 0 〜 上 1
            const top = [0.55, 0.62, 0.78], bot = [0.015, 0.02, 0.05], mid = [0.12, 0.13, 0.2];
            const c = t > 0.5 ? mid.map((m, k) => m + (top[k] - m) * Math.pow((t - 0.5) * 2, 1.5)) : bot.map((b, k) => b + (mid[k] - b) * (t * 2));
            col.push(...c);
        }
        g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
        sc.add(new THREE.Mesh(g, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
        [[-18, 22, 14, 14, 10, 1.6], [24, 8, 6, 8, 14, 0.9], [2, 14, -26, 20, 6, 0.7]].forEach(([x, y, z, w, h, k]) => {   // 照明の板（左上・右・うしろ）
            const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(k, k, k * 1.05), side: THREE.DoubleSide }));
            m.position.set(x, y, z); m.lookAt(0, 0, 0); sc.add(m);
        });
        const pm = new THREE.PMREMGenerator(renderer);
        const tex = pm.fromScene(sc, 0.035).texture;
        pm.dispose(); g.dispose();
        _env.set(renderer, tex);
        return tex;
    }

    // ======================================================================
    // 3. 面の材質（フレネル・縁の光・照り返しのところは不透明に）
    // ======================================================================
    //   visual-fx の照り返しライト（patchShine）とも重ねて使えるように、出力の行は書きかえず、そのあとに足す
    //   o.inShader：色の整え方（tint）と濃さの割合（base ÷ 0.16）をシェーダーの中でかける（アプリの色・濃さの計算を変えずに質感をかける時。次元おりがみの 4次元）
    function patchFace(m, look, o) {
        const THREE = T(), L = lookOf(look), ins = !!(o && o.inShader);
        const u = m.userData.ndSolid = m.userData.ndSolid || {
            uFresA: { value: 0 }, uFresP: { value: 2 }, uRim: { value: new THREE.Color() }, uRimK: { value: 0 }, uLumT: { value: 2 }, uLumK: { value: 0 },
            uMode: { value: 0 }, uAK: { value: 1 }, uSat: { value: 1 }, uLift: { value: 0 }, uTintOn: { value: 0 },
        };
        u.uFresA.value = L.fresA; u.uFresP.value = L.fresP; u.uRim.value.setRGB(L.rim[0], L.rim[1], L.rim[2]); u.uRimK.value = L.rimK; u.uLumT.value = L.lumT; u.uLumK.value = L.lumK;
        u.uMode.value = L.blend === 'multiply' ? 1 : L.blend === 'add' ? 2 : 0;
        u.uAK.value = ins ? L.base / LOOKS.classic.base : 1; u.uTintOn.value = ins ? 1 : 0; u.uSat.value = L.sat; u.uLift.value = L.lift;
        // 混ぜ方：乗算＝後ろの色 ×（1 − a ＋ a·面の色）、加算＝後ろ ＋ 面の光 × a、ふつう＝アルファで重ねる
        if (L.blend === 'multiply') {
            m.blending = THREE.CustomBlending; m.blendEquation = THREE.AddEquation; m.blendSrc = THREE.DstColorFactor; m.blendDst = THREE.OneMinusSrcAlphaFactor;
            m.blendSrcAlpha = THREE.ZeroFactor; m.blendDstAlpha = THREE.OneFactor;
        } else if (L.blend === 'add') { m.blending = THREE.AdditiveBlending; }
        else { m.blending = THREE.NormalBlending; }
        m.roughness = L.rough; m.metalness = L.metal; m.envMapIntensity = L.env;
        if (m.userData.shine0) m.userData.shine0 = [L.rough, L.metal];   // 照り返しライトが ON の時は、この値から少しなめらかに
        if (!m.userData.ndSolidPatched) {
            m.userData.ndSolidPatched = true;
            const prev = m.onBeforeCompile;
            m.onBeforeCompile = function (sh, r) {
                if (prev) prev.call(this, sh, r);
                Object.assign(sh.uniforms, u);
                sh.fragmentShader = 'uniform float uFresA, uFresP, uRimK, uLumT, uLumK, uMode, uAK, uSat, uLift, uTintOn;\nuniform vec3 uRim;\n' + sh.fragmentShader
                    .replace('#include <color_fragment>', '#include <color_fragment>\n  if (uTintOn > 0.5) { float ndY = dot(diffuseColor.rgb, vec3(0.299, 0.587, 0.114)); diffuseColor.rgb = clamp((vec3(ndY) + (diffuseColor.rgb - vec3(ndY)) * uSat) * (1.0 - uLift) + uLift, 0.0, 1.0); }')
                    .replace('#include <tonemapping_fragment>',
                    '{ float ndOn = clamp(diffuseColor.a * 40.0, 0.0, 1.0);\n' +   // もとの濃さがほぼ 0 の面（隠した胞・消えていく面）は、光る効果も出さない
                    '  gl_FragColor.a *= uAK;\n' +
                    '  vec3 ndV = normalize(vViewPosition); float ndF = pow(1.0 - abs(dot(normalize(normal), ndV)), uFresP) * ndOn;\n' +
                    '  gl_FragColor.rgb += uRim * ndF * uRimK;\n' +
                    '  vec3 ndS = reflectedLight.directSpecular + reflectedLight.indirectSpecular; float ndL = max(max(ndS.r, ndS.g), ndS.b) * ndOn;\n' +   // 照り返し（鏡のような反射）の明るさだけ
                    '  gl_FragColor.a = clamp(max(gl_FragColor.a + ndF * uFresA, (ndL - uLumT) * uLumK), 0.0, 1.0);\n' +
                    '  if (uMode > 0.5 && uMode < 1.5) gl_FragColor.rgb = gl_FragColor.a * diffuseColor.rgb; }\n#include <tonemapping_fragment>');   // 乗算：出す色＝a × 面の色（混ぜ方で後ろに掛かる）
            };
            m.needsUpdate = true;
        }
        return m;
    }
    // 面のまとめメッシュ（visual-fx の sortedFaces）に質感をつける。look は後から setLook で変えられる
    function faces(maxQuads, look, renderer, opt) {
        const sf = VFX().sortedFaces(maxQuads, opt);
        const env = renderer ? envMap(renderer) : null;
        sf.setLook = l => { sf.look = lookOf(l); sf.material.envMap = sf.look.env > 0 ? env : null; patchFace(sf.material, sf.look); sf.material.needsUpdate = true; return sf; };
        sf.setLook(look);
        return sf;
    }

    // ======================================================================
    // 4. 辺を管に、頂点を玉に（InstancedMesh で 1 回で描く）
    // ======================================================================
    function rods(maxEdges, maxVerts, renderer, opt) {
        const THREE = T(), o = Object.assign({ look: 'glass', radial: 10 }, opt || {});
        const env = renderer ? envMap(renderer) : null;
        const tubeG = new THREE.CylinderGeometry(1, 1, 1, o.radial, 1, true), ballG = new THREE.SphereGeometry(1, 14, 10);
        const mk = () => new THREE.MeshStandardMaterial({ envMap: env });
        const tubes = new THREE.InstancedMesh(tubeG, mk(), Math.max(1, maxEdges)), balls = new THREE.InstancedMesh(ballG, mk(), Math.max(1, maxVerts));
        const white = new THREE.Color(1, 1, 1);
        for (let i = 0; i < tubes.count; i++) tubes.setColorAt(i, white);   // 色の入れ物を最初に作る（描く前に作らないと色が効かない）
        for (let i = 0; i < balls.count; i++) balls.setColorAt(i, white);
        [tubes, balls].forEach(m => { m.frustumCulled = false; m.renderOrder = 2; });
        const group = new THREE.Group(); group.add(tubes, balls);
        const M = new THREE.Matrix4(), Q = new THREE.Quaternion(), S = new THREE.Vector3(), A = new THREE.Vector3(), B = new THREE.Vector3(), D = new THREE.Vector3(), Y = new THREE.Vector3(0, 1, 0), C = new THREE.Color();
        let look = null;
        function setLook(l) {
            look = lookOf(l); const R = look.rod || LOOKS.glass.rod;
            [tubes, balls].forEach(m => { m.material.roughness = R.rough; m.material.metalness = R.metal; m.material.envMapIntensity = R.env; m.material.needsUpdate = true; });
            group.visible = !!look.rods;
            return api;
        }
        // P：頂点の 3D 位置（nv×3）。edges：辺の頂点の組（2 つずつ）。ecol：辺の色（ne×3）。K：頂点ごとの見かけの縮み（あれば、遠いほど細く）。vcol：頂点の色（nv×3、無ければ白っぽく）
        function update(P, edges, ecol, K, vcol, nv) {
            const R = look.rod || LOOKS.glass.rod, ne = Math.min(tubes.instanceMatrix.count, edges.length / 2);
            let kMax = 1e-9; if (K) for (let i = 0; i < K.length; i++) if (K[i] > kMax) kMax = K[i];
            const kr = i => (K ? Math.sqrt(K[i] / kMax) : 1);   // 手前の太さを 1 として、遠い（小さく写る）ほど細く
            for (let e = 0; e < ne; e++) {
                const a = edges[2 * e], b = edges[2 * e + 1];
                A.set(P[a * 3], P[a * 3 + 1], P[a * 3 + 2]); B.set(P[b * 3], P[b * 3 + 1], P[b * 3 + 2]);
                D.subVectors(B, A); const len = D.length();
                if (len < 1e-6) { M.makeScale(0, 0, 0); tubes.setMatrixAt(e, M); continue; }
                Q.setFromUnitVectors(Y, D.multiplyScalar(1 / len));
                const r = R.r * (kr(a) + kr(b)) / 2;
                S.set(r, len, r); M.compose(A.add(B).multiplyScalar(0.5), Q, S); tubes.setMatrixAt(e, M);
                C.setRGB(ecol[e * 3], ecol[e * 3 + 1], ecol[e * 3 + 2]); tubes.setColorAt(e, C);
            }
            tubes.count = ne;
            const nb = Math.min(balls.instanceMatrix.count, nv !== undefined ? nv : P.length / 3);
            Q.identity();
            for (let i = 0; i < nb; i++) {
                const r = R.ball * kr(i);
                A.set(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]); S.set(r, r, r); M.compose(A, Q, S); balls.setMatrixAt(i, M);
                if (vcol) C.setRGB(vcol[i * 3], vcol[i * 3 + 1], vcol[i * 3 + 2]); else C.setRGB(0.92, 0.94, 1); balls.setColorAt(i, C);
            }
            balls.count = nb;
            tubes.instanceMatrix.needsUpdate = true; balls.instanceMatrix.needsUpdate = true;
            if (tubes.instanceColor) tubes.instanceColor.needsUpdate = true; if (balls.instanceColor) balls.instanceColor.needsUpdate = true;
        }
        const api = { group, tubes, balls, update, setLook, get look() { return look; } };
        setLook(o.look);
        return api;
    }

    // ======================================================================
    // 5. n 次元の面の陰影
    // ======================================================================
    //   面（正方形）の 2 本の辺の向きを n 次元で回し、面の広がる平面を作る。光 L のうち、その平面に乗らない分（＝面の法線の側）が多いほど明るい。
    //   3D なら「光が面に垂直に当たるほど明るい」と同じ。表と裏は区別しない（ガラスは両側から光る）。回すと 5 次元の向きの変化が陰影の流れになる
    const _a = [], _b = [];
    function planeShade(R, n, V, i0, i1, i3, L, amb) {
        amb = amb === undefined ? 0.35 : amb;
        L = L || VFX().lightDir(n);
        let aa = 0, ab = 0;
        for (let r = 0; r < n; r++) {
            let sa = 0, sb = 0;
            for (let c = 0; c < n; c++) { const m = R ? R[r * n + c] : (r === c ? 1 : 0); sa += m * (V[i1 * n + c] - V[i0 * n + c]); sb += m * (V[i3 * n + c] - V[i0 * n + c]); }
            _a[r] = sa; _b[r] = sb; aa += sa * sa;
        }
        aa = Math.sqrt(aa) || 1;
        for (let r = 0; r < n; r++) { _a[r] /= aa; ab += _a[r] * _b[r]; }
        let bb = 0; for (let r = 0; r < n; r++) { _b[r] -= ab * _a[r]; bb += _b[r] * _b[r]; }
        bb = Math.sqrt(bb) || 1;
        let pa = 0, pb = 0; for (let r = 0; r < n; r++) { pa += L[r] * _a[r]; pb += L[r] * _b[r] / bb; }
        const s = Math.max(0, 1 - pa * pa - pb * pb);
        return amb + (1 - amb) * Math.sqrt(s);
    }

    // ======================================================================
    // 6. 奥行きのかすみ（遠い所ほど背景の色へわずかに溶ける）
    // ======================================================================
    function haze(scene, camera, target, k, color) {
        const THREE = T();
        if (!(k > 0)) { scene.fog = null; return; }
        const d = camera.position.distanceTo(target || new THREE.Vector3());
        if (!scene.fog) scene.fog = new THREE.Fog(color !== undefined ? color : 0x030712, 1, 2);
        scene.fog.near = d * (1 - 0.35 * k); scene.fog.far = d * (1 + 2.6 / k);
    }

    const bgOf = l => { const L = lookOf(l); return L.bg !== undefined ? L.bg : null; };   // その質感で使う背景の色（無ければ null＝いつもの暗い背景）
    global.NDSolid = { version: VERSION, LOOKS, tint, envMap, patchFace, faces, rods, planeShade, haze, bgOf };
})(typeof window !== 'undefined' ? window : this);
