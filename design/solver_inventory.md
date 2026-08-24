# Solver inventory (2026-08-24)

This is the explicit coverage decision for the ordinary benchmark. A row is
included when it is an equilibrium solver; an orchestrator is not counted as a
missing solver.

| family | solver | repository wiring | local smoke state |
|---|---|---|---|
| VMEC family | educational_VMEC, VMEC2000, VMEC++, VMEX, jVMEC | existing adapters | available in this workspace |
| VMEC family | PARVMEC | `repository_manager` + native adapter | checkout exists outside the benchmark base; no built executable in the benchmark base |
| nested-surface | DESC, GVEC | existing adapters + VMEC/GVEC conversion | available; GVEC native `.dat` is retained when no WOUT exists |
| MRxMHD | SPEC | repository + native executable adapter | local `/home/ert/code/SPEC` has `xspec`; add checkout under the configured base to run it |
| MRxMHD | SPECTRE | repository + native adapter | local source/build is known; not installed under the configured base |
| Grad--Shafranov 2-D | FreeGS | Python adapter + GEQDSK converter | smoke-tested on analytical Solovev fixture |
| Grad--Shafranov 2-D | CHEASE | repository + native adapter | source is known, but no conventional executable was found |

STELLOPT and SIMSOPT were checked separately. They call/optimise equilibrium
codes and are not independent equilibrium solvers, so including them would
double-count VMEC/DESC/GVEC rather than close a solver gap. No additional
VMEC-like solver was found that is both an independent equilibrium code and
has a stable input/output contract suitable for this repository.

SPEC/SPECTRE and GVEC deliberately do not get fabricated VMEC WOUT values:
their native outputs and conversion limitations remain visible in the report.
