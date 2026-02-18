# Module Map Syntax Reference

A reference of module map directives, attributes, and syntax for defining C and C++ module interfaces.

## Overview

Module maps use a domain-specific language to describe how C, Objective-C, and C++ headers are organized into modules.
This reference documents the syntax and semantics of module map declarations.

For instructions on creating module maps, see <doc:ModuleMaps>.
For troubleshooting and testing module maps, see <doc:DebuggingModuleMaps>.

The [Clang Modules documentation](https://clang.llvm.org/docs/Modules.html) is the official specification for module maps.
The content below summarizes that reference for common Swift use cases.

## Module declarations

A module declaration defines a named module and specifies its contents.

### Basic syntax

```
module ModuleName {
    declarations
}
```

The module name must be a valid identifier.
It can contain letters, numbers, and underscores, but can't start with a number.
The module name must match the product or target name in Swift Package Manager.

### Framework modules

<!-- REVIEWER QUESTION - Is this section relevant outside of Apple? -->

Framework modules use a specialized syntax for macOS and iOS frameworks:

```
framework module FrameworkName {
    umbrella header "FrameworkName.h"
    export *
    module * { export * }
}
```

The `framework` keyword indicates the module represents a framework bundle.
The `module * { export * }` pattern automatically creates and exports submodules for all headers.

### Explicit submodules

Submodules divide a module into smaller units:

```
module ParentModule {
    explicit module SubmoduleA {
        header "SubA.h"
        export *
    }

    explicit module SubmoduleB {
        header "SubB.h"
        export *
    }
}
```

The `explicit` keyword requires clients to explicitly import the submodule.
Code imports explicit submodules with `import ParentModule.SubmoduleA`.

Without the `explicit` keyword, the submodule is imported automatically when the parent module is imported.

### Header declarations

Header declarations specify which header files belong to a module.

#### header

Includes a header file in the module:

```
header "HeaderName.h"
```

The path is relative to the module map file's location.
The compiler parses the header and makes its declarations available when the module is imported.

<!-- REVIEWER QUESTION - Examples all seem to line up with a single header import, but it looks like you *could* list more than one, assuming there weren't overlaps or such. What are the actual constraints on importing multiple different headers in your library exposes more than one? -->

#### umbrella header

Includes a header that itself includes all other public headers:

```
umbrella header "ModuleName.h"
```

Umbrella headers provide a single entry point for all module functionality.
The header typically includes all other public headers with `#include` directives.

#### private header

Includes a header that's only visible within the module implementation:

```
private header "InternalAPI.h"
```

Private headers aren't visible to clients that import the module.
Use private headers for implementation details that other files within the module need to access.

#### textual header

Includes a header that's textually included rather than compiled as part of the module:

```
textual header "Macros.h"
```

Textual headers are typically used for macro-only headers or headers that can't be parsed in isolation.
The compiler includes the header's contents directly into each translation unit rather than precompiling it as part of the module.

#### exclude header

Explicitly excludes a header from an umbrella:

```
umbrella header "Module.h"
exclude header "Internal.h"
```

When using an umbrella header that includes files you don't want in the module, use `exclude header` to omit specific headers.

#### umbrella directory

Includes all headers in a directory:

```
umbrella "include"
```

The compiler includes all headers found in the specified directory and its subdirectories.
This is less common than umbrella headers because it provides less control over which headers are public.

### Export declarations

Export declarations control which modules are re-exported to clients.

#### export *

Re-exports all imported modules:

```
export *
```

When a client imports your module, they also see declarations from modules your module imports.
This is the most common export pattern for C libraries.

#### Selective exports

Re-exports specific modules:

```
module MyModule {
    header "MyModule.h"
    export Foundation
    export Darwin
}
```

Only the specified modules are visible to clients.
Modules imported but not exported remain private implementation details.

### Link declarations

Link declarations specify libraries the linker should include.

#### Basic syntax

```
link "libraryname"
```

Specify the library name without the `lib` prefix or file extension.
For example, use `link "z"` for `libz.a` or `libz.dylib`.

The build system passes this information to the linker automatically.

#### Framework links

<!-- REVIEWER QUESTION - Is this section relevant outside of Apple? -->

For macOS and iOS frameworks:

```
link framework "FrameworkName"
```

This tells the linker to link against the specified framework.

### Requirements

Requirements specify conditions that must be met for the module to be available.

#### Language requirements

- term cplusplus: Requires C++ language support
- term cplusplus11: Requires C++11 or later
- term cplusplus14: Requires C++14 or later
- term cplusplus17: Requires C++17 or later
- term cplusplus20: Requires C++20 or later
- term objc: Requires Objective-C language support
- term opencl: Requires OpenCL support

Example:

```
module CppLibrary {
    header "CppLibrary.h"
    requires cplusplus11
    export *
}
```

The compiler rejects the module if the build doesn't satisfy the requirements.

#### Feature requirements

- term blocks: Requires blocks (closures) support
- term gnuinlineasm: Requires GNU inline assembly support

Use the negation operator to exclude features:

```
requires !gnuinlineasm
```

#### Combining requirements

Combine multiple requirements with commas:

```
requires cplusplus, !blocks
```

All requirements must be satisfied for the module to be available.

### Module attributes

Attributes modify module behavior and semantics.

#### [system]

<!-- REVIEWER QUESTION - Is this section relevant outside of Apple? -->

Marks a module as a system module:

```
module SystemLibrary [system] {
    header "system.h"
    export *
}
```

System modules receive special treatment:

- Compiler warnings in system headers are suppressed
- Swift imports certain Objective-C types differently (`NSUInteger` becomes `Int` instead of `UInt`)
- The attribute ensures consistent behavior between local builds and client builds

Use `[system]` for SDK-provided libraries and system headers.

#### [extern_c]

Indicates C linkage for C++ code:

```
module [extern_c] CLibrary {
    header "clib.h"
    export *
}
```

This is useful when wrapping C libraries in C++ contexts.

#### [no_undeclared_includes]

Prevents implicit inclusion of headers:

```
module StrictModule [no_undeclared_includes] {
    header "StrictModule.h"
    export *
}
```

Clients must explicitly import all modules they use.
This makes dependencies explicit and prevents accidental reliance on transitive includes.

### Configuration macros

Configuration macros allow different module variants based on preprocessor definitions.

#### config_macros

Declares macros that affect the module's interface:

```
module ConfigurableModule {
    header "ConfigurableModule.h"
    config_macros exhaustive DEBUG_MODE, FEATURE_X
    export *
}
```

The `exhaustive` keyword lists all macros that affect the module's API.
The compiler creates separate module variants for different macro combinations.

Without configuration macros declared, the compiler assumes the module's interface is independent of preprocessor state.

### Conflict declarations

Conflict declarations specify incompatible modules.

#### conflict

Declares that a module conflicts with another:

```
module NewModule {
    header "NewModule.h"
    conflict OldModule, "Use NewModule instead"
    export *
}
```

The compiler produces an error if both modules are imported in the same translation unit.
The message explains why the modules conflict, and what to do instead.

### Extern modules

Extern modules reference module maps in other files.

#### extern module

References a module defined in another module map:

```
extern module ExternalModule "path/to/other.modulemap"
```

This allows organizing large module hierarchies across multiple files.
The path is relative to the current module map file.

### Use declarations

Use declarations specify dependencies between modules.

#### use

Declares that a module depends on another:

```
module DependentModule {
    header "DependentModule.h"
    use Foundation
    export *
}
```

This is informational and helps document module dependencies.
Most module maps don't need explicit `use` declarations.

## Complete syntax example

A comprehensive module map demonstrating multiple features:

```
module CompleteExample [system] {
    // Main module
    umbrella header "CompleteExample.h"
    export *

    // Configuration
    config_macros exhaustive DEBUG, LOGGING_ENABLED

    // Linking
    link "example"

    // Requirements
    requires !gnuinlineasm

    // Explicit submodule
    explicit module Utilities {
        header "Utilities.h"
        export *
    }

    // Private implementation submodule
    explicit module Private {
        private header "CompleteExample_Private.h"
        export *
    }

    // C++ submodule
    explicit module CPP {
        header "CompleteExample_CPP.hpp"
        requires cplusplus11
        export *
    }
}

// Backward compatibility module
module CompleteExampleOld {
    header "CompleteExample_Old.h"
    conflict CompleteExample, "Use CompleteExample instead of CompleteExampleOld"
    export *
}
```

## Module map file naming

Module map files must follow specific naming conventions:

- term module.modulemap: Standard public module map
- term module.private.modulemap: Private module map for implementation details

Swift Package Manager looks for `module.modulemap` by default.

### System library wrapper

```
module SystemLib [system] {
    header "shim.h"
    link "systemlib"
    export *
}
```

The shim header includes the actual system header, allowing the compiler to find it through search paths.

### C++ library

```
module CppLib {
    header "CppLib.hpp"
    requires cplusplus11
    export *
}
```

The `requires cplusplus11` directive ensures the module is only available in C++11 mode or later.

### Framework with submodules

```
framework module MyFramework {
    umbrella header "MyFramework.h"
    export *
    module * { export * }

    explicit module Private {
        private header "MyFramework_Private.h"
        export *
    }
}
```

Public headers are automatically modularized, while private headers require explicit import.

### Multiple libraries

```
module CompositeLib {
    module Core {
        header "Core.h"
        link "core"
        export *
    }

    module Utils {
        header "Utils.h"
        link "utils"
        export *
    }
}
```

Each submodule can link to its own library.

## Diagnostic directives

Module maps don't support preprocessor directives like `#if` or `#ifdef`.
All content in a module map is always active.

To handle platform-specific headers, use separate module maps for each platform or use requirements:

```
module CrossPlatform {
    // Common headers
    header "Common.h"

    // Platform-specific via requirements
    module Darwin {
        requires objc
        header "Darwin.h"
        export *
    }

    export *
}
```

## Module map parsing

The compiler parses module maps with these characteristics:

- Comments use C++ style (`//`) or C style (`/* */`).
- Identifiers follow C naming rules (letters, digits, underscores).
- String literals use double quotes.
- Paths in string literals are relative to the module map file.
- Whitespace is insignificant outside string literals.
- Module map files must be valid UTF-8.

## Limitations and constraints

Module maps have several limitations:

- Module names can't contain periods (use submodules instead).
- Header paths must be relative to the module map file.
- Circular dependencies between modules aren't supported.
- Conditional compilation directives aren't supported in module maps.
- Module maps assume headers are well-formed and can be parsed in isolation.

## Integration with Swift Package Manager

Swift Package Manager uses module maps to bridge C and C++ libraries:

- The `moduleMapPath` field in artifact bundles specifies the module map location.
- System library targets place module maps in the target directory.
- The build system automatically adds `-fmodule-map-file=` flags.
- Module names must match binary target or system library target names.

For instructions on creating a module map, see <doc:ModuleMaps>.

## Best practices

Follow these practices when writing module maps:

- Use `[system]` for SDK and system library modules.
- Specify `requires cplusplus` for any C++ code.
- Use umbrella headers for multi-header libraries.
- Keep module names simple and descriptive.
- Match module names to artifact names exactly.
- Use relative paths for all header references.
- Document configuration macros with `exhaustive`.
- Test module maps on all target platforms.
- Use explicit submodules for optional functionality.
- Keep module maps minimal and focused.

## See Also

- [Clang Modules Documentation](https://clang.llvm.org/docs/Modules.html)
- <doc:DebuggingModuleMaps>

