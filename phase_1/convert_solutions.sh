OBSID=$1
FREQ=$2
TARGET_SOL=$3
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"

module load hyperdrive/0.6.1
module load python/3.11.6
module load singularity/4.1.0-slurm
container=/software/projects/mwasci/awaszewski/ips_post.img

avg_sol=${DATA}/cal_sol_ch${FREQ}_sols_scaled_160.fits

if [ ! -f ${avg_sol} ]; then
	
	echo "INFO: FITS target solution doesn't exist, checking for unaveraged solution"
	unavg_sol=${DATA}/cal_sol_ch${FREQ}_sols_scaled.fits 
	unavg_sol_bin=${DATA}/cal_sol_ch${FREQ}_sols_scaled.bin

	if [ ! -f ${unavg_sol} ]; then

		echo "ERROR: Unaveraged solution does not exist, cannot create target calibration solution"
		exit 1

	else
	
		echo "INFO: Unaveraged solutions found, averaging to target frequency resolution"

		# CONVERT FROM FITS TO BIN
		hyperdrive solutions-convert ${unavg_sol} ${unavg_sol_bin}

		# AVERAGE UP SOLUTIONS
		singularity exec -B $PWD ${container} python3 /software/projects/mwasci/awaszewski/pipeline_scripts/aocal_interp.py -a 4 ${unavg_sol_bin} ${TARGET_SOL}

		echo "COMPLETE: Target solutions created"
	
	fi

else

	echo "INFO: Converting FITS target solution to AO format"

	# CONVERT FROM FITS TO BIN
	hyperdrive solutions-convert ${avg_sol} ${TARGET_SOL}

	echo "COMPLETE: Target solutions created"

fi


### OLD ###
#START=$3
#STOP=$4
# EXTRACT CHANNELS
#singularity exec -B $PWD ${container} python3 ./select_channels_cal_sol.py -o ${OBSID} --start ${START} --stop ${STOP} --channel ${FREQ} -d ${DATA}
