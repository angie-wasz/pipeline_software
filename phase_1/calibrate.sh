OBSID=$1
FREQ=$2
#FREQ='62-63'
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
CAL_SOLS=/scratch/mwasci/awaszewski/pipeline/${OBSID}/${OBSID}.bin
LOG=/software/projects/mwasci/awaszewski/phase_1/compression_log.sqlite

# CHECK IF DATA DIRECTORY EXISTS
if [ ! -d ${DATA} ]; then
    echo "${OBSID} Creating data directory"
    mkdir ${DATA}
fi

# CHECK IF SUN MODEL EXISTS
module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

if [ ! -s ${DATA}/sun_model_${OBSID}.yaml ]; then
	echo "${OBSID} Generating solar model"
	singularity exec -B $PWD ${container} python3 generate_sun_model.py -d ${DATA} -o ${OBSID}
fi

# GET ASVO DATA
module load python/3.11.6
ASVOID=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')

# CALIBRATION
echo "${OBSID} Calibration"

singularity exec -B $PWD ${container} jinja2 self-calibrate-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D output=${DATA}/${OBSID}_ch${FREQ}-calibrate.out -D freq=${FREQ} \
	--strict -o ${DATA}/${OBSID}_${FREQ}-calibrate.sh

sbatch ${DATA}/${OBSID}_${FREQ}-calibrate.sh

# would ideally then do fit temp straight away but that would involve the data base and i don't want to do that right now
