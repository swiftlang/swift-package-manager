# Resources

## Table of Contents

* [Overview](README.md)
* [Usage](Usage.md)
* [PackageDescription API](PackageDescription.md)
* [**Resources**](Resources.md)
  * [Support](#support)
  * [Reporting a SwiftPM Bug](#reporting-a-swiftpm-bug)

---

## Support

User-to-user support for Swift Package Manager is available on
[swift-forums](https://forums.swift.org/c/development/SwiftPM).

---

## Reporting a SwiftPM Bug

Use the [Swift bug tracker](http://bugs.swift.org) to report bugs with Swift
Package Manager. Sign up if you haven't already and click the "Create" button to
start filing an issue.

Fill the following fields:

* `Summary`: A one line summary of the problem you're facing
* `Description`: The complete description of the problem. Be specific and clearly mention the steps to reproduce the bug
* `Environment`: The Operating System, Xcode version (`$ xcodebuild -version`), Toolchain, and `swift build` version (`$ swift build --version`)
* `Component/s`: Package Manager
* `Attachment`: Relevant files like logs, project files, etc.

Please include a minimal example package which can reproduce the issue. The
sample package can be attached with the report or you can include the URL of the
package hosted on places like GitHub.
Also, include the verbose logs by adding `--verbose` or `-v` after a subcommand.
For example:

    $ swift build --verbose
    $ swift package -v update

If the bug is with a generated Xcode project, include how the project was
generated and the Xcode build log.
