import struct PackageDescription.Version
import struct PackageType.Manifest
import struct Utility.Path
import func POSIX.rename

class Updater {
    typealias URL = String

    private var pending: [URL: Checkout] = [:]
    private var graph: [URL: Range<Version>] = [:]
    private var queue: [URL] = []
    private var done: [URL: Version] = [:]

    init(dependencies: [(URL, Range<Version>)]) {
        for (url, range) in dependencies {
            queue.append(url)
            graph[url] = range
        }
    }

    /**
      Packages enter the system as URLs, they
      are then fed via calls to crank() to a manager of some sort,
      they then re-enter the system as Checkouts where they will
      later be updated as necessary. This may seem more elaborate
      than necessary, but it is the lowest level of abstraction
      considering packages may not be cloned yet (new dependencies)
      and not all inputs are packages (the rootManifest).
    */
    func crank() throws -> Ejecta? {
        guard !queue.isEmpty else { return nil }

        let url = queue.remove(at: 0)

        if let version = done[url] {

            // this dependency was already processed, lets check it still
            // fits in the graph. If not we throw though fixing this is a
            // TODO since the graph is still valid at this point.

            guard graph[url]! ~= version else {
                throw Error.LimitedFunctionality(url)
            }

            return .Processed(url, version)

        } else if let checkout = pending.removeValue(forKey: url) {

            // we have a Checkout object which means we can
            // fetch and update it

            func fetch() throws -> () throws -> Delta {
                try checkout.repo.fetch()
                return { () throws -> Delta in

                    let clamp = self.graph[checkout.url]!
                    let versions = checkout.repo.versions.filter{ $0.isStable && clamp ~= $0 }.sorted()
                    guard let newVersion = versions.last else {
                        throw Error.GraphCannotBeSatisfied(dependency: checkout.url)
                    }

                    self.done[url] = newVersion

                    if newVersion == checkout.version {
                        return .NoChange(checkout.url, checkout.version)
                    } else {
                        let oldVersion = checkout.version
                        let newpath = Path.join(checkout.repo.path, "../\(checkout.name)-\(newVersion)").normpath
                        try checkout.repo.set(branch: newVersion)
                        try rename(old: checkout.repo.path, new: newpath)
                        return .Changed(checkout.url, oldVersion, newVersion)
                    }
                }
            }
            return .Pending(fetch)

        } else {

            // we have a URL and a range of versions that the
            // package at that URL is allowed to be part of

            return .PleaseQueue(url, { (checkout: Checkout) throws -> Void in
                pending[url] = checkout  // -----------------> queue for updates
                queue.append(url)  // -----------------------> back in the queue!
                for (url, versionRange) in checkout.deps {  // queue deps
                    queue.append(url)
                    guard let clamp = (graph[url] ?? Version.maxRange).constrained(to: versionRange) else {
                        throw Error.GraphCannotBeSatisfied(dependency: url)
                    }
                    graph[url] = clamp
                }
            })
        }
    }

    enum Error: ErrorProtocol {
        case GraphCannotBeSatisfied(dependency: String)
        case LimitedFunctionality(String)
    }

    enum Ejecta {
        case Processed(URL, Version)
        case Pending(() throws -> () throws -> Delta)
        case PleaseQueue(URL, @noescape (Checkout) throws -> Void)
    }

    enum Delta {
        case NoChange(URL, Version)
        case Changed(URL, Version, Version)
    }
}
