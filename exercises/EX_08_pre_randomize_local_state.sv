// 013: pre_randomize() trying to remember state in a local variable
//
// pre_randomize() runs immediately before every .randomize() call, which
// makes it a natural place to compute context a constraint depends on.
// It's also just a function: any variable declared local to it is fresh
// every single call, not preserved from the call before. Code that's
// trying to alternate or accumulate state across calls using a local
// silently resets that intent every time, and the constraint that reads
// it never sees anything but the same starting value.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class packet_item;
  rand bit [7:0] len;
  bit is_jumbo;

  function void pre_randomize();
    bit toggle = 0;
    toggle = !toggle;
    is_jumbo = toggle;
  endfunction

  constraint c_len {
    is_jumbo  -> len inside {[200:255]};
    !is_jumbo -> len inside {[1:64]};
  }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    packet_item item = new();
    bit saw_jumbo = 0;
    bit saw_normal = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      if (item.len >= 200) saw_jumbo = 1;
      else saw_normal = 1;
    end

    if (!saw_normal || !saw_jumbo) begin
      $display({"FAIL: is_jumbo never actually alternated across 20 calls ",
          "(saw_normal=%0d saw_jumbo=%0d)"}, saw_normal, saw_jumbo);
      $fatal(1);
    end else begin
      $display("PASS: saw both normal and jumbo packets across 20 calls");
      $finish;
    end
  end
endmodule
