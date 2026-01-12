#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_ips_image
#SBATCH --output={{data}}/{{obsid}}-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --mem=50G
#SBATCH --time=05:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load python/3.11.6
module load hyperdrive/0.6.1-cpu
module load singularity/4.1.0-slurm

trap 'python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Running 

imstack={{software}}/imstack/

cd {{data}}

cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms ./{{obsid}}{{freq}}.ms
ms={{obsid}}{{freq}}.ms

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

cal_sol={{calsol}}

# Change centre
singularity exec -B $PWD {{gleam_container}} chgcentre -minw -shiftback ${ms}

# Apply calibration solutions
singularity exec -B $PWD {{gleam_container}} applysolutions ${ms} ${cal_sol}
#hyperdrive apply-solutions -d ${ms} -s ${cal_sol} -o {{obsid}}.ms
#ms={{obsid}}.ms

# Image full standard image
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time ${ms}

# Image snapshot images
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} --subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} ${ms}

rm ./*-dirty.fits
rm ./*-model.fits
rm ./*-psf.fits

# hdf5 file
module load py-scipy/1.14.1 py-astropy/4.2.1 py-h5py/3.12.1 py-numpy/1.25.2
python ${imstack}/make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile={{obsid}}.hdf5 --skip_beam --allow_missing {{obsid}} --bands={{freq}}

module unload py-numpy/1.25.2 py-h5py/3.12.1 py-scipy/1.14.1 py-astropy/4.2.1
singularity exec -B $PWD {{container}} python ${imstack}/lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path={{software}}/hdf5/gleam_xx_yy.hdf5 -v
singularity exec -B $PWD {{container}} python ${imstack}/add_continuum.py --overwrite {{obsid}}.hdf5 {{obsid}} {{freq}} image

rm *-t0*
rm -r {{obsid}}{{freq}}.ms
#rm -r {{obsid}}.ms

module load python/3.11.6

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Done
