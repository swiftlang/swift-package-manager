#if os(WASI)
#error("MacroImplSupport must not be compiled for WebAssembly.")
#endif

public func quoted(_ value: String) -> String {
    "\"\(value)\""
}
