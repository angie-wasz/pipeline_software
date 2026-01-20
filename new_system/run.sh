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
SCRATCH=/scratch/mwasci/awaszewski/pipeline

# Data storage
echo "${OBSID} Checking if data directory already exists"
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"
if [ ! -d ${DATA} ]; then
	echo "${OBSID} creating data directory"
	mkdir ${DATA}
fi
# I'm aware that if a data directory already exists, its probably been processed previously but easier to check with log

ASVO_SKIP=FALSE
CAL_SKIP=FALSE

# Start log
echo "${OBSID} Checking if observation is initialised in log"
output=$(python read_log.py -l ${LOG} -o ${OBSID})

if [ -z "$output" ]; then
	echo "${OBSID} initialising observation in log"
	python update_log.py -l ${LOG} -o ${OBSID} --initialise
else
	stage=$(echo ${output} | cut -d "|" -f 3 | awk '{print $2}')
	status=$(echo ${output} | cut -d "|" -f 4 | awk '{print $2}')
	ASVOID=$(echo ${output} | cut -d "|" -f 2 | awk '{print $2}')

	if [[ $SKIP_FAIL_CHECK = FALSE ]]; then 
		if [[ "$status" == "Failed" ]]; then
			echo "${OBSID} has been processed in the past and has failed. Skipping this observation. If you want to run it again, then create new list of failed observations and add flag --skip-fail-check"
			exit
		fi
	fi
	
	if [[ $ASVOID -ne 0 ]]; then
		echo "${OBSID} has already been downloaded from ASVO. Checking if measurement set is available."
		ms=/scratch/mwasci/asvo/${ASVOID}/${OBSID}_ch121-132.ms/table.dat
		if [ -f ${ms} ]; then
			echo "${OBSID} measurement set available. Skipping ASVO download"
			ASVO_SKIP=TRUE
		else
			echo "${OBSID} measurement set does not exist. Proceeding with ASVO download"
		fi
	fi

	if [[ ("$stage" == "Calibration" && "$status" == "Complete") || ("$stage" == "Imaging" || "$stage" == "Post-Image") ]]; then
		echo "${OBSID} has already been through calibration. Checking if calibration solutions are available."
		#cal_sols=${DATA}/${OBSID}_sols.fits
		#if [ -f ${cal_sols} ]; then
		#	echo "${OBSID} calibration solutions are available. Skipping calibration"
		#	CAL_SKIP=TRUE
		#else
		cal_sols=${DATA}/${OBSID}_160.bin
		if [ -f ${cal_sols} ]; then
			echo "${OBSID} calibration solutions are available. Skipping calibration"
			CAL_SKIP=TRUE
		else
			echo "${OBSID} calibration solutions do not exist. Proceeding with calibration"
		fi
		#fi
	fi
fi

# ASVO staging
if [ $ASVO_SKIP = FALSE ]; then
	bash ./asvo.sh ${OBSID} ${LOG}
	ASVOID=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')
fi

# Calibration
if [ $CAL_SKIP = FALSE ]; then
	bash ./calibrate.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}
fi

# Data Quality (part of calibration)
echo "${OBSID} Checking data quality"
frac_bad=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 2 | awk '{print $2}')
resid=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 3 | awk '{print $2}')
echo "${OBSID} quality ${frac_bad} ${resid}"

if [[ -z "$frac_bad" || -z "$resid" ]]; then
	echo "${OBSID} Quality metrics don't exist"
	exit 1
fi

if (( $(echo "$frac_bad > 0.6" | bc -l) )); then
	if (( $(echo "$resid > 20" | bc -l) )); then
		echo "${OBSID} Data quality does not meet requirements for further processing"
		exit
	fi
fi

if [ "$CALIBRATE" == "TRUE" ]; then
	echo "${OBSID} As only calibration was chosen, workflow finishing now"
	exit
fi

# Imaging
if [ "$IMAGE" == "TRUE" ]; then
	echo "${OBSID} Only proceeding with imaging (no post image)"
	STAGE="image"
elif [ "$POSTIMAGE" == "TRUE" ]; then
	echo "${OBSID} Only proceeding with post-imaging. Checking if images exist."
	image_file=${DATA}/${OBSID}_121-132-XX-image.fits
	if [ -f ${image_file} ]; then
		echo "${OBSID} Images exist, proceeding with post-imaging"
		STAGE="post"
		## Would check if post-image has already been run, but hdf5 wouldn't work because of 121-132 column existing
		#postimage_file=${DATA}/${OBSID}_121-132-image_comp.vot
		#if [ -f ${postimage_file} ]; then
		#	echo "${OBSID} Post-image has run before, overwriting files"
		#	rm ${DATA}/*.vot
	else
		echo "${OBSID} Images do not exist, first running imaging"
		STAGE="full"
	fi
else
	echo "${OBSID} Proceeding with full image and post-image"
	STAGE="full"
fi

bash ./image.sh ${STAGE} ${OBSID} ${ASVOID} ${cal_sols} ${DATA} ${SOFTWARE} ${LOG}
# Imaging/Post-imaging is checked if successful when it's run

# creation of g-map, then save it
# bash ./gmap.sh ${OBSID} 

# Acacia storage
if [[ ("$STAGE" == "full") || ("$STAGE" == "post") ]]; then
	bash ./acacia.sh ${OBSID} ${SCRATCH} ${SOFTWARE}
fi

# Do we want to check when acacia transfer is done? 
# Yes but I don't know how
# For now it just spits out the job id for both transfers and hope for the best I guess

echo "${OBSID} done"
