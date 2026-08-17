// =================================================================================================
// generate a RISC-V-style instruction stream with data hazards 70% of the time
// =================================================================================================
//
// A pipeline hazard test needs instructions that deliberately depend on each other's registers,
// not just random independent ones. A read-after-write hazard is exactly that: an instruction
// reads a register that the instruction immediately before it is about to write.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Fix the implementation so that if hazard is true, we generate data hazards on the instruction.
// Generate hazard 70% of the time.
// -------------------------------------------------------------------------------------------------
class instr_item;
  rand bit [4:0] dst_reg;
  rand bit [4:0] src_reg_0;
  rand bit [4:0] src_reg_1;
  rand bit       hazard;
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    instr_item item = new();
    bit [4:0] prev_dst_reg;
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
        if (item.src_reg_0 != prev_dst_reg && item.src_reg_1 != prev_dst_reg) begin
          $display($sformatf({"FAIL: instr %0d claims hazard=1 but neither src_reg_0=%0d nor ",
                              "src_reg_1=%0d matches prev_dst_reg=%0d"}, t, item.src_reg_0,
                               item.src_reg_1, prev_dst_reg));
          bad_link_found = 1;
        end
      end

      prev_dst_reg = item.dst_reg;
      has_prev     = 1;
    end

    if (bad_link_found) $fatal(1);

    if (hazard_count < (total * 60 / 100) || hazard_count > (total * 80 / 100)) begin
      $display("FAIL: hazard rate %0d/%0d (%0d%%), expected roughly 70%%", hazard_count, total,
               (hazard_count * 100) / total);
      $fatal(1);
    end

    $display("PASS: %0d/%0d instructions hazarded (%0d%%), every hazard correctly linked",
             hazard_count, total, (hazard_count * 100) / total);
    $finish;
  end
endmodule
