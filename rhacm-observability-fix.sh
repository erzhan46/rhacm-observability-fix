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
if ! (return 0 2> /dev/null); then
    # A better class of script...
    set -o errexit      # Exit on most errors (see the manual)
    set -o nounset      # Disallow expansion of unset variables
    set -o pipefail     # Use last non-zero exit code in a pipeline
fi

# Enable errtrace or the error trap handler will not work as expected
set -o errtrace         # Ensure the error trap handler is inherited

# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
# NOTE: The convention used in this script for exit codes is:
#       0: Normal exit
#       1: Abnormal exit due to external error
#       2: Abnormal exit due to script error
function script_exit() {
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
	-u mcm_user		MCM Cluster username
	-p mcm_pwd		MCM Cluster password
	-c mgd_api		Managed Cluster API
	-d mgd_ns		Managed Cluster namespace for observability addon (usually open-cluster-management-addon-observability)
	-e mgd_user		Managed Cluster username
	-f mgd_pass		Managed Cluster password
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

    MODE="undef"
    MCM_API=""
    MCM_NS=""
    MCM_USER=""
    MCM_PASS=""
    MGD_API=""
    MGD_NS="open-cluster-management-addon-observability"
    MGD_USER=""
    MGD_PASS=""
}

# DESC: Parameter parser for fix option
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_fix_params() {
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
	        MCM_UI="$1"
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
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
    if [[ -z ${MCM_API} ]]; then
        script_exit "MCM Cluster API is not provided" 1
    fi
    if [[ -z ${MCM_NS} ]]; then
        script_exit "MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster is not provided" 1
    fi
    if [[ -z ${MCM_USER} ]]; then
        script_exit "MCM Cluster username is not provided" 1
    fi
    if [[ -z ${MCM_PASS} ]]; then
        script_exit "MCM Cluster password is not provided" 1
    fi
    if [[ -z ${MGD_API} ]]; then
        script_exit "Managed Cluster API is not provided" 1
    fi
    if [[ -z ${MGD_NS} ]]; then
        script_exit "Managed Cluster namespace for observability addon is not provided" 1
    fi
    if [[ -z ${MGD_USER} ]]; then
        script_exit "Managed Cluster username is not provided" 1
    fi
    if [[ -z ${MGD_PASS} ]]; then
        script_exit "Managed Cluster password is not provided" 1
    fi

        -m mcm_api              MCM Cluster API
        -n mcm_ns               MCM Cluster namespace for endpoint-observability-work manifestwork for Managed cluster
        -u mcm_user             MCM Cluster username
        -p mcm_pwd              MCM Cluster password
        -c mgd_api              Managed Cluster API
        -d mgd_ns               Managed Cluster namespace for observability addon (usually open-cluster-management-addon-observability)
        -e mgd_user             Managed Cluster username
        -f mgd_pass             Managed Cluster password


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
                ;;
            restore)
                MODE="restore"
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {

    script_init "$@"
    parse_params "$@"
    #lock_init system
}



# Invoke main with args if not sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2> /dev/null); then
    main "$@"
fi


