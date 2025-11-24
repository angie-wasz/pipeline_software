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
# first check if it already exists
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

	if [[ ("$stage" == "Calibration" && "$status" == "Complete") || ("$stage" == "Imaging" || "$stage" == "Post-Imaging") ]]; then
		echo "${OBSID} has already been through calibration. Checking if calibration solutions are available."
		cal_sols=${DATA}/${OBSID}_sols.fits
		if [ -f ${cal_sols} ]; then
			echo "${OBSID} calibration solutions are available. Skipping calibration"
			CAL_SKIP=TRUE
		fi
	fi

	if [[ $ASVOID -ne 0 ]]; then
		echo "${OBSID} has already been downloaded from ASVO. Checking if measurement set is available."
		ms=/scratch/mwasci/asvo/${ASVOID}/${OBSID}_ch121-132.ms/
		echo ${ms}
		if [ -d ${ms} ]; then
			echo "${OBSID} measurement set available. Skipping ASVO download"
			ASVO_SKIP=TRUE
		fi
	fi
fi

# ASVO staging
if [ $ASVO_SKIP = FALSE ]; then
	#./asvo.sh ${OBSID} ${LOG}
	echo "ASVO"
	ASVOID=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')
fi

# Calibration
if [ $CAL_SKIP = FALSE ]; then
	echo "Calibration"
	#./calibrate.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}
fi

# Check data quality
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
# do i check if observation has already been imaged? if it has I probably wouldn't be running the pipeline on it
echo "Imaging"
bash ./image.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}

# Acacia storage
# move hdf5 to acacia separately in its own hdf5 directory
# zip up the rest of the observation directory and shove it onto acacia
#./acacia.sh ${OBSID} ${DATA}

# Do we want to check when acacia transfer is done? 
# Yes but I don't know how

echo "${OBSID} done"
