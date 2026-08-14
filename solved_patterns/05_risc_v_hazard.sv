class instr_item;
  rand bit [4:0] dest;
  rand bit [4:0] src1;
  rand bit [4:0] src2;
  rand bit       hazard;

  bit [4:0] prev_dest;
  bit       has_prev;

  constraint c_hazard_dist { hazard dist {1 := 70, 0 := 30}; }
  constraint c_hazard_link { (has_prev && hazard) -> src1 == prev_dest; }

  function void post_randomize();
    prev_dest = dest;
    has_prev  = 1;
  endfunction
endclass

module top;
  initial begin
    instr_item item = new();
    bit [4:0] prev_dest;
    bit has_prev = 0;
    int ok;
    int hazard_count = 0;
    int total = 2000;
    bit bad_link_found = 0;

    for (int t = 0; t < total; t++) begin
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at instruction %0d", t);
        $fatal(1);
      end

      if (has_prev && item.hazard) begin
        hazard_count++;
        if (item.src1 != prev_dest) begin
          $display("FAIL: instr %0d claims hazard=1 but src1=%0d != prev_dest=%0d",
              t, item.src1, prev_dest);
          bad_link_found = 1;
        end
      end

      prev_dest = item.dest;
      has_prev  = 1;
    end

    if (bad_link_found) $fatal(1);

    if (hazard_count < (total * 60 / 100) || hazard_count > (total * 80 / 100)) begin
      $display("FAIL: hazard rate %0d/%0d (%0d%%), expected roughly 70%%",
          hazard_count, total, (hazard_count * 100) / total);
      $fatal(1);
    end

    $display("PASS: %0d/%0d instructions hazarded (%0d%%), every hazard correctly linked",
        hazard_count, total, (hazard_count * 100) / total);
    $finish;
  end
endmodule
