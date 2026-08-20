#if os(WASI)
#error("PluginToolHelpers must not be compiled for WebAssembly.")
#endif

public func pluginToolHelper() -> String {
    "generated"
}
