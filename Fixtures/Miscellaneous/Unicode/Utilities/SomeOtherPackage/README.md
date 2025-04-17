# SomeOtherPackage

This nested utility package refers back to the main repository as a local dependency.

If client tools accidentally pick this package up as part of the main repository package, dependency resolution could become circular or otherwise problematic.

(Prior to direct Xcode support for packages, this repository structure was a common way of hiding executable utilities from `generate-xcodeproj`, so that the main package would still be viable for iOS.)
