// missing rand
//
// A field that's supposed to be randomized every call needs the `rand`
// keyword. Without it, the field is just a plain class member: calling
// .randomize() on the object compiles fine, runs fine, and returns 1
// (success) every time -- but the field itself never actually changes,
// because randomize() only touches fields explicitly declared `rand`
// or `randc`. This is an easy one to miss on a copy-paste: the keyword
// looks decorative until it silently isn't there.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class delay_item;
  bit [7:0] delay;
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    delay_item item = new();
    bit [7:0] seen[5];
    bit all_same = 1;

    for (int i = 0; i < 5; i++) begin
      void'(item.randomize());
      seen[i] = item.delay;
    end

    for (int i = 1; i < 5; i++)
      if (seen[i] != seen[0]) all_same = 0;

    if (all_same) begin
      $display($sformatf({"FAIL: delay never changed across 5 randomize() calls (got %0d every ",
          "time) -- is it actually declared `rand`?"}, seen[0]));
      $fatal(1);
    end else begin
      $display("PASS: delay varied across calls: %p", seen);
      $finish;
    end
  end
endmodule
