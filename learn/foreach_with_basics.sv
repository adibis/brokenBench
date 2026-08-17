// =================================================================================================
// write a foreach constraint, and an inline randomize() with{} constraint
// =================================================================================================
//
// `foreach (arr[i]) ...` introduces `i` as a loop variable scoped to that constraint, usable to
// index the same array on each pass. Separately, `randomize() with { ... }` adds a one-off
// constraint for a single call without touching the class itself -- useful for pinning a `rand`
// field to a specific value just for that call.
//
// Fix the class and function below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraint and the inline randomize() call from scratch:
//
//   1. every element of lens must stay in [1:100].
//   2. tag_item() must randomize item so that tag ends up equal to the target argument.
// -------------------------------------------------------------------------------------------------
class pkt_item;
  rand bit [7:0] lens[4];
  rand bit [7:0] tag;
  // write constraints here
endclass

function void tag_item(pkt_item it, bit [7:0] target);
  // write this function so item.tag always ends up equal to target
endfunction

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    pkt_item item = new();
    bit bad_found = 0;

    for (int t = 0; t < 10; t++) begin
      bit [7:0] target = 8'(t + 1);
      tag_item(item, target);

      if (item.tag != target) begin
        $display("FAIL: target=%0d but item.tag=%0d on call %0d", target, item.tag, t);
        bad_found = 1;
      end

      foreach (item.lens[i]) begin
        if (item.lens[i] < 1 || item.lens[i] > 100) begin
          $display("FAIL: lens[%0d]=%0d is outside [1:100] on call %0d", i, item.lens[i], t);
          bad_found = 1;
        end
      end
    end

    if (bad_found) $fatal(1);

    $display("PASS: lens stayed in [1:100] and tag matched its target on every call");
    $finish;
  end
endmodule
