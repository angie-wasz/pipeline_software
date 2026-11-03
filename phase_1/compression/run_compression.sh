#!/bin/bash -l
#SBATCH --account=mwasci
#SBATCH --partition=mwa
#SBATCH --job-name=solar_compression
#SBATCH --output=/software/projects/mwasci/awaszewski/phase_1/compression/compression_quiet_129-130.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=32
#SBATCH --mem=50G
#SBATCH --time=06:00:00
#SBATCH --export=NONE

set -euxEo pipefail

module load singularity/4.1.0-slurm

software=/software/projects/mwasci/awaszewski/phase_1/compression/
data=/scratch/mwasci/awaszewski/pipeline/
freq=129-130
#obs=1061264416
obs=1063597216
cd ${data}/${obs}/

echo 'DATE: copying measurement set'
date -Iseconds
cp -r ${obs}_ch${freq}.ms ${obs}_ch${freq}_scaled.ms
ms=${obs}_ch${freq}_scaled.ms

echo 'DATE: remove DATA column'
date -Iseconds
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif /code/venv/bin/python ${software}/strip_cols.py --filename ${ms} --datacol DATA

echo 'DATE: scale visibilities to match virgo flux'
date -Iseconds
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif /code/venv/bin/python ${software}/scale_visibilities.py --file ${ms} --scale 15.9

echo 'DATE: image pre-compressed data'
date -Iseconds
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif wsclean -name ${obs}_${freq}_precompress -data-column CORRECTED_DATA -j 32 -abs-mem 50 -pol xx,yy -size 1024 1024 -join-polarizations -niter 100000 -minuv-l 0 -nmiter 0 -auto-threshold 2 -auto-mask 3 -taper-inner-tukey 50 -taper-gaussian 2amin -scale 0.2amin -reorder -log-time ${ms}

comp=mgard
for acc in 100 50 25 10 5 1; do
echo 'Accuracy' ${acc}

echo 'DATE: copying measurement set'
date -Iseconds
cp -r ${obs}_ch${freq}_scaled.ms ${obs}_ch${freq}_compress_${acc}.ms
ms=${obs}_ch${freq}_compress_${acc}.ms

echo 'DATE: compressing'
date -Iseconds
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif /code/venv/bin/python ${software}/create_compressed_col.py --filename ${ms} --datacol CORRECTED_DATA --accuracy ${acc} --compressor ${comp}

echo 'DATE: imaging compressed data col'
date -Iseconds
acc_str=$(printf "%03d" "$acc")
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif wsclean -name ${obs}_${freq}_compress_${acc_str} -data-column COPY_DATA -j 32 -abs-mem 50 -pol xx,yy -size 1024 1024 -join-polarizations -niter 100000 -minuv-l 0 -nmiter 0 -auto-threshold 2 -auto-mask 3 -taper-inner-tukey 50 -taper-gaussian 2amin -scale 0.2amin -reorder -log-time ${ms}

echo 'DATE: removing redundant data cols'
date -Iseconds
singularity exec -B $PWD ${software}/wsclean-nompi-portable.sif /code/venv/bin/python ${software}/strip_cols.py --filename ${ms} --datacol DATA,CORRECTED_DATA

done

echo 'DATE: done'
date -Iseconds
