module load singularity/4.1.0-slurm
module load python/3.11.6
module load giant-squid/2.3.0
module load py-numpy/1.25.2
module load py-astropy/5.1
set -eE

export MWA_ASVO_API_KEY=bafde459-bcaa-4019-84b8-b87667f01e47
export GIANT_SQUID_DELIVERY=scratch

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
		-s|--safemode)
			SAFEMODE="$2"
			shift
			shift;;
		-o|--obsid)
			OBSID="$2"
			shift
			shift;;
		-l|--log)
			LOG="$2"
			shift
			shift;;
		-*|--*)
			echo "Unknown option $1"
			exit 1;;
		*)
			POSITIONAL_ARGS+=("$1")
			shift;
	esac
done
set -- "${POSITIONAL_ARGS[@]}"

if [ -z "$OBSID" ]; then
	echo "No OBSID passed in"
	exit 1
elif [[ ${#OBSID} -ne 10 ]]; then
	echo "OBSID of incorrect format, must be in GPS (10 digits)"
	exit 1
fi

echo "Parameters passed to pipeline"
echo "OBSID		= $OBSID"
echo "SAFEMODE	= ${SAFEMODE}"
echo " "

# Want to kick off obsid with a delay rather than all at once, especially at the beginning
# sleep for a random amount of time
sleep $(echo "scale=3; $RANDOM/32768*10" | bc)

# Start log
# first check if it already exists
echo "Checking if observation is initialised in log"
output=$(python read_log.py -l ${LOG} -o ${OBSID})
if [[ -z "$output" ]]; then
	python update_log.py -l ${LOG} -o ${OBSID} --initialise
fi

# Data storage
echo "Checking if data directory already exists"
data_dir="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"
if [ ! -d ${data_dir} ]; then
	mkdir ${data_dir}
fi

# ASVO staging
echo "Staging on ASVO"
python update_log.py -l ${LOG} -o ${OBSID} --stage ASVO --status Processing
if giant-squid submit-conv ${OBSID} -w -d scratch -p avg_time_res=0.5,avg_freq_res=160,flag_edge_width=160,output=ms; then
	giant-squid list ${OBSID} > asvo_${OBSID}
	ASVOID=$(grep "Conversion" asvo_${OBSID} | awk '{print $2}')
	rm asvo_${OBSID}
	python update_log.py -l ${LOG} -o ${OBSID} --status Complete
else
	echo "Failed to stage ${OBSID} on ASVO"
	python update_log.py -l ${LOG} -o ${OBSID} --status Failed
	exit 1
fi
python update_log.py -l ${LOG} -o ${OBSID} --asvo ${ASVOID}

# Calibration
echo "Creating calibrate job"
container="/software/projects/mwasci/awaszewski/ips_post.img"
singularity exec -B $PWD ${container} jinja2 calibrate-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${data_dir}/${OBSID}-calibrate.sh

echo "Submitting calibrate job"
python update_log.py -l ${LOG} -o ${OBSID} --stage Calibration --status Queued
cd ${data_dir}
sbatch ${OBSID}-calibrate.sh | cut -d " " -f 4

running=1
while [ ${running} -eq 1 ]; do
	sleep 180
	echo "Checking if observation has finished processing"
	output=$(python /software/projects/mwasci/awaszewski/new_system/read_log.py -l /software/projects/mwasci/awaszewski/new_system/${LOG} -o ${OBSID} | cut -d "|" -f 4)
	if [[ "$output" == *"Failed"* ]]; then
		running=0
		echo "Calibration has failed"
		exit 1
	elif [[ "$output" == *"Complete"* ]]; then
		running=0
		echo "Running data quality checks"
		python /software/projects/mwasci/awaszewski/quality_scripts/calc_quality.py -o ${OBSID} -p ${data_dir} -l /software/projects/mwasci/awaszewski/new_system/${LOG}
	fi
done

echo "Calibration complete"
echo " "

log_dir=/software/projects/mwasci/awaszewski/new_system/
cd ${log_dir}

echo "Begin Imaging"

frac_bad=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 2 | awk '{print $2}')
resid=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 3 | awk '{print $2}')
echo $frac_bad $resid
if [ ${frac_bad} -gt 0.6 ]; then
	if [ ${resid} -gt 20 ]; then
		echo "Data quality does not meet requirements for imaging"
		exit
	fi
fi
echo "Data quality good enough"

echo "Creating image and post-image job"
container="/software/projects/mwasci/awaszewski/ips_post.img"
singularity exec -B $PWD ${container} jinja2 image-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${data_dir}/${OBSID}-image.sh

singularity exec -B $PWD ${container} jinja2 postimage-template.sh pipeline-info.yaml --format=yaml \
	-D obsid=${OBSID} -D asvo=${ASVOID} -D log=${LOG} \
	--strict -o ${data_dir}/${OBSID}-postimage.sh

echo "Submitting image and post-image job"
python update_log.py -l ${LOG} -o ${OBSID} --stage Imaging --status Queued
cd ${data_dir}
jobid = $(sbatch ${OBSID}-image.sh | cut -d " " -f 4)

# Post Imaging
sbatch --dependency=afterok:$jobid ${OBSID}-post-image.sh

running=1
while [ ${running} -eq 1 ]; do
	sleep 300
	echo "Checking if observation has finished processing"
	output=$(python ${log_dir}/read_log.py -l ${log_dir}/${LOG} -o ${OBSID} | cut -d "|" -f 4)
	if [[ "$output" == *"Failed"* ]]; then
		running=0
		echo "Imaging has failed"
		exit 1
	elif [[ "$output" == *"Complete"* ]]; then
		running=0
		echo "Processing has completed"
	fi
done

# move hdf5 to acacia separately in its own hdf5 directory
# zip up the rest of the observation directory and shove it onto acacia
