// =================================================================================================
// write a function that makes randomize() reproducible
// =================================================================================================
//
// `handle.randomize()` and `handle.srandom(seed)` do two different jobs, and it's easy to mix
// them up:
//
//   handle.randomize()   -- rolls new values into the object's `rand`/`randc` fields, using
//                            whatever PRNG state the object currently has. You call this every
//                            time you want a new random result.
//   handle.srandom(seed) -- doesn't randomize anything itself. It resets the object's internal
//                            PRNG to a state fully determined by `seed`. Call it once, and every
//                            randomize() call on that object afterward follows a reproducible
//                            sequence -- same seed in, same sequence of results out, every time.
//
// They're two separate calls on the handle, not composable -- srandom(seed) is not an argument
// you pass into randomize(); randomize() only takes an optional list of field names to restrict
// which fields get re-rolled.
//
// Fix the function below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write make_seeded_item() from scratch:
//
//   1. it must return a valid (non-null) handle.
//   2. two calls with the same seed must make every later randomize() on that object follow the
//      same sequence of results.
//   3. two calls with different seeds must diverge.
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
