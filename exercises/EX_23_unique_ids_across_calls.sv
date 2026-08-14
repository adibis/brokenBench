// =================================================================================================
// EX_23 -- an ID that must never repeat across many randomize() calls
// =================================================================================================
//
// `randc` looks purpose-built for this: IEEE 1800-2023 defines it as cycling through every legal
// value of its declared range exactly once before any value repeats. For a bare randc field with
// no other constraints touching it, that guarantee holds. The moment a constraint DOES touch it --
// even something as small and reasonable-looking as "don't repeat the immediately previous call's
// value" -- the LRM's cycling guarantee is no longer about the constrained legal set. What actually
// happens next is tool-dependent, and worth checking directly rather than assuming.
//
// Randomize this class 40 times in a row with the constraint below in place and watch how soon a
// value repeats. Is it close to what you'd expect from a working cycle-of-16 guarantee, or much
// sooner?
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// This id repeats far sooner than it should. Fix the class so all 16 possible values of id come
// out exactly once, in any order, before a randomize() call is ever allowed to fail or repeat one.
// -------------------------------------------------------------------------------------------------
class id_item;
  randc bit [3:0] id;
  bit [3:0] last_id;
  bit       has_last;

  constraint c_no_immediate_repeat { has_last -> id != last_id; }

  function void post_randomize();
    last_id  = id;
    has_last = 1;
  endfunction
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    id_item item = new();
    bit seen[16];
    int ok;
    bit dup_found = 0;

    for (int t = 0; t < 16; t++) begin
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d (should succeed for 16 calls)", t);
        $fatal(1);
      end
      if (seen[item.id]) begin
        $display("FAIL: id=%0d repeated at call %0d", item.id, t);
        dup_found = 1;
      end
      seen[item.id] = 1;
    end

    if (dup_found) $fatal(1);

    ok = item.randomize();
    if (ok) begin
      $display("FAIL: 17th randomize() succeeded (id=%0d) but all 16 values were already used",
          item.id);
      $fatal(1);
    end

    $display("PASS: 16 calls, all distinct IDs; 17th call correctly failed (exhausted)");
    $finish;
  end
endmodule
