// self-test fixture -- not a real exercise. A checker that always passes regardless
// of the class above it, used to prove check_unpatched_fails.py actually catches this
// failure mode. See tests/ci-selftest/README.md.

class widget_item;
  bit [3:0] val;  // deliberately never rand -- doesn't matter, checker below never checks it
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    $display("PASS: nothing was actually verified");
    $finish;
  end
endmodule
