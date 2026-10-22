import Foundation

/// A burst of wakeups only needs one tick to drain the pending runtime work.
final class RuntimeWakeup {
    private let source: DispatchSourceUserDataAdd

    init(queue: DispatchQueue = .main, tick: @escaping () -> Void) {
        source = DispatchSource.makeUserDataAddSource(queue: queue)
        source.setEventHandler(handler: tick)
        source.resume()
    }

    func schedule() {
        source.add(data: 1)
    }

    deinit {
        source.cancel()
    }
}
