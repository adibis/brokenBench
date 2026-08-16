// =================================================================================================
// a reduction constraint on an array whose size is itself random
// =================================================================================================
//
// `data.sum() == 100` is a completely ordinary constraint on its own.
// So is sizing a dynamic array with `data.size() == n` where `n` is
// itself `rand`. Putting them in the same class is where this stops
// working: on the current toolchain, a `rand`-sized dynamic array
// combined with a reduction method (`.sum()`, `.product()`) over its own
// contents fails to solve, every time, regardless of `solve ... before`
// ordering hints. This is a real, documented class of constrained-random
// gotcha (array reduction methods interacting badly with a size that
// isn't fixed yet), not a mistake specific to this file.
//
// A smarter ordering hint won't get you out of this one -- the actual
// fix changes what's `rand` in the first place. Ask what this exercise
// is actually trying to demonstrate about `.sum()` before assuming the
// array needs to stay dynamically sized to make that point.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the class so randomize() reliably produces a data array that sums to 100, every call.
// -------------------------------------------------------------------------------------------------
class buf_item;
  rand int unsigned n;
  rand int data[];
  constraint c_n     { n inside {[2:4]}; }
  constraint c_size  { data.size() == n; }
  constraint c_elem  { foreach (data[i]) data[i] inside {[0:50]}; }
  constraint c_sum   { data.sum() == 100; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    buf_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0");
      $fatal(1);
    end

    if (item.data.sum() != 100) begin
      $display("FAIL: data.sum()=%0d, expected 100", item.data.sum());
      $fatal(1);
    end

    foreach (item.data[i])
      if (item.data[i] < 0 || item.data[i] > 50) begin
        $display("FAIL: data[%0d]=%0d out of [0:50]", i, item.data[i]);
        $fatal(1);
      end

    $display("PASS: data=%p sums to %0d", item.data, item.data.sum());
    $finish;
  end
endmodule
