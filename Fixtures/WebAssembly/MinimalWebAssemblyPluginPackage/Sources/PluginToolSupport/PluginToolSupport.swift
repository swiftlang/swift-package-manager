#if os(WASI)
#error("PluginToolSupport must not be compiled for WebAssembly.")
#endif

public func generatedSource(returning value: String) -> String {
    """
    public func generatedFunction() -> String {
        "\(value)"
    }
    """
}
