import Foundation

@main
struct WakeupBenchmark {
    static func main() {
        let count = 100_000
        for batched in [false, true] {
            let queue = DispatchQueue(label: "wakeup-benchmark")
            let done = DispatchSemaphore(value: 0)
            var ticks = 0
            let wakeup = RuntimeWakeup(queue: queue) {
                ticks += 1
                if ticks == count { done.signal() }
            }
            let start = DispatchTime.now().uptimeNanoseconds
            queue.sync {
                for index in 0..<count {
                    if batched {
                        wakeup.schedule()
                    } else {
                        queue.async {
                            ticks += 1
                            if index == count - 1 { done.signal() }
                        }
                    }
                }
            }
            done.wait()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            queue.sync {
                print("\(batched ? "batched" : "baseline"): \(count) wakeups, \(ticks) ticks, \(String(format: "%.2f", elapsed)) ms")
            }
            withExtendedLifetime(wakeup) {}
        }
    }
}
