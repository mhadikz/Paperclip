#!/usr/bin/env python3
"""Regenerates Paperclip.xcodeproj from the files on disk.

The Command Line Tools build (scripts/build.sh) is the source of truth for the compile set;
this script keeps the Xcode project in sync for contributors who prefer Xcode.

    python3 scripts/generate-xcodeproj.py
"""
import hashlib
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "Paperclip.xcodeproj")
PBXPROJ = os.path.join(PROJECT_DIR, "project.pbxproj")

APP_INFO = os.path.join(ROOT, "Paperclip", "Resources", "Info.plist")
with open(APP_INFO, "rb") as fh:
    info = plistlib.load(fh)
VERSION = info["CFBundleShortVersionString"]
BUILD = info["CFBundleVersion"]
BUNDLE_ID = info["CFBundleIdentifier"]

APP_FRAMEWORKS = ["ServiceManagement", "Carbon", "Vision", "WidgetKit", "AppIntents"]
WIDGET_FRAMEWORKS = ["WidgetKit", "SwiftUI", "AppIntents"]


def uid(key: str) -> str:
    """Deterministic 24-hex object id so regenerating produces stable diffs."""
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def swift_files(rel_dir: str):
    out = []
    for base, _dirs, files in os.walk(os.path.join(ROOT, rel_dir)):
        for name in files:
            if name.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(out)


app_sources = [f for f in swift_files("Paperclip")]
widget_sources = swift_files("PaperclipWidget") + [
    "Paperclip/Shared/WidgetSnapshot.swift",
    "Paperclip/Shared/WidgetActions.swift",
]
test_sources = swift_files("PaperclipTests") + [f for f in app_sources if not f.endswith("PaperclipApp.swift")]

objects = {}


def add(obj_id, isa, **fields):
    objects[obj_id] = dict(isa=isa, **fields)
    return obj_id


# --- File references and groups -------------------------------------------------------------

file_refs = {}


def file_ref(rel_path, file_type=None, source_tree="<group>", explicit=False):
    if rel_path in file_refs:
        return file_refs[rel_path]
    oid = uid("ref:" + rel_path)
    fields = {"path": os.path.basename(rel_path), "sourceTree": source_tree}
    ext = os.path.splitext(rel_path)[1]
    if file_type is None:
        file_type = {
            ".swift": "sourcecode.swift",
            ".plist": "text.plist.xml",
            ".entitlements": "text.plist.entitlements",
            ".icns": "image.icns",
            ".md": "net.daringfireball.markdown",
            ".sh": "text.script.sh",
            ".py": "text.script.python",
            ".json": "text.json",
        }.get(ext, "text")
    if explicit:
        fields["explicitFileType"] = file_type
        fields["includeInIndex"] = 0
    else:
        fields["lastKnownFileType"] = file_type
    add(oid, "PBXFileReference", **fields)
    file_refs[rel_path] = oid
    return oid


group_cache = {}


def group_for(rel_dir):
    """Nested PBXGroup mirroring the folder layout."""
    if rel_dir in group_cache:
        return group_cache[rel_dir]
    oid = uid("group:" + rel_dir)
    add(oid, "PBXGroup", children=[], path=os.path.basename(rel_dir), sourceTree="<group>")
    group_cache[rel_dir] = oid
    parent = os.path.dirname(rel_dir)
    if parent:
        objects[group_for(parent)]["children"].append(oid)
    else:
        objects[ROOT_GROUP]["children"].append(oid)
    return oid


ROOT_GROUP = uid("group:<root>")
add(ROOT_GROUP, "PBXGroup", children=[], sourceTree="<group>")


def register(rel_path, **kw):
    ref = file_ref(rel_path, **kw)
    objects[group_for(os.path.dirname(rel_path))]["children"].append(ref)
    return ref


all_files = sorted(set(app_sources + widget_sources + swift_files("PaperclipTests")))
for f in all_files:
    register(f)
for extra in [
    "Paperclip/Resources/Info.plist",
    "Paperclip/Resources/Paperclip.entitlements",
    "Paperclip/Resources/AppIcon.icns",
    "PaperclipWidget/Info.plist",
    "PaperclipWidget/PaperclipWidget.entitlements",
]:
    if os.path.exists(os.path.join(ROOT, extra)):
        register(extra)

# Docs & scripts shown in the navigator for convenience (not compiled).
for extra in ["README.md", "AGENTS.md", "CHANGELOG.md", "LICENSE"]:
    if os.path.exists(os.path.join(ROOT, extra)):
        ref = file_ref(extra)
        objects[ROOT_GROUP]["children"].append(ref)

# Frameworks group
FRAMEWORKS_GROUP = uid("group:Frameworks")
add(FRAMEWORKS_GROUP, "PBXGroup", children=[], name="Frameworks", sourceTree="<group>")
objects[ROOT_GROUP]["children"].append(FRAMEWORKS_GROUP)
framework_refs = {}
for name in sorted(set(APP_FRAMEWORKS + WIDGET_FRAMEWORKS)):
    oid = uid("framework:" + name)
    add(oid, "PBXFileReference", lastKnownFileType="wrapper.framework", name=f"{name}.framework",
        path=f"System/Library/Frameworks/{name}.framework", sourceTree="SDKROOT")
    framework_refs[name] = oid
    objects[FRAMEWORKS_GROUP]["children"].append(oid)

# Products group
PRODUCTS_GROUP = uid("group:Products")
add(PRODUCTS_GROUP, "PBXGroup", children=[], name="Products", sourceTree="<group>")
objects[ROOT_GROUP]["children"].append(PRODUCTS_GROUP)
APP_PRODUCT = file_ref("Paperclip.app", file_type="wrapper.application", source_tree="BUILT_PRODUCTS_DIR", explicit=True)
WIDGET_PRODUCT = file_ref("PaperclipWidgets.appex", file_type="wrapper.app-extension", source_tree="BUILT_PRODUCTS_DIR", explicit=True)
TEST_PRODUCT = file_ref("PaperclipTests", file_type="compiled.mach-o.executable", source_tree="BUILT_PRODUCTS_DIR", explicit=True)
objects[PRODUCTS_GROUP]["children"] += [APP_PRODUCT, WIDGET_PRODUCT, TEST_PRODUCT]

# --- Build files and phases --------------------------------------------------------------------


def build_file(target, rel_path, settings=None):
    oid = uid(f"build:{target}:{rel_path}")
    fields = {"fileRef": file_refs[rel_path]}
    if settings:
        fields["settings"] = settings
    add(oid, "PBXBuildFile", **fields)
    return oid


def framework_build_file(target, name):
    oid = uid(f"buildfw:{target}:{name}")
    add(oid, "PBXBuildFile", fileRef=framework_refs[name])
    return oid


def sources_phase(target, files):
    oid = uid(f"phase:sources:{target}")
    add(oid, "PBXSourcesBuildPhase", buildActionMask=2147483647,
        files=[build_file(target, f) for f in files], runOnlyForDeploymentPostprocessing=0)
    return oid


def frameworks_phase(target, names):
    oid = uid(f"phase:frameworks:{target}")
    add(oid, "PBXFrameworksBuildPhase", buildActionMask=2147483647,
        files=[framework_build_file(target, n) for n in names], runOnlyForDeploymentPostprocessing=0)
    return oid


def resources_phase(target, files):
    oid = uid(f"phase:resources:{target}")
    add(oid, "PBXResourcesBuildPhase", buildActionMask=2147483647,
        files=[build_file(target, f) for f in files], runOnlyForDeploymentPostprocessing=0)
    return oid


def embed_appex_phase():
    oid = uid("phase:embed:app")
    bf = uid("build:app:embed-appex")
    add(bf, "PBXBuildFile", fileRef=WIDGET_PRODUCT, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
    add(oid, "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13,
        files=[bf], name="Embed Foundation Extensions", runOnlyForDeploymentPostprocessing=0)
    return oid


# --- Build configurations -----------------------------------------------------------------------

COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "",
    "MARKETING_VERSION": VERSION,
    "CURRENT_PROJECT_VERSION": BUILD,
    "ENABLE_HARDENED_RUNTIME": "YES",
}
DEBUG_EXTRA = {"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
               "ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
               "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}
RELEASE_EXTRA = {"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_OPTIMIZATION_LEVEL": "-O",
                 "SWIFT_COMPILATION_MODE": "wholemodule"}

APP_SETTINGS = {
    "PRODUCT_NAME": "Paperclip",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "INFOPLIST_FILE": "Paperclip/Resources/Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "Paperclip/Resources/Paperclip.entitlements",
    "GENERATE_INFOPLIST_FILE": "NO",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "COMBINE_HIDPI_IMAGES": "YES",
}
WIDGET_SETTINGS = {
    "PRODUCT_NAME": "PaperclipWidgets",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".Widget",
    "INFOPLIST_FILE": "PaperclipWidget/Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "PaperclipWidget/PaperclipWidget.entitlements",
    "GENERATE_INFOPLIST_FILE": "NO",
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks",
    "SKIP_INSTALL": "YES",
}
TEST_SETTINGS = {
    "PRODUCT_NAME": "PaperclipTests",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".Tests",
    "GENERATE_INFOPLIST_FILE": "YES",
    "ENABLE_HARDENED_RUNTIME": "NO",
}


def config_list(key, base, extra_debug=None, extra_release=None):
    debug = uid(f"config:{key}:Debug")
    release = uid(f"config:{key}:Release")
    add(debug, "XCBuildConfiguration", name="Debug", buildSettings={**base, **DEBUG_EXTRA, **(extra_debug or {})})
    add(release, "XCBuildConfiguration", name="Release", buildSettings={**base, **RELEASE_EXTRA, **(extra_release or {})})
    oid = uid(f"configlist:{key}")
    add(oid, "XCConfigurationList", buildConfigurations=[debug, release],
        defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    return oid


# --- Targets ------------------------------------------------------------------------------------

WIDGET_TARGET = uid("target:widget")
add(WIDGET_TARGET, "PBXNativeTarget", name="PaperclipWidgets", productName="PaperclipWidgets",
    productReference=WIDGET_PRODUCT, productType="com.apple.product-type.app-extension",
    buildConfigurationList=config_list("widget", WIDGET_SETTINGS),
    buildPhases=[sources_phase("widget", widget_sources), frameworks_phase("widget", WIDGET_FRAMEWORKS),
                 resources_phase("widget", [])],
    buildRules=[], dependencies=[])

WIDGET_PROXY = uid("proxy:widget")
WIDGET_DEP = uid("dep:widget")

APP_TARGET = uid("target:app")
add(APP_TARGET, "PBXNativeTarget", name="Paperclip", productName="Paperclip",
    productReference=APP_PRODUCT, productType="com.apple.product-type.application",
    buildConfigurationList=config_list("app", APP_SETTINGS),
    buildPhases=[sources_phase("app", app_sources), frameworks_phase("app", APP_FRAMEWORKS),
                 resources_phase("app", ["Paperclip/Resources/AppIcon.icns"]), embed_appex_phase()],
    buildRules=[], dependencies=[WIDGET_DEP])

TEST_TARGET = uid("target:tests")
add(TEST_TARGET, "PBXNativeTarget", name="PaperclipTests", productName="PaperclipTests",
    productReference=TEST_PRODUCT, productType="com.apple.product-type.tool",
    buildConfigurationList=config_list("tests", TEST_SETTINGS),
    buildPhases=[sources_phase("tests", test_sources), frameworks_phase("tests", APP_FRAMEWORKS)],
    buildRules=[], dependencies=[])

PROJECT = uid("project")
add(WIDGET_PROXY, "PBXContainerItemProxy", containerPortal=PROJECT, proxyType=1,
    remoteGlobalIDString=WIDGET_TARGET, remoteInfo="PaperclipWidgets")
add(WIDGET_DEP, "PBXTargetDependency", target=WIDGET_TARGET, targetProxy=WIDGET_PROXY)

add(PROJECT, "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 1600, "LastUpgradeCheck": 1600,
                "TargetAttributes": {APP_TARGET: {"CreatedOnToolsVersion": "16.0"},
                                     WIDGET_TARGET: {"CreatedOnToolsVersion": "16.0"},
                                     TEST_TARGET: {"CreatedOnToolsVersion": "16.0"}}},
    buildConfigurationList=config_list("project", COMMON),
    compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
    knownRegions=["en", "Base"], mainGroup=ROOT_GROUP, productRefGroup=PRODUCTS_GROUP,
    projectDirPath="", projectRoot="", targets=[APP_TARGET, WIDGET_TARGET, TEST_TARGET])

# --- Serialization (old-style plist) ------------------------------------------------------------


def quote(value):
    s = str(value)
    if s == "":
        return '""'
    safe = all(c.isalnum() or c in "_./-$@" for c in s) and not s.startswith("-")
    if safe:
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def emit(value, indent):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key in sorted(value.keys(), key=lambda k: (k != "isa", k)):
            lines.append(f"{pad}\t{quote(key)} = {emit(value[key], indent + 1)};")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "(\n" + pad + ")"
        inner = "".join(f"{pad}\t{emit(v, indent + 1)},\n" for v in value)
        return "(\n" + inner + pad + ")"
    return quote(value)


ISA_ORDER = ["PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase", "PBXFileReference",
             "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase",
             "PBXSourcesBuildPhase", "PBXTargetDependency", "XCBuildConfiguration", "XCConfigurationList"]

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for isa in ISA_ORDER:
    section = {k: v for k, v in objects.items() if v["isa"] == isa}
    if not section:
        continue
    out.append(f"\n/* Begin {isa} section */")
    for oid in sorted(section):
        obj = section[oid]
        comment = obj.get("name") or obj.get("path") or isa
        body = emit(obj, 2)
        out.append(f"\t\t{oid} /* {comment} */ = {body};")
    out.append(f"/* End {isa} section */")
out.append("\t};")
out.append(f"\trootObject = {PROJECT} /* Project object */;")
out.append("}")

os.makedirs(PROJECT_DIR, exist_ok=True)
with open(PBXPROJ, "w") as fh:
    fh.write("\n".join(out) + "\n")

# Shared scheme so `xcodebuild -scheme Paperclip` works out of the box.
schemes_dir = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")
os.makedirs(schemes_dir, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{APP_TARGET}" BuildableName = "Paperclip.app" BlueprintName = "Paperclip" ReferencedContainer = "container:Paperclip.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{APP_TARGET}" BuildableName = "Paperclip.app" BlueprintName = "Paperclip" ReferencedContainer = "container:Paperclip.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
"""
with open(os.path.join(schemes_dir, "Paperclip.xcscheme"), "w") as fh:
    fh.write(scheme)

print(f"→ Wrote {PBXPROJ} ({len(app_sources)} app files, {len(widget_sources)} widget files, {len(test_sources)} test files)")
