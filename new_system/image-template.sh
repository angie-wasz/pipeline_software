#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_ips_image
#SBATCH --output={{obsid}}-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --mem=50G
#SBATCH --time=05:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load python/3.11.6
module load wsclean/3.4-idg
module load hyperdrive/0.6.1-cpu
module load py-scipy/1.14.1
module load py-astropy/5.1
module load py-h5py/3.12.1

trap 'python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Running 

imstack={{software}}/imstack/

cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms ./{{obsid}}{{freq}}.ms
ms={{obsid}}{{freq}}.ms

if [ ! -s {{obsid}}.metafits ]; then
	cp /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ./
fi

# calibration solutions should be in the directory
#cal_sol={{obsid}}_160.bin
cal_sol={{obsid}}_sols.fits

# Change centre
chgcentre -minw -shiftback ${ms}

# Apply calibration solutions
#applysolutions ${ms} ${cal_sol}
hyperdrive apply-solutions -d ${ms} -s ${cal_sol} -o {{obsid}}.ms
ms={{obsid}}.ms

# Image full standard image
wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} --subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} ${ms}

rm ./*-dirty.fits
rm ./*-model.fits
rm ./*-psf.fits

# hdf5 file
python ${imstack}/make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile={{obsid}}.hdf5 --skip_beam --allow_missing {{obsid}} --bands={{freq}}
python ${imstack}/lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path={{software}}/hdf5/gleam_xx_yy.hdf5 -v
python ${imstack}/add_continuum.py --overwrite {{obsid}}.hdf5 {{obsid}} {{freq}} image

rm *-t0*
rm -r {{obsid}}{{freq}}.ms
rm -r {{obsid}}.ms

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Queued --stage Post-Image
