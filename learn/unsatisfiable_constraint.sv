// =================================================================================================
// a constraint that can never be satisfied
// =================================================================================================
//
// .randomize() returns 0 when the constraint solver can't find any value
// satisfying every active constraint at once. That return value matters:
// code that doesn't check it just keeps whatever the field held before
// the failed call (usually 0, or a stale value from the last successful
// randomize()) and carries on as if nothing went wrong. The checker below
// DOES check the return value and will tell you plainly if that's what's
// happening -- your job is to find the actual conflict in the constraint
// and fix it so a value exists at all.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the constraint so delay has at least one satisfiable value greater than 10.
// -------------------------------------------------------------------------------------------------
class delay_item;
  rand int delay;
  constraint c_range {
    delay > 10;
    delay < 5;
  }
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
