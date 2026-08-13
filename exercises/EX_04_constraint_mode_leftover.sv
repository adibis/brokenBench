// 011: constraint_mode(0) left disabled on the constraint that matters
//
// constraint_mode() turns a specific constraint block on or off without
// removing it from the class -- useful for temporarily relaxing one rule
// while chasing something unrelated. Left disabled, the class still
// compiles clean, .randomize() still returns 1, and every OTHER
// constraint still holds. The one thing quietly not being enforced is
// exactly the one someone meant to turn back on.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class addr_item;
  rand bit [15:0] addr;

  constraint c_range { addr inside {[16'h1000:16'hFFFF]}; }
  constraint c_align  { addr[1:0] == 2'b00; }

  function new();
    // turned off to isolate an alignment-unrelated bug last week
    c_align.constraint_mode(0);
  endfunction
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    addr_item item = new();
    int unaligned_count = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      if (item.addr[1:0] != 2'b00) unaligned_count++;
    end

    if (unaligned_count > 0) begin
      $display("FAIL: addr was unaligned on %0d of 20 calls -- c_align isn't being enforced", unaligned_count);
      $fatal(1);
    end else begin
      $display("PASS: addr was 4-byte aligned on every call");
      $finish;
    end
  end
endmodule
