# Contributing

## Adding an implementation

Add a wrapper in `src/` extending `vmec_implementation_t`
(`src/vmec_implementation_base.f90`), register it
with the benchmark runner and add an independent test in `test/`. Keep the
native outputs, and record failed or unsupported runs explicitly rather than
dropping them.

Use `fpm build` and `fpm test` for Fortran changes and `uv run` for Python.

## Pull requests and merging

- Every pull request, including each layer of a stacked pull request, runs CI.
- Review a stack layer by layer. When it is ready, retarget the top layer to
  `main` so that it contains the whole stack; the lower pull requests then show
  as merged.
- Merge with "Merge when ready" (or `gh pr merge --merge --auto`). The pull
  request enters the merge queue, CI runs on the merge result, and on success
  it lands on `main` as a merge commit.
- A branch does not need to be up to date with `main`; merge `main` into it
  only to resolve conflicts.
