# Swift Package Manager: Quick Start
Swift Package Manager (SwiftPM) is a tool for building, testing and managing Swift project dependencies.
In order to use it you will need Swift 3.0 or greater.
SwiftPM is also included in Xcode 8.0 and above.
For usage getting started: [https://swift.org/getting-started/#using-the-package-manager](https://swift.org/getting-started/#using-the-package-manager)
For overview and examples: [https://swift.org/package-manager](https://swift.org/package-manager/)

## Code Contributions
Everyone is welcome to contribute to SwiftPM, submitting fixes, enhancement etc.
Find out how previous coding decisions for SwiftPM evolution have been made: https://github.com/apple/swift-package-manager/blob/main/Documentation/Internals/PackageManagerCommunityProposal.md

### Requirements
You have multiple ways to setup your development environment, here we will focus on 2:
A) *[Using Xcode](#using-xcode)* or B) [Using *the standalone Swift toolchain*](#using-standalone).

<a id="using-xcode">*A) _Use Xcode to setup what you need_*.</a>
Xcode is only available for macOS.

1. Install Xcode 12 - [https://developer.apple.com/xcode](https://developer.apple.com/xcode/)
2. Make sure you have at least SwiftPM 5.3:
```
$> swift package --version
Swift Package Manager - Swift 5.3.0
```
3. Make sure you have at least Swift 5.3:
```
$> swift --version
Apple Swift version 5.3
```
If you were able to do and verify the steps above, go to [**Getting Started**](#getting-started)

<a id="using-standalone">*B) _Use standalone Swift toolchain</a>: 2a) [On macOS](#on-macos) or 2b) [On Linux](#on-linux)_*.

Procedure valid for macOS and Linux.

1. Pull the Swift repository:
```
git clone https://github.com/apple/swift.git
```
- 2 a. <a id="on-macos">On macOS</a>
```
PATH/TO/REPO/swift/utils/build-script --preset=buildbot_swiftpm_macos_platform,tools=RA,stdlib=RA
```
- 2b. <a id="on-linux">On Linux</a>
```
PATH/TO/REPO/swift/utils/build-script --preset=buildbot_swiftpm_linux_platform,tools=RA,stdlib=RA
```

### <a name="getting-started">Getting Started</a>
1. Pull the SwiftPM repository:
```
git clone https://github.com/apple/swift-package-manager.git
```
2. Run your first build:
```
$> cd swift-package-manager
$> swift build
```
If the build process ends with exit code 0, the build is successful (we have an Enhancement Radar to implement a message for successful build and a short output on where the generated binaries are: rdar://69970428).
After a successful build (currently), you should see something like this:
```
[476/476] Linking swift-package
```
A `.build/` folder will be generated and it should have inside a similar structure (including build binaries):
```
artifacts/
checkouts/
debug/
repositories
x86_64-apple-macosx
debug.yaml
manifest.db
workspace-state.json 
```
Binaries (in the example above) are in `x86_64-apple-macosx/`
If you need to build the generated binaries, run `swift-build` in inside `.build/`:
```
./.build/x86_64-apple-macosx/debug/swift-build
```

### Code Editor
If you are contributing using macOS, the best option is to use Xcode to build and run test SwiftPM. 

### Troubleshooting
* If during `swift build` you encounter these outputs:
```
/../swift-package-manager/Sources/SPMTestSupport/misc.swift:93:35: warning: parameter 'file' with default argument '#file' passed to parameter 'file', whose default argument is '#filePath'
        XCTFail("\(error)", file: file, line: line)
                                  ^
/../swift-package-manager/Sources/SPMTestSupport/misc.swift:37:26: note: did you mean for parameter 'file' to default to '#filePath'?
    file: StaticString = #file,
                         ^~~~~
                         #filePath
/../swift-package-manager/Sources/SPMTestSupport/misc.swift:93:35: note: add parentheses to silence this warning
        XCTFail("\(error)", file: file, line: line)
                                  ^
                                  (   )
```
Do not worry, since those are known warnings that will be addressed at some point.
Warnings differ depending on the platform and they can be seen from time to time due the amount of contributions.
Our goal is to constantly monitor warnings and work on fix them (even if they are not affecting a successful implementation).
* If during `swift build` you encounter this error:
```
/../apple-repos/swift-package-manager/.build/checkouts/swift-driver/Sources/SwiftDriver/Explicit Module Builds/InterModuleDependencyGraph.swift:102:3: error: unknown attribute '_spi'
  @_spi(Testing) public var isFramework: Bool
  ^
```
Make sure you are using SwiftPM 5.3
```
$> swift package --version
Swift Package Manager - Swift 5.3.0
```

### Find your way to contribute
Report a bug guide: https://github.com/apple/swift-package-manager/blob/main/Documentation/Resources.md#reporting-a-good-swiftpm-bug.
JIRA Bug Tracker (a place where you can open bugs, enhancements to start to contribute): [https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22](https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22).

### Commits / PRs
1. Fork: https://github.com/apple/swift-package-manager
2. Clone a working copy of your fork
3. Create a new branch
4. Make your code changes
5. Commit (include the Radar link or JIRA issue id in the commit message if possible and a description your changes)
6. Push the commit / branch to your fork
7. Make a PR from your fork / branch to `apple: main`
8. Leave a new comment to trigger smoke tests: `@swift-ci please smoke test`
9. Reviewers are going to be automatically added to your PR
10. Merge pull request when you received approval from the reviewers (one or more)

### Community and Support
If you want to connect with the Swift community you can:
* Use Swift Forums: [https://forums.swift.org](https://forums.swift.org/)
* Contact the CODEOWNERS: https://github.com/apple/swift-package-manager/blob/main/CODEOWNERS
(mailing lists are usually the best place to go for help: [code-owners@swift.org](mailto:code-owners@swift.org), [conduct@swift.org](mailto:conduct@swift.org), [swift-infrastructure@swift.org](mailto:swift-infrastructure@swift.org)

### Additional Links
* Official Apple GitHub
[https://github.com/apple](https://github.com/apple)
* Swift Package Manager GitHub
[https://github.com/apple/swift-package-manager](https://github.com/apple/swift-package-manager)
* Setup Development
[https://github.com/apple/swift-package-manager/blob/main/Documentation/Development.md](https://github.com/apple/swift-package-manager/blob/main/Documentation/Development.md)
* `Swift.org` Contributing page
[https://swift.org/contributing/](https://swift.org/contributing/)
* License
[https://swift.org/LICENSE.txt](https://swift.org/LICENSE.txt)
* Code of Conduct
[https://swift.org/community/#code-of-conduct](https://swift.org/community/#code-of-conduct)
