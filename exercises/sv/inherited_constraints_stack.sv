// =================================================================================================
// a subclass's new constraint doesn't replace the base class's
// =================================================================================================
//
// Constraint blocks aren't like virtual methods -- a differently-named
// constraint added in a subclass doesn't override anything in the base
// class, it just adds another block that has to hold at the same time as
// everything the base class already declared. Every constraint block
// across the whole inheritance chain is ANDed together. A subclass
// author who assumes their new range constraint replaces the base
// class's range constraint ends up with the intersection of both instead
// -- often a much narrower space than either constraint alone.
//
// Fix the classes below so the check after them passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the classes so wide_item's values genuinely reach above 50, not just the base range.
// -------------------------------------------------------------------------------------------------
class base_item;
  rand bit [7:0] value;
  constraint c_range {value inside {[0 : 50]};}
endclass

class wide_item extends base_item;
  constraint c_wide_range {value inside {[40 : 255]};}
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    wide_item item = new();
    bit saw_above_50 = 0;

    for (int i = 0; i < 30; i++) begin
      void'(item.randomize());
      if (item.value > 50) saw_above_50 = 1;
    end

    if (!saw_above_50) begin
      $display($sformatf({"FAIL: value never exceeded 50 across 30 calls -- wide_item's ",
                          "constraint is being intersected with base_item's, not replacing it"}));
      $fatal(1);
    end else begin
      $display("PASS: value reached above 50 across 30 calls");
      $finish;
    end
  end
endmodule
