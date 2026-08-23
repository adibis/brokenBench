// =================================================================================================
// dropping an objection that was never raised doesn't just do nothing -- it's a fatal
// =================================================================================================
//
// `raise_objection()`/`drop_objection()` aren't independent calls -- together they form a counter
// UVM uses to decide when a phase is allowed to end. Every `raise_objection()` has to be matched by
// exactly one `drop_objection()`. Drop one more time than you raised, and UVM doesn't quietly clamp
// the counter at zero -- it reports a real `UVM_FATAL` (`OBJTN_ZERO`), because an objection count
// going negative means something in the testbench's bookkeeping is already wrong, and continuing to
// run on top of that isn't safe.
//
// `run_phase` below does its real work (`recorded = 42;`) correctly, then drops an objection it
// never raised.
//
// Run this: `recorded` does become 42 -- that part isn't the problem -- but a `UVM_FATAL` fires
// right after it.
//
// -------------------------------------------------------------------------------------------------
// Fix `run_phase` so no `UVM_FATAL` occurs. Don't edit anything at or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class test extends uvm_test;
  `uvm_component_utils(test)

  int recorded = -1;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // ---------------------------------------------------------------------------------------------
    // fix this: drop_objection() below has no matching raise_objection()
    // ---------------------------------------------------------------------------------------------
    recorded = 42;
    phase.drop_objection(this);

    phase.raise_objection(this);
    #1;

    // ---8<--- checker below: don't edit ---
    if (uvm_report_server::get_server().get_severity_count(UVM_FATAL) != 0) begin
      $display("FAIL: %0d UVM_FATAL(s) occurred during run_phase",
                uvm_report_server::get_server().get_severity_count(UVM_FATAL));
      $fatal(1);
    end
    if (recorded != 42) begin
      $display("FAIL: recorded=%0d, want 42", recorded);
      $fatal(1);
    end
    $display("PASS: recorded=42, no UVM_FATAL, objection count stayed balanced");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
