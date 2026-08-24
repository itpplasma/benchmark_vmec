# Common-format adapters

The ordinary benchmark keeps one small, inspectable interchange layer.  It is
not a differentiable API and it never substitutes a code-specific objective:

| code/input | common artifact | reverse/limits |
| --- | --- | --- |
| VMEC INDATA or JSON | `*.common.json` | common JSON → VMEC INDATA |
| VMEC INDATA → GVEC | `parameter.ini` via `pygvec convert-params --vmec` | requires GVEC |
| DESC input | `wout_*.nc` via DESC `VMECIO` | DESC's own loader is authoritative |
| FreeGS | GEQDSK + `freegs_result.json` | GEQDSK summary via `freeqdsk` |
| SPEC `.sp.h5` | JSON dataset inventory | no lossless WOUT conversion (MRxMHD) |
| SPEC `.sp` / SPECTRE `.toml` | common JSON summary | common JSON → documented native template |

Every adapter writes its native output and the common metadata sidecar. Failed
or unsupported rows stay in the report; they are never silently dropped.
