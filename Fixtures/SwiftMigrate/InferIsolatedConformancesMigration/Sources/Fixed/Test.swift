@MainActor
class C: nonisolated Equatable {
  let name = "Hello"

  nonisolated static func ==(lhs: C, rhs: C) -> Bool {
    lhs.name == rhs.name
  }
}

protocol P {}
protocol Q {}

@MainActor
struct S: nonisolated P & Q {}
