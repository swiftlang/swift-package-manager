
# Extending Plugins for Custom Targets and External Targets
This feature breaks down restrictions on what files build plugin tools can produce. This includes being able to have a plugin without Swift/Clang sources but with other sources, or no sources at all, and let the plugins decide what commands with inputs and outputs to add to the build graph. This general concept is called Custom Targets though plugins should be able to produce any file for any type of target.
We then build on this by introducing external targets that take a source tree, possibly downloaded from source control or a remote source archive, and plugins add commands to build that source to produce libraries or executables that can be introduced into the SwiftBuild build graph so Swift/Clang modules may depend on them.
The aim 
## Requirements
There are a number of use cases we'd like to extend plugins to support:
- Generating arbitrary outputs
  - Not just source as we have is today
  - Include object code that can be linked with standard Clang/Swift objects
- Incorporate knowledge of the build request
  - Enable plugins to generate commands with knowledge of
    - The triple(s) components
    - The SDK
    - The build configuration
- Provide an intermediate directory for outputs
    - For given combinations of build request properties
- Enable them to copy results to the build products directory
    - Make them available with -show-bin-path
    - So that dependent targets can find the results
- Allow to be the sole provider of the build for a target
    - If a target has no source, headers, modulemap that would map it into a traditional target
- But also apply to traditional targets
    - can product traditional products as well as custom ones
- Allow plugins to specify platform independent commands for "copy" and "touch"

Introduce a new target type, similar to binary targets, but allows incorporating a non-Swift source or binary tree
- Target specifies location for source
    - Local file system, allow outside package
    - Source control, including version ranges
    - Remote source archive with checksum
- Target can also specify location for binaries
    - Remote binary archive with checksum
    - Selected based on condition
- Uses the plugin extensions above to perform any steps necessary to get products in to the products directory.
- Specifies build settings like public header file path needed for consuming targets

External library target to incorporate library products into rest of build.
    - Similar to system libraries except library is located in the build products directory

External executable target to incorporate executable products into rest of build, including use by build tool plugins.
## Design
Introduce variables that can be used in the strings/URLs when the plugin defines a Command
- e.g. `$(SDKROOT)
- Looks like SwiftBuild build setting macros but they're not
    - But can map to them when creating the CustomTask
    - Lets us control what is visible and produce more ergonomic names for them
    - (Also closes a hole where they can sneak in now)
- Add variables for the build products and intermediates directory so the plugins can place files in build specific directories
- provide variables from the copy command and the touch command
    - To copy files to the build products directory
    - To update timestamp on marker files to allow for variable output file list
    - May want more in the future

Add a new `Module` type for non-source targets, i.e. Not Swift or Clang modules.
- Generate AggregateTargets for these and add the CustomTargets for each plugin usage

Add a module type for external targets
- Manages download of archive or checkout of source
    - Can we get this at build request time so we only download archives we need
- Plugins run the build and copy the products for the target to the build products directory for the target
- Exposes build settings to allow dependent targets to use the build products
    - User provided public header path
    - Automatically adds build products directory to public library path (assuming it's different from other targets)

Add module type for external executable.
- Adds the executable to the model.

Since the library path is added to the imparted settings of the external module, we don't need an external library module type
- And we want to get the produced libraries into modules as quickly (directly) as possible

## Implementation Questions
Things that need to be resolved:
- With the use of variable expressions in paths in the plugins, URL no longer makes as much sense
    - Variables like BUILT\_PRODUCTS\_DIR is an absolute path so forcing these things into AbsolutePath with a leading "/" will cause issues on Windows
    - Paths at this point need to be Strings across the wire, or a generic Path that can be either relative or absolute.
- A new subclass of Module, CustomTarget, is added to handle targets that have no sources or headers as returned by the TargetSourcesBuilder.
    - It returns a list of "other" files. we add those as sources for the CustomTarget
    - Should other files be added to all targets? Needs more study
- In order for a plugin to be more generic, it needs to be able to see the build products from it's dependencies, including the ones generated by plugins on those dependencies.
    - That would require the plugins to be run in topographical order
    - And then we need to add that to the target info passed to the plugin for those dependencies
    - Should this info be part of the action graph like we have for the sources already?
    - At the least, we should be able to detect when commands output files to the BUILT\_PRODUCTS\_DIR and make that list available to dependant targets' plugins.
- How do plugins handle builds for multiple platforms?
    - Some of the commands it adds only work on certain platforms, e.g. building the jar files in SDL are only for Android
    - Can we add "when" clauses to the commands?
- How do we implement cross-platform copy and touch commands?
    - We could introduce variables for the commands and detect them.
    - We don't want to open the sandbox to the product directory so the copy task needs to be managed carefully
## Examples
To help confirm we have the desired capability and ergonomics, we'll produce examples in the Examples directory.
- Simple Java compile, produce jar from classes
- SDL that includes an executable that shows calls into SDL working
    - Builds for host and for Android including creating an APK
- MLX-swift and shaders
    - Can we integrate shader compilers into the build of MLX-swift in a more natural way

## Future Work
### Plugin Settings
Once plugins become more powerful, package developers will want to be able to share plugins and apply them to multiple packages, adding to the ecosystem. We will need a way to configure the use of a plugin as applied to a target. Plugins have relied on config files to help with that. It would be more ergonomic if such settings were specified in the package manifest and passed to the plugin at run time. This could be a [String: [String]] dictionary.
### External Binary Targets as Prebuilts
Can we use external binary targets to generalize prebuilts?
    - Somehow associate an external source target with a list of external binary targets that are prebuilts of the source target.
- If one of the binary targets have successful target conditions, use it, otherwise use the source target

We might want to make the binary target support future work as well until we can figure that out. Source would be fine for now.
