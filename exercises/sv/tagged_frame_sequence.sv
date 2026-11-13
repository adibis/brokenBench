// =================================================================================================
// one distinguished header, three different kinds of persistent state
// =================================================================================================
//
// A frame stream where each frame has a header, an id, a payload and a size. The rules only bite
// for frames whose header is the distinguished value XYZ:
//
//   - XYZ frames carry a payload counting up from 100. That count has to survive across freshly
//     constructed objects, which is why next_xyz_payload and frames_since_last_xyz are already
//     static.
//   - XYZ frames can't come too close together or too far apart. That's about when a frame may
//     be XYZ, so constrain header itself against frames_since_last_xyz rather than checking
//     afterward.
//   - ids are a separate rule: no frame reuses an earlier frame's id. randc looks right, but its
//     cycling isn't reliable on this toolchain once you exclude more than the last value (see
//     the README, "Real, current tool limitations"). Use a plain rand field and a queue of used
//     ids with `inside {}`.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, across many randomize() calls on freshly constructed objects:
//
//   1. Every frame's id differs from every earlier frame's id.
//   2. header may equal XYZ (8'hAB) only if at least 5 frames have passed since the last XYZ
//      frame (or there hasn't been one), and must equal XYZ once 9 have passed, so no run of 10
//      frames is XYZ-free.
//   3. When header == XYZ, payload is 100 for the first such frame, 101 for the second, and so
//      on, counting only XYZ frames.
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
