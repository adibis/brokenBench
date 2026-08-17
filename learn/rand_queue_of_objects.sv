// =================================================================================================
// write post_randomize() so a queue of objects isn't full of nulls
// =================================================================================================
//
// `rand Packet queue_of_pkts[$];` makes the QUEUE randomizable -- the solver can decide how many
// elements it has and what each element's handle value is. What it can't do is construct the
// objects those handles point to: `new()` isn't a random value, it's a statement, and the solver
// only ever picks values, never runs code. A `rand` array/queue of class handles ends up sized
// correctly but full of null handles unless something else builds the actual objects.
//
// `post_randomize()` is the natural place to do that -- it runs right after randomize() finishes
// picking every random value, including the queue's own size, so by the time it runs you know
// exactly how many elements there are to build.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write post_randomize() so every element of queue_of_pkts ends up as a real, randomized object:
//
//   1. every element must be constructed (not null).
//   2. every element's own fields must actually be randomized, not left at their default values.
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
        $display("FAIL: queue_of_pkts.size()=%0d, expected 5 at call %0d", gen.queue_of_pkts.size(),
                 t);
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
