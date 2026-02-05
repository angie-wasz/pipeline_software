OBSID=1062301216
ASVOID=982876
CAL_SOLS=/scratch/mwasci/awaszewski/pipeline/1062280936/1062280936_ch129-130_160.bin
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

echo "${OBSID} Imaging and Post-imaging"

singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D calsol=${CAL_SOLS} -D data=${DATA} \
	--strict -o ${DATA}/${OBSID}-image.sh

sbatch ${DATA}/${OBSID}-image.sh
