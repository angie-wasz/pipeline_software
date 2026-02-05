OBSID=1062280936
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/

module load singularity/4.1.0-slurm

container=/software/projects/mwasci/awaszewski/ips_post.img

singularity exec -B $PWD ${container} python3 /software/projects/mwasci/awaszewski/pipeline_scripts/aocal_interp.py -a 4 ${DATA}/${OBSID}_ch129-130_sols.bin ${DATA}/${OBSID}_ch129-130_160.bin
