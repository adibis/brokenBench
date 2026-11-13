// =================================================================================================
// catch a write that never reaches hardware -- write()'s status and the mirror both say it did
// =================================================================================================
//
// With auto-prediction on (configured below the checker marker), uvm_reg::write() calls
// do_predict() when the bus transaction completes, and do_predict() only checks the status was
// UVM_IS_OK. A write the hardware silently drops but completes cleanly (a stuck write-enable, say)
// is predicted as a success, and the mirror takes the value you meant to write.
//
// Requirements for `write_verifier::verify_write(uvm_reg r, uvm_reg_map map, bit [7:0] data)`:
//
//   1. It writes through the register layer, like any frontdoor access.
//   2. It confirms the write landed by reading the register back over the bus and comparing:
//      not from write()'s status, and not from `r.get_mirrored_value()`, which already holds
//      the intended value.
//   3. A matching read-back increments `confirmed_count`; a mismatch increments
//      `dropped_count`.
//
// Right now: `confirmed_count=0, want 3`. The stub checks nothing.
// -------------------------------------------------------------------------------------------------
// Done when: of the four registers written below the checker marker, register 2 has a stuck
// write-enable, so confirmed_count is 3 and dropped_count is 1. Checking the mirror instead gives
// confirmed_count=4, dropped_count=0.
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
