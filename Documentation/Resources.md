# Resources

## Table of Contents

* [Overview](README.md)
* [Usage](Usage.md)
* [PackageDescription API Version 3](PackageDescriptionV3.md)
* [PackageDescription API Version 4](PackageDescriptionV4.md)
* [**Resources**](Resources.md)
  * [Support](#support)
  * [Reporting a good SwiftPM Bug](#reporting-a-good-swiftpm-bug)
  * [Community Proposal](#community-proposal)

---

## Support

User-to-user support for Swift Package Manager is available on [swift-users mailing list](mailto:swift-users@swift.org).

---

## Reporting a good SwiftPM Bug

Use the [Swift bug tracker](http://bugs.swift.org) to report bugs with Swift Package Manager. Sign up if you haven't already and click the "Create" button to start filing an issue.  

Fill the following fields:
* `Summary`: One line summary of the problem you're facing  
* `Description`: The complete description of the problem. Be specific and clearly mention the steps to reproduce the bug  
* `Environment`: The Operating System, Xcode version (`$ xcodebuild -version`), Toolchain and `swift build` version (`$ swift build --version`)  
* `Component/s`: Package Manager  
* `Attachment`: Attach relevant files like logs, project

Please include a minimal example package which can reproduce the issue. The sample package can be attached with the report or you can include URL of the package hosted on places like GitHub.  
Also, include the verbose build log. If you're using `swift build` to compile the project you can obtain the verbose log using:

    $ swift build -v

If the bug is with a generated Xcode project, include how the project was generated and the Xcode build log.

---

## Project History

To learn the original intentions for Swift Package Manager, read the [Community Proposal](PackageManagerCommunityProposal.md).
