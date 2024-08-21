#!/bin/bash -l
#SBATCH --job-name=ips-post-image-{{obsid}}
#SBATCH --output={{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}-ips-post-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --time=1:00:00
#SBATCH --clusters=garrawarla
#SBATCH --partition=workq
#SBATCH --account=mwasci
#SBATCH --export=NONE
#SBATCH --gres=tmp:100g

set -exE

##########
# Preamble
##########

# Load relevant modules
module load singularity

# Incase of failure
trap 'ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -s Failed -l {{DB_dir}}/log_image.sqlite"' ERR

# Move to the temporary working directory on the NVMe
cd {{tmp_dir}}
cp {{pipeline_dir}}/pipeline_scripts/* .

# Move relevant files onto nvme
date -Iseconds
rsync -a {{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}.hdf5 \
	{% for p in pols %}{{pipeline_dir}}/{{year}}/{{obsid}}/{{obsid}}_{{freq}}-{{p}}-image.fits \
	{% endfor %} ./
date -Iseconds

# Locate metafits file
if [ ! -s {{metafits_dir}}/{{obsid}}.metafits ]; then
    echo downloading {{obsid}} metafits
    wget http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}} -O {{obsid}}.metafits
else
    cp {{metafits_dir}}/{{obsid}}.metafits ./
fi

#########################
# Continuum and abs scale
#########################
date -Iseconds

{% for pol in pols %}
singularity exec -B $PWD {{container}} BANE --noclobber --compress {{obsid}}_{{freq}}-{{pol}}-image.fits
singularity exec -B $PWD {{container}} aegean --autoload --seedclip=5 --floodclip=4 --table {{obsid}}_{{freq}}-{{pol}}-image.vot  {{obsid}}_{{freq}}-{{pol}}-image.fits
singularity exec -B $PWD {{container}} python3 make_cat.py --pol={{pol}} {{obsid}}.hdf5 {{obsid}}_{{freq}}-{{pol}}-image_comp.vot {{obsid}}_{{freq}}-{{pol}}-image.vot -o {{obsid}}
singularity exec -B $PWD {{container}} python3 match_calibration.py {{obsid}}_{{freq}}-{{pol}}-image.vot {{pipeline_dir}}/catalogs/ips_continuum_cal.fits {{obsid}}_{{freq}}-{{pol}}-image_cal.vot
{% endfor %}

singularity exec -B $PWD {{container}} python3 abs_scale.py {{obsid}} {{freq}}
date -Iseconds

#################################
# Moment images and measure noise
#################################
mypath=$PATH
mypythonpath=$PYTHONPATH
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load python numpy scipy mpi4py astropy h5py
srun --export=all -N 1 -n {{n_core}} python3 moment_image.py {{obsid}}.hdf5 -f {{freq}} --filter_lo --filter_hi --trim=900 --pol --n_moments=2
rm *moments.hdf5
export PATH=$mypath
export PYTHONPATH=$mypythonpath
singularity exec -B $PWD {{container}} python3 measure_noise.py {{obsid}}

#########################
# Get final files
#########################
singularity exec -B $PWD {{container}} python3 get_continuum.py --sigma {{obsid}}.hdf5 {{freq}} {{obsid}}_{{freq}}-image.fits
singularity exec -B $PWD {{container}} BANE --noclobber --compress {{obsid}}_{{freq}}-image.fits
singularity exec -B $PWD {{container}} aegean --autoload --seedclip=4 --floodclip=3 --table {{obsid}}_{{freq}}-image.vot {{obsid}}_{{freq}}-image.fits

mypath=$PATH
mypythonpath=$PYTHONPATH
module use /pawsey/mwa_sles12sp5/modulefiles/python
module load python numpy scipy mpi4py astropy h5py
srun --export=all -N 1 -n {{n_core}} python3 moment_image.py {{obsid}}.hdf5 -f {{freq}} --filter_lo --filter_hi
export PATH=$mypath
export PYTHONPATH=$mypythonpath

singularity exec -B $PWD {{container}} BANE --noclobber --compress {{obsid}}_{{freq}}_image_moment2.fits
singularity exec -B $PWD {{container}} aegean --autoload --seedclip=4 --floodclip=3 --table {{obsid}}_{{freq}}_image_moment2.vot {{obsid}}_{{freq}}_image_moment2.fits

# Copy back relevant files to /astro
date -Iseconds
rsync -a {{obsid}}.hdf5 \
	{% for i in range(1, 5) %}{{obsid}}_{{freq}}_image_moment{{i}}.fits \
	{% endfor %}{{obsid}}_{{freq}}_image_moment2_comp.vot \
	{{obsid}}_{{freq}}-image.fits \
	{{obsid}}_{{freq}}-image_bkg.fits \
	{{obsid}}_{{freq}}-image_rms.fits \
	{{obsid}}_{{freq}}_image_moment2_bkg.fits \
	{{obsid}}_{{freq}}_image_moment2_rms.fits \
	{{obsid}}_{{freq}}-image_comp.vot \
	{{pipeline_dir}}/{{year}}/{{obsid}}/
date -Iseconds

# Update database to show that observation has finished processing
# ssh mwa-solar "export DB_FILE={{DB_dir}}/log.sqlite; python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -s Completed" || echo "Log file update failed"
ssh mwa-solar "python3 {{DB_dir}}/db_update_log.py -o {{obsid}} -s Completed -l {{DB_dir}}/log_image.sqlite" || echo "Log file update failed}"	