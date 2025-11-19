#!/bin/bash -l

#SBATCH --account=mwasci
#SBATCH --partition=copy
#SBATCH --job-name={{obsid}}-ips-acacia
#SBATCH --output={{obsid}}-acacia.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=8G
#SBATCH --time=12:00:00
#SBATCH --export=NONE
#SBATCH --signal=B:INT@60

trap 'echo "Requeuing job"; scontrol requeue $SLURM_JOB_ID;' INT

module load rclone/1.68.1

profileName={{profile}}
bucketName={{bucket}}
prefixPath={{path}}
fullPathInAcacia="${profileName}:${bucketName}/${prefixPath}"

workingDir={{DATA}}
tarFileNames={{FILES}}


# YOU SHOULD NOT NEED TO EDIT ANYTHING BELOW THIS LINE
#-----------------------------------------------------

#Check if Acacia definitions make sense, and if you can transfer objects into the desired bucket
echo "Checking that the profile exists"
rclone config show | grep "${profileName}" > /dev/null; exitcode=$?
if [ $exitcode -ne 0 ]; then
   echo "The given profileName=$profileName seems not to exist in the user configuration of rclone"
   echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
   exit 1
fi
echo "Checking the bucket exists and that you have writing access"
rclone lsd "${profileName}:${bucketName}" > /dev/null; exitcode=$? #Note the colon(:) when using rclone
if [ $exitcode -ne 0 ]; then
   echo "The bucket intended to receive the data does not exist: ${profileName}:${bucketName}"
   echo "Trying to create it"
   rclone mkdir "${profileName}:${bucketName}"; exitcode=$?
   if [ $exitcode -ne 0 ]; then
      echo "Creation of bucket failed"
      echo "The bucket name or the profile name may be wrong: ${profileName}:${bucketName}"
      echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
      exit 1
   fi
fi
echo "Checking if a test file can be trasferred into the desired full path in Acacia"
testFile=test_file_${SLURM_JOBID}.txt
echo "File for test" > "${testFile}"
rclone copy "${testFile}" "${fullPathInAcacia}/"; exitcode=$?
if [ $exitcode -ne 0 ]; then
   echo "The test file $testFile cannot be transferred into ${fullPathInAcacia}"
   echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
   exit 1
fi
echo "Checking if the test file can be listed in Acacia"
listResult=$(rclone lsl "${fullPathInAcacia}/${testFile}")
if [ -z "$listResult" ]; then
   echo "Problems occurred during the listing of the test file ${testFile} in ${fullPathInAcacia}"
   echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
   exit 1
fi
echo "Removing test file from Acacia"
rclone delete "${fullPathInAcacia}/${testFile}"; exitcode=$?
if [ $exitcode -ne 0 ]; then
   echo "The test file $testFile cannot be removed from ${fullPathInAcacia}"
   echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
   exit 1
fi
rm $testFile
 
#----------------
#Defining the working dir and cd into it
echo "Checking that the working directory exists"
if ! [ -d $workingDir ]; then
   echo "The working directory $workingDir does not exist"
   echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
   exit 1
else
   cd $workingDir
fi
 
#-----------------
#Perform the transfer of the tar file into the working directory and check for the transfer
echo "Performing the transfer ... "
for tarFile in "${tarFileNames[@]}";do
    echo "rclone sync -P --transfers ${SLURM_CPUS_PER_TASK} --checkers ${SLURM_CPUS_PER_TASK} ${workingDir}/${tarFile} ${fullPathInAcacia}/ &"
    srun rclone sync -P --transfers ${SLURM_CPUS_PER_TASK} --checkers ${SLURM_CPUS_PER_TASK} "${workingDir}/${tarFile}" "${fullPathInAcacia}/" &
    wait $!; exitcode=$?
    if [ $exitcode -ne 0 ]; then
       echo "Problems occurred during the transfer of file ${tarFile}"
       echo "Check that the file exists in ${workingDir}"
       echo "And that nothing is wrong with the fullPathInAcacia: ${fullPathInAcacia}/"
       echo "Exiting the script with non-zero code in order to inform job dependencies not to continue."
       exit 1
    else
       echo "Final place in Acacia: ${fullPathInAcacia}/${tarFile}"
    fi
done 
#---------------
# Final checks ...
 
#---------------
#Successfully finished
echo "Done"
exit 0