// =================================================================================================
// write mem_checker so it catches a real address-decode corruption bug -- uvm_mem itself keeps
// no record of what any address should currently hold
// =================================================================================================
//
// uvm_reg has a mirror: ask a field what it should currently read, and the register layer answers
// from its own tracked state. uvm_mem has no such thing. A uvm_mem object is a placeholder for an
// address range and nothing else -- every write/read just moves data across the bus layer, and the
// instant it's done, nothing in the register model remembers what any given address was last set
// to. If a scoreboard needs to know whether a later read came back correct, that expected state has
// to be built by hand, keyed by address, from scratch.
//
// `mem_checker` sits on the driver's analysis port and sees every completed access, write and read
// alike, in the order they actually happen on the bus. Implement `write(mem_item it)` (and whatever
// member state you need) so that:
//
//   1. A write at some address records what that address should read back as -- and that recorded
//      value survives any number of *other* addresses being written in between, right up until a
//      write actually lands on that same address again.
//   2. A read increments `match_count` if it returns the value last written to that same address,
//      or `mismatch_count` otherwise -- and it's still `mismatch_count`, not something you silently
//      drop, when the data legitimately doesn't match (that's the whole point: it means the bus
//      actually returned something other than what was last written there).
//
// Run this as shipped: it reports `match_count=0, want 4` -- the stub doesn't track anything at all.
// -------------------------------------------------------------------------------------------------
// Target: after the exact access sequence below the checker marker runs, `match_count` must be 4
// and `mismatch_count` must be 1 -- not merely nonzero. One of those five reads really does land on
// corrupted data (a real address-decode bug in the driver, not a bug in your checker), and your
// checker has to be the thing that catches it.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class mem_item extends uvm_sequence_item;
  `uvm_object_utils(mem_item)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  bit is_read;

  function new(string name = "mem_item");
    super.new(name);
  endfunction
endclass

class mem_checker extends uvm_component;
  `uvm_component_utils(mem_checker)

  uvm_analysis_imp#(mem_item, mem_checker) ap_imp;

  int unsigned match_count    = 0;
  int unsigned mismatch_count = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction

  // write write(mem_item it), and whatever member state it needs, below

endclass

// ---8<--- checker below: don't edit ---

class mem_sequencer extends uvm_sequencer #(mem_item);
  `uvm_component_utils(mem_sequencer)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class mem_driver extends uvm_driver #(mem_item);
  `uvm_component_utils(mem_driver)

  uvm_analysis_port #(mem_item) ap;

  // 16 real storage locations, decoded off addr[3:0] only -- a classic incomplete
  // address-decode bug. Any address with the same low 4 bits aliases the same word.
  bit [31:0] storage[0:15];

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    mem_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) it.data = storage[it.addr[3:0]];
      else storage[it.addr[3:0]] = it.data;
      ap.write(it);
      seq_item_port.item_done();
    end
  endtask
endclass

class mem_adapter extends uvm_reg_adapter;
  `uvm_object_utils(mem_adapter)

  function new(string name = "mem_adapter");
    super.new(name);
    supports_byte_enable = 0;
    provides_responses   = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    mem_item it = mem_item::type_id::create("it");
    it.addr    = rw.addr[31:0];
    it.data    = rw.data[31:0];
    it.is_read = (rw.kind == UVM_READ);
    return it;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    mem_item it;
    if (!$cast(it, bus_item)) `uvm_fatal("mem_adapter", "bad cast")
    rw.kind   = it.is_read ? UVM_READ : UVM_WRITE;
    rw.addr   = it.addr;
    rw.data   = it.data;
    rw.status = UVM_IS_OK;
  endfunction
endclass

class mem_block extends uvm_reg_block;
  `uvm_object_utils(mem_block)

  uvm_mem m;

  function new(string name = "mem_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    m = new("m", 32, 32, "RW");
    m.configure(this);
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    map.add_mem(m, 0);
  endfunction
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  mem_block     blk;
  mem_sequencer sqr;
  mem_driver    drv;
  mem_adapter   adapter;
  mem_checker   chk;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    blk = mem_block::type_id::create("blk");
    blk.build();
    blk.lock_model();
    sqr     = mem_sequencer::type_id::create("sqr", this);
    drv     = mem_driver::type_id::create("drv", this);
    adapter = mem_adapter::type_id::create("adapter");
    chk     = mem_checker::type_id::create("chk", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    drv.ap.connect(chk.ap_imp);
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

  local task mem_write(bit [31:0] addr, bit [31:0] data);
    uvm_status_e status;
    e.blk.m.write(status, addr, data, UVM_FRONTDOOR, e.blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: write to addr=%0h status=%s", addr, status.name());
      $fatal(1);
    end
  endtask

  local task mem_read(bit [31:0] addr);
    uvm_status_e status;
    bit [31:0] rdata;
    e.blk.m.read(status, addr, rdata, UVM_FRONTDOOR, e.blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: read from addr=%0h status=%s", addr, status.name());
      $fatal(1);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    mem_write(0, 32'hAAAA_0000);
    mem_write(1, 32'hBBBB_0001);
    mem_read(0);  // must still match -- an unrelated address was written in between
    mem_write(2, 32'hDDDD_0002);
    mem_read(1);  // same: survives an interleaving write to a different address
    // addr 16 decodes to the same storage word as addr 0 (decode bug, addr[3:0] only) --
    // this silently corrupts whatever addr 0 held.
    mem_write(16, 32'hCCCC_0010);
    mem_read(0);  // real corruption: addr 0 now reads back addr 16's data
    mem_read(16);
    mem_read(2);  // unaffected address, still correct

    #1;

    if (e.chk.match_count != 4) begin
      $display("FAIL: match_count=%0d, want 4", e.chk.match_count);
      $fatal(1);
    end
    if (e.chk.mismatch_count != 1) begin
      $display("FAIL: mismatch_count=%0d, want 1", e.chk.mismatch_count);
      $fatal(1);
    end
    $display("PASS: match_count=4, mismatch_count=1 -- shadow model caught the real corruption");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
