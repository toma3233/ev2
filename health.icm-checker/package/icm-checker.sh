#!/bin/bash
set -euo pipefail
# INPUT: REGIONS_TO_CHECK, check all regions if empty

INCIDENTS_FILE='incidents.json'
IGNORE_KEYWORD='IGNORE_IN_RELEASE_GATE'
ICM_CHECKER_ID='icm-checker'
UNKNOWN_REGION='unknown_region'

openssl pkcs12 -in icm.pfx -out client.pem -clcerts -nokeys -passin 'pass:'
openssl pkcs12 -in icm.pfx -out key.pem -nocerts -nodes -passin 'pass:'

REGIONS_TO_CHECK="${REGIONS_TO_CHECK:-}|^${UNKNOWN_REGION}$"
echo "REGIONS_TO_CHECK: ${REGIONS_TO_CHECK}"

teamId="AZURECONTAINERSERVICE\\RP"
incidentType="LiveSite"
filter="OwningTeamId eq '${teamId}' and Severity le 2 and IncidentType eq '${incidentType}' and Status eq 'Active'"
filter="$( echo ${filter} | sed "s/\\\/%5C/g" | sed "s/ /%20/g" | sed "s/\//%2F/g" | sed "s/'/%27/g" )"

statusCode="$(curl -s https://prod.microsofticm.com/api/cert/incidents?\$filter=${filter} \
                   -k --cert client.pem --key key.pem --write-out '%{http_code}' \
                   -o ${INCIDENTS_FILE} \
                   --http1.1 \
                   --connect-timeout 60 \
                   --retry 5 \
                   --retry-delay 0)"
echo "icm response status code: ${statusCode}"
if [[ "${statusCode}" != "200" ]]; then
    exit 1
fi

# icm-checker just uses the "ServiceInstanceId" (a.k.a. "Slice" in IcM portal) field to filter its concerned incidents as there is no better available field which geneva monitor can configure for IcM
TRANSFORM="{id:.Id,title:.Title,keywords:.Keywords,slice:.IncidentLocation.ServiceInstanceId,deployenv:(.IncidentLocation.Environment|ascii_downcase|sub(\" \";\"\";\"g\")),region:(.IncidentLocation.DataCenter // \"${UNKNOWN_REGION}\"|ascii_downcase|sub(\" \";\"\";\"g\"))}"
FILTER_KEYWORD="select( ( .keywords == null ) or ( .keywords | contains(\"${IGNORE_KEYWORD}\") | not ) )"
FILTER_SLICE="select( ( .slice != null ) and ( .slice | contains( \"${ICM_CHECKER_ID}\") ) )"
FILTER_REGION="select( (( .deployenv == null ) or ( .deployenv == \"prod\" )) and (.region| test(\"${REGIONS_TO_CHECK}\")) )"
INCIDENTS=$(jq -r ".value[] | $TRANSFORM | $FILTER_KEYWORD | $FILTER_SLICE | $FILTER_REGION" $INCIDENTS_FILE)

if [[ "${INCIDENTS}" == "" ]]; then
    echo "Blocking incident not found"
else
    echo "Found blocking incidents from previous regions:"
    echo ${INCIDENTS} | jq '"\(.region)|https://portal.microsofticm.com/imp/v3/incidents/details/\(.id)|\(.title)"'
    echo "Note some incidents without region info will be marked as $UNKNOWN_REGION thus blocking all releases, please consider:"
    echo "1. If it is not blocking, adding $IGNORE_KEYWORD to incident 'Keywords'"
    echo "2. If it is due to missing region info, you can manually update incident 'Location->DC/region' to correct region, please also consider updating monitor to generate correct region."
    echo "See detailed TSG: http://aka.ms/aks/release-gate?anchor=start-group-release-gate"
    exit 1
fi
