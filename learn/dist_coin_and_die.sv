// =================================================================================================
// write two `dist` clauses from scratch: a fair coin, and a loaded die
// =================================================================================================
//
// `dist` takes two different weight operators, and they mean different things once one side of
// an entry is a range instead of a single value:
//
//   value := weight        -- that value gets exactly this weight, full stop.
//   [lo:hi] := weight       -- every value in the range gets this weight EACH (so a wider range
//                              gets proportionally more of the total).
//   [lo:hi] :/ weight       -- the range gets this weight TOTAL, divided evenly across every
//                              value in it (so a wider range does NOT get more weight overall --
//                              each individual value inside it gets less).
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write two constraints from scratch:
//
//   1. `coin` is a fair coin flip -- 0 and 1 need to come up about equally often. Two single
//      values, each with the same weight, is exactly what `:=` is for.
//   2. `roll` is a loaded six-sided die, values 1 through 6. It should land on 6 about half the
//      time. The OTHER half of the time, it should be anything from 1 to 5, with all five of
//      those values getting an even share of that other half -- not each individually getting
//      the same weight as 6 itself. That's the difference between `:=` and `:/ ` on a range: get
//      this one backwards and 1-5 either vanish entirely or swamp 6's intended 50%.
// -------------------------------------------------------------------------------------------------
class dist_practice;
  rand bit coin;
  rand bit [2:0] roll;
  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    dist_practice item = new();
    int heads = 0;
    int sixes = 0;
    bit low_seen[5];
    int total = 20000;

    for (int i = 0; i < total; i++) begin
      void'(item.randomize());
      if (item.roll < 1 || item.roll > 6) begin
        $display("FAIL: roll=%0d is outside 1-6 at call %0d", item.roll, i);
        $fatal(1);
      end
      if (item.coin == 1) heads++;
      if (item.roll == 6) sixes++;
      if (item.roll >= 1 && item.roll <= 5) low_seen[item.roll-1] = 1;
    end

    if (heads < (total * 40 / 100) || heads > (total * 60 / 100)) begin
      $display("FAIL: coin==1 came up %0d/%0d (%0d%%), expected roughly 50%%", heads, total,
               (heads * 100) / total);
      $fatal(1);
    end

    if (sixes < (total * 40 / 100) || sixes > (total * 60 / 100)) begin
      $display("FAIL: roll==6 came up %0d/%0d (%0d%%), expected roughly 50%%", sixes, total,
               (sixes * 100) / total);
      $fatal(1);
    end

    foreach (low_seen[i]) begin
      if (!low_seen[i]) begin
        $display("FAIL: roll never came up %0d across %0d calls -- 1-5 need to stay reachable",
                 i + 1, total);
        $fatal(1);
      end
    end

    $display("PASS: coin ~50/50 (%0d%% heads), roll==6 ~50%% (%0d%%), 1-5 all reachable",
             (heads * 100) / total, (sixes * 100) / total);
    $finish;
  end
endmodule
