module load singularity
set -euo pipefail
obsid=$1
asvo=$2
year=$3
log_file=$4

out_dir=/scratch/mwasci/awaszewski/pipeline/${year}/${obsid}
echo "Checking if out directory exists"
if [ ! -d ${out_dir} ]; then
	echo "Making directory: ${out_dir}"
	mkdir ${out_dir}
fi

container=/software/projects/mwasci/awaszewski/ips_post.img
scripts_dir=/software/projects/mwasci/awaszewski/imaging_scripts/

singularity exec -B $PWD ${container} jinja2 ${scripts_dir}/calibrate-template.sh ${scripts_dir}/pipeline-info-2022.yaml --format=yaml \
	-D obsid=${obsid} \
	-D asvo=${asvo} \
	-D log_file=${log_file} \
	--strict -o ${out_dir}/${obsid}-calibrate.sh

slurmid=$(sbatch ${out_dir}/${obsid}-calibrate.sh | cut -d " " -f 4)

echo "Queued all jobs"
