import Foundation

public class NewPlane {
    // `Engine` is defined in Swift.
    var engine: Engine? = nil
    // The following types are defined in Objective-C.
    var pilot: Pilot? = nil
    var cabinClass: CabinClass? = nil
    var hasTrolleyService: Bool {
        return cabinClass != nil && cabinClass != .economyClass
    }

    public init() {}
}
