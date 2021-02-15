#!/usr/bin/env bash

# interactive run example:
#   NOTE Run it in a tmux window to keep it running after logout
#   /PATH/TO/rsync_script.sh -s /PATH/TO/SRC -d /PATH/TO/DST 2>&1 | tee -a /PATH/TO/rsync_script.log

# /etc/crontab example:
#   0  */8  *  *  *   root   /PATH/TO/rsync_script.sh -y -s /PATH/TO/SRC -d /PATH/TO/DST &>> "/PATH/TO/rsync_script-$(date +%Y%m%d_%H%M%S).log"

# to check logs:
#   cd /PATH/TO/LOGS
#   ls -ltr | awk '{print $9}' | xargs -I % bash -c 'echo % && head -n 1 % && tail -n 5 %'

set -u             # treat unset variables as an error, and immediately exit
set -e             # if a command fails, the whole script exit
set -o pipefail    # causes a pipeline to produce a failure return code if any command exits with error
shopt -s failglob  # causes globs that don't get expanded to cause errors

usage() {
    echo "$scriptname - INFO - Usage:"
    echo
    echo "$0 [-t] [-y] -s <source_dir> -d <destination_dir>"
    echo "    -t : dry run"
    echo "    -y : assume yes (skip confirmation prompt)"
    echo "    -s : source directory       NOTE Must be an absolute path; example: /path/to/src"
    echo "    -d : destination directory  NOTE Must be an absolute path; example: /path/to/dst"
    echo
}

exiting() {
    end_time="$(date +%s)"
    echo "$scriptname - INFO - Script ending at: $(date --rfc-3339=s -d @$end_time)"

    duration="$((end_time - start_time))"
    printf "$scriptname - INFO - Script duration: %02dh:%02dm:%02ds\n" "$((duration/3600))" "$((duration%3600/60))" "$((duration%60))"
    echo "-----------------------------------------------------------------------"

    exit "$1"
}

rsync_cmd() {
    # NOTE
    #  --verbose                 increase verbosity; include changes only
    #  --itemize-changes         output a change-summary for all updates            (see: http://andreafrancia.blogspot.com/2010/03/as-you-may-know-rsyncs-delete-options.html)
    #  -hh                       numbers in a human-readable format; use 2^ powers  (see: https://askubuntu.com/questions/909832/file-size-is-different-in-windows-and-ubuntu)
    #  --progress                show progress
    #  --archive                 archive mode; equals to:
    #    --recursive               recurse into directories
    #    --links                   copy symlinks as symlinks
    #    --perms                   preserve permissions
    #    --times                   preserve modification times
    #    --group                   preserve group
    #    --owner                   preserve owner
    #    --devices --specials      preserve special files
    #  --sparse                  handle sparse files efficiently                    (see: https://serverfault.com/questions/749122/copying-data-over-with-rsync-causes-size-discrepancies)
    #  --hard-links              look for hard-linked files in the source and link together the corresponding files on the destination
    #  --acls                    preserve ACLs                                      (see: https://www.redhat.com/sysadmin/linux-access-control-lists)
    #  --xattrs                  preserve extended attributes                       (for copying SELinux values)
    #  --whole-file              copy files whole w/o delta-xfer algorithm          (for faster transfer in local)
    #  --delete                  delete extraneous files from destination dirs
    #  --dry-run                 perform a trial run with no changes made

    if [ "$1" -eq 1 ]; then
        echo "$scriptname - INFO - Executing rsync as **DRY RUN**"
        # NOTE Param --sparse not used
        rsync --verbose --itemize-changes -hh --progress \
            --archive --hard-links --acls --xattrs \
            --whole-file \
            --delete \
            --dry-run \
            "${source_dir}/" "${destination_dir}/"
    else
        # NOTE Param --sparse not used
        rsync --verbose --itemize-changes -hh --progress \
            --archive --hard-links --acls --xattrs \
            --whole-file \
            --delete \
            "${source_dir}/" "${destination_dir}/"
    fi
}

scriptname="[$(basename $0 .sh)]"
start_time="$(date +%s)"
echo "$scriptname - INFO - Script starting at: $(date --rfc-3339=s -d @$start_time)"

if [ $# -eq 0 ]; then
    echo "$scriptname - ERROR - No arguments. Exiting"
    usage
    exiting -1
fi

is_dry_run=0
assume_yes=0
source_dir=""
destination_dir=""
OPTIND=1
while getopts ":tys:d:" opt; do
  case "$opt" in
    t)
        is_dry_run=1
        ;;
    y)
        assume_yes=1
        ;;
    s)
        source_dir="$OPTARG"
        ;;
    d)
        destination_dir="$OPTARG"
        ;;
    \?)
        echo "$scriptname - ERROR - Invalid option \"-$OPTARG\". Exiting"
        usage
        exiting -1
        ;;
    \:)
        echo "$scriptname - ERROR - Option \"-$OPTARG\" requires an argument. Exiting"
        usage
        exiting -1
        ;;
    *)
        echo "$scriptname - ERROR - Invalid input. Exiting"
        usage
        exiting -1
        ;;
  esac
done

shift $((OPTIND-1))
if [ $# -ne 0 ]; then
    echo "$scriptname - ERROR - Wrong arguments. Exiting"
    usage
    exiting -1
fi

if [ -z "$source_dir" ]; then
    echo "$scriptname - ERROR - \"source_dir\" param is empty. Exiting"
    usage
    exiting 1
elif [ -z "$destination_dir" ]; then
    echo "$scriptname - ERROR - \"destination_dir\" param is empty. Exiting"
    usage
    exiting 1
elif [[ "${source_dir:0:1}" != "/" ]]; then
    echo "$scriptname - ERROR - source_dir \"$source_dir\" is not an absolute path. Exiting"
    usage
    exiting 1
elif [[ "${destination_dir:0:1}" != "/" ]]; then
    echo "$scriptname - ERROR - destination_dir \"$destination_dir\" is not an absolute path. Exiting"
    usage
    exiting 1
elif [ "$source_dir" = "/" ]; then
    echo "$scriptname - ERROR - source_dir must not be the root (\"/\") path. Exiting"
    exiting 1
elif [ "$destination_dir" = "/" ]; then
    echo "$scriptname - ERROR - destination_dir must not be the root (\"/\") path. Exiting"
    exiting 1
elif [ "$source_dir" = "$destination_dir" ]; then
    echo "$scriptname - ERROR - \"source_dir\" param equals \"destination_dir\" param. Exiting"
    exiting 1
elif [ ! -d "$source_dir" ]; then
    echo "$scriptname - ERROR - source_dir \"$source_dir\" not found or not a directory. Exiting"
    exiting 1
elif [ ! -d "$destination_dir" ]; then
    echo "$scriptname - ERROR - destination_dir \"$destination_dir\" not found or not a directory. Exiting"
    exiting 1
fi

if ! command -v rsync &> /dev/null; then
    echo "$scriptname - ERROR - rsync command not found. Exiting"
    exiting 3
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "$scriptname - ERROR - Must be root to execute this script. Exiting"
    exiting 2
fi

echo "$scriptname - INFO - Going to rsync:"
echo "    FROM: $source_dir"
echo "    TO:   $destination_dir"
echo
confirm=""
if [ "$assume_yes" -ne 1 ]; then
    read -r -p 'Are you sure [y/n] ? ' confirm
    confirm="${confirm:-n}"
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "yes" && "$confirm" != "YES" ]]; then
        echo "$scriptname - INFO - **NOT** executing rsync. Exiting"
        exiting 4
    fi
fi

rsync_cmd "$is_dry_run"
exiting $?
