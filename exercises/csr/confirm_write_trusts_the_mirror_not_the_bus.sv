// =================================================================================================
// confirm_write() checks the mirror right after the write that set it -- of course it always agrees
// =================================================================================================
//
// SPEC, per the register map doc, status_reg packs one byte into two fields:
//   - cfg: bits [6:0], general configuration, RW.
//   - lock: bit [7] -- "write 1 to lock permanently prevents further configuration changes until
//     the next reset."
//   - NOT settled by that sentence: does "further configuration changes" mean changes requested by
//     a *later* write, or does locking take effect immediately enough to veto a cfg change riding
//     in the very same transaction that sets the lock bit? reg_bus_driver (a separate file,
//     compiled alongside this one) is the actual hardware behavior -- read it if you need to.
//
// -------------------------------------------------------------------------------------------------
// confirmer::confirm_write() below is exactly the kind of helper a model writes with total
// confidence when asked to prove a write landed as intended: with auto-prediction on (the
// default), r.write() sets the mirror directly from the data you handed it, before the bus
// transaction even happens, so checking the mirror right after your own write will always agree
// with what you just told it. Run this as shipped: it reports confirmed_count=3, flagged_count=0 --
// every write "confirmed," including the ones that tried to change cfg and lock in the same
// transaction, and silently didn't change cfg.
//
// -------------------------------------------------------------------------------------------------
// Fix confirm_write() so it checks what the bus actually reports -- an actual frontdoor read, not
// the mirror -- against `expected`. Don't edit anything at or below the "checker" marker; it's
// correct as given and is what's judging you.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class status_reg extends uvm_reg;
  `uvm_object_utils(status_reg)

  rand uvm_reg_field val;

  function new(string name = "status_reg");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 8, 0, "RW", 0, 8'h0, 1, 0, 1);
  endfunction
endclass

class reg_bus_sequencer extends uvm_sequencer #(reg_bus_item);
  `uvm_component_utils(reg_bus_sequencer)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
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

  status_reg r;

  function new(string name = "reg_blk");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    uvm_reg_map map;
    r = status_reg::type_id::create("r");
    r.configure(this, null, "");
    r.build();
    map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
    map.add_reg(r, 0, "RW");
    map.set_auto_predict(1);
  endfunction
endclass

class confirmer;
  int unsigned confirmed_count = 0;
  int unsigned flagged_count   = 0;

  task confirm_write(uvm_reg r, uvm_reg_map map, bit [7:0] expected);
    if (r.get_mirrored_value() == expected) confirmed_count++;
    else flagged_count++;
  endtask
endclass

// ---8<--- checker below: don't edit ---

class test extends uvm_test;
  `uvm_component_utils(test)

  reg_blk           blk;
  reg_bus_sequencer sqr;
  reg_bus_driver    drv;
  reg_bus_adapter   adapter;
  confirmer         cfm;

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
    cfm     = new();
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    blk.default_map.set_sequencer(sqr, adapter);
  endfunction

  local task reg_write(bit [7:0] data);
    uvm_status_e status;
    blk.r.write(status, data, UVM_FRONTDOOR, blk.default_map, null);
    if (status != UVM_IS_OK) begin
      $display("FAIL: write data=%0h status=%s", data, status.name());
      $fatal(1);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    reg_write(8'h2A);  // cfg=0x2A, lock=0 -- unlocked, this one genuinely lands
    cfm.confirm_write(blk.r, blk.default_map, 8'h2A);

    reg_write(8'hBB);  // cfg=0x3B, lock=1 -- same transaction sets lock AND tries to change cfg
    cfm.confirm_write(blk.r, blk.default_map, 8'hBB);

    reg_write(8'hCC);  // cfg=0x4C, lock=1 -- already locked from the write above
    cfm.confirm_write(blk.r, blk.default_map, 8'hCC);

    if (cfm.confirmed_count != 1 || cfm.flagged_count != 2) begin
      $display($sformatf({"FAIL: confirmed_count=%0d, flagged_count=%0d -- want 1 and 2. Only the ",
                          "first write (unlocked) actually lands as written; the next two set the ",
                          "lock bit in the same transaction as a cfg change, and hardware vetoes ",
                          "that cfg change on the spot -- an independent check must catch both"},
                           cfm.confirmed_count, cfm.flagged_count));
      $fatal(1);
    end

    $display("PASS: confirmed_count=1, flagged_count=2 -- confirm_write checked the bus, not its ",
             "own mirror");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
