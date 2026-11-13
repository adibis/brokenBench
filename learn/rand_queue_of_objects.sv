// =================================================================================================
// write post_randomize() so a queue of objects isn't full of nulls
// =================================================================================================
//
// `rand Packet queue_of_pkts[$];` lets the solver pick the queue's size, but it can't construct
// the objects: `new()` is code, and the solver only picks values. The queue comes out the right
// size and full of null handles.
//
// `post_randomize()` runs right after randomize() has picked every value, including the queue's
// size, so it knows how many objects to build.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements for post_randomize(), for every element of queue_of_pkts:
//
//   1. It is constructed (not null).
//   2. Its own fields are randomized, not left at their defaults.
// -------------------------------------------------------------------------------------------------
class Packet;
  rand bit [7:0] length;
  rand bit       is_payload_valid;
endclass

class PacketGenerator;
  rand Packet queue_of_pkts[$];

  constraint c_size {queue_of_pkts.size() == 5;}

  // write post_randomize() here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    PacketGenerator gen = new();
    bit [7:0] seen[10];
    bit varied = 0;
    bit bad_found = 0;

    for (int t = 0; t < 10; t++) begin
      automatic int ok = gen.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", t);
        $fatal(1);
      end

      if (gen.queue_of_pkts.size() != 5) begin
        $display("FAIL: queue_of_pkts.size()=%0d, expected 5 at call %0d",
                 gen.queue_of_pkts.size(), t);
        bad_found = 1;
      end

      foreach (gen.queue_of_pkts[i]) begin
        if (gen.queue_of_pkts[i] == null) begin
          $display("FAIL: queue_of_pkts[%0d] is null at call %0d", i, t);
          bad_found = 1;
        end
      end

      if (bad_found) $fatal(1);

      seen[t] = gen.queue_of_pkts[0].length;
    end

    for (int t = 1; t < 10; t++) if (seen[t] != seen[0]) varied = 1;

    if (!varied) begin
      $display("FAIL: queue_of_pkts[0].length was %0d every call -- was it actually randomized?",
               seen[0]);
      $fatal(1);
    end

    $display("PASS: every call produced 5 constructed, randomized packets");
    $finish;
  end
endmodule
