OBSID=$1
DATA=$2
SOFTWARE=$3
LOG=$4

container="/software/projects/mwasci/awaszewski/ips_post.img"
makefile_dir=${SOFTWARE}/Makefile
scripts_dir="/software/projects/mwasci/awaszewski/pipeline_scripts"

module load python/3.11.6
module load singularity/4.1.0-slurm

# check that the files required exist
## required files
# obsid_freq-image_comp.vot
# obsid_freq-image_moment2_comp.vot

comp_file=${DATA}/${OBSID}_121-132-image_comp.vot
if [ -f ${comp_file} ]; then
	echo "${OBSID} Required files exist, continuing with creation of g-map"
	python update_log.py -l ${LOG} -o ${OBSID} --stage G-map --status Running	
else
	echo "${OBSID} Required files for g-map creation do not exist, exitting workflow"
	python update_log.py -l ${LOG} -o ${OBSID} --stage G-map --status Failed
	exit 1
fi
module unload python/3.11.6

cd ${DATA}

singularity exec -B $PWD ${container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.posinterp -j 2

singularity exec -B $PWD ${container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.ion -j 2

singularity exec -B $PWD ${container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.gleam -j 2

# calculate g-levels
### might need to change it to not run on topcat
bash ${scripts_dir}/glevel_vot.sh ${OBSID} ${DATA}

# create g-map
singularity exec -B $PWD ${container} python ${scripts_dir}/make_gmap.py -o ${OBSID} -d ${DATA}

module load python 3.11.6
python update_log.py -l ${LOG} -o ${OBSID} --status Complete
echo "${OBSID} G-map created"
