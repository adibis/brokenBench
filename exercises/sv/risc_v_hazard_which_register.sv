// =================================================================================================
// when a hazard happens, decide which register(s) it hits
// =================================================================================================
//
// A read-after-write hazard: an instruction reads a register the instruction before it writes.
// gen_hazard decides whether this instruction hazards at all. Given that it does, the hazard
// lands on src_reg_0, src_reg_1 or both, and real pipelines don't split that evenly.
//
// A sequence constructs a fresh instr_item per instruction, so "what the previous instruction
// wrote" can't live in an ordinary member that new() resets. It has to be shared by every
// instance.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, among instructions with gen_hazard set and a previous instruction:
//
//   1. About 20% hazard on src_reg_0 only, 50% on src_reg_1 only, 30% on both; never neither.
//   2. A source register that isn't hazarding doesn't happen to match the previous dst_reg.
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
    instr_item item;
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
      item = new();  // fresh transaction every instruction, like a real sequence
      ok   = item.randomize();
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
      $display("FAIL: gen_hazard rate %0d/%0d (%0d%%), expected roughly 70%%", hazard_count, total,
               (hazard_count * 100) / total);
      $fatal(1);
    end

    if (src0_only < (hazard_count * 10 / 100) || src0_only > (hazard_count * 30 / 100)) begin
      $display("FAIL: src0-only %0d/%0d hazards (%0d%%), expected roughly 20%%", src0_only,
               hazard_count, (src0_only * 100) / hazard_count);
      $fatal(1);
    end

    if (src1_only < (hazard_count * 40 / 100) || src1_only > (hazard_count * 60 / 100)) begin
      $display("FAIL: src1-only %0d/%0d hazards (%0d%%), expected roughly 50%%", src1_only,
               hazard_count, (src1_only * 100) / hazard_count);
      $fatal(1);
    end

    if (both_count < (hazard_count * 20 / 100) || both_count > (hazard_count * 40 / 100)) begin
      $display("FAIL: both-registers %0d/%0d hazards (%0d%%), expected roughly 30%%", both_count,
               hazard_count, (both_count * 100) / hazard_count);
      $fatal(1);
    end

    $display("PASS: %0d hazards -- src0-only=%0d%% src1-only=%0d%% both=%0d%%", hazard_count,
             (src0_only * 100) / hazard_count, (src1_only * 100) / hazard_count,
             (both_count * 100) / hazard_count);
    $finish;
  end
endmodule
