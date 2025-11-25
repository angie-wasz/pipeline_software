module load singularity/4.1.0-slurm
container="/software/projects/mwasci/awaszewski/ips_post.img"

SOFTWARE=/software/projects/mwasci/awaszewski/new_system/
LOG=new_system_test.sqlite

while read -r OBSID; do
	
	DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
	
	singularity exec -B $PWD ${container} python /software/projects/mwasci/awaszewski/quality_scripts/calc_quality.py -o ${OBSID} -p ${DATA} -l ${SOFTWARE}/${LOG} -s ${SOFTWARE}

done < obsids_2025a_nov.txt
