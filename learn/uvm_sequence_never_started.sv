// =================================================================================================
// creating a sequence isn't the same as running it
// =================================================================================================
//
// `my_seq::type_id::create()` allocates a sequence object -- it doesn't put a single item on the
// sequencer. `body()` (where the actual item gets built and sent) only ever runs once something
// calls `.start(sequencer)` on that object. A sequence that's created but never started just sits
// there: no compile error, no runtime error, no `body()`, no item, nothing.
//
// `my_driver` below is correct, working code -- it pulls items off `sqr` and records the last one
// it saw. `my_seq::body()` is correct too -- it builds one item with `value = 42` and sends it.
//
// Run this: `e.drv.received_count` stays 0 -- the driver never gets anything to record.
//
// -------------------------------------------------------------------------------------------------
// Fix `test::run_phase()` so the driver actually receives the item. Don't touch `my_seq` or
// `my_driver`, and don't edit anything at or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class item extends uvm_sequence_item;
  `uvm_object_utils(item)

  int value;

  function new(string name = "item");
    super.new(name);
  endfunction
endclass

class my_sequencer extends uvm_sequencer #(item);
  `uvm_component_utils(my_sequencer)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class my_driver extends uvm_driver #(item);
  `uvm_component_utils(my_driver)

  int received_count = 0;
  int last_value = -1;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    item it;
    forever begin
      seq_item_port.get_next_item(it);
      received_count++;
      last_value = it.value;
      seq_item_port.item_done();
    end
  endtask
endclass

class my_seq extends uvm_sequence #(item);
  `uvm_object_utils(my_seq)

  function new(string name = "my_seq");
    super.new(name);
  endfunction

  virtual task body();
    item it = item::type_id::create("it");
    start_item(it);
    it.value = 42;
    finish_item(it);
  endtask
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  my_sequencer sqr;
  my_driver drv;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = my_sequencer::type_id::create("sqr", this);
    drv = my_driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
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
    my_seq seq;
    phase.raise_objection(this);
    seq = my_seq::type_id::create("seq");
    // ---------------------------------------------------------------------------------------------
    // fix this: seq is created but never started on e.sqr
    // ---------------------------------------------------------------------------------------------
    #1;

    // ---8<--- checker below: don't edit ---
    if (e.drv.received_count != 1) begin
      $display("FAIL: drv.received_count=%0d, want 1 -- was the sequence ever started?",
                e.drv.received_count);
      $fatal(1);
    end
    if (e.drv.last_value != 42) begin
      $display("FAIL: drv.last_value=%0d, want 42", e.drv.last_value);
      $fatal(1);
    end
    $display("PASS: driver received value=42 from the started sequence");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
