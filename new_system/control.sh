#!/bin/bash

Help()
{
	echo " "
	echo "-o/--obsids : a list of obsids that are to be processed, \\n separated. Mandatory"
	echo "-n/--num-parallel : the number of jobs to run in parallel. Default is 8. Optional"
	echo "-s/--safemode : if included, then data is not deleted from /scratch/asvo. CURRENTLY NOT IMPLEMENTED! Optional but recommended"
	echo "-c/--calibrate : if included, then will only run calibration portion of pipeline"
	echo "--skip-fail-check : if included then it won't check if an observation has failed in the past (which by default is skipped)"
	echo " "
}
while getopts ":h" option; do
	case $option in
		h)
			Help
			exit;;
	esac
done

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
	case $1 in
		-o|--obsids)
			OBSIDS="$2"
			shift
			shift;;
		-n|--num-parallel)
			NUM_PARALLEL="$2"
			shift
			shift;;
		-s|--safemode)
			SAFEMODE=TRUE
			shift;;
		-c|--calibrate)
			CALIBRATE=TRUE
			shift;;
		--skip-fail-check)
			SKIP_FAIL_CHECK=TRUE
			shift;;
		-*|--*)
			echo "Unknown option $1"
			exit 1;;
		*)
			POSITIONAL_ARGS+=("$1")
			shift;;
	esac
done
set -- "${POSITIONAL_ARGS[@]}"

# obsid list must be included
# also need to check if the file exists
if [[ -z ${OBSIDS} ]]; then
	echo "A list of obsids must be provided"
	exit 1
elif [ ! -f ${OBSIDS} ]; then
	echo "Obsid list provided does not exist"
	exit 1
fi

# setting defaults
if [[ -z ${NUM_PARALLEL+x} ]]; then
	NUM_PARALLEL=8
fi
if [[ -z ${SAFEMODE+x} ]]; then
	SAFEMODE=FALSE
	echo "Safemode is turned off. Are you sure?"
	secs=10
	while [ $secs -gt 0 ]; do
		echo -ne "$secs\033[0K\r"
		sleep 1
		: $((secs--))
	done
fi
if [[ -z ${CALIBRATE+x} ]]; then
	CALIBRATE=FALSE
fi
if [[ -z ${SKIP_FAIL_CHECK+x} ]]; then
	SKIP_FAIL_CHECK=FALSE
fi

echo "Workflow Parameters"
echo "OBSIDS 		= ${OBSIDS}"
echo "NUM_PARALLEL 	= ${NUM_PARALLEL}"
echo "SAFEMODE	= ${SAFEMODE}" 
echo "CALIBRATE = ${CALIBRATE}"
echo "SKIP_FAIL_CHECK = ${SKIP_FAIL_CHECK}"
echo " "

# Log must be separately initialised
LOG=new_system_test.sqlite

# Kick off the pipeline
echo "Begin processing"
cat ${OBSIDS} | xargs -P $NUM_PARALLEL -d $'\n' -n 1 bash ./run.sh --safemode ${SAFEMODE} --calibrate ${CALIBRATE} --skip-fail-check ${SKIP_FAIL_CHECK} -l ${LOG} -o 
echo "Finished processing"

