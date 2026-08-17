// =================================================================================================
// write two implication constraints from scratch
// =================================================================================================
//
// `a -> b` means "whenever a holds, b must also hold" -- it says nothing at all about what
// happens when a doesn't hold, and it isn't symmetric: `a -> b` and `b -> a` are two different
// constraints. Getting the two sides backwards from what you meant still compiles and still looks
// reasonable at a glance; it just enforces the opposite relationship.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write two implication constraints from scratch:
//
//   1. alarm_active can only ever be true when temp_reading is over 100 -- never at a safe
//      reading, but it doesn't have to be true just because the reading is high either.
//   2. whenever maint_mode is true, alarm_active must be false.
// -------------------------------------------------------------------------------------------------
class sensor_item;
  rand bit alarm_active;
  rand int temp_reading;
  rand bit maint_mode;

  constraint c_range {temp_reading inside {[0 : 200]};}

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    sensor_item item = new();
    bit maint_seen[20];
    bit maint_varied = 0;
    bit bad_found = 0;

    for (int i = 0; i < 20; i++) begin
      void'(item.randomize());
      maint_seen[i] = item.maint_mode;
      if (item.alarm_active && item.temp_reading <= 100) begin
        $display("FAIL: alarm_active=1 at temp_reading=%0d (<=100) on call %0d", item.temp_reading,
                 i);
        bad_found = 1;
      end
      if (item.maint_mode && item.alarm_active) begin
        $display($sformatf({"FAIL: maint_mode=1 but alarm_active=1 on call %0d -- maint_mode ",
                            "should force alarm_active to 0"}, i));
        bad_found = 1;
      end
    end

    for (int i = 1; i < 20; i++) if (maint_seen[i] != maint_seen[0]) maint_varied = 1;

    if (!maint_varied) begin
      $display("FAIL: maint_mode was %0d every time across 20 calls -- is it declared `rand`?",
               maint_seen[0]);
      bad_found = 1;
    end

    if (bad_found) $fatal(1);

    $display("PASS: alarm_active only followed the reading, maint_mode varied: %p", maint_seen);
    $finish;
  end
endmodule
