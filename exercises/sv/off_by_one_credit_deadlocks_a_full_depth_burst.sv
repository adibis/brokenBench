// =================================================================================================
// the link never deadlocks under everyday traffic -- only a full-depth burst finds it
// =================================================================================================
//
// SPEC: at reset, credits must equal DEPTH (16) -- the receive buffer's actual physical capacity,
// since nothing is in flight yet. A full-depth burst is one indivisible 16-flit transfer: the
// receiver returns no credit for any of it until all 16 flits have landed, then returns all 16 at
// once. (Everyday, non-burst traffic acks per flit and never approaches this limit -- it isn't
// modeled here because it isn't where the bug lives.)
//
// -------------------------------------------------------------------------------------------------
// link_model below is exactly the kind of class a model writes with total confidence when asked to
// implement the spec above: `credits = DEPTH - 1` reads like the array-index idiom that's correct
// everywhere else in a file like this one (`buf[DEPTH-1]` is the last valid index) -- it just isn't
// an index here, it's a count, and a count has to equal the thing it's counting. Run this: the
// burst never completes.
//
// -------------------------------------------------------------------------------------------------
// Fix link_model so a full-depth burst actually completes. Don't edit anything at or below the
// "checker" marker; it's correct as given and is what's judging you.
// -------------------------------------------------------------------------------------------------

class link_model;
  localparam int DEPTH = 16;

  int credits;
  int flits_received;

  function new();
    credits        = DEPTH - 1;  // 15
    flits_received = 0;
  endfunction

  // one flit of an atomic DEPTH-flit burst. Returns 1 if the flit was actually sent, 0 if blocked
  // on credits. The receiver returns no credit at all until the whole burst has landed, then
  // returns all DEPTH credits together.
  function bit send_burst_flit();
    if (credits <= 0) return 0;
    credits--;
    flits_received++;
    if (flits_received == DEPTH) credits += DEPTH;
    return 1;
  endfunction
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    link_model link = new();
    int sent = 0;
    int attempts = 0;

    while (link.flits_received < link_model::DEPTH && attempts < 1000) begin
      if (link.send_burst_flit()) sent++;
      attempts++;
    end

    if (link.flits_received != link_model::DEPTH) begin
      $display($sformatf({"FAIL: burst never completed -- stuck at %0d/%0d flits after %0d ",
                          "attempts, credits=%0d (this is the deadlock: sender has no credits, ",
                          "receiver is still waiting for the flit the sender can't send)"},
                           link.flits_received, link_model::DEPTH, attempts, link.credits));
      $fatal(1);
    end

    $display($sformatf({"PASS: burst completed, %0d/%0d flits sent in %0d attempts, ",
                        "%0d credits remaining"}, sent, link_model::DEPTH, attempts, link.credits));
    $finish;
  end
endmodule
