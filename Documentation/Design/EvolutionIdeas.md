# Swift Package Manager Ideas

This is a list of some evolution ideas for the package manager. Once the details
of an idea are fleshed out and there is a full proposal, it can be scheduled for
the Swift Evolution process. It is important to note that not every idea on this
list is guaranteed to become an official feature, and it all depends on where
the design discussion leads us. Also, this is not meant to be an exhaustive
feature list, if you have an idea for a feature that you think will be
a valuable addition to the package manager, feel free to start a discussion
about it.

If you're interested in participating in a particular evolution idea, please
familiarize yourself with the existing discussion on that topic and start
participating in the discussion thread of that idea. If a thread doesn't exist
for that idea, please start one with a [draft
proposal](https://github.com/swiftlang/swift-evolution/blob/master/proposal-templates/0000-swiftpm-template.md)
that can be used as a starting point.

**Important Note**: This list is not in any particular order. I plan to keep
this post updated, but please let me know if you see something out-of-date.

## Mirror and Fork Support

You may want an easy way to mirror or fork specific packages in your package
graph. This could be useful if you want to make a private customization to
a package that you depend on, or even if you just want to override the origin
repository of your packages so that you can fetch from a private mirror and not
depend on the original repository always being there.

Thread: https://forums.swift.org/t/dependency-mirroring-and-forking/13902
Bug: [SR-679](https://bugs.swift.org/browse/SR-679)

## Build Settings

Some packages require specific language or linker flags that SwiftPM doesn’t
currently support, and some packages may desire other configurable properties as
well. We want to have a real, robust "build settings" model for adding these
kinds of properties, potentially including conditional settings and
fine-grained control over what parts of the package use which property values.

Thread: N/A
Bug: [SR-3948](https://bugs.swift.org/browse/SR-3948)

## Conditional Dependencies

Packages may want to use dependencies that they only use while testing the
package. Such dependencies shouldn't take part in dependency resolution process
when a package is being used as a dependency. This is also called test-only or
development dependencies in other package managers. It is sometimes also
required to declare platform-specific dependencies which should only be fetched
when a package is being built for a certain platform. This is currently possible
using `#if os` checks, but it leads to two problems: 1) it forces
a non-declarative syntax in the manifest file, and 2) it causes issues in
maintaining the `Package.resolved` file as the dependency is added or removed
depending on the platform.

Thread: N/A
Bug: [SR-883](https://bugs.swift.org/browse/SR-883)

## Resource Support

The Swift Package Manager needs a story for how packages should specify their
resources to include with products.

Thread: N/A
Bug: [SR-2866](https://bugs.swift.org/browse/SR-2866)

## Extensible Build Tools

Many users want to incorporate a variety of build-time tools into their
packages, whether to support a custom language or preprocessor, or to add their
own documentation generator or linter. SwiftPM could add extensibility to
support tools packages which could bring these steps to the build process. We
expect this behavior to greatly enhance our capacity for building complex
software packages.

One important thing for us to be careful about here is to make sure that all
parts of the build process still clearly declare their inputs and outputs to
SwiftPM, so that it can make sure that they behave correctly and perform well
for incremental and parallel builds.

Thread: https://forums.swift.org/t/package-manager-extensible-build-tools/10900
Bug: N/A

## User-defined Template Support

It would be nice if users can hook into the init command to add custom templates
that they frequently use.

Thread: N/A
Bug: [SR-7837](https://bugs.swift.org/browse/SR-7837)

## Documentation Generation Support

We can leverage SourceKit to extract documentation information from Swift
packages that can be further transformed into a developer consumable format like
a static HTML website.

Thread: N/A
Bug: N/A

## Tagging and Publishing Support

Today you publish new versions of your package by tagging manually with Git, and
you use Git directly to view your published tags. SwiftPM could help automate
this process, performing any validation, housekeeping, or auxiliary tasks that
might make sense as part of a streamlined and safe publication workflow.

Thread: N/A
Bug: N/A

## Install/Deploy Command

When you’re deploying the product of your package, whether to a server or your
local system, it could be helpful for SwiftPM to provide support for automating
that process. You may want to configure layout and library linkage aspects of
your products for your specific deployment environment, record version
information about what your products were built from, and otherwise leverage the
context that SwiftPM has about your packages for a seamless deployment
experience.

Thread: N/A
Bug: N/A

## Performance Testing Support

Currently, SwiftPM has no support for running performance tests. We need to
provide a way to specify performance tests for a package and to run them from
the SwiftPM command-line tools.

[Here](https://github.com/aciidb0mb3r/swift-evolution/blob/pref-proposal/proposals/xxxx-package-manager-performance-testing.md) is a very old draft proposal that I haven't gotten around to posting for discussion yet.

Thread: N/A
Bug: [SR-1354](https://bugs.swift.org/browse/SR-1354)

## Support for External Testing Frameworks

Currently, SwiftPM only supports writing tests with help of the XCTest testing
framework. The community should be able to use any testing framework of their
choice to test with SwiftPM. This feature will most likely depend on the proposed extensible
build tools feature described [here](https://forums.swift.org/t/package-manager-extensible-build-tools/10900).

Thread: N/A
Bug: N/A

## Package Index

SwiftPM plans to have a real index for Swift packages some day. In addition to
defining a namespace for package names and providing easier package discovery,
it could even support metrics for quality, such as automated test coverage
statistics, or ways to evaluate the trustworthiness of packages that you’re
considering using. This will be a large project.

Thread: N/A
Bug: N/A

## Multi-Package Repository Support

Currently the package manager requires that each package live at the root of
a Git repository. This means that you can't store multiple packages in the same
repository, or develop packages which locate each other in a filesystem-relative
manner without relying on Git. We need a proposal for how we would like to
support this.

Thread: N/A
Bug: [SR-3951](https://bugs.swift.org/browse/SR-3951)

## Cross-platform Sandboxing

Sandboxing is one way to help prevent `Package.swift` manifest evaluation and
builds from escaping out into your system, either accidentally or deliberately.
SwiftPM uses macOS's sandboxing technology already, but it would be great to
bring this safety to other platforms.

Thread: N/A
Bug: N/A

## Automatic Semantic Versioning

Automatically detecting what semantic version it looks like you should be
publishing your changes with could be very helpful for package authors. SwiftPM
could do this by analyzing the source code's API to see what has changed and
whether the API is backwards-compatible, at least at compile time.

Thread: N/A
Bug: N/A

## Machine-Editable Package.swift

We need an easy way to edit the Package.swift manifest from automated tools, for
cases where you don't want users to have to update the Swift code directly. We
think that it's possible to provide an API to allow this, probably using
[`SwiftSyntax`](https://github.com/swiftlang/swift-syntax).

Thread: N/A
Bug: N/A
