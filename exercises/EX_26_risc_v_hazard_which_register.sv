// =================================================================================================
// EX_26 -- when a hazard happens, decide which register(s) it hits
// =================================================================================================
//
// Building on EX_25: gen_hazard decides whether this instruction hazards against the one before it
// at all, at whatever rate you choose. That part's unrelated to what comes next. GIVEN gen_hazard
// is 1, the hazard still has to land somewhere -- on src_reg_0 alone, src_reg_1 alone, or both --
// and real pipelines don't split that three ways evenly.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so that, among instructions where gen_hazard is 1 (and there was a
// previous instruction), roughly 20% hazard on src_reg_0 only, 50% on src_reg_1 only, and 30% on
// both -- and never on neither. Registers that aren't hazarding shouldn't coincidentally match the
// previous instruction's dst_reg either.
// -------------------------------------------------------------------------------------------------
class instr_item;
  rand bit [4:0] dst_reg;
  rand bit [4:0] src_reg_0;
  rand bit [4:0] src_reg_1;
  rand bit       gen_hazard;
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    instr_item item = new();
    bit [4:0] prev_dst_reg;
    bit has_prev = 0;
    int ok;
    int total = 2000;
    int hazard_count = 0;
    int src0_only = 0;
    int src1_only = 0;
    int both_count = 0;
    bit bad_found = 0;

    for (int t = 0; t < total; t++) begin
      automatic bit m0, m1;
      ok = item.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at instruction %0d", t);
        $fatal(1);
      end

      if (has_prev && item.gen_hazard) begin
        hazard_count++;
        m0 = (item.src_reg_0 == prev_dst_reg);
        m1 = (item.src_reg_1 == prev_dst_reg);

        if (!m0 && !m1) begin
          $display("FAIL: instr %0d has gen_hazard=1 but neither src_reg_0 nor src_reg_1 matches",
              t);
          bad_found = 1;
        end else if (m0 && m1) both_count++;
        else if (m0) src0_only++;
        else src1_only++;
      end

      prev_dst_reg = item.dst_reg;
      has_prev     = 1;
    end

    if (bad_found) $fatal(1);

    if (hazard_count < (total * 60 / 100) || hazard_count > (total * 80 / 100)) begin
      $display("FAIL: gen_hazard rate %0d/%0d (%0d%%), expected roughly 70%%",
          hazard_count, total, (hazard_count * 100) / total);
      $fatal(1);
    end

    if (src0_only < (hazard_count * 10 / 100) || src0_only > (hazard_count * 30 / 100)) begin
      $display("FAIL: src0-only %0d/%0d hazards (%0d%%), expected roughly 20%%",
          src0_only, hazard_count, (src0_only * 100) / hazard_count);
      $fatal(1);
    end

    if (src1_only < (hazard_count * 40 / 100) || src1_only > (hazard_count * 60 / 100)) begin
      $display("FAIL: src1-only %0d/%0d hazards (%0d%%), expected roughly 50%%",
          src1_only, hazard_count, (src1_only * 100) / hazard_count);
      $fatal(1);
    end

    if (both_count < (hazard_count * 20 / 100) || both_count > (hazard_count * 40 / 100)) begin
      $display("FAIL: both-registers %0d/%0d hazards (%0d%%), expected roughly 30%%",
          both_count, hazard_count, (both_count * 100) / hazard_count);
      $fatal(1);
    end

    $display("PASS: %0d hazards -- src0-only=%0d%% src1-only=%0d%% both=%0d%%",
        hazard_count, (src0_only * 100) / hazard_count, (src1_only * 100) / hazard_count,
        (both_count * 100) / hazard_count);
    $finish;
  end
endmodule
