// =================================================================================================
// one distinguished header, three different kinds of persistent state
// =================================================================================================
//
// A frame stream where every frame has a header, an id, a payload, and a size. Most of that is
// unconstrained. The interesting part only kicks in for frames whose header equals the
// distinguished value XYZ:
//
//   - consecutive XYZ frames carry a strictly increasing payload -- the first one 100, the next
//     101, the next 102, and so on. That's state that has to survive across freshly-constructed
//     objects (a real sequence doesn't reuse one transaction and re-randomize() it), which is why
//     next_xyz_payload and frames_since_last_xyz below are already `static`, not something you
//     need to invent.
//   - XYZ frames can't come too close together -- at least 5 non-XYZ frames between any two of
//     them -- and they can't be too far apart either: any run of 10 consecutive frames has to
//     contain at least one. Both of those are properties of WHEN a frame is allowed to be XYZ, not
//     properties of the frame's own fields, so they have to be enforced by constraining `header`
//     itself against frames_since_last_xyz, not checked after the fact.
//   - id has nothing to do with any of that -- it's a completely separate requirement that every
//     frame's id, XYZ or not, has to differ from every id used by any earlier frame in the stream.
//     `randc` looks tempting here, but the moment you're excluding more values than "the literal
//     previous one" its cycling guarantee stops being reliable on this toolchain (see this repo's
//     README, "Real, current tool limitations") -- a plain `rand` field plus a used-value queue
//     checked with `inside {}` is the pattern that actually holds up.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the class so, across many randomize() calls on freshly-constructed objects:
//
//   1. every frame's id differs from every id used by any earlier frame.
//   2. header may only equal XYZ (8'hAB) if at least 5 frames have passed since the last XYZ frame
//      (or none has happened yet), and header MUST equal XYZ once 9 frames have passed since the
//      last one, so no run of 10 consecutive frames is ever XYZ-free.
//   3. whenever header == XYZ, payload equals 100 for the first such frame, 101 for the second,
//      102 for the third, and so on, counting only XYZ frames.
// -------------------------------------------------------------------------------------------------
class TaggedFrameSequence;
  localparam bit [7:0] XYZ = 8'hAB;

  rand bit   [ 7:0] header;
  rand bit   [ 7:0] id;
  rand bit   [15:0] payload;
  rand bit   [ 7:0] size;

  static bit [15:0] next_xyz_payload          = 16'd100;
  static int        frames_since_last_xyz     = 0;
  static bit [ 7:0] used_ids_q           [$];

  // write constraints and post_randomize() here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    TaggedFrameSequence item;
    int ok;
    int total = 80;
    bit seen_id[256];
    int frames_since_last_xyz = 0;
    bit has_seen_xyz = 0;
    int expected_next_xyz_payload = 100;
    int xyz_count = 0;
    bit bad_found = 0;

    for (int t = 0; t < total; t++) begin
      automatic bit was_xyz;

      item = new();  // fresh transaction every frame, like a real sequence
      ok   = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at frame %0d", t);
        $fatal(1);
      end

      if (seen_id[item.id]) begin
        $display("FAIL: id=%0d repeated at frame %0d", item.id, t);
        bad_found = 1;
      end
      seen_id[item.id] = 1;

      was_xyz = (item.header == TaggedFrameSequence::XYZ);

      if (was_xyz) begin
        xyz_count++;
        if (item.payload != expected_next_xyz_payload) begin
          $display("FAIL: XYZ frame %0d has payload=%0d, expected %0d at frame %0d", xyz_count,
                   item.payload, expected_next_xyz_payload, t);
          bad_found = 1;
        end
        expected_next_xyz_payload++;

        if (has_seen_xyz && frames_since_last_xyz < 5) begin
          $display("FAIL: only %0d frames since the last XYZ frame at frame %0d (need >= 5)",
                   frames_since_last_xyz, t);
          bad_found = 1;
        end
        has_seen_xyz          = 1;
        frames_since_last_xyz = 0;
      end else begin
        frames_since_last_xyz++;
        if (frames_since_last_xyz >= 10) begin
          $display(
              "FAIL: %0d consecutive non-XYZ frames at frame %0d (10-frame window with no XYZ)",
              frames_since_last_xyz, t);
          bad_found = 1;
        end
      end
    end

    if (bad_found) $fatal(1);

    if (xyz_count < (total / 12)) begin
      $display("FAIL: only %0d XYZ frames across %0d total -- suspiciously few", xyz_count, total);
      $fatal(1);
    end

    // Pin the exact minimum-gap boundary directly rather than hoping the main loop's free choice
    // of WHEN to go XYZ happens to probe it -- nothing above biases the solver toward an early
    // XYZ, so a too-loose gap requirement (e.g. "< 2" instead of "< 5") can slip past 80 unforced
    // frames undetected. IEEE 1800's post_randomize() runs even when randomize() fails, so a
    // failed forced attempt below still executes the class's own post_randomize() against the
    // stale (unchanged) header from the last successful call -- restore frames_since_last_xyz
    // after every failed attempt so that phantom advance doesn't corrupt the next one.
    TaggedFrameSequence::frames_since_last_xyz = 0;  // known-good starting point for the probe
    for (int gap = 0; gap < 5; gap++) begin
      automatic int pre_state = TaggedFrameSequence::frames_since_last_xyz;
      item = new();
      ok   = item.randomize() with {header == TaggedFrameSequence::XYZ;};
      if (!ok) TaggedFrameSequence::frames_since_last_xyz = pre_state;
      if (ok) begin
        $display("FAIL: XYZ allowed only %0d frames after the previous one (need >= 5)", gap);
        $fatal(1);
      end
      item = new();
      ok   = item.randomize() with {header != TaggedFrameSequence::XYZ;};
    end

    $display(
        "PASS: %0d frames, %0d of them XYZ, every id unique, spacing and payload sequence held",
        total, xyz_count);
    $finish;
  end
endmodule
