/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageGraph
import PackageModel

func xcscheme(container: String, graph: PackageGraph, enableCodeCoverage: Bool, printer print: (String) -> Void) {
    print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    print("<Scheme LastUpgradeVersion = \"9999\" version = \"1.3\">")
    print("  <BuildAction parallelizeBuildables = \"YES\" buildImplicitDependencies = \"YES\">")
    print("    <BuildActionEntries>")

    // Create buildable references for non-test modules.
    for module in graph.modules where !module.isTest {
        // Ignore system modules.
        //
        // FIXME: We shouldn't need to manually do this here, instead this
        // should be phrased in terms of the set of targets we computed.
        if module.type == .systemModule {
            continue
        }
        
        print("      <BuildActionEntry buildForTesting = \"YES\" buildForRunning = \"YES\" buildForProfiling = \"YES\" buildForArchiving = \"YES\" buildForAnalyzing = \"YES\">")
        print("        <BuildableReference")
        print("          BuildableIdentifier = \"primary\"")
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
    print("    shouldUseLaunchSchemeArgsEnv = \"YES\"")
    print("    codeCoverageEnabled = \"\(enableCodeCoverage ? "YES" : "NO")\">")
    print("    <Testables>")

    // Create testable references.
    for module in graph.modules where module.isTest {
        print("    <TestableReference")
        print("      skipped = \"NO\">")
        print("      <BuildableReference")
        print("        BuildableIdentifier = \"primary\"")
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
