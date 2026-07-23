# ``PackagePlugin/PluginContext``

Use a plugin context to inspect the package and locate the command-line tools
that a plugin needs.

## Locating Command-Line Tools

Call ``tool(named:)`` with a tool's logical name to obtain the URL of an
executable that runs on the host platform. SwiftPM builds executable dependencies
for the host platform and selects host-compatible variants from binary artifact
bundles.

The lookup name depends on how the plugin declares the tool:

| Dependency | Lookup name |
| --- | --- |
| Executable target in the same package | Target name |
| Executable product from another package | Product name |
| Executable in a binary target | Artifact name in the artifact bundle metadata |

Only direct dependencies of the plugin target provide tools. A declared tool
takes precedence over any executable with the same name in a host-provided
search directory. If a binary target declares the requested artifact but has no
variant for the host platform, lookup reports
``PluginContextError/toolNotSupportedOnTargetPlatform(name:)`` instead of
searching for another executable with that name.

If no declared dependency matches, ``tool(named:)`` checks each host-provided
search directory in order and returns the first executable file with the
requested name. On Windows, it appends the `.exe` suffix when searching these
directories. The directories are an implementation detail of the host and can
differ between SwiftPM, an IDE, and other package-manager integrations. Declare
every required executable as a plugin dependency when the plugin needs to work
across hosts. A plugin that intentionally uses a tool installed on the user's
system should document the supported host and configuration requirements.

## Topics

### Inspecting the Context

- ``pluginWorkDirectoryURL``
- ``tool(named:)``
- ``package``
- ``Tool``
- ``pluginWorkDirectory``
