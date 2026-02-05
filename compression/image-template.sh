#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_image
#SBATCH --output={{data}}/{{obsid}}-image.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node={{n_cpu}}
#SBATCH --mem={{mem}}G
#SBATCH --time=05:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load singularity/4.1.0-slurm

cd {{data}}

rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch{{freq}}.ms/ ./{{obsid}}.ms
ms={{obsid}}.ms

if [ ! -s {{obsid}}.metafits ]; then
	if [ ! -s /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ]; then
		wget "http://ws.mwatelescope.org/metadata/fits?obs_id={{obsid}}" -qO {{obsid}}.metafits
	else
		cp /scratch/mwasci/asvo/{{asvo}}/{{obsid}}.metafits ./
	fi
fi

if [ ! -s {{obsid}}.metafits ]; then
	echo "Metafits file doesn't exist, exitting program"
	exit 1 
fi

cal_sol=/scratch/mwasci/awaszewski/pipeline/{{sun_coords[obsid]['cal_obs']}}/{{sun_coords[obsid]['cal_obs']}}_ch129-130_sols.fits

echo "DATE"
date -Iseconds

# chgcentre
singularity exec -B $PWD {{gleam_container}} chgcentre ${ms} {{sun_coords[obsid]['ra']}} {{sun_coords[obsid]['dec']}}

echo "DATE"
date -Iseconds

# Apply calibration solutions
singularity exec -B $PWD {{gleam_container}} applysolutions ${ms} ${cal_sol}

# Standard image
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_cpu}} -abs-mem {{mem}} -name {{obsid}}_{{freq}} --pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -minuv-l {{minuv_l}} -nmiter {{nmiter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -taper-inner-tukey {{taper_inner_tukey}} -taper-gaussian {{taper}} -scale {{scale}} -reorder -log-time ${ms}

# Flag non-core tiles
singularity exec -B $PWD {{gleam_container}} flagantennae ${ms} 11 18 21 22 23 28 31 32 46 48 51 52 53 54 55 56 57 58 61 71 72 73 74 75 76 77 78 81 82 87 88 91 92 93 96 97 98 101 102 103 104 105 106 107 108 111 112 113 114 115 116 117 118 121 122 123 124 125 126 127 128 131 132 133 134 135 136 137 138 141 142 143 144 145 146 147 148 151 152 153 154 155 156 157 158 161 162 163 164 165 166 167 168

# Standard image - core
singularity exec -B $PWD {{gleam_container}} wsclean -j {{n_cpu}} -abs-mem {{mem}} -name {{obsid}}_{{freq}}_core --pol xx,yy -size {{size}} {{size}} -join-polarizations -niter {{niter}} -nmiter {{nmiter}} -auto-threshold {{autothresh}} -auto-mask {{automask}} -scale {{scale_core}} -reorder -log-time ${ms}


