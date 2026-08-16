// =================================================================================================
// EX_01 -- inside {} against a queue that was never populated
// =================================================================================================
//
// `val inside {legal_vals}` constrains val to whatever's in the legal_vals queue at the moment
// .randomize() runs. That's a normal, useful pattern for a runtime-computed set of legal values --
// as long as something actually populates the queue first. Nothing does here.
//
// So: legal_vals starts empty, and the constraint checks `val inside {legal_vals}`. What does "val
// must be inside an empty set" actually mean -- is that no restriction at all, or is it the
// strictest restriction possible? What do you think happens when Verilator tries to satisfy it?
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// This constraint cannot be satisfied today. Fix the code below so `val` gets an odd number
// between 1 and 11.
// -------------------------------------------------------------------------------------------------
class legal_item;
  rand int val;
  int legal_vals[$];
  constraint c_legal { val inside {legal_vals}; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    legal_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0 -- legal_vals.size()=%0d", item.legal_vals.size());
      $fatal(1);
    end else if (item.val < 1 || item.val > 11 || (item.val % 2) == 0) begin
      $display("FAIL: val=%0d is not an odd number between 1 and 11", item.val);
      $fatal(1);
    end else begin
      $display("PASS: val=%0d chosen from legal_vals=%p", item.val, item.legal_vals);
      $finish;
    end
  end
endmodule
