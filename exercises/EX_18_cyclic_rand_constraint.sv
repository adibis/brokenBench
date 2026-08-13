// EX 18: two constraints that can't both be true
//
// `a == b + 1` and `b == a + 1` each look like an ordinary relational
// constraint on their own. Together, substituting one into the other
// gives `a == a + 2`, which has no solution for any value of `a` at
// all -- not "hard to find," genuinely impossible. This isn't the same
// thing as an ordinary solver-friendly mutual dependency (a solver
// handles `a == b + 1` and `b inside {...}` together just fine); this
// specific pair is a real contradiction hiding behind two constraints
// that each read as reasonable in isolation.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class pair_item;
  rand int a;
  rand int b;
  constraint c_bounds { a inside {[0:100]}; }
  constraint c1 { a == b + 1; }
  constraint c2 { b == a + 1; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    pair_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0 -- the two constraints on a and b contradict each other");
      $fatal(1);
    end

    if (item.a != item.b + 1) begin
      $display("FAIL: a=%0d b=%0d, expected a == b+1", item.a, item.b);
      $fatal(1);
    end

    $display("PASS: a=%0d b=%0d, a == b+1 holds", item.a, item.b);
    $finish;
  end
endmodule
