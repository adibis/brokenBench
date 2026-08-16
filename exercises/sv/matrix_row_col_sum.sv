// uniqueness scoped to the wrong dimension
//
// A `foreach (grid[i])` loop iterating rows and constraining each row's
// three cells to be mutually different does exactly what it says --
// every row genuinely has no repeated values in it. Nothing about that
// constraint says anything about column 0 of row 0 versus column 0 of
// row 1, though, and if the actual intent was "every value in the whole
// grid is unique," a row-scoped foreach silently stops one dimension
// short of the real requirement. Two values that never sit in the same
// row can still collide.
//
// (`unique{}` isn't used here on purpose: on the current toolchain, using
// unique{} on a row-slice of a 2D array crashes the compiler outright --
// a real, current tool limitation, not a design choice. Pairwise != is
// the working alternative here, same idea as the standalone
// unique_without_unique_keyword exercise.)
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class grid_item;
  rand bit [4:0] grid[3][3];
  constraint c_range  { foreach (grid[i,j]) grid[i][j] inside {[1:9]}; }
  constraint c_rowsum { foreach (grid[i]) grid[i][0] + grid[i][1] + grid[i][2] == 15; }
  constraint c_unique_row {
    foreach (grid[i]) {
      grid[i][0] != grid[i][1];
      grid[i][1] != grid[i][2];
      grid[i][0] != grid[i][2];
    }
  }
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
        if (g.grid[i][0] + g.grid[i][1] + g.grid[i][2] != 15) begin
          $display("FAIL: row %0d does not sum to 15: %p", i, g.grid[i]);
          bad_found = 1;
        end

      for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++)
          for (int i2 = 0; i2 < 3; i2++)
            for (int j2 = 0; j2 < 3; j2++)
              if (!(i==i2 && j==j2) && g.grid[i][j] == g.grid[i2][j2]) begin
                $display($sformatf({"FAIL: grid[%0d][%0d]=grid[%0d][%0d]=%0d -- duplicate ",
                    "across the whole grid"}, i, j, i2, j2, g.grid[i][j]));
                bad_found = 1;
              end
    end

    if (bad_found) $fatal(1);

    $display("PASS: 20 trials, every row sums to 15, every value in the grid is unique");
    $finish;
  end
endmodule
