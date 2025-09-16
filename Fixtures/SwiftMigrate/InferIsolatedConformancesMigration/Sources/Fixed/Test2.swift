protocol P {}
protocol Q {}

@MainActor
struct S: nonisolated P & Q {}
