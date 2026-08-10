# Custom Targets

Custom targets are simply targets that contain one or more build tool plugins. There is no predefined output of a custom target. Their role is to simply give the plugins a home and to provide optional dependencies for the plugins to operate on.

As with regular build tool plugins, they provide Commands to that build system that will execute a tool that consumes input files and produces output files. However, they are much more freeform. The inputs to commands may come from the following providers:
- the sources and resources of the target they are connected to
- the outputs of commands in the same target
- the outputs of commands in the custom targets that are direct dependencies of the target
- the products of library and executable targets that are direct dependencies of the target

Outputs that are not consumed by another command are considered products of the target.
- *TODO: Should the products list be more explicit?*
- *TODO: Should we allow object files that can be linked into library and executable targets?*
- *TODO: Should we allow plugins to categorize output files as resource files that are bundled in a platforms specific way by the end application/executable target?*

Regular module targets may depend on custom targets that produce source and resource files as outputs.

Since the outputs of commands in one target may be consumed by commands in a dependant target, we need to run the plugins in topological order to allow them to be discovered by the dependant targets.
- *TODO: Do we finally need a build system for the plugins to control this order? Could be a simple llbuild graph.*
- *TODO: Are plugins for a given target run in a reproducible order, e.g. the order they are listed in?*

To provide configuration of the plugins, we add a general class of plugin settings to custom targets. These are simply `[String: [String]]` dictionaries that are passed to the plugin in the target context object.
- *TODO: Should we make this generally available, i.e. pass all build tool plugins all of build settings for targets*
- *TODO: We need to investigate how packages defining plugins can provide static function definitions for their settings to avoid using so many strings*

## Example

An example is provided for Java in Examples/java-targets. It compiles a simple java file and then creates a jar file with the resulting class. To build use `--product JarTarget`. The resulting jar file can be executed by a Java virtual machine to print “Hello World".

The intention is to provide a fuller example with better support for swift-java and for generating Android APKs and Windows SxS assemblies.

## Future Work

Allow custom targets to use files from alternative repositories as input. In the Java case, this could be jar files from Maven central and Android repositories. This would leverage our upcoming feature that introduces Package URLs (PURLs) as Package identities allow for dependencies to be expressed on alternative package repositories.

To allow `swift run` to be able to deploy and execute the outputs of custom tasks, we’ll need additional plugins that can understand the tools necessary to transfer those outputs to a device, if necessary, and to manage the execution of those binaries.

The use of plain String dictionaries for build settings adds to our list of Strings that could use Swift function helpers to improve ergonomics. Packages should be able to provide these functions to consuming packages. We need to solve the chicken and egg problem though of parsing a manifest to resolve the dependencies of that package to know what helper functions to compile that manifest with. There are some experiments under way to solve that at least for constrained classes of manifest.