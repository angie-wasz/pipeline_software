# runs the fit temp for an observation
OBSID=$1
CAL=$2
FREQ=$3
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

# will be working completely out of the obsid directory so copy all cal related stuff into that directory
if [ ! -d ${DATA} ]; then
	echo "${OBSID} Data directory does not exist, check if observation has been calibrated"
	exit 1
fi

# check if cal solution exists for both
if [ ! -s ${DATA}/${OBSID}_ch${FREQ}_sols_160.fits ]; then
	echo "${OBSID} Self-cal calibration solution does not exist, check if observation has been calibrated"
	exit 1
fi

if [ ! -s ${DATA}/${CAL}_ch${FREQ}_sols_160.fits ]; then
	if [ ! -s /scratch/mwasci/awaszewski/pipeline/${CAL}/${CAL}_ch${FREQ}_sols_160.fits ]; then
		echo "${OBSID} Calibrator observation does not exist, check if transferred over correctly"
		exit 1
	else
		cp /scratch/mwasci/awaszewski/pipeline/${CAL}/${CAL}_ch${FREQ}_sols_160.fits ${DATA}/
	fi
fi

# check if metafits exist both for obsid and cal
if [ ! -s ${DATA}/${OBSID}.metafits ]; then
	wget "http://ws.mwatelescope.org/metadata/fits?obs_id=${OBSID}" -qO ${DATA}/${OBSID}.metafits
fi

if [ ! -s ${DATA}/${CAL}.metafits ]; then
	if [ ! -s /scratch/mwasci/awaszewski/pipeline/${CAL}/${CAL}.metafits ]; then
		wget "http://ws.mwatelescope.org/metadata/fits?obs_id=${CAL}" -qO ${DATA}/${CAL}.metafits
	else
		cp /scratch/mwasci/awaszewski/pipeline/${CAL}/${CAL}.metafits ${DATA}/
	fi
fi

# then run python file; fits temp ramp, saves the fits in dataframe, saves new cal solutions
module load singularity/4.1.0-slurm
#container="/software/projects/mwasci/awaszewski/ips_post.img"
container="/software/projects/mwasci/kross/GLEAM-X-pipeline_old/gleamx_container.img"
echo "${OBSID} Fitting temperature ramp and creating new calibration solutions"
singularity exec -B $PWD ${container} python3 fit_temp_phases.py -o ${OBSID} -d ${DATA} -f ${FREQ} --fine_chans 16 --cal_obs ${CAL}
