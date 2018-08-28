Note: This is in reverse chronological order, so newer entries are added to the top.


Swift 4.2
---------

* [SE-209](https://github.com/apple/swift-evolution/blob/master/proposals/0209-package-manager-swift-lang-version-update.md)

  The `swiftLanguageVersions` property no longer takes its Swift language versions via
  a freeform Integer array; instead it should be passed as a new `SwiftVersion` enum
  array.

* [SE-208](https://github.com/apple/swift-evolution/blob/master/proposals/0208-package-manager-system-library-targets.md)

  The `Package` manifest now accepts a new type of target, `systemLibrary`. This
  deprecates "system-module packages" which are now to be included in the packages
  that require system-installed dependencies.

* [SE-201](https://github.com/apple/swift-evolution/blob/master/proposals/0201-package-manager-local-dependencies.md)

  Packages can now specify a dependency as `package(path: String)` to point to a
  path on the local filesystem which hosts a package. This will enable interconnected
  projects to be edited in parallel.

* [#1604](https://github.com/apple/swift-package-manager/pull/1604)

  The `generate-xcodeproj` has a new `--watch` option to automatically regenerate the Xcode project
  if changes are detected. This uses the
  [`watchman`](https://facebook.github.io/watchman/docs/install.html) tool to detect filesystem
  changes.

* Scheme generation has been improved:
  * One scheme containing all regular and test targets of the root package.
  * One scheme per executable target containing the test targets whose dependencies
    intersect with the dependencies of the exectuable target.

* [SR-6978](https://bugs.swift.org/browse/SR-6978)
  Packages which mix versions of the form `vX.X.X` with `Y.Y.Y` will now be parsed and
  ordered numerically.

* [#1489](https://github.com/apple/swift-package-manager/pull/1489)
  A simpler progress bar is now generated for "dumb" terminals.

Swift 4.1
---------

* [#1485](https://github.com/apple/swift-package-manager/pull/1485)
  Support has been added to automatically generate the `LinuxMain` files for testing on
  Linux systems. On a macOS system, run `swift test --generate-linuxmain`.

* [SR-5918](https://bugs.swift.org/browse/SR-5918)
  `Package` manifests that include multiple products with the same name will now throw an
  error.


Swift 4.0
---------

* The generated Xcode project creates a dummy target which provides
  autocompletion for the manifest files. The name of the dummy target is in
  format: `<PackageName>PackageDescription`.

* `--specifier` option for `swift test` is now deprecated.
  Use `--filter` instead which supports regex.

Swift 3.0
---------

* [SE-0135](https://github.com/apple/swift-evolution/blob/master/proposals/0135-package-manager-support-for-differentiating-packages-by-swift-version.md)

  The package manager now supports writing Swift 3.0 specific tags and
  manifests, in order to support future evolution of the formats used in both
  cases while still allowing the Swift 3.0 package manager to continue to
  function.

* [SE-0129](https://github.com/apple/swift-evolution/blob/master/proposals/0129-package-manager-test-naming-conventions.md)

  Test modules now *must* be named with a `Tests` suffix (e.g.,
  `Foo/Tests/BarTests/BarTests.swift`). This name also defines the name of the
  Swift module, replacing the old `BarTestSuite` module name.

* It is no longer necessary to run `swift build` before running `swift test` (it
  will always regenerates the build manifest when necessary). In addition, it
  now accepts (and requires) the same `-Xcc`, etc. options as are used with
  `swift build`.

* The `Package` initializer now requires the `name:` parameter.
