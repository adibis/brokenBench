## Vendored UVM package

`uvm_pkg.svh` is UVM 2020.3.2 (non-DPI build), copied verbatim from Verilator's own regression
suite (`test_regress/t/uvm/uvm_pkg_all_v2020_3_2_nodpi.svh` in the verilator/verilator repo),
which concatenates the whole Accellera UVM class library into one file specifically so it can be
compiled with a single `verilator ... uvm_pkg.svh <exercise>.sv` command, with no external
`$UVM_HOME` or separately-installed UVM needed.

Chosen because Verilator's own CI already builds and runs real tests against this exact file
(`t_uvm_hello`, `t_uvm_typeof_type`, `t_uvm_return_type`), so it's a known-good starting point
rather than an untested vendoring guess. The non-DPI variant avoids needing a C++ compile step
just to run an exercise.

Licensed Apache-2.0 (Accellera UVM), same license terms as the rest of the UVM class library --
see the header of `uvm_pkg.svh` itself for the full copyright/license text.

Any exercise in `exercises/uvm/` or `exercises/csr/` compiles against this file automatically;
see the Makefile's `run`/`check` targets, which prepend it for those two tracks.
