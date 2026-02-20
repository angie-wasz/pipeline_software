OBSID=$1
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
LOG=/software/projects/mwasci/awaszewski/compression/compression_log.sqlite

module load python/3.11.6
module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

if [ ! -d ${DATA} ]; then
	echo "${OBSID} creating data directory"
	mkdir ${DATA}
fi

ASVOID=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')

echo "${OBSID} Imaging"

# WILL HAVE TO MANUALLY CHANGE THESE PARAMETERS FOR THE DIFFERENT GLEAM BANDS 
cal_obs=1061486560
cal_freq_ch='62-63'
cal_sol="/scratch/mwasci/awaszewski/pipeline/${cal_obs}/${cal_obs}_ch${cal_freq_ch}.bin"

singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D data=${DATA} -D cal_sol=${cal_sol}\
	--strict -o ${DATA}/${OBSID}-image.sh

sbatch ${DATA}/${OBSID}-image.sh
