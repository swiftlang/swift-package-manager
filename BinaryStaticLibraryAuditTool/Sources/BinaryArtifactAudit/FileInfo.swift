package import Foundation

package struct FileInfo {
    package let type: FileAttributeType
    package init(type: FileAttributeType) {
        self.type = type
    }

    package var isRegularFile: Bool { self.type == .typeRegular }

    package var isDirectory: Bool { self.type == .typeDirectory }
}
