/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageGraph
import PackageModel

/// Represents a scheme in Xcode for the project generation support.
public struct Scheme {

    /// The name of the scheme.
    public var name: String

    /// The scheme filename.
    public var filename: String {
        return name + ".xcscheme"
    }

    /// The list of regular targets contained in this scheme.
    public var regularTargets: Set<ResolvedTarget>

    /// The list of test targets contained in this scheme.
    public var testTargets: Set<ResolvedTarget>

    init(name: String, regularTargets: [ResolvedTarget], testTargets: [ResolvedTarget]) {
        self.name = name
        self.regularTargets = Set(regularTargets)
        self.testTargets = Set(testTargets)
    }
}

public final class SchemesGenerator {

    private let graph: PackageGraph
    private let container: String
    private let schemesDir: AbsolutePath
    private let isCodeCoverageEnabled: Bool
    private let fs: FileSystem

    public init(
        graph: PackageGraph,
        container: String,
        schemesDir: AbsolutePath,
        isCodeCoverageEnabled: Bool,
        fs: FileSystem
    ) {
        self.graph = graph
        self.container = container
        self.schemesDir = schemesDir
        self.isCodeCoverageEnabled = isCodeCoverageEnabled
        self.fs = fs
    }

    public func buildSchemes() -> [Scheme] {
        let rootPackage = graph.rootPackages[0]

        var schemes: [Scheme] = []

        let testTargetsMap = graph.computeTestTargetsForExecutableTargets()

        // Create one scheme per executable target.
        for target in rootPackage.targets where target.type == .executable {
            let testTargets = testTargetsMap[target]

            schemes.append(Scheme(
                name: target.name,
                regularTargets: [target],
                testTargets: testTargets ?? []
            ))
        }

        // Finally, create one master scheme for the entire package.
        let regularTargets = rootPackage.targets.filter({ 
            switch $0.type {
            case .test, .systemModule, .binary:
                return false
            case .executable, .library:
                return true
            }
        })
        schemes.append(Scheme(
            name: rootPackage.name + "-Package",
            regularTargets: regularTargets,
            testTargets: rootPackage.targets.filter({ $0.type == .test })
        ))

        return schemes
    }

    func generate() throws {
        let schemes = buildSchemes()
        for scheme in schemes {
            try create(scheme)
        }

        try disableSchemeAutoCreation()
    }

    private func create(_ scheme: Scheme) throws {
        assert(!scheme.regularTargets.isEmpty, "Scheme \(scheme.name) contains no target")

        let stream = BufferedOutputByteStream()
        stream <<< """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme LastUpgradeVersion = "9999" version = "1.3">
              <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
                <BuildActionEntries>

            """

        // Create buildable references for non-test targets.
        for target in scheme.regularTargets {
            stream <<< """
                      <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                        <BuildableReference
                          BuildableIdentifier = "primary"
                          BuildableName = "\(target.buildableName)"
                          BlueprintName = "\(target.blueprintName)"
                          ReferencedContainer = "container:\(container)">
                        </BuildableReference>
                      </BuildActionEntry>

                """
        }

        stream <<< """
                </BuildActionEntries>
              </BuildAction>

            """

        stream <<< """
              <TestAction
                buildConfiguration = "Debug"
                selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
                selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
                shouldUseLaunchSchemeArgsEnv = "YES"
                codeCoverageEnabled = "\(isCodeCoverageEnabled ? "YES" : "NO")">
                <Testables>

            """

        // Create testable references.
        for target in scheme.testTargets {
            stream <<< """
                        <TestableReference
                          skipped = "NO">
                          <BuildableReference
                            BuildableIdentifier = "primary"
                            BuildableName = "\(target.buildableName)"
                            BlueprintName = "\(target.blueprintName)"
                            ReferencedContainer = "container:\(container)">
                          </BuildableReference>
                        </TestableReference>

                """
        }

        stream <<< """
                </Testables>
              </TestAction>

            """

        if let target = scheme.regularTargets.first {
            if scheme.regularTargets.count == 1 && target.type == .executable {
                stream <<< """
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
                             BuildableName = "\(target.buildableName)"
                             BlueprintName = "\(target.blueprintName)"
                             ReferencedContainer = "container:\(container)">
                          </BuildableReference>
                       </BuildableProductRunnable>
                       <AdditionalOptions>
                       </AdditionalOptions>
                    </LaunchAction>

                    """
            }
        }

        stream <<< """
            </Scheme>

            """

        let file = schemesDir.appending(RelativePath(scheme.filename))
        try fs.writeFileContents(file, bytes: stream.bytes)
    }

    private func disableSchemeAutoCreation() throws {
        let workspacePath = schemesDir.appending(RelativePath("../../project.xcworkspace"))

        // Write the settings file to disable automatic scheme creation.
        var stream = BufferedOutputByteStream()
        stream <<< """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
                <false/>
            </dict>
            </plist>
            """
        let settingsPlist = workspacePath.appending(RelativePath("xcshareddata/WorkspaceSettings.xcsettings"))
        try fs.createDirectory(settingsPlist.parentDirectory, recursive: true)
        try fs.writeFileContents(settingsPlist, bytes: stream.bytes)

        // Write workspace contents file.
        let contentsFile = workspacePath.appending(RelativePath("contents.xcworkspacedata"))
        stream = BufferedOutputByteStream()
        stream <<< """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace
               version = "1.0">
               <FileRef
                  location = "self:">
               </FileRef>
            </Workspace>
            """
        try fs.createDirectory(contentsFile.parentDirectory, recursive: true)
        try fs.writeFileContents(contentsFile, bytes: stream.bytes)
    }
}

func legacySchemeGenerator(container: String, graph: PackageGraph, codeCoverageEnabled: Bool, printer print: (String) -> Void) {
    print("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "9999" version = "1.3">
          <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
            <BuildActionEntries>
        """)

    // Create buildable references for non-test targets.
    for target in graph.reachableTargets where target.type != .test {
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
    for target in graph.reachableTargets where target.type == .test {
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
