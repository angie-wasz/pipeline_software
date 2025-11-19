module load python/3.11.6
module load py-numpy/1.25.2
module load py-astropy/5.1

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
SOFTWARE=/software/projects/mwasci/awaszewski/new_system/

# Data storage
echo "Checking if data directory already exists"
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"
if [ ! -d ${DATA} ]; then
	mkdir ${DATA}
fi

# ASVO staging
./asvo.sh ${OBSID} ${LOG}
ASVOID=$(python read_log.py -l ${LOG} -o ${OBSID} | cut -d "|" -f 2 | awk '{print $2}')

# Calibration
./calibrate.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}

# Check data quality
frac_bad=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 2 | awk '{print $2}')
resid=$(python read_log.py -l ${LOG} -o ${OBSID} --quality | cut -d "|" -f 3 | awk '{print $2}')
echo $frac_bad $resid
if [ ${frac_bad} -gt 0.6 ]; then
	if [ ${resid} -gt 20 ]; then
		echo "Data quality does not meet requirements for further processing"
		exit
	fi
fi

if [ "$CALIBRATE" == "TRUE" ]; then
	echo "Skipping imaging steps"
else
	# Imaging
	./image.sh ${OBSID} ${ASVOID} ${DATA} ${SOFTWARE} ${LOG}
fi

# Acacia storage
# move hdf5 to acacia separately in its own hdf5 directory
# zip up the rest of the observation directory and shove it onto acacia
./acacia.sh ${OBSID} ${DATA}