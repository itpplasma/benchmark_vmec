#!/usr/bin/env bash
#SBATCH --job-name=parvmec-benchmark
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=7-00:00:00
#SBATCH --output=slurm-%x-%j.out
#SBATCH --error=slurm-%x-%j.err

set -euo pipefail
if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    repo_root=$(cd -- "$SLURM_SUBMIT_DIR" && pwd)
else
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    repo_root=$(cd -- "$script_dir/.." && pwd)
fi
cd "$repo_root"
exec "$repo_root/tools/run_parvmec_slurm.sh"
