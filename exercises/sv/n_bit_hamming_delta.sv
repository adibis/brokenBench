// =================================================================================================
// counting flipped bits with sum() with(), not $countones()
// =================================================================================================
//
// $countones() would make this trivial -- but the point here is the array-reduction technique
// itself, not the answer. `sum() with (...)` needs an actual array to reduce, and a 32-bit vector
// isn't one: `current_data ^ previous_data` is still a single packed value, and there's no direct
// way to hand a packed expression straight to `.sum()` (the streaming operator `{<<{...}}` can't
// be chained into a method call, and comparing an unpacked array against a streaming expression
// with `==` fails to compile -- both real, worth hitting once so you know what doesn't work, not
// just what does). What DOES work: declare a plain array of individual bits, tie each element to
// the matching XOR bit with an ordinary `foreach` constraint (not a procedural loop -- constraints
// don't have those), and reduce that array. `sum() with (int'(item))` on a plain (non-struct)
// array of `rand bit` elements works cleanly; casting each 1-bit element to `int` before summing
// avoids the count silently wrapping once more than one bit is set.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints and lifecycle hook so:
//
//   1. toggle_target is randomized to somewhere between 1 and 32, inclusive.
//   2. changed_bits[k] equals current_data[k] ^ previous_data[k] for every k -- tie each element
//      of the helper array to the matching bit of the XOR, via foreach.
//   3. changed_bits.sum() with (int'(item)) equals toggle_target -- the actual Hamming-distance
//      constraint, expressed as an array reduction over changed_bits.
//   4. post_randomize() updates previous_data to current_data, so the next randomize() call (on
//      this object, or on a brand new one -- previous_data is static) measures its distance from
//      what was just generated, not from whatever came before that.
// -------------------------------------------------------------------------------------------------
class PowerFuzzer;
  static bit [31:0] previous_data       = 32'h0000_0000;

  rand bit   [31:0] current_data;
  rand bit   [ 5:0] toggle_target;
  rand bit          changed_bits  [32];

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    bit bad_found = 0;

    if (PowerFuzzer::previous_data != 32'h0000_0000) begin
      $display("FAIL: PowerFuzzer::previous_data=%08h at boot, expected 32'h0000_0000",
               PowerFuzzer::previous_data);
      $fatal(1);
    end

    for (int t = 0; t < 20; t++) begin
      automatic PowerFuzzer f = new();  // a brand-new instance every call, on purpose
      automatic bit [31:0] prev_snapshot = PowerFuzzer::previous_data;
      automatic int ok = f.randomize();
      automatic int actual;

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", t);
        $fatal(1);
      end

      if (f.toggle_target < 1 || f.toggle_target > 32) begin
        $display("FAIL: toggle_target=%0d is outside [1:32] at call %0d", f.toggle_target, t);
        bad_found = 1;
      end

      actual = $countones(f.current_data ^ prev_snapshot);
      if (actual != f.toggle_target) begin
        $display($sformatf({"FAIL: call %0d, prev=%08h cur=%08h, Hamming distance=%0d, ",
                            "expected toggle_target=%0d"}, t, prev_snapshot, f.current_data,
                             actual, f.toggle_target));
        bad_found = 1;
      end

      if (PowerFuzzer::previous_data != f.current_data) begin
        $display($sformatf({"FAIL: call %0d, PowerFuzzer::previous_data=%08h after ",
                            "randomize(), expected it to already equal current_data=%08h -- ",
                            "did post_randomize() run?"}, t, PowerFuzzer::previous_data,
                             f.current_data));
        bad_found = 1;
      end

      if (bad_found) $fatal(1);
    end

    $display("PASS: 20 calls, every Hamming distance matched its own toggle_target exactly");
    $finish;
  end
endmodule
