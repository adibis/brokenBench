// =================================================================================================
// uniqueness scoped to the wrong dimension
// =================================================================================================
//
// Making each row's cells differ leaves the columns free to repeat. Adding the same check per
// column still isn't grid-unique: two cells that share neither a row nor a column, such as the
// ends of a diagonal, are never compared. The only sure way is to compare every pair of cells.
//
// `unique{}` isn't used on purpose: on the current toolchain, unique{} over a row of a 2D array
// crashes the compiler. Pairwise != works.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. Every core_power[i][j] is between 1 and 9, inclusive.
//   2. All 9 values are different from each other across the whole grid. Compare every pair.
//   3. Every row sums to exactly 15.
//   4. Every column sums to exactly 15.
//   5. Both main diagonals sum to exactly 15.
//
// No array-reduction methods (sum() with, find() with): plain expressions and index-based
// foreach only.
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
