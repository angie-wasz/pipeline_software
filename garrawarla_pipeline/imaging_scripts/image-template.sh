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
trap 'ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -l {{DB_dir}}/{{log_file}} --status Failed --note \"Failed during imaging\""' ERR

# Load relevant modules
module use /pawsey/mwa/software/python3/modulefiles
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load wsclean mwa-reduce
module load python scipy astropy h5py

# Move to the temporary working directory on the NVMe
cd {{tmp_dir}}
mkdir {{obsid}}
cd {{obsid}}/
echo "CHECK USAGE: Moving into obsid directory on NVMe"
du -sh .
# copy across files for later
cp /software/projects/mwasci/awaszewski/imstack/* ./

# Update database to set observation to processing
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --slurm $SLURM_JOB_ID --status "Processing" -l {{DB_dir}}/{{log_file}}" || echo "Log file update failed"

# Move ms onto nvme
date -Iseconds
#rm -rf /astro/mwasci/asvo/{{asvo}}/{{obsid}}_ch57-68.ms
cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms ./
#cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.ms ./
mv {{obsid}}_ch121-132.ms {{obsid}}{{freq}}.ms
#mv {{obsid}}.ms {{obsid}}{{freq}}.ms
date -Iseconds
echo "CHECK USAGE: .ms moved to NVMe"
du -sh .

# Locate metafits file
if [ ! -s {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}.metafits ]; then
	echo "Downloading {{obsid}} metafits"
	wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
else
	cp {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}.metafits ./
	rsync -av {{obsid}}.metafits {{pipeline_dir}}/{{year}}/{{obsid}}/
fi
echo "CHECK USAGE: .metafits moved to NVMe"
du -sh .

# Copy calibration solutions

#2019+2020
rsync -a mwa-solar:/data/awaszewski/ips/pipeline/{{year}}/cal_sols_160/{{obsid}}_160.bin ./

#the new normal way
#rsync -a mwa-solar:/data/awaszewski/ips/pipeline/{{year}}/central/{{obsid}}/{{obsid}}_160.bin ./

#2022
#rsync -a mwa-solar:/data/awaszewski/ips/pipeline/{{year}}/central/cal_sols_160/{{obsid}}_160.bin ./

mv {{obsid}}_160.bin {{obsid}}_sols_avg.bin

#2024 cross-cal
#rsync -a mwa-solar:/data/awaszewski/ips/pipeline/{{year}}/central/{{obsid_cal}}/{{obsid_cal}}_160.bin ./
#mv {{obsid_cal}}_160.bin {{obsid}}_sols_avg.bin


# Change centre
date -Iseconds
chgcentre -minw -shiftback {{obsid}}{{freq}}.ms
date -Iseconds

# Apply calibration solutions
applysolutions {{obsid}}{{freq}}.ms {{obsid}}_sols_avg.bin
date -Iseconds

# Image full standard image
wsclean -j {{n_core}} -mem {{mem}} -name {{obsid}}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time {{obsid}}{{freq}}.ms
echo "CHECK USAGE: Standard image done"
du -sh .

# Image snapshot images
wsclean -j {{n_core}} -mem {{mem}} --name {{obsid}}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} {{obsid}}{{freq}}.ms
echo "CHECK USAGE: Snapshot images done"
du -sh .

rm ./*-dirty.fits*
rm ./*-model.fits
rm ./*-psf.fits

# Make hdf5 file
date -Iseconds
python3 make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile={{obsid}}.hdf5 --skip_beam --allow_missing {{obsid}} --bands={{freq}}
date -Iseconds
python3 lookup_beam_imstack.py {{obsid}}.hdf5 {{obsid}}.metafits {{freq}} --beam_path=/software/projects/mwasci/awaszewski/hdf5/gleam_xx_yy.hdf5 -v
python3 add_continuum.py --overwrite {{obsid}}.hdf5 {{obsid}} {{freq}} image
date -Iseconds
echo "CHECK USAGE: hdf5 done"
du -sh .

# Copy back relevant files to /astro
rm *-t0*
rsync -av ./*.fits {{pipeline_dir}}/{{year}}/{{obsid}}/
rsync -av {{obsid}}.hdf5 {{pipeline_dir}}/{{year}}/{{obsid}}/
date -Iseconds

date -Iseconds

# ONLY USE THIS WHEN TESTING IMAGING WITHOUT POST IMAGE
#ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} --status "Done" -l {{DB_dir}}/log.sqlite" || echo "Log file update failed}"
