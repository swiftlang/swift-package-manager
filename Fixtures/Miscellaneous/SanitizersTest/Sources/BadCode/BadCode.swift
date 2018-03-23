import CLib

// This code properly crashes with just
//
//  swiftc -sanitize=thread
//
public func badSwift() -> Int32 {
    var nonatomic: Int32 = 0

    let pt = spawn { nonatomic += 1 }

    nonatomic += 1

    join(pt)

    return nonatomic
}

// This code only properly crashes with
//
//  swiftc -sanitize=thread -Xcc -fsanitize=thread
//
public func badSwiftWithBadC() -> Int32 {
    var nonatomic: Int32 = 0

    incrementInThread(&nonatomic)

    nonatomic += 1

    joinThread()

    return nonatomic
}

private func spawn(_ callback: @escaping () -> ()) -> pthread_t {
#if os(Linux)
    var pt: pthread_t = pthread_t()
#else
    var pt: pthread_t? = nil
#endif

    let box = BoxedCallback(callback)

    let res = pthread_create(&pt, nil, { p in
        let box = Unmanaged<BoxedCallback>.fromOpaque((p as UnsafeMutableRawPointer?)!.assumingMemoryBound(to: BoxedCallback.self)).takeRetainedValue()

        box.value()

        return nil
    }, Unmanaged.passRetained(box).toOpaque())

    precondition(res == 0, "Unable to create thread")

#if os(Linux)
    return pt
#else
    return pt!
#endif
}

private func join(_ pt: pthread_t) {
    pthread_join(pt, nil)
}

final class Box<T> {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}
typealias BoxedCallback = Box<()->()>
