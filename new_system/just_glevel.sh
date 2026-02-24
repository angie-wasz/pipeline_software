OBSID=$1
DATA=/scratch/mwasci/awaszewski/pipeline/${OBSID}/
SOFTWARE=/software/projects/mwasci/awaszewski/new_system/
LOG=new_system_test.sqlite

bash ./glevel.sh ${OBSID} ${DATA} ${SOFTWARE} ${LOG}
