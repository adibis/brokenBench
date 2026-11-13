// =================================================================================================
// dropping an objection that was never raised is a fatal, not a no-op
// =================================================================================================
//
// `raise_objection()` and `drop_objection()` drive a counter that decides when a phase may end,
// so every raise needs exactly one drop. Drop more than you raised and UVM reports `UVM_FATAL`
// (`OBJTN_ZERO`) rather than clamping the count at zero.
//
// `run_phase` does its work (`recorded = 42;`) correctly, then drops an objection it never
// raised.
//
// Right now: `recorded` becomes 42, then a `UVM_FATAL` fires.
//
// -------------------------------------------------------------------------------------------------
// Fix `run_phase` so no `UVM_FATAL` occurs. Don't edit anything at or below the "checker"
// marker.
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
