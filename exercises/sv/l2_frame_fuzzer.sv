// =================================================================================================
// three lifecycle pieces, one class
// =================================================================================================
//
// A NIC frame has an 8-bit header, a variable-length payload and an 8-bit CRC. The interesting
// part is where each piece is decided:
//
//   - header's low 4 bits come from a global flag (jumbo_mode_en) before the solver runs. That's
//     pre_randomize()'s job; header isn't rand.
//   - The payload size depends on that, through `->`. Constrain only the jumbo case and a
//     non-jumbo frame can still roll a payload over 1500 bytes: each case needs its own `->`.
//   - crc is arithmetic over values the solver already picked, so it belongs in post_randomize().
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. pre_randomize() sets header[3:0] to 4'b1111 if jumbo_mode_en is set, else 4'b0000.
//   2. When header[3:0] == 4'b1111, payload.size() is in [1501:2048].
//      When header[3:0] == 4'b0000, payload.size() is in [46:1500].
//   3. post_randomize() sets crc to the 8-bit sum (wrapping) of header and every payload byte,
//      inverted if crc_corrupt came out set.
// -------------------------------------------------------------------------------------------------

package test_pkg;
  bit jumbo_mode_en = 0;
endpackage

import test_pkg::*;

class L2FrameFuzzer;
  bit       [7:0] header;  // set procedurally in pre_randomize -- not rand
  rand byte       payload                                                  [];  // dynamic array
  rand bit        crc_corrupt;  // 1 = deliberately invert the computed CRC
  bit       [7:0] crc;  // set procedurally in post_randomize -- not rand

  constraint c_payload_base_size {payload.size() inside {[46 : 2048]};}

  // write pre_randomize(), the size-dependency constraint, and post_randomize() here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    L2FrameFuzzer f;
    int ok;
    bit bad_found = 0;
    bit saw_small = 0, saw_large = 0;
    bit saw_clean = 0, saw_corrupt = 0;

    // non-jumbo mode: size must stay in [46:1500], and genuinely vary -- not lock to one value
    jumbo_mode_en = 0;
    for (int t = 0; t < 100; t++) begin
      f  = new();
      ok = f.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 in non-jumbo mode at trial %0d", t);
        $fatal(1);
      end
      if (f.header[3:0] !== 4'b0000) begin
        $display("FAIL: header[3:0]=%0h with jumbo_mode_en=0 at trial %0d", f.header[3:0], t);
        bad_found = 1;
      end
      if (f.payload.size() < 46 || f.payload.size() > 1500) begin
        $display("FAIL: non-jumbo payload.size()=%0d outside [46:1500] at trial %0d",
                 f.payload.size(), t);
        bad_found = 1;
      end
      if (f.payload.size() < 400) saw_small = 1;
      if (f.payload.size() > 1100) saw_large = 1;

      // crc check lives in this same loop, reusing this call site's randomize() output --
      // see README's tool-limitations section: a third separate randomize() call site for
      // this class corrupts an earlier loop's header value on this toolchain.
      begin
        int sum;
        bit [7:0] expected;
        sum = f.header;
        foreach (f.payload[i]) sum += int'(f.payload[i]);
        expected = f.crc_corrupt ? ~(sum[7:0]) : sum[7:0];
        if (f.crc !== expected) begin
          $display($sformatf({"FAIL: crc=%0h, expected %0h (header=%0h + payload bytes, ",
                              "wrapped mod 256, corrupt=%0d) at trial %0d"}, f.crc, expected,
                               f.header, f.crc_corrupt, t));
          bad_found = 1;
        end
        if (f.crc_corrupt) saw_corrupt = 1;
        else saw_clean = 1;
      end
    end
    if (!saw_small || !saw_large) begin
      $display($sformatf({"FAIL: non-jumbo payload.size() didn't range across [46:1500] -- ",
                          "looks locked to a narrow/fixed value instead of left free"}));
      bad_found = 1;
    end
    if (!saw_clean || !saw_corrupt) begin
      $display("FAIL: crc_corrupt didn't vary across trials -- can't tell if inversion is real");
      bad_found = 1;
    end

    // jumbo mode: size must stay in [1501:2048]
    jumbo_mode_en = 1;
    for (int t = 0; t < 100; t++) begin
      f  = new();
      ok = f.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 in jumbo mode at trial %0d", t);
        $fatal(1);
      end
      if (f.header[3:0] !== 4'b1111) begin
        $display("FAIL: header[3:0]=%0h with jumbo_mode_en=1 at trial %0d", f.header[3:0], t);
        bad_found = 1;
      end
      if (f.payload.size() <= 1500 || f.payload.size() > 2048) begin
        $display("FAIL: jumbo payload.size()=%0d outside [1501:2048] at trial %0d",
                 f.payload.size(), t);
        bad_found = 1;
      end
    end

    if (bad_found) $fatal(1);

    $display("PASS: header tracks jumbo_mode_en, payload size respects the dependency in both");
    $display("      directions, and crc is computed and corrupted correctly");
    $finish;
  end
endmodule
