// =================================================================================================
// enable a device through update() without silently clearing a real pending interrupt sitting in
// the same register
// =================================================================================================
//
// `ctrl_reg` packs two fields into one register: `enable` (plain RW) and `irq_pending` (W1C --
// write 1 to clear, matching real hardware: a bus write with that bit set clears the real pending
// flag). `uvm_reg::update()` is supposed to be the convenient way to push only what you changed --
// but it computes what to write for *every* field in the register, not just the one you touched.
// For a W1C field, that computation inverts whatever `desired` currently holds: `desired=0`
// becomes a write of 1 (assert clear). If `irq_pending` was never read first, its `desired` still
// sits at its reset default (0) -- not because anyone decided "clear this," but simply because
// nothing ever told the model otherwise. `update()` can't tell the difference, and silently clears
// a real, currently-pending interrupt nobody asked it to touch.
//
// Write `enabler::enable_device(uvm_reg r, uvm_reg_field enable, uvm_reg_map map)` so that it
// enables the device (`enable` ends up set) *without* corrupting whatever `irq_pending` actually
// holds in hardware at the time. The fix is one extra call, in the right place, before anything
// else -- think about what has to happen before `desired` can be trusted to mean "leave this
// alone" for a field you never meant to touch.
//
// Run this as shipped: it reports `enable=0, want 1` -- the stub does nothing at all yet.
// -------------------------------------------------------------------------------------------------
// Target: after `enable_device` runs, a real frontdoor read-back of the register (below the
// marker) must show enable=1 *and* irq_pending=1 -- the device is on, and the interrupt that was
// genuinely pending before the call is still genuinely pending after it. Calling `enable.set(1)`
// then `r.update(...)` with no read in between gets enable=1 but irq_pending=0 -- it enables the
// device by silently acking an interrupt nobody touched.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class enabler extends uvm_component;
  `uvm_component_utils(enabler)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // write enable_device(uvm_reg r, uvm_reg_field enable, uvm_reg_map map) below

endclass

// ---8<--- checker below: don't edit ---

class ctrl_reg extends uvm_reg;
  `uvm_object_utils(ctrl_reg)

  rand uvm_reg_field enable;
  rand uvm_reg_field irq_pending;

  function new(string name = "ctrl_reg");
    super.new(name, 2, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    enable      = uvm_reg_field::type_id::create("enable");
    irq_pending = uvm_reg_field::type_id::create("irq_pending");
    enable.configure(this, 1, 0, "RW", 0, 1'h0, 1, 0, 1);
    irq_pending.configure(this, 1, 1, "W1C", 0, 1'h0, 1, 0, 1);
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

  // bit 1 (irq_pending) starts real, already pending -- some earlier hardware event the
  // register model hasn't observed yet. bit 0 (enable) starts off.
  bit [31:0] storage = 2'b10;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_bus_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) begin
        it.data = storage;
      end else begin
        if (it.data[1]) storage[1] = 0;  // write-1-to-clear, real hardware side effect
        storage[0] = it.data[0];
      end
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

  ctrl_reg r;

  function new(string name = "reg_blk");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    r = ctrl_reg::type_id::create("r");
    r.configure(this, null, "");
    r.build();
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    map.add_reg(r, 0, "RW");
    map.set_auto_predict(1);
  endfunction
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  reg_blk           blk;
  reg_bus_sequencer sqr;
  reg_bus_driver    drv;
  reg_bus_adapter   adapter;
  enabler           en;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    blk = reg_blk::type_id::create("blk");
    blk.build();
    blk.lock_model();
    sqr     = reg_bus_sequencer::type_id::create("sqr", this);
    drv     = reg_bus_driver::type_id::create("drv", this);
    adapter = reg_bus_adapter::type_id::create("adapter");
    en      = enabler::type_id::create("en", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    blk.default_map.set_sequencer(sqr, adapter);
  endfunction
endclass

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
    uvm_status_e status;
    bit [31:0] rdata;
    phase.raise_objection(this);

    e.en.enable_device(e.blk.r, e.blk.r.enable, e.blk.default_map);

    #1;
    e.blk.r.read(status, rdata, UVM_FRONTDOOR, e.blk.default_map, null);
    if (rdata[0] != 1) begin
      $display("FAIL: enable=%0d, want 1 -- device never actually got enabled", rdata[0]);
      $fatal(1);
    end
    if (rdata[1] != 1) begin
      $display("FAIL: irq_pending=%0d, want 1 -- a real pending interrupt got silently cleared",
               rdata[1]);
      $fatal(1);
    end
    $display("PASS: enable=1, irq_pending=1 -- enabled the device without touching the real irq");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
