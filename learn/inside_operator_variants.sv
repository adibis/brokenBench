// =================================================================================================
// write three `inside` constraints from scratch, three different set shapes
// =================================================================================================
//
// `inside` takes a set on its right-hand side, and that set can be built three different ways:
//
//   a plain list of values      -- x inside {1, 2, 3}
//   a range mixed with values   -- x inside {[10:20], 255}
//   a range with variable ends  -- x inside {[lo:hi]}          (lo/hi don't have to be literals)
//
// Same operator every time, always wrapped in braces, entries separated by commas, a range
// written as [low:high] with low on the left.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so mode, address, and val each land in their intended set on every
// randomize() call.
//
//   1. `mode` must be one of exactly 0, 2, 4, or 8 -- nothing else.
//   2. `address` must be either between 10 and 20 (inclusive), or exactly 255 -- nothing else.
//   3. `val` must fall between `low_bound` and `high_bound` (inclusive) -- using the two
//      variables below, not the literal numbers they currently hold.
// -------------------------------------------------------------------------------------------------
class cfg_item;
  rand bit [3:0] mode;
  rand bit [7:0] address;
  rand bit [7:0] val;

  bit [7:0] low_bound = 5;
  bit [7:0] high_bound = 15;

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    cfg_item item = new();

    for (int i = 0; i < 20; i++) begin
      int ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d -- is low_bound <= high_bound?", i);
        $fatal(1);
      end
      if (!(item.mode inside {0, 2, 4, 8})) begin
        $display("FAIL: mode=%0d is not in {0,2,4,8} at call %0d", item.mode, i);
        $fatal(1);
      end
      if (!(item.address inside {[10 : 20], 255})) begin
        $display("FAIL: address=%0d is not in [10:20] or 255 at call %0d", item.address, i);
        $fatal(1);
      end
      if (item.val < 5 || item.val > 15) begin
        $display("FAIL: val=%0d is not in [5:15] at call %0d", item.val, i);
        $fatal(1);
      end
    end

    $display("PASS: mode/address/val all stayed in their intended sets across 20 calls");
    $finish;
  end
endmodule
