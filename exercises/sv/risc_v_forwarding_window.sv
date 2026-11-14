// =================================================================================================
// three forwarding paths deep, not one
// =================================================================================================
//
// risc_v_hazard_which_register looked one instruction back: the EX forward. A real pipeline also
// forwards from MEM (2 back) and WB (3 back). Here a hazard targets one of those three slots,
// weighted EX 40%, MEM 40%, WB 20%.
//
// The history of recent dst_regs is shared across instances again, now as a static 3-deep
// window that post_randomize() shifts on every call.
//
// Two points of the spec need care:
//
//   - x0 is hardwired to zero in RISC-V, so a slot holding x0 isn't a real hazard target. Rule
//     such slots out of the choice in the constraint, not by skipping them afterward.
//   - If two slots hold the same nonzero value, hitting one also matches the other. That's the
//     same register twice in the window, not a leak.
//
// `dist{}` directly on an enum-typed rand variable doesn't reproduce its weights reliably on
// this toolchain (README, "Real, current tool limitations"). Weight a plain rand field and map it
// onto the enum with an equality constraint.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. history is a static 3-deep window: history[0] is EX (1 back), history[1] MEM (2 back),
//      history[2] WB (3 back). post_randomize() shifts it and puts the new dst_reg in history[0].
//   2. With gen_hazard set, the target is EX 40%, MEM 40%, WB 20%, except that a slot holding x0
//      (5'd0) is never targeted; its share drops out rather than being redistributed.
//   3. With a target, at least one of src_reg_0/src_reg_1 equals that slot's value, and neither
//      matches a slot holding a different value.
//   4. With gen_hazard clear, neither source register matches any nonzero slot.
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
  function automatic bit distinct_slots();
    bit [4:0] h[3] = advanced_instr_fuzzer::history;
    return h[0] != 0 && h[1] != 0 && h[2] != 0 && h[0] != h[1] && h[1] != h[2] && h[0] != h[2];
  endfunction

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

    // A leak into another slot needs a source register to land on that slot's value by chance,
    // which a random stream can go thousands of trials without doing. So ask for each leak
    // directly: with three distinct nonzero slots, every request below must be unsatisfiable.
    for (int tgt = 0; tgt < 4; tgt++) begin
      for (int slot = 0; slot < 3; slot++) begin
        for (int src = 0; src < 2; src++) begin
          // Targets in enum order: EX, MEM, WB hit slots 0, 1, 2; NONE (3) hits none.
          automatic
          advanced_instr_fuzzer::stage_target_e
          want = advanced_instr_fuzzer::stage_target_e'(tgt);
          automatic bit [4:0] other;
          if (tgt == slot) continue;  // matching the targeted slot itself is the point
          // Some simulators shift the window even when randomize() fails, so get three
          // distinct nonzero slots again before every request.
          for (int t = 0; t < 1000 && !distinct_slots(); t++) begin
            stream = new();
            void'(stream.randomize());
          end
          other  = advanced_instr_fuzzer::history[slot];
          stream = new();
          if (stream.randomize() with {
                target == want;
                (src == 0) -> (src_reg_0 == other);
                (src == 1) -> (src_reg_1 == other);
              }) begin
            $display("FAIL: %s allows src_reg_%0d == %0d, the value in history[%0d]", want.name(),
                     src, other, slot);
            $fatal(1);
          end
        end
      end
    end

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
