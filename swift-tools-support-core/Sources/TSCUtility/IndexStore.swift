/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCclibc

public final class IndexStore {

    public struct TestCaseClass {
        public var name: String
        public var module: String
        public var methods: [String]
    }

    let api: IndexStoreAPI

    var fn: indexstore_functions_t {
        return api.fn
    }

    let store: indexstore_t

    private init(store: indexstore_t, api: IndexStoreAPI) {
        self.store = store
        self.api = api
    }

    static public func open(store path: AbsolutePath, api: IndexStoreAPI) throws -> IndexStore {
        if let store = try api.call({ api.fn.store_create(path.pathString, &$0) }) {
            return IndexStore(store: store, api: api)
        }
        throw StringError("Unable to open store at \(path)")
    }

    public func listTests(inObjectFile object: AbsolutePath) throws -> [TestCaseClass] {
        // Get the records of this object file.
        let unitReader = try api.call{ fn.unit_reader_create(store, unitName(object: object), &$0) }
        let records = try getRecords(unitReader: unitReader)

        // Get the test classes.
        let testCaseClasses = try records.flatMap{ try self.getTestCaseClasses(forRecord: $0) }

        // Fill the module name and return.
        let module = fn.unit_reader_get_module_name(unitReader).str
        return testCaseClasses.map {
            var c = $0
            c.module = module
            return c
        }
    }

    private func getTestCaseClasses(forRecord record: String) throws -> [TestCaseClass] {
        let recordReader = try api.call{ fn.record_reader_create(store, record, &$0) }

        class TestCaseBuilder {
            var classToMethods: [String: Set<String>] = [:]

            func add(klass: String, method: String) {
                classToMethods[klass, default: []].insert(method)
            }

            func build() -> [TestCaseClass] {
                return classToMethods.map {
                    TestCaseClass(name: $0.key, module: "", methods: $0.value.sorted())
                }
            }
        }

        let builder = Ref(TestCaseBuilder(), api: api)

        let ctx = unsafeBitCast(Unmanaged.passUnretained(builder), to: UnsafeMutableRawPointer.self)
        _ = fn.record_reader_occurrences_apply_f(recordReader, ctx) { ctx , occ -> Bool in
            let builder = Unmanaged<Ref<TestCaseBuilder>>.fromOpaque(ctx!).takeUnretainedValue()
            let fn = builder.api.fn

            // Get the symbol.
            let sym = fn.occurrence_get_symbol(occ)

            // We only care about symbols that are marked unit tests and are instance methods.
            if fn.symbol_get_properties(sym) != UInt64(INDEXSTORE_SYMBOL_PROPERTY_UNITTEST.rawValue) {
                return true
            }
            if fn.symbol_get_kind(sym) != INDEXSTORE_SYMBOL_KIND_INSTANCEMETHOD {
                return true
            }

            let className = Ref("", api: builder.api)
            let ctx = unsafeBitCast(Unmanaged.passUnretained(className), to: UnsafeMutableRawPointer.self)

            _ = fn.occurrence_relations_apply_f(occ!, ctx) { ctx, relation in
                guard let relation = relation else { return true }
                let className = Unmanaged<Ref<String>>.fromOpaque(ctx!).takeUnretainedValue()
                let fn = className.api.fn

                // Look for the class.
                if fn.symbol_relation_get_roles(relation) != UInt64(INDEXSTORE_SYMBOL_ROLE_REL_CHILDOF.rawValue) {
                    return true
                }

                let sym = fn.symbol_relation_get_symbol(relation)
                className.instance = fn.symbol_get_name(sym).str
                return true
            }

            if !className.instance.isEmpty {
                let testMethod = fn.symbol_get_name(sym).str
                builder.instance.add(klass: className.instance, method: testMethod)
            }

            return true
        }

        return builder.instance.build()
    }

    private func getRecords(unitReader: indexstore_unit_reader_t?) throws -> [String] {
        let builder = Ref([String](), api: api)

        let ctx = unsafeBitCast(Unmanaged.passUnretained(builder), to: UnsafeMutableRawPointer.self)
        _ = fn.unit_reader_dependencies_apply_f(unitReader, ctx) { ctx , unit -> Bool in
            let store = Unmanaged<Ref<[String]>>.fromOpaque(ctx!).takeUnretainedValue()
            let fn = store.api.fn
            if fn.unit_dependency_get_kind(unit) == INDEXSTORE_UNIT_DEPENDENCY_RECORD {
                store.instance.append(fn.unit_dependency_get_name(unit).str)
            }
            return true
        }

        return builder.instance
    }

    private func unitName(object: AbsolutePath) -> String {
        let initialSize = 64
        var buf = UnsafeMutablePointer<CChar>.allocate(capacity: initialSize)
        let len = fn.store_get_unit_name_from_output_path(store, object.pathString, buf, initialSize)

        if len + 1 > initialSize {
            buf.deallocate()
            buf = UnsafeMutablePointer<CChar>.allocate(capacity: len + 1)
            _ = fn.store_get_unit_name_from_output_path(store, object.pathString, buf, len + 1)
        }

        defer {
            buf.deallocate()
        }

        return String(cString: buf)
    }
}

private class Ref<T> {
    let api: IndexStoreAPI
    var instance: T
    init(_ instance: T, api: IndexStoreAPI) {
        self.instance = instance
        self.api = api
    }
}

public final class IndexStoreAPI {

    /// The path of the index store dylib.
    private let path: AbsolutePath

    /// Handle of the dynamic library.
    private let dylib: DLHandle

    /// The index store API functions.
    fileprivate let fn: indexstore_functions_t

    fileprivate func call<T>(_ fn: (inout indexstore_error_t?) -> T) throws -> T {
        var error: indexstore_error_t? = nil
        let ret = fn(&error)

        if let error = error {
            if let desc = self.fn.error_get_description(error) {
                throw StringError(String(cString: desc))
            }
            throw StringError("Unable to get description for error: \(error)")
        }

        return ret
    }

    public init(dylib path: AbsolutePath) throws {
        self.path = path
#if os(Windows)
        let flags: DLOpenFlags = []
#elseif os(Android)
        let flags: DLOpenFlags = [.lazy, .local, .first]
#else
        let flags: DLOpenFlags = [.lazy, .local, .first, .deepBind]
#endif
        self.dylib = try dlopen(path.pathString, mode: flags)

        func dlsym_required<T>(_ handle: DLHandle, symbol: String) throws -> T {
            guard let sym: T = dlsym(handle, symbol: symbol) else {
                throw StringError("Missing required symbol: \(symbol)")
            }
            return sym
        }

        var api = indexstore_functions_t()
        api.store_create = try dlsym_required(dylib, symbol: "indexstore_store_create")
        api.store_get_unit_name_from_output_path = try dlsym_required(dylib, symbol: "indexstore_store_get_unit_name_from_output_path")
        api.unit_reader_create = try dlsym_required(dylib, symbol: "indexstore_unit_reader_create")
        api.error_get_description = try dlsym_required(dylib, symbol: "indexstore_error_get_description")
        api.unit_reader_dependencies_apply_f = try dlsym_required(dylib, symbol: "indexstore_unit_reader_dependencies_apply_f")
        api.unit_reader_get_module_name = try dlsym_required(dylib, symbol: "indexstore_unit_reader_get_module_name")
        api.unit_dependency_get_kind = try dlsym_required(dylib, symbol: "indexstore_unit_dependency_get_kind")
        api.unit_dependency_get_name = try dlsym_required(dylib, symbol: "indexstore_unit_dependency_get_name")
        api.record_reader_create = try dlsym_required(dylib, symbol: "indexstore_record_reader_create")
        api.symbol_get_name = try dlsym_required(dylib, symbol: "indexstore_symbol_get_name")
        api.symbol_get_properties = try dlsym_required(dylib, symbol: "indexstore_symbol_get_properties")
        api.symbol_get_kind = try dlsym_required(dylib, symbol: "indexstore_symbol_get_kind")
        api.record_reader_occurrences_apply_f = try dlsym_required(dylib, symbol: "indexstore_record_reader_occurrences_apply_f")
        api.occurrence_get_symbol = try dlsym_required(dylib, symbol: "indexstore_occurrence_get_symbol")
        api.occurrence_relations_apply_f = try dlsym_required(dylib, symbol: "indexstore_occurrence_relations_apply_f")
        api.symbol_relation_get_symbol = try dlsym_required(dylib, symbol: "indexstore_symbol_relation_get_symbol")
        api.symbol_relation_get_roles = try dlsym_required(dylib, symbol: "indexstore_symbol_relation_get_roles")

        self.fn = api
    }

    deinit {
        // FIXME: is it safe to dlclose() indexstore? If so, do that here. For now, let the handle leak.
        dylib.leak()
    }
}

extension indexstore_string_ref_t {
    fileprivate var str: String {
        return String(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: data),
            length: length,
            encoding: .utf8,
            freeWhenDone: false
        )!
    }
}
