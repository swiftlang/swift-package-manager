/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


//TODO our references should remain human readable, but they
// aren't unique enough, eg. if a module is called ProxyFoo then the TargetProxy for Foo will conflict with the Target for ProxyFoo

//TODO blue folder everything not part of the build

//TODO split out tests and non-tests in Products group

//TODO enable code coverage

//TODO make frameworks instead of dylibs and command line toggle


import PackageType
import Utility
import POSIX

public func create(path path: String, package: Package, modules: [SwiftModule], products: [Product]) throws {

    let dirname = try mkdir(path, "\(package.name).xcodeproj")

    try fopen(dirname, "project.pbxproj", mode: .Write) { fp in
        try print(package: package, modules: modules, products: products) { line in
            try fputs(line, fp)
            try fputs("\n", fp)
        }
    }

    let schemedir = try mkdir(dirname, "xcshareddata/xcschemes")

    try fopen(schemedir, "\(package.name).xcscheme", mode: .Write) { fp in

        func write(line: String) throws {
            try fputs(line, fp)
            try fputs("\n", fp)
        }

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        try write("<Scheme LastUpgradeVersion = \"9999\" version = \"1.3\">")
        try write("  <BuildAction parallelizeBuildables = \"YES\" buildImplicitDependencies = \"YES\">")
        try write("    <BuildActionEntries>")

        let nontests = modules.filter{ !($0 is TestModule) }
        let tests = modules.filter{ $0 is TestModule }

        for module in nontests {
            try write("      <BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">")
            try write("        <BuildableReference")
            try write("          BuildableIdentifier = \"primary\"")
            try write("          BlueprintIdentifier = \"\(module.blueprintIdentifier)\"")
            try write("          BuildableName = \"\(module.buildableName)\"")
            try write("          BlueprintName = \"\(module.blueprintName)\"")
            try write("          ReferencedContainer = \"container:\(package.name).xcodeproj\">")
            try write("        </BuildableReference>")
            try write("      </BuildActionEntry>")
        }

        try write("    </BuildActionEntries>")
        try write("  </BuildAction>")
        try write("  <TestAction")
        try write("    buildConfiguration = \"Debug\"")
        try write("    selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\"")
        try write("    selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\"")
        try write("    shouldUseLaunchSchemeArgsEnv = \"YES\">")
        try write("    <Testables>")

        for module in tests {

            try write("    <TestableReference")
            try write("      skipped = \"NO\">")
            try write("      <BuildableReference")
            try write("        BuildableIdentifier = \"primary\"")
            try write("        BlueprintIdentifier = \"\(module.blueprintIdentifier)\"")
            try write("        BuildableName = \"\(module.buildableName)\"")
            try write("        BlueprintName = \"\(module.blueprintName)\"")
            try write("        ReferencedContainer = \"container:\(package.name).xcodeproj\">")
            try write("      </BuildableReference>")
            try write("    </TestableReference>")
        }

        try write("    </Testables>")
        try write("  </TestAction>")
        try write("</Scheme>")
    }

    try fopen(schemedir, "xcschememanagement.plist", mode: .Write) { fp in
        func write(line: String) throws {
            try fputs(line, fp)
            try fputs("\n", fp)
        }

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        try write("<plist version=\"1.0\">")
        try write("<dict>")
        try write("  <key>SchemeUserState</key>")
        try write("  <dict>")
        try write("    <key>\(package.name).xcscheme</key>")
        try write("    <dict></dict>")
        try write("  </dict>")
        try write("  <key>SuppressBuildableAutocreation</key>")
        try write("  <dict></dict>")
        try write("</dict>")
        try write("</plist>")
    }
}
