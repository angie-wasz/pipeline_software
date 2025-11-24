OBSID=$1
ASVOID=$2
DATA=$3
SOFTWARE=$4
LOG=$5

module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

echo "${OBSID} Calibration"

singularity exec -B $PWD ${container} jinja2 calibrate-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${DATA}/${OBSID}-calibrate.sh

python update_log.py -l ${LOG} -o ${OBSID} --stage Calibration --status Queued

cd ${DATA}
sbatch ${OBSID}-calibrate.sh
cd ${SOFTWARE}

running=1
while [ ${running} -eq 1 ]; do
    
    sleep 300 #the typical amount of time it takes to calibrate + some queue time
    output=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 4)

    if [[ "$output" == *"Failed"* ]]; then 
        
        echo "${OBSID} Calibration has failed"
        exit 1

    elif [[ "$output" == *"Complete" ]]; then   
        
        running=0
        python /software/projects/mwasci/awaszewski/quality_scripts/calc_quality.py -o ${OBSID} -p ${DATA} -l ${SOFTWARE}/${LOG} -s ${SOFTWARE}

    fi
done

echo "${OBSID} Calibration complete"
