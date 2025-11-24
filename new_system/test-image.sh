module load singularity/4.1.0-slurm
module load python/3.11.6

OBSID=1447141016
ASVOID=952835
LOG=new_system_test.sqlite
data_dir=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

python update_log.py -o ${OBSID} --stage Post-Image -l new_system_test.sqlite

container="/software/projects/mwasci/awaszewski/ips_post.img"
singularity exec -B $PWD ${container} jinja2 postimage-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${data_dir}/${OBSID}-postimage.sh
