protocol P {}
protocol Q {}

@MainActor
struct S: P & Q {}
