#!/bin/bash

#SBATCH --job-name=rosetta_relax
#SBATCH --time=1-00:00:00
#SBATCH -e rosetta_relax_%A_%a_err.txt
#SBATCH -o rosetta_relax_%A_%a_out.txt
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --mem=4000

# FastRelax (InterfaceRelax2019-based) followed by InterfaceAnalyzer, on a list of PDBs.
#
# Usage:
#   sbatch --array=0-<N-1> submit_rosetta_relax.sh <pdb_list> <out_dir> [ramp|constrained]
#   bash submit_rosetta_relax.sh <pdb_list> <out_dir> [ramp|constrained]   # no Slurm: one task, all PDBs
#
# Modes:
#   ramp        coord_cst_weight 1.0 -> 0.5 -> 0 -> 0 per cycle (default)
#   constrained coord_cst_weight 1.0 throughout
#
# Environment:
#   ROSETTA_BIN   (required) path to rosetta/main/source/bin, or the bin/ of a conda env with the rosetta package
#   ROSETTA_EXT   binary suffix (default: linuxgccrelease; set to "" for the conda package's unsuffixed names)
#   INTERFACE     chains on each side, e.g. "A_B" or "AB_C"
#   FIXEDCHAINS   alternatively, chains kept together on one side, e.g. "A B"
#                 One of INTERFACE/FIXEDCHAINS is required: -constrain_relax_to_start_coords adds a virtual
#                 root residue that InterfaceAnalyzer counts as an extra chain, so it won't guess an interface.
#   FRAGFOLD_DIR  repo root; needed under sbatch, which runs a copy of this script from the spool dir
#                 (default: two levels above this script)

set -euo pipefail

pdb_list=$1
out_dir=$2
mode=${3:-ramp}

: "${ROSETTA_BIN:?set ROSETTA_BIN to rosetta/main/source/bin}"
rosetta_ext=${ROSETTA_EXT-linuxgccrelease}
relaxBin=$ROSETTA_BIN/relax${rosetta_ext:+.$rosetta_ext}
intAnaBin=$ROSETTA_BIN/InterfaceAnalyzer${rosetta_ext:+.$rosetta_ext}
# Prebuilt macOS (conda) binaries reference their dylibs by build-machine path; fall back to the bin dir
if [ "$(uname)" = Darwin ]; then
    export DYLD_FALLBACK_LIBRARY_PATH=$ROSETTA_BIN${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}
fi

if [ -n "${INTERFACE:-}" ]; then
    interface_args=(-interface "$INTERFACE")
elif [ -n "${FIXEDCHAINS:-}" ]; then
    interface_args=(-fixedchains $FIXEDCHAINS)
else
    echo "set INTERFACE (e.g. A_B) or FIXEDCHAINS (e.g. \"A B\")" >&2
    exit 1
fi

repo_dir=${FRAGFOLD_DIR:-$(dirname "${BASH_SOURCE[0]}")/../..}
script_dir=$repo_dir/scripts/rosetta
case $mode in
    ramp) relax_script=$script_dir/relaxscript_modified_InterfaceRelax2019.txt ;;
    constrained) relax_script=$script_dir/relaxscript_modified_InterfaceRelax2019_constrainttostart.txt ;;
    *) echo "unknown mode: $mode (expected ramp or constrained)" >&2; exit 1 ;;
esac
if [ ! -f "$relax_script" ]; then
    echo "relax script not found: $relax_script (set FRAGFOLD_DIR to the repo root)" >&2
    exit 1
fi

task_id=${SLURM_ARRAY_TASK_ID:-0}
n_tasks=${SLURM_ARRAY_TASK_COUNT:-1}

mkdir -p "$out_dir/lists"
batch_list=$out_dir/lists/batch_${task_id}_list.txt
silentfile=$out_dir/relaxed_${task_id}.silent

# Every n_tasks-th line, starting at task_id
awk -v n="$n_tasks" -v i="$task_id" 'NF && (NR - 1) % n == i' "$pdb_list" > "$batch_list"
if [ ! -s "$batch_list" ]; then
    echo "No structures for task $task_id"
    exit 0
fi
echo "Task $task_id/$n_tasks: $(wc -l < "$batch_list") structures, mode=$mode"

SECONDS=0

set -x
"$relaxBin" -in:file:l "$batch_list" \
    -relax:script "$relax_script" -constrain_relax_to_start_coords \
    -out:file:silent "$silentfile" -out:file:silent_struct_type binary \
    -out:file:scorefile "$out_dir/relax_score_${task_id}.sc"

"$intAnaBin" -in:file:silent "$silentfile" \
    -out:file:score_only -out:file:scorefile "$out_dir/interface_score_${task_id}.sc" \
    "${interface_args[@]}"
set +x

ELAPSED="Elapsed: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
echo $ELAPSED