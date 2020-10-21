# Contributing to Swift Package Manager
There are several types of contributions one can make. Bug fixes, documentation and enhancements that do not materially change the user facing semantics of Swift Package Manager should be submitted directly as PR. 

Larger changes that do materially change the semantics of Swift Package Manager (e.g. changes to the manifest format or behavior) are required to go through [Swift Evolution Process](https://github.com/apple/swift-evolution/blob/master/process.md).
To see how previous evolution decisions for SwiftPM have been made check out https://github.com/apple/swift-package-manager/blob/main/Documentation/Internals/PackageManagerCommunityProposal.md.  

For more information about making contributions to the Swift project in general see [Swift Contribution Guide](https://swift.org/contributing/)  

## Reporting issues
Report a bug guide: https://github.com/apple/swift-package-manager/blob/main/Documentation/Resources.md#reporting-a-good-swiftpm-bug.  
JIRA Bug Tracker (a place where you can open bugs, enhancements to start to contribute): [https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22](https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22).

## Development environment
If you are contributing using macOS, the best option is to use Xcode to build and run test SwiftPM.  
You have multiple ways to setup your development environment, here we will focus on two:  
* [Using Xcode](#using-xcode)
* [Using a standalone Swift toolchain](#using-standalone)

<a id="using-xcode">*A) _Use Xcode to setup what you need_*.</a>  
Xcode is only available for macOS.

1. Install latest Xcode - [https://developer.apple.com/xcode](https://developer.apple.com/xcode/)
2. Confirm you have the latest SwiftPM:
```
$> swift package --version
Swift Package Manager - Swift 5.3.0
```
3. Confirm you have the latest Swift version:
```
$> swift --version
Apple Swift version 5.3
```

<a id="using-standalone">*B) _Use standalone Swift toolchain_*</a>:  
Download the toolchain from https://swift.org/download/ (or use tools like swiftenv) and confirm its installed correctly as described above.

## <a name="getting-started">Getting Started</a>
1. Pull the SwiftPM repository:
```
git clone https://github.com/apple/swift-package-manager.git
```
2. Run your first build:
```
$> cd swift-package-manager
$> swift build
```
Make sure the build did not fail.  

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
Binaries (in the example above) are in `x86_64-apple-macosx/`.  
If you need to build the generated binaries, run `swift-build` in inside `.build/`:
```
./.build/x86_64-apple-macosx/debug/swift-build
```

## Commits / PRs
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

## Community and Support
If you want to connect with the Swift community you can:
* Use Swift Forums: [https://forums.swift.org/c/development/SwiftPM](https://forums.swift.org/c/development/SwiftPM)
* Contact the CODEOWNERS: https://github.com/apple/swift-package-manager/blob/main/CODEOWNERS
(mailing lists are usually the best place to go for help: [code-owners@swift.org](mailto:code-owners@swift.org), [conduct@swift.org](mailto:conduct@swift.org), [swift-infrastructure@swift.org](mailto:swift-infrastructure@swift.org)

## Additional resources
* `Swift.org` Contributing page
[https://swift.org/contributing/](https://swift.org/contributing/)
* License
[https://swift.org/LICENSE.txt](https://swift.org/LICENSE.txt)
* Code of Conduct
[https://swift.org/community/#code-of-conduct](https://swift.org/community/#code-of-conduct)

## Troubleshooting
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
* If during `swift build` you encounter this error:
```
/../swift-package-manager/Sources/PackageLoading/Target+PkgConfig.swift:84:36: error: type 'PkgConfigError' has no member 'prohibitedFlags'
            error = PkgConfigError.prohibitedFlags(filtered.unallowed.joined(separator: ", "))
                    ~~~~~~~~~~~~~~ ^~~~~~~~~~~~~~~
```
Make sure to update your TSC (Tools Support Core):
```
swift package update
```
Alternatively, if you are using Xcode, you can update to the latest version of all packages:  
**Xcode App** > *File* > *Swift Packages* > *Update to Latest Package Versions*
