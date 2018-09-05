// RUN: %lit-test-helper -classify-syntax -source-file %s | %FileCheck %s

// CHECK: <#kw>#if</#kw> <#id>d</#id>
// CHECK-NEXT: <kw>func</kw> bar() {
// CHECK-NEXT: <#kw>#if</#kw> <#id>d</#id>
// CHECK-NEXT: }
// CHECK-NEXT: <kw>func</kw> foo() {}

#if d
func bar() {
  #if d
}
func foo() {}
