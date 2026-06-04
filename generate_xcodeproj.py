#!/usr/bin/env python3
"""
generate_xcodeproj.py

Generates GlanceNote.xcodeproj/project.pbxproj and all required support files
(Info.plist, entitlements, xcscheme) for the GlanceNote multi-target project.

Run from the GlanceNote repository root:
    python3 generate_xcodeproj.py
"""

import os
import uuid
import plistlib
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

ROOT       = Path(__file__).parent.resolve()
XCODEPROJ  = ROOT / "GlanceNote.xcodeproj"
XCSHARED   = XCODEPROJ / "xcshareddata" / "xcschemes"
RESOURCES  = ROOT / "GlanceNote" / "Resources"
WIDGET_DIR = ROOT / "GlanceNoteWidget"

# ---------------------------------------------------------------------------
# UID factory — 24-character uppercase hex, Xcode-compatible
# ---------------------------------------------------------------------------

def u() -> str:
    return uuid.uuid4().hex[:24].upper()

# ---------------------------------------------------------------------------
# Allocate all UIDs up front so every section can reference any other
# ---------------------------------------------------------------------------

# Project
P_PROJECT        = u()
P_MAIN_GROUP     = u()
P_PRODUCTS_GROUP = u()
P_CFG_LIST       = u()
P_DEBUG          = u()
P_RELEASE        = u()

# App target
A_TARGET    = u()
A_CFG_LIST  = u()
A_DEBUG     = u()
A_RELEASE   = u()
A_SOURCES   = u()
A_FRAMEWORKS= u()
A_RESOURCES = u()
A_COPY_EXTS = u()   # Embed extensions phase

# Widget target
W_TARGET    = u()
W_CFG_LIST  = u()
W_DEBUG     = u()
W_RELEASE   = u()
W_SOURCES   = u()
W_FRAMEWORKS= u()
W_RESOURCES = u()

# Dependency wiring (app depends on widget)
DEP_PROXY   = u()
DEP_ITEM    = u()

# Product file references
A_PRODUCT_REF = u()   # GlanceNote.app
W_PRODUCT_REF = u()   # GlanceNoteWidget.appex

# ---------------------------------------------------------------------------
# Source file table
# (path-relative-to-root, display-name, fileref-uid, app-buildfile, widget-buildfile)
# None means "not compiled into this target"
# ---------------------------------------------------------------------------

SOURCES = [
    ("GlanceNote/App/GlanceNoteApp.swift",        "GlanceNoteApp.swift",       u(), u(), None),
    ("GlanceNote/Model/Note.swift",               "Note.swift",                u(), u(), None),
    ("GlanceNote/Shared/NoteCardView.swift",      "NoteCardView.swift",        u(), u(), None),
    ("GlanceNote/macOS/NotePanel.swift",          "NotePanel.swift",           u(), u(), None),
    ("GlanceNote/macOS/PanelRegistry.swift",      "PanelRegistry.swift",       u(), u(), None),
    ("GlanceNote/macOS/MenuBarController.swift",  "MenuBarController.swift",   u(), u(), None),
    ("SharedKit/SharedDataClient.swift",          "SharedDataClient.swift",    u(), u(), u()),
    ("GlanceNoteWidget/GlanceNoteWidget.swift",   "GlanceNoteWidget.swift",    u(), None, u()),
]

# Info.plist file references (treated as resources, not compiled)
A_INFOPLIST_REF = u()
A_INFOPLIST_BF  = u()
W_INFOPLIST_REF = u()
W_INFOPLIST_BF  = u()

# Widget .appex in the embed phase
W_APPEX_EMBED_BF = u()

# ---------------------------------------------------------------------------
# Group UIDs for the navigator tree
# ---------------------------------------------------------------------------
G_GLANCENOTE = u()
G_APP        = u()
G_MODEL      = u()
G_SHARED     = u()
G_MACOS      = u()
G_SHAREDKIT  = u()
G_WIDGET     = u()
G_RESOURCES  = u()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def indent(text: str, level: int = 1) -> str:
    return "\n".join("\t" * level + line if line.strip() else line
                     for line in text.splitlines())

# ---------------------------------------------------------------------------
# pbxproj builder
# ---------------------------------------------------------------------------

def build_pbxproj() -> str:
    lines = []

    def L(s=""):
        lines.append(s)

    # ---- PBXBuildFile section ----
    L("\t\t/* Begin PBXBuildFile section */")
    for path, name, fref, abf, wbf in SOURCES:
        if abf:
            L(f"\t\t{abf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
        if wbf:
            L(f"\t\t{wbf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {name} */; }};")
    L(f"\t\t{A_INFOPLIST_BF} /* Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {A_INFOPLIST_REF} /* Info.plist */; }};")
    L(f"\t\t{W_INFOPLIST_BF} /* Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {W_INFOPLIST_REF} /* Info.plist */; }};")
    L(f"\t\t{W_APPEX_EMBED_BF} /* GlanceNoteWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {W_PRODUCT_REF} /* GlanceNoteWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    L("\t\t/* End PBXBuildFile section */")
    L()

    # ---- PBXCopyFilesBuildPhase section (Embed Extensions) ----
    L("\t\t/* Begin PBXCopyFilesBuildPhase section */")
    L(f"\t\t{A_COPY_EXTS} /* Embed Foundation Extensions */ = {{")
    L(f"\t\t\tisa = PBXCopyFilesBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tdstPath = \"\";")
    L(f"\t\t\tdstSubfolderSpec = 13;")  # PlugIns folder
    L(f"\t\t\tfiles = (")
    L(f"\t\t\t\t{W_APPEX_EMBED_BF} /* GlanceNoteWidget.appex in Embed Foundation Extensions */,")
    L(f"\t\t\t);")
    L(f"\t\t\tname = \"Embed Foundation Extensions\";")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")
    L("\t\t/* End PBXCopyFilesBuildPhase section */")
    L()

    # ---- PBXFileReference section ----
    L("\t\t/* Begin PBXFileReference section */")
    L(f"\t\t{A_PRODUCT_REF} /* GlanceNote.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = GlanceNote.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L(f"\t\t{W_PRODUCT_REF} /* GlanceNoteWidget.appex */ = {{isa = PBXFileReference; explicitFileType = wrapper.app-extension; includeInIndex = 0; path = GlanceNoteWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L(f"\t\t{A_INFOPLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    L(f"\t\t{W_INFOPLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    for path, name, fref, abf, wbf in SOURCES:
        L(f"\t\t{fref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    L("\t\t/* End PBXFileReference section */")
    L()

    # ---- PBXFrameworksBuildPhase section ----
    L("\t\t/* Begin PBXFrameworksBuildPhase section */")
    L(f"\t\t{A_FRAMEWORKS} /* Frameworks */ = {{")
    L(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")
    L(f"\t\t{W_FRAMEWORKS} /* Frameworks */ = {{")
    L(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")
    L("\t\t/* End PBXFrameworksBuildPhase section */")
    L()

    # ---- PBXGroup section ----
    L("\t\t/* Begin PBXGroup section */")

    # Main group
    L(f"\t\t{P_MAIN_GROUP} = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    L(f"\t\t\t\t{G_GLANCENOTE} /* GlanceNote */,")
    L(f"\t\t\t\t{G_SHAREDKIT} /* SharedKit */,")
    L(f"\t\t\t\t{G_WIDGET} /* GlanceNoteWidget */,")
    L(f"\t\t\t\t{P_PRODUCTS_GROUP} /* Products */,")
    L(f"\t\t\t);")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    # Products group
    L(f"\t\t{P_PRODUCTS_GROUP} /* Products */ = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    L(f"\t\t\t\t{A_PRODUCT_REF} /* GlanceNote.app */,")
    L(f"\t\t\t\t{W_PRODUCT_REF} /* GlanceNoteWidget.appex */,")
    L(f"\t\t\t);")
    L(f"\t\t\tname = Products;")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    # GlanceNote top group
    L(f"\t\t{G_GLANCENOTE} /* GlanceNote */ = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    L(f"\t\t\t\t{G_APP} /* App */,")
    L(f"\t\t\t\t{G_MODEL} /* Model */,")
    L(f"\t\t\t\t{G_SHARED} /* Shared */,")
    L(f"\t\t\t\t{G_MACOS} /* macOS */,")
    L(f"\t\t\t\t{G_RESOURCES} /* Resources */,")
    L(f"\t\t\t);")
    L(f"\t\t\tpath = GlanceNote;")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    def file_group(group_uid, group_name, path_prefix, filter_fn):
        L(f"\t\t{group_uid} /* {group_name} */ = {{")
        L(f"\t\t\tisa = PBXGroup;")
        L(f"\t\t\tchildren = (")
        for path, name, fref, abf, wbf in SOURCES:
            if filter_fn(path):
                L(f"\t\t\t\t{fref} /* {name} */,")
        L(f"\t\t\t);")
        L(f"\t\t\tpath = {path_prefix};")
        L(f"\t\t\tsourceTree = \"<group>\";")
        L(f"\t\t}};")

    file_group(G_APP,     "App",    "App",    lambda p: p.startswith("GlanceNote/App/"))
    file_group(G_MODEL,   "Model",  "Model",  lambda p: p.startswith("GlanceNote/Model/"))
    file_group(G_SHARED,  "Shared", "Shared", lambda p: p.startswith("GlanceNote/Shared/"))
    file_group(G_MACOS,   "macOS",  "macOS",  lambda p: p.startswith("GlanceNote/macOS/"))

    # Resources group
    L(f"\t\t{G_RESOURCES} /* Resources */ = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    L(f"\t\t\t\t{A_INFOPLIST_REF} /* Info.plist */,")
    L(f"\t\t\t);")
    L(f"\t\t\tpath = Resources;")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    # SharedKit group
    L(f"\t\t{G_SHAREDKIT} /* SharedKit */ = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    for path, name, fref, abf, wbf in SOURCES:
        if path.startswith("SharedKit/"):
            L(f"\t\t\t\t{fref} /* {name} */,")
    L(f"\t\t\t);")
    L(f"\t\t\tpath = SharedKit;")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    # Widget group
    L(f"\t\t{G_WIDGET} /* GlanceNoteWidget */ = {{")
    L(f"\t\t\tisa = PBXGroup;")
    L(f"\t\t\tchildren = (")
    for path, name, fref, abf, wbf in SOURCES:
        if path.startswith("GlanceNoteWidget/"):
            L(f"\t\t\t\t{fref} /* {name} */,")
    L(f"\t\t\t\t{W_INFOPLIST_REF} /* Info.plist */,")
    L(f"\t\t\t);")
    L(f"\t\t\tpath = GlanceNoteWidget;")
    L(f"\t\t\tsourceTree = \"<group>\";")
    L(f"\t\t}};")

    L("\t\t/* End PBXGroup section */")
    L()

    # ---- PBXNativeTarget section ----
    L("\t\t/* Begin PBXNativeTarget section */")

    # App target
    L(f"\t\t{A_TARGET} /* GlanceNote */ = {{")
    L(f"\t\t\tisa = PBXNativeTarget;")
    L(f"\t\t\tbuildConfigurationList = {A_CFG_LIST} /* Build configuration list for PBXNativeTarget \"GlanceNote\" */;")
    L(f"\t\t\tbuildPhases = (")
    L(f"\t\t\t\t{A_SOURCES} /* Sources */,")
    L(f"\t\t\t\t{A_FRAMEWORKS} /* Frameworks */,")
    L(f"\t\t\t\t{A_RESOURCES} /* Resources */,")
    L(f"\t\t\t\t{A_COPY_EXTS} /* Embed Foundation Extensions */,")
    L(f"\t\t\t);")
    L(f"\t\t\tbuildRules = (")
    L(f"\t\t\t);")
    L(f"\t\t\tdependencies = (")
    L(f"\t\t\t\t{DEP_ITEM} /* PBXTargetDependency */,")
    L(f"\t\t\t);")
    L(f"\t\t\tname = GlanceNote;")
    L(f"\t\t\tproductName = GlanceNote;")
    L(f"\t\t\tproductReference = {A_PRODUCT_REF} /* GlanceNote.app */;")
    L(f"\t\t\tproductType = \"com.apple.product-type.application\";")
    L(f"\t\t}};")

    # Widget target
    L(f"\t\t{W_TARGET} /* GlanceNoteWidget */ = {{")
    L(f"\t\t\tisa = PBXNativeTarget;")
    L(f"\t\t\tbuildConfigurationList = {W_CFG_LIST} /* Build configuration list for PBXNativeTarget \"GlanceNoteWidget\" */;")
    L(f"\t\t\tbuildPhases = (")
    L(f"\t\t\t\t{W_SOURCES} /* Sources */,")
    L(f"\t\t\t\t{W_FRAMEWORKS} /* Frameworks */,")
    L(f"\t\t\t\t{W_RESOURCES} /* Resources */,")
    L(f"\t\t\t);")
    L(f"\t\t\tbuildRules = (")
    L(f"\t\t\t);")
    L(f"\t\t\tdependencies = (")
    L(f"\t\t\t);")
    L(f"\t\t\tname = GlanceNoteWidget;")
    L(f"\t\t\tproductName = GlanceNoteWidget;")
    L(f"\t\t\tproductReference = {W_PRODUCT_REF} /* GlanceNoteWidget.appex */;")
    L(f"\t\t\tproductType = \"com.apple.product-type.app-extension\";")
    L(f"\t\t}};")

    L("\t\t/* End PBXNativeTarget section */")
    L()

    # ---- PBXProject section ----
    L("\t\t/* Begin PBXProject section */")
    L(f"\t\t{P_PROJECT} /* Project object */ = {{")
    L(f"\t\t\tisa = PBXProject;")
    L(f"\t\t\tattributes = {{")
    L(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    L(f"\t\t\t\tLastSwiftUpdateCheck = 1540;")
    L(f"\t\t\t\tLastUpgradeCheck = 1540;")
    L(f"\t\t\t\tTargetAttributes = {{")
    L(f"\t\t\t\t\t{A_TARGET} = {{")
    L(f"\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
    L(f"\t\t\t\t\t}};")
    L(f"\t\t\t\t\t{W_TARGET} = {{")
    L(f"\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;")
    L(f"\t\t\t\t\t}};")
    L(f"\t\t\t\t}};")
    L(f"\t\t\t}};")
    L(f"\t\t\tbuildConfigurationList = {P_CFG_LIST} /* Build configuration list for PBXProject \"GlanceNote\" */;")
    L(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    L(f"\t\t\tdevelopmentRegion = en;")
    L(f"\t\t\thasScannedForEncodings = 0;")
    L(f"\t\t\tknownRegions = (")
    L(f"\t\t\t\ten,")
    L(f"\t\t\t\tBase,")
    L(f"\t\t\t);")
    L(f"\t\t\tmainGroup = {P_MAIN_GROUP};")
    L(f"\t\t\tproductsGroup = {P_PRODUCTS_GROUP} /* Products */;")
    L(f"\t\t\tprojectDirPath = \"\";")
    L(f"\t\t\tprojectRoot = \"\";")
    L(f"\t\t\ttargets = (")
    L(f"\t\t\t\t{A_TARGET} /* GlanceNote */,")
    L(f"\t\t\t\t{W_TARGET} /* GlanceNoteWidget */,")
    L(f"\t\t\t);")
    L(f"\t\t}};")
    L("\t\t/* End PBXProject section */")
    L()

    # ---- PBXResourcesBuildPhase section ----
    L("\t\t/* Begin PBXResourcesBuildPhase section */")
    L(f"\t\t{A_RESOURCES} /* Resources */ = {{")
    L(f"\t\t\tisa = PBXResourcesBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")
    L(f"\t\t{W_RESOURCES} /* Resources */ = {{")
    L(f"\t\t\tisa = PBXResourcesBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")
    L("\t\t/* End PBXResourcesBuildPhase section */")
    L()

    # ---- PBXSourcesBuildPhase section ----
    L("\t\t/* Begin PBXSourcesBuildPhase section */")

    # App sources
    L(f"\t\t{A_SOURCES} /* Sources */ = {{")
    L(f"\t\t\tisa = PBXSourcesBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    for path, name, fref, abf, wbf in SOURCES:
        if abf:
            L(f"\t\t\t\t{abf} /* {name} in Sources */,")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")

    # Widget sources
    L(f"\t\t{W_SOURCES} /* Sources */ = {{")
    L(f"\t\t\tisa = PBXSourcesBuildPhase;")
    L(f"\t\t\tbuildActionMask = 2147483647;")
    L(f"\t\t\tfiles = (")
    for path, name, fref, abf, wbf in SOURCES:
        if wbf:
            L(f"\t\t\t\t{wbf} /* {name} in Sources */,")
    L(f"\t\t\t);")
    L(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L(f"\t\t}};")

    L("\t\t/* End PBXSourcesBuildPhase section */")
    L()

    # ---- PBXTargetDependency section ----
    L("\t\t/* Begin PBXTargetDependency section */")
    L(f"\t\t{DEP_ITEM} /* PBXTargetDependency */ = {{")
    L(f"\t\t\tisa = PBXTargetDependency;")
    L(f"\t\t\ttarget = {W_TARGET} /* GlanceNoteWidget */;")
    L(f"\t\t\ttargetProxy = {DEP_PROXY} /* PBXContainerItemProxy */;")
    L(f"\t\t}};")
    L("\t\t/* End PBXTargetDependency section */")
    L()

    # ---- PBXContainerItemProxy section ----
    L("\t\t/* Begin PBXContainerItemProxy section */")
    L(f"\t\t{DEP_PROXY} /* PBXContainerItemProxy */ = {{")
    L(f"\t\t\tisa = PBXContainerItemProxy;")
    L(f"\t\t\tcontainerPortal = {P_PROJECT} /* Project object */;")
    L(f"\t\t\tproxyType = 1;")
    L(f"\t\t\tremoteGlobalIDString = {W_TARGET};")
    L(f"\t\t\tremoteInfo = GlanceNoteWidget;")
    L(f"\t\t}};")
    L("\t\t/* End PBXContainerItemProxy section */")
    L()

    # ---- XCBuildConfiguration section ----
    L("\t\t/* Begin XCBuildConfiguration section */")

    # Project-level Debug
    L(f"\t\t{P_DEBUG} /* Debug */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    L(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    L(f"\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
    L(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    L(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    L(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    L(f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    L(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    L(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    L(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    L(f"\t\t\t\tENABLE_TESTABILITY = YES;")
    L(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    L(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    L(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    L(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    L(f"\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\");")
    L(f"\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    L(f"\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    L(f"\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    L(f"\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    L(f"\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    L(f"\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    L(f"\t\t\t\tMTL_FAST_MATH = YES;")
    L(f"\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    L(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    L(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Debug;")
    L(f"\t\t}};")

    # Project-level Release
    L(f"\t\t{P_RELEASE} /* Release */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    L(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    L(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    L(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    L(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    L(f"\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    L(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    L(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    L(f"\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    L(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    L(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    L(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    L(f"\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    L(f"\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    L(f"\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    L(f"\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    L(f"\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    L(f"\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tMTL_FAST_MATH = YES;")
    L(f"\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    L(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Release;")
    L(f"\t\t}};")

    # App target Debug
    L(f"\t\t{A_DEBUG} /* Debug */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    L(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = GlanceNote/Resources/GlanceNote.entitlements;")
    L(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    L(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    L(f"\t\t\t\tDEVELOPMENT_TEAM = \"\";")
    L(f"\t\t\t\tINFOPLIST_FILE = GlanceNote/Resources/Info.plist;")
    L(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/../Frameworks\");")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.yourteam.glancenote;")
    L(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    L(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    L(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Debug;")
    L(f"\t\t}};")

    # App target Release
    L(f"\t\t{A_RELEASE} /* Release */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    L(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = GlanceNote/Resources/GlanceNote.entitlements;")
    L(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    L(f"\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    L(f"\t\t\t\tDEVELOPMENT_TEAM = \"\";")
    L(f"\t\t\t\tINFOPLIST_FILE = GlanceNote/Resources/Info.plist;")
    L(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/../Frameworks\");")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.yourteam.glancenote;")
    L(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    L(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    L(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Release;")
    L(f"\t\t}};")

    # Widget target Debug
    L(f"\t\t{W_DEBUG} /* Debug */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = GlanceNoteWidget/GlanceNoteWidget.entitlements;")
    L(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    L(f"\t\t\t\tDEVELOPMENT_TEAM = \"\";")
    L(f"\t\t\t\tINFOPLIST_FILE = GlanceNoteWidget/Info.plist;")
    L(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/../Frameworks\", \"@executable_path/../../../../Frameworks\");")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.yourteam.glancenote.widget;")
    L(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    L(f"\t\t\t\tSKIP_INSTALL = YES;")
    L(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    L(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Debug;")
    L(f"\t\t}};")

    # Widget target Release
    L(f"\t\t{W_RELEASE} /* Release */ = {{")
    L(f"\t\t\tisa = XCBuildConfiguration;")
    L(f"\t\t\tbuildSettings = {{")
    L(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = GlanceNoteWidget/GlanceNoteWidget.entitlements;")
    L(f"\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    L(f"\t\t\t\tDEVELOPMENT_TEAM = \"\";")
    L(f"\t\t\t\tINFOPLIST_FILE = GlanceNoteWidget/Info.plist;")
    L(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/../Frameworks\", \"@executable_path/../../../../Frameworks\");")
    L(f"\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    L(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.yourteam.glancenote.widget;")
    L(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    L(f"\t\t\t\tSKIP_INSTALL = YES;")
    L(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    L(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    L(f"\t\t\t}};")
    L(f"\t\t\tname = Release;")
    L(f"\t\t}};")

    L("\t\t/* End XCBuildConfiguration section */")
    L()

    # ---- XCConfigurationList section ----
    L("\t\t/* Begin XCConfigurationList section */")

    L(f"\t\t{P_CFG_LIST} /* Build configuration list for PBXProject \"GlanceNote\" */ = {{")
    L(f"\t\t\tisa = XCConfigurationList;")
    L(f"\t\t\tbuildConfigurations = (")
    L(f"\t\t\t\t{P_DEBUG} /* Debug */,")
    L(f"\t\t\t\t{P_RELEASE} /* Release */,")
    L(f"\t\t\t);")
    L(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    L(f"\t\t\tdefaultConfigurationName = Release;")
    L(f"\t\t}};")

    L(f"\t\t{A_CFG_LIST} /* Build configuration list for PBXNativeTarget \"GlanceNote\" */ = {{")
    L(f"\t\t\tisa = XCConfigurationList;")
    L(f"\t\t\tbuildConfigurations = (")
    L(f"\t\t\t\t{A_DEBUG} /* Debug */,")
    L(f"\t\t\t\t{A_RELEASE} /* Release */,")
    L(f"\t\t\t);")
    L(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    L(f"\t\t\tdefaultConfigurationName = Release;")
    L(f"\t\t}};")

    L(f"\t\t{W_CFG_LIST} /* Build configuration list for PBXNativeTarget \"GlanceNoteWidget\" */ = {{")
    L(f"\t\t\tisa = XCConfigurationList;")
    L(f"\t\t\tbuildConfigurations = (")
    L(f"\t\t\t\t{W_DEBUG} /* Debug */,")
    L(f"\t\t\t\t{W_RELEASE} /* Release */,")
    L(f"\t\t\t);")
    L(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    L(f"\t\t\tdefaultConfigurationName = Release;")
    L(f"\t\t}};")

    L("\t\t/* End XCConfigurationList section */")

    # Assemble full pbxproj
    objects_block = "\n".join(lines)

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

{objects_block}

\t}};
\trootObject = {P_PROJECT} /* Project object */;
}}
"""


# ---------------------------------------------------------------------------
# Info.plist — App target
# ---------------------------------------------------------------------------

APP_INFOPLIST = {
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    # Hide from Dock and App Switcher — menu bar only
    "LSUIElement": True,
    "NSHumanReadableCopyright": "Copyright © 2024. All rights reserved.",
    # Required for local notifications (reminders)
    "NSUserNotificationAlertStyle": "alert",
    # Required for macOS Sonoma+ privacy prompts
    "NSAppleEventsUsageDescription": "GlanceNote uses Apple Events for widget updates.",
}

# ---------------------------------------------------------------------------
# Info.plist — Widget target
# ---------------------------------------------------------------------------

WIDGET_INFOPLIST = {
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleDisplayName": "GlanceNote Widget",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "NSExtension": {
        "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
    },
}

# ---------------------------------------------------------------------------
# Entitlements — App
# ---------------------------------------------------------------------------

APP_ENTITLEMENTS = {
    # iCloud entitlements (ubiquity-kvstore-identifier, icloud-container-identifiers)
    # require a paid Apple Developer Program membership and are intentionally
    # omitted here. Add them once you have a paid account and a registered App ID.
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.application-groups": ["group.com.yourteam.glancenote"],
}

# ---------------------------------------------------------------------------
# Entitlements — Widget
# ---------------------------------------------------------------------------

WIDGET_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.application-identifier": "$(AppIdentifierPrefix)com.yourteam.glancenote.widget",
    "com.apple.security.application-groups": ["group.com.yourteam.glancenote"],
}

# ---------------------------------------------------------------------------
# Xcscheme
# ---------------------------------------------------------------------------

def build_scheme() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{A_TARGET}"
               BuildableName = "GlanceNote.app"
               BlueprintName = "GlanceNote"
               ReferencedContainer = "container:GlanceNote.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{A_TARGET}"
            BuildableName = "GlanceNote.app"
            BlueprintName = "GlanceNote"
            ReferencedContainer = "container:GlanceNote.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{A_TARGET}"
            BuildableName = "GlanceNote.app"
            BlueprintName = "GlanceNote"
            ReferencedContainer = "container:GlanceNote.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


# ---------------------------------------------------------------------------
# Write helpers
# ---------------------------------------------------------------------------

def write(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"  wrote  {path.relative_to(ROOT)}")

def write_plist(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML)
    print(f"  wrote  {path.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Generating GlanceNote.xcodeproj …\n")

    # project.pbxproj
    write(XCODEPROJ / "project.pbxproj", build_pbxproj())

    # xcscheme
    write(XCSHARED / "GlanceNote.xcscheme", build_scheme())

    # workspace settings (makes Xcode use the project, not a workspace)
    write(
        XCODEPROJ / "project.xcworkspace" / "contents.xcworkspacedata",
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace version = "1.0">\n'
        '   <FileRef location = "self:"></FileRef>\n'
        '</Workspace>\n'
    )

    # App Info.plist
    write_plist(RESOURCES / "Info.plist", APP_INFOPLIST)

    # App entitlements
    write_plist(RESOURCES / "GlanceNote.entitlements", APP_ENTITLEMENTS)

    # Widget Info.plist
    write_plist(WIDGET_DIR / "Info.plist", WIDGET_INFOPLIST)

    # Widget entitlements
    write_plist(WIDGET_DIR / "GlanceNoteWidget.entitlements", WIDGET_ENTITLEMENTS)

    print("\nDone. Open the project with:")
    print(f"\n    open \"{XCODEPROJ}\"\n")
    print("First-build checklist:")
    print("  1. Set your Team in Signing & Capabilities for both targets.")
    print("  2. Replace 'com.yourteam' with your actual bundle ID prefix.")
    print("  3. Ensure the App Group identifier matches in both entitlements.")


if __name__ == "__main__":
    main()
