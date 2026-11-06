# Support

This page records what each implementation needs in order to run every case,
whether the change is in the benchmark or in the code itself, and where it
lives. A case counts as supported only when the code solves the same physical
problem as the VMEC reference: the same boundary or coil field, profiles,
enclosed flux and current constraint.

## Changes

| Implementation | Change | Where | Status |
| --- | --- | --- | --- |
| all | A run that wrote a wout counts as completed; timeouts are reported separately from crashes | #13 | merged |
| PARVMEC | Superbuild defines the Stellarator-Tools `pull_libstell` and `pull_parvmec` targets | #11 | merged |
| DESC | Free-boundary inputs are reported unsupported: the VMEC reader solves them as fixed-boundary | #12 | merged |
| GVEC, SPECTRE | Free-boundary inputs are reported unsupported: the converters write fixed-boundary runs | #14 | merged |
| all | mgrid fixtures for 46 free-boundary cases (DIII-D grid from STELLOPT; TFTR, NCSX and W7-X grids from MAKEGRID on the corpus coils) | #16 | merged |
| all | Legacy INDATA names (`TYPE_PRECON`, `RAXIS_CO`, `ZAXIS_CO`, `AC_FORM = 0`) are renamed before any code reads them | #17 | merged |
| all | `plasma_current` and `pressure_axis` are read from `ctor` and `presf`; they were always zero | #18 | merged |
| DESC, GVEC, SPECTRE | `GAMMA != 0` is reported unsupported: these codes hold the pressure profile fixed | #19 | merged |
| VMEX | `PRECON_TYPE` CG, GMRESR and TFQMR run on the GMRES path | [uwplasma/vmex#727](https://github.com/uwplasma/vmex/pull/727) | draft |
| VMEX | educational_VMEC's `VAC_1_2` is accepted | [uwplasma/vmex#730](https://github.com/uwplasma/vmex/pull/730) | draft |
| VMEX, VMEC2000, educational VMEC | `sum_atan` takes its limit at the edge for every exponent and sign | [uwplasma/vmex#729](https://github.com/uwplasma/vmex/pull/729), [itpplasma/VMEC2000#5](https://github.com/itpplasma/VMEC2000/pull/5), [itpplasma/educational_VMEC#1](https://github.com/itpplasma/educational_VMEC/pull/1) | draft |
| VMEX | the 2-D GMRES path stalls above tight FTOL | [uwplasma/vmex#731](https://github.com/uwplasma/vmex/issues/731) | issue |
| GVEC | all VMEC profile types; interpolated profiles honour `scale` (current sign) | [itpplasma/gvec#27](https://github.com/itpplasma/gvec/pull/27) | draft |
| DESC | VMEC profile types as splines, VMEC's current sign, free boundary in the mgrid field | [itpplasma/DESC#17](https://github.com/itpplasma/DESC/pull/17) | draft |
| SPECTRE | VMEC profile types in the VMEC converter; converged wout profiles | [krystophny/spectre!5](https://gitlab.com/krystophny/spectre/-/merge_requests/5) | draft |

## Convergence tolerances

The codes stop on different quantities, so equal tolerance values do not mean
equal accuracy, and `residual_over_tolerance` is comparable only within one
code.

| Implementation | Stopping criterion |
| --- | --- |
| VMEC2000, PARVMEC, VMEX, VMEC++, jVMEC, educational VMEC | normalised squared force residuals `fsqr`, `fsqz`, `fsql` below `FTOL` |
| GVEC | unsquared absolute L2 norm of the variational force of each variable below `minimize_tol` (`MinimizeMHD3D_descent`) |
| DESC (command line) | relative change of the least-squares cost below `ftol`; the normalised force error is reported, not enforced |

A tolerance of `1e-12` on a squared residual therefore corresponds to about
`1e-6` on the force norm itself.

Deck tolerances also limit accuracy. On `Benchmarks/input.w7s`, VMEC2000 at
its `FTOL = 1e-11` is `2.5e-3` off its own edge iota at `FTOL = 1e-16`, and
VMEC++ `1.2e-3`; at `1e-16` the two agree to `7e-6`. Differences of that size
between VMEC-family codes at the deck tolerance are convergence, not physics.
