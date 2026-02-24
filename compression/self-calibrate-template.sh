#!/bin/bash -l
#SBATCH --account=mwasci-gpu
#SBATCH --partition=mwa-gpu
#SBATCH --job-name={{obsid}}_cal
#SBATCH --output={{output}}
#SBATCH --nodes=1
#SBATCH --time=00:10:00
#SBATCH --gres=gpu:2
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

sky_model=sun_model_{{obsid}}.yaml

hyperdrive di-calibrate -d {{obsid}}.ms {{obsid}}.metafits \
	-s {{skymodel}} \
	--num-sources {{sources}} \
	--uvw-min {{uvwmin}} \
	--uvw-max {{uvwmax}} \
	--tile-flags Tile051 Tile052 Tile053 Tile054 Tile055 Tile056 Tile057 Tile058 Tile071 Tile072 Tile073 Tile074 Tile075 Tile076 Tile077 Tile078 Tile97 Tile98 Tile101 Tile102 Tile103 Tile104 Tile105 Tile106 Tile107 Tile108 Tile111 Tile112 Tile113 Tile114 Tile115 Tile116 Tile117 Tile118 Tile121 Tile122 Tile123 Tile124 Tile125 Tile126 Tile127 Tile128 Tile131 Tile132 Tile133 Tile134 Tile135 Tile136 Tile137 Tile138 Tile141 Tile142 Tile143 Tile144 Tile145 Tile146 Tile147 Tile148 Tile151 Tile152 Tile153 Tile154 Tile155 Tile156 Tile157 Tile158 Tile161 Tile162 Tile163 Tile164 Tile165 Tile166 Tile167 Tile168 \
	-o {{obsid}}_sols.fits

hyperdrive plot-solutions {{obsid}}_sols.fits

# separate script that extracts the frequency channels required
# then convert into bin
# then aocal interp up to 160kHz? 

# Transfer data back to scratch
rsync -av {{obsid}}_sols.fits \
	{{obsid}}*.png \
	{{obsid}}.metafits \
	{{pipeline}}/{{obsid}}/

cd ../
rm -r {{obsid}}/

