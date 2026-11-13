// =================================================================================================
// a subclass's new constraint doesn't replace the base class's
// =================================================================================================
//
// Constraint blocks aren't virtual methods. A differently named constraint in a subclass doesn't
// override the base class's: every block in the inheritance chain is ANDed together, so adding
// [0:200] on top of [0:50] still leaves [0:50].
//
// `constraint_mode(0)` switches a named constraint block off, including an inherited one,
// without touching its declaration: `rand_mode()` for constraints instead of fields.
//
// Fix the classes below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, so that wide_item's value can reach above 50:
//
//   1. Add a constraint in wide_item allowing value up to 200.
//   2. In wide_item's constructor, turn off base_item's c_range with constraint_mode(0).
// -------------------------------------------------------------------------------------------------
class base_item;
  rand bit [7:0] value;
  constraint c_range {value inside {[0 : 50]};}
endclass

class wide_item extends base_item;
  // write constraints here
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
