// =================================================================================================
// override uvm_reg's sample() hook -- it runs before the mirror updates
// =================================================================================================
//
// uvm_reg::sample() is called from the base class's do_write()/do_read() once a map has
// auto-prediction on (`set_auto_predict(1)`, done below the checker marker), and its default body
// is empty. A register-model generator normally wires it to a covergroup; by hand, nothing is
// sampled until you override it.
//
// The obvious body asks the field for `val.get_mirrored_value()`. That's wrong: sample() gets
// the access's own `data` before do_predict() runs, on every access, so the mirror still holds
// what the previous access left.
//
// Requirements, overriding `sample(uvm_reg_data_t data, uvm_reg_data_t byte_en, bit is_read,
// uvm_reg_map map)` on `cov_reg` with whatever state it needs:
//
//   1. Every access to this register is recorded.
//   2. What's recorded is the value this access carried, not the field's mirror.
//
// `expected_q` holds what each access carries, in order, filled before each access fires.
// Compare sample()'s value with its front: `match_count++` if they agree, `mismatch_count++`
// if not.
//
// Right now: `match_count=0, want 5`. The stub touches neither counter.
// -------------------------------------------------------------------------------------------------
// Done when: after the four writes and one read below the checker marker, match_count is 5 and
// mismatch_count is 0. Reading the mirror gets every write wrong and the read right only by luck
// (match_count=1, mismatch_count=4).
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class cov_reg extends uvm_reg;
  `uvm_object_utils(cov_reg)

  rand uvm_reg_field val;

  int unsigned match_count    = 0;
  int unsigned mismatch_count = 0;

  uvm_reg_data_t expected_q[$];

  function new(string name = "cov_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 8, 0, "RW", 0, 8'h0, 1, 0, 1);
  endfunction

  // override sample(uvm_reg_data_t data, uvm_reg_data_t byte_en, bit is_read, uvm_reg_map map)
  // below

endclass

// ---8<--- checker below: don't edit ---

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

  bit [31:0] storage;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_bus_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) it.data = storage;
      else storage = it.data;
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

class cov_blk extends uvm_reg_block;
  `uvm_object_utils(cov_blk)

  cov_reg r;

  function new(string name = "cov_blk");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    r = cov_reg::type_id::create("r");
    r.configure(this, null, "");
    r.build();
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    map.add_reg(r, 0, "RW");
    map.set_auto_predict(1);
  endfunction
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  cov_blk           blk;
  reg_bus_sequencer sqr;
  reg_bus_driver    drv;
  reg_bus_adapter   adapter;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    blk = cov_blk::type_id::create("blk");
    blk.build();
    blk.lock_model();
    sqr     = reg_bus_sequencer::type_id::create("sqr", this);
    drv     = reg_bus_driver::type_id::create("drv", this);
    adapter = reg_bus_adapter::type_id::create("adapter");
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

  local task reg_write(bit [7:0] data);
    uvm_status_e status;
    e.blk.r.expected_q.push_back(data);
    e.blk.r.write(status, data, UVM_FRONTDOOR, e.blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: write data=%0h status=%s", data, status.name());
      $fatal(1);
    end
  endtask

  local task reg_read(bit [7:0] expect_data);
    uvm_status_e status;
    bit [31:0] rdata;
    e.blk.r.expected_q.push_back(expect_data);
    e.blk.r.read(status, rdata, UVM_FRONTDOOR, e.blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: read status=%s", status.name());
      $fatal(1);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    reg_write(8'hAA);
    reg_write(8'hBB);
    reg_write(8'hCC);
    reg_write(8'hDD);
    reg_read(8'hDD);  // storage still holds DD from the write just before it

    #1;

    if (e.blk.r.match_count != 5) begin
      $display("FAIL: match_count=%0d, want 5", e.blk.r.match_count);
      $fatal(1);
    end
    if (e.blk.r.mismatch_count != 0) begin
      $display("FAIL: mismatch_count=%0d, want 0", e.blk.r.mismatch_count);
      $fatal(1);
    end
    $display("PASS: match_count=5, mismatch_count=0 -- sample() used the real access value");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
