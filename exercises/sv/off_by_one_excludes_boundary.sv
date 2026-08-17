// =================================================================================================
// an off-by-one that mathematically excludes the boundary
// =================================================================================================
//
// A regression that runs this constraint ten thousand times and never
// fails looks thorough. It isn't, if the constraint itself makes the one
// value most worth checking -- the maximum a field can hold, exactly
// where overflow and wraparound bugs live -- impossible to ever generate
// in the first place. More iterations don't help. The value is excluded
// by construction, not by bad luck.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix c_range so credits can reach 8'hFF (255), its actual maximum value.
// -------------------------------------------------------------------------------------------------
class credit_item;
  rand bit [7:0] credits;
  constraint c_range {credits inside {[0 : 254]};}
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    credit_item item = new();
    bit saw_max = 0;

    for (int i = 0; i < 10000; i++) begin
      void'(item.randomize());
      if (item.credits == 8'hFF) saw_max = 1;
    end

    if (!saw_max) begin
      $display($sformatf({"FAIL: credits never once hit 8'hFF (max value) across 10000 calls ",
                          "-- the constraint's range excludes it entirely"}));
      $fatal(1);
    end else begin
      $display("PASS: credits reached 8'hFF at least once across 10000 calls");
      $finish;
    end
  end
endmodule
