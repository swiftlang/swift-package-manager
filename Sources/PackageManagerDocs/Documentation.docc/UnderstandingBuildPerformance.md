# Understanding Build Performance

Use SwiftPM to investigate and diagnose issues with package build performance.

## Overview

Build performance is an important component of developer productivity. Clean build performance is largely determined by how much work is required to build a package and how effectively that work can be parallelized, while incremental build performance also depends on how much of a build is invalidated by a particular incremental change. When analyzing build performance of a package, it's sometimes difficult to determine how build tools and package configuration influence these factors and where there are opportunities to make improvements. SwiftPM provides tools which give users insight into build performance so that they can make more informed decisions when optimizing build times or debugging build performance issues.

## Trace Events Output

SwiftPM supports emitting trace files in the Trace Events format via the `--trace-events-file <path>` option, which can be passed to any command which runs a build. The resulting trace includes timing information for every task which ran during the build, showing which tasks ran faster or slower compared to others, and which tasks ran in parallel. This information can be very helpful when optimizing a clean build to improve parallelism, identifying expensive work on the critical path, or identifying the full set of tasks running in an incremental build after making a particular change. Many tools including Chrome's `about://tracing` feature support visualizing traces in this format.

## Task Backtraces

When debugging incremental build performance issues, it's important not only to understand the performance of tasks which ran, but also why they needed to re-run. Task backtraces enumerate the sequence of steps which led a task to be invalidated, making it easier to identify inconsistent configuration, nondeterminism, and other common sources of unexpectedly expensive incremental rebuilds.

Task backtraces are enabled by passing `--enable-task-backtraces` to any SwiftPM subcommand which runs a build. This flag must be paired with either `--trace-events-file` to include the backtrace information in the build trace, `--verbose`/`--very-verbose` to include it in the textual build output, or both.

Here's an example of a backtrace from an incremental build of SwiftPM itself, describing why the `swift-build` executable was re-linked in an incremental build after making a change to `URL.swift` in the `Basics` module of the package:

```
#0: an input of 'Link swift-build (arm64)' changed
#1: the task producing file '.../swiftpm/.build/out/Products/Debug/Basics.o' ran
#2: an input of 'Link Basics.o (arm64)' changed
#3: the task producing file '.../swiftpm/.build/out/Intermediates.noindex/SwiftPM.build/Debug/Basics-t.build/Objects-normal/arm64/URL.o' ran
#4: an input of 'Compile Basics (arm64)' changed
#5: file '.../swiftpm/Sources/Basics/URL.swift' changed
```

The first line of the backtrace describes the most immediate reason the link task needed to run: one of its inputs had changed. From there, the backtrace can be read top to bottom to understand the full chain of events which connect this change to the original change, the user-initated modification to `URL.swift`. In this case, the change to `URL.swift` meant it needed to be recompiled, which in turn invalidated the corresponding object file, which in turn invalidated the link of the `Basics` target, which in turn invalidated the link of the final executable.

In addition to diagnosing changes in input files, task backtraces could also indicate a task needed to run in an incremental build because:
* Its arguments, working directory, or environment changed
* One of its outputs was deleted or otherwise modified outside the build
* The previous build failed or was cancelled before the task ran

