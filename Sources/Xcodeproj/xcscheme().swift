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
    print("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "9999" version = "1.3">
          <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
            <BuildActionEntries>
        """)

    // Create buildable references for non-test targets.
    for target in graph.targets where target.type != .test {
        // Ignore system targets.
        //
        // FIXME: We shouldn't need to manually do this here, instead this
        // should be phrased in terms of the set of targets we computed.
        if target.type == .systemModule {
            continue
        }

        print("""
                  <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                    <BuildableReference
                      BuildableIdentifier = "primary"
                      BuildableName = "\(target.buildableName)"
                      BlueprintName = "\(target.blueprintName)"
                      ReferencedContainer = "container:\(container)">
                    </BuildableReference>
                  </BuildActionEntry>
            """)
    }

    print("""
            </BuildActionEntries>
          </BuildAction>
          <TestAction
            buildConfiguration = "Debug"
            selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
            selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
            shouldUseLaunchSchemeArgsEnv = "YES"
            codeCoverageEnabled = "\(codeCoverageEnabled ? "YES" : "NO")">
            <Testables>
        """)

    // Create testable references.
    for target in graph.targets where target.type == .test {
        print("""
                <TestableReference
                  skipped = "NO">
                  <BuildableReference
                    BuildableIdentifier = "primary"
                    BuildableName = "\(target.buildableName)"
                    BlueprintName = "\(target.blueprintName)"
                    ReferencedContainer = "container:\(container)">
                  </BuildableReference>
                </TestableReference>
            """)
    }

    print("""
            </Testables>
          </TestAction>
        </Scheme>
        """)
}
