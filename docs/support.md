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
| all except GVEC | GVEC's native test cases on the (R, Z) map run as VMEC inputs in `cases/from_gvec` (14 equilibria for 21 cases; `tools/convert_gvec_to_vmec.py`). The 9 cases on knot, Frenet or cylinder maps have no VMEC equivalent | #23 | merged |
| all | Decks without `LFREEB` are free-boundary when they name a grid, as in VMEC; a grid with fewer coil groups than the deck's nonzero `EXTCUR` is reported unsupported (TFTR and W7-X fixtures for 22 STELLOPT and coverage decks) | #25 | merged |
| GVEC | A run counts as converged only when its force is below `minimize_tol`; native states named after `ProjectName` are found | #22 | merged |
| GVEC | Runs get the deck's VMEC iteration budget instead of the 10000 iterations GVEC's VMEC reader sets | #28 | merged |
| educational VMEC | Input lines longer than 1000 characters, such as 100-knot spline lists, are kept whole | #29 | merged |
| VMEC++ | `&indata` in lower case is read as a classic input | [itpplasma/vmecpp#39](https://github.com/itpplasma/vmecpp/pull/39), [proximafusion/vmecpp#1067](https://github.com/proximafusion/vmecpp/pull/1067) | fork merged, upstream ready |
| VMEC++ | Zero padding of spline knot lists is dropped as in VMEC | [itpplasma/vmecpp#40](https://github.com/itpplasma/vmecpp/pull/40), [proximafusion/vmecpp#1068](https://github.com/proximafusion/vmecpp/pull/1068) | fork merged, upstream ready |
| VMEX | `PRECON_TYPE` CG, GMRESR and TFQMR run on the GMRES path | [uwplasma/vmex#727](https://github.com/uwplasma/vmex/pull/727) | upstream, ready |
| VMEX | educational_VMEC's `VAC_1_2` is accepted | [uwplasma/vmex#730](https://github.com/uwplasma/vmex/pull/730) | upstream, ready |
| VMEX, VMEC2000, educational VMEC | `sum_atan` takes its limit at the edge for every exponent and sign | [uwplasma/vmex#729](https://github.com/uwplasma/vmex/pull/729), [itpplasma/VMEC2000#5](https://github.com/itpplasma/VMEC2000/pull/5), [itpplasma/educational_VMEC#1](https://github.com/itpplasma/educational_VMEC/pull/1) | VMEX upstream ready, forks merged |
| VMEX | the 2-D GMRES path stalls above tight FTOL | [uwplasma/vmex#731](https://github.com/uwplasma/vmex/issues/731) | issue |
| GVEC | all VMEC profile types; interpolated profiles honour `scale` (current sign) | [itpplasma/gvec#27](https://github.com/itpplasma/gvec/pull/27) | merged |
| GVEC | `pygvec run` from a VMEC wout keeps the wout's nfp, boundary, flux and profiles after the initial stage | [itpplasma/gvec#28](https://github.com/itpplasma/gvec/pull/28) | merged |
| GVEC | integer polynomial profile coefficients; decks without `AM` get zero pressure | [itpplasma/gvec#29](https://github.com/itpplasma/gvec/pull/29), [itpplasma/gvec#32](https://github.com/itpplasma/gvec/pull/32) | merged |
| GVEC | legacy `RAXIS`/`ZAXIS` and scalar axis entries are read as VMEC reads them | [itpplasma/gvec#30](https://github.com/itpplasma/gvec/pull/30) | merged |
| GVEC | after a Jacobian sign change in the initial guess, the run retries with a guessed axis and then with a lower radial power of the shaping modes, as VMEC resets its axis | [itpplasma/gvec#31](https://github.com/itpplasma/gvec/pull/31), [itpplasma/gvec#33](https://github.com/itpplasma/gvec/pull/33) | merged |
| GVEC | files beside native parameter files (wout, hmap, boundary) are staged; only `&INDATA` is parsed | #32, #33 | merged |
| KIN6D | Fixed-boundary VMEC inputs run through KIN6D's `nested_equilibrium` (`tools/convert_vmec_to_kin6d.py`): power-series iota and pressure, boundary oriented as VMEC orients it. Current-constrained (NCURR = 1), non-power-series profiles, BLOAT, SPRES_PED < 1, LRFP and GAMMA != 0 are reported unsupported | this PR | open |
| DESC | VMEC profile types as splines, VMEC's current sign, free boundary in the mgrid field | [itpplasma/DESC#18](https://github.com/itpplasma/DESC/pull/18), [PlasmaControl/DESC#2392](https://github.com/PlasmaControl/DESC/pull/2392) (profiles, sign); [itpplasma/DESC#17](https://github.com/itpplasma/DESC/pull/17) (free boundary), [PlasmaControl/DESC#2393](https://github.com/PlasmaControl/DESC/pull/2393) (`LFREEB` warning) | fork #18 blocked by CI, #17 draft; upstream ready |
| SPECTRE | VMEC profile types in the VMEC converter; converged wout profiles; iota-constrained conversions start from the poloidal flux and `mu` of the transform, without which axisymmetric cases hit a singular straight-field-line solve | [krystophny/spectre!5](https://gitlab.com/krystophny/spectre/-/merge_requests/5), upstream [spectre-eq/spectre!72](https://gitlab.com/spectre-eq/spectre/-/merge_requests/72) and [!71](https://gitlab.com/spectre-eq/spectre/-/merge_requests/71) | fork merged, upstream draft |
| SPECTRE | VMEC inputs go through SPECTRE's own converter at the deck's resolution, with boundaries oriented as VMEC orients them; volume and aspect ratio come from SPECTRE's output (its innermost surface is a coordinate axis, not the magnetic axis), the force residual from its minimiser; convergence follows the tolerance table below | #24 | open |

## Convergence tolerances

The codes stop on different quantities, so equal tolerance values do not mean
equal accuracy, and `residual_over_tolerance` is comparable only within one
code.

| Implementation | Stopping criterion |
| --- | --- |
| VMEC2000, PARVMEC, VMEX, VMEC++, jVMEC, educational VMEC | normalised squared force residuals `fsqr`, `fsqz`, `fsql` below `FTOL` |
| GVEC | unsquared absolute L2 norm of the variational force of each variable below `minimize_tol` (`MinimizeMHD3D_descent`) |
| DESC (command line) | relative change of the least-squares cost below `ftol`; the normalised force error is reported, not enforced |
| SPECTRE | relative change of the least-squares cost; the benchmark stops it after 500 evaluations and counts a run as converged when SPECTRE reports success or the root mean square of its final force residuals is at most 1e-8 |

A tolerance of `1e-12` on a squared residual therefore corresponds to about
`1e-6` on the force norm itself.

Deck tolerances also limit accuracy. On `Benchmarks/input.w7s`, VMEC2000 at
its `FTOL = 1e-11` is `2.5e-3` off its own edge iota at `FTOL = 1e-16`, and
VMEC++ `1.2e-3`; at `1e-16` the two agree to `7e-6`. Differences of that size
between VMEC-family codes at the deck tolerance are convergence, not physics.
