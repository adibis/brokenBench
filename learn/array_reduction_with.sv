// =================================================================================================
// write two `with`-transformed array reduction constraints from scratch
// =================================================================================================
//
// Array reduction methods (`sum()`, `product()`, `and()`, `or()`, `xor()`) collapse a whole array
// down to one value. On their own they reduce the raw elements -- `arr.sum()` adds up whatever's
// actually in the array. Adding `with (expression)` changes what gets reduced: the expression is
// evaluated once per element (the implicit name `item` stands in for that element's value), and
// the reduction combines the RESULTS of the expression instead of the raw elements.
//
// That makes `sum() with (...)` a way to count: `arr.sum() with (item == N ? 1 : 0)` turns every
// element into a 1 (if it matches) or 0 (if it doesn't), and summing those 1s and 0s gives you
// exactly how many elements equal N -- without touching what any individual element's value is.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write two constraints from scratch, each using sum() with (...) to count matching elements:
//
//   1. exactly 2 of the 8 elements in levels must equal 3.
//   2. exactly 3 of the 8 elements in levels must equal 0.
// -------------------------------------------------------------------------------------------------
class bucket_item;
  rand bit [1:0] levels[8];
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    bucket_item item = new();
    bit [1:0] first_seen[8];
    bit varied = 0;

    for (int t = 0; t < 20; t++) begin
      automatic int ok = item.randomize();
      automatic int cnt3 = 0;
      automatic int cnt0 = 0;

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", t);
        $fatal(1);
      end

      foreach (item.levels[i]) begin
        if (item.levels[i] == 3) cnt3++;
        if (item.levels[i] == 0) cnt0++;
      end

      if (cnt3 != 2) begin
        $display("FAIL: %0d elements equal 3 at call %0d, expected exactly 2", cnt3, t);
        $fatal(1);
      end

      if (cnt0 != 3) begin
        $display("FAIL: %0d elements equal 0 at call %0d, expected exactly 3", cnt0, t);
        $fatal(1);
      end

      if (t == 0) first_seen = item.levels;
      else foreach (item.levels[i]) if (item.levels[i] != first_seen[i]) varied = 1;
    end

    if (!varied) begin
      $display("FAIL: levels was the exact same arrangement every call across 20 calls");
      $fatal(1);
    end

    $display("PASS: every call had exactly 2 threes and 3 zeros, arrangement varied");
    $finish;
  end
endmodule
