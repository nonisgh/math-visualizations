# ウェブ版の数学アプリ（サイトの一覧 index.html に載っているもの全部）を、アプリに入れる形にして Web/ に写す（make-app.sh がビルドの前に動かす）。
#   使い方：python3 -I tools/sync_web.py
#   名前はウェブ版と同じ（ページどうしのリンクがそのまま効く）。lib/ の共通部品も写す（リンクはたどって中身を）。
#   CDN の three.js・その部品・lucide・Tailwind は、Web/vendor の手元の写し（版を決めたもの）に置きかえる（オフラインでも開けるように）。
#   Google Fonts はそのまま（つながっていなければ、システムの書体になる）。元のファイル（~/math-visualizations/）は変えない
import os, re, shutil
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
math = os.path.dirname(os.path.dirname(root))               # ~/math-visualizations
PAGES = ['index', 'polygon', 'graph', 'vec3d', 'euler', 'graph4d', 'hypercube', 'hypercube6d', 'ndim',
         'hypersphere', 'hypersphere_beta', 's3walk', 'hypersphere5d_ui', 'hypersphere5d_bubbles', 'thurston', 'buffon', 'monty']
TJ = r'https://cdn\.jsdelivr\.net/npm/three@0\.128\.0/examples/js/'
SUBS = [
    (r'https://cdnjs\.cloudflare\.com/ajax/libs/three\.js/r128/three\.min\.js', 'vendor/three.min.js'),
    (TJ + r'controls/OrbitControls\.js', 'vendor/OrbitControls.js'),
    (TJ + r'lines/LineMaterial\.js', 'vendor/LineMaterial.js'),
    (TJ + r'lines/LineSegments2\.js', 'vendor/LineSegments2.js'),
    (TJ + r'lines/LineSegmentsGeometry\.js', 'vendor/LineSegmentsGeometry.js'),
    (r'https://unpkg\.com/lucide@[^"\']*', 'vendor/lucide.min.js'),
    (r'https://cdn\.tailwindcss\.com[^"\']*', 'vendor/tailwind.js'),
]
web = os.path.join(root, 'Web'); os.makedirs(web, exist_ok=True)
changed = 0
def put(path, data):
    global changed
    old = open(path, 'rb').read() if os.path.exists(path) else None
    if old != data: open(path, 'wb').write(data); changed += 1
for name in PAGES:
    src = os.path.join(math, name + '.html')
    if not os.path.exists(src): print('見つからない：', src); continue
    t = open(os.path.realpath(src), encoding='utf-8').read()
    for a, b in SUBS: t = re.sub(a, b, t)
    left = sorted(set(re.findall(r'<script[^>]+src="(https?:[^"]+)"', t)))
    if left: print(name, '：まだ外から読むスクリプト', left)
    put(os.path.join(web, name + '.html'), t.encode('utf-8'))
# 共通部品（lib/*.js。リンクの先の中身を写す）
os.makedirs(os.path.join(web, 'lib'), exist_ok=True)
for f in sorted(os.listdir(os.path.join(math, 'lib'))):
    p = os.path.join(math, 'lib', f)
    if f.endswith('.js') and os.path.isfile(p): put(os.path.join(web, 'lib', f), open(os.path.realpath(p), 'rb').read())
print('ウェブ版：%d ページ・変わったファイル %d' % (len(PAGES), changed))
