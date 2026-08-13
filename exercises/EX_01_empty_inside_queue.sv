// 008: inside {} against a queue that was never populated
//
// `val inside {legal_vals}` is a perfectly normal way to constrain a
// field to a runtime-computed set of legal values instead of a fixed
// range. It only works if something actually puts values into that
// queue before .randomize() runs. An empty queue doesn't mean "no
// restriction" -- it means there's nothing val is allowed to be, and
// the constraint is unsatisfiable every single time.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class legal_item;
  rand int val;
  int legal_vals[$];
  constraint c_legal { val inside {legal_vals}; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    legal_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0 -- legal_vals.size()=%0d", item.legal_vals.size());
      $fatal(1);
    end else begin
      $display("PASS: val=%0d chosen from legal_vals=%p", item.val, item.legal_vals);
      $finish;
    end
  end
endmodule
