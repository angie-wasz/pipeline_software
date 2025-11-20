OBSID=$1
ASVOID=$2
DATA=$3
SOFTWARE=$4
LOG=$5

container="/software/projects/mwasci/awaszewski/ips_post.img"

echo "${OBSID} Imaging and Post-imaging"

singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${DATA}/${OBSID}-image.sh

singularity exec -B $PWD ${container} jinja2 postimage-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${DATA}/${OBSID}-postimage.sh

python update_log.py -l ${LOG} -o ${OBSID} --stage Imaging --status Queued

cd ${DATA}
jobid = $(sbatch ${OBSID}-image.sh | cut -d " " -f 4)
sbatch --dependency=afterok:$jobid ${OBSID}-post-image.sh
cd ${SOFTWARE}

sleep 1800

running=1
while [ ${running} -eq 1 ]; do

    sleep 600
    output=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 4)

    if [[ "$output" == *"Failed"* ]]; then

        echo "${OBSID} Imaging has failed"
        exit 1

    elif [[ "$output" == *"Complete" ]]; then

        running=0

    fi
done

echo "${OBSID} Imaging and Post-imaging complete