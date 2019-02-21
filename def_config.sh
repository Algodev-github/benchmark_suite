# Default configuration file; do not edit this file, but the file .S-config.sh
# in your home directory. The latter gets created on the very first execution
# of some benchmark script (even if only the option -h is passed to the script).

# Set to yes if you want to use SCSI_DEBUG; this will override your
# possible choice for TEST_PARTITION below, and will set BASE_DIR too,
# automatically, overriding your possible choice for BASE_DIR below.
# scsi_debug is not a good option for performance profiling, use
# nullb for that (next option).
SCSI_DEBUG=no

# Set to yes if you want to use the nullb device; this will override your
# possible choice for TEST_PARTITION below, and will set BASE_DIR too,
# automatically, overriding your possible choice for BASE_DIR below.
NULLB=no

# Set the following parameter to the name (not the full path) of a
# device or of a partition, if you want to perform tests on that
# device or partition.
#
# If you go for a device, then the following two alternatives are
# handled differently: first, the device contains the partition
# /dev/${TEST_DEV}1 and /dev/${TEST_DEV}1 contains a mounted
# filesystem; second, the latter compound condition does not hold. In
# the first case, all test files are created in that filesystem. In
# the second case, the execution is simply aborted if the following
# FORMAT parameter is not set to yes. If, instead, FORMAT is set to
# yes, then
# - the device is formatted so as to contain a partition ${TEST_DEV}1;
# - an ext4 filesystem is made on that partition;
# - that filesystem is mounted.
#
# If you go directly for a partition, then the latter must contain a
# mounted filesystem.
#
# In all succesful cases, all test files are created in the filesystem
# contained in the test partition.
#
# If TEST_DEV is set, then BASE_DIR will be built automatically,
# overriding your possible choice below.
#
# Be careful in setting TEST_DEV manually in case of bcache or
# raids. With these configurations, more then one device is involved.
# The simplest option is to set BASE_DIR to a directory stored on
# these devices, and let the code of the suite automatically detect
# all the involved devices.
TEST_DEV=

# If set to yes, then $TEST_DEV is (re)formatted if needed, as
# explained in detail in the comments on TEST_DEV.
FORMAT=no

# Directory containing files read/written during benchmarks.  The path
# "$PWD/../" points to S root directory. The value for BASE_DIR chosen
# here is overridden if SCSI_DEBUG or TEST_DEV is set.
BASE_DIR=$PWD/../workfiles

# Next parameter contains the names of the devices the test files are
# on (devices may be more than one in case of a RAID
# configuration). Those devices are the ones for which, e.g., the I/O
# scheduler is changed, if you do ask the benchmarks to select the
# scheduler(s) to use. These devices are detected automatically.  If
# automatic detection does not work, or is not wat you want, then just
# reassign the value of DEVS.
# For example: DEVS=sda.
#
# For the same reasons pointed out for TEST_DEV, in case of bcache or
# raids it may not be so easy to set DEVS correctly. It is simpler and
# safer to set, instead, BASE_DIR to a directory stored on the
# involved devices, and let the code of the suite automatically detect
# these devices correctly.
DEVS=

# Size of (each of) the files to create for reading/writing, in
# MiB. If left empty, then automatically set to the maximum value that
# guarantees that at most 50% of the free space is used, or left to
# the value used in last file creation, if lower than the latter
# threshold.  For random I/O with rotational devices, consider that
# the size of the files may heavily influence throughput and, in
# general, service properties.
#
# Change at your will, if you prefer a different value.
FILE_SIZE_MB=

# Portion, in 1M blocks, to read for each file, used only in
# fairness.sh; make sure it is not larger than $FILE_SIZE_MB
NUM_BLOCKS=2000

# If equal to 1, tracing is enabled during each test
TRACE=0

# The kernel-development benchmarks expect a repository in the
# following directory. In particular, they play with v4.0, v4.1 and
# v4.2, so they expect these versions to be present.
KERN_DIR=$BASE_DIR/linux.git-for_kern_dev_benchmarks
# If no repository is found in the above directory, then a repository
# is cloned therein. The source URL is stored in the following
# variable.
KERN_REMOTE=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

# NCQ queue depth, if undefined then no script will change the current value
NCQ_QUEUE_DEPTH=

# Set this variable to the name of your package manager, if auto detect fails
PACKAGE_MANAGER=

# Mail-report parameters. A mail transfer agent (such as msmtp) and a mail
# client (such as mailx) must be installed to be able to send mail reports.
# The sender e-mail address will be the one configured as default in the
# mail client itself.
MAIL_REPORTS=0
MAIL_REPORTS_RECIPIENT=
