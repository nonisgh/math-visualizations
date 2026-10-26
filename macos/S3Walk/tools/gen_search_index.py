# 設定の検索の索引を作る：Dock.swift の PanelContent の中の Toggle・Picker・row・irow・Button・note の文字を、パネルごとに集めて
#   Sources/S3Walk/SearchIndex.swift に書く（make-app.sh がビルドの前に動かす）。使い方：python3 -I tools/gen_search_index.py
import re, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(root, 'Sources/S3Walk/Dock.swift'), encoding='utf-8').read()
i = src.index('struct PanelContent: View {'); j = src.index('\n}\n', i)
body = src[i:j]
items = []; panel = None
lit = r'"((?:[^"\\]|\\.)*)"'
for line in body.split('\n'):
    m = re.match(r'\s*case \.(\w+):', line)
    if m: panel = m.group(1); continue
    if not panel: continue
    for kind, pat in [('set', r'(?:Toggle|Picker|row|irow)\(\s*' + lit), ('btn', r'Button\(\s*' + lit), ('note', r'note\(\s*' + lit)]:
        for mm in re.finditer(pat, line):
            t = mm.group(1)
            t = re.sub(r'\\\(.*?\)', '', t).replace('\\"', '"').strip()
            if len(t) < 2: continue
            items.append((panel, kind, t))
seen = set(); out = []
for p, k, t in items:
    if (p, t) in seen: continue
    seen.add((p, t)); out.append((p, k, t))
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
lines = ['// 自動で作る（tools/gen_search_index.py）。手で直さない', '// 設定の検索の索引：(パネル, 種類 set・btn・note, 文字)',
         'let searchIndex: [(PanelID, String, String)] = [']
lines += ['    (.%s, %s, %s),' % (p, q(k), q(t)) for p, k, t in out]
lines += [']', '']
open(os.path.join(root, 'Sources/S3Walk/SearchIndex.swift'), 'w', encoding='utf-8').write('\n'.join(lines))
print('索引', len(out))
