Note: This is in reverse chronological order, so newer entries are added to the top.

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
