swift-tools-support-core
=========================

Contains common infrastructural code for both [SwiftPM](https://github.com/apple/swift-package-manager)
and [llbuild](https://github.com/apple/swift-llbuild).

Development
-------------

All changes to source files in this repository need to be done in the repository of the Swift Package Manager repository ([link](https://github.com/apple/swift-package-manager)) and then copied here using the Script in `Utilities/import` which takes the local path to the SwiftPM directory as input (or uses `../swiftpm` as default).
All targets with a TSC prefix in [SwiftPM](https://github.com/apple/swift-package-manager) are part of the swift-tools-support-core and will be imported by the import script. The plan is to eventually move ownership to this repository.

License
-------

Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors.
Licensed under Apache License v2.0 with Runtime Library Exception.

See http://swift.org/LICENSE.txt for license information.
