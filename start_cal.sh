module load singularity
set -euo pipefail
obsid=$1
asvo=$2
year=$3

out_dir=/scratch/mwasci/awaszewski/pipeline/${year}/${obsid}

container=/software/projects/mwasci/awaszewski/ips_post.img
scripts_dir=/software/projects/mwasci/awaszewski/imaging_scripts/

singularity exec -B $PWD ${container} jinja2 ${scripts_dir}/calibrate-template.sh ${scripts_dir}/pipeline-info.yaml --format=yaml \
	-D obsid=${obsid} \
	-D asvo=${asvo} \
	--strict -o ${out_dir}/${obsid}-calibrate.sh

slurmid=$(sbatch ${out_dir}/${obsid}-calibrate.sh | cut -d " " -f 4)

echo "Queued all jobs"
