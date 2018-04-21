# Makefile Generation Support

SwiftPM has support for generating makefiles for simple Swift packages.  Some of
the advanced features like modulemap generation, package dependencies, etc are
out-of-scope unless required in future. The makefile support is accessible using
an hidden flag and is intended to be used only for Swift.org related projects for
bootstrapping them on the Swift CI.

To generate makefile for a package, run the following command:

```sh
$ swift package __internal-tools --generate-makefile
```

**Note**: This command is hidden from the help.

SwiftPM will generate files inside the directory `swift-ci/`.  The generated
files are supposed to be checked-in and would require re-generation when there
is a change in target or product structure of the package.

Default targets: 
- A top-level target "all" that builds everything including tests.
- A "clean" target to clean the build directory.

Customizable variables:
- By default, the build directory will be `<package root>/.build` but can
  be customized using the variable `BUILD_DIR_PATH`.
- Build config can be selected using the variable `CONFIG`. There are two
  configs available debug (default) and release.
