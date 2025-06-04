# EnableCommandPlugin

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

A package plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package that defines it.

To get access to a plugin defined in another package, add a package dependency on the package that defines the plugin.  This will let the package access any build tool plugins and command plugins from the dependency.


### Making use of a command plugin

Unlike build tool plugins, which are invoked as needed when package manager constructs the build task graph, command plugins are only invoked directly by the user.  This is done through the `swift` `package` command line interface:

```shell
❯ swift package my-plugin --my-flag my-parameter
```

Any command line arguments that appear after the invocation verb defined by the plugin are passed unmodified to the plugin — in this case, `--my-flag` and `my-parameter`.  This is commonly used in order to narrow down the application of a command to one or more targets, through the convention of one or more occurrences of a `--target` option with the name of the target(s).

To list the plugins that are available within the context of a package, use the `--list` option of the `plugin` subcommand:

```shell
❯ swift package plugin --list
```

Command plugins that need to write to the file system will cause package manager to ask the user for approval if `swift package` is invoked from a console, or deny the request if it is not.  Passing the `--allow-writing-to-package-directory` flag to the `swift package` invocation will allow the request without questions — this is particularly useful in a Continuous Integration environment. Similarly, the `--allow-network-connections` flag can be used to allow network connections without showing a prompt.
