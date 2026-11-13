// =================================================================================================
// write a function that makes randomize() reproducible
// =================================================================================================
//
// Two separate calls on a handle:
//
//   handle.randomize()    -- rolls new values into the rand fields from the object's current
//                            PRNG state.
//   handle.srandom(seed)  -- randomizes nothing. It resets the object's PRNG from `seed`, so
//                            every later randomize() follows the same sequence for that seed.
//
// srandom() isn't an argument to randomize(); call it on the handle first.
//
// Fix the function below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements for make_seeded_item():
//
//   1. It returns a valid (non-null) handle.
//   2. Two calls with the same seed give objects whose later randomize() calls produce the same
//      sequence.
//   3. Two calls with different seeds give sequences that diverge.
// -------------------------------------------------------------------------------------------------
class data_item;
  rand bit [31:0] data;
endclass

function data_item make_seeded_item(int seed);
  data_item item;
  // write this function so it returns a handle seeded from `seed`
  return item;
endfunction

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    data_item a1;
    data_item a2;
    data_item b1;

    a1 = make_seeded_item(1);
    if (a1 == null) begin
      $display("FAIL: make_seeded_item() returned a null handle");
      $fatal(1);
    end
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

    $display("PASS: seed 1 reproduced (%0d == %0d), seed 2 differed (%0d)", a1.data, a2.data,
             b1.data);
    $finish;
  end
endmodule
