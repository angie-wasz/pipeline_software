#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name={{obsid}}_ips_avg
#SBATCH --output={{data}}/{{obsid}}-avg.out
#SBATCH --nodes=1
#SBATCH --time=12:00:00
#SBATCH --export=NONE
#SBATCH --ntasks-per-node={{n_core}}
#SBATCH --mem={{mem}}G
set -euxEo pipefail

module load python/3.11.6
module load hyperdrive/0.6.1-cpu
module load singularity/4.1.0-slurm

trap 'module load python/3.11.6; python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Failed' ERR

sleep $(echo "scale=3; $RANDOM/32768*30" | bc)

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Averaging

echo "DATE"
date -Iseconds

cd {{data}}

ms=/scratch/mwasci/asvo/{{asvo}}/{{obsid}}_ch121-132.ms
new_ms={{obsid}}_121-132_avg.ms
hyperdrive vis-convert --freq-average 160kHz -o ${new_ms} -d ${ms}

echo "DATE"
date -Iseconds

python {{software}}/new_system/update_log.py -l {{software}}/new_system/{{log}} -o {{obsid}} --status Averaged
