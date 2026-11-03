#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_{{freq}}_apply_sols
#SBATCH --output={{output}}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_cpu}}
#SBATCH --mem={{mem}}G
#SBATCH --time=02:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load singularity/4.1.0-slurm

cd {{data}}

# COPY OVER DATA
ms={{obsid}}_ch{{freq}}.ms

echo "DATE"
date -Iseconds

# CALIBRATION SOLUTION
cal_sol={{cal_sols}}

echo "DATE"
date -Iseconds

# CHG-CENTRE
singularity exec -B $PWD {{gleam_container}} chgcentre ${ms} {{sun_coords[obsid]['ra']}} {{sun_coords[obsid]['dec']}}

echo "DATE"
date -Iseconds

# APPLY SOLUTIONS
singularity exec -B $PWD {{gleam_container}} applysolutions ${ms} ${cal_sol}
