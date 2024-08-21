#!/bin/bash -l
#SBATCH --job-name=ips-image-{{obsid}}
#SBATCH --output={{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}-ips-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=38
#SBATCH --time=12:00:00
#SBATCH --clusters=garrawarla
#SBATCH --partition=workq
#SBATCH --account=mwasci
#SBATCH --export=NONE
#SBATCH --gres=tmp:400g

set -exE
# Load relevant modules
module use /pawsey/mwa/software/python3/modulefiles
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load wsclean mwa-reduce
module load python scipy astropy h5py

# Move to the temporary working directory on the NVMe
cd {{tmp_dir}}
# copy across files for laer
cp /astro/mwasci/awaszewski/boss_sun_pipeline/imstack/* ./

# Move ms onto nvme
date -Iseconds
rm -rf /astro/mwasci/asvo/{{asvo}}/{{obsid}}_057-068.ms .
cp -r /astro/mwasci/asvo/{{asvo}}/{{obsid}}_121-132.ms .
date -Iseconds

# Locate metafits file
if [ ! -s /astro/mwasci/jmorgan/ips/metafits/{{obsid}}.metafits ]; then
    echo downloading {{obsid}} metafits
    wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
else
    cp /astro/mwasci/jmorgan/ips/metafits/{{obsid}}.metafits .
fi
# Copy calibration solutions
cp /astro/mwasci/jmorgan/ips/target_cal/{{obsid}}_{{freq}}.bin .

# Change centre
date -Iseconds
chgcentre {{obsid}}{{freq}}.ms {{coordinates[obsid]['ra']}} {{coordinates[obsid]['dec']}}
date -Iseconds
chgcentre -minw -shiftback {{obsid}}_{{freq}}.ms
date -Iseconds

# Apply calibration solutions
applysolutions -nocopy  {{obsid}}_{{freq}}.ms {{obsid}}_{{freq}}.bin
date -Iseconds

# Image full standard image
wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time {{obsid}}_{{freq}}.ms
rsync -a ./*.fits {{pipeline_dir}}/{{year}}/{{obsid}}/

# Image snapshot images
wsclean -j {{n_core}} -mem {{mem}} --name {{obsid}}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} {{obsid}}_{{freq}}.ms

rm ./*-dirty.fits*
rm ./*-model.fits
rm ./*-psf.fits
# Make hdf5 file
date -Iseconds
python3 make_imstack2.py -vvn 1152 --start=0 --suffixes=image --outfile={{obsid}}.hdf5 --skip_beam --allow_missing {{obsid}} --bands={{freq}}
date -Iseconds
python3 lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path=/astro/mwasci/awaszewski/EoR_scin_pipeline/hdf5/gleam_xx_yy.hdf5 -v
python3 add_continuum.py --overwrite {{obsid}}.hdf5 {{obsid}} {{freq}} image
date -Iseconds

# Copy back relevant files to /astro
rsync -a {{obsid}}.hdf5 {{pipeline_dir}}/{{year}}/{{obsid}}/
date -Iseconds

rm -rf /astro/mwasci/asvo/{{asvo}}/* .
date -Iseconds
