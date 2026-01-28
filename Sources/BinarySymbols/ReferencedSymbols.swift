//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package struct ReferencedSymbols {
    package private(set) var defined: Set<String>
    package private(set) var undefined: Set<String>

    package init() {
        // Some symbols are defined by linker directly by convention and need to be assumed defined.
        // The list below was pulled from
        // https://github.com/llvm/llvm-project/blob/177e38286cd61a7b5a968636e1f147f128dd25a2/lld/ELF/Config.h#L632
        self.defined = [
            "__bss_start",
            "_etext",
            "etext",
            "_edata",
            "edata",
            "_end",
            "end",
            "_GLOBAL_OFFSET_TABLE_",
            "_gp",
            "_gp_disp",
            "__gnu_local_gp",
            "__global_pointer$",
            "__rela_iplt_start",
            "__rela_iplt_end",
            "_TLS_MODULE_BASE",
        ]
        self.undefined = []
    }

    mutating func addUndefined(_ name: String) {
        guard !self.defined.contains(name) else {
            return
        }
        self.undefined.insert(name)
    }

    mutating func addDefined(_ name: String) {
        self.defined.insert(name)
        self.undefined.remove(name)
    }
}
