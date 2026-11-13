// =================================================================================================
// three sensible constraints that can never all hold -- and nobody checks randomize()
// =================================================================================================
//
// SPEC, for a DMA descriptor (addr, len):
//   - addr (descriptor start) lands in the start window [0x1000:0x1FFF].
//   - len (transfer length) is at least 4097 bytes, the current minimum burst.
//   - The buffer this window addresses is 8 KB (0x2000 bytes), based at 0x1000; a descriptor
//     never reads past its end.
//
// -------------------------------------------------------------------------------------------------
// desc_item is what a model writes with confidence from that spec: one constraint per bullet,
// each fine on its own. They only contradict each other together.
//
// The loop that drives it is the usual create, randomize, use. Right now every descriptor comes
// back with addr == 0 and len == 0, and randomize()'s return value, which says so, is never
// read. Verilator prints an UNSATCONSTR warning each time, but a warning fails no regression.
//
// -------------------------------------------------------------------------------------------------
// Fix what's actually broken against the spec, not a leftover default. Don't edit anything at or
// below the "checker" marker; it's correct as given.
// -------------------------------------------------------------------------------------------------

class desc_item;
  rand bit [31:0] addr;
  rand bit [15:0] len;

  constraint c_region {addr inside {[32'h1000 : 32'h1FFF]};}
  constraint c_no_wrap {
    addr + len <= 32'h2000;
  }  // must not run past the end of the underlying buffer
  constraint c_min_len {len >= 16'd4097;}  // minimum burst granularity, per the latest spec rev
endclass

module top;
  bit [31:0] addrs[20];
  bit [15:0] lens [20];

  initial begin
    for (int i = 0; i < 20; i++) begin
      automatic desc_item item = new();
      item.randomize();
      addrs[i] = item.addr;
      lens[i]  = item.len;
    end

    // ---8<--- checker below: don't edit ---

    foreach (addrs[i]) begin
      if (addrs[i] < 32'h1000 || addrs[i] > 32'h1FFF) begin
        $display("FAIL: addrs[%0d]=%08h is outside the window [1000:1FFF]", i, addrs[i]);
        $fatal(1);
      end
      if (lens[i] < 16'd4097) begin
        $display("FAIL: lens[%0d]=%0d is below the minimum burst length of 4097", i, lens[i]);
        $fatal(1);
      end
      if ({16'h0, lens[i]} + addrs[i] > 32'h3000) begin
        $display("FAIL: addrs[%0d]=%08h + lens[%0d]=%0d runs past the window ceiling 0x3000", i,
                 addrs[i], i, lens[i]);
        $fatal(1);
      end
    end

    $display("PASS: 20/20 descriptors in-window, minimum length, no wrap");
    $finish;
  end
endmodule
