// && where -> was meant
//
// `a -> b` inside a constraint means "when a holds, b must hold too" --
// it says nothing about what happens when a is false. `a && b` means
// something completely different: both a and b must hold, always,
// unconditionally. Writing && where -> was intended doesn't just weaken
// a constraint, it silently forces the left-hand side to a single fixed
// value forever, because that's the only way the unconditional AND can
// ever be satisfied.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class txn_item;
  rand bit       is_write;
  rand bit [7:0] wdata;

  // intent: writes need data, reads don't care what wdata holds
  constraint c_write_data { is_write && (wdata inside {[1:255]}); }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    txn_item item = new();
    bit saw_read = 0;
    bit saw_write = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      if (item.is_write) saw_write = 1;
      else saw_read = 1;
    end

    if (!saw_read) begin
      $display("FAIL: is_write was 1 on every one of 20 calls -- reads should be possible too");
      $fatal(1);
    end else begin
      $display("PASS: saw both reads and writes across 20 calls");
      $finish;
    end
  end
endmodule
