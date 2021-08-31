//
//  PromiseCompletion.swift
//  PromiseCompletion
//
//  Created by pronebird on 30/08/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

/// Promise result type.
enum PromiseCompletion<Value> {
    /// Promise is finished with value.
    case finished(Value)

    /// Promise is cancelled.
    case cancelled

    /// Return the contained value, otherwise `nil`.
    var unwrappedValue: Value? {
        switch self {
        case .finished(let value):
            return value
        case .cancelled:
            return nil
        }
    }

    /// Map the contained value, producing new `PromiseCompletion` type.
    func map<NewValue>(_ transform: (Value) throws -> NewValue) rethrows -> PromiseCompletion<NewValue> {
        switch self {
        case .finished(let value):
            return .finished(try transform(value))
        case .cancelled:
            return .cancelled
        }
    }
}

extension PromiseCompletion: Equatable where Value: Equatable {
    static func == (lhs: PromiseCompletion<Value>, rhs: PromiseCompletion<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.finished(let lhsValue), .finished(let rhsValue)):
            return lhsValue == rhsValue
        case (.cancelled, .cancelled):
            return true
        case (.finished, .cancelled), (.cancelled, .finished):
            return false
        }
    }
}
