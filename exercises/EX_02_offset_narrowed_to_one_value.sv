// EX 02: "random" that can only ever produce one value
//
// Every individual constraint below is completely reasonable on its own.
// Put together, they leave exactly one legal value in the entire 8-bit
// range -- randomize() succeeds every time, the field is genuinely
// `rand`, nothing is illegal, and the result is not random at all. This
// is the shape of bug that survives code review easily, because nothing
// about any single constraint looks wrong in isolation.
//
// The checker here is specific on purpose: it's not enough to make the
// value vary at all. It has to reach exactly the legal set implied by
// the range-and-alignment intent, and never step outside range or
// alignment while doing it. A half-fix in either direction -- leaving it
// too narrow, or deleting more than the one constraint that's actually
// wrong -- will still fail.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class offset_item;
  rand bit [7:0] offset;
  constraint c_range  { offset inside {[100:110]}; }
  constraint c_align  { offset[1:0] == 2'b00; }
  constraint c_narrow { offset inside {[104:104]}; }
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
      $display("FAIL: expected exactly {100,104,108} reachable, saw mask=%011b", seen_mask);
      $fatal(1);
    end

    $display("PASS: all three legal offsets (100, 104, 108) reached, nothing else");
    $finish;
  end
endmodule
