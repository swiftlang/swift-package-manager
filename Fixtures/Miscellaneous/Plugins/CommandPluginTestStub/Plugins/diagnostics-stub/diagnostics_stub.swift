import Foundation
import PackagePlugin

@main
struct diagnostics_stub: CommandPlugin {
    // This is a helper for testing plugin diagnostics.  It sends different messages to SwiftPM depending on its arguments.
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Build a target, possibly asking SwiftPM to echo the logs as they are produced.
        if arguments.contains("build") {
            // If echoLogs is true, SwiftPM will print build logs to stderr as they are produced.
            // SwiftPM does not add a prefix to these logs.
            let result = try packageManager.build(
                .product("placeholder"),
                parameters: .init(echoLogs: arguments.contains("echologs"))
            )

            // To verify that logs are also returned correctly to the plugin,
            // print the accumulated log buffer lines with a prefix to
            // distinguish them from echoed logs.   These logs are normal output
            // from the plugin and will be printed on stdout.
            if arguments.contains("printlogs") {
                for line in result.logText.components(separatedBy: "\n") {
                    print("command plugin: packageManager.build logtext: \(line)")
                }
            }
        }

        // Anything a plugin writes to standard output appears on standard output.
        // Printing to stderr will also go to standard output because SwiftPM combines
        // stdout and stderr before launching the plugin.
        if arguments.contains("print") {
           print("command plugin: print")
        }

        // Diagnostics are collected by SwiftPM and printed to standard error, depending on the current log verbosity level.
        if arguments.contains("progress") {
           Diagnostics.progress("command plugin: Diagnostics.progress")     // prefixed with [plugin_name]
        }

        if arguments.contains("remark") {
           Diagnostics.remark("command plugin: Diagnostics.remark")     // prefixed with 'info:' when printed
        }

        if arguments.contains("warning") {
           Diagnostics.warning("command plugin: Diagnostics.warning")   // prefixed with 'warning:' when printed
        }

        if arguments.contains("error") {
           Diagnostics.error("command plugin: Diagnostics.error")       // prefixed with 'error:' when printed
        }
    }
}
