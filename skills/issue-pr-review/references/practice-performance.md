# Performance practices

- **P1 No per-item I/O.** Fetch related data in one batched call (`IN (…)`, join, eager load), never a query, request or file read per item. *Check:* no query or network call inside a loop or per-item callback.
- **P2 No quadratic loops.** Over unbounded input, use a set or map instead of a search inside a loop, and a join instead of repeated concatenation. *Check:* no linear search inside such a loop.
- **P3 Load in pages.** A new list query, endpoint or rendered list has a limit or page; large files and result sets stream. *Check:* no read-everything call on unbounded input.
- **P4 Non-blocking async paths.** Async code uses non-blocking file, network and database calls and keeps CPU-heavy loops off the event loop. *Check:* no sync I/O or blocking sleep inside an async function.
- **P5 Measure speed work.** Speed work beyond P1–P4 and P8 targets a hot path the issue or a measurement names, with before and after numbers. *Check:* the numbers are reported.
- **P6 Index new query shapes.** A new filter, join or sort on a growing table has an index, or the gap is reported. *Check:* grep the schema for each such column.
- **P7 Bounded caches.** Every cache or collection the diff adds that grows at run time has a size limit or TTL and is invalidated on writes. *Check:* find both.
- **P8 Hoist invariant work.** Compile, parse or build once, outside the loop or handler, what does not change per item. *Check:* each expensive call in a new loop uses per-item data.
- **P9 Bounded fan-out and retries.** Per-item concurrency runs in bounded batches; a retry loop has a cap and backoff and surfaces the last error. *Check:* no unbounded `Promise.all(items.map(…))`.
- **P10 Narrow critical sections.** Hold a lock only around shared-state access, with no I/O or sleep inside. *Check:* every new critical section holds only in-memory work.
