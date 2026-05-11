#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_{{freq}}_ds
#SBATCH --output={{output}}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_cpu}}
#SBATCH --mem={{mem}}G
#SBATCH --time=05:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load singularity/4.1.0-slurm

#cd {{data}}

# TEMP FILESYSTEM IN RAM
cd /dev/shm
mkdir {{obsid}}/
cd {{obsid}}/

echo "DATE"
date -Iseconds

# COPY OVER DATA
rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch{{freq}}.ms/ ./{{obsid}}_ch{{freq}}.ms
ms={{obsid}}_ch{{freq}}.ms

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

# CORE IMAGE
# reduce pixel size and resolution
# image every fine channel and timestep
# within 125m
#singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_cpu}} -abs-mem {{mem}} -name {{obsid}}_{{freq}}_ds -pol xx,yy -join-polarizations -niter 0 -intervals-out 496 -channels-out 2 -minuv-l 10 -maxuv-l 50 -scale 6amin -size 512 512 -log-time ${ms}

# STANDARD IMAGE
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_cpu}} -abs-mem {{mem}} -name {{obsid}}_{{freq}}_ds_standard -pol xx,yy -join-polarizations -intervals-out 496 -channels-out 2 -size 512 512 -niter 100000 -minuv-l 0 -scale 0.2amin -nmiter 0 -auto-threshold 2 -auto-mask 3 -taper-inner-tukey 50 -taper-gaussian 2amin -log-time ${ms}

# CREATE HDF5
module load python/3.11.6 py-scipy/1.14.1 py-astropy/4.2.1 py-h5py/3.12.1 py-numpy/1.25.2
python /software/projects/mwasci/awaszewski/phase_1/make_hdf5.py --start=0 --suffixes=image --outfile={{obsid}}_{{freq}}_ds_standard.hdf5 {{obsid}} --bands={{freq}}
module unload py-numpy/1.25.2 py-h5py/3.12.1 py-scipy/1.14.1 py-astropy/4.2.1

echo "DATE"
date -Iseconds

# TRANSFER DATA
cp {{obsid}}_{{freq}}_ds_standard.hdf5 {{data}}/

# CLEAN UP
rm *{{freq}}*-t*
cd ../
rm -r {{obsid}}/

