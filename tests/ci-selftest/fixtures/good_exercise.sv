// self-test fixture -- not a real exercise. A genuinely correct exercise+patch pair,
// used to prove the checker scripts accept good input, not just reject bad input.
// See tests/ci-selftest/README.md.

class widget_item;
  bit [3:0] val;
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    widget_item item = new();
    bit [3:0] seen[3];
    bit all_same = 1;

    for (int i = 0; i < 3; i++) begin
      void'(item.randomize());
      seen[i] = item.val;
    end

    for (int i = 1; i < 3; i++) if (seen[i] != seen[0]) all_same = 0;

    if (all_same) begin
      $display("FAIL: val never changed across 3 randomize() calls");
      $fatal(1);
    end else begin
      $display("PASS: val varied across calls: %p", seen);
      $finish;
    end
  end
endmodule
