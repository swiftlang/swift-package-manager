import LibOne
import LibTwo
import LibThree

print("sharedMajor: \(LibOne.sharedMajor) \(LibTwo.sharedMajor) \(LibThree.sharedMajor)   (expected 1 2 3)")
print("token types: \(LibOne.tokenTypeName), \(LibTwo.tokenTypeName), \(LibThree.tokenTypeName)")

// Each call appends to its own major's log, so a merged log would show entries from the other libraries.
// LibOne is called a second time at the end to confirm its log accumulates independently.
print("LibOne   log: \(LibOne.registerAndDump())")
print("LibTwo   log: \(LibTwo.registerAndDump())")
print("LibThree log: \(LibThree.registerAndDump())")
print("LibOne   log: \(LibOne.registerAndDump())   (expected [v1:LibOne, v1:LibOne])")
