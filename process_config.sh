# Default configuration file; do not edit this file, but the file .S-config.sh
# in your home directory. The latter gets created on the very first execution
# of some benchmark script (even if only the option -h is passed to the script).

# first, a little code to to automate stuff; configuration parameters
# then follow

if [[ "$1" != "-h" && "$(id -u)" -ne "0" && -z $BATS_VERSION ]]; then
    echo "You are currently executing me as $(whoami),"
    echo "but I need root privileges (e.g., to switch"
    echo "between schedulers)."
    echo "Please run me as root."
    exit 1
else
    FIRST_PARAM=$1
fi

function print_dev_help
{
    # find right path to config file, used in help messages
    if [ "$SUDO_USER" != "" ]; then
	eval REALHOME=~$SUDO_USER
    else
	eval REALHOME=~
    fi
    CONFPATH=${REALHOME}/.S-config.sh

    echo
    echo To address this issue, you can
    echo - either set the parameter BASE_DIR, in $CONFPATH, to a directory
    echo "  that you know to be in a local filesystem (such a local filesystem"
    echo "  must be mounted on a supported physical or virtual device);"
    echo - or set the parameter TEST_DEV, in $CONFPATH, to \
	 the \(supported\) device
    echo "  or partition you want to use for your tests."
    echo
    echo See the comments in $CONFPATH for details and more options.
}

function get_partition_info
{
	PART_INFO=
	if [[ -e $1 ]]; then
		PART_INFO=$(df $1 | egrep $1)
	else
		# most likely linux live os
		PART_INFO=$(df | egrep $1)
	fi
	echo $PART_INFO
}

function find_partition_for_dir
{
	PART=$(df "$1" | tail -1 | awk '{print $1;}')
	echo $PART
}

function find_dev_for_dir
{
    if [[ "$PART" == "" ]]; then
	PART=$(find_partition_for_dir $1)
    fi

    if [[ "$PART" == "" ]]; then
	echo Sorry, failed to find the partition containing the directory
	echo $1.
	print_dev_help
	exit
    fi

    REALPATH=$PART
    if [[ -e $PART ]]; then
    REALPATH=$(readlink -f $PART) # moves to /dev/dm-X in case of device mapper
    if [[ "$REALPATH" == "" ]]; then
	echo The directory where you want me store my test files,
	echo namely $1,
	echo is contained in the following partition:
	echo $PART.
	echo Unfortunately, such a partition does not seem to correspond
	echo to any local partition \(it is probably a remote filesystem\).
	print_dev_help
	exit
    fi
    fi

    BASEPART=$(basename $PART)
    REALPART=$(basename $REALPATH)

    BACKING_DEVS=
    if [[ "$(echo $BASEPART | egrep loop)" != "" ]]; then
	# loopback device: $BASEPART is already equal to the device name
	BACKING_DEVS=$BASEPART
    elif cat /proc/1/cgroup | tail -1 | egrep -q "container"; then
	# is container. lsblk will return block devices of the host
	# so let's use the host drive.
	BACKING_DEVS=$(lsblk | egrep -m 1 "disk" | awk '{print $1;}')
    elif ! egrep -q $BASEPART /proc/partitions; then
	# is linux live OS. Use cd drive
	BACKING_DEVS=$(lsblk | egrep -m 1 "rom" | awk '{print $1;}')
    else
	# get devices from partition
	for dev in $(ls /sys/block/); do
	    match=$(lsblk /dev/$dev | egrep "$BASEPART|$REALPART")
	    if [[ "$match" == "" ]]; then
		continue
	    fi
	    disk_line=$(lsblk -n -i /dev/$dev | egrep disk | egrep -v "^ |^\`|\|")
	    if [[ "$disk_line" != "" && \
		      ( "$(lsblk -n -o TRAN /dev/$dev 2> /dev/null)" != "" || \
			    $(echo $dev | egrep "mmc|sda|nvme") != "" \
			) ]]; then
		BACKING_DEVS="$BACKING_DEVS $dev"

		if [[ "$HIGH_LEV_DEV" == "" ]]; then
		    HIGH_LEV_DEV=$dev # make md win in setting HIGH_LEV_DEV
		fi
	    fi

	    raid_line=$(lsblk /dev/$dev | egrep raid | egrep ^md)
	    if [[ "$raid_line" != "" ]]; then
		if [[ "$(echo $HIGH_LEV_DEV | egrep md)" != "" ]]; then
		    echo -n Stacked raids not supported
		    echo " ($HIGH_LEV_DEV + $dev), sorry."
		    print_dev_help
		    exit
		fi

		HIGH_LEV_DEV=$dev  # set unconditionally as high-level
				   # dev (the one used, e.g., to
				   # measure aggregate throughput)
	    fi
	done
    fi

    if [[ "$BACKING_DEVS" == "" ]]; then
	echo Block devices for partition $BASEPART or $REALPART unrecognized.
	print_dev_help
	exit
    fi
}

function check_create_mount_part
{
    if [[ $(echo $BACKING_DEVS | egrep "mmc|nvme") != "" ]]; then
	extra_char=p
    fi

    TARGET_PART=${BACKING_DEVS}${extra_char}1

    if [[ ! -b $TARGET_PART ]]; then
	(
	 echo o # Create a new empty DOS partition table
	 echo n # Add a new partition
	 echo p # Primary partition
	 echo 1 # Partition number
	 echo   # First sector (Accept default: 1)
	 echo   # Last sector (Accept default: varies)
	 echo w # Write changes
	) | fdisk $BACKING_DEVS > /dev/null
    fi

    BASE_DIR=$1
    if [[ "$(mount | egrep $BASE_DIR)" == "" ]]; then
	fsck.ext4 -n $TARGET_PART
	if [[ $? -ne 0 ]]; then
	    mkfs.ext4 -F $TARGET_PART
	    if [ $? -ne 0 ]; then
		echo Filesystem creation failed, aborting.
		exit
	    fi
	fi

	mkdir -p $BASE_DIR
	mount $TARGET_PART $BASE_DIR
	if [ $? -ne 0 ]; then
		echo Mount failed, aborting.
		exit
	fi
    fi
    BACKING_DEVS=$(basename $BACKING_DEVS)
    HIGH_LEV_DEV=$BACKING_DEVS
}

function use_nullb_dev
{
	lsmod | grep null_blk > /dev/null

	if [ $? -eq 0 ]; then
		modprobe -r null_blk 2> /dev/null
		if [ $? -eq 1 ]; then # null_blk is not a module but built-in
			echo "ERROR: failed to unload null_blk module"
			exit 1
		fi
	fi

	modprobe null_blk queue_mode=2 irqmode=0 completion_nsec=0 \
		nr_devices=1
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to load null_blk module"
		exit 1
	fi

	BACKING_DEVS=nullb0
	HIGH_LEV_DEV=$BACKING_DEVS
	BASE_DIR= # empty, to signal that there is no fs and no file to create
}

function use_scsi_debug_dev
{
    ../utilities/check_dependencies.sh lsscsi mkfs.ext4 fsck.ext4 sfdisk
    if [[ $? -ne 0 ]]; then
	exit 1
    fi

    if [[ "$(lsmod | egrep scsi_debug)" == "" ]]; then
	echo -n Setting up scsi_debug, this may take a little time ...
	sudo modprobe scsi_debug ndelay=1600000 dev_size_mb=1000 max_queue=4
	if [[ $? -ne 0 ]]; then
	    echo
	    echo "Failed to load scsi_debug module (maybe not installed?)"
	    exit 1
	fi
	echo " done"
    fi

    BACKING_DEVS=$(lsscsi | egrep scsi_debug | sed 's<\(.*\)/dev/</dev/<')
    BACKING_DEVS=$(echo $BACKING_DEVS | awk '{print $1}')

    check_create_mount_part /mnt/scsi_debug
}

function format_and_use_test_dev
{
    ../utilities/check_dependencies.sh mkfs.ext4 fsck.ext4 sfdisk
    if [[ $? -ne 0 ]]; then
	exit 1
    fi

    BACKING_DEVS=/dev/$TEST_DEV
    check_create_mount_part /mnt/S-testfs
}

function get_max_affordable_file_size
{
    if [[ "$FIRST_PARAM" == "-h" ]]; then
	echo
	exit
    fi

    if [[ "$BASE_DIR" == "" ]]; then
	TOT_SIZE=$(blockdev --getsize64 /dev/$HIGH_LEV_DEV)
	TOT_SIZE_MB=$(( $TOT_SIZE / 1000000 ))
	echo $(( $TOT_SIZE_MB / 100 ))
	exit
    fi

    if [[ ! -d $BASE_DIR ]]; then
	echo
	exit
    fi

    if [[ "$PART" == "" ]]; then
	PART=$(find_partition_for_dir $BASE_DIR)
    fi

    if [[ "$(get_partition_info $PART)" == "" ]]; then # it must be /dev/root
	PART=/dev/root
    fi

    BASE_DIR_SIZE=$(du -s $BASE_DIR | awk '{print $1}')
    FREESPACE=$(get_partition_info $PART | awk '{print $4}' | head -n 1)
    MAXTOTSIZE=$((($FREESPACE + $BASE_DIR_SIZE) / 2))
    MAXTOTSIZE_MiB=$(($MAXTOTSIZE / 1024))
    MAXSIZE_MiB=$((MAXTOTSIZE_MiB / 15))
    MAXSIZE_MiB=$(( $MAXSIZE_MiB<500 ? $MAXSIZE_MiB : 500 ))

    if [[ -f ${BASE_FILE_PATH}0 ]]; then
	file_size=$(du --apparent-size -B 1024 ${BASE_FILE_PATH}0 |\
			col -x | cut -f 1 -d " ")
	file_size_MiB=$(($file_size / 1024))
    else
	file_size_MiB=$MAXSIZE_MiB
    fi
    echo $(( $MAXSIZE_MiB>$file_size_MiB ? $file_size_MiB : $MAXSIZE_MiB ))
}

function find_partition {
    lsblk -rno MOUNTPOINT /dev/$TEST_DEV \
	> mountpoints 2> /dev/null

    cur_line=$(tail -n +2  mountpoints | head -n 1)
    i=3
    while [[ "$cur_line" == "" && \
	     $i -lt $(cat mountpoints | wc -l) ]]; do
	cur_line=$(tail -n +$i mountpoints | head -n 1)
	i=$(( i+1 ))
    done

    rm mountpoints

    echo $cur_line
}

function prepare_basedir
{
    # NOTE: the following cases are mutually exclusive

    if [[ "$FIRST_PARAM" == "-h" ]]; then
	return
    fi

    if [[ "$SCSI_DEBUG" == yes ]]; then
	use_scsi_debug_dev # this will set BASE_DIR
	return
    fi

    if [[ "$NULLB" == yes ]]; then
	use_nullb_dev
	return
    fi

    if [[ "$TEST_DEV" != "" ]]; then
	# strip /dev/ if present
	TEST_DEV=$(echo $TEST_DEV | sed 's</dev/<<')

	if [[ "${TEST_DEV: -1}" == [0-9] ]]; then
	    parent_dev=$(readlink /sys/class/block/$TEST_DEV)
	    parent_dev=${parent_dev%/*}
	    parent_dev=${parent_dev##*/}
	    if [[ "$parent_dev" == block ]]; then # not a partition
		parent_dev=
	    fi
	fi

	if [[ "$parent_dev" != "" ]]; then
	    TEST_PARTITION=/dev/$TEST_DEV
	    TEST_PARTITION=$(readlink -f $TEST_PARTITION)
	    TEST_PARTITION=$(echo $TEST_PARTITION | sed 's</dev/<<')

	    TEST_DEV=$parent_dev
	else
	    TEST_DEV=$(readlink -f /dev/$TEST_DEV)
	    TEST_DEV=$(echo $TEST_DEV | sed 's</dev/<<')
	fi

	DISK=$(lsblk -o TYPE /dev/$TEST_DEV | egrep disk)

	if [[ "$DISK" != "" ]]; then
	    FORMAT_DISK=$FORMAT
	fi

	if [[ $TEST_PARTITION != "" ]]; then
	    mntpoint=$(lsblk -no MOUNTPOINT /dev/$TEST_PARTITION)
	else
	    mntpoint=$(find_partition)

	    if [[ "$mntpoint" == "" ]]; then
		# check whether whole dev is used as a degenerate partition
		mntpoint=$(lsblk -no MOUNTPOINT /dev/$TEST_DEV)
	    fi
	fi

	if [[ "$mntpoint" == "" && "$FORMAT_DISK" != yes ]]; then
	    echo -n "Sorry, no mountpoint found for partitions "
	    echo in $TEST_DEV,
	    echo or no partition in $TEST_DEV at all.
	    echo Set FORMAT=yes and TEST_DEV=\<actual drive\> if you want
	    echo me to format the drive, create a fs and mount it for you.
	    echo Aborting.
	    exit
	elif  [[ "$mntpoint" == "" ]]; then # implies $FORMAT_DISK == yes
	    format_and_use_test_dev
	    mntpoint=$BASE_DIR
	fi

	mntpoint=${mntpoint%/} # hate to see consecutive / in paths :)
	BASE_DIR="$mntpoint/var/lib/S"
    fi

    if [[ ! -d $BASE_DIR ]]; then
	mkdir -p $BASE_DIR
    fi

    if [[ ! -w $BASE_DIR && "$TEST_PARTITION" != "" ]]; then
	echo Sorry, $BASE_DIR not writeable for test partition $TEST_PARTITION
	echo Aborting.
	exit
    fi

    if [[ ! -w $BASE_DIR ]]; then
	echo "$BASE_DIR is not writeable, reverting to /tmp/test"
	BASE_DIR=/tmp/test
	mkdir -p $BASE_DIR
    fi

    if [[ "$PART" == "" ]]; then
	PART=$(find_partition_for_dir $BASE_DIR)
    fi

    if [[ "$(get_partition_info $PART)" == "" ]]; then # it must be /dev/root
	PART=/dev/root
    fi

    FREESPACE=$(get_partition_info $PART | awk '{print $4}' | head -n 1)

    BASE_DIR_SIZE=$(du -s $BASE_DIR | awk '{print $1}')

    if [[ $(( ($FREESPACE + $BASE_DIR_SIZE) / 1024 )) -lt 500 ]]; then
	echo Not enough free space for test files in $BASE_DIR: \
	     I need at least 500MB
	exit
    fi

    if [[ "$TEST_DEV" == "" && -d $BASE_DIR ]]; then
	find_dev_for_dir $BASE_DIR
    else
	# in case no path setting BACKING_DEVS has been followed:
	BACKING_DEVS=$TEST_DEV
        HIGH_LEV_DEV=$BACKING_DEVS
    fi
}

# MAIN

prepare_basedir

# paths of files to read/write in the background
if [[ "$BASE_DIR" != "" ]]; then
	BASE_FILE_PATH=$BASE_DIR/largefile
fi

if [[ "$DEVS" == "" ]]; then
    DEVS=$BACKING_DEVS
fi

if [[ "$FIRST_PARAM" != "-h" && -z $BATS_VERSION ]]; then
    # test target devices
    for dev in $DEVS; do
	cat /sys/block/$dev/queue/scheduler >/dev/null 2>&1
	if [ $? -ne 0 ]; then
	    echo -n "There is something wrong with the device /dev/$dev, "
	    echo which should be
	    echo a device on which your test directory $BASE_DIR
	    echo is mounted.
	    echo -n "Try setting your target devices manually "
	    echo \(and correctly\) in ~/.S-config.sh
	    exit
	fi
    done
fi

if [[ "$FILE_SIZE_MB" == "" ]]; then
    FILE_SIZE_MB=$(get_max_affordable_file_size)
fi
