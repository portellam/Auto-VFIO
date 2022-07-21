#!/bin/bash sh

# function steps #
# 1. check if related packages are installed, git repo exists, continue.
# 2. read hugepages logfile for vars, calculate reasonable zram swap size
# 3. save output to file, restart related services
#

# check if sudo/root #
if [[ `whoami` != "root" ]]; then
    echo -e "$0: WARNING: Script must be run as Sudo or Root! Exiting."
    exit 0
fi
#

SAVEIFS=$IFS   # Save current IFS (Internal Field Separator)
IFS=$'\n'      # Change IFS to newline char

# parameters #
str_file1="/etc/default/zramswap"
str_file2="/etc/default/zram-swap"
str_file3=`ls $(pwd) | grep -i 'hugepages' | grep -i '.log'`
#

# prompt #
str_output1="$0: ZRAM allocates RAM as a compressed swapfile.\n\tThe default compression method \"lz4\", at a ratio of 2:1 to 5:2, offers the greatest performance."

echo -e $str_output1
#

# parameters #
int_HostMemMaxK=`cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1`     # sum of system RAM in KiB
str_GitHub_Repo="FoundObjects/zram-swap"
#

# check for zram-utils #
if [[ ! -z $str_file1 ]]; then
    apt install -y git zram-tools
    systemctl stop zramswap
    systemctl disable zramswap
fi
#

#
if [[ -z "~/git/$str_GitHub_Repo" ]]; then
    mkdir ~/git
    mkdir ~/git/`echo $str_GitHub_Repo | cut -d '/' -f 1`
    cd ~/git/`echo $str_GitHub_Repo | cut -d '/' -f 1`
    git clone https://www.github.com/$str_GitHub_Repo
fi
#

# check for zram-swap #
if [[ -z $str_file2 ]]; then
    cd ~/git/$str_GitHub_Repo
    sh ./install.sh
fi
#

if [[ `sudo swapon -v | grep /dev/zram*` == "/dev/zram"* ]]; then sudo swapoff /dev/zram*; fi   # disable ZRAM swap
if [[ -z $str_file2"_old" ]]; then cp $str_file2 $str_file2"_old"; fi                           # backup config file

# find HugePage size #
#str_HugePageSize="1G"

# read from hugepages log file

# read from file #
while read str_line1; do
    if [[ $str_line1 == *"hugepagesz="* ]]; then str_HugePageSize=`echo $str_line1 | cut -d '=' -f2`; fi      # parse hugepage size
    if [[ $str_line1 == *"hugepages="* ]]; then str_HugePageNum=`echo $str_line1 | cut -d '=' -f2`; fi        # parse hugepage num
done < $str_file3
#

if [[ $str_HugePageSize == "2M" ]]; then declare -i int_HugePageSizeK=2048; fi
if [[ $str_HugePageSize == "1G" ]]; then declare -i int_HugePageSizeK=1048576; fi

int_HugePageNum=$str_HugePageNum
#

## find free memory ##
declare -i int_HostMemMaxG=$((int_HostMemMaxK/1048576))
declare -i int_SysMemMaxG=$((int_HostMemMaxG+1))        # use modulus?

# free memory #
declare -i int_HugepagesMemG=$int_HugePageNum*$int_HugePageSizeK/1048576
declare -i int_HostMemFreeG=$int_SysMemMaxG-$int_HugepagesMemG
echo -e "$0: Free system memory after hugepages (${int_HugepagesMemG}G): <= ${int_HostMemFreeG}G"
#

# setup ZRAM #
if [[ $int_HostMemFreeG -le 8 ]]; then declare -i int_ZRAM_SizeG=$int_HostMemFreeG/2
else declare -i int_ZRAM_SizeG=4; fi

declare -i int_denominator=$int_SysMemMaxG/$int_ZRAM_SizeG

echo -e "$0: str_HugePageSize == '$str_HugePageSize'"
echo -e "$0: int_HugePageSizeK == '$int_HugePageSizeK'"
echo -e "$0: int_HugePageNum == '$int_HugePageNum'"
echo -e "$0: int_HostMemFreeG == '$int_HostMemFreeG'"
echo -e "$0: int_SysMemMaxG == '$int_SysMemMaxG'"
echo -e "$0: int_ZRAM_SizeG == '$int_ZRAM_SizeG'"
echo -e "$0: int_denominator == '$int_denominator'"

#str_input_ZRAM="_zram_fixedsize=\"${int_ZRAM_SizeG}G\""
#

# file 3
declare -a arr_file_ZRAM=(
"# compression algorithm to employ (lzo, lz4, zstd, lzo-rle)
# default: lz4
_zram_algorithm=\"lz4\"

# portion of system ram to use as zram swap (expression: \"1/2\", \"2/3\", \"0.5\", etc)
# default: \"1/2\"
_zram_fraction=\"1/$int_denominator\"

# setting _zram_swap_debugging to any non-zero value enables debugging
# default: undefined
#_zram_swap_debugging=\"beep boop\"

# expected compression factor; set this by hand if your compression results are
# drastically different from the estimates below
#
# Note: These are the defaults coded into /usr/local/sbin/zram-swap.sh; don't alter
#       these values, use the override variable '_comp_factor' below.
#
# defaults if otherwise unset:
#       lzo*|zstd)  _comp_factor=\"3\"   ;; # expect 3:1 compression from lzo*, zstd
#       lz4)        _comp_factor=\"2.5\" ;; # expect 2.5:1 compression from lz4
#       *)          _comp_factor=\"2\"   ;; # default to 2:1 for everything else
#
#_comp_factor=\"2.5\"

# if set skip device size calculation and create a fixed-size swap device
# (size, in MiB/GiB, eg: \"250M\" \"500M\" \"1.5G\" \"2G\" \"6G\" etc.)
#
# Note: this is the swap device size before compression, real memory use will
#       depend on compression results, a 2-3x reduction is typical
#
#_zram_fixedsize=\"4G\"

# vim:ft=sh:ts=2:sts=2:sw=2:et:"
)
#

# write to file #
if [[ -e $str_file1 ]]; then rm $str_file1; fi      # clear existing file

for str_line1 in ${arr_file_ZRAM[@]}; do echo -e $str_line1 >> $str_file2; done
#
    
systemctl restart zram-swap     # restart service   # NOTE: do not enable/start zramswap.service.
# NOTE: in my setup, I prefer the git repo. I currently do not understand zram setup using the debian package/config file (zram pages are exact sizes compressed, not uncompressed as above).

IFS=$SAVEIFS        # reset IFS
echo "$0: Exiting."
exit 0