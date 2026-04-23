//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageGraph
import PackageModel

extension PackagePIFBuilder {
    /// Computes the set of modules in `graph` that are reachable ONLY via
    /// host-only chains (macros, plugins, or executables whose transitive
    /// consumers are all plugins / other plugin tools).
    ///
    /// The PIF emitter uses this set to restrict `SUPPORTED_PLATFORMS` to
    /// `$(HOST_PLATFORM)`, preventing swift-build from compiling these
    /// modules for the run-destination SDK (e.g. wasm32), which is
    /// unnecessary and often impossible (e.g. `Dispatch`/`dup` unavailable
    /// on WASI).
    ///
    /// This is a PIF-level analysis — it does NOT mutate
    /// `ResolvedModule.platformConstraint`, which is shared with the native
    /// build system. Native's `Build/BuildPlan` uses its own destination
    /// computation and is unaffected.
    static func computeHostOnlyReachableModules(in graph: ModulesGraph) -> Set<ResolvedModule.ID> {
        let pluginTools = computePluginTools(in: graph)

        func isInherentlyHostOnly(_ module: ResolvedModule) -> Bool {
            switch module.type {
            case .macro, .plugin:
                return true
            case .test:
                return module.hasDirectMacroDependencies
            case .executable:
                return pluginTools.contains(module.id)
            default:
                return false
            }
        }

        // Iterative forward walk from root-package target-eligible modules.
        var targetReachable = Set<ResolvedModule.ID>()
        var worklist: [ResolvedModule] = []
        for package in graph.rootPackages {
            for module in package.modules where !isInherentlyHostOnly(module) {
                if targetReachable.insert(module.id).inserted {
                    worklist.append(module)
                }
            }
        }
        while let current = worklist.popLast() {
            for dep in current.dependencies {
                switch dep {
                case .module(let child, _):
                    if !isInherentlyHostOnly(child) && targetReachable.insert(child.id).inserted {
                        worklist.append(child)
                    }
                case .product(let product, _):
                    for child in product.modules where !isInherentlyHostOnly(child) {
                        if targetReachable.insert(child.id).inserted {
                            worklist.append(child)
                        }
                    }
                }
            }
        }

        // Host-only = every reachable module NOT in targetReachable.
        var hostOnly = Set<ResolvedModule.ID>()
        for module in graph.reachableModules where !targetReachable.contains(module.id) {
            hostOnly.insert(module.id)
        }
        return hostOnly
    }

    /// Identifies executable modules that are consumed ONLY by plugins or by
    /// other plugin tools (fixed-point). These are "plugin tools" — build-time
    /// helpers that run on the host, not consumer-facing executables. Used
    /// by `computeHostOnlyReachableModules` to stop target-reachability walks
    /// at plugin-tool boundaries.
    private static func computePluginTools(in graph: ModulesGraph) -> Set<ResolvedModule.ID> {
        // Build reverse-dep map and module lookup in one pass.
        var consumers: [ResolvedModule.ID: [ResolvedModule.ID]] = [:]
        var byId: [ResolvedModule.ID: ResolvedModule] = [:]
        for module in graph.reachableModules {
            byId[module.id] = module
            for dep in module.dependencies {
                switch dep {
                case .module(let child, _):
                    consumers[child.id, default: []].append(module.id)
                case .product(let product, _):
                    for child in product.modules {
                        consumers[child.id, default: []].append(module.id)
                    }
                }
            }
        }

        var pluginTools = Set<ResolvedModule.ID>()
        var changed = true
        while changed {
            changed = false
            for (id, module) in byId where module.type == .executable && !pluginTools.contains(id) {
                let cs = consumers[id] ?? []
                // Classify as plugin tool only if it has at least one consumer
                // AND every consumer is a plugin or an already-classified
                // plugin tool. Executables with no consumers (leaf root
                // executables) are NOT plugin tools — they're consumer-facing.
                guard !cs.isEmpty else { continue }
                let allHostOnlyConsumers = cs.allSatisfy { consumerId in
                    guard let consumer = byId[consumerId] else { return false }
                    return consumer.type == .plugin || pluginTools.contains(consumerId)
                }
                if allHostOnlyConsumers {
                    pluginTools.insert(id)
                    changed = true
                }
            }
        }
        return pluginTools
    }
}
