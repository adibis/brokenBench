// 016: := vs :/ inside a dist clause
//
// `dist` weights aren't as simple as "bigger number, more likely." `value
// := weight` assigns that weight to each individual value written,
// including every value inside a range -- so `[1:3] := 1` gives 1, 2,
// and 3 a weight of 1 each, three separate buckets. `value :/ weight`
// divides the weight across the range instead, so `[1:3] :/ 1` treats
// the whole range as ONE bucket worth 1, split three ways. Writing := on
// a range when you meant "this whole range together should be as likely
// as this single value" gives every value in the range far more combined
// weight than intended.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class priority_item;
  rand bit [1:0] prio;
  // intent: priority 0 should come up about as often as 1, 2, and 3
  // *combined* -- a rough 50/50 split between "urgent" and "everything else"
  constraint c_prio { prio dist {0 := 1, [1:3] := 1}; }
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
      $display("FAIL: priority==0 came up %0d/%0d times (%0d%%), expected roughly 50%%", zero_count, total, (zero_count*100)/total);
      $fatal(1);
    end else begin
      $display("PASS: priority==0 came up %0d%% of the time, roughly the intended 50/50 split", (zero_count*100)/total);
      $finish;
    end
  end
endmodule
