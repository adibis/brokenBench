// Pattern A: video frame generation where each frame must differ from the
// previous one by exactly one pixel. Requires remembering the previous
// randomize() result (post_randomize) and using it to shape the next one
// (pre_randomize / a constraint that reads the remembered state).

class frame_item;
  rand bit [7:0] frame[4][4];
  bit   [7:0] prev_frame[4][4];
  bit         has_prev;

  rand int unsigned diff_i;
  rand int unsigned diff_j;

  constraint c_pixel_range { foreach (frame[i, j]) frame[i][j] inside {[0:255]}; }
  constraint c_diff_idx    { diff_i inside {[0:3]}; diff_j inside {[0:3]}; }

  constraint c_one_pixel_diff {
    if (has_prev) {
      foreach (frame[i, j]) {
        if (i == diff_i && j == diff_j) frame[i][j] != prev_frame[i][j];
        else frame[i][j] == prev_frame[i][j];
      }
    }
  }

  function void post_randomize();
    prev_frame = frame;
    has_prev   = 1;
  endfunction
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
