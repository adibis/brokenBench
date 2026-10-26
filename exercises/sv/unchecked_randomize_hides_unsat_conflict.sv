// =================================================================================================
// desc_item.randomize() fails every single call -- and nothing that matters ever checks
// =================================================================================================
//
// SPEC, for a DMA descriptor (addr, len):
//   - addr (descriptor start) must land in the start window [0x1000:0x1FFF].
//   - len (transfer length) must be at least 4097 bytes -- the current minimum burst granularity.
//   - The underlying buffer this window addresses is 8 KB (0x2000 bytes) total, based at 0x1000 --
//     a descriptor may never read past the end of that buffer.
//
// -------------------------------------------------------------------------------------------------
// desc_item below is exactly the kind of class a model writes with total confidence when asked to
// implement the spec above: one constraint per bullet, each individually unremarkable. Read any
// single constraint in isolation and nothing looks wrong -- the three only contradict each other
// once you work out what they jointly allow.
//
// The loop below is the kind of driving loop that shows up in a thousand sequences -- create an
// item, randomize it, use it. It compiles. It runs. Run it: every single descriptor comes back
// with addr == 0 and len == 0, and the return value randomize() hands back -- the one piece of
// information that would have said so directly -- is never looked at. Verilator itself prints an
// UNSATCONSTR warning on every failed call; that's realistic, not a tell -- a plain $warning never
// fails a regression, and a log with warnings scrolling by looks identical to a clean one unless
// someone is actually grepping for them.
//
// -------------------------------------------------------------------------------------------------
// Fix whatever's actually broken against the spec above -- not a leftover default. Don't edit
// anything at or below the "checker" marker; it's correct as given and is what's judging you.
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
