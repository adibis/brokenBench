// =================================================================================================
// an off-by-one at the exact boundary a spec cares about
// =================================================================================================
//
// Spec: packets longer than 60 bytes must carry a CRC flag; packets at
// or under 60 don't need one. `(len >= 60) -> has_crc == 1` reads like a
// faithful translation, and for every length except exactly 60 it
// behaves identically to the spec. At len==60 it silently over-applies
// the rule the spec explicitly didn't ask for at that boundary. This is
// the kind of off-by-one that a spot check at len=0, len=64, and a
// handful of random lengths will almost never land on by chance -- it
// only shows up if something specifically drives the boundary value.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix c_crc so len==60 leaves has_crc free but len==61 correctly forces it to 1.
// -------------------------------------------------------------------------------------------------
class pkt_item;
  rand bit [6:0] len;
  rand bit       has_crc;
  constraint c_len { len inside {[0:64]}; }
  constraint c_crc { (len >= 60) -> has_crc == 1; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    pkt_item item = new();
    int ok;
    bit saw_no_crc_at_60 = 0;
    bit crc_missing_above_60 = 0;

    for (int t = 0; t < 30; t++) begin
      ok = item.randomize() with { len == 60; };
      if (!ok) begin
        $display("FAIL: randomize() with len==60 returned 0");
        $fatal(1);
      end
      if (item.has_crc == 0) saw_no_crc_at_60 = 1;
    end

    for (int t = 0; t < 30; t++) begin
      ok = item.randomize() with { len == 61; };
      if (!ok || item.has_crc != 1) crc_missing_above_60 = 1;
    end

    if (!saw_no_crc_at_60) begin
      $display($sformatf({"FAIL: at len==60, has_crc was forced to 1 every time -- ",
          "the spec only requires it above 60"}));
      $fatal(1);
    end

    if (crc_missing_above_60) begin
      $display("FAIL: at len==61, has_crc wasn't reliably forced to 1");
      $fatal(1);
    end

    $display("PASS: len==60 leaves has_crc free, len==61 correctly forces it");
    $finish;
  end
endmodule
