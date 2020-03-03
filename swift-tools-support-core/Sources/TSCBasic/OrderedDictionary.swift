/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A generic collection to store key-value pairs in the order they were inserted in.
///
/// This is modelled after the stdlib's Dictionary.
public struct OrderedDictionary<Key: Hashable, Value> {

    /// The element type of a dictionary: a tuple containing an individual
    /// key-value pair.
    public typealias Element = (key: Key, value: Value)

    /// The underlying storage for the OrderedDictionary.
    fileprivate var array: [Key]
    fileprivate var dict: [Key: Value]

    /// Create an empty OrderedDictionary object.
    public init() {
        self.array = []
        self.dict = [:]
    }

    /// Accesses the value associated with the given key for reading and writing.
    ///
    /// This *key-based* subscript returns the value for the given key if the key
    /// is found in the dictionary, or `nil` if the key is not found.
    public subscript(key: Key) -> Value? {
        get {
            return dict[key]
        }
        set {
            if let newValue = newValue {
                updateValue(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    /// Updates the value stored in the dictionary for the given key, or adds a
    /// new key-value pair if the key does not exist.
    ///
    /// Use this method instead of key-based subscripting when you need to know
    /// whether the new value supplants the value of an existing key. If the
    /// value of an existing key is updated, `updateValue(_:forKey:)` returns
    /// the original value.
    @discardableResult
    public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
        // If there is already a value for this key, replace and return the old value.
        if let oldValue = dict[key] {
            dict[key] = value
            return oldValue
        }

        // Otherwise, create a new entry.
        dict[key] = value
        array.append(key)
        return nil
    }

    /// Removes the given key and its associated value from the dictionary.
    ///
    /// If the key is found in the dictionary, this method returns the key's
    /// associated value.
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        guard let value = dict[key] else {
            return nil
        }
        dict[key] = nil
        array.remove(at: array.firstIndex(of: key)!)
        return value
    }

    /// An array containing just the values of the ordered dictionary.
    public var values: [Value] {
        return self.array.map { self.dict[$0]! }
    }

    /// Remove all key-value pairs from the ordered dictionary.
    public mutating func removeAll() {
        self.array.removeAll()
        self.dict.removeAll()
    }
}

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init()
        for element in elements {
            updateValue(element.1, forKey: element.0)
        }
    } 
}

extension OrderedDictionary: CustomStringConvertible {
    public var description: String {
        var string = "["
        for (idx, key) in array.enumerated() {
            string += "\(key): \(dict[key]!)"
            if idx != array.count - 1 {
                string += ", "
            }
        }
        string += "]"
        return string
    }
}

extension OrderedDictionary: RandomAccessCollection {
    public var startIndex: Int { return array.startIndex }
    public var endIndex: Int { return array.endIndex }
    public subscript(index: Int) -> Element {
        let key = array[index]
        let value = dict[key]!
        return (key, value)
    }
}
