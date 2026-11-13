// =================================================================================================
// rand_mode(0) left on from a debug helper
// =================================================================================================
//
// rand_mode() switches randomization of a field off or on without touching its declaration.
// That's handy for pinning a field while debugging, and easy to leave behind: the field is still
// declared `rand`, still compiles, and every other field keeps randomizing.
//
// The constructor makes two rand_mode() calls: one turns randomization off for the whole object,
// the other turns it back on for one field. Which field is left pinned?
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirement: seq_num varies across repeated randomize() calls, as channel already does.
// -------------------------------------------------------------------------------------------------
class frame_item;
  rand bit [7:0] seq_num;
  rand bit [3:0] channel;

  function new();
    // left over from debugging a channel-0-only issue
    this.rand_mode(0);
    this.channel.rand_mode(1);
  endfunction
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    frame_item item = new();
    bit [7:0] seen[8];
    bit all_same = 1;

    for (int i = 0; i < 8; i++) begin
      void'(item.randomize());
      seen[i] = item.seq_num;
    end

    for (int i = 1; i < 8; i++) if (seen[i] != seen[0]) all_same = 0;

    if (all_same) begin
      $display("FAIL: seq_num was %0d every time across 8 calls -- check rand_mode() on seq_num",
               seen[0]);
      $fatal(1);
    end else begin
      $display("PASS: seq_num varied across calls: %p", seen);
      $finish;
    end
  end
endmodule
