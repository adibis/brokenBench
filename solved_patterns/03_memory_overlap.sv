// EX 15: sorted isn't the same as non-overlapping
//
// A classic memory-allocator constraint: hand out N address ranges that
// don't overlap. `base[0] < base[1] < base[2]` looks like it accomplishes
// that -- the bases are in order, nothing about the constraint is
// obviously wrong -- but ordering the *starts* of three ranges says
// nothing about where each range actually *ends*. A large enough size on
// an earlier region reaches straight into the next one, sorted base
// addresses and all.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class region_set;
  rand bit [15:0] base[3];
  rand bit [15:0] size[3];
  constraint c_size   { foreach (size[i]) size[i] inside {[1:20]}; }
  constraint c_bounds { foreach (base[i]) base[i] inside {[0:1000]}; }
  constraint c_order  { base[0] + size[0] <= base[1]; base[1] + size[1] <= base[2]; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    region_set rs = new();
    int ok;
    bit overlap_found = 0;

    for (int t = 0; t < 50; t++) begin
      ok = rs.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end
      for (int i = 0; i < 3; i++)
        for (int j = i+1; j < 3; j++)
          if (rs.base[i] < rs.base[j] + rs.size[j] && rs.base[j] < rs.base[i] + rs.size[i]) begin
            $display("FAIL: region %0d [%0d:%0d) overlaps region %0d [%0d:%0d)",
              i, rs.base[i], rs.base[i]+rs.size[i], j, rs.base[j], rs.base[j]+rs.size[j]);
            overlap_found = 1;
          end
    end

    if (overlap_found) $fatal(1);

    $display("PASS: 50 trials, no overlaps");
    $finish;
  end
endmodule
