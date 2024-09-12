module load singularity
set -euo pipefail
obsid=$1
asvo=$2
year=$3

out_dir=/scratch/mwasci/awaszewski/pipeline/${year}/${obsid}
echo "Checking if out directory exists"
if [ ! -d ${out_dir} ]; then
	echo "Making out directory"
	mkdir ${out_dir}
fi

container=/software/projects/mwasci/awaszewski/ips_post.img
scripts_dir=/software/projects/mwasci/awaszewski/imaging_scripts/

#echo "Creating first slurm script"
#singularity exec -B $PWD ${container} jinja2 ${scripts_dir}/image-template.sh ${scripts_dir}/pipeline-info.yaml --format=yaml \
#	-D obsid=${obsid} \
#	-D asvo=${asvo} \
#	--strict -o ${out_dir}/${obsid}-image.sh

#slurmid1=$(sbatch ${out_dir}/${obsid}-image.sh | cut -d " " -f 4)

echo "Creating second slurm script"
singularity exec -B $PWD ${container} jinja2 ${scripts_dir}/post-image-template.sh ${scripts_dir}/pipeline-info.yaml --format=yaml \
	-D obsid=${obsid} \
	--strict -o ${out_dir}/${obsid}-post-image.sh

#slurmid2=$(sbatch --dependency=afterok:${slurmid1} ${out_dir}/${obsid}-post-image.sh)
slurmid2=$(sbatch ${out_dir}/${obsid}-post-image.sh)

echo "Queued all jobs"
