#!/usr/bin/env bash
#SBATCH --job-name=vmec-benchmark
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --mem=96G
#SBATCH --time=7-00:00:00
#SBATCH --output=slurm-%x-%j.out
#SBATCH --error=slurm-%x-%j.err

set -euo pipefail
# Slurm executes a submitted relative script from its spool directory.  Use
# the submit directory when available so the wrapper always finds this
# checkout rather than /var/lib/slurm/slurmd/tools.
if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    repo_root=$(cd -- "$SLURM_SUBMIT_DIR" && pwd)
else
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    repo_root=$(cd -- "$script_dir/.." && pwd)
fi
cd "$repo_root"
mode=${BENCHMARK_MODE:-full}
exec "$repo_root/tools/run_slurm_benchmark.sh" "$mode"
