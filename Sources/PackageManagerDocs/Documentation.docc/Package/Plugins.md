# Plugins

Swift Package Manager supports plugins that can extend package functionality.

## Overview

There are two kinds of plugins in SwiftPM:

- **Command plugins**, which are invoked explicitly by users.
- **Build tool plugins**, which are applied to targets during the build.

## Build Tool Plugins

Build tool plugins are executed by the build system and may generate files
that are used as inputs to compilation.

## Plugin Outputs and Visibility

Plugins may generate files that are tracked by the build system for incremental
builds. Generated files are associated with the target the plugin is applied to.

Plugins do not form a pipeline, and outputs produced by one plugin are not
guaranteed to be visible to other plugins.

