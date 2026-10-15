// =================================================================================================
// catch a write that silently never reaches hardware -- neither write()'s own status nor the
// register model's mirror can tell you that on their own
// =================================================================================================
//
// With auto-prediction on (already configured for you below the marker), uvm_reg::write() calls
// do_predict() once the bus transaction completes -- but do_predict() only looks at whether the
// transaction's own reported status came back UVM_IS_OK. It has no independent way to confirm the
// hardware actually did anything: a write that's silently dropped but still completes cleanly (no
// bus error, no timeout -- a stuck write-enable signal, a realistic hardware bug, not a contrived
// one) still gets predicted as a success, and the register model's mirror updates to match the
// value you *intended* to write, not whatever's actually sitting in hardware.
//
// Write `write_verifier::verify_write(uvm_reg r, uvm_reg_map map, bit [7:0] data)` so that:
//
//   1. It performs the write through the register layer, same as any other frontdoor access.
//   2. It independently confirms the write actually landed -- not by trusting write()'s own
//      status, and not by trusting `r.get_mirrored_value()` right afterward (do_predict() already
//      updated it to the intended value regardless of what hardware did) -- the only way to really
//      know is to read the register back through the bus and compare what actually comes back.
//   3. `confirmed_count` counts a write whose read-back matches; `dropped_count` counts one whose
//      read-back doesn't -- and it's still `dropped_count`, not something silently ignored, when a
//      write legitimately never reached hardware (that's the whole point of this check existing).
//
// Run this as shipped: it reports `confirmed_count=0, want 3` -- the stub never actually checks
// anything.
// -------------------------------------------------------------------------------------------------
// Target: of the four registers written below the marker, exactly one (register 2) has a stuck
// write-enable and never actually updates -- confirmed_count must be 3, dropped_count must be 1.
// Checking get_mirrored_value() instead of reading back gets this wrong for all four registers
// (confirmed_count=4, dropped_count=0) -- do_predict() predicts success from the transaction's
// reported status alone, which this specific hardware bug can't help but report as clean.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class write_verifier extends uvm_component;
  `uvm_component_utils(write_verifier)

  int unsigned confirmed_count = 0;
  int unsigned dropped_count   = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // write verify_write(uvm_reg r, uvm_reg_map map, bit [7:0] data) below

endclass

// ---8<--- checker below: don't edit ---

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

  bit [31:0] storage[0:3];

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_bus_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) begin
        it.data = storage[it.addr[1:0]];
      end else begin
        // register 2's write-enable is stuck off -- the bus transaction still completes
        // cleanly, nothing ever errors, the write just never lands in storage.
        if (it.addr[1:0] != 2) storage[it.addr[1:0]] = it.data;
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

  plain_reg regs[4];

  function new(string name = "reg_blk");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    foreach (regs[i]) begin
      regs[i] = plain_reg::type_id::create($sformatf("regs[%0d]", i));
      regs[i].configure(this, null, "");
      regs[i].build();
      map.add_reg(regs[i], i, "RW");
    end
    map.set_auto_predict(1);
  endfunction
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  reg_blk           blk;
  reg_bus_sequencer sqr;
  reg_bus_driver    drv;
  reg_bus_adapter   adapter;
  write_verifier    verifier;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    blk = reg_blk::type_id::create("blk");
    blk.build();
    blk.lock_model();
    sqr      = reg_bus_sequencer::type_id::create("sqr", this);
    drv      = reg_bus_driver::type_id::create("drv", this);
    adapter  = reg_bus_adapter::type_id::create("adapter");
    verifier = write_verifier::type_id::create("verifier", this);
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
    phase.raise_objection(this);

    foreach (e.blk.regs[i]) begin
      e.verifier.verify_write(e.blk.regs[i], e.blk.default_map, 8'hA0 + i);
    end

    #1;

    if (e.verifier.confirmed_count != 3) begin
      $display("FAIL: confirmed_count=%0d, want 3", e.verifier.confirmed_count);
      $fatal(1);
    end
    if (e.verifier.dropped_count != 1) begin
      $display("FAIL: dropped_count=%0d, want 1", e.verifier.dropped_count);
      $fatal(1);
    end
    $display("PASS: confirmed_count=3, dropped_count=1 -- caught the stuck write-enable on reg 2");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
