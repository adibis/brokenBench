// =================================================================================================
// factory override compiles clean and runs clean, but the DUT's parity checker never actually
// gets tested
// =================================================================================================
//
// A register-write test wants to run with an error-injecting driver instead of the normal one, so
// the DUT's write-parity checker actually gets exercised: the error-injecting driver corrupts one
// bit of every write, and the checker is supposed to catch it. Swapping drivers is done with a
// factory type override -- `base_write_driver` -> `error_inject_write_driver` -- so the env's own
// code never has to know the error-injecting variant exists.
//
// Run this: the test believes it configured the error-injecting driver, but `env.drv` is still a
// plain `base_write_driver`.
//
// -------------------------------------------------------------------------------------------------
// Fix the code so `env.drv` really is an `error_inject_write_driver`. Don't edit anything at or
// below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class base_write_driver extends uvm_component;
  `uvm_component_utils(base_write_driver)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class error_inject_write_driver extends base_write_driver;
  `uvm_component_utils(error_inject_write_driver)

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class reg_env extends uvm_component;
  `uvm_component_utils(reg_env)

  base_write_driver drv;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = base_write_driver::type_id::create("drv", this);
  endfunction
endclass

// ---------------------------------------------------------------------------------------------
// override the base_write_driver with error_inject_write_driver here.
// ---------------------------------------------------------------------------------------------
class test extends uvm_test;
  `uvm_component_utils(test)

  reg_env env;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = reg_env::type_id::create("env", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #1;

    // ---8<--- checker below: don't edit ---
    if (env.drv.get_type_name() != "error_inject_write_driver") begin
      $display("FAIL: env.drv is a %s, expected error_inject_write_driver",
               env.drv.get_type_name());
      $fatal(1);
    end
    $display("PASS: env.drv is an error_inject_write_driver as configured");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
