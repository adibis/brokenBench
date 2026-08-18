// =================================================================================================
// a subclass's new constraint doesn't replace the base class's
// =================================================================================================
//
// Constraint blocks aren't like virtual methods -- a differently-named
// constraint added in a subclass doesn't override anything in the base
// class, it just adds another block that has to hold at the same time as
// everything the base class already declared. Every constraint block
// across the whole inheritance chain is ANDed together. A subclass that
// wants a wider range than its base class can't get there by just adding
// a second, wider constraint -- the intersection of `[0:50]` and
// `[0:200]` is still `[0:50]`.
//
// What actually works: `constraint_mode()`, the same idea as
// `rand_mode()` but for constraint blocks instead of fields. Called on a
// named constraint -- including one inherited from a base class --
// `constraint_mode(0)` turns that specific block off without touching
// its declaration. Turn the base class's range constraint off in the
// subclass's own constructor, then a new constraint declared in the
// subclass is the only one left applying.
//
// Fix the classes below so the check after them passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write constraints so that wide_item's values reach above 50:
//
//   1. add a new constraint in wide_item allowing value up to 200.
//   2. in wide_item's constructor, disable base_item's c_range constraint via
//      constraint_mode(0) so it stops intersecting with the new one.
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
