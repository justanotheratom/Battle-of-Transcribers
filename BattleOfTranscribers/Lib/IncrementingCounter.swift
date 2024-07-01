
import Foundation
import Atomics

struct IncrementingCounter {
    private var atomicCounter: ManagedAtomic<Int>

    init(initialValue: Int = 0) {
        atomicCounter = ManagedAtomic<Int>(initialValue)
    }

    func next() -> Int {
        return atomicCounter.wrappingIncrementThenLoad(ordering: .relaxed)
    }
    
    func read() -> Int {
        return atomicCounter.load(ordering: .relaxed)
    }
}
