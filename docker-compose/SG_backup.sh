#!/usr/bin/env bash

#
# backup sourcegraph docker-compose configuration
#
# Insturctions: https://docs.sourcegraph.com/admin/install/docker-compose/backup#restoring-sourcegraph-databases-into-an-existing-environment
#
set -e

function _debug()
{
    echo false
}

function _verbose()
{
    echo false
}

#
# _handle_BU_error: remove backup directory on error
#
function _handle_BU_error()
{
    local _rtn=$?
    local _backup_dir=$1

    [[ "${_rtn}" -eq  0 ]] && exit 0
    [[ -d ${_backup_dir} ]] && rm -rf ${_backup_dir}
}


#
# _errAbort: print error message and show stack trace
#
function _errAbort()
{
    set +x
    printf "\n   %-7s%-80s\n\n"  "Error:" "$*"

    # to avoid noise we start with 1 to skip get_stack caller
    local i
    local _stack_size=${#FUNCNAME[@]}

    local _fmt="    %-20s%-30s%-12s\n"
    printf "${_fmt}" Function Source Line
    printf "${_fmt}" -------- ------ ----

    for (( i=1; i<${_stack_size}; i++ ))
    do
        local _func="${FUNCNAME[$i]}"
        [[ ! -n "${_func}" ]] && _func=_MAIN

        local _src="${BASH_SOURCE[$i]}"
        [[ ! -n "${_src}" ]]  && _src=non_file_source

        local _lineno="${BASH_LINENO[(( i - 1 ))]}"

        printf "${_fmt}" ${_func} ${_src} ${_lineno}

    done
    printf "\n"
    exit 1
}

#
# Manage directory where backups are kept
#
function _backup_dir()
{
    local _backup=$(pwd)/Sourcegraph_backups
    echo ${_backup}
}

function _mk_backup_dir()
{
    local _dir=$(_backup_dir)/$(date "+%Y_%m_%d__%H_%M_%S")
    mkdir -p ${_dir} || _errAbort "could not create ${_dir}"
    echo ${_dir}
}


function _prune_backups()
{
    local _max_backups=30
    local _dir=$(_backup_dir)
    local _prune_list=$(ls -tp ${_dir} | \
                        grep '/$' | \
                        tail -n +$(( ++_max_backups )) | \
                        paste -sd' ' -)

    [[ -z ${_prune_list} ]] && return || :

    pushd ${_dir} > /dev/null
    rm -rf ${_prune_list}
    popd > /dev/null
}

#
# When backup completes create a symlink to the current backup directory
#
function _current()
{
   local  _symLink="$(pwd)/CURRENT_SG_BACKUP"
   echo ${_symLink}
}


function _set_current()
{
    [[ $# -ne 1 ]] && _errAbort "number of parms $# should be 1"
    local _dir=$1
    local _current=$(_current)
    #
    # remove and create the symlink
    #
    rm ${_current} &> /dev/null || :
    ln -s ${_dir} ${_current}
    _prune_backups

    [[ "$(_verbose)" = true ]] && echo current backup: ${_dir} || :
}

function _get_current()
{
    local _current=$(_current)
    local _dir=$(readlink ${_current})
    # check if current exist
    [[ -L ${_current} ]] || _errAbort "symlink ${_current} does not exist"
    [[ -d ${_dir}     ]] || _errAbort "directlry ${_dir} does not exist"

    # return current
    echo ${_dir}
}


function _get_container_id()
{
    [[ $# -ne 1 ]] && _errAbort "number of parms $# should be 1"
    local _name=$1
    local _container=$( docker ps --format \
                                '{{.Names}} {{.ID}}' | \
                            grep ${_name} | \
                            cut -f2 -d' ' )

    [[ -z ${_container} ]] && \
        _errAbort "Could not find id for container: ${_name}"

    echo ${_container}
}


function _backup_dbs()
{
    #
    # backup databases
    #
    [[ $# -ne 1 ]] && _errAbort "number of parms $# should be 1"
    local _backup_dir=$1

    #
    # Sourcegraph database
    #
    local _db_user=sg
    local _db=sg
    local _db_host=pgsql
    local _container=$(_get_container_id ${_db_host})

    docker exec -i ${_container} \
        sh -c "pg_dump -C --username=${_db_user} ${_db}" | \
               gzip --stdout > ${_backup_dir}/sg_db_backup.gz || \
            _errAbort backup ${_db_host} failed

    #
    # Code Intel database
    #
    _db_user=sg
    _db=sg
    _db_host=codeintel-db
    _container=$(_get_container_id ${_db_host})

    docker exec -i ${_container} \
        sh -c "pg_dump -C --username=${_db_user} ${_db}" | \
               gzip --stdout > ${_backup_dir}/codeintel_db_backup.gz || \
            _errAbort backup ${_db_host} failed
}


function _backup_docker_compose()
{
    [[ $# -ne 1 ]] && _errAbort "number of parms $# should be 1"
    local _backup_dir=$1

    [[ -f ./docker-compose.yaml ]] && cp ./docker-compose.yaml ${_backup_dir}

    [[ $(id -u) != 0 ]] && echo "backup SSH as id 0, not $(id -u)" && return
    [[ -d ./SSH ]] && tar -cjvpf ${_backup_dir}/SSH.tar.bz2 SSH
}


function _pause_sourcegraph_for_backup()
{
    [[ ! -f ./docker-compose.yaml ]] && _errAbort "no docker-compose.yaml"
    [[ ! -f ./db-only-migrate.docker-compose.yaml ]] && \
        _errAbort "no db-only-migrate.docker-compose.yaml"

    docker-compose down
    docker-compose -f ./db-only-migrate.docker-compose.yaml up -d
}


function _start_sourcegraph()
{
    [[ ! -f ./docker-compose.yaml ]] && _errAbort "no docker-compose.yaml"
    docker-compose -f ./docker-compose.yaml up -d
}


function _backup()
{
    [[ "$(_debug)" = true ]] && set -x || :

    local _backup_dir=$(_mk_backup_dir)
    # 
    # delete the backup directory on error
    #
    trap "_handle_BU_error '${_backup_dir}'" EXIT

    _pause_sourcegraph_for_backup

    _backup_dbs ${_backup_dir}
    _backup_docker_compose ${_backup_dir}

    _set_current ${_backup_dir}

    _start_sourcegraph

    trap - EXIT

    [[ "$(_debug)" = true ]] && set +x || :
}


function _main()
{
    _backup 
}

_main
