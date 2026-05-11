OBSID=$1
FREQ=$2
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
CAL_SOLS=/scratch/mwasci/awaszewski/pipeline/${OBSID}/${OBSID}.bin
LOG=/software/projects/mwasci/awaszewski/phase_1/compression_log.sqlite

module load python/3.11.6
module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

#sleep $(echo "scale=3; $RANDOM/32768*10" | bc)

if [ ! -d ${DATA} ]; then
    echo "${OBSID} creating data directory"
    mkdir ${DATA}
fi

ASVOID=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')

echo "${OBSID} Calibration"

#FREQ='62-63'

singularity exec -B $PWD ${container} jinja2 self-calibrate-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D output=${DATA}/${OBSID}_ch${FREQ}-calibrate.out -D freq=${FREQ} \
	--strict -o ${DATA}/${OBSID}_${FREQ}-calibrate.sh

sbatch ${DATA}/${OBSID}_${FREQ}-calibrate.sh

#echo "${OBSID} Imaging"

#singularity exec -B $PWD ${container} jinja2 cal-image-template.sh pipeline-info.yaml --format=yaml \
#    -D obsid=${OBSID} -D asvo=${ASVOID} -D calsol=${CAL_SOLS} -D data=${DATA} \
#    --strict -o ${DATA}/${OBSID}-image.sh

#sbatch ${DATA}/${OBSID}-image.sh
