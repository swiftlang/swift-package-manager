# Swift-based Manifest Format

> **PLEASE NOTE** This document represents the initial proposal for Swift Package Manager, and is provided for historical purposes only. It does not represent the current state or future direction of the project. For current documentation, see the main Swift Package Manager [documentation](../README.md).

## Purpose

We need to have some facility for describing additional package metadata, outside of the content in the sources files. This document describes a proposal for using a Swift-based format for this manifest data.


## Motivation

The package manager strives to support a "convention based" project structure which is derived from the project files and source code. This approach allows users to primarily focus on authoring their actual software and expect that the tools will assemble it into a product by following sensible defaults.

However, packages also have information which cannot naturally be inferred from the project structure. To that end, we need to support some kind of manifest which contains the additional project information.

At a high level, the primary purpose of this manifest is to:

* Complement the convention based system.

  The manifest complements the convention based system, by being the one definitive place to add any project metadata that would otherwise require the project to use a custom configuration. The goal is that 80%+ of projects should be able to use only a manifest and the convention based layout.

  By allowing the manifest to extend and override a few key, carefully picked details of the convention based system, then we allow many more projects to use the system without needing to define complex conventions.

* Provide package information in a standard format.

  There are certain pieces of information which are important enough and common enough that we would like all projects to include, or any projects which do include them to do so in a standardized manner. For example, the license declaration of a project should follow a very standard definition.

* Serve as an indicator of a package manager project.

  Although it is simple, having the manifest exist with a known name at the root of a package serves as an indicator to developers and tools of the type of project and how they are expected to interact with it.

* Provide support for programmatic analysis and editing of project structure.

  The manifest should be machine readable and writeable format. We envision a variety of tools that may want to inspect the contents of packages (for example, to build information for an index) or make automatic edits to the project structure. For example, when introducing a new library dependency via adding an import statement, we would like it if a tool could, after a user prompt, automatically update the manifest to specify the new dependency.


## Proposal

We propose to use the Swift language itself to write the manifest. An example of a proposed manifest for a small cross-platform project with several libraries might look something like this:

```swift
// This imports the API for declaring packages.
import PackageDescription

// This declares the package.
let package = Package(
    // The name of the package (defaults to source root directory name).
    name: "Foo",

    // The list of targets in the package.
    targets: [
        // Declares the main application.
        Target(
            name: "Foo",
            // Declare the type of application.
            type: .Tool,
            // Declare that this target is a published product of the package
            // (as opposed to an internal library or tool).
            published: true),

        // Add information on a support library "CoreFoo" (as found by the
        // convention based system in CoreFoo/**/*.swift).
        Target(
            name: "CoreFoo",
            depends: [
                // The library always depends on the "Utils" target.
                "Utils",

                // This library depends on "AccessibilityUtils" on Linux.
                .Conditional(name: "AccessibilityUtils", platforms: [.Linux])
            ]),

        // NOTE: There is a "Utils" target inferred by the convention based
        // system, but we don't need to modify it at all because the defaults
        // were fine.

        // Declare that the "AccessibilityUtils" target is Linux-specific.
        Target(name: "AccessibilityUtils", platforms: [.Linux])
	])
```

*NOTE: this example is for expository purposes, the exact APIs are subject to change.*

By writing the manifest in Swift, we ensure a consistent development experience across not only authoring their source code, but also their project metadata. This means developers will have a consistent environment with all of the development conveniences they expect: syntax coloring, code completion, API documentation, and formatting tools. This also ensures that new developers to Swift can focus on learning the language and its tools, not another custom package description format.

The package description itself is a declarative definition of information which *augments* the convention based system. The actual package definition that will be used for a project consists of the convention based package definition with the package description applied to override or customize default behaviors. For example, this target description:

```swift
Target(name: "AccessibilityUtils", platforms: [.Linux])
```

*does not* add a new target. Rather, it modifies the existing target `AccessibilityUtils` to specify what platforms it is available for.


## Customization

We intend for the declaration package definition to cover 80%+ of the use cases for modifying the convention based system. Nevertheless, there are some kinds of legitimate project structures which are difficult or cumbersome to encode in a purely declarative model. For example, designing a general purpose mechanism to cover all the ways in which users may wish to divide their source code is difficult.

Instead, we allow users to interact with the `Package` object using its native Swift APIs. The package declaration in a file may be followed by additional code which configures the package using a natural, imperative, Swifty API. For example, this is an example of a project which uses a custom convention for selecting which files build with unchecked optimizations:

```swift
import PackageDescription

let package = Package(name: "FTW")

// MARK: Custom Configuration

// Build all *_unchecked.swift files using "-Ounchecked" for Release mode.
for target in package.targets {
    for source in target.sources {
        if source.path.hasSuffix("_unchecked.swift") {
            source.customFlags += [.Conditional("-Ounchecked", mode: .Release)
        }
    }
}
```

It is important to note that even when using this feature, package manifest still **must be** declarative. That is, the only output of a manifest is a complete description of the package, which is then operated on by the package manager and build tools. For example, a manifest **must not** attempt to do anything to directly interact with the build output. All such interactions must go through a documented, public API vended by the package manager libraries and surfaced via the package manager tools.


## Editor Support

The package definition format being written in Swift is problematic for tools that wish to perform automatic updates to the file (for example, in response to a user action, or to bind to a user interface), or for situations where dealing with executable code is problematic.

To that end, the declarative package specification portion of the file is "Swift" in the same sense that "JSON is Javascript". The syntax itself is valid, executable, Swift but the tools that process it will only accept a restricted, declarative, subset of Swift which can be statically evaluated, and which can be unambiguously, automatically rewritten by editing tools. We do not intend to define a "standard" syntax for "Swift Object Notation", but we intend to accept a natural restriction of the language which only accepts literal expressions. We do intend to allow the restricted subset to take full advantage of Swift's rich type inference and literal convertible design to allow for a succinct, readable, and yet expressive syntax.

The customization section above will *not* be written in this syntax. Instead, the customization section will be clearly demarcated in the file. The leading file section up to the first '// MARK:' will be processed as part of the restricted declarative specification. All subsequent code **must be** honored by tools which only need to consume the output of the specification, and **should be** displayed by tools which present an editor view of the manifest, but **should not** be automatically modified. The semantics of the APIs will be specifically designed to accommodate the expected use case of editor support for the primary data with custom project-specific logic for special cases.

All tools which process the package manifest **must** validate that the declaration portion of the specification fits into the restricted language subset, to ensure a consistent user experience.


## Implementation

We need to have efficient, programmatic access to the data from the manifest for use in the package manager and associated tools. Additionally, we may wish to use this data in contexts where the executable-code nature of the manifest format is problematic. On the other hand, we also want the file format to properly match the Swift language.

To satisfy these two goals, we intend to extract the package metadata from the manifest file by using the Swift parser **and** type checker to parse the leading package declaration portion of the file (not including any customizations made subsequent to the package definition). Once type checked, we will then validate the AST produced for the package description using custom logic which validates that the AST can (a) be parsed into validate model objects without needing to execute code, and (b) is written following the strict format such that it can be automatically modified by editing tools.

Tools that do not need to be as strict with the manifest format will be able to load it by using Swift directly to execute the file and then interact with the package definition API to extract the constructed model.


## Discussion

We decided to use a Swift-based format for the manifest because we believe it gives developers the best experience for working with and describing their project. The primary alternative we considered was to use a declarative format encoded in a common data format like JSON. Although that would simplify implementation of the tooling around the manifest, it has the downside that users must then learn this additional language, and the development of high quality tools for that (documentation, syntax coloring, parsing diagnostics) isn't aligned with our goal of building great tools for Swift. In contrast, using the Swift language means that we can leverage all of the work on Swift to make those tools great.

The decision to use a restricted subset of Swift for the primary package definition is because we believe it is important that common tasks which require the manifest be able to be automated or surfaced via a user interface.

We decided to allow additional customization of the package via imperative code because we do not anticipate that the convention based system will be able to cover all possible uses cases. When users need to accommodate special cases, we want them to be able to do so using the most natural and expression medium, by writing Swift code. By explicitly designing in a customization system, we believe we will be able to deliver a higher quality set of core conventions -- there is an escape hatch for the special cases that allows us to focus on only delivering conventions (and core APIs) for the things that truly merit it.

A common problem with systems that permit arbitrary customization (especially via a programmatic interface) is that they become difficult to maintain and evolve, since it is hard to predict how developers have taken advantage of the interface. We deal with this by requiring that the manifest only interact with the package and tools through a strict, well defined API. That is, even though we allow developers to write arbitrary code to construct their package, we do not allow arbitrary interactions with the build process. Viewed a different way, the output of *all* manifests **must be** able to be treated as a single declaration specification -- even if part of that specification was programmatically generated.
