// =================================================================================================
// write a scoreboard that correlates two independent transaction streams by id, not by arrival
// order
// =================================================================================================
//
// A reference model publishes the expected result of every transaction; a monitor publishes what
// actually came back from the DUT. The two streams don't arrive in the same order as each other --
// the DUT itself reorders responses -- so a scoreboard that just compares the Nth expected item
// against the Nth actual item will misreport perfectly correct traffic as one long string of
// mismatches.
//
// Every transaction (`xaction`) carries an `id` -- the correlation key both sides agree on -- and a
// `data` payload -- the value actually being checked. Write `sb`'s callbacks, and whatever internal
// state you need, so that:
//
//   1. `write_expected(t)` and `write_actual(t)` can each arrive in any order, interleaved
//      arbitrarily with each other and with other ids -- a transaction on one side has to wait,
//      correctly, for its matching id to show up on the other side, however long that takes and
//      regardless of what else arrives in between.
//   2. Once both sides have reported the same `id`: if `data` matches on both sides, increment
//      `match_count`. If `data` differs, increment `mismatch_count` instead -- that's still a
//      completed, resolved comparison, not a leftover.
//   3. The same `id` can legitimately show up more than once over the life of the test -- once a
//      given occurrence is resolved (matched or mismatched), it's consumed. A later, independent
//      occurrence of that same `id` starts a fresh correlation; it is never compared against
//      whatever it was already resolved with, and never silently overwrites an *unresolved*
//      earlier occurrence of the same `id` either -- if `id`=7 arrives twice on one side before
//      its first occurrence has been resolved, both occurrences are still owed a match.
//   4. `pending_count()` returns exactly how many transactions are still waiting, on either side,
//      for their other half to show up, at whatever point it's called.
// -------------------------------------------------------------------------------------------------

import uvm_pkg::*;

class xaction extends uvm_object;
  `uvm_object_utils(xaction)

  int unsigned id;
  int unsigned data;

  function new(string name = "xaction");
    super.new(name);
  endfunction
endclass

`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_actual)

class sb extends uvm_component;
  `uvm_component_utils(sb)

  uvm_analysis_imp_expected #(xaction, sb) expected_export;
  uvm_analysis_imp_actual #(xaction, sb) actual_export;

  int match_count = 0;
  int mismatch_count = 0;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_export = new("expected_export", this);
    actual_export   = new("actual_export", this);
  endfunction

  // write write_expected(), write_actual(), pending_count(), and whatever internal state you need,
  // below

endclass

class env extends uvm_component;
  `uvm_component_utils(env)

  sb scoreboard;

  function new(string name, uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    scoreboard = sb::type_id::create("scoreboard", this);
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

  local function void send_expected(int unsigned id, int unsigned data);
    xaction x = xaction::type_id::create($sformatf("e_%0d_%0d", id, data));
    x.id   = id;
    x.data = data;
    e.scoreboard.expected_export.write(x);
  endfunction

  local function void send_actual(int unsigned id, int unsigned data);
    xaction x = xaction::type_id::create($sformatf("a_%0d_%0d", id, data));
    x.id   = id;
    x.data = data;
    e.scoreboard.actual_export.write(x);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    send_actual(5, 500);
    send_expected(2, 200);
    send_actual(1, 100);
    send_expected(9, 900);
    send_actual(3, 300);
    send_expected(5, 500);
    send_actual(9, 999);  // data mismatch against pending expected(9, 900)
    send_expected(1, 100);
    send_actual(2, 200);
    send_expected(3, 300);
    send_actual(6, 600);
    send_expected(6, 600);
    send_actual(7, 700);
    send_expected(7, 700);
    send_actual(8, 800);
    send_expected(8, 800);
    send_expected(4, 400);
    send_actual(4, 400);
    send_expected(10, 1000);  // no actual counterpart ever arrives
    send_actual(11, 1100);  // no expected counterpart ever arrives
    send_expected(2, 8888);  // id 2 reused after its first occurrence already resolved
    send_actual(2, 9999);  // data mismatch against this second, independent id=2

    // id 99 arrives twice on the expected side before either occurrence is resolved -- both are
    // still owed a match, in order, once the actual side catches up
    send_expected(99, 910);
    send_expected(99, 920);
    send_actual(99, 910);
    send_actual(99, 920);

    #1;

    if (e.scoreboard.match_count != 10) begin
      $display("FAIL: match_count=%0d, want 10", e.scoreboard.match_count);
      $fatal(1);
    end
    if (e.scoreboard.mismatch_count != 2) begin
      $display("FAIL: mismatch_count=%0d, want 2", e.scoreboard.mismatch_count);
      $fatal(1);
    end
    if (e.scoreboard.pending_count() != 2) begin
      $display("FAIL: pending_count()=%0d, want 2 (id 10 and id 11, still unresolved)",
               e.scoreboard.pending_count());
      $fatal(1);
    end
    $display("PASS: match_count=10, mismatch_count=2, pending_count()=2, all correctly correlated");
    phase.drop_objection(this);
  endtask
endclass

module top;
  initial run_test("test");
endmodule
