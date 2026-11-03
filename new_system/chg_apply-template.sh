#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_ips_apply
#SBATCH --output={{data}}/{{obsid}}-apply.out
#SBATCH --nodes=1
#SBATCH --time=03:00:00
#SBATCH --export=NONE
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --mem=100G
set -euxEo pipefail

module load python/3.11.6
module load hyperdrive/0.6.1-cpu
module load singularity/4.1.0-slurm

trap 'module load python/3.11.6; python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

sleep $(echo "scale=3; $RANDOM/32768*30" | bc)

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Applying

echo "DATE"
date -Iseconds

# Go to temp directory and make unique name
cd /dev/shm/
mkdir {{obsid}}_{{freq}}/
cd {{obsid}}_{{freq}}/

# Copy over measurement set to temp directory
rsync -av /scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch{{freq}}.ms ./
mv {{obsid}}_ch{{freq}}.ms {{obsid}}_{{freq}}_sols.ms
ms={{obsid}}_{{freq}}_sols.ms

# for those already downloaded
#rsync -av {{data}}/{{obsid}}_{{freq}}_avg.ms ./
#mv {{obsid}}_{{freq}}_avg.ms {{obsid}}_{{freq}}_sols.ms
#ms={{obsid}}_{{freq}}_sols.ms

echo "DATE"
date -Iseconds

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

if [ -f ${ms}/table.lock ]; then
	rm ${ms}/table.lock
fi

echo "DATE"
date -Iseconds

# Change centre
singularity exec -B $PWD {{gleam_container}} chgcentre -minw -shiftback ${ms}

echo "DATE"
date -Iseconds

# Apply calibration solutions
cal_sol={{calsol}}
singularity exec -B $PWD {{gleam_container}} applysolutions ${ms} ${cal_sol}

echo "DATE"
date -Iseconds

# Copy over back to /scratch
rsync -av ${ms} {{data}}/

# Clean up temp directory and go back to /scratch
cd ../
rm -r {{obsid}}_{{freq}}/
cd {{data}}

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Applied
