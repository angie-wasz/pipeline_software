OBSID=$1
LOG=$2

module load giant-squid/2.3.0

echo "${OBSID} ASVO"

export MWA_ASVO_API_KEY=bafde459-bcaa-4019-84b8-b87667f01e47
export GIANT_SQUID_DELIVERY=scratch

# Update log to show processing on ASVO
python update_log.py -l ${LOG} -o ${OBSID} --stage ASVO --status Processing

# Submit job on ASVO
if giant-squid submit-conv ${OBSID} -w -d scratch \
    -p avg_time_res=0.5,avg_freq_res=160,flag_edge_width=160,output=ms; then

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
	
    python update_log.py -l ${LOG} -o ${OBSID} --status Complete --asvo ${ASVOID}

else

    echo "${OBSID} Failed to stage on ASVO"
    python update_log.py -l ${LOG} -o ${OBSID} --status Failed
    exit 1

fi

echo "${OBSID} ASVO Complete"