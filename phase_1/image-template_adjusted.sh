#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_{{freq}}_image
#SBATCH --output={{output}}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_cpu}}
#SBATCH --mem={{mem}}G
#SBATCH --time=05:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load singularity/4.1.0-slurm

cd {{data}}

# COPY OVER DATA
rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch{{freq}}.ms/ ./{{obsid}}_ch{{freq}}.ms
ms={{obsid}}_ch{{freq}}.ms

if [ -f ${ms}/table.lock ]; then
    rm ${ms}/table.lock
fi

# METAFITS
if [ ! -s {{obsid}}.metafits ]; then
	if [ ! -s /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ]; then
		wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
	else
		cp /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ./
	fi
fi

if [ ! -s {{obsid}}.metafits ]; then
	echo "Metafits file doesn't exist, exitting program"
	exit 1 
fi

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

# FLAG MISBEHAVING TILES
singularity exec -B $PWD {{gleam_container}} flagantennae ${ms} 101 105

# STANDARD IMAGE
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_cpu}} -abs-mem {{mem}} -name {{obsid}}_{{freq}}_fine --pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -scale {{scale}} -reorder -log-time ${ms}

