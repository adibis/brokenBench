// =================================================================================================
// wire up a uvm_reg_predictor -- in explicit-prediction mode, it's the only thing that ever
// updates the mirror, and "the fields look set up right" doesn't mean it's actually connected
// =================================================================================================
//
// `blk`'s map runs with auto-prediction off (`set_auto_predict(0)`, below the marker) -- a
// deliberate choice real testbenches make when something other than this register model's own
// write()/read() calls can also touch the DUT, and the mirror has to track reality from observed
// bus traffic instead of just trusting its own API calls. With auto-prediction off, calling
// `blk.r.write(...)` still genuinely writes through the bus -- but it does *not* touch the mirror
// at all. The only thing that can ever update it is a `uvm_reg_predictor` that's actually wired
// up: `.map` and `.adapter` set, *and* something feeding it real bus transactions through its
// `bus_in` analysis port.
//
// `predictor` is already constructed for you (see `env::build_phase`, below the marker) -- an
// unconfigured, unconnected `uvm_reg_predictor#(reg_bus_item)` sitting there doing nothing. Finish
// wiring it up in `env::connect_phase`, below, so that:
//
//   1. `predictor.map` and `predictor.adapter` are set to the same map/adapter the bus itself uses.
//   2. `drv.ap` (the driver's own analysis port -- every access it completes gets broadcast there)
//      is connected to `predictor.bus_in`.
//
// Run this as shipped: it reports `mirror=0 after first write, want aa` -- setting .map/.adapter
// alone isn't enough either; the predictor's write() callback never even gets called until its
// bus_in import actually has something connected to it.
// -------------------------------------------------------------------------------------------------
// Target: after each of two writes below the marker, blk.r.get_mirrored_value() must equal exactly
// what was just written. Leaving out either .map/.adapter or the bus_in connection leaves the
// mirror stuck at its reset value (0) forever, regardless of how many writes actually succeed on
// the bus.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class plain_reg extends uvm_reg;
  `uvm_object_utils(plain_reg)

  rand uvm_reg_field val;

  function new(string name = "plain_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 8, 0, "RW", 0, 8'h0, 1, 0, 1);
  endfunction
endclass

class reg_bus_item extends uvm_sequence_item;
  `uvm_object_utils(reg_bus_item)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  bit is_read;

  function new(string name = "reg_bus_item");
    super.new(name);
  endfunction
endclass

class reg_bus_sequencer extends uvm_sequencer #(reg_bus_item);
  `uvm_component_utils(reg_bus_sequencer)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class reg_bus_driver extends uvm_driver #(reg_bus_item);
  `uvm_component_utils(reg_bus_driver)

  uvm_analysis_port #(reg_bus_item) ap;
  bit [31:0] storage;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_bus_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) it.data = storage;
      else storage = it.data;
      ap.write(it);
      seq_item_port.item_done();
    end
  endtask
endclass

class reg_bus_adapter extends uvm_reg_adapter;
  `uvm_object_utils(reg_bus_adapter)

  function new(string name = "reg_bus_adapter");
    super.new(name);
    supports_byte_enable = 0;
    provides_responses   = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    reg_bus_item it = reg_bus_item::type_id::create("it");
    it.addr    = rw.addr[31:0];
    it.data    = rw.data[31:0];
    it.is_read = (rw.kind == UVM_READ);
    return it;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    reg_bus_item it;
    if (!$cast(it, bus_item)) `uvm_fatal("reg_bus_adapter", "bad cast")
    rw.kind   = it.is_read ? UVM_READ : UVM_WRITE;
    rw.addr   = it.addr;
    rw.data   = it.data;
    rw.status = UVM_IS_OK;
  endfunction
endclass

class reg_blk extends uvm_reg_block;
  `uvm_object_utils(reg_blk)

  plain_reg r;

  function new(string name = "reg_blk");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    r = plain_reg::type_id::create("r");
    r.configure(this, null, "");
    r.build();
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    map.add_reg(r, 0, "RW");
    map.set_auto_predict(0);  // explicit prediction -- the predictor is the only path in
  endfunction
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  reg_blk                           blk;
  reg_bus_sequencer                 sqr;
  reg_bus_driver                    drv;
  reg_bus_adapter                   adapter;
  uvm_reg_predictor #(reg_bus_item) predictor;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    blk = reg_blk::type_id::create("blk");
    blk.build();
    blk.lock_model();
    sqr       = reg_bus_sequencer::type_id::create("sqr", this);
    drv       = reg_bus_driver::type_id::create("drv", this);
    adapter   = reg_bus_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(reg_bus_item)::type_id::create("predictor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    blk.default_map.set_sequencer(sqr, adapter);

    // wire predictor.map, predictor.adapter, and drv.ap -> predictor.bus_in below

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

  local task reg_write(bit [7:0] data);
    uvm_status_e status;
    e.blk.r.write(status, data, UVM_FRONTDOOR, e.blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: write data=%0h status=%s", data, status.name());
      $fatal(1);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    reg_write(8'hAA);
    #1;
    if (e.blk.r.get_mirrored_value() != 8'hAA) begin
      $display("FAIL: mirror=%0h after first write, want aa", e.blk.r.get_mirrored_value());
      $fatal(1);
    end

    reg_write(8'hBB);
    #1;
    if (e.blk.r.get_mirrored_value() != 8'hBB) begin
      $display("FAIL: mirror=%0h after second write, want bb", e.blk.r.get_mirrored_value());
      $fatal(1);
    end

    $display("PASS: mirror correctly tracked both writes through the predictor");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
