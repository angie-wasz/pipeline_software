OBSID=$1
LOG=/software/projects/mwasci/awaszewski/compression/compression_log.sqlite

module load giant-squid/2.3.0
module load python/3.11.6

sleep $(echo "scale=3; $RANDOM/32768*10" | bc)

echo "${OBSID} ASVO"

export MWA_ASVO_API_KEY=bafde459-bcaa-4019-84b8-b87667f01e47
export GIANT_SQUID_DELIVERY=scratch

python ../new_system/update_log.py -l ${LOG} -o ${OBSID} --init

# Update log to show processing on ASVO
python ../new_system/update_log.py -l ${LOG} -o ${OBSID} --stage ASVO --status Processing

# Submit job on ASVO
if giant-squid submit-conv ${OBSID} -w -d scratch \
    -p avg_time_res=0.5,avg_freq_res=40,flag_edge_width=40,output=ms; then
	
	#-p avg_time_res=4,avg_freq_res=40,flag_edge_width=40,output=ms; then
	# for calibrator imaging ^

	# for solar imaging
    #-p avg_time_res=0.5,avg_freq_res=160,flag_edge_width=160,output=ms; then

	giant-squid list ${OBSID} > asvo_${OBSID}
	ASVOID=$(grep "Conversion" asvo_${OBSID} | awk '{print $2}')
	rm asvo_${OBSID}

	if [ -z "$ASVOID" ]; then
    	echo "${OBSID} ASVOID does not exist"
	    exit 1
	elif [[ ${#ASVOID} -ne 6 ]]; then
    	echo "${OBSID} ASVOID of incorrect format, must be a 6 digit integer - what was provided: ${ASVOID}"
	    exit 1
	fi
	
	python ../new_system/update_log.py -l ${LOG} -o ${OBSID} --status Complete --asvo ${ASVOID}

else

	echo "${OBSID} Failed to stage on ASVO"
    python ../new_system/update_log.py -l ${LOG} -o ${OBSID} --status Failed
    exit 1

fi

echo "${OBSID} ASVO Complete"
