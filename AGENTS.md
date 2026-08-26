# Agent rules

- Keep this repository focused on the ordinary, non-differentiable equilibrium benchmark.
- Use `fpm build` and `fpm test` for Fortran changes. Run the repository's
  formatter when formatting is required.
- Use `uv` for Python environments, dependencies, and commands (`uv run ...`).
- Preserve unrelated work and stage explicit paths before committing.
- Keep analytical and numerical 1-D, 2-D, and 3-D cases, all VMEC-like wrappers, common-format adapters, and explicit failed/unsupported results.
- Keep documentation minimal: update `README.md`, and make scripts/examples self-documenting.
