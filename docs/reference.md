# SystemVerilog reference notes

General SystemVerilog language semantics worth knowing, confirmed real and
independent of any particular tool -- not Verilator bugs. See
[README.md's "Real, current tool limitations"](../README.md#real-current-tool-limitations-found-while-building-this)
for those; this file is for things that are simply how the language works,
even when that's surprising.

- **A variable declared inside a loop's `begin...end` block, without the
  `automatic` keyword, defaults to *static* lifetime** (IEEE 1800-2023
  6.21) -- its initializer runs once, not on every iteration, so it
  silently accumulates instead of resetting. Looks exactly like a
  randomization bug until traced with real debug output. Declare
  loop-body-local accumulator variables `automatic`, or declare once
  outside the loop and assign (not re-declare) inside it.
