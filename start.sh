module load singularity
set -euo pipefail
obsid=$1
asvo=$2
year=$3

#python3 gen_slurm_image.py -o ${obsid} -a ${asvo} -y ${year}

#out_dir=/astro/mwasci/awaszewski/feb_cme/2023/${obsid}
out_dir=/scratch/mwasci/awaszewski/pipeline/${year}/${obsid}

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
