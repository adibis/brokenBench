// =================================================================================================
// the scoreboard's predictor calls the same function the "DUT" does -- of course they always agree
// =================================================================================================
//
// dut_pkg::checksum() is the behavioral stand-in for what the real RTL computes -- lifted straight
// into this reference model because it was already written and already "working" against the RTL
// testbench. sb::predict() calls it too, for exactly the same reason: it's right there, it's
// already written, why reimplement the XOR by hand? Run this: every single comparison matches.
//
// dut_pkg::checksum() stops one byte early -- a real off-by-one, the kind that ships because the
// RTL's own test never caught it either. A scoreboard whose predictor calls the DUT's own function
// has no way to disagree with it; the bug is invisible to a check that can't help but agree with
// itself.
//
// -------------------------------------------------------------------------------------------------
// Fix sb::predict() so it's an actual independent implementation of the spec -- "checksum is the
// XOR of every byte in the packet" -- not a call to dut_pkg::checksum(). Don't edit anything at or
// below the "checker" marker; it's correct as given and is what's judging you.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

package dut_pkg;
  // the RTL's own checksum, ported here as a reference -- stops one byte early
  function automatic bit [7:0] checksum(bit [7:0] data[]);
    automatic bit [7:0] acc = 8'h00;
    for (int i = 0; i < data.size() - 1; i++) acc ^= data[i];
    return acc;
  endfunction
endpackage

class sb extends uvm_component;
  `uvm_component_utils(sb)

  int unsigned match_count    = 0;
  int unsigned mismatch_count = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function bit [7:0] predict(bit [7:0] data[]);
    return dut_pkg::checksum(data);
  endfunction

  function void check(bit [7:0] data[], bit [7:0] actual);
    if (predict(data) == actual) match_count++;
    else mismatch_count++;
  endfunction
endclass

// ---8<--- checker below: don't edit ---

class test extends uvm_test;
  `uvm_component_utils(test)

  sb scoreboard;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    scoreboard = sb::type_id::create("scoreboard", this);
  endfunction

  // the true spec, computed independently of dut_pkg entirely: XOR of every byte, no exceptions
  function automatic bit [7:0] true_checksum(bit [7:0] data[]);
    automatic bit [7:0] acc = 8'h00;
    foreach (data[i]) acc ^= data[i];
    return acc;
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [7:0] packets[5][$];
    phase.raise_objection(this);

    packets[0] = '{8'h11, 8'h22, 8'hFF};
    packets[1] = '{8'hAA, 8'h01};
    packets[2] = '{8'h00, 8'h00, 8'h00, 8'h80};
    packets[3] = '{8'h5A, 8'hA5, 8'h0F, 8'hF0, 8'h3C};
    packets[4] = '{8'h7E, 8'h81};

    foreach (packets[p]) begin
      automatic bit [7:0] data[] = packets[p];
      automatic bit [7:0] actual = dut_pkg::checksum(data);  // what the "DUT" really outputs
      scoreboard.check(data, actual);

      if (true_checksum(data) == actual) begin
        $display("FAIL: packet %0d wasn't actually a real DUT bug -- test data needs reworking", p);
        $fatal(1);
      end
    end

    if (scoreboard.match_count != 0 || scoreboard.mismatch_count != 5) begin
      $display($sformatf({"FAIL: scoreboard reported match_count=%0d, mismatch_count=%0d -- want ",
                          "0 and 5. All 5 packets hit a real DUT bug; an independent predictor ",
                          "must flag every one, not agree with the DUT by construction"},
                           scoreboard.match_count, scoreboard.mismatch_count));
      $fatal(1);
    end

    $display("PASS: independent predictor caught all 5 real DUT mismatches (0 false matches)");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
