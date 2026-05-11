OBSID=$1
freq=$2
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
LOG=/software/projects/mwasci/awaszewski/phase_1/compression_log.sqlite

module load python/3.11.6
module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

ASVOID=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')

echo "${OBSID} Imaging"

cal_sol="/scratch/mwasci/awaszewski/pipeline/${OBSID}/cal_sol_ch${freq}_sols_fine_160.bin"

singularity exec -B $PWD ${container} jinja2 dynamic-spectrum-imaging.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D data=${DATA} -D freq=${freq} -D cal_sols=${cal_sol} -D output=${DATA}/${OBSID}_ch${freq}-image_ds.out \
	--strict -o ${DATA}/${OBSID}_ch${freq}-image_ds.sh

echo "${OBSID} Submitting image job"
sbatch ${DATA}/${OBSID}_ch${freq}-image_ds.sh
