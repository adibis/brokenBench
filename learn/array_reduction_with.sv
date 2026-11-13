// =================================================================================================
// write two `with`-transformed array reduction constraints from scratch
// =================================================================================================
//
// Reduction methods (`sum()`, `product()`, `and()`, `or()`, `xor()`) collapse an array to
// one value. With `with (expr)`, they reduce the expression's result for each element instead of
// the element itself; `item` names the element inside the expression.
//
// That makes `sum() with` a counter: `arr.sum() with (item == N ? 1 : 0)` is the number of
// elements equal to N.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, each a constraint using sum() with (...):
//
//   1. Exactly 2 of the 8 elements in levels equal 3.
//   2. Exactly 3 of the 8 elements in levels equal 0.
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
