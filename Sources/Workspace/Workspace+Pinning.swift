//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Basics.ObservabilityScope
import class PackageGraph.PinsStore
import struct PackageModel.PackageReference
import struct PackageModel.ToolsVersion
import struct TSCUtility.Version

extension Workspace {
    /// Pins all of the current managed dependencies at their checkout state.
    func saveResolvedFile(
        pinsStore: PinsStore,
        dependencyManifests: DependencyManifests,
        originHash: String,
        rootManifestsMinimumToolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) throws {
        var dependenciesToPin = [ManagedDependency]()
        let requiredDependencies = try dependencyManifests.requiredPackages.filter(\.kind.isPinnable)
        for dependency in requiredDependencies {
            if let managedDependency = self.state.dependencies[comparingLocation: dependency] {
                dependenciesToPin.append(managedDependency)
            } else if let managedDependency = self.state.dependencies[dependency.identity] {
                observabilityScope
                    .emit(
                        info: "required dependency '\(dependency.identity)' from '\(dependency.locationString)' was not found in managed dependencies, using alternative location '\(managedDependency.packageRef.locationString)' instead"
                    )
                dependenciesToPin.append(ManagedDependency(packageRef: dependency, state: managedDependency.state, subpath: managedDependency.subpath))
            } else {
                observabilityScope
                    .emit(
                        warning: "required dependency '\(dependency.identity)' from '\(dependency.locationString)' was not found in managed dependencies and will not be recorded in resolved file"
                    )
            }
        }

        // try to load the pin store from disk so we can compare for any changes
        // this is needed as we want to avoid re-writing the resolved files unless absolutely necessary
        var needsUpdate = false
        if let storedPinStore = try? self.pinsStore.load() {
            // compare for any differences between the existing state and the stored one
            // subtle changes between versions of SwiftPM could treat URLs differently
            // in which case we don't want to cause unnecessary churn
            if dependenciesToPin.count != storedPinStore.pins.count {
                needsUpdate = true
            } else {
                for dependency in dependenciesToPin {
                    if let pin = storedPinStore.pins[comparingLocation: dependency.packageRef] {
                        if pin.state != PinsStore.Pin(dependency)?.state {
                            needsUpdate = true
                            break
                        }
                    } else {
                        needsUpdate = true
                        break
                    }
                }
            }
        } else {
            needsUpdate = true
        }

        // exist early is there is nothing to do
        if !needsUpdate {
            return
        }

        // reset the pinsStore and start pinning the required dependencies.
        pinsStore.unpinAll()
        for dependency in dependenciesToPin {
            pinsStore.pin(dependency)
        }

        observabilityScope.trap {
            try pinsStore.saveState(
                toolsVersion: rootManifestsMinimumToolsVersion,
                originHash: originHash
            )
        }

        // Ask resolved file watcher to update its value so we don't fire
        // an extra event if the file was modified by us.
        self.resolvedFileWatcher?.updateValue()
    }

    /// Watch the Package.resolved for changes.
    ///
    /// This is useful if clients want to be notified when the Package.resolved
    /// file is changed *outside* of libSwiftPM operations. For example, as part
    /// of a git operation.
    public func watchResolvedFile() throws {
        // Return if we're already watching it.
        guard self.resolvedFileWatcher == nil else { return }
        self
            .resolvedFileWatcher = try ResolvedFileWatcher(
                resolvedFile: self.location
                    .resolvedVersionsFile
            ) { [weak self] in
                self?.delegate?.resolvedFileChanged()
            }
    }
}

extension PinsStore {
    /// Pin a managed dependency at its checkout state.
    ///
    /// This method does nothing if the dependency is in edited state.
    func pin(_ dependency: Workspace.ManagedDependency) {
        if let pin = PinsStore.Pin(dependency) {
            self.add(pin)
        }
    }
}

extension PinsStore.Pin {
    fileprivate init?(_ dependency: Workspace.ManagedDependency) {
        switch dependency.state {
        case .sourceControlCheckout(.version(let version, let revision)):
            self.init(
                packageRef: dependency.packageRef,
                state: .version(version, revision: revision.identifier)
            )
        case .sourceControlCheckout(.branch(let branch, let revision)):
            self.init(
                packageRef: dependency.packageRef,
                state: .branch(name: branch, revision: revision.identifier)
            )
        case .sourceControlCheckout(.revision(let revision)):
            self.init(
                packageRef: dependency.packageRef,
                state: .revision(revision.identifier)
            )
        case .registryDownload(let version):
            self.init(
                packageRef: dependency.packageRef,
                state: .version(version, revision: .none)
            )
        case .edited, .fileSystem, .custom:
            // NOOP
            return nil
        }
    }
}

extension PackageReference.Kind {
    var isPinnable: Bool {
        switch self {
        case .remoteSourceControl, .localSourceControl, .registry:
            return true
        default:
            return false
        }
    }
}

extension PinsStore.PinState {
    func equals(_ checkoutState: CheckoutState) -> Bool {
        switch (self, checkoutState) {
        case (.version(let lversion, let lrevision), .version(let rversion, let rrevision)):
            return lversion == rversion && lrevision == rrevision.identifier
        case (.branch(let lbranch, let lrevision), .branch(let rbranch, let rrevision)):
            return lbranch == rbranch && lrevision == rrevision.identifier
        case (.revision(let lrevision), .revision(let rrevision)):
            return lrevision == rrevision.identifier
        default:
            return false
        }
    }

    func equals(_: Version) -> Bool {
        switch self {
        case .version(let version, _):
            return version == version
        default:
            return false
        }
    }
}

extension PinsStore.Pins {
    subscript(comparingLocation package: PackageReference) -> PinsStore.Pin? {
        if let pin = self[package.identity], pin.packageRef.equalsIncludingLocation(package) {
            return pin
        }
        return .none
    }
}
