// =================================================================================================
// write three constraints from scratch, each with its own name
// =================================================================================================
//
// Every constraint block in a class needs its own name, the same as any other class member --
// two blocks sharing a name isn't two constraints being combined, it's a redefinition error.
// Beyond that, this is just ordinary constraint-writing: a range needs `inside`, and a field
// pinned to one exact value needs `==`, not `=` (which isn't a valid constraint operator at all).
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write three constraints from scratch, each in its own uniquely-named constraint block:
//
//   1. priority_lo must stay in [0:3].
//   2. priority_hi must stay in [4:7].
//   3. mode must always equal 2'b01.
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
