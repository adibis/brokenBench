// =================================================================================================
// write a constraint, then check that randomize() actually succeeded
// =================================================================================================
//
// .randomize() returns 0 when the constraint solver can't find any value
// satisfying every active constraint at once. That return value matters:
// code that doesn't check it just keeps whatever the field held before
// the failed call (usually 0, or a stale value from the last successful
// randomize()) and carries on as if nothing went wrong. The checker below
// DOES check the return value and will tell you plainly if a constraint
// you wrote can never be satisfied.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write a constraint from scratch:
//
//   1. delay must always be greater than 10 -- nothing else.
// -------------------------------------------------------------------------------------------------
class delay_item;
  rand int delay;
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    delay_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0 -- the constraint has no satisfiable value");
      $fatal(1);
    end else if (item.delay <= 10) begin
      $display("FAIL: randomize() succeeded but delay=%0d is not > 10", item.delay);
      $fatal(1);
    end else begin
      $display("PASS: delay=%0d satisfies the constraint", item.delay);
      $finish;
    end
  end
endmodule
