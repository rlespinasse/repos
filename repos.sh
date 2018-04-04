#!/usr/bin/env bash
set -euo pipefail

#/ Usage: repos.sh [--init|--help]
#/ Description: Synchronize your repositories
#/ Examples:
#/   repos.sh
#/   repos.sh --init
#/ Options:
#/   --help: Display this help message
#/   --init: Initialize your repositories
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

readonly LOG_FILE="/tmp/$(basename "$0").log"
info()     { echo "[INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning()  { echo "[WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()    { echo "[ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()    { echo "[FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

readonly STATUS_BASENAME="/tmp/$(basename "$0")-$$.status"
readonly STATUS_DONE="████████████████████"
readonly STATUS_TODO="░░░░░░░░░░░░░░░░░░░░"
status_log() {
    taskId=$1
    repositoryName=$2
    message=$3
    percent=$4

    lendone=$((percent / 5))
    lentodo=20-$lendone
    print_percent=$(printf %3d "${percent}")
    
    printf "| %-29s | %-166s\\n" "${STATUS_DONE:0:$lendone}${STATUS_TODO:0:$lentodo} | $print_percent %" "${repositoryName} (${message})" > "${STATUS_BASENAME}.${taskId}.tmp"
    mv "${STATUS_BASENAME}.${taskId}.tmp" "${STATUS_BASENAME}.${taskId}"
}

status_printer() { 
  # First time in the loop is special insofar we don't have to 
  #  scroll up to overwrite previous output. 
  TASK_PIDS=$1
  FIRST_TIME=1 
  while true ; do 
    # If not first time, scroll up as many lines as we have 
    #  regular background tasks to overwrite previous output. 
    test $FIRST_TIME -eq 0 && for PID in $TASK_PIDS ; do 
      echo -ne '\033M' # scrol up one line using ANSI/VT100 cursor control sequences 
    done 
    FIRST_TIME=0
    TASK_ID=0
    for PID in $TASK_PIDS ; do 
      # If status file exists print first line 
      test -f "${STATUS_BASENAME}.${TASK_ID}" && head -1 "${STATUS_BASENAME}.${TASK_ID}" || echo "waiting..." 
      TASK_ID=`expr $TASK_ID + 1` # using expr for portability :) 
    done 
    test -f "${STATUS_BASENAME}.done" && return
    sleep 1 # seconds to wait between updates 
  done 
} 

cleanup() {
    rm -f "${STATUS_BASENAME}."* 
    tput cnorm
}

initRepository() {
    repo=$1
    site=$2
    name=$3
    root_folder=$4

    info "Clone ${site}/${name}/${repo}"

    mkdir -p "${root_folder}/repos/${site}/${name}"
    git clone "git@${site}:${name}/${repo}.git" "${root_folder}/${site}/${name}/${repo}"
}

initRepositories() {
    info "Initialize all the repositories"

    root_folder=$1

    sites=$(jq -r '.sites | map([.owner, .site, .api, .type, .token] | join(",")) | join("\n")' < "${HOME}/.repos.json")
    while IFS="," read -r name site api nametype token;
    do
        all_repos=$(curl -s "${api}/${nametype}/${name}/repos?access_token=${token}&per_page=100" | jq -r ".[].name" | sort)
        
        while read -r repo; 
        do
            mkdir -p "${root_folder}/${site}/${name}"
            if [ ! -d "${root_folder}/${site}/${name}/${repo}" ];
            then
                initRepository "$repo" "${site}" "${name}" "${root_folder}"
            fi
        done < <(echo "${all_repos}")
    done < <(echo "${sites}")

    exit 0
}

syncRepository() {
    repo=$1
    site=$2
    name=$3
    root_folder=$4
    TASK_ID=$5

    REPODIR="${root_folder}/${site}/${name}/${repo}"
    repofull="${site}/${name}/${repo}"

    status_log "${TASK_ID}" "$repofull" "fetch" "0"
    git -C "${REPODIR}" fetch origin -q --prune

    current_branch=$(git -C "${REPODIR}" rev-parse --abbrev-ref HEAD)

    status_log "${TASK_ID}" "$repofull" "pull origin/${current_branch}" "30"
    git -C "${REPODIR}" add -A .
    stash_result=$(git -C "${REPODIR}" stash)
    git -C "${REPODIR}" pull -q origin "${current_branch}" >/dev/null 2>&1
    pull_result=$?

    if [ $pull_result -gt 0 ]; then

        status_log "${TASK_ID}" "$repofull" "checkout + pull master" "60"
        git -C "${REPODIR}" checkout -q master
        git -C "${REPODIR}" pull -q origin master

        status_log "${TASK_ID}" "$repofull" "delete ${current_branch}" "70"
        git -C "${REPODIR}" branch -q -D "${current_branch}"
    elif [ "No local changes to save" != "$stash_result" ]; then

        status_log "${TASK_ID}" "$repofull" "unstash changes" "60"
        git -C "${REPODIR}" stash pop -q
    fi

    status_log "${TASK_ID}" "$repofull" "prune" "80"
    git -C "${REPODIR}" prune >/dev/null 2>&1

    status_log "${TASK_ID}" "$repofull" "gc" "90"
    git -C "${REPODIR}" gc -q

    if [ "No local changes to save" != "$stash_result" ]; then
        if [ $pull_result -gt 0 ]; then
            status_log "${TASK_ID}" "$repofull" "complete, check your stashed changes" "100"
        else
            status_log "${TASK_ID}" "$repofull" "complete, unstash ok" "100"
        fi
    else
        status_log "${TASK_ID}" "$repofull" "complete" "100"
    fi
}

syncRepositories() {
    info "Synchronize all the repositories"

    root_folder=$1

    tput civis
    RESULT=0
    count=0
    TASK_PIDS=""

    sites=$(jq -r '.sites | map([.owner, .site, .api, .type, .token] | join(",")) | join("\n")' < "${HOME}/.repos.json")
    
    while IFS="," read -r name site api nametype token;
    do
        all_repos=$(curl -s "${api}/${nametype}/${name}/repos?access_token=${token}&per_page=100" | jq -r ".[].name" | sort)
        while read -r repo; 
        do
            mkdir -p "${root_folder}/${site}/${name}"
            if [ -d "${root_folder}/${site}/${name}/${repo}" ];
            then
                syncRepository "$repo" "${site}" "${name}" "${root_folder}" "$count" &
                TASK_PIDS="$TASK_PIDS $!"
                count=$((count+1))
            fi
        done < <(echo "${all_repos}")
    done < <(echo "${sites}")

    status_printer "${TASK_PIDS}" & PRINTER_PID=$!     
    for PID in $TASK_PIDS; do
        wait "$PID" || let "RESULT=1"
    done

    touch "${STATUS_BASENAME}.done"
    wait $PRINTER_PID
    sleep 1
    tput cnorm
    exit ${RESULT}
}

checkConfiguration() {
    if [ ! -f "${HOME}/.repos.json" ];
    then
        echo "Missing ${HOME}/.repos.json"
        cat > "${HOME}/.repos.json" << EOF
{
    "root_folder": "~/sources",
    "sites": [
        {
            "site": "github.myentreprise.com",
            "api": "https://github.myentreprise.com/api/v3",
            "owner": "EntrepriseOrganization",
            "type": "orgs",
            "token": "YOUR API TOKEN from github.myentreprise.com"
        },
        {
            "site": "github.com",
            "api": "https://api.github.com",
            "owner": "YOUR LOGIN",
            "type": "users",
            "token": "YOUR API TOKEN from github.com"
        }
    ]
}
EOF
        vim ~/.repos.json
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    trap cleanup EXIT

    checkConfiguration

    root_folder=$(jq -r '.root_folder' < "${HOME}/.repos.json")
    root_folder="${root_folder/#\~/$HOME}"
    expr "$*" : ".*--init" > /dev/null && initRepositories "${root_folder}"
    syncRepositories "${root_folder}"
fi
