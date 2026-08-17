// =================================================================================================
// := vs :/ inside a dist clause
// =================================================================================================
//
// `dist` weights aren't as simple as "bigger number, more likely," and a
// range on the left-hand side changes what the weight even means --
// SystemVerilog gives you two different operators for it, and they don't
// do the same thing once the left side is a range instead of a single
// value. Read what each one actually distributes across a range, then
// look at what c_prio below is asking for -- priority 0 should come up
// about as often as 1, 2, and 3 *combined*, a rough 50/50 split. Run it
// and see how far off the observed split actually is before deciding
// which operator is doing what you think it's doing.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix c_prio so priority==0 comes up roughly 50% of the time across many calls.
// -------------------------------------------------------------------------------------------------
class priority_item;
  rand bit [1:0] prio;
  // intent: priority 0 should come up about as often as 1, 2, and 3
  // *combined* -- a rough 50/50 split between "urgent" and "everything else"
  constraint c_prio {
    prio dist {
      0 := 1,
      [1 : 3] := 1
    };
  }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    priority_item item = new();
    int zero_count = 0;
    int total = 20000;

    for (int i = 0; i < total; i++) begin
      void'(item.randomize());
      if (item.prio == 0) zero_count++;
    end

    // expect roughly 50% -- allow a wide band since this is statistical
    if (zero_count < (total * 40 / 100) || zero_count > (total * 60 / 100)) begin
      $display("FAIL: priority==0 came up %0d/%0d times (%0d%%), expected roughly 50%%",
               zero_count, total, (zero_count * 100) / total);
      $fatal(1);
    end else begin
      $display("PASS: priority==0 came up %0d%% of the time, roughly the intended 50/50 split",
               (zero_count * 100) / total);
      $finish;
    end
  end
endmodule
