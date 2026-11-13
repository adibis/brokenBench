// =================================================================================================
// every deferred transaction ends up showing the last one's data, not its own
// =================================================================================================
//
// `producer` reuses one `xact` handle for every broadcast rather than allocating a new one, a
// common pattern for a monitor that samples every cycle. `imm_sub` handles each broadcast as it
// arrives and is correct. `batch_sub` defers its checking to the end of the test, which is fine
// on its own.
//
// Right now: `imm_sub` reports every transaction correctly, but `batch_sub` reports the final
// transaction's `id`/`data` for every entry it collected.
//
// -------------------------------------------------------------------------------------------------
// Fix the code so `batch_sub` reports each transaction's `id`/`data` as they were when it
// arrived. Don't edit anything at or below the "checker" marker.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class xact extends uvm_object;
  `uvm_object_utils(xact)

  int unsigned id;
  int unsigned data;

  function new(string name = "xact");
    super.new(name);
  endfunction
endclass

class imm_sub extends uvm_component;
  `uvm_component_utils(imm_sub)

  uvm_analysis_imp #(xact, imm_sub) ap_imp;
  int unsigned seen_id[$];
  int unsigned seen_data[$];

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction

  virtual function void write(xact t);
    seen_id.push_back(t.id);
    seen_data.push_back(t.data);
  endfunction
endclass

class batch_sub extends uvm_component;
  `uvm_component_utils(batch_sub)

  uvm_analysis_imp #(xact, batch_sub) ap_imp;
  xact stored[$];

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
  endfunction

  virtual function void write(xact t);
    stored.push_back(t);
  endfunction
endclass

class producer extends uvm_component;
  `uvm_component_utils(producer)

  uvm_analysis_port #(xact) ap;
  xact cur;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap  = new("ap", this);
    cur = xact::type_id::create("cur");
  endfunction

  virtual task run_phase(uvm_phase phase);
    for (int i = 0; i < 5; i++) begin
      cur.id   = i;
      cur.data = i * 111;
      ap.write(cur);
    end
  endtask
endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  producer  prod;
  imm_sub   imm;
  batch_sub batch;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    prod  = producer::type_id::create("prod", this);
    imm   = imm_sub::type_id::create("imm", this);
    batch = batch_sub::type_id::create("batch", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    prod.ap.connect(imm.ap_imp);
    prod.ap.connect(batch.ap_imp);
  endfunction
endclass

// ---8<--- checker below: don't edit ---

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
    #1;

    if (e.imm.seen_id.size() != 5 || e.batch.stored.size() != 5) begin
      $display("FAIL: imm_sub saw %0d, batch_sub saw %0d (want 5, 5)", e.imm.seen_id.size(),
               e.batch.stored.size());
      $fatal(1);
    end

    for (int i = 0; i < 5; i++) begin
      if (e.imm.seen_id[i] != i || e.imm.seen_data[i] != i * 111) begin
        $display("FAIL: imm_sub entry %0d = (id=%0d, data=%0d), want (id=%0d, data=%0d)", i,
                 e.imm.seen_id[i], e.imm.seen_data[i], i, i * 111);
        $fatal(1);
      end
      if (e.batch.stored[i].id != i || e.batch.stored[i].data != i * 111) begin
        $display("FAIL: batch_sub entry %0d = (id=%0d, data=%0d), want (id=%0d, data=%0d)", i,
                 e.batch.stored[i].id, e.batch.stored[i].data, i, i * 111);
        $fatal(1);
      end
    end

    $display("PASS: all 5 entries correct in both imm_sub and batch_sub");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
