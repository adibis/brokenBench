// =================================================================================================
// EX_02 -- "random" that can only ever produce one value
// =================================================================================================
//
// Every individual constraint on offset below is completely reasonable on its own: a legal range,
// an alignment rule, a narrower sub-range. Put together, they leave exactly one legal value in the
// entire 8-bit space -- randomize() succeeds every time, offset is genuinely `rand`, nothing is
// illegal, and the result is not random at all.
//
// This is the shape of bug that survives code review easily: nothing about any single constraint
// looks wrong in isolation. So look at the three constraints one at a time -- which one, on its
// own, already pins offset down to a single value before the other two even get involved?
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// This class is over-constrained today. Fix it so offset reaches exactly 100, 104, and 108 across
// repeated randomize() calls -- and nothing outside that set.
// -------------------------------------------------------------------------------------------------
class offset_item;
  rand bit [7:0] offset;
  constraint c_range  { offset inside {[100:110]}; }
  constraint c_align  { offset[1:0] == 2'b00; }
  constraint c_narrow { offset inside {[104:114]}; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    offset_item item = new();
    bit [10:0] seen_mask = 11'b0; // bit i => offset == 100+i observed
    bit bad_value_found = 0;

    for (int i = 0; i < 200; i++) begin
      void'(item.randomize());
      if (item.offset < 100 || item.offset > 110 || item.offset[1:0] != 2'b00) begin
        $display("FAIL: offset=%0d violates the range/alignment intent", item.offset);
        bad_value_found = 1;
      end else begin
        seen_mask[item.offset - 100] = 1'b1;
      end
    end

    if (bad_value_found) $fatal(1);

    // legal aligned offsets in [100:110] are exactly 100, 104, 108
    if (seen_mask !== (11'b1 << 0 | 11'b1 << 4 | 11'b1 << 8)) begin
      $display($sformatf({"FAIL: offset should reach exactly {100, 104, 108} across 200 calls, ",
          "no more, no less."}));
      if (!seen_mask[0]) $display("      100 was never reached.");
      if (!seen_mask[4]) $display("      104 was never reached.");
      if (!seen_mask[8]) $display("      108 was never reached.");
      if (|(seen_mask & ~(11'b1 << 0 | 11'b1 << 4 | 11'b1 << 8)))
        $display("      a value outside {100, 104, 108} was also reached.");
      $fatal(1);
    end

    $display("PASS: all three legal offsets (100, 104, 108) reached, nothing else");
    $finish;
  end
endmodule
