// EX 13: pairwise inequality that only checks neighbors
//
// This is a direct companion to unique_oversized_array: on the current
// toolchain, `unique{}` on an array degrades past about 4-5 elements,
// silently returning success with real duplicates present. The working
// alternative is writing the pairwise inequality out explicitly. The
// trap in doing that by hand is covering *every* pair, not just the ones
// that are easy to think of -- `tags[i] != tags[i+1]` reads like a
// uniqueness check and even has the right shape, but it only ever
// compares an element to its immediate neighbor. Two elements three
// slots apart can still collide, and nothing about this constraint would
// ever catch it.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class tag_item;
  rand bit [3:0] tags[8];
  constraint c_unique {
    foreach (tags[i])
      if (i < 7)
        tags[i] != tags[i+1];
  }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    tag_item item = new();
    int ok;
    bit dup_found = 0;

    for (int t = 0; t < 20; t++) begin
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end
      for (int i = 0; i < 8; i++)
        for (int j = i+1; j < 8; j++)
          if (item.tags[i] == item.tags[j]) begin
            $display("FAIL: tags[%0d]=tags[%0d]=%0d, trial %0d: %p", i, j, item.tags[i], t, item.tags);
            dup_found = 1;
          end
    end

    if (dup_found) $fatal(1);

    $display("PASS: 20 trials, all 8 tags mutually unique every time");
    $finish;
  end
endmodule
