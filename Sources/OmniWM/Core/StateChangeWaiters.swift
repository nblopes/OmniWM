// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class StateChangeWaiters {
    static let shared = StateChangeWaiters()

    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var observers: [UInt64: @MainActor @Sendable () -> Void] = [:]
    private var nextObserverID: UInt64 = 0

    func next() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func observe(_ handler: @escaping @MainActor @Sendable () -> Void) -> () -> Void {
        let id = nextObserverID
        nextObserverID &+= 1
        observers[id] = handler
        return { MainActor.assumeIsolated { StateChangeWaiters.shared.observers[id] = nil } }
    }

    func signal() {
        let resumed = continuations
        continuations.removeAll()
        for continuation in resumed {
            continuation.resume()
        }
        for handler in observers.values {
            handler()
        }
    }
}
