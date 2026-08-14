class id_item;
  rand bit [3:0] id;
  bit [3:0] used_q[$];

  constraint c_unused { !(id inside {used_q}); }

  function void post_randomize();
    used_q.push_back(id);
  endfunction
endclass

module top;
  initial begin
    id_item item = new();
    bit seen[16];
    int ok;
    bit dup_found = 0;

    for (int t = 0; t < 16; t++) begin
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d (should succeed for 16 calls)", t);
        $fatal(1);
      end
      if (seen[item.id]) begin
        $display("FAIL: id=%0d repeated at call %0d", item.id, t);
        dup_found = 1;
      end
      seen[item.id] = 1;
    end

    if (dup_found) $fatal(1);

    ok = item.randomize();
    if (ok) begin
      $display("FAIL: 17th randomize() succeeded (id=%0d) but all 16 values were already used",
          item.id);
      $fatal(1);
    end

    $display("PASS: 16 calls, all distinct IDs; 17th call correctly failed (exhausted)");
    $finish;
  end
endmodule
