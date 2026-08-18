// =================================================================================================
// uniqueness scoped to the wrong dimension
// =================================================================================================
//
// A `foreach (grid[i])` loop iterating rows and constraining each row's three cells to be
// mutually different does exactly what it says -- every row genuinely has no repeated values in
// it. Nothing about that constraint says anything about column 0 of row 0 versus column 0 of row
// 1, though. Adding a matching column-scoped check closes that gap too, but even ROW-unique AND
// COLUMN-unique together still isn't the same as GRID-unique: two cells that share neither a row
// nor a column -- the two ends of a diagonal, for instance -- never get compared by either check,
// and can still collide. The only way to be sure no two cells anywhere in the grid share a value
// is to check every pair against every other pair directly, not to assemble the guarantee out of
// row-shaped and column-shaped pieces that each stop short of the real requirement.
//
// (`unique{}` isn't used here on purpose: on the current toolchain, using unique{} on a row-slice
// of a 2D array crashes the compiler outright -- a real, current tool limitation, not a design
// choice. Pairwise != is the working alternative here.)
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so:
//
//   1. every core_power[i][j] is between 1 and 9, inclusive.
//   2. every one of the 9 values is different from every other one -- genuinely unique across the
//      whole grid, not just within its own row or column. Check every pair directly.
//   3. every row sums to exactly 15.
//   4. every column sums to exactly 15.
//   5. both main diagonals (top-left to bottom-right, and top-right to bottom-left) sum to
//      exactly 15.
//
// No array-reduction methods (sum() with (...), find() with (...)) anywhere in this one -- direct
// algebraic expressions and index-based foreach only.
// -------------------------------------------------------------------------------------------------
class ThermalPowerFuzzer;
  rand bit [3:0] core_power[3][3];

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    ThermalPowerFuzzer f;
    bit bad_found = 0;

    for (int t = 0; t < 20; t++) begin
      automatic int ok;

      f  = new();
      ok = f.randomize();

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end

      foreach (f.core_power[i, j]) begin
        if (f.core_power[i][j] < 1 || f.core_power[i][j] > 9) begin
          $display("FAIL: core_power[%0d][%0d]=%0d is outside [1:9] at trial %0d", i, j,
                   f.core_power[i][j], t);
          bad_found = 1;
        end
      end

      for (int i = 0; i < 3; i++) begin
        for (int j = 0; j < 3; j++) begin
          for (int i2 = 0; i2 < 3; i2++) begin
            for (int j2 = 0; j2 < 3; j2++) begin
              if (!(i == i2 && j == j2) && f.core_power[i][j] == f.core_power[i2][j2]) begin
                $display($sformatf({"FAIL: core_power[%0d][%0d]=core_power[%0d][%0d]=%0d -- ",
                                    "duplicate across the whole grid at trial %0d"}, i, j, i2, j2,
                                     f.core_power[i][j], t));
                bad_found = 1;
              end
            end
          end
        end
      end

      for (int i = 0; i < 3; i++) begin
        if (f.core_power[i][0] + f.core_power[i][1] + f.core_power[i][2] != 15) begin
          $display("FAIL: row %0d does not sum to 15 at trial %0d", i, t);
          bad_found = 1;
        end
      end

      for (int j = 0; j < 3; j++) begin
        if (f.core_power[0][j] + f.core_power[1][j] + f.core_power[2][j] != 15) begin
          $display("FAIL: column %0d does not sum to 15 at trial %0d", j, t);
          bad_found = 1;
        end
      end

      if (f.core_power[0][0] + f.core_power[1][1] + f.core_power[2][2] != 15) begin
        $display("FAIL: top-left-to-bottom-right diagonal does not sum to 15 at trial %0d", t);
        bad_found = 1;
      end

      if (f.core_power[0][2] + f.core_power[1][1] + f.core_power[2][0] != 15) begin
        $display("FAIL: top-right-to-bottom-left diagonal does not sum to 15 at trial %0d", t);
        bad_found = 1;
      end

      if (bad_found) $fatal(1);
    end

    $display("PASS: 20 trials, every grid a genuinely valid 3x3 magic square");
    $finish;
  end
endmodule
