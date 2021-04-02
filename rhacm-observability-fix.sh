#!/usr/bin/env bash

# Script to implement a workaround for a RHACM problem observed in IBM Cloud Classoc Openshfit Environments
# Problem is similar to the bug described in https://bugzilla.redhat.com/show_bug.cgi?id=1906542
# This script implements the fix for MCM cluster as well as all other cluster being observed
# Script allows fix to be disabled to allow new clusters to be automatically added tby multiclusterobservability operator

# Script allows fix to be implemented for a specific observed cluster
# It can be run from another script to apply the fix for multiple clusters

# v0.1 Yerzhan Beisembayev ybeisemb@redhat.com



# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# Only enable these shell behaviours if we're not being sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
#if ! (return 0 2> /dev/null); then
    # A better class of script...
#    set -o errexit      # Exit on most errors (see the manual)
#    set -o nounset      # Disallow expansion of unset variables
#    set -o pipefail     # Use last non-zero exit code in a pipeline
#fi

# Enable errtrace or the error trap handler will not work as expected
#set -o errtrace         # Ensure the error trap handler is inherited

# DESC: Script output (currently just echo to stdout)
# ARGS: $1 - Text for output
# OUTS: None
script_output () {
    echo $1
}

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
# NOTE: The convention used in this script for exit codes is:
#       0: Normal exit
#       1: Abnormal exit due to external error
#       2: Abnormal exit due to script error
function script_exit() {
    if [[ -f ${CERT_FILE} ]]; then
        rm -f ${CERT_FILE}
    fi
    if [[ -f ${KUBE_FILE} ]]; then
        rm -f ${KUBE_FILE}
    fi
    if [[ -f ${MFO_FILE} ]]; then
        rm -f ${MFO_FILE}
    fi
    printf '%s\n' "$1"
    exit ${2:-0}
}

# DESC: Usage help
# ARGS: None
# OUTS: None
script_usage () {
  if [[ ${MODE} == "fix" ]]; then
    cat << EOF
Fix parameters:
	-m mcm_api		MCM Cluster API
	-n mcm_ns		MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster
        Authentication:
	   -u mcm_user		MCM Cluster username
	   -p mcm_pwd		MCM Cluster password
        Or:
           -t mcm_token		MCM Cluster token
	-c mgd_api		Managed Cluster API
	-d mgd_ns		Managed Cluster namespace for observability addon (usually open-cluster-management-addon-observability)
        Authentication:
	   -e mgd_user		Managed Cluster username
	   -f mgd_pass		Managed Cluster password
        Or:
           -g mgd_token		Managed Cluster token
EOF
  elif [[ ${MODE} == "restore" ]]; then
    cat << EOF
Restore parameters:
        -m mcm_api              MCM Cluster API
        -n mcm_ns               MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster
        Authentication:
           -u mcm_user          MCM Cluster username
           -p mcm_pwd           MCM Cluster password
        Or:
           -t mcm_token         MCM Cluster token
EOF
  else
    cat << EOF
Usage:
	-h|--help		Displays this help
  	restore			Restore multiclusterobservability
	fix			Enable observability fix
EOF
  fi
}

# DESC: Generic script initialisation
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: $orig_cwd: The current working directory when the script was run
#       $script_path: The full path to the script
#       $script_dir: The directory path of the script
#       $script_name: The file name of the script
#       $script_params: The original parameters provided to the script
function script_init() {
    # Useful paths
    readonly orig_cwd="$PWD"
    readonly script_path="${BASH_SOURCE[1]}"
    readonly script_dir="$(dirname "$script_path")"
    readonly script_name="$(basename "$script_path")"
    readonly script_params="$*"

    oc_cmd=$(which oc 2>&1)
    if [[ $? -ne 0 ]]; then
        if [[ -x "/usr/bin/oc" ]]; then
            oc_cmd="/usr/bin/oc"
        elif [[ -x "/usr/local/bin/oc" ]]; then
            oc_cmd="/usr/local/bin/oc"
        else
            script_exit "OCP command line utility (oc) is not found. Install it before continuing" 1
        fi
    fi

    openssl_cmd=$(which openssl 2>&1)
    if [[ $? -ne 0 ]]; then
        if [[ -x "/usr/bin/openssl" ]]; then
            oc_cmd="/usr/bin/openssl"
        elif [[ -x "/usr/local/bin/openssl" ]]; then
            oc_cmd="/usr/local/bin/openssl"
        else
            script_exit "Openssl command line utility (openssl) is not found. Install it before continuing" 1
        fi
    fi


    MODE="undef"
    MCM_API=""
    MCM_NS=""
    MCM_USER=""
    MCM_PASS=""
    MCM_TOKEN=""
    MGD_API=""
    MGD_NS="open-cluster-management-addon-observability"
    MGD_USER=""
    MGD_PASS=""
    MGD_TOKEN=""

    MCM_CONTEXT=""
    MGD_CONTEXT=""

    CERT_FILE=$(mktemp)
    KUBE_FILE=$(mktemp)
    MFO_FILE=$(mktemp)
}

# DESC: Parameter parser 
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_common_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                script_exit ""
                ;;
            -m)
	        MCM_API="$1"
		shift
		;;
            -n)
	        MCM_NS="$1"
		shift
		;;
            -u)
	        MCM_USER="$1"
		shift
		;;
	    -p)
	        MCM_PASS="$1"
		shift
		;;
	    -t)
	        MCM_TOKEN="$1"
		shift
		;;
	    -c)
	        MGD_API="$1"
		shift
		;;
	    -d)
	        MGD_NS="$1"
		shift
		;;
	    -e)
	        MGD_USER="$1"
		shift
		;;
	    -f)
	        MGD_PASS="$1"
		shift
		;;
	    -g)
	        MGD_TOKEN="$1"
		shift
		;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# DESC: Parameter parser for fix option
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_fix_params() {

    parse_common_params "$@"

    if [[ -z ${MCM_API} ]]; then
        script_usage
        script_exit "MCM Cluster API is not provided" 1
    fi
    if [[ -z ${MCM_NS} ]]; then
        script_usage
        script_exit "MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster is not provided" 1
    fi
    if [[ -z ${MCM_TOKEN} ]] && [[ -z ${MCM_USER} || -z ${MCM_PASS} ]]; then
        script_usage
        script_exit "MCM Cluster authentication is not provided" 1
    fi
    if [[ -z ${MGD_API} ]]; then
        script_usage
        script_exit "Managed Cluster API is not provided" 1
    fi
    if [[ -z ${MGD_NS} ]]; then
        script_usage
        script_exit "Managed Cluster namespace for observability addon is not provided" 1
    fi
    if [[ -z ${MGD_TOKEN} ]] && [[ -z ${MGD_USER} || -z ${MGD_PASS} ]]; then
        script_usage
        script_exit "Managed Cluster authentication is not provided" 1
    fi
}

# DESC: Parameter parser for restore option
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_restore_params() {

    parse_common_params "$@"

    if [[ -z ${MCM_API} ]]; then
        script_usage
        script_exit "MCM Cluster API is not provided" 1
    fi
    if [[ -z ${MCM_NS} ]]; then
        script_usage
        script_exit "MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster is not provided" 1
    fi
    if [[ -z ${MCM_TOKEN} ]] && [[ -z ${MCM_USER} || -z ${MCM_PASS} ]]; then
        script_usage
        script_exit "MCM Cluster authentication is not provided" 1
    fi
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    if [[ $# -eq 0 ]]; then
      script_usage
      script_exit ""
    fi
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                script_exit ""
                ;;
            fix)
                MODE="fix"
                parse_fix_params "$@"
                break
                ;;
            restore)
                MODE="restore"
                parse_restore_params "$@"
                break
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# DESC: OCP Get Context
# ARGS: None
# OUTS: Context
function ocp_get_context() {
    local c_output=""
    local c_result=0

    c_output=$(${oc_cmd} config current-context 2>&1)
    c_result=$?
    if [[ ${c_result} -ne 0 ]]; then
        script_exit "Attempt to get current context from OCP kubeconfig failed: ${c_output}" ${c_result}
    fi
    echo ${c_output}
}

# DESC: OCP Set Context
# ARGS: Context
# OUTS: None
function ocp_set_context() {
    local c_contex=$1
    local c_output=""
    local c_result=0

    c_output=$(${oc_cmd} config use-context ${c_contex} 2>&1)
    c_result=$?
    if [[ ${c_result} -ne 0 ]]; then
        script_exit "Attempt to set current context(${c_contex}) failed: ${c_output}" ${c_result}
    fi
}


# DESC: OCP Login
# ARGS: $1 - Cluster API endpoint
# $2 - Login token or username
# $3 - Should not be provided if second parameter is token, otherwise - password
# OUTS: None if successful, Error text otherwise
# EXIT: 0 - success, 1 - error
function ocp_login() {
    local c_output=""
    local c_result=0

    if [[ -z $3 ]]; then
        c_output=$(${oc_cmd} login --token=$2 --server=$1 2>&1)
    else
        c_output=$(${oc_cmd} login --username=$2 --password=$3 --server=$1 2>&1)
    fi
    c_result=$?
    if [[ ${c_result} -ne 0 ]]; then
        echo "Attempt to login to OCP Cluster failed: ${c_output}"
    fi
    exit ${c_result}
}

# DESC: Login to all clusters
# ARGS: None
# OUTS: None
function login_all() {
    local c_output=""
    local c_result=9

    # Login to MCM cluster
    if [[ -n ${MCM_TOKEN} ]]; then
        script_output "Attempting to login to MCM cluster using token provided"
        c_output=$(ocp_login ${MCM_API} ${MCM_TOKEN})
        c_result=$?
    fi
    if [[ ${c_result} -ne 0 && -n ${MCM_USER} && -n ${MCM_USER} ]]; then
        script_output "Attempting to login to MCM cluster using username and password provided"
        c_output=$(ocp_login ${MCM_API} ${MCM_USER} ${MCM_PASS})
        c_result=$?
    fi
    if [[ ${c_result} -ne 0 ]]; then
        script_exit "${c_output}" ${c_result}
    fi
    MCM_CONTEXT=$(ocp_get_context)

    # Login to Managed Cluster
    if [[ ${MCM_API} == ${MGD_API} ]]; then
        # All activities to be done on the same cluster - Reuse connection
        script_output "Reusing MCM connection for Managed cluster activities"
        MGD_CONTEXT=${MCM_CONTEXT}
    else
        c_result=9
        if [[ -n ${MGD_TOKEN} ]]; then
            script_output "Attempting to login to MGD cluster using token provided"
            c_output=$(ocp_login ${MGD_API} ${MGD_TOKEN})
            c_result=$?
        fi
        if [[ ${c_result} -ne 0 && -n ${MGD_USER} && -n ${MGD_USER} ]]; then
            script_output "Attempting to login to MGD cluster using username and password provided"
            c_output=$(ocp_login ${MGD_API} ${MGD_USER} ${MGD_PASS})
            c_result=$?
        fi
        if [[ ${c_result} -ne 0 ]]; then
            script_exit "${c_output}" ${c_result}
        fi
        MGD_CONTEXT=$(ocp_get_context)
    fi
}

# DESC: Pause MCO operation
# ARGS: None
# OUTS: None
function pause_mco() {
    local c_output=""
    local c_result=9

    if [[ -z $1 ]]; then
        script_exit "pause_mco(): argument is not provided" 2
    fi

    # Pause/unpause MCO processing
    ocp_set_context ${MCM_CONTEXT}
    if [[ $1 == "true" ]]; then
        c_output=$(${oc_cmd} patch multiclusterobservability/observability --type=merge -p '{"metadata":{"annotations":{"mco-pause":"true"}}}')
    elif [[ $1 == "false" ]]; then
        c_output=$(${oc_cmd} patch multiclusterobservability/observability --type=merge -p '{"metadata":{"annotations":{"mco-pause":"false"}}}')
    else
        script_exit "pause_mco(): Incorrect argument is not provided: $1" 2
    fi
    c_result=$?
    if [[ ${c_result} -ne 0 ]]; then
        script_exit "Failure: ${c_output}" ${c_result}
    fi
}


# DESC: Restore MCO operation
# ARGS: None
# OUTS: None
function restore_mco() {

    # Restore MCO processing
    script_output "Attempting to restore MCO operation on MCM cluster"
    pause_mco false
}

# DESC: Retrieve the MCM API endpoint certificate
# ARGS: None
# OUTS: None
function get_cert() {
    local c_output=""
    local c_result=9
    local c_cert=""

    local c_api=$1
    local c_host=${c_api#https://}
    local c_name=${c_host%\:[0-9]*}

    if [[ -z $c_host || -z $c_name ]]; then
        script_exit "get_cert(): Error parsing api name: $1" 2
    fi

    c_output=$(true | ${openssl_cmd} s_client -servername ${c_name} -connect ${c_host} >${CERT_FILE} 2>&1)
    c_result=$?

    if [[ ${c_result} -ne 0 ]]; then
        script_exit "get_cert(): Openssl failed to retrieve the data: ${c_output}" ${c_result}
    fi 

    sed -i -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' ${CERT_FILE}
    c_cert=$(cat ${CERT_FILE})

    if [[ -z ${c_cert} ]]; then
        script_exit "get_cert(): Failed to parse the data: ${c_output}" 2
    fi 
}

# DESC: Patch manifestwork
# ARGS: None
# OUTS: None
function patch_mfo() {
    local c_output=""
    local c_result=9
    local c_cert=""

    local c_api=$1
    local c_host=${c_api#https://}
    local c_name=${c_host%\:[0-9]*}

    if [[ -z $c_host || -z $c_name ]]; then
        script_exit "get_cert(): Error parsing api name: $1" 2
    fi

    c_output=$(true | ${openssl_cmd} s_client -servername ${c_name} -connect ${c_host} >${CERT_FILE} 2>&1)
    c_result=$?

    if [[ ${c_result} -ne 0 ]]; then
        script_exit "get_cert(): Openssl failed to retrieve the data: ${c_output}" ${c_result}
    fi

    sed -i -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' ${CERT_FILE}
    c_cert=$(cat ${CERT_FILE})

    if [[ -z ${c_cert} ]]; then
        script_exit "get_cert(): Failed to parse the data: ${c_output}" 2
    fi
}


# DESC: Disable (pause) MCO operation and fix connectivity for a specific endpoint observer
# ARGS: None
# OUTS: None
function fix_mco() {
    local c_output=""
    local c_result=9

    # Restore MCO processing
    script_output "Attempting to retrieve MCM API endpoint certificate"
    get_cert ${MCM_API}

    # Pause MCO processing
    script_output "Attempting to pause MCO operation on MCM cluster"
    pause_mco true

    # Patch manifestwork
    script_output "Attempting to patch manifestwork on MCM cluster"
    patch_mfo

}



# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
#    trap script_trap_err ERR
#    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"

    # Log in to MCM Cluster
    login_all

    # Restore mode
    if [[ ${MODE} == "restore" ]]; then
       restore_mco
    fi

    if [[ ${MODE} == "fix" ]]; then
       fix_mco
    fi

    script_exit "Command completed successfully" 0
}



# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2> /dev/null); then
    main "$@"
fi


