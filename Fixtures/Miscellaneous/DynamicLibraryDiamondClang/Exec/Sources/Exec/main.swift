import First
import Second

// Both dynamic libraries call into the same `Shared` module. If `Shared` was linked
// into each of them separately there will be two copies of its global state and both
// calls return 1; if it was linked once they share it and return 1 then 2.
print("first=\(firstBump()) second=\(secondBump())")
