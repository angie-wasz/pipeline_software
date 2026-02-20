OBSID=$1
START=$2
STOP=$3
FREQ=$4
DATA='/scratch/mwasci/awaszewski/pipeline/${OBSID}'

module load hyperdrive/0.6.1
module load python/3.11.6

# run python script to cut down the solutions file to correct channels
python ./select_channels_cal_sol.py -o ${OBSID} --start ${START} --stop ${STOP} --channel ${FREQ} -d ${DATA}

# convert into a .bin for apply solutions
fits_file=${DATA}/${OBSID}_ch${FREQ}_sols.fits
bin_file=${DATA}/${OBSID}_ch${FREQ}.bin

hyperdrive solutions-convert ${fits_file} ${bin_file}
