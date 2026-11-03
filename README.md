# Fan In

A Ruby implementation of the **Fan-In pattern** for merging multiple input streams into a single output stream without blocking the rest of the work.

Fan-in is useful when a system receives data from several sources and needs to process all results in one place while preserving the natural order of each source.

### How it works

`FanIn.fan_in(inputs)` accepts an array of enumerables and produces an output enumerator. Each input is consumed in its own thread, and values are pushed into a shared queue that is drained by the consumer.

The implementation keeps the ordering inside each input stream intact, while allowing the slowest source to be processed independently from the others. If one input fails, its error is reported as a structured result and the remaining inputs continue running.

### Features

* Merge multiple enumerables into a single stream
* Preserve the order within each source
* Continue processing healthy inputs even if one fails
* Stop reading inputs once the consumer stops early
* Thread-safe coordination via Ruby queues and threads
* Structured results with `ok?`, `value`, and `error`

### Tests

The RSpec suite covers:

* Merging multiple streams while keeping per-stream ordering
* Non-blocking behavior when one input is slower than the others
* Completion only after all inputs are finished
* Empty-input handling
* Error propagation from a failing channel without interrupting the rest
* Correct ordering of values before an error
* Completion when all inputs fail

The implementation is intentionally small and dependency-free, which makes the fan-in behavior easy to observe, test, and reuse.
