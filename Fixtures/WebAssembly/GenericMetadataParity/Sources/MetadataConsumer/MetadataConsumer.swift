import MetadataLib

// Instantiating Boxed<H1> across the module boundary is the trigger; a single-target fixture does not reproduce it.
@main
struct Main {
    static func main() {
        #if os(WASI)
        let boxed: Any = Boxed<H1>(42)
        if boxed is Boxed<H1> {
            print("ok")
        } else {
            fatalError("Boxed<H1> failed its own dynamic cast")
        }
        #endif
    }
}
