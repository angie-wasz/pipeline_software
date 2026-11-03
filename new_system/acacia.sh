OBSID=$1
DATA=$2
SOFTWARE=$3

module load singularity/4.3.5-slurm

container="/software/projects/mwasci/awaszewski/ips_post.img"
copyouts=/software/projects/mwasci/awaszewski/copyouts/obsids

echo "${OBSID} Moving data to Acacia"

# first create hdf5 transfer job
FILES=${OBSID}.hdf5
path=ips/hdf5_2020/
singularity exec -B $PWD ${container} jinja2 acacia-template.sh acacia-info.yaml --format yaml \
    -D jobName=${OBSID}-hdf5-acacia -D output=${copyouts}/${OBSID}-hdf5-acacia.out \
    -D path=${path} -D DATA=${DATA}/${OBSID} -D FILES=${FILES} \
    --strict -o ${copyouts}/${OBSID}-hdf5-acacia.sh

jobid=$(sbatch ${copyouts}/${OBSID}-hdf5-acacia.sh | cut -d " " -f 4)
#sbatch ${copyouts}/${OBSID}-hdf5-acacia.sh

echo "${OBSID} Compressing directory"
#cd ${DATA}/${OBSID}
#tar -cvf ${OBSID}.tar --exclude={'${DATA}/${OBSID}/${OBSID}.hdf5', '${DATA}/${OBSID}/${OBSID}_121-132_avg.ms', '${DATA}/${OBSID}/${OBSID}_121-132_sols.ms'} ${DATA}/${OBSID}
cd ${DATA}/${OBSID}
tar -cvf "${OBSID}.tar" \
    --exclude="${OBSID}/${OBSID}.hdf5" \
    --exclude="${OBSID}/${OBSID}_121-132_sols.ms" \
    ${DATA}/${OBSID}
cd ${SOFTWARE}
# --exclude="${OBSID}/${OBSID}_121-132_avg.ms" \

FILES=${OBSID}.tar
path=ips/data/
singularity exec -B $PWD ${container} jinja2 acacia-template.sh acacia-info.yaml --format yaml \
    -D jobName=${OBSID}-acacia -D output=${copyouts}/${OBSID}-acacia.out \
    -D path=${path} -D DATA=${DATA}/${OBSID} -D FILES=${FILES} \
    --strict -o ${copyouts}/${OBSID}-acacia.sh
    
transfer_jobid=$(sbatch --dependency=afterok:$jobid ${copyouts}/${OBSID}-acacia.sh | cut -d " " -f 4)

echo "${OBSID} Finished processing - check transfer jobs"
echo "${OBSID} Job ids to check - hdf5 job: ${jobid} and tar job: ${transfer_jobid}"
