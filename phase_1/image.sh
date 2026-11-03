OBSID=$1
freq=$2
#freq_start=$3
#freq_stop=$4
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
LOG=/software/projects/mwasci/awaszewski/phase_1/compression_log.sqlite

module load python/3.11.6
module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

if [ ! -d ${DATA} ]; then
	echo "${OBSID} creating data directory"
	mkdir ${DATA}
fi

ASVOID=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')
#ASVOID=1082551 #for rfi flagging tests

#Check if data still exists
#du -sh /scratch/mwasci/asvo/${ASVOID}/*${freq}*ms

cal_sol="/scratch/mwasci/awaszewski/pipeline/${OBSID}/cal_sol_ch${freq}_sols_scaled_160.bin"

if [ ! -f ${cal_sol} ]; then
	echo "${OBSID} Target solutions do not exist, attempting conversion"
	bash convert_solutions.sh ${OBSID} ${freq} ${cal_sol}
fi

#metafits="/scratch/mwasci/asvo/${ASVO}/${OBSID}.metafits"
#if [ ! -f ${metafits} ]; then
#	echo "${OBSID} Data not available anymore"
#fi

if [ -f ${cal_sol} ]; then
	echo "${OBSID} Imaging"
	singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
		-D obsid=${OBSID} -D asvo=${ASVOID} -D data=${DATA} -D freq=${freq} -D cal_sols=${cal_sol} -D output=${DATA}/${OBSID}_ch${freq}-image_check.out \
		--strict -o ${DATA}/${OBSID}_ch${freq}-image_check.sh

	echo "${OBSID} Submitting image job"
	sbatch ${DATA}/${OBSID}_ch${freq}-image_check.sh
fi
	#-D freq_start=${freq_start} -D freq_stop=${freq_stop} \

#singularity exec -B $PWD ${container} jinja2 apply_sols-template.sh pipeline-info.yaml --format=yaml \
#	-D obsid=${OBSID} -D data=${DATA} -D freq=${freq} -D cal_sols=${cal_sol} -D output=${DATA}/${OBSID}_ch${freq}-apply.out \
#	--strict -o ${DATA}/${OBSID}_ch${freq}-apply.sh

#sbatch ${DATA}/${OBSID}_ch${freq}-apply.sh
