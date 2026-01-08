STAGE=$1
OBSID=$2
ASVOID=$3
CAL_SOLS=$4
DATA=$5
SOFTWARE=$6
LOG=$7

module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

echo "${OBSID} Imaging and Post-imaging"

if [[ ("${STAGE}" == "full") || ("${STAGE}" == "image") ]]; then
	singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
		-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} -D calsol=${CAL_SOLS}\
		--strict -o ${DATA}/${OBSID}-image.sh
fi

if [[ ("${STAGE}" == "full") || ("${STAGE}" == "post") ]]; then
	singularity exec -B $PWD ${container} jinja2 postimage-template.sh pipeline-info.yaml --format=yaml \
		-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
		--strict -o ${DATA}/${OBSID}-postimage.sh
fi

cd ${DATA}

if [[ ("${STAGE}" == "full") ]]; then

	python update_log.py -l ${LOG} -o ${OBSID} --stage Imaging --status Queued
	jobid=$(sbatch ${OBSID}-image.sh | cut -d " " -f 4)
	sbatch --dependency=afterok:${jobid} ${OBSID}-postimage.sh
	FINAL="Complete"

elif [[ ("${STAGE}" == "image") ]]; then

	python update_log.py -l ${LOG} -o ${OBSID} --stage Imaging --status Queued
	sbatch ${OBSID}-image.sh
	FINAL="Done"

elif [[ ("${STAGE}" == "post") ]]; then
	
	python update_log.py -l ${LOG} -o ${OBSID} --stage Post-Image --status Queued
	sbatch ${OBSID}-postimage.sh
	FINAL="Complete"

else
	echo "${OBSID} stage passed incorrectly"
	exit 1
fi

cd ${SOFTWARE}

running=1
while [ ${running} -eq 1 ]; do

    sleep 600
    output=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 4)

    if [[ "$output" == *"Failed"* ]]; then

        echo "${OBSID} Imaging has failed"
        exit 1

    elif [[ "$output" == *"${FINAL}"* ]]; then

        running=0

    fi

done

echo "${OBSID} Imaging and Post-imaging complete"
