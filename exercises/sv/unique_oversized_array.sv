// unique{} asked to do something impossible, and nobody checked
//
// unique{} on an array is a real, correctly-enforced constraint -- ask
// for more unique values than the field's own bit width can represent,
// and the solver correctly refuses (randomize() returns 0) rather than
// quietly giving you duplicates. The trap isn't that unique{} is broken.
// It's that when the return value goes unchecked, the array still gets
// filled with *something* -- values that look plausibly random at a
// glance, with duplicates sitting right there in the data.
//
// One honest, current tool note while you're fixing this: Verilator's
// unique{} solver is reliable for small arrays but gets unreliable past
// about 4-5 elements, independent of how much headroom exists in the
// value space -- a real, currently-open limitation, not a rule from the
// LRM. Size your fix to stay comfortably inside that -- 4 elements is a
// safe target here, not just "anything under 16."
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

class tag_item;
  rand bit [3:0] tags[20];   // only 16 distinct 4-bit values exist
  constraint c_unique { unique {tags}; }
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    tag_item item = new();
    int ok = item.randomize();
    bit dup_found = 0;

    if (!ok) begin
      $display($sformatf({"FAIL: randomize() returned 0 -- %0d elements can never all be unique ",
          "4-bit values (only 16 exist)"}, $size(item.tags)));
      $fatal(1);
    end

    for (int i = 0; i < $size(item.tags); i++)
      for (int j = i+1; j < $size(item.tags); j++)
        if (item.tags[i] == item.tags[j]) dup_found = 1;

    if (dup_found) begin
      $display("FAIL: randomize() ok=1 but tags contains duplicates: %p", item.tags);
      $fatal(1);
    end else begin
      $display("PASS: tags=%p, all unique", item.tags);
      $finish;
    end
  end
endmodule
