import Foundation

/// Avoid allocating a main-queue block per wakeup. Every requested tick is
/// preserved because a tick can stop draining the mailbox early.
final class RuntimeWakeup {
    private let source: DispatchSourceUserDataAdd

    init(queue: DispatchQueue = .main, tick: @escaping () -> Void) {
        source = DispatchSource.makeUserDataAddSource(queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let pending = self.source.data
            let count = min(pending, 64)
            if pending > count { self.source.add(data: pending - count) }
            for _ in 0..<count { tick() }
        }
        source.resume()
    }

    func schedule() {
        source.add(data: 1)
    }

    deinit {
        source.cancel()
    }
}
