#  Diagnostics

This is a brief overview of the internal workings of SwiftPM diagnostics, from a contributor's perspective.

In addition to describing the current machinery for collecting and reporting diagnostics, this document provides some best-practices that should be followed for new code.  There is some cleanup to be done of various parts of the code base that use older idioms, so when in doubt, the recommendations in this document should have priority.

## Overview

### `DiagnosticsEngine`

Diagnostics are collected using a `DiagnosticEngine`.  In addition to building up a list of emitted diagnostics, a diagnostics engine can have one or more handler closures that are invoked for each diagnostic that is emitted.  Emitting diagnostics to an engine is thread-safe.

A diagnostic engine can also have a default location, which will be assigned to any diagnostics that are emitted to the engine and that don't have their own location.  A typical usage pattern is to create a diagnostics engine for use in a suboperation pertaining to a particular file, repository, etc, and then to pass that diagnostics engine as a parameter to functions that implement the subsystem.  As diagnostics are emitted to the engine, they will be assigned the default location.

### `Diagnostic`

A `Diagnostic` represents a single occurrence of a warning, error, notice, or other item of interest to end users.  A `Diagnostic` consists of a `Diagnostic.Message` and a `DiagnosticLocation`.  A message, in turn, has a `Diagnostic.Behavior` and a `DiagnosticData`.  The location provides information about the conceptual location of the diagnostic, the behavior indicates the severity of the problem, and the "diagnostic data" contains any domain-specific information needed for the diagnostic.  Both the location and the diagnostic data, as well as the diagnostic itself, are `CustomStringConvertible`.

### `DiagnosticData`

Individual subsystems that need to record custom properties can specialize the `DiagnosticData` protocol.  Either a struct or an enum can be used, and examples of both can be found throughout the codebase.  These types would then implement the `description` computed-property to construct an appropriate description from the custom properties.

### `DiagnosticLocation`

`DiagnosticLocation` is a protocol that represents the conceptual location of a diagnostic.  It could refer to a concrete location such as a file at a particular path, but could also refer to an abstract location such as a repository represented by a URL.  The CLI emits these as strings, and clients of _libSwiftPM_ (such as IDEs) typically bridge the known specializations of `DiagnosticLocation` to their internal types.

### Thrown `Swift.Error`s

`DiagnosticsEngine` provides a `wrap()` method that takes a closure and emits any Swift Error thrown by the closure as a `Diagnostic` of severity `error`.  This is a fairly commonly used idiom.

## Common Usage Patterns

### String diagnostics

In practice, most diagnostics are simple and don't need the full customizability of `DiagnosticData`.  The specialization
`StringDiagnostic` is commonly used for cases in which no custom properties are required.

This commonly used pattern involves defining an extension on `Diagnostic.Message` that implements static constructors for the specific messages that can be emitted by the subsystem, e.g.
```
extension Diagnostic.Message {
    static func productUsesUnsafeFlags(product: String, target: String) -> Diagnostic.Message {
        .error("the target '\(target)' in product '\(product)' contains unsafe build flags")
    }
    static func unusedDependency(_ name: String) -> Diagnostic.Message {
        .warning("dependency '\(name)' is not used by any target")
    }
}
```

This uses the convenience initializers `error`, `warning`, `note`, and `remark`, which end up returning messages that wrap instances of `StringDiagnostic` which are then wrapped in instances of `Diagnostic.Message`.

This pattern keeps the specific formulation of messages independent from the conceptual message and its parameters in its source code.

### Specializing `DiagnosticData`

Another common pattern is to define a struct that conforms to `DiagnosticData`, and to emit it to the diagnostics engine.  A variation is to make the struct conform to `DiagnosticData` as well as to `Swift.Error`, so that it can be thrown and caught by `DiagnosticEngine.wrap()`. 

## Future Improvements

#### Get rid of `DiagnosticDataConvertible`

This seems to be a vestige of an earlier usage pattern.  There is a comment in the code that this type should be eliminated.  These seems to be one remaining client of it.

#### First-class support for recovery suggestions

Some diagnostics contain recovery suggestions as part of the message text.  This should really be separated out, and in the future should in fact become fix-its that a user could choose to mechanically apply.

#### Support for nested `DiagnosticsEngine`s

Sometimes the context for a diagnostic is not as simple as just its location — for example, a diagnostic emitted by an operation not easily associated with a single location should be shown as being associated with that operation, which might itself be the suboperation of yet another operation.

#### Support for underlying errors

Some specializations of `Error` have ad hoc support for recording underlying errors, but this seems like something that might be useful as a "for more details, see this error" facility for `Diagnostic`.  A particularly common use of this would be when a file system error (missing file, permission errors, broken symlink, I/O error) causes a higher-level error (couldn't load manifest, etc).

#### Support for `Error` with locations

Although `Error`s are caught, they cannot provide their own locations, and this is sometimes a problem.  It may be worth declaring a protocol such as `DiagnosticLocationProviding` that could return a `DiagnosticLocation` for the engine to use when it emits the diagnostic. 

#### Bridge to ActivityLogs?

Should we bridge to ActivityLogs?  This would let us provide better contextual information for diagnostics, and informational output even when there are no diagnostics.  This would be one way of addressing the lack of nestable context described in the previous bullet.
