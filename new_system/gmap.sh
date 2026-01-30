OBSID=$1
DATA=$2
SOFTWARE=$3
LOG=$4

gleam_container=/software/projects/mwasci/kross/GLEAM-X-pipeline_old/gleamx_container.img
container="/software/projects/mwasci/awaszewski/ips_post.img"
makefile_dir=${SOFTWARE}/Makefile
scripts_dir="/software/projects/mwasci/awaszewski/pipeline_scripts"

module load singularity/4.1.0-slurm

# check that the files required exist
## required files
# obsid_freq-image_comp.vot
# obsid_freq-image_moment2_comp.vot

module load python/3.11.6
comp_file=${DATA}/${OBSID}_121-132-image_comp.vot
if [ -f ${comp_file} ]; then
	echo "${OBSID} Required files exist, continuing with creation of g-map"
	python update_log.py -l ${LOG} -o ${OBSID} --stage g-level --status Running	
else
	echo "${OBSID} Required files for g-map creation do not exist, exitting workflow"
	python update_log.py -l ${LOG} -o ${OBSID} --stage g-level --status Failed
	exit 1
fi
trap 'python ${SOFTWARE}/update_log.py -l ${SOFTWARE}/${LOG} -o ${OBSID} --status Failed' ERR
module unload python/3.11.6

cd ${DATA}

# posinterp working
echo "${OBSID} posinterp"
singularity exec -B $PWD ${container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.posinterp -j 2

echo "${OBSID} calibrator"
make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.cal -j 2

echo "${OBSID} ion"
singularity exec -B $PWD ${gleam_container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.ion -j 2

echo "${OBSID} gleam1"
make OBSID=${OBSID} scripts_dir=${scripts_dir} DATA=${DATA} -f ${makefile_dir}/Makefile.gleam1 -j 2
echo "${OBSID} gleam_nsi"
singularity exec -B $PWD ${gleam_container} make OBSID=${OBSID} scripts_dir=${scripts_dir} -f ${makefile_dir}/Makefile.gleam_nsi -j 2
echo "${OBSID} gleam2"
make OBSID=${OBSID} scripts_dir=${scripts_dir} DATA=${DATA} -f ${makefile_dir}/Makefile.gleam2 -j 2

echo "${OBSID} glevel"
bash ${scripts_dir}/glevel_vot.sh ${OBSID} ${DATA}

## Nevermind, gmap can be made externally
#echo "${OBSID} gmap"
#singularity exec -B $PWD ${container} python ${scripts_dir}/make_gmap.py -o ${OBSID} -d ${DATA}

module load python 3.11.6
python ${SOFTWARE}/update_log.py -l ${SOFTWARE}/${LOG} -o ${OBSID} --status Complete
echo "${OBSID} g-level calculated"
