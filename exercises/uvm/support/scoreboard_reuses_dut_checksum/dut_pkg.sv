// Behavioral reference for this revision's CRC-8 hardware block. Ported directly from the
// RTL team's own bit-serial implementation so the testbench wouldn't have to re-derive the
// polynomial math from scratch -- compiled alongside the exercise file, never part of what
// you're fixing.
package dut_pkg;
  function automatic bit [7:0] crc8(bit [7:0] data[]);
    automatic bit [7:0] crc = 8'h00;
    foreach (data[i]) begin
      crc ^= data[i];
      for (int b = 0; b < 8; b++) begin
        if (crc[0]) crc = (crc >> 1) ^ 8'hE0;
        else crc = crc >> 1;
      end
    end
    return crc;
  endfunction
endpackage
