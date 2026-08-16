// =================================================================================================
// an inline constraint that resolves to the wrong "len"
// =================================================================================================
//
// `randomize() with { ... }` constraints resolve unprefixed names against
// the object's own class members first. The function below takes an
// argument named `len`, and the class it's randomizing also happens to
// have a field named `len`. Both are in scope inside the inline
// constraint at the same time -- which one does an unprefixed `len`
// actually bind to there, and does the constraint as written still
// reference the argument at all once you know the answer?
//
// Fix the function below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix randomize_with_target() so item.len always matches the target argument it's given.
// -------------------------------------------------------------------------------------------------
class pkt_item;
  rand int len;
endclass

function void randomize_with_target(pkt_item item, int len);
  void'(item.randomize() with { len == len; });
endfunction

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    pkt_item item = new();
    bit bad_found = 0;

    for (int i = 0; i < 10; i++) begin
      int target = 10 + i;
      randomize_with_target(item, target);
      if (item.len != target) begin
        $display("FAIL: target=%0d but item.len=%0d", target, item.len);
        bad_found = 1;
      end
    end

    if (bad_found) $fatal(1);

    $display("PASS: item.len matched the target on every call");
    $finish;
  end
endmodule
