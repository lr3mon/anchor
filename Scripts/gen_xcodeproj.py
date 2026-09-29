#!/usr/bin/env python3
"""
AnchorApp.xcodeproj 생성기.

SwiftPM 은 .app 번들을 만들지 못한다. 메뉴바 앱은 NSApplication/NSPopover 로
직접 떠야 하므로 (SwiftUI App Scene 는 LSUIElement 조합에서 불안정) Info.plist 와
번들 설정이 있는 Xcode 프로젝트가 필요하다.

XcodeGen 없이 순수하게 pbxproj 를 만들어写出���다.
"""
import hashlib, os, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "AnchorApp.xcodeproj"
APP_SRC = ROOT / "Sources" / "AnchorApp"
CORE_SRC = ROOT / "Sources" / "AnchorCore"

def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()

def fileref(path: Path, root: Path, name: str | None = None) -> dict:
    """sourceTree=<group> 는 그룹 위치 기준으로 해석돼 경로가 틀린다.
    프로젝트 루트 기준 상대경로를 명시한다."""
    rel = path.relative_to(root)
    return {
        "id": uid("ref:" + str(path)),
        "path": str(rel),
        "name": name or path.name,
        "type": "file",
    }

def build_refs() -> dict:
    refs = {}
    app_files = sorted(APP_SRC.glob("*.swift"))
    core_files = sorted(CORE_SRC.glob("*.swift"))
    for f in app_files + core_files:
        refs[str(f)] = fileref(f, ROOT)
    info = ROOT / "Info.plist"
    if info.exists():
        refs[str(info)] = fileref(info, ROOT)
    return refs

def main() -> int:
    if not APP_SRC.exists():
        print("Sources/AnchorApp 가 없습니다", file=__import__("sys").stderr)
        return 1
    PROJ.mkdir(exist_ok=True)
    refs = build_refs()

    # 파일 참조 id 목록
    file_ids = [r["id"] for r in refs.values()]

    # Build File(컴파일) — 소스만 컴파일, plist 는 Resources 아님(BUNDLE)
    app_builds, core_builds = [], []
    for path, r in refs.items():
        if not path.endswith(".swift"):
            continue
        if "/AnchorApp/" in path:
            app_builds.append((uid("bf:" + path), r["id"],
                               basename := os.path.basename(path)))
        else:
            core_builds.append((uid("bf:" + path), r["id"], os.path.basename(path)))

    lines = []
    A = lines.append
    A("// !$*UTF8*$!")
    A("{")
    A("\tarchiveVersion = 1;")
    A("\tclasses = {")
    A("\t};")
    A("\tobjectVersion = 77;")
    A("\tobjects = {")

    # ── PBXBuildFile ──
    A("\n/* Begin PBXBuildFile section */")
    for bid, fid, name in app_builds + core_builds:
        A(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid}; }};")
    A("/* End PBXBuildFile section */")

    # ── PBXFileReference ──
    A("\n/* Begin PBXFileReference section */")
    for path, r in refs.items():
        last = r["type"] == "file"
        ptype = "sourcecode.swift" if path.endswith(".swift") else "text.plist.xml"
        A(f'\t\t{r["id"]} /* {r["name"]} */ = {{isa = PBXFileReference; '
          f'lastKnownFileType = {ptype}; name = "{r["name"]}"; '
          f'path = "{r["path"]}"; sourceTree = SOURCE_ROOT; }};')
    prod_ref = uid("product:AnchorApp")
    A(f'\t\t{prod_ref} /* Anchor.app */ = {{isa = PBXFileReference; '
      f'explicitFileType = wrapper.application; includeInIndex = 0; '
      f'path = Anchor.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    A("/* End PBXFileReference section */")

    # ── PBXGroup ──
    A("\n/* Begin PBXGroup section */")
    root_g = uid("group:root")
    app_g = uid("group:AnchorApp")
    core_g = uid("group:AnchorCore")
    prod_g = uid("group:Products")
    A(f"\t\t{root_g} = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{app_g} /* AnchorApp */,")
    A(f"\t\t\t\t{core_g} /* AnchorCore */,")
    A(f"\t\t\t\t{prod_g} /* Products */,")
    A("\t\t\t);")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    for gid, gname, members in [
        (app_g, "AnchorApp", [r["id"] for p, r in refs.items() if "/AnchorApp/" in p]),
        (core_g, "AnchorCore", [r["id"] for p, r in refs.items() if "/AnchorCore/" in p]),
    ]:
        A(f"\t\t{gid} /* {gname} */ = {{")
        A("\t\t\tisa = PBXGroup;")
        A("\t\t\tchildren = (")
        for m in members:
            nm = next(r["name"] for r in refs.values() if r["id"] == m)
            A(f"\t\t\t\t{m} /* {nm} */,")
        A("\t\t\t);")
        A("\t\t\tname = " + gname + ";")
        A(f'\t\t\tpath = "Sources/{gname}";')
        A("\t\t\tsourceTree = \"<group>\";")
        A("\t\t};")
    A(f"\t\t{prod_g} /* Products */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{prod_ref} /* Anchor.app */,")
    A("\t\t\t);")
    A("\t\t\tname = Products;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("/* End PBXGroup section */")

    # ── PBXNativeTarget ──
    tgt = uid("target:AnchorApp")
    phases = uid("phase:sources")
    res = uid("phase:resources")
    frm = uid("phase:frameworks")
    cfgl = uid("config:list")
    A("\n/* Begin PBXNativeTarget section */")
    A(f"\t\t{tgt} /* AnchorApp */ = {{")
    A("\t\t\tisa = PBXNativeTarget;")
    A(f'\t\t\tbuildConfigurationList = {cfgl};')
    A("\t\t\tbuildPhases = (")
    A(f"\t\t\t\t{phases} /* Sources */,")
    A(f"\t\t\t\t{frm} /* Frameworks */,")
    A(f"\t\t\t\t{res} /* Resources */,")
    A("\t\t\t);")
    A("\t\t\tbuildRules = (")
    A("\t\t\t);")
    A("\t\t\tdependencies = (")
    A("\t\t\t);")
    A("\t\t\tname = AnchorApp;")
    A("\t\t\tproductName = AnchorApp;")
    A(f"\t\t\tproductReference = {prod_ref};")
    A("\t\t\tproductType = \"com.apple.product-type.application\";")
    A("\t\t};")
    A("/* End PBXNativeTarget section */")

    # ── PBXProject ──
    prj = uid("project:root")
    A("\n/* Begin PBXProject section */")
    A(f"\t\t{prj} /* Project object */ = {{")
    A("\t\t\tisa = PBXProject;")
    A("\t\t\tattributes = {")
    A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    A("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    A("\t\t\t\tLastUpgradeCheck = 1600;")
    A("\t\t\t\tTargetAttributes = {")
    A(f"\t\t\t\t\t{tgt} = {{")
    A("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    A("\t\t\t\t\t};")
    A("\t\t\t\t};")
    A("\t\t\t};")
    A(f"\t\t\tbuildConfigurationList = {uid('config:list:project')};")
    A("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    A("\t\t\tdevelopmentRegion = ko;")
    A("\t\t\thasScannedForEncodings = 0;")
    A("\t\t\tknownRegions = (ko, en, Base);")
    A(f"\t\t\tmainGroup = {root_g};")
    A(f"\t\t\tproductRefGroup = {prod_g};")
    A("\t\t\tprojectDirPath = \"\";")
    A("\t\t\tprojectRoot = \"\";")
    A("\t\t\ttargets = (")
    A(f"\t\t\t\t{tgt} /* AnchorApp */,")
    A("\t\t\t);")
    A("\t\t};")
    A("/* End PBXProject section */")

    # ── Build phases ──
    A("\n/* Begin PBXSourcesBuildPhase section */")
    A(f"\t\t{phases} /* Sources */ = {{")
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for bid, fid, name in app_builds + core_builds:
        A(f"\t\t\t\t{bid} /* {name} in Sources */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXSourcesBuildPhase section */")

    A("\n/* Begin PBXResourcesBuildPhase section */")
    A(f"\t\t{res} /* Resources */ = {{")
    A("\t\t\tisa = PBXResourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXResourcesBuildPhase section */")

    A("\n/* Begin PBXFrameworksBuildPhase section */")
    A(f"\t\t{frm} /* Frameworks */ = {{")
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXFrameworksBuildPhase section */")

    # ── Build configurations ──
    proj_cfg_list = uid("config:list:project")
    A("\n/* Begin XCBuildConfiguration section */")
    for cfg in ("Debug", "Release"):
        cid = uid(f"config:project:{cfg}")
        A(f"\t\t{cid} /* {cfg} */ = {{")
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        A("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        A("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
        A("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        A("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
        A("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
        A("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
        A("\t\t\t\tSDKROOT = macosx;")
        A("\t\t\t\tSWIFT_VERSION = 6.0;")
        A("\t\t\t};")
        A(f"\t\t\tname = {cfg};")
        A("\t\t};")
    for cfg in ("Debug", "Release"):
        cid = uid(f"config:target:{cfg}")
        A(f"\t\t{cid} /* {cfg} */ = {{")
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        A("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        A("\t\t\t\tCODE_SIGN_IDENTITY = \"-\";")
        A("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
        A("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
        A("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
        A("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
        A("\t\t\t\tINFOPLIST_FILE = Info.plist;")
        A("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
        A("\t\t\t\t\t\"$(inherited)\",")
        A("\t\t\t\t\t\"@executable_path/../Frameworks\",")
        A("\t\t\t\t);")
        A("\t\t\t\tMARKETING_VERSION = 0.1.0;")
        A("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.lr3mon.anchor;")
        A("\t\t\t\tPRODUCT_NAME = Anchor;")
        A("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
        if cfg == "Debug":
            A("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
            A("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
        else:
            A("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
        A("\t\t\t};")
        A(f"\t\t\tname = {cfg};")
        A("\t\t};")
    A("/* End XCBuildConfiguration section */")

    A("\n/* Begin XCConfigurationList section */")
    A(f"\t\t{proj_cfg_list} = {{")
    A("\t\t\tisa = XCConfigurationList;")
    A("\t\t\tbuildConfigurations = (")
    A(f"\t\t\t\t{uid('config:project:Debug')} /* Debug */,")
    A(f"\t\t\t\t{uid('config:project:Release')} /* Release */,")
    A("\t\t\t);")
    A("\t\t\tdefaultConfigurationIsVisible = 0;")
    A("\t\t\tdefaultConfigurationName = Release;")
    A("\t\t};")
    A(f"\t\t{cfgl} = {{")
    A("\t\t\tisa = XCConfigurationList;")
    A("\t\t\tbuildConfigurations = (")
    A(f"\t\t\t\t{uid('config:target:Debug')} /* Debug */,")
    A(f"\t\t\t\t{uid('config:target:Release')} /* Release */,")
    A("\t\t\t);")
    A("\t\t\tdefaultConfigurationIsVisible = 0;")
    A("\t\t\tdefaultConfigurationName = Release;")
    A("\t\t};")
    A("/* End XCConfigurationList section */")

    A("\t};")
    A(f"\trootObject = {prj};")
    A("}")

    pbx = PROJ / "project.pbxproj"
    pbx.write_text("\n".join(lines) + "\n")

    scheme_dir = PROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "AnchorApp.xcscheme").write_text(SCHEME)

    print(f"생성 완료: {PROJ}")
    print(f"  소스 {len(app_builds)} (앱) + {len(core_builds)} (core)")
    return 0


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES"
                           buildForProfiling = "YES" buildForArchiving = "YES"
                           buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "__TARGET_ID__"
               BuildableName = "Anchor.app"
               BlueprintName = "AnchorApp"
               ReferencedContainer = "container:AnchorApp.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = ""
      launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES" debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "__TARGET_ID__"
            BuildableName = "Anchor.app"
            BlueprintName = "AnchorApp"
            ReferencedContainer = "container:AnchorApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""

if __name__ == "__main__":
    raise SystemExit(main())
