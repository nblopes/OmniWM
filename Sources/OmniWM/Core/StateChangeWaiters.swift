// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class StateChangeWaiters {
    static let shared = StateChangeWaiters()

    private var continuations: [CheckedContinuation<Void, Never>] = []

    func next() async {
        await withCheckedContinuation { continuations.append($0) }
    }

    func signal() {
        let resumed = continuations
        continuations.removeAll()
        for continuation in resumed {
            continuation.resume()
        }
    }
}
