// =================================================================================================
// four DMA channel agents, four configured channel ids, one wrong answer reported four times
// =================================================================================================
//
// A DMA subsystem env builds one agent per channel -- NUM_CHANNELS of them, each one talking to a
// different hardware DMA channel. Every agent needs to know which channel it owns, so the test
// configures each agent's `channel_id` via `uvm_config_db` before the env is built: channel 0 must
// end up owning id 10, channel 1 owning 20, channel 2 owning 30, channel 3 owning 40.
//
// Before trusting the rest of the environment to run real stimulus, `run_phase` does a standard
// sanity check first: query every channel agent concurrently and confirm each one owns the
// channel the test actually configured it for. Catching a wiring mistake here, before stimulus
// starts, is a lot cheaper than debugging why traffic meant for one channel mysteriously shows up
// on a different channel's monitor two hours into a regression.
//
// Run this: the sanity check fails, and it reports the same channel id four times.
//
// -------------------------------------------------------------------------------------------------
// Fix the code so every channel agent reports its own configured id. Don't edit anything at or
// below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

localparam int NUM_CHANNELS = 4;

class dma_channel_agent extends uvm_component;
  `uvm_component_utils(dma_channel_agent)

  int channel_id;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(int)::get(this, "", "channel_id", channel_id)) channel_id = -1;
  endfunction
endclass

class dma_env extends uvm_component;
  `uvm_component_utils(dma_env)

  dma_channel_agent channels[NUM_CHANNELS];

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (channels[k]) begin
      channels[k] = dma_channel_agent::type_id::create($sformatf("channels[%0d]", k), this);
    end
  endfunction
endclass

class test extends uvm_test;
  `uvm_component_utils(test)

  dma_env e;
  int reported_ids[$];
  int i;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // ---------------------------------------------------------------------------------------------
    // fix this: give each channel agent its own id via uvm_config_db --
    // channel 0 -> 10, channel 1 -> 20, channel 2 -> 30, channel 3 -> 40
    // ---------------------------------------------------------------------------------------------
    e = dma_env::type_id::create("e", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    int expected_ids[$];
    int got_ids[$];

    phase.raise_objection(this);

    // ---------------------------------------------------------------------------------------------
    // fix this: sanity-check every channel agent's own configured id, concurrently
    // ---------------------------------------------------------------------------------------------
    foreach (e.channels[k]) begin
      i = k;
      fork
        begin
          #1;
          reported_ids.push_back(e.channels[i].channel_id);
        end
      join_none
    end
    wait fork;
    // ---------------------------------------------------------------------------------------------

    // ---8<--- checker below: don't edit ---
    for (int k = 0; k < NUM_CHANNELS; k++) expected_ids.push_back((k + 1) * 10);
    got_ids = reported_ids;
    got_ids.sort();

    if (got_ids != expected_ids) begin
      $display("FAIL: channel ids reported (sorted)=%p, expected %p", got_ids, expected_ids);
      $fatal(1);
    end
    $display("PASS: all %0d channel agents reported their own configured id", NUM_CHANNELS);
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
