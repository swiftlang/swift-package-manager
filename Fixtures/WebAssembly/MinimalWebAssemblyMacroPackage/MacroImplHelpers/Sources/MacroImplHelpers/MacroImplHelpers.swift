#if os(WASI)
#error("MacroImplHelpers must not be compiled for WebAssembly.")
#endif

public func macroImplHelper() -> String {
    "expanded"
}
