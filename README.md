# Fragment binding prediction with ColabFold

> Note: this repo was previously hosted at [https://github.com/swanss/FragFold](https://github.com/swanss/FragFold) and [https://github.com/gwlilabmit/FragFold](https://github.com/gwlilabmit/FragFold).

Scripts for predicting how short fragments of natural proteins bind to full-length proteins, as described in the [manuscript](https://www.pnas.org/doi/10.1073/pnas.2322412122). This program is built on top of MMseqs2 and ColabFold, extending them to efficiently predict interactions between a full-length protein and fragments derived from a protein.

This code is associated with the following article:
A. Savinov, S. Swanson, A. E. Keating, G.-W. Li. High-throughput discovery of inhibitory protein fragments with AlphaFold. *Proceedings of the National Academy of Sciences* **122**(6), e2322412122 (2025). doi: 10.1073/pnas.2322412122

Please cite this article if you make use of FragFold.

Associated Source Data can also be found here: 
https://figshare.com/articles/dataset/Source_Data_for_Savinov_and_Swanson_et_al_2023/24841269  
doi: 10.6084/m9.figshare.24841269


# Installing FragFold

## 1. Install local colabfold

The locally installable version of ColabFold is used to predict structures. Go to the [repo](https://github.com/YoshitakaMo/localcolabfold) and follow the instructions to install ColabFold on your system (this can take >1 hr). You can ignore the recommendation to edit your `~/.bashrc` to add local ColabFold to your PATH, this is handled by FragFold.

We developed and tested FragFold on this specific [commit](https://github.com/YoshitakaMo/localcolabfold/tree/88d174ffa7a7bc76a644db14ba0099ceb0606aed). Note that CUDA 11.8 is required to use a GPU with ColabFold.

Log the output while installing to verify that each step of the process completed successfully, this can be particularly helpful for debugging issues later on.

```bash
bash install_colabbatch_linux.sh | tee install_colabbatch_linux.log
```

Once installation has completed successfully, run a small test job to verify that it's working. The following example is taken from the localcolabfold README.

```bash
/path/to/installation/colabfold_batch example.fasta colabfold_batch_test
```

Where **`example.fasta`** is a short amino acid sequence
```
>sp|P61823
MALKSLVLLSLLVLVLLLVRVQPSLGKETAAAKFERQHMDSSTSAASSSNYCNQMMKSRN
LTKDRCKPVNTFVHESLADVQAVCSQKNVACKNGQTNCYQSYSTMSITDCRETGSSKYPN
CAYKTTQANKHIIVACEGNPYVPVHFDASV
```

If you're running on a system with a NVIDIA gpu, look for `Running on GPU` in the output. If you see that not GPU is detected, check if one is currently available with `nvidia-smi`. If you're still having issues, look back at the logs to check if the version of tensorflow that was installed is compatible with CUDA 11.8.

### 2. Install FragFold

Use the following commands to clone the repo and install FragFold and its dependencies on your computer.

```bash
git clone https://github.com/swanss/FragFold.git
cd FragFold
bash install_fragfold.sh
```

`install_fragfold.sh` uses conda to set up an environment containing FragFold as well as nextflow, the workflow system used to run jobs. The script should print `installation complete`, if not, there was an issue during one of steps.

# Running FragFold

FragFold uses [nextflow](https://www.nextflow.io/) to manage the execution of the pipeline. MSA building with MMseq2s, MSA processing/concatenation, ColabFold, and the analysis and aggregation are each defined as individual **processes** in `FragFold/nextflow/modules.nf` and then used to construct **workflows** for modeling homomeric or heteromeric interactions between fragments and full-length proteins, e.g. `FragFold/nextflow/main.nf`. The details of execution, such as whether a process should be run locally or submitted to a job queue in an HPC environment is controlled by the config file `FragFold/nextflow/nextflow.config`. The job-specific parameters are defined in a yaml file, for example, `FragFold/nextflow/params/ftsZ_monomeric_example.yaml`.

## FtsZ example

The following example demonstrates how to model homomeric interactions between full-length FtsZ (with slight truncations of the terminal residues) with 30aa fragments derived from the protein.

### Setting system-specific variables

Before running the pipeline, edit `FragFold/nextflow/nextflow.config`. First, set general parameters according to your install.

```nextflow
// Define system-specific variables for all processes
executor.queueSize = 50
executor.conda = '/home/gridsan/sswanson/mambaforge/envs/fragfold'
env.repo_dir = '/data1/groups/keatinglab/swans/savinovCollaboration/FragFold'
env.colabfold_dir = '/home/gridsan/sswanson/localcolabfold/colabfold-conda'
env.alphafold_params_dir = '/home/gridsan/sswanson/localcolabfold/colabfold'

// Parameters that general don't change (but you can adjust to experiment)
env.model_type = 'alphafold2_ptm' //alt: alphafold2_multimer_v1 alphafold2_multimer_v2 alphafold2_multimer_v3
env.pair_mode = 'unpaired' //alt: paired

// Parameters that govern how the output is stored
env.colabfold_outdir = "output_colabfold"
env.peakprediction_outdir = "output_peakprediction"
```

Tips
- You can get the location of your FragFold conda install with `conda info --envs`
- `colabfold_dir` will be determined based on where you ran the install
- `alphafold_params_dir` can be found with the colabfold directory

### Creating process profiles

Next you will need to edit the process profiles (in `FragFold/nextflow/nextflow.config`) according to your HPC environment. 

```nextflow
withLabel: cpu_network {
    executor = 'slurm'
    time = '1h'
    cpus = 1
    memory = '4 GB'
    queue = 'download' // edit this value
    clusterOptions = '--ntasks-per-node=1'
}
```

In this example, we define a process profile with the label `cpu_network`. If you're using a HPC with SLURM, you will only need to change `queue` to a partition on your HPC (see all partitions with `sinfo`). Note that the nodes in the partition set for cpu_network must have network access, as this is required for contacting the mmseqs server.

Repeat this for all of the profiles that are defined in the config file. Note that if you have nodes with different memory/cpu/time limits, you will need to adjust these values to match those.

Tips
- If you'd like to run all steps locally, go to `FragFold/nextflow/modules.nf` and replace the label for each process with `'standard'`
- If your cluster uses a different resource manager, check the nextflow executor [docs](https://www.nextflow.io/docs/latest/executor.html) to see if it is supported and edit the profiles accordingly.

### Setting job-specific variables

Now we set the job-specific parameters that control FragFold execution. In order to run the example, use `FragFold/nextflow/params/ftsZ_monomeric_example.yaml`, you will only need to edit the path of the query sequence and experimental to match your local installation.

```yaml
job_name: ftsZ_test
heteromeric_mode: false
protein_query_seq: /home/gridsan/sswanson/keatinglab_shared/swans/savinovCollaboration/FragFold/input/gene_fasta/ftsZ_A0A140NFM6.fasta
protein_name: ftsZ-coding-EcoliBL21DE3 #"" if you want to use the protein_query_seq filename
fragment_ntermres_start: 260
fragment_ntermres_final: 265
fragment_length: 30
protein_nterm_res: 10
protein_cterm_res: 316
protein_copies: 1
experimental_data: /home/gridsan/sswanson/keatinglab_shared/swans/savinovCollaboration/FragFold/input/inhibitory_data/Savinov_2022_inhib_peptide_mapping.csv
n_contacts: 3
n_weighted_contacts: 3
iptm: 0.3
contact_distance_cutoff: 3.5
contact_distance_cluster_cutoff: 0.6
cluster_peaks_frac_overlap: 0.7
```

Note: if you don't have any experimental data corresponding to the fragments, set the path to `nextflow/assets/NO_FILE`.

```yaml
experimental_data: /data1/groups/keatinglab/swans/savinovCollaboration/FragFold/nextflow/assets/NO_FILE
```

### Running nextflow.

Run nextflow with the following command:
```bash
NEXTFLOWDIR=/home/gridsan/user/FragFold/nextflow #directory containing nextflow scripts
WORKDIR=/home/gridsan/user/FragFold/example #directory where results will be stored
NF_CFG=${NEXTFLOWDIR}/nextflow.config
PARAMS=${NEXTFLOWDIR}/params/ftsZ_monomeric_example.yaml
nextflow run ${NEXTFLOWDIR}/main.nf -w $WORKDIR -c $NF_CFG -params-file $PARAMS -resume
```

Assuming you have access to GPUs, this should take ~half an hour. After the job is completed you should see output like this:
```bash
(fragfold) user@d-19-1-1:/state/partition1/user/user$ nextflow run ${NEXTFLOWDIR}/main.nf -w $WORKDIR -c $NF_CFG -params-file $PARAMS -resume
N E X T F L O W  ~  version 23.10.1
Launching `/home/gridsan/user/keatinglab_shared/user/savinovCollaboration/FragFold/nextflow/ftsZ_homomeric_example.nf` [tiny_agnesi] DSL2 - revision: f2c61140f9
executor >  slurm (1)
[b5/8446c6] process > build_msa          [100%] 1 of 1 ✔
[51/8c5e4b] process > process_msa        [100%] 1 of 1 ✔
[66/32bf2a] process > colabfold (5)      [100%] 11 of 11 ✔
[89/a44267] process > create_summary_csv [100%] 1 of 1 ✔
[d8/d7g0w3] process > predict_peaks      [100%] 1 of 1 ✔
```

To inspect the output of intermediate steps, use the names of the processes to find the directory. For example to find output from colabfold, go to `/home/gridsan/user/FragFold/nextflow/practice/66/32bf2a*`.

The output csvs (colabfold output: `*_results_expmerge.csv`, predicted peaks: `*_predictalphafoldpeaks_*.csv`) are copied to the working directory where the nextflow job was submitted. Note that there is more output contained in the directories, including plots of the weighted contacts by fragment position.

### A note on file systems and NextFlow compatibility

Nextflow uses file locking to store task metadata and can only be run in a directory that has locking. This is not compatible with certain filesystem types, such as Lustre. To check what file systems are available on your system, use `findmnt`, the output will report the file system type for available directories and also describe whether locking is available in the OPTIONS column (If you see `noflock`, locking is not supported).

One workaround for this is to run nextflow on a file system that supports locking (e.g. a local filesystem) for task metadata storage while running the processes/and storing the output on a shared lustre directory. This works because the directory where results are stored does not need file locking (as outputs are always stored in separate directories to avoid collisions). To do this, simply run the nextflow command in a directory with locking and add the `-w` argument to specify the working directory.

As an example, this is how we start nextflow on our HPC:
```bash
# request an interactive node
LLsub -i --time=1-00:00 --partition=xeon-p8
# create a new directory on the local filesystem
USER=$(whoami) && mkdir -p /state/partition1/user/$USER && cd /state/partition1/user/$USER && conda activate fragfold
NEXTFLOWDIR=/home/gridsan/user/FragFold/nextflow #directory containing nextflow scripts
WORKDIR=/home/gridsan/user/FragFold/example #directory where results will be stored
NF_CFG=${NEXTFLOWDIR}/nextflow.config
PARAMS=${NEXTFLOWDIR}/params/ftsZ_monomeric_example.yaml
nextflow run ${NEXTFLOWDIR}/main.nf -w $WORKDIR -c $NF_CFG -params-file $PARAMS -resume
```

### Submitting nextflow as a job for large colabfold jobs

For most users, it will take days for all the submitted colabfold jobs to complete. In order to keep nextflow running until all the processes are complete, we submit it as a job with a long time limit. For help with submitting jobs, see the example script: `FragFold/scripts/submit/submit_nextflow.sh`. This script supports `-resume` by copying the task metadata files. To get it running on your HPC, you will need to edit the slurm directives and paths.

# Rosetta relax and interface analysis (optional)

Predicted fragment-protein complexes can be relaxed with Rosetta FastRelax and scored with `InterfaceAnalyzer`. This is separate from the Nextflow pipeline. Build Rosetta from source, or install a prebuilt package from the RosettaCommons conda channel:

```bash
conda create -n rosetta -c https://conda.rosettacommons.org -c conda-forge rosetta python=3.12
```

`scripts/submit/submit_rosetta_relax.sh` relaxes each structure in a list of PDBs and then runs `InterfaceAnalyzer` on the relaxed models. As a Slurm array job, each task takes every Nth line of the list. Without Slurm, it processes the whole list in one run.

```bash
ls preds/*.pdb > pdb_list.txt
export ROSETTA_BIN=/path/to/rosetta/main/source/bin   # conda: $CONDA_PREFIX/bin, with ROSETTA_EXT=""
export FRAGFOLD_DIR=/path/to/FragFold
export INTERFACE=A_B          # or FIXEDCHAINS="A B" to keep several protein copies on one side
sbatch --array=0-9 ${FRAGFOLD_DIR}/scripts/submit/submit_rosetta_relax.sh pdb_list.txt relax_out ramp
```

There are two relax protocols in `scripts/rosetta/`. Both are five repeats of InterfaceRelax2019 with constraints to the starting coordinates:
- `ramp`: the coordinate-constraint weight ramps 1.0 → 0.5 → 0 → 0 within each repeat. Flexible regions, such as linkers or hinges, can move substantially.
- `constrained`: the weight stays at 1.0, so the model stays close to the prediction.

Each task writes `relaxed_N.silent`, `relax_score_N.sc` and `interface_score_N.sc`, which has `dG_separated`, `dSASA_int`, `sc_value` and related columns.
