// =================================================================================================
// uvm_config_db::get() works fine -- nobody ever called set()
// =================================================================================================
//
// `uvm_config_db` is just a global, hierarchy-scoped lookup table: `set()` writes an entry keyed by
// (component path, field name), `get()` reads one back. The two calls aren't a matched pair the way
// a constructor and a destructor are -- `get()` doesn't require a `set()` to exist. If no entry
// matches, `get()` returns 0 and quietly leaves the variable it was given exactly as it was. No
// error, no warning, nothing -- the component just keeps running with whatever default it already
// had.
//
// `worker` below reads its own `mode` via `uvm_config_db#(int)::get()` in its own `build_phase()`.
// That's correct, working code -- the bug isn't there.
//
// Run this: `w.mode` stays -1, `worker`'s uninitialized default, instead of becoming 1.
//
// -------------------------------------------------------------------------------------------------
// Fix `test::build_phase()` so `w.mode` ends up 1. Don't touch `worker`, and don't edit anything at
// or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class worker extends uvm_component;
  `uvm_component_utils(worker)

  int mode = -1;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int)::get(this, "", "mode", mode));
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test)

  worker w;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // ---------------------------------------------------------------------------------------------
    // fix this: configure w's mode to 1 via uvm_config_db before it's created
    // ---------------------------------------------------------------------------------------------
    w = worker::type_id::create("w", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #1;

    // ---8<--- checker below: don't edit ---
    if (w.mode != 1) begin
      $display("FAIL: w.mode=%0d, want 1 -- was uvm_config_db#(int)::set() ever called?", w.mode);
      $fatal(1);
    end
    $display("PASS: w.mode=1, configured through uvm_config_db");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
