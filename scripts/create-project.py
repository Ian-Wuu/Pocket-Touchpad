from pathlib import Path
import hashlib, plistlib
root=Path(__file__).resolve().parent.parent
objects={}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(name,body): objects[uid(name)]=body; return uid(name)
def ref(name): return uid(name)
def arr(items): return '('+','.join(items)+',)'
def settings(d): return '{'+''.join(f'{k} = {v};' for k,v in d.items())+'}'
allfiles=['Shared/Wire.swift','Shared/Motion.swift','iPhone/Connection.swift','iPhone/TouchSurface.swift','iPhone/TouchpadApp.swift','iPhone/PairingView.swift','Mac/Receiver.swift','Mac/Gestures.swift','Mac/Pointer.swift','Mac/NativeInput.mm','Mac/NativeInput.h']
for f in allfiles:
    filetype={'.swift':'sourcecode.swift','.mm':'sourcecode.cpp.objcpp','.h':'sourcecode.c.h'}[Path(f).suffix]
    add(f, f'{{isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{f}"; sourceTree = "<group>";}}')
asset='Shared/Assets.xcassets'
add(asset, f'{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{asset}"; sourceTree = "<group>";}}')
signing='Config/Signing.xcconfig'
add(signing, f'{{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "{signing}"; sourceTree = "<group>";}}')
products=[];targets=[]
for name,files,platform in [('Touchpad',[f for f in allfiles if not f.startswith('Mac/')],'iphoneos'),('TouchpadMac',[f for f in allfiles if not f.startswith('iPhone/')],'macosx')]:
    ios=platform=='iphoneos'
    product=add(name+'product',f'{{isa = PBXFileReference; explicitFileType = wrapper.application; path = "{name}.app"; sourceTree = BUILT_PRODUCTS_DIR;}}');products.append(product)
    builds=[]
    for f in files:
        if not f.endswith('.h'): builds.append(add(name+f+'build',f'{{isa = PBXBuildFile; fileRef = {ref(f)};}}'))
    source=add(name+'sources',f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;}}')
    iconbuild=add(name+'iconbuild',f'{{isa = PBXBuildFile; fileRef = {ref(asset)};}}')
    resources=add(name+'resources',f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild},); runOnlyForDeploymentPostprocessing = 0;}}')
    configids=[]
    for config in ['Debug','Release']:
        s={'PRODUCT_NAME':'"$(TARGET_NAME)"','PRODUCT_BUNDLE_IDENTIFIER':f'art.dongheng.{name.lower()}','SWIFT_VERSION':'5.0','SDKROOT':platform,'CODE_SIGN_STYLE':'Automatic','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','INFOPLIST_FILE':f'"{"iPhone" if ios else "Mac"}/Info.plist"','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','ENABLE_APP_SANDBOX':'NO','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if config=='Debug' else '"-O"','CLANG_ENABLE_MODULES':'YES','ENABLE_HARDENED_RUNTIME':'YES'}
        if config == 'Debug': s['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        if ios: s.update({'IPHONEOS_DEPLOYMENT_TARGET':'26.0','TARGETED_DEVICE_FAMILY':'"1,2"','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO'})
        else: s.update({'MACOSX_DEPLOYMENT_TARGET':'26.0','SWIFT_OBJC_BRIDGING_HEADER':'"Mac/NativeInput.h"','CLANG_ENABLE_OBJC_ARC':'YES','CLANG_CXX_LANGUAGE_STANDARD':'"c++17"'})
        configids.append(add(name+config, f'{{isa = XCBuildConfiguration; baseConfigurationReference = {ref(signing)}; buildSettings = {settings(s)}; name = {config};}}'))
    configs=add(name+'configs',f'{{isa = XCConfigurationList; buildConfigurations = {arr(configids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
    targets.append(add(name+'target',f'{{isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = {arr([source,resources])}; buildRules = (); dependencies = (); name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.application";}}'))
    info={'CFBundleDevelopmentRegion':'zh_CN','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'Pocket Touchpad' if ios else 'Pocket Touchpad Mac','CFBundleDisplayName':'Pocket Touchpad' if ios else 'Pocket Touchpad Mac','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','NSBonjourServices':['_touchpad._tcp'],'NSLocalNetworkUsageDescription':'通过本地网络加密连接 iPhone 与 Mac，用于触摸板和键盘控制。'}
    if ios: info.update({'LSRequiresIPhoneOS':True,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'NSCameraUsageDescription':'扫描 Mac 上的二维码以配对触摸板。'})
    else: info.update({'LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True})
    (root/('iPhone' if ios else 'Mac')/'Info.plist').write_bytes(plistlib.dumps(info))
    scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name+'target')}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Touchpad.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name+'target')}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Touchpad.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
    folder=root/'Touchpad.xcodeproj/xcshareddata/xcschemes';folder.mkdir(parents=True,exist_ok=True);(folder/(name+'.xcscheme')).write_text(scheme)
pg=add('products',f'{{isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";}}')
main=add('main',f'{{isa = PBXGroup; children = {arr([ref(f) for f in allfiles]+[ref(asset),ref(signing),pg])}; sourceTree = "<group>";}}')
pc=[]
for c in ['Debug','Release']: pc.append(add('project'+c,f'{{isa = XCBuildConfiguration; buildSettings = {{}}; name = {c};}}'))
pconfigs=add('projectconfigs',f'{{isa = XCConfigurationList; buildConfigurations = {arr(pc)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
project=add('project',f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {pconfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en,zh_CN,Base,); mainGroup = {main}; productRefGroup = {pg}; projectDirPath = ""; projectRoot = ""; targets = {arr(targets)};}}')
(root/'Touchpad.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(f'{key} = {value};\n' for key,value in objects.items())+f'}}; rootObject = {project};}}\n')
