#  README

The Triple.swift and Triple+Platform.swift files in this directory have been
vendored from SwiftDriver. The purpose of this approach is to avoid
introducing a dependency on Driver in the "data model" section of SwiftPM,
which could currently lead to complications with the Xcode integration.

In the long term, our goal is to consolidate this code into a shared
implementation that can be utilized by both SwiftPM and SwiftDriver through a
package. However, until we reach that point, it is important to keep the files
in this directory up to date by incorporating any relevant additions from the
original copies.
