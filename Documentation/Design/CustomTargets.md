# Custom Targets, External Targets, and Swift Syntax Prebuilts
## Extending Build Tool Plugins
At the core of these features is extending build tool plugins to allow them to specify outputs that are build products that should be made available to other target's plugins. In SwiftBuild terms, these files are added to the copy files phase and coped into the build products directory. This opens up incredible power to build plugin tools to produce artifacts of any kind and have those artifacts added to the build graph.
With this extra power comes the need for build plugin tools to be able to adapt to build requests, particularly with the knowledge of the platform, triple, and build configuration. This is accomplished with the addition of build variables. They look suspicioulsly like SwiftBuild macro expressions but they are not directly those macros. To ensure we maintain a layer between the plugins and SwiftBuild that will allow us to evolve SwiftPM's build system, these variables are translated when the CustomTask for the plugin tool is created. Unknown variables will not be blindly copied to the task to ensure we keep that separation. The variable can apply to any string field in the build Command but usually will result in adapted arguments to the command or in the environment for the command. Input and output files may also use these variables.
*TODO: Since these variables may come at the beginning of a path specification and may resolve into an absolute path or a relative path, paths become hard to model with URLs. It may be better to model them as strings, at least in the serialization, and revive the Path type that was previously deprecated.*
In order for plugins to discover the build products from the context target's dependencies, we will need to run the plugins in topographical order. The list of build products provided by a target's plugins should really be calculated close to package resolution time, potentially at package manifest load time. In fact, you need to know the list of generated files so you can tell whether a Module is a SwiftModule, ClangModule or CustomTarget. That is calculated in the PackageBuilder really early in the construction of the graph.
## Sandboxing
Plugins remain sandboxed on Mac and introduced on Linux using Bubblewrap or equivalent, and on Windows using AppContainers. Plugins continue to only have write access to the plugin output directory with read access to the package sources and the build products directory for the current effective platform. All network access and writes to the build products directory are performed by SwiftPM itself upon validating the parameters of the request.
## Custom Targets
While the extended plugin capability is available to plugins attached to Clang and Swift modules, they can also be applied to modules that do not have Clang or Swift sources. Previously this would error out. Instead, a new subclass of Module is created, CustomTarget, and a new target type, custom, to model this. CustomTargets result in AggregateTargets in the PIF. Commands from the build tool plugins are converted into CustomTasks on the target. As well, any build product files are added as BuildFiles to the copy phase of the target.
When a custom target produces libraries that may be consumed by dependent targets, build settings may be specified on the custom target. Those settings are added to the imparted settings for the custom target.
*TODO: do we need build settings to be imparted like this from Clang/Swift module targets as well?*
## External Target
External targets are custom targets with the source for the target being external to the package. Similar to package dependencies, the target specifies the location for that source as either
- A path in the local file system
- Remote source archive URL with checksum
- Source control URL with version range

It is expected that build tool plugins would be attached to the target to add commands that produce the build of that source and to register the build products that would be consumed by dependent targets. Build settings on the external target are imparted on those dependent targets.
## Prebuilt Target
We leverage Custom Targets to model the libraries for prebuilts. We can then add conditional dependencies on these targets to allow them to be used for host builds, or to use the prebuilts source package when building for non-host.

##  Examples
To help confirm we have the desired capability and ergonomics, we'll produce examples in the Examples directory.
- Simple Java/jar build to demonstrate the pure Custom Targets workflow.
- SDL that includes an executable that shows calls into SDL working
    - Builds for host and for Android including creating an APK
    - Note that until we get the products/target unification complette, the Android app part needs to be in a separate package so it can consume the shared library from the swift-sdl package.
- MLX-swift and shaders
    - Can we integrate shader compilers into the build of MLX-swift in a more natural way

## Future Work
### Plugin Settings
Once plugins become more powerful, package developers will want to be able to share plugins and apply them to multiple packages, adding to the ecosystem. We will need a way to configure the use of a plugin as applied to a target. Plugins have relied on config files to help with that. It would be more ergonomic if such settings were specified in the package manifest and passed to the plugin at run time. This could be a [String: [String]] dictionary.
### External Binary Targets
The Prebuilt Target shows how we can integrate binaries using the custom target mechanism. Can we generalize it to handle any binary targets?
- Like external targets can specify the path or url/checksum to a binary archive that SwiftPM fetches.
- Be able to specify the product files in the distribution as well as build settings that are imparted to dependent targets to use them.
- Need more detailed target conditionals to ensure the right archive is fetched for the platform/triple of the build request
###  Custom Executable Targets
If a custom/external/binary target supplies executables that can be used by plugins or exposed to swift run, we need a way to add these executable to the graph.
Could be as simple as an executable target that doesn't have source but who's binary is found in the build products directory of one of it's dependencies.
BTW, this may also make sense for the Android APK target which is probably better modelled as an executable target since it could be an argument to swift run.
