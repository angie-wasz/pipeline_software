#!/bin/bash -l
#SBATCH --job-name={{obsid}}-ips-calibrate
#SBATCH --output={{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}-calibrate.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --time=01:00:00
#SBATCH --clusters=garrawarla
#SBATCH --partition=gpuq
#SBATCH --account=mwasci
#SBATCH --export=NONE
#SBATCH --gres=gpu:1,tmp:800g

set -euxEo pipefail

# In case of failure
trap 'ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -l {{DB_dir}}/log.sqlite --status Failed --note \"Failed during calibration\""' ERR

# Load relevant modules
module use /pawsey/mwa/software/python3/modulefiles
module load hyperdrive/v0.2.1 singularity

# Move onto temporary working directory on NVMe
cd {{tmp_dir}}
mkdir {{obsid}}
cd {{obsid}}/

# Update database to set observation to processing
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --slurm $SLURM_JOB_ID --status Processing -l {{DB_dir}}/log.sqlite" || echo "Log file update failed"

command -V hyperdrive

# Get neccessary files
date -Iseconds
cp /scratch/mwasci/asvo/{{asvo}}/* ./
date -Iseconds

# Neccessary scripts for calibration
cp /software/projects/mwasci/awaszewski/pipeline_scripts/aocal* ./

# Obtain sky model, probably on mwa-solar, move it over to garra at beginning
#cp {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}_skymodel.* ./
# SIKE actually use the big gleam one
skymodel="/software/projects/mwasci/awaszewski/catalogs/GGSM.txt"

# Calibration
hyperdrive di-calibrate -d *ch{{files162}}*.fits {{obsid}}.metafits \
								-s ${skymodel} \
								--num-sources 250 \
								--uvw-min 130m \
								--uvw-max 2600m \
								-o {{obsid}}_sols.fits
#								--tile-flags 85 101 107 109 110 112 \

# Plot solutions
hyperdrive plot-solutions {{obsid}}_sols.fits

# Convert solutions into bin files
hyperdrive solutions-convert {{obsid}}_sols.fits {{obsid}}.bin
singularity exec -B $PWD {{container}} python3 aocal_interp.py -a {{aocal}} {{obsid}}.bin {{obsid}}_160.bin

# Transfer files back to scratch
rsync -av {{obsid}}_sols.fits \
		{{obsid}}*.png \
		{{obsid}}.bin \
		{{obsid}}_160.bin \
		{{obsid}}.metafits \
		{{pipeline_dir}}/{{year}}/{{obsid}}/

# Update database to show that observation has finished successfully
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --status Done -l {{DB_dir}}/log.sqlite" || echo "Log file update failed"
