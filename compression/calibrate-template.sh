#!/bin/bash -l
#SBATCH --account=mwasci-gpu
#SBATCH --partition=mwa-gpu
#SBATCH --job-name={{obsid}}_cal
#SBATCH --output={{output}}
#SBATCH --nodes=1
#SBATCH --time=00:30:00
#SBATCH --gres=gpu:3
#SBATCH --export=NONE

set -euxEo pipefail

# Load relevant modules
module load hyperdrive/0.6.1
hyperdrive -V

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

rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.ms/ ./{{obsid}}.ms

hyperdrive di-calibrate -d {{obsid}}.ms {{obsid}}.metafits \
	-s {{skymodel}} \
	--num-sources {{sources}} \
	--uvw-min {{uvwmin}} \
	--uvw-max {{uvwmax}} \
	-o {{obsid}}_sols.fits

hyperdrive plot-solutions {{obsid}}_sols.fits

hyperdrive solutions-convert {{obsid}}_sols.fits {{obsid}}.bin

# Transfer data back to scratch
rsync -av {{obsid}}_sols.fits \
	{{obsid}}*.png \
	{{obsid}}.bin \
	{{obsid}}.metafits \
	{{pipeline}}/{{obsid}}/

cd ../
rm -r {{obsid}}/

