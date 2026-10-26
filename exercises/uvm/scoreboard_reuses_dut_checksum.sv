// =================================================================================================
// the scoreboard's predictor calls the same CRC-8 function the "DUT" does -- of course they agree
// =================================================================================================
//
// Spec: CRC-8/SMBUS over the packet payload -- polynomial x^8 + x^2 + x + 1 (0x07), MSB-first bit
// processing, initial value 0x00, no input or output reflection, no final XOR. This is the
// standard packet-error-check byte used on SMBus; the public catalog check value for ASCII
// "123456789" under this exact definition is 0xF4 -- verify any from-scratch implementation
// against that before trusting it against anything else.
//
// dut_pkg::crc8() (a separate file, compiled alongside this one -- open it if you want to read it,
// but you don't need to in order to find the bug) is the behavioral stand-in for what this
// revision's CRC-8 hardware block computes. sb::predict() calls it too, because it's already
// written and "obviously" implements CRC-8 -- a reasonable thing to reach for when the alternative
// is re-deriving polynomial division by hand. Run this: every single comparison matches.
//
// A scoreboard whose predictor calls the DUT's own function has no way to disagree with it, no
// matter what that function actually computes. Reading predict() in isolation won't tell you
// anything is wrong -- it calls a function named crc8 and returns what it returns. The only way to
// know whether that's actually CRC-8/SMBUS is to implement the spec above independently and check.
//
// -------------------------------------------------------------------------------------------------
// Fix sb::predict() so it's an actual independent implementation of CRC-8/SMBUS, as specified
// above -- not a call to dut_pkg::crc8(). Verify your implementation against the 0xF4 check value
// before assuming it's right. Don't edit anything at or below the "checker" marker; it's correct
// as given and is what's judging you.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class sb extends uvm_component;
  `uvm_component_utils(sb)

  int unsigned match_count    = 0;
  int unsigned mismatch_count = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function bit [7:0] predict(bit [7:0] data[]);
    return dut_pkg::crc8(data);
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

  // the true spec, implemented independently of dut_pkg entirely: CRC-8/SMBUS, MSB-first,
  // poly 0x07, init 0x00, no reflection, no final XOR
  function automatic bit [7:0] true_crc8(bit [7:0] data[]);
    automatic bit [7:0] crc = 8'h00;
    foreach (data[i]) begin
      crc ^= data[i];
      for (int b = 0; b < 8; b++) begin
        if (crc[7]) crc = (crc << 1) ^ 8'h07;
        else crc = crc << 1;
      end
    end
    return crc;
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [7:0] check_vec[9];
    bit [7:0] packets  [5] [$];
    phase.raise_objection(this);

    foreach (check_vec[i]) check_vec[i] = 8'h31 + i[7:0];  // ASCII "123456789"
    if (true_crc8(check_vec) != 8'hF4) begin
      $display("FAIL: true_crc8() got the public check value wrong -- checker itself is broken");
      $fatal(1);
    end

    packets[0] = '{8'h11, 8'h22, 8'hFF};
    packets[1] = '{8'hAA, 8'h01};
    packets[2] = '{8'h00, 8'h00, 8'h00, 8'h80};
    packets[3] = '{8'h5A, 8'hA5, 8'h0F, 8'hF0, 8'h3C};
    packets[4] = '{8'h7E, 8'h81};

    foreach (packets[p]) begin
      automatic bit [7:0] data[] = packets[p];
      automatic bit [7:0] actual = dut_pkg::crc8(data);  // what the "DUT" really outputs
      scoreboard.check(data, actual);

      if (true_crc8(data) == actual) begin
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

    $display("PASS: independent CRC-8/SMBUS predictor caught all 5 real DUT mismatches");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
