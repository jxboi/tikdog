#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party tooling."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(name, body):
    key = uid(name); objects[key] = body; return key

def ref(path, kind): return obj('ref:'+path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = "<group>";')
def build(name, file): return obj('build:'+name, f'isa = PBXBuildFile; fileRef = {file};')
def group(name, children, path=None):
    return obj('group:'+name, f'isa = PBXGroup; children = ({", ".join(children)}); '+(f'path = "{path}";' if path else f'name = "{name}";')+' sourceTree = "<group>";')
def phase(name, isa, files): return obj('phase:'+name, f'isa = {isa}; buildActionMask = 2147483647; files = ({", ".join(files)}); runOnlyForDeploymentPostprocessing = 0;')
def configs(name, settings, base=None):
    ids=[]
    for mode in ['Debug','Release']:
        values=dict(settings)
        if mode=='Debug': values.update({'ONLY_ACTIVE_ARCH':'YES','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"','DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'"DEBUG $(inherited)"'})
        else: values.update({'SWIFT_OPTIMIZATION_LEVEL':'"-O"','DEBUG_INFORMATION_FORMAT':'"dwarf-with-dsym"'})
        ids.append(obj('config:'+name+mode, 'isa = XCBuildConfiguration; '+(f'baseConfigurationReference = {base};' if base else '')+' buildSettings = { '+ ' '.join(f'{k} = {v};' for k,v in values.items())+f' }}; name = {mode};'))
    return obj('configlist:'+name,f'isa = XCConfigurationList; buildConfigurations = ({", ".join(ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

swift_files=sorted(ROOT.glob('TikDog/**/*.swift'))
app_refs=[]; source_builds=[]
for file in swift_files:
    path=str(file.relative_to(ROOT)); r=ref(path,'sourcecode.swift');app_refs.append(r);source_builds.append(build(path,r))
resource_builds=[]
for file in sorted((ROOT/'TikDog/Resources/Media').glob('*')):
    path=str(file.relative_to(ROOT)); r=ref(path, 'image.jpeg' if file.suffix=='.jpg' else 'file'); app_refs.append(r);resource_builds.append(build(path,r))
for path, kind in [('TikDog/Resources/Assets.xcassets','folder.assetcatalog'),('TikDog/Resources/PrivacyInfo.xcprivacy','text.xml'),('TikDog/Resources/Legal.json','text.json')]:
    r=ref(path,kind); app_refs.append(r);resource_builds.append(build(path,r))
app_refs += [ref('TikDog/Resources/Info.plist','text.plist.xml'),ref('TikDog/Resources/TikDog.entitlements','text.plist.entitlements')]
base=ref('Config/App.xcconfig','text.xcconfig')
app_product=obj('product:app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TikDog.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product=obj('product:tests','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TikDogUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
unit_product=obj('product:unit tests','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TikDogTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
test_refs=[];test_builds=[]
for file in sorted(ROOT.glob('TikDogUITests/*.swift')):
    path=str(file.relative_to(ROOT));r=ref(path,'sourcecode.swift');test_refs.append(r);test_builds.append(build(path,r))
unit_refs=[];unit_builds=[]
for file in sorted(ROOT.glob('TikDogTests/*.swift')):
    path=str(file.relative_to(ROOT));r=ref(path,'sourcecode.swift');unit_refs.append(r);unit_builds.append(build(path,r))
package=obj('package:core','isa = XCLocalSwiftPackageReference; relativePath = TikDogCore;')
product=obj('packageproduct:core',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = TikDogCore;')
product_build=obj('packagebuild:core',f'isa = PBXBuildFile; productRef = {product};')
project_id=uid('project');app_id=uid('app');test_id=uid('tests');unit_id=uid('unit tests')
proxy=obj('proxy:app',f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = TikDog;')
dependency=obj('dependency:app',f'isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};')
app_settings={'ENABLE_USER_SCRIPT_SANDBOXING':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]"':'TikDog/Resources/TikDog.entitlements','INFOPLIST_FILE':'TikDog/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','PRODUCT_NAME':'"$(TARGET_NAME)"','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','SDKROOT':'iphoneos','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/Frameworks"'}
app_configs=configs('app',app_settings,base)
test_configs=configs('tests',{'PRODUCT_BUNDLE_IDENTIFIER':'com.tikdog.uitests','PRODUCT_NAME':'"$(TARGET_NAME)"','GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1','SDKROOT':'iphoneos','TEST_TARGET_NAME':'TikDog','CODE_SIGN_STYLE':'Automatic'})
unit_configs=configs('unit tests',{'PRODUCT_BUNDLE_IDENTIFIER':'com.tikdog.tests','PRODUCT_NAME':'"$(TARGET_NAME)"','GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1','SDKROOT':'iphoneos','TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/TikDog.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TikDog"','BUNDLE_LOADER':'"$(TEST_HOST)"','CODE_SIGN_STYLE':'Automatic'})
project_configs=configs('project',{'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_TREAT_WARNINGS_AS_ERRORS':'YES'})
archive_check = obj('phase:archive release check', 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = ("$(SRCROOT)/scripts/check_release.py", "$(SRCROOT)/release", "$(SRCROOT)/Config", "$(SRCROOT)/TikDog/Resources"); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; alwaysOutOfDate = 1; shellPath = /bin/sh; shellScript = '+json.dumps('if [ "$ACTION" = "install" ]; then\n /usr/bin/python3 "$SRCROOT/scripts/check_release.py" --archive\nfi\n')+';')
app_phases=[archive_check,phase('app sources','PBXSourcesBuildPhase',source_builds),phase('app frameworks','PBXFrameworksBuildPhase',[product_build]),phase('app resources','PBXResourcesBuildPhase',resource_builds)]
test_phases=[phase('test sources','PBXSourcesBuildPhase',test_builds),phase('test frameworks','PBXFrameworksBuildPhase',[]),phase('test resources','PBXResourcesBuildPhase',[])]
unit_phases=[phase('unit sources','PBXSourcesBuildPhase',unit_builds),phase('unit frameworks','PBXFrameworksBuildPhase',[product_build]),phase('unit resources','PBXResourcesBuildPhase',[])]
obj('app',f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = ({", ".join(app_phases)}); buildRules = (); dependencies = (); name = TikDog; packageProductDependencies = ({product}); productName = TikDog; productReference = {app_product}; productType = "com.apple.product-type.application";')
obj('tests',f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = ({", ".join(test_phases)}); buildRules = (); dependencies = ({dependency}); name = TikDogUITests; productName = TikDogUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
obj('unit tests',f'isa = PBXNativeTarget; buildConfigurationList = {unit_configs}; buildPhases = ({", ".join(unit_phases)}); buildRules = (); dependencies = ({dependency}); name = TikDogTests; packageProductDependencies = ({product}); productName = TikDogTests; productReference = {unit_product}; productType = "com.apple.product-type.bundle.unit-test";')
main=group('root',[group('App',app_refs),group('Tests',test_refs),group('Unit Tests',unit_refs),base,group('Products',[app_product,test_product,unit_product])])
obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 16.0; }}; {test_id} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_id}; }}; {unit_id} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; packageReferences = ({package}); productRefGroup = {uid("group:Products")}; projectDirPath = ""; projectRoot = ""; targets = ({app_id}, {test_id}, {unit_id});')
project=ROOT/'TikDog.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(f'{k} = {{ {v} }};' for k,v in objects.items())+f'\n}}; rootObject = {project_id};\n}}\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def entry(target, name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:TikDog.xcodeproj"/>'
(scheme/'TikDog.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{entry(app_id,'TikDog.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{entry(unit_id,'TikDogTests.xctest')}</TestableReference><TestableReference skipped="NO">{entry(test_id,'TikDogUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app_id,'TikDog.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry(app_id,'TikDog.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project} ({len(swift_files)} app source files)')
