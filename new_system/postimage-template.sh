#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_ips_postimage
#SBATCH --output={{data}}/{{obsid}}-postimage.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --time=00:20:00
#SBATCH --export=NONE

set -exE

module load singularity/4.1.0-slurm
module load python/3.11.6

trap 'module load python/3.11.6; python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Running

scripts_dir={{software}}/pipeline_scripts/

cd {{data}}

echo "DATE"
date -Iseconds

# Continuum and abs scale
{% for pol in pols %}

singularity exec -B $PWD {{gleam_container}} BANE --cores=1 --compress {{obsid}}_{{freq}}-{{pol}}-image.fits 
singularity exec -B $PWD {{gleam_container}} aegean --slice=0 --autoload --seedclip=5 --floodclip=4 --table {{obsid}}_{{freq}}-{{pol}}-image.vot {{obsid}}_{{freq}}-{{pol}}-image.fits

singularity exec -B $PWD {{container}} python ${scripts_dir}/make_cat.py --pol={{pol}} {{obsid}}.hdf5 {{obsid}}_{{freq}}-{{pol}}-image_comp.vot {{obsid}}_{{freq}}-{{pol}}-image.vot -o {{obsid}}
singularity exec -B $PWD,{{software}} {{container}} python ${scripts_dir}/match_calibration.py {{obsid}}_{{freq}}-{{pol}}-image.vot {{software}}/catalogs/ips_continuum_cal.fits {{obsid}}_{{freq}}-{{pol}}-image_cal.vot

{% endfor %}

singularity exec -B $PWD {{container}} python ${scripts_dir}/abs_scale.py {{obsid}} {{freq}} --n_fail=0

echo "DATE"
date -Iseconds

# Moment images and measure noise
#mypath=$PATH
#mypythonpath=$PYTHONPATH
module load py-scipy/1.14.1 py-astropy/5.1 py-mpi4py/4.0.1-py3.11.6
srun --export=all -N 1 -n {{n_core}} python ${scripts_dir}/moment_image.py {{obsid}}.hdf5 -f {{freq}} --filter_lo --filter_hi --trim=900 --pol --n_moments=2
rm *moments.hdf5
module unload py-scipy/1.14.1 py-astropy/5.1 py-mpi4py/4.0.1-py3.11.6

#export PATH=$mypath
#export PYTHONPATH=$mypythonpath
singularity exec -B $PWD {{container}} python ${scripts_dir}/measure_noise.py {{obsid}}

# Get final files
singularity exec -B $PWD {{container}} python ${scripts_dir}/get_continuum.py --sigma {{obsid}}.hdf5 {{freq}} {{obsid}}_{{freq}}-image.fits
singularity exec -B $PWD {{gleam_container}} BANE --cores=1 --compress {{obsid}}_{{freq}}-image.fits
singularity exec -B $PWD {{gleam_container}} aegean --slice=0 --autoload --seedclip=4 --floodclip=3 --table {{obsid}}_{{freq}}-image.vot {{obsid}}_{{freq}}-image.fits

echo "DATE"
date -Iseconds

#mypath=$PATH
#mypythonpath=$PYTHONPATH
module load py-scipy/1.14.1 py-astropy/5.1 py-mpi4py/4.0.1-py3.11.6
srun --export=all -N 1 -n {{n_core}} python ${scripts_dir}/moment_image.py {{obsid}}.hdf5 -f {{freq}} --filter_lo --filter_hi
module unload py-scipy/1.14.1 py-astropy/5.1 py-mpi4py/4.0.1-py3.11.6

#export PATH=$mypath
#export PYTHONPATH=$mypythonpath
singularity exec -B $PWD {{gleam_container}} BANE --cores 1 --compress {{obsid}}_{{freq}}_image_moment2.fits
singularity exec -B $PWD {{gleam_container}} aegean --slice=0 --autoload --seedclip=4 --floodclip=3 --table {{obsid}}_{{freq}}_image_moment2.vot {{obsid}}_{{freq}}_image_moment2.fits

# I don't think we need the _beam.hdf5
#python ${scripts_dir}/make_beam_only.py {{obsid}}.hdf5 {{obsid}}_beam.hdf5 -f 121-132

echo "DATE"
date -Iseconds

#remove unneccesary files
rm {{obsid}}_121-132image_moment1-XX.fits \
	{{obsid}}_121-132image_moment1-YY.fits \
	{{obsid}}_121-132image_moment2-XX.fits \
	{{obsid}}_121-132image_moment2-YY.fits \
	{{obsid}}_121-132-XX-image_bkg.fits \
	{{obsid}}_121-132-XX-image_cal.vot \
	{{obsid}}_121-132-XX-image_comp.vot \
	{{obsid}}_121-132-XX-image_rms.fits \
	{{obsid}}_121-132-XX-image.vot \
	{{obsid}}_121-132-YY-image_bkg.fits \
	{{obsid}}_121-132-YY-image_cal.vot \
	{{obsid}}_121-132-YY-image_comp.vot \
	{{obsid}}_121-132-YY-image_rms.fits \
	{{obsid}}_121-132-YY-image.vot \
	{{obsid}}_image_moments.hdf5 

module load python/3.11.6
python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Complete
