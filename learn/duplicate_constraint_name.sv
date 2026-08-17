// =================================================================================================
// two constraint blocks with the same name
// =================================================================================================
//
// Every constraint block in a class needs its own name, the same as any
// other class member. Two blocks named identically -- easy to end up with
// after copy-pasting one constraint to write a second -- isn't two
// constraints being combined, it's a redefinition error. The compiler
// won't guess which one you meant.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the class so both constraint blocks have distinct names, priority_lo stays in [0:3], and
// priority_hi stays in [4:7].
// -------------------------------------------------------------------------------------------------
class priority_item;
  rand bit [2:0] priority_lo;
  rand bit [2:0] priority_hi;
  constraint c_range {priority_lo inside {[0 : 3]};}
  constraint c_range {priority_hi inside {[4 : 7]};}
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    priority_item item = new();
    int ok = item.randomize();

    if (!ok || item.priority_lo > 3 || item.priority_hi < 4) begin
      $display("FAIL: randomize() ok=%0d priority_lo=%0d priority_hi=%0d", ok, item.priority_lo,
               item.priority_hi);
      $fatal(1);
    end else begin
      $display("PASS: priority_lo=%0d priority_hi=%0d", item.priority_lo, item.priority_hi);
      $finish;
    end
  end
endmodule
