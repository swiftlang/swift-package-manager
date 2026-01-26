@main struct Entry {
    static func main() {
        // Ensure that Bar can be referenced as a member of the module named Foo,
        // even though the executable target Foo may have been merged into the Exe1 or Exe2 products.
        let x = Foo.Bar()
    }
}

struct Bar {}
