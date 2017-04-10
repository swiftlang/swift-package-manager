/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageGraph
import PackageModel

func xcscheme(container: String, graph: PackageGraph, codeCoverageEnabled: Bool, printer print: (String) -> Void) {
    print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    print("<Scheme LastUpgradeVersion = \"9999\" version = \"1.3\">")
    print("  <BuildAction parallelizeBuildables = \"YES\" buildImplicitDependencies = \"YES\">")
    print("    <BuildActionEntries>")

    // Create buildable references for non-test targets.
    for target in graph.targets where target.type != .test {
        // Ignore system targets.
        //
        // FIXME: We shouldn't need to manually do this here, instead this
        // should be phrased in terms of the set of targets we computed.
        if target.type == .systemModule {
            continue
        }

        print("      <BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">")
        print("        <BuildableReference")
        print("          BuildableIdentifier = \"primary\"")
        print("          BuildableName = \"\(target.buildableName)\"")
        print("          BlueprintName = \"\(target.blueprintName)\"")
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
    print("    shouldUseLaunchSchemeArgsEnv = \"YES\"")
    print("    codeCoverageEnabled = \"\(codeCoverageEnabled ? "YES" : "NO")\">")
    print("    <Testables>")

    // Create testable references.
    for target in graph.targets where target.type == .test {
        print("    <TestableReference")
        print("      skipped = \"NO\">")
        print("      <BuildableReference")
        print("        BuildableIdentifier = \"primary\"")
        print("        BuildableName = \"\(target.buildableName)\"")
        print("        BlueprintName = \"\(target.blueprintName)\"")
        print("        ReferencedContainer = \"container:\(container)\">")
        print("      </BuildableReference>")
        print("    </TestableReference>")
    }

    print("    </Testables>")
    print("  </TestAction>")
    print("</Scheme>")
}
