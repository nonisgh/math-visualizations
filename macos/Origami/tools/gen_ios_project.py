# 次元おりがみの iPad・iPhone 版の Xcode プロジェクト（iOS/OrigamiiOS.xcodeproj）を作る。使い方：python3 -I tools/gen_ios_project.py
#   Mac 版と同じ Sources/Origami の共通のファイル（MacApp.swift は Mac だけ）と、iOS/ の入口を 1 つのアプリにまとめる（iPhone と iPad の両方）
#   球面さんぽの tools/gen_ios_project.py をもとにしたもの
import os, hashlib
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = ['NDGeom', 'OrigamiGlass', 'Origami', 'OrigamiSpace', 'OrigamiUI', 'OrigamiPlay', 'OrigamiRaster', 'OrigamiKeys', 'OrigamiSettings', 'OrigamiPalette', 'OrigamiNets', 'OrigamiNetAtlas', 'OrigamiPoints', 'OrigamiSection', 'OrigamiIntegral', 'OrigamiWater', 'OrigamiIntShapes', 'OrigamiInSphere', 'OrigamiDice', 'OrigamiAsmPose']
srcs = ['../Sources/Origami/%s.swift' % n for n in CORE] + sorted('%s' % f for f in os.listdir(os.path.join(root, 'iOS')) if f.endswith('.swift'))
res = ['../Fonts/KaTeX_Math-Italic.ttf', 'Assets.xcassets']
def oid(s): return hashlib.md5(s.encode()).hexdigest()[:24].upper()
P = oid('project'); T = oid('target'); G = oid('group'); PG = oid('products'); APP = oid('app')
SB = oid('srcphase'); RB = oid('resphase'); FB = oid('fwphase'); CLP = oid('cl-proj'); CLT = oid('cl-target')
cfg = {k: oid('cfg' + k) for k in ['pd', 'pr', 'td', 'tr']}
L = []
w = L.append
w('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n')
for f in srcs + res:
    w('\t\t%s = {isa = PBXBuildFile; fileRef = %s; };\n' % (oid('bf' + f), oid('fr' + f)))
for f in srcs:
    w('\t\t%s = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "%s"; sourceTree = "<group>"; name = "%s"; };\n' % (oid('fr' + f), f, os.path.basename(f)))
w('\t\t%s = {isa = PBXFileReference; lastKnownFileType = file; path = "%s"; sourceTree = "<group>"; name = "%s"; };\n' % (oid('fr' + res[0]), res[0], os.path.basename(res[0])))
w('\t\t%s = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "%s"; sourceTree = "<group>"; };\n' % (oid('fr' + res[1]), res[1]))
w('\t\t%s = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "OrigamiiOS.app"; sourceTree = BUILT_PRODUCTS_DIR; };\n' % APP)
w('\t\t%s = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; };\n' % FB)
w('\t\t%s = {isa = PBXGroup; children = (\n%s\t\t\t\t%s,\n\t\t\t); sourceTree = "<group>"; };\n' % (G, ''.join('\t\t\t\t%s,\n' % oid('fr' + f) for f in srcs + res), PG))
w('\t\t%s = {isa = PBXGroup; children = (\n\t\t\t\t%s,\n\t\t\t); name = Products; sourceTree = "<group>"; };\n' % (PG, APP))
w('\t\t%s = {isa = PBXNativeTarget; buildConfigurationList = %s; buildPhases = (\n\t\t\t\t%s,\n\t\t\t\t%s,\n\t\t\t\t%s,\n\t\t\t); buildRules = (\n\t\t\t); dependencies = (\n\t\t\t); name = OrigamiiOS; productName = OrigamiiOS; productReference = %s; productType = "com.apple.product-type.application"; };\n' % (T, CLT, SB, FB, RB, APP))
w('\t\t%s = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; }; buildConfigurationList = %s; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja, en, Base, ); mainGroup = %s; productRefGroup = %s; projectDirPath = ""; projectRoot = ""; targets = (\n\t\t\t\t%s,\n\t\t\t); };\n' % (P, CLP, G, PG, T))
w('\t\t%s = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\n%s\t\t\t); runOnlyForDeploymentPostprocessing = 0; };\n' % (RB, ''.join('\t\t\t\t%s,\n' % oid('bf' + f) for f in res)))
w('\t\t%s = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n%s\t\t\t); runOnlyForDeploymentPostprocessing = 0; };\n' % (SB, ''.join('\t\t\t\t%s,\n' % oid('bf' + f) for f in srcs)))
common = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0', 'ALWAYS_SEARCH_USER_PATHS': 'NO', 'CLANG_ENABLE_MODULES': 'YES'}
tgt = {'PRODUCT_NAME': '"$(TARGET_NAME)"', 'PRODUCT_BUNDLE_IDENTIFIER': 'io.github.nonisgh.origami.ios', 'TARGETED_DEVICE_FAMILY': '"1,2"',
       'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': '"次元おりがみ"', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
       'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
       'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
       'INFOPLIST_KEY_UIStatusBarHidden': 'YES',
       'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0',
       'LD_RUNPATH_SEARCH_PATHS': '"$(inherited) @executable_path/Frameworks"', 'ENABLE_PREVIEWS': 'NO'}
# 実機に入れる時のチーム（Xcode の Signing で選んだもの）。iOS/team.txt に書いておくと、作り直しても消えない
tf = os.path.join(root, 'iOS/team.txt')
if os.path.exists(tf):
    team = open(tf).read().strip()
    if team: tgt['DEVELOPMENT_TEAM'] = team
def cfgblock(i, name, settings):
    s = ''.join('\t\t\t\t%s = %s;\n' % kv for kv in sorted(settings.items()))
    w('\t\t%s = {isa = XCBuildConfiguration; buildSettings = {\n%s\t\t\t}; name = %s; };\n' % (i, s, name))
cfgblock(cfg['pd'], 'Debug', dict(common, ONLY_ACTIVE_ARCH='YES', SWIFT_OPTIMIZATION_LEVEL='"-O"', DEBUG_INFORMATION_FORMAT='dwarf'))
cfgblock(cfg['pr'], 'Release', dict(common, SWIFT_OPTIMIZATION_LEVEL='"-O"', VALIDATE_PRODUCT='YES'))
cfgblock(cfg['td'], 'Debug', tgt); cfgblock(cfg['tr'], 'Release', tgt)
w('\t\t%s = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t\t%s,\n\t\t\t\t%s,\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n' % (CLP, cfg['pd'], cfg['pr']))
w('\t\t%s = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t\t%s,\n\t\t\t\t%s,\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n' % (CLT, cfg['td'], cfg['tr']))
w('\t};\n\trootObject = %s;\n}\n' % P)
d = os.path.join(root, 'iOS/OrigamiiOS.xcodeproj'); os.makedirs(d, exist_ok=True)
open(os.path.join(d, 'project.pbxproj'), 'w', encoding='utf-8').write(''.join(L))
print('ファイル', len(srcs), '・', d)
