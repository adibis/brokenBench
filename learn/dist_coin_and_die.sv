// =================================================================================================
// write two `dist` clauses from scratch: a fair coin, and a loaded die
// =================================================================================================
//
// `dist` has two weight operators, and they differ once an entry is a range:
//
//   value   := weight   -- that value gets this weight.
//   [lo:hi] := weight   -- every value in the range gets this weight each, so a wider range
//                          gets more of the total.
//   [lo:hi] :/ weight   -- the range gets this weight in total, split evenly across its values.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. `coin` is a fair coin: 0 and 1 come up about equally often.
//   2. `roll` is a loaded die, always 1 to 6. It lands on 6 about half the time; the other half
//      is spread evenly over 1 to 5, so each of those comes up about a tenth of the time.
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
