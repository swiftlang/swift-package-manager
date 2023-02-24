import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `#fontLiteral` macro, which is similar in spirit
/// to the built-in expressions `#colorLiteral`, `#imageLiteral`, etc., but in
/// a small macro.
public struct FontLiteralMacro: ExpressionMacro {
  public static func expansion(
    of macro: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) -> ExprSyntax {
    let argList = replaceFirstLabel(
      of: macro.argumentList,
      with: "fontLiteralName"
    )
    let initSyntax: ExprSyntax = ".init(\(argList))"
    if let leadingTrivia = macro.leadingTrivia {
      return initSyntax.with(\.leadingTrivia, leadingTrivia)
    }
    return initSyntax
  }
}

/// Replace the label of the first element in the tuple with the given
/// new label.
private func replaceFirstLabel(
  of tuple: TupleExprElementListSyntax,
  with newLabel: String
) -> TupleExprElementListSyntax {
  guard let firstElement = tuple.first else {
    return tuple
  }

  return tuple.replacing(
    childAt: 0,
    with: firstElement.with(\.label, .identifier(newLabel))
  )
}
