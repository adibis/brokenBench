// how many bits changed, versus how many bits are set
//
// "Generate a value where exactly N bits differ from the previous one"
// is a genuinely common request -- bit-toggle coverage, glitch injection,
// walking patterns. `$countones(cur)` counts how many bits are set in
// the new value. It says nothing about the previous value at all. The
// constraint that actually answers "how many bits changed" needs the
// previous value in the expression: `$countones(prev ^ cur)`, since XOR
// is exactly the set of bit positions that differ.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class walk_item;
  rand bit [31:0] cur;
  bit [31:0] prev;
  constraint c_delta { $countones(cur) == 2; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    walk_item item = new();
    bit [31:0] prev = 32'h0;
    bit bad_found = 0;

    for (int i = 0; i < 30; i++) begin
      item.prev = prev;
      if (!item.randomize()) begin
        $display("FAIL: randomize() returned 0 at step %0d", i);
        $fatal(1);
      end
      if ($countones(item.prev ^ item.cur) != 2) begin
        $display("FAIL: step %0d, prev=%0h cur=%0h, Hamming distance=%0d, expected 2",
          i, item.prev, item.cur, $countones(item.prev ^ item.cur));
        bad_found = 1;
      end
      prev = item.cur;
    end

    if (bad_found) $fatal(1);

    $display("PASS: every one of 30 steps changed exactly 2 bits from the previous value");
    $finish;
  end
endmodule
