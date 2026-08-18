// =================================================================================================
// write a class, a compound constraint, and a factory function from scratch
// =================================================================================================
//
// A class handle that's declared but never assigned with `new()` is null -- calling a method or
// randomizing through it fails at runtime, not at compile time. A factory function that's supposed
// to hand back a ready-to-use object has exactly one job it can't skip: actually constructing the
// object before returning it.
//
// Fix the class and function below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraint and the factory function from scratch:
//
//   1. addr's low 2 bits must always be 0 (addr[1:0] == 2'b00).
//   2. size must stay between 1 and 8, inclusive.
//   3. make_item() must return a valid (non-null) handle.
// -------------------------------------------------------------------------------------------------
class addr_item;
  rand bit [15:0] addr;
  rand bit [ 3:0] size;
  // write constraints here
endclass

function addr_item make_item();
  addr_item item;
  // write this function so it returns a valid handle
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
