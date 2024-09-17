#!/bin/bash -l
#SBATCH --job-name={{obsid}}-ips-image
#SBATCH --output={{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --time=05:00:00
#SBATCH --clusters=garrawarla
#SBATCH --partition=workq
#SBATCH --account=mwasci
#SBATCH --export=NONE
#SBATCH --gres=tmp:800g

set -euxEo pipefail

# In case of failure
trap 'ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -l {{DB_dir}}/log.sqlite --status Failed --note \"Failed during imaging\""' ERR

# Load relevant modules
module use /pawsey/mwa/software/python3/modulefiles
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load wsclean mwa-reduce
module load python scipy astropy h5py

# Move to the temporary working directory on the NVMe
cd {{tmp_dir}}
mkdir {{obsid}}
cd {{obsid}}/
# copy across files for later
cp /software/projects/mwasci/awaszewski/imstack/* ./

# Update database to set observation to processing
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --slurm $SLURM_JOB_ID --status "Processing" -l {{DB_dir}}/log.sqlite" || echo "Log file update failed"
#ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --status Processing -l {{DB_dir}}/log_image.sqlite" || echo "Log file update failed"

# Move ms onto nvme
date -Iseconds
#rm -rf /astro/mwasci/asvo/{{asvo}}/{{obsid}}_ch57-68.ms
cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms ./
mv {{obsid}}_ch121-132.ms {{obsid}}{{freq}}.ms
date -Iseconds

# Locate metafits file
if [ ! -s {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}.metafits ]; then
	echo "Downloading {{obsid}} metafits"
	wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
else
	cp {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}.metafits ./
	rsync -av {{obsid}}.metafits {{pipeline_dir}}/{{year}}/{{obsid}}/
fi

# Copy calibration solutions
rsync -a mwa-solar:/data/awaszewski/ips/pipeline/{{year}}/central/{{obsid}}/{{obsid}}_160.bin ./
mv {{obsid}}_160.bin {{obsid}}_sols_avg.bin

# Change centre
date -Iseconds
chgcentre -minw -shiftback {{obsid}}{{freq}}.ms
date -Iseconds

# Apply calibration solutions
applysolutions {{obsid}}{{freq}}.ms {{obsid}}_sols_avg.bin
date -Iseconds

# Image full standard image
wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time {{obsid}}{{freq}}.ms

# Image snapshot images
wsclean -j {{n_core}} -mem {{mem}} --name {{obsid}}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} {{obsid}}{{freq}}.ms

rm ./*-dirty.fits*
rm ./*-model.fits
rm ./*-psf.fits
# Make hdf5 file
date -Iseconds
python3 make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile={{obsid}}.hdf5 --skip_beam --allow_missing {{obsid}} --bands={{freq}}
date -Iseconds
#python3 lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path=/astro/mwasci/awaszewski/EoR_scin_pipeline/hdf5/gleam_xx_yy.hdf5 -v
python3 lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path=/software/projects/mwasci/awaszewski/hdf5/gleam_xx_yy.hdf5 -v
python3 add_continuum.py --overwrite {{obsid}}.hdf5 {{obsid}} {{freq}} image
date -Iseconds

# Copy back relevant files to /astro
rm *-t0*
rsync -av ./*.fits {{pipeline_dir}}/{{year}}/{{obsid}}/
rsync -av {{obsid}}.hdf5 {{pipeline_dir}}/{{year}}/{{obsid}}/
date -Iseconds

#rm -rf /astro/mwasci/asvo/{{asvo}}/* 
date -Iseconds

# DON"T SAY ITS DONE ITS NOT DONE IT NEEDS TO DO POST IMAGE AS WELL
#ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --status "Done" -l {{DB_dir}}/log.sqlite" || echo "Log file update failed}"
