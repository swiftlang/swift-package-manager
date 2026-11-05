import LibOne
import LibTwo

// The root's own bucket is spelled `Shared` (the build passes -module-alias Shared=Shared_v2, and the compiler
// rejects `import Shared_v2` for an aliased module; see example 01).
import Shared

let fromOne = LibOne.makeToken("hello")   // Shared 1.x Token
let fromTwo = LibTwo.makeToken("hello")   // Shared 2.x Token
let own = Token("hello")                  // root's own Shared (2.x) Token

print("fromOne: \(String(reflecting: type(of: fromOne)))")
print("fromTwo: \(String(reflecting: type(of: fromTwo)))")
print("own:     \(String(reflecting: type(of: own)))")

// What works: handing LibTwo something of its own major.
print(LibTwo.describe(fromTwo))
print(LibTwo.describe(own))

// The only bridge between majors is through types both sides agree on, here a String.
print(LibTwo.describe(Token(fromOne.value)))

#if MISMATCH
// Build with `-Xswiftc -DMISMATCH`. Expected compile error: cannot convert value of type
// 'Shared_v1.Token' to expected argument type 'Shared_v2.Token' (or similar).
print(LibTwo.describe(fromOne))
#endif
