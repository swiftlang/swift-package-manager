class Queue {
    private var queue = Array<URL>()
    private var set = Set<URL>()
    private var state = [URL: UpdateState]()

    private enum State {
        case PreUpdate, Updating, Done
    }
    private var mystate: State = .PreUpdate

    func pop() -> (URL, UpdateState)? {
        switch mystate {
        case .PreUpdate:
            if queue.isEmpty {
                queue = state.keys.map{$0}
                for url in queue { state[url] = .Parsed }
                mystate = .Updating
            }
            fallthrough

        case .Updating:
            if queue.isEmpty {
                mystate = .Done
                fallthrough
            }
            let url = queue.remove(at: 0)
            set.remove(url)
            return (url, state[url]!)

        case .Done:
            return nil
        }
    }

    func push(_ url: URL) {
        guard !set.contains(url) else { return } // already queued for something
        guard state[url] == nil else { return }  // don't fetch more than once
        set.insert(url)
        queue.append(url)
        state[url] = .Unknown
    }

    func push(_ url: URL, state: UpdateState) {
        assert(!set.contains(url))
        self.state[url] = state
        queue.append(url)
        set.insert(url)
    }

    func set(done url: URL) {
        assert(state[url] == .Parsed)
        state[url] = .Updated
    }

    enum UpdateState {
        case Unknown
        case Fetched
        case Parsed
        case Updated
    }
}
