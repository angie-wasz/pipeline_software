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
#SBATCH --gres=tmp:800g

set -euxEo pipefail

# In case of failure
trap 'ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -s Failed -l {{DB_dir}}/log_image.sqlite"' ERR

# Load relevant modules
module use /pawsey/mwa/software/python3/modulefiles
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load wsclean mwa-reduce
module load python scipy astropy h5py
module load giant-squid

# Move to the temporary working directory on the NVMe
cd {{tmp_dir}}
# copy across files for laer
cp /astro/mwasci/awaszewski/imstack/* ./

# Update database to set observation to processing
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -j $SLURM_JOB_ID -s Processing -l {{DB_dir}}/log_image.sqlite" || echo "Log file update failed"

export MWA_ASVO_API_KEY=3144f819-2df7-4baf-9646-3d3854c1ad6e

# Find the rest of the observations in the trio
central={{obsid}}
first=$((central - 200))
last=$((central + 200))

# Find ASVO Job ID for all observations
#asvo_central={{asvo}}

#giant-squid list $first >> asvo_${first}
#asvo_first=$(grep $first asvo_${first} | sed -n 3p | awk '{print $2}')
#rm asvo_${first}

#giant-squid list $last >> asvo_${last}
#asvo_last=$(grep $last asvo_${last} | sed -n 2p | awk '{print $2}')
#rm asvo_${last}

### FOR NOW CAUSE THE FUCKING EXPIRY NEVER WORKS FOR ME EVER
asvo_central=675600
asvo_first=675601
asvo_last=675602


# Move ms onto nvme
date -Iseconds
cp -r /astro/mwasci/asvo/${asvo_central}/${central}_ch121-132.ms .
mv ${central}_ch121-132.ms ${central}.ms
cp -r /astro/mwasci/asvo/${asvo_first}/${first}_ch121-132.ms .
mv ${first}_ch121-132.ms ${first}.ms
cp -r /astro/mwasci/asvo/${asvo_last}/${last}_ch121-132.ms .
mv ${last}_ch121-132.ms ${last}.ms
date -Iseconds

# Locate metafits file
#if [ ! -s /astro/mwasci/jmorgan/ips/metafits/${central}.metafits ]; then
echo downloading ${central} metafits
wget "http://ws.mwatelescope.org/metadata/fits?obs_id=${central}" -qO ${central}.metafits
wget "http://ws.mwatelescope.org/metadata/fits?obs_id=${first}" -qO ${first}.metafits
wget "http://ws.mwatelescope.org/metadata/fits?obs_id=${last}" -qO ${last}.metafits
#else
#    cp /astro/mwasci/jmorgan/ips/metafits/${central}.metafits .
#fi

# Copy calibration solutions
rsync -a mwa-solar:/data/awaszewski/ips/feb_cme/2023/${central}/${central}_160.bin ./
mv ${central}_160.bin ${central}_sols.bin

# Change centre
date -Iseconds

phasecentre=$(python calc_pointing.py "${central}.metafits")

chgcentre -minw -shiftback ${central}.ms
chgcentre ${first}.ms ${phasecentre}
chgcentre ${central}.ms ${phasecentre}
chgcentre ${last}.ms ${phasecentre}
date -Iseconds

# Apply calibration solutions
applysolutions ${central}.ms ${central}_sols.bin
applysolutions ${first}.ms ${central}_sols.bin
applysolutions ${last}.ms ${central}_sols.bin
date -Iseconds

# Image full standard image
date -Iseconds
#wsclean -j {{n_core}} -mem {{mem}} -name ${central}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time ${first}.ms ${central}.ms ${last}.ms
#date -Iseconds

# test by imaging seperately
wsclean -j {{n_core}} -mem {{mem}} -name ${first}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time ${first}.ms 

wsclean -j {{n_core}} -mem {{mem}} -name ${central}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time ${central}.ms

wsclean -j {{n_core}} -mem {{mem}} -name ${last}_{{freq}} -pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -mgain {{mgain}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -scale {{scale}} -log-time ${last}.ms


# Image snapshot images separetely
date -Iseconds

wsclean -j {{n_core}} -mem {{mem}} --name ${central}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} ${central}.ms

wsclean -j {{n_core}} -mem {{mem}} --name ${first}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} ${first}.ms

wsclean -j {{n_core}} -mem {{mem}} --name ${last}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} ${last}.ms

date -Iseconds

# Rename snapshot images
freq_name="121-132"
new_prefix="${central}_${freq_name}"

# Start by renaming the central observations to the middle of the timesteps
number_XX=400
number_YY=400

#echo "Renaming central"

#for file in ./${central}*t*XX-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_XX})
#		new_filename="${new_prefix}-t${formatted}-XX-image.fits"
#		mv ${file} ${new_filename}
#		number_XX=$((number_XX + 1))
#	fi
#done

#for file in ./${central}*t*YY-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_YY})
#		new_filename="${new_prefix}-t${formatted}-YY-image.fits"
#		mv ${file} ${new_filename}
#		number_YY=$((number_YY + 1))
#	fi
#done

# Then we can rename the first and last observations

number_XX=0
number_YY=0

#echo "Renaming first"

#for file in ./${first}*t*XX-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_XX})
#		new_filename="${new_prefix}-t${formatted}-XX-image.fits"
#		mv ${file} ${new_filename}
#		number_XX=$((number_XX + 1))
#	fi
#done

#for file in ./${first}*t*YY-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_YY})
#		new_filename="${new_prefix}-t${formatted}-YY-image.fits"
#		mv ${file} ${new_filename}
#		number_YY=$((number_YY + 1))
#	fi
#done

number_XX=800
number_YY=800

#echo "Renaming last"

#for file in ./${last}*t*XX-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_XX})
#		new_filename="${new_prefix}-t${formatted}-XX-image.fits"
#		mv ${file} ${new_filename}
#		number_XX=$((number_XX + 1))
#	fi
#done

#for file in ./${last}*t*YY-image.fits; do
#	if [ -f "$file" ]; then
#		formatted=$(printf "%04d" ${number_YY})
#		new_filename="${new_prefix}-t${formatted}-YY-image.fits"
#		mv ${file} ${new_filename}
#		number_YY=$((number_YY + 1))
#	fi
#done		

#echo "Finished renaming"

rm ./*-dirty.fits*
rm ./*-model.fits
rm ./*-psf.fits

# Image snapshot images
#wsclean -j {{n_core}} -mem {{mem}} --name {{obsid}}_{{freq}} -subtract-model -pol xx,yy -size {{size}} {{size}} -join-polarizations -minuv-l {{minuv_l}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -nwlayers {{n_core}} -niter {{niter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale}} -log-time -no-reorder -no-update-model-required -interval {{interval_start}} {{interval_stop}} -intervals-out {{interval_stop-interval_start}} {{obsid}}{{freq}}.ms


# Make hdf5 file
date -Iseconds
#python3 make_imstack2.py -vvn 1200 --start=0 --suffixes=image --outfile=${central}.hdf5 --skip_beam --allow_missing ${central} --bands={{freq}}
python3 make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile=${first}.hdf5 --skip_beam --allow_missing ${first} --bands={{freq}}
python3 make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile=${central}.hdf5 --skip_beam --allow_missing ${central} --bands={{freq}}
python3 make_imstack2.py -vvn 400 --start=0 --suffixes=image --outfile=${last}.hdf5 --skip_beam --allow_missing ${last} --bands={{freq}}
date -Iseconds

python3 lookup_beam_imstack.py ${first}.hdf5 ${first}.metafits {{freq}} --beam_path=/astro/mwasci/awaszewski/EoR_scin_pipeline/hdf5/gleam_xx_yy.hdf5 -v
python3 lookup_beam_imstack.py ${central}.hdf5 ${central}.metafits {{freq}} --beam_path=/astro/mwasci/awaszewski/EoR_scin_pipeline/hdf5/gleam_xx_yy.hdf5 -v
python3 lookup_beam_imstack.py ${last}.hdf5 ${last}.metafits {{freq}} --beam_path=/astro/mwasci/awaszewski/EoR_scin_pipeline/hdf5/gleam_xx_yy.hdf5 -v

python3 add_continuum.py --overwrite ${first}.hdf5 ${first} {{freq}} image
python3 add_continuum.py --overwrite ${central}.hdf5 ${central} {{freq}} image
python3 add_continuum.py --overwrite ${last}.hdf5 ${last} {{freq}} image

date -Iseconds

# Copy back relevant files to /astro
rm *-t*
rsync -av ./${central}*.fits {{pipeline_dir}}/{{year}}/${central}/
rsync -av ${central}.hdf5 {{pipeline_dir}}/{{year}}/${central}/
date -Iseconds

rsync -av ./${first}*.fits {{pipeline_dir}}/{{year}}/${first}/
rsync -av ${first}.hdf5 {{pipeline_dir}}/{{year}}/${first}/

rsync -av ./${last}*.fits {{pipeline_dir}}/{{year}}/${last}/
rsync -av ${last}.hdf5 {{pipeline_dir}}/{{year}}/${last}/

#rm -rf /astro/mwasci/asvo/{{asvo}}/* 
date -Iseconds
