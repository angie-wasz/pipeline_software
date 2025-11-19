OBSID=$1
DATA=$2

# transfer over the hdf5

# if successful remove the hdf5 file

# tar up the remainder of the directory
FILES = 

# create copy job using template
singularity exec -B $PWD ${container} jinja2 acacia-template.sh acacia-info.yaml --format yaml \
    -D obsid=${OBSID} -D DATA=${DATA} -D FILES=${FILES} \
    --strict -o /software/projects/mwasci/awaszewski/copyouts/${OBSID}-acacia.sh
    
# run