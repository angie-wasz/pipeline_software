module load python/3.11.6
module load py-numpy/1.25.2
module load py-astropy/4.2.1

set -eE

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
		-s|--safemode)
			SAFEMODE="$2"
			shift
			shift;;
		-c|--calibrate)
			CALIBRATE="$2"
			shift
			shift;;
		-i|--image)
			IMAGE="$2"
			shift
			shift;;
		-p|--post-image)
			POSTIMAGE="$2"
			shift
			shift;;
		--skip-fail-check)
			SKIP_FAIL_CHECK="$2"
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
	echo "OBSID of incorrect format, must be in GPS (10 digits) - what was provided: ${OBSID}"
	exit 1
fi

# Want to kick off obsid with a delay rather than all at once, especially at the beginning
# sleep for a random amount of time
sleep $(echo "scale=3; $RANDOM/32768*10" | bc)

SOFTWARE=/software/projects/mwasci/awaszewski/new_system/
SCRATCH=/scratch/mwasci/awaszewski/pipeline/
ASVO=/scratch/mwasci/asvo/

# Data storage
echo "${OBSID} Checking if data directory already exists"
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"
if [ ! -d ${DATA} ]; then
	echo "${OBSID} creating data directory"
	mkdir ${DATA}
fi

ASVO_SKIP=FALSE
#CAL_SKIP=FALSE

# I'm aware that if a data directory already exists, its probably been processed previously but easier to check with log
# Start log
echo "${OBSID} Checking if observation is initialised in log"
output=$(python read_log.py -l ${LOG} -o ${OBSID})

if [ -z "$output" ]; then
	# If not previously processed, add it to the log
	echo "${OBSID} initialising observation in log"
	python update_log.py -l ${LOG} -o ${OBSID} --initialise
else
	# Otherwise, read info about the observation
	stage=$(echo ${output} | cut -d "|" -f 3 | awk '{print $2}')
	status=$(echo ${output} | cut -d "|" -f 4 | awk '{print $2}')
	ASVOID=$(echo ${output} | cut -d "|" -f 2 | awk '{print $2}')

	# Has it failed in the past?
	if [[ $SKIP_FAIL_CHECK = FALSE ]]; then 
		if [[ "$status" == "Failed" ]]; then
			echo "${OBSID} has been processed in the past and has failed. Skipping this observation. If you want to run it again, then create new list of failed observations and add flag --skip-fail-check"
			exit
		fi
	fi
	
	# Is data from ASVO already available?
	if [[ $ASVOID -ne 0 ]]; then
		echo "${OBSID} has already been downloaded from ASVO. Checking if measurement set is available."
		ms=${ASVO}/${ASVOID}/${OBSID}_ch121-132.ms/table.dat
		if [ -f ${ms} ]; then
			echo "${OBSID} measurement set available. Skipping ASVO download"
			ASVO_SKIP=TRUE
		else
			echo "${OBSID} measurement set does not exist. Proceeding with ASVO download"
		fi
	fi
		
	# Has it been calibrated?
#	cal_sols=${DATA}/${OBSID}_sols_162MHz_160.bin
#	if [ -f ${cal_sols} ]; then
#		echo "${OBSID} calibration solutions are available. Skipping calibration"
#		CAL_SKIP=TRUE
#	else
#		echo "${OBSID} calibration solutions do not exist. Proceeding with calibration"
#	fi

fi

# ASVO staging (if required)
if [ $ASVO_SKIP = FALSE ]; then
	bash ./asvo.sh ${OBSID} ${LOG}
	ASVOID=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')
fi

cal_sols=${DATA}/${OBSID}_sols_162MHz_160.bin
echo "${OBSID} Checking if calibration solutions exist"
if [ -f ${cal_sols} ]; then
	echo "${OBSID} calibration solutions are available. Skipping calibration"
else
	echo "${OBSID} calibration solutions do not exist. Proceeding with calibration"
	bash ./calibrate.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}
fi

# Data Quality
echo "${OBSID} Checking data quality"

module load singularity/4.1.0-slurm
module unload python/3.11.6 py-numpy/1.25.2 py-astropy/4.2.1

container="/software/projects/mwasci/awaszewski/ips_post.img"
singularity exec -B $PWD ${container} python /software/projects/mwasci/awaszewski/quality_scripts/calc_quality.py -o ${OBSID} -p ${DATA} -l ${SOFTWARE}/${LOG} -s ${SOFTWARE}

module load python/3.11.6 py-numpy/1.25.2 py-astropy/4.2.1 

frac_bad=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 2 | awk '{print $2}')
resid=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 3 | awk '{print $2}')
echo "${OBSID} quality ${frac_bad} ${resid}"

if [[ -z "$frac_bad" || -z "$resid" ]]; then
	echo "${OBSID} Quality metrics don't exist"
	exit 1
fi

# Does it qualify for imaging?
frac_bad_limit=0.6
resid_limit=20
if (( $(echo "$frac_bad > $frac_bad_limit" | bc -l) )); then
	if (( $(echo "$resid > $resid_limit" | bc -l) )); then
		echo "$OBSID Data quality does not meet requirements for further processing"
		python update_log.py -l ${LOG} -o ${OBSID} --status 'Bad Quality'
		exit 1
	fi
fi

# Stopping here if only calibration option was chosen
if [ "$CALIBRATE" == "TRUE" ]; then
	echo "${OBSID} As only calibration was chosen, workflow finishing now"
	exit
fi

# Imaging and Post-imaging
if [ "$IMAGE" == "TRUE" ]; then
	echo "${OBSID} Only proceeding with imaging (no post image)"
	STAGE="image"
elif [ "$POSTIMAGE" == "TRUE" ]; then
	echo "${OBSID} Only proceeding with post-imaging. Checking if images exist."
	image_file=${DATA}/${OBSID}_121-132-XX-image.fits
	if [ -f ${image_file} ]; then
		echo "${OBSID} Images exist, proceeding with post-imaging"
		STAGE="post"
	else
		echo "${OBSID} Images do not exist, first running imaging"
		STAGE="full"
	fi
else
	echo "${OBSID} Proceeding with full image and post-image"
	STAGE="full"
fi

# Some form of imaging must run if it is selected
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"
bash ./image.sh ${STAGE} ${OBSID} ${ASVOID} ${cal_sols} ${DATA} ${SOFTWARE} ${LOG}

# Did it successfully image?
output=$(python read_log.py -l ${LOG} -o ${OBSID})
status=$(echo ${output} | cut -d "|" -f 4 | awk '{print $2}')
if [[ "$status" == "Failed" ]]; then
	echo "${OBSID} has failed image or post-image, exiting pipeline"
	exit
fi

# g-level and Acacia storage
# If post image was run, then do post processing
#FREQ='121-132'
if [[ ("$STAGE" == "full") || ("$STAGE" == "post") ]]; then
# CURRENTLY HAVE ISSUES WITH THIS PART, WEIRD CONTAINER ISSUES
#	bash ./glevel.sh ${OBSID} ${DATA} ${SOFTWARE} ${LOG} ${FREQ}
	bash ./acacia.sh ${OBSID} ${SCRATCH} ${SOFTWARE}
fi

echo "${OBSID} done"
