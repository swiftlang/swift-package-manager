// RUN: %lit-test-helper -classify-syntax -source-file %s | %FileCheck %s

// CHECK: <kw>return</kw> c.return

class C {
  var `return` = 2
}

func foo(_ c: C) -> Int {
  return c.return
}
