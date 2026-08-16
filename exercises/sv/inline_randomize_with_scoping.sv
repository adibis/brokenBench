// =================================================================================================
// an inline constraint that resolves to the wrong "len"
// =================================================================================================
//
// `randomize() with { ... }` constraints resolve unprefixed names against
// the object's own class members first. A function argument that happens
// to share a name with a class member -- `len`, here, both the class
// field and the argument meant to drive it -- doesn't get referenced by
// the inline constraint at all. `len == len` compiles cleanly, reads
// like it's pinning the field to the argument, and is actually just
// comparing the class member to itself: trivially true for any value,
// which is the same as no constraint at all.
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
