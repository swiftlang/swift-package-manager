// RUN: %lit-test-helper -classify-syntax -source-file %s | %FileCheck %s

// CHECK: <comment-block>/* foo is the best */</comment-block>
/* foo is the best */
func foo(n: Float) {}

///- returns: single-line, no space
// CHECK: <doc-comment-line>///- returns: single-line, no space</doc-comment-line>

/// - returns: single-line, 1 space
// CHECK: <doc-comment-line>/// - returns: single-line, 1 space</doc-comment-line>

///  - returns: single-line, 2 spaces
// CHECK: <doc-comment-line>///  - returns: single-line, 2 spaces</doc-comment-line>

///       - returns: single-line, more spaces
// CHECK: <doc-comment-line>///       - returns: single-line, more spaces</doc-comment-line>

// CHECK: <kw>protocol</kw> Prot
protocol Prot {}

func f(x: Int) -> Int {
  // CHECK: <comment-line>// string interpolation is the best</comment-line>
  // string interpolation is the best
  "This is string \(x) interpolation"
}

// FIXME: blah.
//    FIXME:   blah blah
// Something something, FIXME: blah

// CHECK: <comment-line>// FIXME: blah.</comment-line>
// CHECK: <comment-line>//    FIXME:   blah blah</comment-line>
// CHECK: <comment-line>// Something something, FIXME: blah</comment-line>



/* FIXME: blah*/

// CHECK: <comment-block>/* FIXME: blah*/</comment-block>

/*
 * FIXME: blah
 * Blah, blah.
 */

// CHECK: <comment-block>/*
// CHECK:  * FIXME: blah
// CHECK:  * Blah, blah.
// CHECK:  */</comment-block>

// TODO: blah.
// TTODO: blah.
// MARK: blah.

// CHECK: <comment-line>// TODO: blah.</comment-line>
// CHECK: <comment-line>// TTODO: blah.</comment-line>
// CHECK: <comment-line>// MARK: blah.</comment-line>

// CHECK: <kw>func</kw> test5() -> <type>Int</type> {
func test5() -> Int {
  // CHECK: <comment-line>// TODO: something, something.</comment-line>
  // TODO: something, something.
  // CHECK: <kw>return</kw> <int>0</int>
  return 0
}

// http://whatever.com?ee=2&yy=1 and radar://123456
/* http://whatever.com FIXME: see in http://whatever.com/fixme
  http://whatever.com */

// CHECK: <comment-line>// http://whatever.com?ee=2&yy=1 and radar://123456</comment-line>
// CHECK: <comment-block>/* http://whatever.com FIXME: see in http://whatever.com/fixme
// CHECK:   http://whatever.com */</comment-block>

// CHECK: <comment-line>// http://whatever.com/what-ever</comment-line>
// http://whatever.com/what-ever

/// Brief.
///
/// Simple case.
///
/// - parameter x: A number
/// - parameter y: Another number
/// - PaRamEteR z-hyphen-q: Another number
/// - parameter : A strange number...
/// - parameternope1: Another number
/// - parameter nope2
/// - parameter: nope3
/// -parameter nope4: Another number
/// * parameter nope5: Another number
///  - parameter nope6: Another number
///  - Parameters: nope7
/// - seealso: yes
///   - seealso: yes
/// - seealso:
/// -seealso: nope
/// - seealso : nope
/// - seealso nope
/// - returns: `x + y`
func foo(x: Int, y: Int) -> Int { return x + y }
// CHECK: <doc-comment-line>/// Brief.</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>/// Simple case.</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameter x: A number</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameter y: Another number</doc-comment-line>
// CHECK: <doc-comment-line>/// - PaRamEteR z-hyphen-q: Another number</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameter : A strange number...</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameternope1: Another number</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameter nope2</doc-comment-line>
// CHECK: <doc-comment-line>/// - parameter: nope3</doc-comment-line>
// CHECK: <doc-comment-line>/// -parameter nope4: Another number</doc-comment-line>
// CHECK: <doc-comment-line>/// * parameter nope5: Another number</doc-comment-line>
// CHECK: <doc-comment-line>///  - parameter nope6: Another number</doc-comment-line>
// CHECK: <doc-comment-line>///  - Parameters: nope7</doc-comment-line>
// CHECK: <doc-comment-line>/// - seealso: yes</doc-comment-line>
// CHECK: <doc-comment-line>///   - seealso: yes</doc-comment-line>
// CHECK: <doc-comment-line>/// - seealso:</doc-comment-line>
// CHECK: <doc-comment-line>/// -seealso: nope</doc-comment-line>
// CHECK: <doc-comment-line>/// - seealso : nope</doc-comment-line>
// CHECK: <doc-comment-line>/// - seealso nope</doc-comment-line>
// CHECK: <doc-comment-line>/// - returns: `x + y`</doc-comment-line>
// CHECK: <kw>func</kw> foo(x: <type>Int</type>, y: <type>Int</type>) -> <type>Int</type> { <kw>return</kw> x + y }


/// Brief.
///
/// Simple case.
///
/// - Parameters:
///   - x: A number
///   - y: Another number
///
///- note: NOTE1
///
/// - NOTE: NOTE2
///   - note: Not a Note field (not at top level)
/// - returns: `x + y`
func bar(x: Int, y: Int) -> Int { return x + y }
// CHECK: <doc-comment-line>/// Brief.</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>/// Simple case.</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>/// - Parameters:</doc-comment-line>
// CHECK: <doc-comment-line>///   - x: A number</doc-comment-line>
// CHECK: <doc-comment-line>///   - y: Another number</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>///- note: NOTE1</doc-comment-line>
// CHECK: <doc-comment-line>///</doc-comment-line>
// CHECK: <doc-comment-line>/// - NOTE: NOTE2</doc-comment-line>
// CHECK: <doc-comment-line>///   - note: Not a Note field (not at top level)</doc-comment-line>
// CHECK: <doc-comment-line>/// - returns: `x + y`</doc-comment-line>
// CHECK: <kw>func</kw> bar(x: <type>Int</type>, y: <type>Int</type>) -> <type>Int</type> { <kw>return</kw> x + y }

/**
  Does pretty much nothing.

  Not a parameter list: improper indentation.
    - Parameters: sdfadsf

  - WARNING: - WARNING: Should only have one field

  - $$$: Not a field.

  Empty field, OK:
*/
func baz() {}
// CHECK: <doc-comment-block>/**
// CHECK:   Does pretty much nothing.
// CHECK:   Not a parameter list: improper indentation.
// CHECK:     - Parameters: sdfadsf
// CHECK:   - WARNING: - WARNING: Should only have one field
// CHECK:   - $$$: Not a field.
// CHECK:   Empty field, OK:
// CHECK: */</doc-comment-block>
// CHECK: <kw>func</kw> baz() {}

/***/
func emptyDocBlockComment() {}
// CHECK: <doc-comment-block>/***/</doc-comment-block>
// CHECK: <kw>func</kw> emptyDocBlockComment() {}

/**
*/
func emptyDocBlockComment2() {}
// CHECK: <doc-comment-block>/**
// CHECK: */
// CHECK: <kw>func</kw> emptyDocBlockComment2() {}

/**          */
func emptyDocBlockComment3() {}
// CHECK: <doc-comment-block>/**          */
// CHECK: <kw>func</kw> emptyDocBlockComment3() {}


/**/
func malformedBlockComment(f : () throws -> ()) rethrows {}
// CHECK: <doc-comment-block>/**/</doc-comment-block>

// CHECK: <kw>func</kw> malformedBlockComment(f : () <kw>throws</kw> -> ()) <kw>rethrows</kw> {}

//: playground doc comment line
func playgroundCommentLine(f : () throws -> ()) rethrows {}
// CHECK: <comment-line>//: playground doc comment line</comment-line>

/*:
  playground doc comment multi-line
*/
func playgroundCommentMultiLine(f : () throws -> ()) rethrows {}
// CHECK: <comment-block>/*:
// CHECK: playground doc comment multi-line
// CHECK: */</comment-block>

/// [strict weak ordering](http://en.wikipedia.org/wiki/Strict_weak_order#Strict_weak_orderings)
// CHECK: <doc-comment-line>/// [strict weak ordering](http://en.wikipedia.org/wiki/Strict_weak_order#Strict_weak_orderings)</doc-comment-line>

/** aaa

 - returns: something
 */
// CHECK:  - returns: something
let blah = 0

// Keep this as the last test
/**
  Trailing off ...
func unterminatedBlockComment() {}
// CHECK: <comment-line>// Keep this as the last test</comment-line>
// CHECK: <doc-comment-block>/**
// CHECK:  Trailing off ...
// CHECK:  func unterminatedBlockComment() {}
// CHECK:  </doc-comment-block>
