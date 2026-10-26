// Behavioral reference for this revision's control-register hardware. Compiled alongside the
// exercise file, never part of what you're fixing -- read it if the register-map doc in the
// exercise file doesn't settle what a given write actually does.
import uvm_pkg::*;

class reg_bus_item extends uvm_sequence_item;
  `uvm_object_utils(reg_bus_item)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  bit is_read;

  function new(string name = "reg_bus_item");
    super.new(name);
  endfunction
endclass

class reg_bus_driver extends uvm_driver #(reg_bus_item);
  `uvm_component_utils(reg_bus_driver)

  bit [7:0] storage = 8'h00;
  bit locked = 1'b0;

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
        automatic bit new_lock = it.data[7];
        if (!locked && !new_lock) storage[6:0] = it.data[6:0];
        storage[7] |= new_lock;
        if (new_lock) locked = 1'b1;
      end
      seq_item_port.item_done();
    end
  endtask
endclass
