OBSID=$1
FREQ=$2
START=$3
STOP=$4
DATA="/scratch/mwasci/awaszewski/pipeline/${OBSID}/"

module load hyperdrive/0.6.1
module load python/3.11.6
module load singularity/4.1.0-slurm

container=/software/projects/mwasci/awaszewski/ips_post.img

# EXTRACT CHANNELS
singularity exec -B $PWD ${container} python3 ./select_channels_cal_sol.py -o ${OBSID} --start ${START} --stop ${STOP} --channel ${FREQ} -d ${DATA}

# CONVERT FROM FITS TO BIN
hyperdrive solutions-convert ${DATA}/${OBSID}_ch${FREQ}_sols.fits ${DATA}/${OBSID}_ch${FREQ}_sols.bin

# AVERAGE UP SOLUTIONS
singularity exec -B $PWD ${container} python3 /software/projects/mwasci/awaszewski/pipeline_scripts/aocal_interp.py -a 4 ${DATA}/${OBSID}_ch${FREQ}_sols.bin ${DATA}/${OBSID}_ch${FREQ}_sols_160.bin

# CONVERT FROM BIN TO FITS
hyperdrive solutions-convert ${DATA}/${OBSID}_ch${FREQ}_sols_160.bin ${DATA}/${OBSID}_ch${FREQ}_sols_160.fits


##### RUNS ONCE WE HAVE TEMPERATURE ADJUSTED SOLUTIONS #####
# CONVERT FROM FITS TO BIN
#hyperdrive solutions-convert ${DATA}/cal_sol_ch${FREQ}_sols_fine_160.fits ${DATA}/cal_sol_ch${FREQ}_sols_fine_160.bin
