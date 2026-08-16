// =================================================================================================
// a constraint that only ever picks one value
// =================================================================================================
//
// c_write_data below is meant to say "writes need data, reads don't
// care what wdata holds" -- but every one of 20 randomize() calls comes
// back with is_write pinned to the same value every time. Something about
// how the two halves of that constraint are being combined is stronger
// than the intent describes. Look at what the constraint actually
// requires to be true simultaneously, versus what "when X, then Y" would
// require.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix c_write_data so writes get a nonzero wdata and reads still vary freely -- both is_write
// values need to show up across repeated randomize() calls.
// -------------------------------------------------------------------------------------------------
class txn_item;
  rand bit       is_write;
  rand bit [7:0] wdata;

  // intent: writes need data, reads don't care what wdata holds
  constraint c_write_data { is_write && (wdata inside {[1:255]}); }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    txn_item item = new();
    bit saw_read = 0;
    bit saw_write = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      if (item.is_write) saw_write = 1;
      else saw_read = 1;
    end

    if (!saw_read) begin
      $display("FAIL: is_write was 1 on every one of 20 calls -- reads should be possible too");
      $fatal(1);
    end else begin
      $display("PASS: saw both reads and writes across 20 calls");
      $finish;
    end
  end
endmodule
