// =================================================================================================
// generate frames that differ from the last one by exactly one pixel
// =================================================================================================
//
// A common stimulus-generation shape: each new random value has to be shaped by the *previous*
// random value, not generated in isolation. Video frame streams, this exercise's example, are one
// case -- so are monotonic counters, "don't repeat the last packet ID," and delta-encoded
// sequences generally. `post_randomize()` runs after every successful randomize() and is the
// normal place to remember what just happened, so the next call's constraints can read it.
//
// Nothing below does that yet -- there's no memory of the previous frame, and no constraint
// linking one frame to the next. Both need to be added.
//
// One thing worth knowing before you reach for it: comparing two whole arrays with `!=` inside a
// constraint is not the same kind of ask for a solver as comparing two integers, and it may not
// do what the syntax suggests. If your first attempt uses it, check what randomize() actually
// returns before assuming the logic is the problem.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write constraints so every frame after the first differs from the
// immediately preceding frame in exactly one pixel -- no more, no less.
// -------------------------------------------------------------------------------------------------
class frame_item;
  rand bit [7:0] frame[4][4];
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    frame_item f = new();
    bit [7:0] last_frame[4][4];
    int ok;
    bit bad_found = 0;

    for (int t = 0; t < 20; t++) begin
      ok = f.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at frame %0d", t);
        $fatal(1);
      end

      if (t > 0) begin
        automatic int diff_count = 0;
        for (int i = 0; i < 4; i++)
          for (int j = 0; j < 4; j++)
            if (f.frame[i][j] != last_frame[i][j]) diff_count++;

        if (diff_count != 1) begin
          $display("FAIL: frame %0d differs from frame %0d in %0d pixels, expected exactly 1",
              t, t - 1, diff_count);
          bad_found = 1;
        end
      end

      last_frame = f.frame;
    end

    if (bad_found) $fatal(1);

    $display("PASS: 20 frames, each differing from the last by exactly one pixel");
    $finish;
  end
endmodule
