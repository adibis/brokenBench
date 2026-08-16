// three bugs, one at a time
//
// This one has three separate problems stacked in the same small scenario,
// on purpose. Fix the first one the compiler reports, recompile, and the
// next one shows up -- that's normal, not a sign you broke something new.
// Each of the three is diagnosed completely differently: one is a parser
// error, one is a name-resolution error, and the last one only shows up
// at runtime, not at compile time at all. Reading which KIND of error
// you're looking at is most of the skill here.
//
// Fix the code below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class addr_item;
  rand bit [15:0] addr;
  rand bit [3:0]  size;
  constraint c_addr {
    addr[1:0] == 2'b00
    sz inside {[1:8]};
  }
endclass

function addr_item make_item();
  addr_item item;
  return item;
endfunction

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    addr_item item = make_item();

    if (item == null) begin
      $display("FAIL: make_item() returned a null handle");
      $fatal(1);
    end

    if (!item.randomize()) begin
      $display("FAIL: randomize() returned 0");
      $fatal(1);
    end

    if (item.addr[1:0] != 2'b00 || item.size < 1 || item.size > 8) begin
      $display("FAIL: addr=%0h size=%0d violates the constraint", item.addr, item.size);
      $fatal(1);
    end

    $display("PASS: addr=%0h size=%0d", item.addr, item.size);
    $finish;
  end
endmodule
