// = inside a constraint block
//
// Inside a constraint block, `==` means equality and `=` is not a valid
// constraint operator at all -- it's not silently reinterpreted as
// assignment either, it's simply illegal there. This is exactly the kind
// of typo that's easy to make coming from procedural code, where `=` is
// assignment everywhere. The compiler will refuse this file outright;
// read its error message, it's the whole "checker" for this exercise.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class mode_item;
  rand bit [1:0] mode;
  constraint c_mode { mode = 2'b01; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    mode_item item = new();
    int ok = item.randomize();

    if (!ok || item.mode !== 2'b01) begin
      $display("FAIL: randomize() ok=%0d mode=%b, expected mode==01", ok, item.mode);
      $fatal(1);
    end else begin
      $display("PASS: mode=%b", item.mode);
      $finish;
    end
  end
endmodule
