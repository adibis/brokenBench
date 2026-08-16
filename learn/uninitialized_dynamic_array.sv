// a dynamic array that was never given a size
//
// A dynamic array starts out with zero elements until something sizes
// it -- either an explicit `arr = new[N]`, or a constraint that
// determines its size as part of solving. Randomizing a `rand` dynamic
// array that's still sitting at its default zero length isn't an error:
// there's nothing to fill, so randomize() has nothing to fail on and
// returns 1. The array just stays empty, silently, with no signal that
// anything is wrong.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class buf_item;
  rand int data[];
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    buf_item item = new();
    int ok = item.randomize();

    if (!ok) begin
      $display("FAIL: randomize() returned 0");
      $fatal(1);
    end

    if (item.data.size() == 0) begin
      $display("FAIL: data.size()==0 -- the array was never given a size before randomize()");
      $fatal(1);
    end

    $display("PASS: data.size()=%0d, data=%p", item.data.size(), item.data);
    $finish;
  end
endmodule
