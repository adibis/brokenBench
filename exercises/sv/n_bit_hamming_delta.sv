// =================================================================================================
// counting flipped bits with sum() with(), not $countones()
// =================================================================================================
//
// $countones() would make this trivial; the point is the array-reduction technique. `sum() with`
// needs an array, and `current_data ^ previous_data` is a single packed value. Two things that
// look like they should work and don't compile: chaining the streaming operator `{<<{...}}` into
// a method call, and comparing an unpacked array to a streaming expression with `==`.
//
// What works: an array of `rand bit`, each element tied to one bit of the XOR by a foreach
// constraint, then reduced. Cast each element with `int'(item)`, or the count wraps at 1 bit.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. toggle_target is between 1 and 32, inclusive.
//   2. changed_bits[k] == current_data[k] ^ previous_data[k] for every k, via foreach.
//   3. changed_bits.sum() with (int'(item)) == toggle_target.
//   4. post_randomize() sets previous_data to current_data, so the next randomize() measures
//      its distance from this one. previous_data is static, so this holds across objects too.
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
