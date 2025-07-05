@MainActor
class C: Equatable {
  let name = "Hello"

  nonisolated static func ==(lhs: C, rhs: C) -> Bool {
    lhs.name == rhs.name
  }
}
