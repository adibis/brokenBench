// =================================================================================================
// write a class, a compound constraint, and a factory function from scratch
// =================================================================================================
//
// A handle declared but never assigned with `new()` is null, and using it fails at runtime, not
// at compile time. A factory function's one job is to construct the object before returning it.
//
// Fix the class and function below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. addr's low 2 bits are always 0 (addr[1:0] == 2'b00).
//   2. size stays between 1 and 8, inclusive.
//   3. make_item() returns a valid (non-null) handle.
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

    // One call would let a missing constraint pass by luck (addr[1:0] is 0 one time in 4).
    for (int i = 0; i < 200; i++) begin
      if (!item.randomize()) begin
        $display("FAIL: randomize() returned 0 on call %0d", i);
        $fatal(1);
      end
      if (item.addr[1:0] != 2'b00 || item.size < 1 || item.size > 8) begin
        $display("FAIL: addr=%0h size=%0d violates the constraint on call %0d", item.addr,
                 item.size, i);
        $fatal(1);
      end
    end

    $display("PASS: 200 randomizations, every addr word-aligned and size in 1..8");
    $finish;
  end
endmodule
