// reproducibility needs an explicit seed
//
// A randomized test that can't be reproduced is much harder to debug than
// a deterministic one: a failure shows up once, and the next run rolls
// completely different values, so there's nothing to re-run against a
// fix. `srandom(seed)` makes an object's randomization sequence
// deterministic -- the same seed always produces the same sequence of
// results, and a different seed produces a different one. Skipping it
// isn't a compile error or even a wrong answer today; it's a debugging
// session waiting to happen the first time a regression needs to be
// reproduced.
//
// Fix the function below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class data_item;
  rand bit [31:0] data;
endclass

function data_item make_seeded_item(int seed);
  data_item item;
  item = new();
  return item;
endfunction

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    data_item a1;
    data_item a2;
    data_item b1;

    a1 = make_seeded_item(1);
    void'(a1.randomize());

    a2 = make_seeded_item(1);
    void'(a2.randomize());

    b1 = make_seeded_item(2);
    void'(b1.randomize());

    if (a1.data !== a2.data) begin
      $display("FAIL: same seed (1) produced different results: %0d vs %0d", a1.data, a2.data);
      $fatal(1);
    end

    if (a1.data === b1.data) begin
      $display($sformatf({"FAIL: different seeds (1 and 2) produced the same result: %0d ",
          "-- that's suspicious, not reproducible"}, a1.data));
      $fatal(1);
    end

    $display("PASS: seed 1 reproduced (%0d == %0d), seed 2 differed (%0d)",
        a1.data, a2.data, b1.data);
    $finish;
  end
endmodule
