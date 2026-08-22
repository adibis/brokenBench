// =================================================================================================
// write coord_vseq::body() so channel B's item carries the exact value channel A's driver actually
// processed -- not a value you compute or guess ahead of time
// =================================================================================================
//
// coord_vseqr is already wired (see env below) to three things: `chan_a_sqr` and `chan_b_sqr`, the
// two real channel sequencers to send items on, and `chan_a_drv`, channel A's driver -- the only
// place that ever learns what tag channel A's item actually carried, once it's actually been
// driven.
//
// Write `coord_vseq::body()` so that:
//
//   1. It sends exactly one item on `p_sequencer.chan_a_sqr`, with `tag` set to any value of your
//      choosing (e.g. `$urandom`).
//   2. Concurrently -- via `fork`/`join`, not one item after the other -- it sends exactly one item
//      on `p_sequencer.chan_b_sqr`, with `tag` set to the exact value `p_sequencer.chan_a_drv`
//      recorded for channel A's item.
//
// `p_sequencer.chan_a_drv.last_tag` only becomes correct once channel A's driver has actually
// pulled the item and processed it -- not the instant you call `start_item` on channel A, and not
// just because your channel A branch happens to be the first one written in the `fork`. Reading it
// too early doesn't error -- it silently reads whatever channel A's driver last recorded, which at
// the very start of the test is nothing at all.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class item extends uvm_sequence_item;
  `uvm_object_utils(item)

  int tag;

  function new(string name = "item");
    super.new(name);
  endfunction
endclass

class chan_sequencer extends uvm_sequencer #(item);
  `uvm_component_utils(chan_sequencer)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class chan_driver extends uvm_driver #(item);
  `uvm_component_utils(chan_driver)

  int received_count = 0;
  int last_tag = -1;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    item it;
    forever begin
      seq_item_port.get_next_item(it);
      received_count++;
      last_tag = it.tag;
      seq_item_port.item_done();
    end
  endtask
endclass

class chan_agent extends uvm_component;
  `uvm_component_utils(chan_agent)

  chan_sequencer sqr;
  chan_driver drv;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = chan_sequencer::type_id::create("sqr", this);
    drv = chan_driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

class coord_vseqr extends uvm_sequencer #(item);
  `uvm_component_utils(coord_vseqr)

  chan_sequencer chan_a_sqr;
  chan_sequencer chan_b_sqr;
  chan_driver chan_a_drv;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class coord_vseq extends uvm_sequence #(item);
  `uvm_object_utils(coord_vseq)
  `uvm_declare_p_sequencer(coord_vseqr)

  function new(string name = "coord_vseq");
    super.new(name);
  endfunction

  virtual task body();
    // write your virtual sequence body here
  endtask
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  chan_agent  chan_a;
  chan_agent  chan_b;
  coord_vseqr vseqr;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    chan_a = chan_agent::type_id::create("chan_a", this);
    chan_b = chan_agent::type_id::create("chan_b", this);
    vseqr  = coord_vseqr::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    vseqr.chan_a_sqr = chan_a.sqr;
    vseqr.chan_b_sqr = chan_b.sqr;
    vseqr.chan_a_drv = chan_a.drv;
  endfunction
endclass

// ---8<--- checker below: don't edit ---

class test extends uvm_test;
  `uvm_component_utils(test)

  env e;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e = env::type_id::create("e", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    coord_vseq vseq;
    phase.raise_objection(this);
    vseq = coord_vseq::type_id::create("vseq");
    vseq.start(e.vseqr);
    #1;

    if (e.chan_a.drv.received_count != 1 || e.chan_b.drv.received_count != 1) begin
      $display("FAIL: received_count (chan_a, chan_b) = %0d, %0d (want 1, 1)",
               e.chan_a.drv.received_count, e.chan_b.drv.received_count);
      $fatal(1);
    end
    if (e.chan_a.drv.last_tag == -1 || e.chan_b.drv.last_tag == -1) begin
      $display("FAIL: last_tag (chan_a, chan_b) = %0d, %0d -- a driver never received a real tag",
               e.chan_a.drv.last_tag, e.chan_b.drv.last_tag);
      $fatal(1);
    end
    if (e.chan_a.drv.last_tag != e.chan_b.drv.last_tag) begin
      $display("FAIL: chan_a tag=%0d does not match chan_b tag=%0d -- not properly synchronized",
               e.chan_a.drv.last_tag, e.chan_b.drv.last_tag);
      $fatal(1);
    end
    $display("PASS: chan_a and chan_b both received tag=%0d, properly synchronized",
             e.chan_a.drv.last_tag);
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
