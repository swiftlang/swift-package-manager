import Dispatch

public func executeRace() {
    var global = 5

    let sema = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        global = 6
        sema.signal()
    }

    global = 7
    sema.wait()

    print(global)
}
