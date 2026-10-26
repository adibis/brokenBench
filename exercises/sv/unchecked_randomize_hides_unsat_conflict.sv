// =================================================================================================
// item.randomize() fails every single call -- and nothing that matters ever checks
// =================================================================================================
//
// addr_item models a DMA descriptor address: word-aligned, constrained to a specific region. The
// loop below is the kind of driving loop that shows up in a thousand sequences -- create an item,
// randomize it, use it. It compiles. It runs. Run it: every single descriptor comes back with
// addr == 0, and the return value randomize() hands back -- the one piece of information that
// would have said so directly -- is never looked at. Verilator itself prints an UNSATCONSTR
// warning on every failed call; that's realistic, not a tell -- a plain $warning never fails a
// regression, and a log with warnings scrolling by looks identical to a clean one unless someone
// is actually grepping for them.
//
// -------------------------------------------------------------------------------------------------
// Fix whatever's actually broken so every generated addr lands inside the region, aligned, and
// actually comes from a successful randomize() call -- not a leftover default. Don't edit anything
// at or below the "checker" marker; it's correct as given and is what's judging you.
// -------------------------------------------------------------------------------------------------

class addr_item;
  rand bit [31:0] addr;

  constraint c_aligned {addr[1:0] == 2'b00;}
  constraint c_region {addr inside {[32'h1000 : 32'h1FFF]};}

  // added later, for a narrower test case -- still active for everyone else
  constraint c_narrow {addr inside {[32'h0000 : 32'h0FFF]};}
endclass

module top;
  bit [31:0] addrs[20];

  initial begin
    for (int i = 0; i < 20; i++) begin
      automatic addr_item item = new();
      item.randomize();
      addrs[i] = item.addr;
    end

    // ---8<--- checker below: don't edit ---

    foreach (addrs[i]) begin
      if (addrs[i][1:0] != 2'b00) begin
        $display("FAIL: addrs[%0d]=%08h is not word-aligned", i, addrs[i]);
        $fatal(1);
      end
      if (addrs[i] < 32'h1000 || addrs[i] > 32'h1FFF) begin
        $display("FAIL: addrs[%0d]=%08h is outside the region [1000:1FFF]", i, addrs[i]);
        $fatal(1);
      end
    end

    $display("PASS: 20/20 descriptors aligned and inside [1000:1FFF]");
    $finish;
  end
endmodule
