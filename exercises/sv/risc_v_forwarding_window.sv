// =================================================================================================
// three forwarding paths deep, not one
// =================================================================================================
//
// risc_v_hazard_which_register only ever looked one instruction back -- a single EX-stage forward.
// A real pipeline has more forwarding paths than that: an instruction can also be fed from MEM (2
// cycles back) or WB (3 cycles back). This exercise generates a hazard against any one of those
// three slots, weighted the way real pipelines actually see them: EX 40%, MEM 40%, WB 20%.
//
// Same requirement as before carries over: a real sequence constructs a fresh instr_item per
// instruction, so whatever remembers recent dst_regs needs to be shared across instances, not
// reset by every new(). This time it's not one register, it's a 3-deep sliding window -- keep it
// as a static array and shift it in post_randomize() every call: what was 1-cycle-ago becomes
// 2-cycles-ago, what was 2-cycles-ago becomes 3-cycles-ago, and the newest dst_reg becomes
// 1-cycle-ago.
//
// Two things make the spec itself, not just the mechanics, worth getting exactly right:
//
//   - register x0 is hardwired to zero in RISC-V. A "hazard" against a history slot that holds x0
//     isn't a real hazard -- nothing legally forwards from it. That has to rule x0-holding slots
//     out of the target selection dynamically, not just skip checking them afterward.
//   - "no coincidental match to a slot you didn't target" needs a precise definition. If two
//     different history slots happen to hold the identical nonzero value (nothing stops that --
//     dst_reg is unconstrained), matching your targeted slot unavoidably also numerically matches
//     the other one. That isn't a coincidental leak, it's the same register value appearing twice
//     in the window -- don't treat it as a violation of isolation.
//
// One tool-specific thing to know before you reach for the obvious approach: putting a `dist{}`
// clause directly on an enum-typed rand variable does not reproduce its declared weights
// reliably on this toolchain (confirmed in this repo's own README -- see the
// "Real, current tool limitations" section). Drive the weighted pick through a plain-width rand
// field instead, and map it onto the enum afterward with an ordinary equality constraint.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the class so:
//
//   1. history is a static, 3-deep sliding window: history[0] is 1-cycle-ago (EX), history[1] is
//      2-cycles-ago (MEM), history[2] is 3-cycles-ago (WB). post_randomize() shifts it every call
//      and inserts the just-generated dst_reg at history[0].
//   2. Given gen_hazard is 1, the targeted slot is EX 40% of the time, MEM 40%, WB 20% -- except a
//      slot currently holding x0 (5'd0) can never be targeted; its share of the weight goes away
//      rather than being redistributed.
//   3. When a slot is targeted, at least one of src_reg_0/src_reg_1 equals that slot's value, and
//      neither source register coincidentally matches a DIFFERENT-valued slot elsewhere in the
//      window (a slot that happens to share the targeted slot's own value doesn't count).
//   4. When gen_hazard is 0, neither source register matches any nonzero slot in the window.
// -------------------------------------------------------------------------------------------------
class advanced_instr_fuzzer;
  static bit [4:0] history    [3] = '{5'd1, 5'd2, 5'd3};

  rand bit   [4:0] dst_reg;
  rand bit   [4:0] src_reg_0;
  rand bit   [4:0] src_reg_1;
  rand bit         gen_hazard;

  typedef enum bit [1:0] {
    HIT_EX,
    HIT_MEM,
    HIT_WB,
    HIT_NONE
  } stage_target_e;

  // write constraints and post_randomize() here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    advanced_instr_fuzzer stream;
    int ok;
    int total = 6000;
    int ex_cnt = 0, mem_cnt = 0, wb_cnt = 0, hazard_cnt = 0;
    bit bad_found = 0;

    for (int t = 0; t < total; t++) begin
      automatic bit [4:0] h0, h1, h2;
      h0 = advanced_instr_fuzzer::history[0];
      h1 = advanced_instr_fuzzer::history[1];
      h2 = advanced_instr_fuzzer::history[2];

      stream = new();  // fresh transaction every instruction, like a real sequence
      ok = stream.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end

      if (stream.gen_hazard != (stream.target != stream.HIT_NONE)) begin
        $display("FAIL: gen_hazard doesn't match target at trial %0d", t);
        bad_found = 1;
      end

      case (stream.target)
        stream.HIT_EX: begin
          hazard_cnt++;
          ex_cnt++;
          if (h0 == 0) begin
            $display("FAIL: targeted EX slot holding x0 at trial %0d", t);
            bad_found = 1;
          end
          if (stream.src_reg_0 != h0 && stream.src_reg_1 != h0) begin
            $display("FAIL: EX hazard but neither src matches history[0]=%0d at trial %0d", h0, t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h1 || stream.src_reg_1 == h1) && h1 != 0 && h1 != h0) begin
            $display("FAIL: EX hazard coincidentally also matches MEM slot at trial %0d", t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h2 || stream.src_reg_1 == h2) && h2 != 0 && h2 != h0) begin
            $display("FAIL: EX hazard coincidentally also matches WB slot at trial %0d", t);
            bad_found = 1;
          end
        end
        stream.HIT_MEM: begin
          hazard_cnt++;
          mem_cnt++;
          if (h1 == 0) begin
            $display("FAIL: targeted MEM slot holding x0 at trial %0d", t);
            bad_found = 1;
          end
          if (stream.src_reg_0 != h1 && stream.src_reg_1 != h1) begin
            $display("FAIL: MEM hazard but neither src matches history[1]=%0d at trial %0d", h1, t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h0 || stream.src_reg_1 == h0) && h0 != 0 && h0 != h1) begin
            $display("FAIL: MEM hazard coincidentally also matches EX slot at trial %0d", t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h2 || stream.src_reg_1 == h2) && h2 != 0 && h2 != h1) begin
            $display("FAIL: MEM hazard coincidentally also matches WB slot at trial %0d", t);
            bad_found = 1;
          end
        end
        stream.HIT_WB: begin
          hazard_cnt++;
          wb_cnt++;
          if (h2 == 0) begin
            $display("FAIL: targeted WB slot holding x0 at trial %0d", t);
            bad_found = 1;
          end
          if (stream.src_reg_0 != h2 && stream.src_reg_1 != h2) begin
            $display("FAIL: WB hazard but neither src matches history[2]=%0d at trial %0d", h2, t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h0 || stream.src_reg_1 == h0) && h0 != 0 && h0 != h2) begin
            $display("FAIL: WB hazard coincidentally also matches EX slot at trial %0d", t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h1 || stream.src_reg_1 == h1) && h1 != 0 && h1 != h2) begin
            $display("FAIL: WB hazard coincidentally also matches MEM slot at trial %0d", t);
            bad_found = 1;
          end
        end
        stream.HIT_NONE: begin
          if ((stream.src_reg_0 == h0 || stream.src_reg_1 == h0) && h0 != 0) begin
            $display("FAIL: no-hazard trial matches EX slot at trial %0d", t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h1 || stream.src_reg_1 == h1) && h1 != 0) begin
            $display("FAIL: no-hazard trial matches MEM slot at trial %0d", t);
            bad_found = 1;
          end
          if ((stream.src_reg_0 == h2 || stream.src_reg_1 == h2) && h2 != 0) begin
            $display("FAIL: no-hazard trial matches WB slot at trial %0d", t);
            bad_found = 1;
          end
        end
      endcase
    end

    if (bad_found) $fatal(1);

    if (ex_cnt < (hazard_cnt * 36 / 100) || ex_cnt > (hazard_cnt * 44 / 100)) begin
      $display("FAIL: EX %0d/%0d hazards (%0d%%), expected roughly 40%%", ex_cnt, hazard_cnt,
               (ex_cnt * 100) / hazard_cnt);
      $fatal(1);
    end
    if (mem_cnt < (hazard_cnt * 36 / 100) || mem_cnt > (hazard_cnt * 44 / 100)) begin
      $display("FAIL: MEM %0d/%0d hazards (%0d%%), expected roughly 40%%", mem_cnt, hazard_cnt,
               (mem_cnt * 100) / hazard_cnt);
      $fatal(1);
    end
    if (wb_cnt < (hazard_cnt * 16 / 100) || wb_cnt > (hazard_cnt * 24 / 100)) begin
      $display("FAIL: WB %0d/%0d hazards (%0d%%), expected roughly 20%%", wb_cnt, hazard_cnt,
               (wb_cnt * 100) / hazard_cnt);
      $fatal(1);
    end

    $display("PASS: %0d hazards -- EX=%0d%% MEM=%0d%% WB=%0d%%, x0 respected, isolation held",
             hazard_cnt, (ex_cnt * 100) / hazard_cnt, (mem_cnt * 100) / hazard_cnt,
             (wb_cnt * 100) / hazard_cnt);
    $finish;
  end
endmodule
