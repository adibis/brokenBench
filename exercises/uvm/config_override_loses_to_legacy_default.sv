// =================================================================================================
// the test's override compiles clean, runs clean, and still silently loses
// =================================================================================================
//
// Early in `build_phase`, the test sets a broad default for everything under the agent -- config
// that predates this test and is meant to apply hierarchy-wide. Further down the same
// `build_phase`, the test sets a specific override for this run, scoped directly through the agent
// handle it just created, since that's the most precise handle available.
//
// Run this: the override is 7. `a.channel_id` comes out 999 -- the broad default -- instead.
//
// `uvm_config_db::set()` computes precedence from the depth of the component passed as its first
// argument, not from which call is more specific or which one runs last. A call scoped through a
// deeper component's handle gets a lower precedence than one scoped through a shallower one, even
// when the deeper call is the one meant to win.
//
// -------------------------------------------------------------------------------------------------
// Fix the test's override so `a.channel_id` ends up 7. Don't touch `chan_agent`, and don't edit
// anything at or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class chan_agent extends uvm_component;
  `uvm_component_utils(chan_agent)

  int channel_id = -1;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int)::get(this, "", "channel_id", channel_id));
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test)

  chan_agent a;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a = chan_agent::type_id::create("a", this);
    // broad default for the whole agent subtree, predates this test
    uvm_config_db#(int)::set(this, "a", "channel_id", 999);
    uvm_config_db#(int)::set(a, "", "channel_id", 7);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #1;

    // ---8<--- checker below: don't edit ---
    if (a.channel_id != 7) begin
      $display("FAIL: a.channel_id=%0d, want 7", a.channel_id);
      $fatal(1);
    end
    $display("PASS: a.channel_id=7, override beat the legacy default");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
