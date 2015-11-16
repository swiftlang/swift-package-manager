# Source Layouts

The modules that `swift build` creates are determined from the filesystem layout of your source files.

For example, if you created a directory with the following layout:

    example/
    example/Sources/bar.swift
    example/Sources/baz.swift

Running `swift build` within directory `example` would produce a single library target: `example/.build/debug/example.a`

To create multiple modules create multiple subdirectories:

    example/Sources/foo/foo.swift
    example/Sources/bar/bar.swift

Running `swift build` would produce two library targets:

* `example/.build/debug/foo.a`
* `example/.build/debug/bar.a`

To generate an executable module (instead of a library module) add a `main.swift` file to that module’s subdirectory:

    example/Sources/foo/main.swift
    example/Sources/bar/bar.swift

Running `swift build` would now produce:

* `example/.build/debug/foo`
* `example/.build/debug/bar.a`

Where `foo` is an executable and `bar.a` a static library.


## Other Rules

* Directories named `Tests` are ignored
* Sub directories of a directory named `Sources`, `Source`, `srcs` or `src` become modules
* It is acceptable to have no `Sources` directory, in which case the root directory is treated as a single module (place your sources there) or sub directories of the root are considered modules. Use this layout convention for simple projects.
