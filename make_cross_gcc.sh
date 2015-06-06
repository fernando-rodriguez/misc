#!/bin/bash
#
# http://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/
#

PREFIX=
TARGET=$(gcc -dumpmachine)
GCC_VER=4.8.4
JOBS=2
LINUX_ARCH=
BULLET="\033[0;32m *\033[0m"
REDBUL="\033[0;31m !!\033[0m"

print_msg()
{
	echo -e "$BULLET $1..."
	echo -ne "\033]0;$1\007"
}

print_err()
{
	echo -e "$REDBUL $1"
}

check_err()
{
	if [ $err == 1 ]; then
		print_err "$1"
		exit -1
	fi
}

progressfilt ()
{
        local flag=false
        local gotnewline=false
        local c=
        local cr=$'\r'
        local nl=$'\n'
        local blank=
        local count=0

        while IFS='' read -d '' -rn 1 c
        do
                if [ $flag == true ];
                then
                        if [[ $c == $nl ]];
                        then
                                gotnewline=true
                        fi
                        if [ $gotnewline == false ];
                        then
                                printf '%c' "$c"
                        fi
                else
                        if [[ $c != $cr && $c != $nl ]]
                        then
                                count=0
                        else
                                ((count++))
                                if ((count > 1))
                                then
                                        flag=true
                                fi
                        fi
                fi
        done

        COLUMNS=$(tput cols)
        count=0
        while [ $count -lt $COLUMNS ];
        do
                blank="$blank "
                ((count++))
        done

        printf '%c' "$cr"
        printf "$blank"
        printf '%c' "$cr"
}

dowget()
{
        #if [ $QUIET == 1 ]; then
        #       wget -qc $1 2>&1 > /dev/null
        #else
        #fi
        print_msg "Fetching $1"
        wget -c --progress=bar:force -c $1  2>&1 | \
                "$SCRIPTPATH/make_cross_gcc.sh" --progress-filter
}

untar()
{
        print_msg "Unpacking $(basename $1)..."
	tar -xf $1 || err=1
	[ $err == 1 ] && exit -1
	return 0
}

if [ "$1" == "--progress-filter" ]; then
        progressfilt
        exit 0
fi

# do our best to detect the host platform
# and default compiler to use
#
case $(uname) in
        Darwin)
                JOBS=$(/usr/sbin/sysctl -n hw.ncpu)
                #if [ "$(which automake-1.11)" == "" ]; then
                #       NEED_AUTOMAKE_1_11=1
                #fi 
        ;;  
        CYGWIN*)
                #XHOST=i686-pc-mingw32
                JOBS=$(cat /proc/cpuinfo | grep processor | wc -l)
                #export PATH=/opt/gcc-tools/epoch2/bin/:$PATH
        ;;  
        Linux)
                JOBS=$(cat /proc/cpuinfo | grep processor | wc -l)
        ;;  
esac


# parse arguments
#
while [ $# != 0 ]; do
        case $1 in
		--target=*)
			TARGET=${1#*=}
		;;
		--jobs=*)
			JOBS=${1#*=}
		;;
		--prefix=*)
			PREFIX=${1#*=}
		;;
		--linux-arch=*)
			LINUX_ARCH=${1#*=}
		;;
		--gcc-version=*)
			GCC_VER=${1#*=}
		;;
		*)
			print_err "Invalid argument: $1!!"
			exit -1
		;;
        esac
        shift
done

# if no prefix was given use /opt/$TARGET
#
if [ "${PREFIX}" == "" ]; then
	PREFIX=/opt/${TARGET}
fi

# make sure that the requested target is Linux
#
case $TARGET in
	*-linux-*) ;;
	*)
		print_err "Invalid target!!"
		print_err "This script can only build Linux compilers!!"
		exit -1
	;;
esac

# try to guess linux ARCH if no value was
# provided
#
if [ "${LINUX_ARCH}" == "" ]; then
	case $TARGET in
		i[3-6]86-*)
			LINUX_ARCH=i386
		;;
		x86_64-*)
			LINUX_ARCH=x86_64
		;;
	esac
fi

SCRIPTPATH="$( cd $(dirname $0)/ ; pwd -P )"
cd "$SCRIPTPATH"


err=0
export PATH=$PREFIX/bin:$PATH

print_msg "GCC Version: ${GCC_VER}"
print_msg "Target: ${TARGET}"
print_msg "Linux ARCH: ${LINUX_ARCH}"
print_msg "Prefix: ${PREFIX}"
print_msg "Path: ${PATH}"
print_msg "Jobs: ${JOBS}"

mkdir -p distfiles
cd distfiles
dowget http://ftp.gnu.org/gnu/binutils/binutils-2.24.tar.gz
dowget http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz
dowget https://gmplib.org/download/gmp/gmp-6.0.0a.tar.lz
dowget http://www.mpfr.org/mpfr-current/mpfr-3.1.2.tar.xz
dowget ftp://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz
dowget http://ftp.gnu.org/gnu/glibc/glibc-2.20.tar.xz
dowget https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.18.14.tar.xz
cd ..

mkdir -p $PREFIX || err=1
check_err "Unable to create/access target directory!"

if [ 1 == 1 ]; then
print_msg "Cleaning up build directories"
rm -rf gcc-${GCC_VER}
rm -rf binutils-2.24
rm -rf glibc-2.20
rm -rf build-gcc
rm -rf build-binutils
rm -rf build-glibc
rm -rf linux-3.18.14
rm -rf $PREFIX/*

untar distfiles/binutils-2.24.tar.gz || err=1
untar distfiles/gcc-${GCC_VER}.tar.gz || err=1
untar distfiles/gmp-6.0.0a.tar.lz || err=1
untar distfiles/mpc-1.0.3.tar.gz || err=1
untar distfiles/mpfr-3.1.2.tar.xz || err=1
untar distfiles/glibc-2.20.tar.xz || err=1
untar distfiles/linux-3.18.14.tar.xz || err=1
[ $err == 1 ] && exit -1
fi

print_msg "Compiling GNU Binutils"
mkdir -p build-binutils
cd build-binutils
../binutils-2.24/configure \
	--target=$TARGET \
	--prefix=$PREFIX \
	--with-sysroot \
	--with-lib-path=$PREFIX/lib \
	--disable-werror \
	--disable-nls || err=1
check_err "Error configuring binutils..."
make || err=1
check_err "Error conpiling binutils..."
make install || err=1
check_err "Error installing binutils..."
cd ..

if [ 1 == 1 ]; then
print_msg "Installing Linux headers"
cd linux-3.18.14
make ARCH=${LINUX_ARCH} INSTALL_HDR_PATH=${PREFIX} headers_install
mkdir -p ${PREFIX}/usr
[ ! -e ${PREFIX}/usr/include ] && \
	(ln -fs ${PREFIX}/include ${PREFIX}/usr/include || err=1)
check_err "Could not create ${PREFIX}/usr/include symlink!!"
cd ..

print_msg "Preparing GCC"
mv gmp-6.0.0 gcc-${GCC_VER}/gmp
mv mpc-1.0.3 gcc-${GCC_VER}/mpc
mv mpfr-3.1.2 gcc-${GCC_VER}/mpfr
cd gcc-4.8.4
sed -i '/k prot/agcc_cv_libc_provides_ssp=yes' gcc/configure || err=1
check_err "Error preparing gcc..."
cd ..

print_msg "Configuring GCC (Stage 1)"
mkdir -p build-gcc
cd build-gcc
../gcc-${GCC_VER}/configure \
	--target=$TARGET \
	--prefix=$PREFIX \
	--enable-languages=c,c++ \
	--with-sysroot=$PREFIX \
	--without-docdir \
	--disable-nls || err=1
check_err "Error configuring GCC!!"
print_msg "Compiling GCC..."
make all-gcc || err=1
check_err "Error building GCC!!"
make install-gcc || err=1
check_err "Error installing GCC!!"
cd ..

print_msg "Configuring GNU C Library"
mkdir -p build-glibc
cd build-glibc
../glibc-2.20/configure \
	--prefix=$PREFIX \
	--build=$(gcc -dumpmachine) \
	--host=$TARGET \
	--enable-kernel=2.6.32 \
	--with-headers=$PREFIX/include \
	libc_cv_forced_unwind=yes || err=1
check_err "Error configuring glibc."

print_msg "Installing libc headers"
make install-bootstrap-headers=yes install-headers || err=1
check_err "Error installing glibc headers"

print_msg "Creating dummy startfiles"
echo "" | ${TARGET}-gcc -nostdlib -nostartfiles -r -o $PREFIX/${TARGET}/lib/crt1.o -xc - || err=1
echo "" | ${TARGET}-gcc -nostdlib -nostartfiles -r -o $PREFIX/${TARGET}/lib/crti.o -xc - || err=1
echo "" | ${TARGET}-gcc -nostdlib -nostartfiles -r -o $PREFIX/${TARGET}/lib/crtn.o -xc - || err=1
echo "" | ${TARGET}-gcc -nostdlib -nostartfiles -shared -o $PREFIX/lib/libc.so -xc - || err=1
check_err "Error creating dummy startfiles..."

touch ${PREFIX}/include/gnu/stubs.h || err=1
[ $err == 1 ] && exit -1
cd ..


print_msg "Compiling compiler support library"
cd build-gcc
make -j${JOBS} all-target-libgcc || err=1
check_err "Error compiling libgcc..."
make install-target-libgcc || err=1
check_err "Error installing libgcc..."
cd ..

print_msg "Compiling GNU C Library"
cd build-glibc
make -j${JOBS} || err=1
check_err "Error building glibc!!"
make install || err=1
check_err "Error installing glibc!!"
cd ..
fi

print_msg "Compiling GCC (Stage 2)"
cd build-gcc
rm -rf ../gcc-${GCC_VER}/configure \
	--target=$TARGET \
	--prefix=$PREFIX \
	--enable-languages=c,c++ \
	--disable-libmudflap \
	--with-headers=$PREFIX/include \
	--with-native-system-header-dir=$PREFIX/include \
	--without-docdir \
	--disable-nls || err=1

make -j${JOBS} || err=1
check_err "Error building gcc support libraries!!"
make install || err=1
check_err "Error installing gcc support libraries!!"
cd ..

print_msg "GCC (${TARGET}) built successfully."
exit 0

