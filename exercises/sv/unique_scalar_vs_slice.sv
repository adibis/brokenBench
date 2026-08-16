// =================================================================================================
// unique{} on a whole row, not one cell of it
// =================================================================================================
//
// REQUIRES A PATCHED VERILATOR -- see the note in README.md before you
// spend time on this one. On every released Verilator as of this writing,
// `unique{}` on a foreach-indexed row of a 2D array (`foreach (grid[i])
// unique {grid[i]}`) crashes the compiler outright (an internal fault, not
// a graceful error) -- the same bug documented for matrix_row_col_sum, and
// the actual reason that exercise uses pairwise != instead of unique{}.
// That crash has a real fix upstream now (verilator/verilator#8100,
// unmerged as of this writing); this exercise is written for a Verilator
// built from that patch:
//
//   make run EX=unique_scalar_vs_slice VERILATOR=/path/to/patched/verilator_bin
//
// The lesson itself, once you have a toolchain that doesn't crash on the
// construct: `unique{}` takes a range list, and IEEE 1800-2023 18.5.4
// defines the uniqueness group by each item's *leaf elements*, not by how
// many items you wrote. `grid[i]` is a 3-element row -- its group has 3
// members, and unique{} forces all 3 apart. `grid[i][0]` is a single
// integral value -- a 1-member group, which the LRM defines as vacuously
// unique (nothing to compare it against). Both compile. Only one of them
// is testing anything.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write constraint so that each element of the grid is between 1 and 9 and
// each row has unique elements.
// -------------------------------------------------------------------------------------------------
class grid_item;
  rand bit [4:0] grid[3][3];
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    grid_item g = new();
    int ok;
    bit bad_found = 0;

    for (int t = 0; t < 20; t++) begin
      ok = g.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end

      for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++)
          if (g.grid[i][j] < 1 || g.grid[i][j] > 9) begin
            $display("FAIL: grid[%0d][%0d]=%0d is outside [1:9]", i, j, g.grid[i][j]);
            bad_found = 1;
          end

      for (int i = 0; i < 3; i++)
        for (int x = 0; x < 3; x++)
          for (int y = x + 1; y < 3; y++)
            if (g.grid[i][x] == g.grid[i][y]) begin
              $display("FAIL: row %0d has a repeated value: %p", i, g.grid[i]);
              bad_found = 1;
            end
    end

    if (bad_found) $fatal(1);

    $display("PASS: 20 trials, every row has three distinct values in [1:9]");
    $finish;
  end
endmodule
