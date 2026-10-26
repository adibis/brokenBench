// =================================================================================================
// confirm_write() checks the mirror right after the write that set it -- of course it always agrees
// =================================================================================================
//
// val is modeled as a plain 8-bit RW field, but bit[7] of the real register is wired off in this
// revision of the silicon: it always reads back 0, no matter what gets written to it. Nobody
// updated the register model to say so -- it still claims all 8 bits are writable. With
// auto-prediction on (the default), r.write() sets the mirror directly from the data you handed
// it, before the bus transaction even happens -- the mirror is a prediction of what you asked for,
// not a report of what hardware actually did.
//
// confirmer::confirm_write() is supposed to prove a write actually landed as intended. Run this as
// shipped: it reports confirmed_count=2, flagged_count=0 -- every write "confirmed," including the
// one that tried to set the reserved bit and silently didn't.
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

  // bit[7] is wired off in the real silicon -- a write never actually sets it, regardless of
  // what the bus asked for
  bit [7:0] storage = 8'h00;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_bus_item it;
    forever begin
      seq_item_port.get_next_item(it);
      if (it.is_read) it.data = storage;
      else storage = it.data[7:0] & 8'h7F;
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

    reg_write(8'hFF);  // tries to set every bit, including the wired-off one
    cfm.confirm_write(blk.r, blk.default_map, 8'hFF);

    reg_write(8'h3C);  // touches no reserved bits -- this one genuinely lands as written
    cfm.confirm_write(blk.r, blk.default_map, 8'h3C);

    if (cfm.confirmed_count != 1 || cfm.flagged_count != 1) begin
      $display($sformatf({"FAIL: confirmed_count=%0d, flagged_count=%0d -- want 1 and 1. The ",
                          "0xFF write didn't land as written (bit 7 is wired off) and must be ",
                          "flagged; the 0x3C write genuinely landed and must be confirmed"},
                           cfm.confirmed_count, cfm.flagged_count));
      $fatal(1);
    end

    $display("PASS: confirmed_count=1, flagged_count=1 -- confirm_write checked the bus, not ",
             "its own mirror");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
