/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType

func xcscheme<T where T:XcodeModuleProtocol, T:Module>(container container: String, modules: [T], printer print: (String) -> Void) {
    print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    print("<Scheme LastUpgradeVersion = \"9999\" version = \"1.3\">")
    print("  <BuildAction parallelizeBuildables = \"YES\" buildImplicitDependencies = \"YES\">")
    print("    <BuildActionEntries>")

    let nontests = modules.filter{ !($0 is TestModule) }
    let tests = modules.filter{ $0 is TestModule }

    for module in nontests {
        print("      <BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">")
        print("        <BuildableReference")
        print("          BuildableIdentifier = \"primary\"")
        print("          BlueprintIdentifier = \"\(module.blueprintIdentifier)\"")
        print("          BuildableName = \"\(module.buildableName)\"")
        print("          BlueprintName = \"\(module.blueprintName)\"")
        print("          ReferencedContainer = \"container:\(container)\">")
        print("        </BuildableReference>")
        print("      </BuildActionEntry>")
    }

    print("    </BuildActionEntries>")
    print("  </BuildAction>")
    print("  <TestAction")
    print("    buildConfiguration = \"Debug\"")
    print("    selectedDebuggerIdentifier = \"Xcode.DebuggerFoundation.Debugger.LLDB\"")
    print("    selectedLauncherIdentifier = \"Xcode.DebuggerFoundation.Launcher.LLDB\"")
    print("    shouldUseLaunchSchemeArgsEnv = \"YES\">")
    print("    <Testables>")

    for module in tests {
        print("    <TestableReference")
        print("      skipped = \"NO\">")
        print("      <BuildableReference")
        print("        BuildableIdentifier = \"primary\"")
        print("        BlueprintIdentifier = \"\(module.blueprintIdentifier)\"")
        print("        BuildableName = \"\(module.buildableName)\"")
        print("        BlueprintName = \"\(module.blueprintName)\"")
        print("        ReferencedContainer = \"container:\(container)\">")
        print("      </BuildableReference>")
        print("    </TestableReference>")
    }

    print("    </Testables>")
    print("  </TestAction>")
    print("</Scheme>")
}
