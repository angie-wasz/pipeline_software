OBSID=$1
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

container="/software/projects/mwasci/awaszewski/ips_post.img"

module load singularity/4.1.0-slurm

cd ${DATA}

singularity exec -B $PWD ${container} python3 /software/projects/mwasci/awaszewski/pipeline_scripts/make_beam_only.py ${OBSID}.hdf5 ${OBSID}_beam.hdf5 -f 121-132
