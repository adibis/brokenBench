// =================================================================================================
// EX_24 -- generate a 4K-page-aligned address
// =================================================================================================
//
// A classic allocator/memory-map constraint: hand out an address that lands exactly on a 4096-byte
// (4K) page boundary, somewhere within a given region. "Aligned to N" for a power-of-two N means
// the low log2(N) bits are all zero -- 4096 is 2^12, so the low 12 bits of a 4K-aligned address are
// always 0, regardless of what the higher bits are.
//
// Write the constraint from scratch below. Getting the region bound right is the easy part --
// getting the alignment width exactly right (not one bit short, not one bit long) is the part
// worth being careful about, since being off by even one bit still looks aligned to a smaller,
// wrong power of two and won't show up unless something specifically checks the real boundary.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so addr stays within [0x0000_0000 : 0x000F_FFFF] and is always 4K-aligned.
// -------------------------------------------------------------------------------------------------
class page_item;
  rand bit [31:0] addr;
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    page_item item = new();
    int ok;
    bit bad_found = 0;

    for (int t = 0; t < 200; t++) begin
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end
      if (item.addr > 32'h000F_FFFF) begin
        $display("FAIL: addr=0x%08h is outside [0x0000_0000:0x000F_FFFF]", item.addr);
        bad_found = 1;
      end
      if (item.addr % 4096 != 0) begin
        $display("FAIL: addr=0x%08h is not 4K-aligned (addr %% 4096 = %0d)",
            item.addr, item.addr % 4096);
        bad_found = 1;
      end
    end

    if (bad_found) $fatal(1);

    $display("PASS: 200 trials, every address in range and 4K-aligned");
    $finish;
  end
endmodule
