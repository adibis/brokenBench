// =================================================================================================
// five items, one bad, and the run dies on it -- with a UVM_FATAL, not a check failure
// =================================================================================================
//
// `run_phase` processes 5 items, each inside its own raise and drop of an objection. Item 2
// fails validation. Its error-handling path works on its own; the trouble is how it combines with
// the rest of the loop body.
//
// Right now: the test never gets past item 2.
//
// -------------------------------------------------------------------------------------------------
// Fix the code so all 5 items are processed, the bad one included, without the simulation dying.
// Don't edit anything at or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class test extends uvm_test;
  `uvm_component_utils(test)

  int unsigned processed_count = 0;
  int unsigned bad_count = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    for (int i = 0; i < 5; i++) begin
      bit is_bad;
      phase.raise_objection(this);
      is_bad = (i == 2);

      if (is_bad) begin
        bad_count++;
        phase.drop_objection(this);
      end

      processed_count++;
      phase.drop_objection(this);
    end
    phase.raise_objection(this);
    #1;

    // ---8<--- checker below: don't edit ---
    if (uvm_report_server::get_server().get_severity_count(UVM_FATAL) != 0) begin
      $display("FAIL: %0d UVM_FATAL(s) occurred during run_phase",
               uvm_report_server::get_server().get_severity_count(UVM_FATAL));
      $fatal(1);
    end
    if (processed_count != 5 || bad_count != 1) begin
      $display("FAIL: processed_count=%0d, bad_count=%0d, want 5, 1", processed_count, bad_count);
      $fatal(1);
    end
    $display("PASS: all 5 items processed, 1 flagged bad, no premature objection underflow");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
