// 018: post_randomize() quietly overwriting what the solver produced
//
// post_randomize() runs immediately after every successful .randomize()
// call, which makes it tempting to use for "just in case" cleanup --
// clamping a value, rounding it, forcing a default. The trap is that this
// runs unconditionally, after the constraint solver already did its job,
// so a clamp that's a little too aggressive silently throws away
// everything the constraint solver actually solved for. randomize()
// still returns 1. Other fields in the class still vary normally. This
// one field just always ends up the same, for a reason that isn't
// visible anywhere in its own constraint block.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class gain_item;
  rand bit [7:0] gain;
  constraint c_range { gain inside {[10:200]}; }

  function void post_randomize();
    // meant to guard against an out-of-range value; the solver already
    // guarantees this range, so this always fires and always to the
    // same value
    if (gain < 250) gain = 100;
  endfunction
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    gain_item item = new();
    bit [7:0] seen[10];
    bit all_same = 1;

    for (int i = 0; i < 10; i++) begin
      void'(item.randomize());
      seen[i] = item.gain;
    end

    for (int i = 1; i < 10; i++)
      if (seen[i] != seen[0]) all_same = 0;

    if (all_same) begin
      $display("FAIL: gain was %0d every time across 10 calls -- check what post_randomize() is doing to it", seen[0]);
      $fatal(1);
    end else begin
      $display("PASS: gain varied across calls: %p", seen);
      $finish;
    end
  end
endmodule
