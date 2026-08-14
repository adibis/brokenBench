class instr_item;
  rand bit [4:0] dst_reg;
  rand bit [4:0] src_reg_0;
  rand bit [4:0] src_reg_1;
  rand bit       gen_hazard;
  rand bit [1:0] hkind;  // 0 = src_reg_0 only, 1 = src_reg_1 only, 2 = both

  bit [4:0] prev_dst_reg;
  bit       has_prev;

  constraint c_hazard_dist { gen_hazard dist {1 := 70, 0 := 30}; }
  constraint c_kind_dist   { hkind dist {0 := 20, 1 := 50, 2 := 30}; }

  constraint c_link {
    if (has_prev && gen_hazard) {
      if (hkind == 0) { src_reg_0 == prev_dst_reg; src_reg_1 != prev_dst_reg; }
      else if (hkind == 1) { src_reg_1 == prev_dst_reg; src_reg_0 != prev_dst_reg; }
      else { src_reg_0 == prev_dst_reg; src_reg_1 == prev_dst_reg; }
    }
  }

  function void post_randomize();
    prev_dst_reg = dst_reg;
    has_prev     = 1;
  endfunction
endclass
