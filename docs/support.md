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
| GVEC, SPECTRE | Free-boundary inputs are reported unsupported: the converters write fixed-boundary runs | #14 | open |

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
