# Swift Package Manager Evolution Proposals

Last Modified: 2026-09-15

This is a list of Swift Evolution proposals that affect the Swift Package
Manager, ordered newest first. See the [swift-evolution repository](https://github.com/swiftlang/swift-evolution/tree/main/proposals)
for the authoritative list and current status.

For pre-proposal evolution ideas that have not yet been formally proposed, see
[EvolutionIdeas.md](EvolutionIdeas.md).

## SE-0549: Package Manager HTTP Proxy Configuration

Status: Active review (September 14...28, 2026)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0549-swiftpm-proxy-configuration.md

## SE-0547: SwiftPM Support for Compilation Caching

Status: Active Review (August 25...September 1, 2026)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0547-swiftpm-compilation-caching.md

## SE-0542: Package Manager Conditional Plugin

Status: Active Review (August 6 - August 21, 2026)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0542-package-manager-conditional-plugin.md

## SE-0534: Opt-in exact matching for version identifiers with build metadata

Status: Rejected

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0534-swiftpm-exact-literal-version-matching.md

## SE-0511: SwiftPM Add Target Plugin Command

Status: Implemented (Swift 6.4)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0511-swiftpm-add-target-plugin.md

## SE-0509: Software Bill of Materials (SBOM) Generation for Swift Package Manager

Status: Implemented (Swift 6.4)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0509-swift-sboms-via-swiftpm.md

## SE-0501: HTML Coverage Report

Status: Implemented (Swift Next)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0501-swiftpm-html-coverage-report.md

## SE-0500: Improving package creation with custom templates: SwiftPM Template Initialization

Status: Accepted

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0500-package-manager-templates.md

## SE-0482: Binary Static Library Dependencies

Status: Implemented (Swift 6.2)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md

## SE-0480: Warning Control Settings for SwiftPM

Status: Implemented (Swift 6.2)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md

## SE-0455: SwiftPM @testable build setting

Status: Accepted

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0455-swiftpm-testable-build-setting.md

## SE-0450: Package traits

Status: Implemented (Swift 6.1)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md

## SE-0435: Swift Language Version Per Target

Status: Implemented (Swift 6.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0435-swiftpm-per-target-swift-language-version-setting.md

## SE-0403: Package Manager Mixed Language Target Support

Status: Returned for Revision

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0403-swiftpm-mixed-language-targets.md

## SE-0394: Package Manager Support for Custom Macros

Status: Implemented (Swift 5.9)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0394-swiftpm-expression-macros.md

## SE-0391: Package Registry Publish

Status: Implemented (Swift 5.9)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md

## SE-0378: Package Registry Authentication

Status: Implemented (Swift 5.8)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0378-package-registry-auth.md

## SE-0332: Package Manager Command Plugins

Status: Implemented (Swift 5.6)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0332-swiftpm-command-plugins.md

## SE-0325: Additional Package Plugin APIs

Status: Implemented (Swift 5.6)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0325-swiftpm-additional-plugin-apis.md

## SE-0321: Package Registry Service - Publish Endpoint

Status: Implemented (Swift 5.6)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0321-package-registry-publish.md

## SE-0305: Package Manager Binary Target Improvements

Status: Implemented (Swift 5.6)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md

## SE-0303: Package Manager Extensible Build Tools

Status: Implemented (Swift 5.6)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md

## SE-0294: Declaring executable targets in Package Manifests

Status: Implemented (Swift 5.4)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0294-package-executable-targets.md

## SE-0292: Package Registry Service

Status: Implemented (Swift 5.7)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md

## SE-0291: Package Collections

Status: Implemented (Swift 5.5)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0291-package-collections.md

## SE-0278: Package Manager Localized Resources

Status: Implemented (Swift 5.3)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0278-package-manager-localized-resources.md

## SE-0273: Package Manager Conditional Target Dependencies

Status: Partially implemented (Swift 5.3 supports platform conditionals, but not configuration conditionals)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0273-swiftpm-conditional-target-dependencies.md

## SE-0272: Package Manager Binary Dependencies

Status: Implemented (Swift 5.3)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0272-swiftpm-binary-dependencies.md

## SE-0271: Package Manager Resources

Status: Implemented (Swift 5.3)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0271-package-manager-resources.md

## SE-0238: Package Manager Target Specific Build Settings

Status: Implemented (Swift 5.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0238-package-manager-build-settings.md

## SE-0236: Package Manager Platform Deployment Settings

Status: Implemented (Swift 5.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0236-package-manager-platform-deployment-settings.md

## SE-0226: Package Manager Target Based Dependency Resolution

Status: Partially implemented (Swift 5.2): Implemented the manifest API to disregard targets not concerned by any dependency products, which avoids building dependency test targets.

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0226-package-manager-target-based-dep-resolution.md

## SE-0219: Package Manager Dependency Mirroring

Status: Implemented (Swift 5.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0219-package-manager-dependency-mirroring.md

## SE-0209: Package Manager Swift Language Version API Update

Status: Implemented (Swift 4.2)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0209-package-manager-swift-lang-version-update.md

## SE-0208: Package Manager System Library Targets

Status: Implemented (Swift 4.2)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0208-package-manager-system-library-targets.md

## SE-0201: Package Manager Local Dependencies

Status: Implemented (Swift 4.2)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0201-package-manager-local-dependencies.md

## SE-0181: Package Manager C/C++ Language Standard Support

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0181-package-manager-cpp-language-version.md

## SE-0179: Swift `run` Command

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0179-swift-run-command.md

## SE-0175: Package Manager Revised Dependency Resolution

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0175-package-manager-revised-dependency-resolution.md

## SE-0162: Package Manager Custom Target Layouts

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0162-package-manager-custom-target-layouts.md

## SE-0158: Package Manager Manifest API Redesign

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0158-package-manager-manifest-api-redesign.md

## SE-0152: Package Manager Tools Version

Status: Implemented (Swift 3.1)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0152-package-manager-tools-version.md

## SE-0151: Package Manager Swift Language Compatibility Version

Status: Implemented (Swift 3.1)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0151-package-manager-swift-language-compatibility-version.md

## SE-0150: Package Manager Support for branches

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0150-package-manager-branch-support.md

## SE-0149: Package Manager Support for Top of Tree development

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0149-package-manager-top-of-tree.md

## SE-0146: Package Manager Product Definitions

Status: Implemented (Swift 4.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0146-package-manager-product-definitions.md

## SE-0145: Package Manager Version Pinning

Status: Implemented (Swift 3.1)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0145-package-manager-version-pinning.md

## SE-0135: Package Manager Support for Differentiating Packages by Swift version

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0135-package-manager-support-for-differentiating-packages-by-swift-version.md

## SE-0129: Package Manager Test Naming Conventions

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0129-package-manager-test-naming-conventions.md

## SE-0085: Package Manager Command Names

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0085-package-manager-command-name.md

## SE-0082: Package Manager Editable Packages

Status: Implemented (Swift 3.1)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0082-swiftpm-package-edit.md

## SE-0063: SwiftPM System Module Search Paths

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0063-swiftpm-system-module-search-paths.md

## SE-0038: Package Manager C Language Target Support

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0038-swiftpm-c-language-targets.md

## SE-0019: Swift Testing

Status: Implemented (Swift 3.0)

https://github.com/swiftlang/swift-evolution/blob/main/proposals/0019-package-manager-testing.md

