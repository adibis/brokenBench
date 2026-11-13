// =================================================================================================
// four DMA channel agents, four configured ids, one wrong answer reported four times
// =================================================================================================
//
// The env builds one agent per DMA channel (NUM_CHANNELS of them). Before the env is built, the
// test sets each agent's `channel_id` through `uvm_config_db`: channel 0 gets 10, channel 1
// 20, channel 2 30, channel 3 40.
//
// Before any stimulus, `run_phase` queries every agent concurrently and checks each one owns the
// id it was given. That's much cheaper than finding one channel's traffic on another channel's
// monitor two hours into a regression.
//
// Right now: the check fails, reporting the same id four times.
//
// -------------------------------------------------------------------------------------------------
// Fix the code so every agent reports its own configured id. Don't edit anything at or below the
// "checker" marker.
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
