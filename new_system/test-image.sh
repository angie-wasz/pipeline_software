module load singularity/4.1.0-slurm

OBSID=1446946472
ASVOID=951906
LOG=new_system_test.sqlite
data_dir=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

container="/software/projects/mwasci/awaszewski/ips_post.img"
singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${data_dir}/${OBSID}-image.sh
