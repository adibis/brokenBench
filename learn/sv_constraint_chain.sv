// =================================================================================================
// write three constraints from scratch, each with its own name
// =================================================================================================
//
// Each constraint block is a class member and needs its own name: two blocks with the same name
// are a redefinition error, not one combined constraint. A range needs `inside`; pinning a field
// to one value needs `==` (`=` isn't a constraint operator).
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, each in its own named constraint block:
//
//   1. priority_lo stays in [0:3].
//   2. priority_hi stays in [4:7].
//   3. mode always equals 2'b01.
// -------------------------------------------------------------------------------------------------
class sched_item;
  rand bit [2:0] priority_lo;
  rand bit [2:0] priority_hi;
  rand bit [1:0] mode;
  rand bit [7:0] delay;

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    sched_item item = new();
    bit [7:0] seen[5];
    bit all_same = 1;

    for (int i = 0; i < 5; i++) begin
      automatic int ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", i);
        $fatal(1);
      end
      if (item.priority_lo > 3 || item.priority_hi < 4) begin
        $display("FAIL: priority_lo=%0d priority_hi=%0d violates the range at call %0d",
                 item.priority_lo, item.priority_hi, i);
        $fatal(1);
      end
      if (item.mode !== 2'b01) begin
        $display("FAIL: mode=%b, expected mode==01 at call %0d", item.mode, i);
        $fatal(1);
      end
      seen[i] = item.delay;
    end

    for (int i = 1; i < 5; i++) if (seen[i] != seen[0]) all_same = 0;

    if (all_same) begin
      $display($sformatf({"FAIL: delay never changed across 5 randomize() calls (got %0d every ",
                          "time) -- is it actually declared `rand`?"}, seen[0]));
      $fatal(1);
    end

    $display("PASS: priority/mode held across 5 calls, delay varied: %p", seen);
    $finish;
  end
endmodule
