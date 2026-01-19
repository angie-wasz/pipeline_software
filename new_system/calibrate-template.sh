#!/bin/bash -l
#SBATCH --account=mwasci-gpu
#SBATCH --partition=mwa-gpu
#SBATCH --job-name={{obsid}}_ips_cal
#SBATCH --output={{output}}
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

echo "DATE"
date -Iseconds

if [ ! -s {{obsid}}.metafits ]; then
	if [ ! -s scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ]; then
		wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
	else
		cp /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ./
	fi
fi

if [ ! -s {{obsid}}.metafits ]; then
	echo "Metafits file doesn't exist, exitting program"
	exit 1 
fi

# MWA primary beam file
export MWA_BEAM_FILE=/scratch/references/mwa/beam-models/mwa_full_embedded_element_pattern.h5

echo "DATE"
date -Iseconds



# 121-132 calibration

# Get data
rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms/ ./{{obsid}}.ms

# Calibration
hyperdrive di-calibrate -d {{obsid}}.ms {{obsid}}.metafits \
	-s {{skymodel}} \
	--num-sources {{sources}} \
	--uvw-min {{uvwmin}} \
	--uvw-max {{uvwmax}} \
	-o {{obsid}}_sols.fits

# Plot solutions
hyperdrive plot-solutions {{obsid}}_sols.fits

echo "DATE"
date -Iseconds

# Convert solutions into bin files
hyperdrive solutions-convert {{obsid}}_sols.fits {{obsid}}_160.bin



# 57-68 calibration

rm -r {{obsid}}.ms

rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch57-68.ms/ ./{{obsid}}.ms

hyperdrive di-calibrate -d {{obsid}}.ms {{obsid}}.metafits \
	-s {{skymodel}} \
	--num-sources {{sources}} \
	--uvw-min {{uvwmin}} \
	--uvw-max {{uvwmax}} \
	-o {{obsid}}_57-68_sols.fits

hyperdrive plot-solutions {{obsid}}_57-68_sols.fits

hyperdrive solutions-convert {{obsid}}_57-68_sols.fits {{obsid}}_57-68_160.bin


# Clean up

# Transfer data back to scratch
rsync -av {{obsid}}_sols.fits \
	{{obsid}}_57-68_sols.fits \
	{{obsid}}*.png \
	{{obsid}}_160.bin \
	{{obsid}}_57-68_160.bin \
	{{obsid}}.metafits \
	{{pipeline}}/{{obsid}}/

cd ../
rm -r {{obsid}}/

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Complete
