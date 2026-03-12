#!/bin/bash

Help()
{
	echo " "
	echo "-o/--obsids : a list of obsids that are to be processed, \\n separated. Mandatory"
	echo "-n/--num-parallel : the number of jobs to run in parallel. Default is 8. Optional"
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

echo "Workflow Parameters"
echo "OBSIDS 		= ${OBSIDS}"
echo "NUM_PARALLEL 	= ${NUM_PARALLEL}"
echo " "

# Kick off the pipeline
echo "Begin processing"
cat ${OBSIDS} | xargs -P $NUM_PARALLEL -d $'\n' -n 1 bash ./image.sh  
echo "Finished processing"

