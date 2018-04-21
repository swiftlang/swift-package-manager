/*
 This source file is part of the Swift.org open source project

 Copyright 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel
import PackageGraph

/// Make file generator.
public final class MakefileGenerator {

    /// The package graph.
    let graph: PackageGraph

    /// The package root.
    let packageRoot: AbsolutePath

    /// The filesystem to operate on.
    let fs: FileSystem

    public init(
        _ graph: PackageGraph,
        packageRoot: AbsolutePath,
        fs: FileSystem = localFileSystem
    ) {
        self.graph = graph
        self.packageRoot = packageRoot
        self.fs = fs
    }

    /// Generates the Makefile at the given path.
    public func generateMakefile(at makefilePath: AbsolutePath) throws {
        let stream = BufferedOutputByteStream()

        appendPreamble(to: stream)
        appendAllRule(to: stream)
        appendCleanRule(to: stream)

        let linuxMainTarget = graph.allProducts.first(where: { $0.type == .test })?.linuxMainTarget

        // Get the list of all targets.
        let targets: [ResolvedTarget] = {
            var targets = graph.allTargets
            if let linuxMain = linuxMainTarget {
                targets.insert(linuxMain)
            }
            return targets.sorted(by: { $0.name < $1.name })
        }()

        for target in targets {
             switch target.underlyingTarget {
             case is SwiftTarget:
                appendSwiftRule(target, linuxOnly: target == linuxMainTarget, stream: stream)
             case is ClangTarget:
                appendClangRule(target, stream: stream)
             case is SystemLibraryTarget:
                 break
             default:
                 fatalError("unhandled \(target.underlyingTarget)")
             }
        }

        // Add the target dependencies at the end when all target specific
        // variables are defined.
        appendTargetDependencies(targets, to: stream)

        // Add products.
        for product in graph.allProducts.sorted(by: { $0.name < $1.name }) {
            appendProductRule(product, to: stream)
        }

        stream <<< "\n"

        // Write to disk.
        try fs.createDirectory(makefilePath.parentDirectory, recursive: true)
        try fs.writeFileContents(makefilePath, bytes: stream.bytes)
        try createUtils(at: makefilePath.parentDirectory.appending(component: "utils.py"))
    }

    /// Returns the targets that should be linked in this product.
    private func recursiveDependencies(of product: ResolvedProduct) -> [ResolvedTarget] {
        let nodes = product.targets.map(ResolvedTarget.Dependency.target)
        let allTargets: [ResolvedTarget] = try! topologicalSort(nodes, successors: { dependency in
            switch dependency {
            case .target(let target):
                return target.dependencies
            case .product:
                return []
            }
        }).compactMap({ dependency in
            switch dependency {
            case .target(let target):
                return target
            case .product:
                return nil
            }
        })

        var targetsToLink: [ResolvedTarget] = []
        for target in allTargets {
            switch target.type {
            // Include executable and tests only if they're top level contents 
            // of the product. Otherwise they are just build time dependency.
            case .executable, .test:
                if product.targets.contains(target) {
                    targetsToLink.append(target)
                }
            // Library targets should always be included.
            case .library:
                targetsToLink.append(target)
            case .systemModule:
                continue
            }
        }

        if product.type == .test {
            product.linuxMainTarget.map { targetsToLink.append($0) }
        }

        return targetsToLink
    }

    private func appendProductRule(_ product: ResolvedProduct, to stream: OutputByteStream) {
        // FIXME: We don't support libary products currently.
        if case .library = product.type {
            return
        }

        stream <<< "\n"
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
        stream <<< "# Product: " <<< product.name <<< "\n"

        // Variables.
        stream <<< product.makeVar("EXE") <<< " := "
        stream <<< "$(BUILD_DIR)/" <<< product.name
        stream <<< "\n"

        // Phony rule.
        stream <<< "\n"
        stream <<< ".PHONY: " <<< product.ruleName <<< "\n"
        stream <<< product.ruleName <<< ": " <<< product.makeVarSub("EXE") <<< "\n"

        // Compute the object that needs to be linked.
        let objVarSubs = recursiveDependencies(of: product).map({ $0.makeVarSub("OBJS") }).joined(separator: " ")

        // Main rule.
        stream <<< "\n"
        stream <<< product.makeVarSub("EXE") <<< ": " <<< objVarSubs <<< "\n"

        stream <<< "\t@echo Linking " <<< product.name <<< "\n"

        // This is only required for macOS to create the bundle structure.
        if product.type == .test {
            stream <<< "\t@mkdir -p $(dir \(product.makeVarSub("EXE")))" <<< "\n"
        }

        // Product specific args.
        let productArgs: [String]
        switch product.type {
        case .executable:
            productArgs = ["-emit-executable"]
        case .test:
            productArgs = ["$(TEST_LINKER_ARGS)"]
        case .library:
            productArgs = []
        }

        stream <<< """
            \t@$(SWIFT_EXEC) -target $(TARGET) -sdk $(SDKROOT) \
            $(EXTRA_SWIFT_FLAGS) -g -L $(BUILD_DIR) -o \(product.makeVarSub("EXE")) \
            -module-name \(product.name) \(productArgs.joined(separator: " ")) \(objVarSubs)
            """
        stream <<< "\n"
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
    }

    private func appendTargetDependencies(_ targets: [ResolvedTarget], to stream: OutputByteStream) {
        stream <<< "\n"
        stream <<< "# Dependencies" <<< "\n"
        for target in targets {
             switch target.underlyingTarget {
             case is SwiftTarget:
                appendTargetDependency(target, stream: stream)
             case is ClangTarget:
                 break
             case is SystemLibraryTarget:
                 break
             default:
                 fatalError("unhandled \(target.underlyingTarget)")
             }
        }
    }

    private func appendTargetDependency(_ target: ResolvedTarget, stream: OutputByteStream) {
        // Add dependencies.
        for dependency in target.dependencies {
            switch dependency {
            case .target(let dependencyTarget):
                stream <<< target.makeVarSub("SWIFT_MODULE") <<< ": " <<< dependencyTarget.makeVarSub("SWIFT_MODULE") <<< "\n"
            case .product:
                fatalError("Unsupported")
            }
        }
    }

    private func appendSwiftRule(_ target: ResolvedTarget, linuxOnly: Bool, stream: OutputByteStream) {
        stream <<< "\n"
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
        if linuxOnly {
            stream <<< "ifeq ($(shell uname -s), Linux)\n"
        }
        stream <<< "# Target: " <<< target.c99name <<< "\n"

        // Variables.
        stream <<< target.makeVar("TARGET_NAME") <<< " := " <<< target.c99name
        stream <<< "\n"

        stream <<< target.makeVar("SRCROOT") <<< " := "
        stream <<< "$(SRCROOT)/" <<< target.sources.root.relative(to: packageRoot).asString
        stream <<< "\n"

        stream <<< target.makeVar("SOURCES") <<< " := "
        stream <<< "$(wildcard " <<< target.makeVarSub("SRCROOT") <<< "/*.swift)"
        stream <<< "\n"

        stream <<< target.makeVar("TEMP_DIR") <<< " := "
        stream <<< "$(BUILD_DIR)/" <<< target.makeVarSub("TARGET_NAME") <<< ".build"
        stream <<< "\n"

        stream <<< target.makeVar("SRCLIST") <<< " := "
        stream <<< target.makeVarSub("TEMP_DIR") <<< "/sourceslist"
        stream <<< "\n"

        stream <<< target.makeVar("OUTPUTFILEMAP") <<< " := "
        stream <<< target.makeVarSub("TEMP_DIR") <<< "/output-file-map.json"
        stream <<< "\n"

        stream <<< target.makeVar("SWIFT_MODULE") <<< " := "
        stream <<< "$(BUILD_DIR)/" <<< target.makeVarSub("TARGET_NAME") <<< ".swiftmodule"
        stream <<< "\n"

        stream <<< target.makeVar("OBJS") <<< " := "
        stream <<< "$(subst " <<< target.makeVarSub("SRCROOT") <<< "," 
        stream <<< target.makeVarSub("TEMP_DIR") <<< ","
        stream <<< "$(" <<< target.makeVar("SOURCES") <<< ":%.swift=%.swift.o))"
        stream <<< "\n"

        // Note: Since this uses variables which might not be definedyet , use
        // = instead of := for assignment.
        stream <<< target.makeVar("INCLUDE_PATHS") <<< " = "
        for dependency in target.recursiveDependencies {
            switch dependency.underlyingTarget {
            case let underlyingTarget as ClangTarget where underlyingTarget.type == .library:
                stream <<< "-I\(dependency.makeVarSub("INCLUDE_DIR")) "
            default: break
            }
        }
        stream <<< "\n"

        // Append any target specific flag.
        let targetTypeFlags = target.type != .executable ? "-parse-as-library" : ""

        // Phony rule.
        stream <<< "\n"
        stream <<< ".PHONY: " <<< target.ruleName <<< "\n"
        stream <<< target.ruleName <<< ": " <<< target.makeVarSub("SWIFT_MODULE") <<< "\n"

        // Main rule.
        stream <<< "\n"
        stream <<< target.makeVarSub("SWIFT_MODULE") <<< ": "
        stream <<< target.makeVarSub("SOURCES") <<< " " <<< target.makeVarSub("OUTPUTFILEMAP") <<< "\n"
        stream <<< "\t@echo Compile Swift Module " <<< target.makeVarSub("TARGET_NAME")
        stream <<< "\n"

        stream <<< """
            \t@$(SWIFT_EXEC) -module-name \(target.makeVarSub("TARGET_NAME")) \
            -incremental -emit-dependencies -emit-module \
            -emit-module-path \(target.makeVarSub("SWIFT_MODULE")) \
            -output-file-map \(target.makeVarSub("OUTPUTFILEMAP")) \
            -num-threads $(NUM_THREADS) -I $(BUILD_DIR) -swift-version 4 \
            -c \(target.makeVarSub("SOURCES")) \
            -target $(TARGET) -sdk $(SDKROOT) $(EXTRA_SWIFT_FLAGS) $(SWIFT_CONFIG_FLAGS) \
            -j$(NUM_THREADS) -DSWIFT_PACKAGE \
            \(target.makeVarSub("INCLUDE_PATHS")) \(targetTypeFlags) \
            -module-cache-path $(BUILD_DIR)/ModuleCache
            \t@touch \(target.makeVarSub("SWIFT_MODULE"))

            """

        // Swift objects depend on module.
        stream <<< "\n"
        stream <<< target.makeVarSub("OBJS") <<< ": "
        stream <<< target.makeVarSub("SWIFT_MODULE") <<< "\n"

        // Output file map.
        stream <<< "\n"
        stream <<< target.makeVarSub("OUTPUTFILEMAP") <<< ": "
        // FIXME: This is a bit wrong. We don't want to depend on list of
        // sources and not their mod time.
        stream <<< target.makeVarSub("SOURCES") <<< "\n"

        stream <<< """
            \t@echo Generating output file map for \(target.makeVarSub("TARGET_NAME"))
            \t@mkdir -p \(target.makeVarSub("TEMP_DIR"))
            \t@echo > \(target.makeVarSub("SRCLIST"))
            \t@for source in \(target.makeVarSub("SOURCES")); do \\
            \t\techo $$source >> \(target.makeVarSub("SRCLIST")) ; \\
            \tdone
            \t@python $(UTILS) \(target.makeVarSub("SRCLIST"))

            """

        if linuxOnly {
            stream <<< "endif\n"
        }
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
    }

    private func appendClangRule(_ target: ResolvedTarget, stream: OutputByteStream) {
        stream <<< "\n"
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
        stream <<< "# Target: " <<< target.c99name <<< "\n"

        // Variables.
        stream <<< target.makeVar("TARGET_NAME") <<< " := " <<< target.c99name
        stream <<< "\n"

        stream <<< target.makeVar("SRCROOT") <<< " := "
        stream <<< "$(SRCROOT)/" <<< target.sources.root.relative(to: packageRoot).asString
        stream <<< "\n"

        stream <<< target.makeVar("INCLUDE_DIR") <<< " := "
        stream <<< target.makeVarSub("SRCROOT") <<< "/include"
        stream <<< "\n"

        stream <<< target.makeVar("SOURCES") <<< " := "
        stream <<< "$(wildcard " <<< target.makeVarSub("SRCROOT") <<< "/*.c)"
        stream <<< "\n"

        stream <<< target.makeVar("TEMP_DIR") <<< " := "
        stream <<< "$(BUILD_DIR)/" <<< target.makeVarSub("TARGET_NAME") <<< ".build"
        stream <<< "\n"

        stream <<< target.makeVar("OBJS") <<< " := "
        stream <<< "$(subst " <<< target.makeVarSub("SRCROOT") <<< "," 
        stream <<< target.makeVarSub("TEMP_DIR") <<< ","
        stream <<< "$(" <<< target.makeVar("SOURCES") <<< ":%.c=%.c.o))"
        stream <<< "\n"

        stream <<< target.makeVar("INCLUDE_PATHS") <<< " = "
        stream <<< "\n\n"

        /// Method to create a rule for every object.
        stream <<< """
            define \(target.makeVar("TARGET_RULE"))
            SRC = $(1)
            OBJ = $$(subst $(2),$(3),$$(SRC:%.c=%.c.o))
            DEPS = $$(OBJ:.o=.d)

            """
        stream <<< """
            $$(OBJ):
            \t@echo Compile $$@
            \t@mkdir -p $\(target.makeVarSub("TEMP_DIR"))
            \t@$$(CC) --sysroot $$(SDKROOT) \
            $$(CLANG_PLATFORM_FLAGS) \
            $$(EXTRA_CC_FLAGS) \
            $$(CLANG_CONFIG_FLAGS) -DSWIFT_PACKAGE=1 -fblocks -fmodules \
            -fmodule-name=$\(target.makeVarSub("TARGET_NAME")) \
            -I $\(target.makeVarSub("INCLUDE_DIR")) \
            -fmodules-cache-path=$$(BUILD_DIR)/ModuleCache \
            -MD -MT dependencies -MF $$(DEPS) -c $(1) -o $$@
            endef
            """
        stream <<< "\n\n"

        // Create rule for each source file.
        stream <<< "$(foreach source,"
        stream <<< target.makeVarSub("SOURCES")
        stream <<< ",$(eval $(call "
        stream <<< target.makeVar("TARGET_RULE")
        stream <<< ", $(source), "
        stream <<< target.makeVarSub("SRCROOT")
        stream <<< ", "
        stream <<< target.makeVarSub("TEMP_DIR")
        stream <<< ")))"

        // Phony rule.
        stream <<< "\n\n"
        stream <<< ".PHONY: " <<< target.ruleName <<< "\n"
        stream <<< target.ruleName <<< ": " <<< target.makeVarSub("OBJS") <<< "\n"

        // Swift objects depend on sources.
        stream <<< "\n"
        stream <<< target.makeVarSub("OBJS") <<< ": "
        stream <<< target.makeVarSub("SOURCES") <<< "\n"
        stream <<< "# --------------------------------------------------------------- #" <<< "\n"
    }

    private func appendAllRule(to stream: OutputByteStream) {
        var allRules = graph.allTargets.map({ $0.ruleName })
        allRules += graph.allProducts.filter({ 
            if case .library = $0.type {
                return false
            }
            return true
        }).map({ $0.ruleName })

        stream <<< "\n"
        stream <<< ".PHONY: all" <<< "\n"
        stream <<< "all: " 
        stream <<< allRules.sorted().joined(separator: " ")
        stream <<< "\n"
        stream <<< "\t@echo --done--" <<< "\n"
    }

    private func appendCleanRule(to stream: OutputByteStream) {
        stream <<< "\n"
        stream <<< ".PHONY: clean" <<< "\n"
        stream <<< "clean: " <<< "\n"
        stream <<< "\trm -rf $(BUILD_DIR)" <<< "\n"
        stream <<< "\t@echo --cleaned--" <<< "\n"
    }

    private func appendPreamble(to stream: OutputByteStream) {
        stream <<< """
            # Follow POSIX standards.
            .POSIX:
            
            # Disable all inference rules.
            .SUFFIXES:
            
            # Compute platform specific variables.
            ifeq ($(shell uname -s), Darwin)
              CC := $(shell xcrun --sdk macosx --find clang)
              SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
              SWIFT_EXEC := $(shell xcrun --sdk macosx --find swiftc)
              FRAMEWORKS_DIR := $(shell xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks
              EXTRA_SWIFT_FLAGS := -F $(FRAMEWORKS_DIR)
              EXTRA_CC_FLAGS := -F $(FRAMEWORKS_DIR)
              TARGET := x86_64-apple-macosx10.10
              TEST_LINKER_ARGS := -Xlinker -bundle
              NUM_THREADS := $(shell sysctl -n hw.ncpu)
              CLANG_PLATFORM_FLAGS := -fobjc-arc -arch x86_64 -mmacosx-version-min=10.10
            else ifeq ($(shell uname -s), Linux)
              SDKROOT := /
              CC := $(shell which clang)
              SWIFT_EXEC := $(shell which swiftc)
              EXTRA_SWIFT_FLAGS :=
              EXTRA_CC_FLAGS :=
              TARGET := x86_64-unknown-linux
              TEST_LINKER_ARGS := -emit-executable -Xlinker -rpath=$ORIGIN
              NUM_THREADS := $(shell nproc --all)
              CLANG_PLATFORM_FLAGS :=
            endif

            MAKE_FILE_PATH := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
            SRCROOT := $(abspath $(MAKE_FILE_PATH)/..)
            BUILD_DIR_PATH := $(SRCROOT)/.build
            CONFIG := debug
            UTILS := $(MAKE_FILE_PATH)/utils.py
            BUILD_DIR := $(BUILD_DIR_PATH)/$(TARGET)/$(CONFIG)
            
            ifeq ($(CONFIG), debug)
              SWIFT_CONFIG_FLAGS := -Onone -g -enable-testing -DDEBUG
              CLANG_CONFIG_FLAGS := -g -DDEBUG=1 -O0
            else
              SWIFT_CONFIG_FLAGS := -O -enable-testing
              CLANG_CONFIG_FLAGS := -O2
            endif

            """
    }

    func createUtils(at utilsPath: AbsolutePath) throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import os
            import sys
            import codecs
            import json
            
            sources_file = str(sys.argv[1])
            sources = codecs.open(sources_file, encoding='utf-8', errors='strict').read().strip().split("\\n")
            
            build_dir = os.path.dirname(sources_file)
            output_file_map = os.path.join(build_dir, "output-file-map.json")
            
            output_file_dict = {}
            
            masterdeps = {
                "swift-dependencies": os.path.join(build_dir, "master.swiftdeps")
            }
            output_file_dict[""] = masterdeps
            
            for source in sources:
                filename = os.path.basename(source)
                filestem = os.path.splitext(filename)[0]
                data = {
                    "dependencies": os.path.join(build_dir, filestem + ".d"),
                    "object": os.path.join(build_dir, filename + ".o"),
                    "swiftmodule": os.path.join(build_dir, filestem + "~partial.swiftmodule"),
                    "swift-dependencies": os.path.join(build_dir, filestem + ".swiftdeps"),
                }
                output_file_dict[source] = data
            
            with open(output_file_map, 'w') as outfile:
                json.dump(output_file_dict, outfile)
            """

        try fs.writeFileContents(utilsPath, bytes: stream.bytes)
    }
}

// MARK :- Private make support

private protocol MakeRuleProtocol {
    /// The name to use for make variables.
    var makeName: String { get }
}

private extension MakeRuleProtocol {
    func makeVar(_ named: String) -> String {
        return makeName.uppercased() + "_" + named
    }

    func makeVarSub(_ named: String) -> String {
        return "$(" + makeVar(named) + ")"
    }

    var ruleName: String {
        return makeName.lowercased() + ".exe"
    }
}

extension ResolvedTarget: MakeRuleProtocol {
    var makeName: String {
        return c99name
    }
}

extension ResolvedProduct: MakeRuleProtocol {
    var makeName: String {
        return name
    }
}
