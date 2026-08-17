// =================================================================================================
// a soft constraint that never actually wins
// =================================================================================================
//
// `soft` constraints are a stated preference, not a requirement -- the
// solver only honors a soft constraint when nothing else conflicts with
// it, and yields to any hard constraint without complaint or error. That
// silence is the trap: randomize() returns 1, the field is filled with a
// value satisfying every hard constraint, and the soft constraint that
// was supposed to bias the result toward a specific region never gets a
// say, with nothing anywhere reporting that it lost.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the class so delay reaches the preferred [100:110] range at least once across 20 calls.
// -------------------------------------------------------------------------------------------------
class delay_item;
  rand bit [7:0] delay;
  // intent: prefer a longer delay when nothing else constrains it
  constraint c_prefer_long {soft delay inside {[100 : 110]};}
  constraint c_narrow {delay inside {[0 : 10]};}
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    delay_item item = new();
    bit saw_preferred = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      if (item.delay inside {[100 : 110]}) saw_preferred = 1;
    end

    if (!saw_preferred) begin
      $display($sformatf({"FAIL: delay never once landed in the preferred [100:110] range across ",
                          "20 calls -- check what's conflicting with the soft constraint"}));
      $fatal(1);
    end else begin
      $display("PASS: delay reached the preferred range at least once across 20 calls");
      $finish;
    end
  end
endmodule
