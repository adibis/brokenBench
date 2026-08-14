class page_item;
  rand bit [31:0] addr;
  constraint c_range { addr inside {[32'h0000_0000 : 32'h000F_FFFF]}; }
  constraint c_align_4k { addr[11:0] == 12'b0; }
endclass

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
      if (item.addr % 4096 != 0) begin
        $display("FAIL: addr=0x%08h is not 4K-aligned (addr %% 4096 = %0d)",
            item.addr, item.addr % 4096);
        bad_found = 1;
      end
    end

    if (bad_found) $fatal(1);

    $display("PASS: 200 trials, every address 4K-aligned");
    $finish;
  end
endmodule
