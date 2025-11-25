#!/bin/bash -l
#SBATCH --account=mwasci-gpu
#SBATCH --partition=mwa-gpu
#SBATCH --job-name={{obsid}}_ips_cal
#SBATCH --output={{obsid}}-cal.out
#SBATCH --nodes=1
#SBATCH --time=00:10:00
#SBATCH --gres=gpu:1
#SBATCH --export=NONE

set -euxEo pipefail

# Load relevant modules
module load python/3.11.6
module load hyperdrive/0.6.1
hyperdrive -V

# In case calibration fails
trap 'python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

# Update database
python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Running

# Move into temp dir
cd /tmp
mkdir {{obsid}}
cd {{obsid}}/

# Get data
cp -r /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms ./{{obsid}}.ms
cp /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ./

# MWA primary beam file
export MWA_BEAM_FILE=/scratch/references/mwa/beam-models/mwa_full_embedded_element_pattern.h5

# Calibration
hyperdrive di-calibrate -d {{obsid}}.ms {{obsid}}.metafits \
	-s {{skymodel}} \
	--num-sources {{sources}} \
	--uvw-min {{uvwmin}} \
	--uvw-max {{uvwmax}} \
	-o {{obsid}}_sols.fits

# Plot solutions
hyperdrive plot-solutions {{obsid}}_sols.fits

# Convert solutions into bin files
hyperdrive solutions-convert {{obsid}}_sols.fits {{obsid}}_160.bin

# Transfer data back to scratch
rsync -av {{obsid}}_sols.fits \
	{{obsid}}*.png \
	{{obsid}}_160.bin \
	{{obsid}}.metafits \
	{{pipeline}}/{{obsid}}/

# Clean up
cd ../
rm -r {{obsid}}/

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Complete
