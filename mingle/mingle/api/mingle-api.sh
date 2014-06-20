MINGLE_INITIALIZE=false

# Initialize our own variables:
verbose=0
suite=""
altPath=""

ad_mkdir() {
    local _dir=$1

    if [ ! -e $_dir ]; then
        mkdir -p $_dir || mingleError $? "mkdir failed for $_dir, aborting!"
    fi
}

ad_rmdir() {
    local _dir=$1

    if [ -e $_dir ]; then
        rm -rf $_dir || mingleError $? "mkdir failed for $_dir, aborting!"
    fi
}

ad_cd() {
    local _dir="$1"
    
    if [ "$_dir" == ".." ]; then
        local _curdirname=`pwd`
        mingleLog "Changing directory to `dirname $_curdirname`..." true
    else
        mingleLog "Changing directory to $_dir..." true
    fi
    
    if [ -z "$_dir" ]; then
       mingleError -1 "Please provide a valid directory."
    fi
    
    cd $_dir || mingleError $? "cd failed, aborting!"
}

ad_isDateNewerThanFileModTime() {
    local _checkdate=$1
    local _filename=$2

    if [ ! -e $_filename ]; then
        return 0
    fi

    local _chkdtseconds=`date -d "$_checkdate" +%s`

    local _getfiledate=`stat -c %y $_filename|sed 's/ .*//'`
    local _cnvrtfieldate=`date -d "$_getfiledate" +%s`

    echo "comparing provided date ($_checkdate, $_chkdtseconds), with filedate ($_getfiledate, $_cnvrtfieldate)."

    if [ "$_chkdtseconds" -gt "$_cnvrtfieldate" ]; then
        return 0
    fi

    return 1
}

ad_getDirFromLocWC() {
    local _project="$1"
    local _directory="$2"
    local _result=`find $_directory -maxdepth 1 -name "$_project" -prune -type d -print | head -1`

    echo "$_result"
}

ad_getDirFromWC() {
    local _project="$1"
    local _result=`find $MINGLE_BUILD_DIR -maxdepth 1 -name "$_project" -prune -type d -print | head -1`

    echo "$_result"
}

ad_getArchiveFromLocWC() {
    local _project="$1"
    local _directory="$2"
    local _result=`find $_directory -maxdepth 1 -name "$_project" -prune -type f -print | head -1`

    echo "$_result"
}

ad_getArchiveFromWC() {
    local _project="$1"
    local _result=`find $MINGLE_CACHE -maxdepth 1 -name "$_project" -prune -type f -print | head -1`

    echo "$_result"
}

ad_rename() {
    local _wildcard="$1"
    local _regex="$2"
    
    mingleLog "Renaming _wildcard=$1, _regex=$2 " true
    
    find . -regex "$_wildcard" | while read line; do
        A=`basename ${line} | sed $_regex`
        B=`dirname ${line}`
        
        echo mv ${line} "${B}/${A}"
        mv ${line} "${B}/${A}" || mingleError $? "rename failed, aborting!"
    done
}

ad_relocate_bin_dlls() {
    local _dllPrefix="$1"

    mingleLog "Checking for DLLS with prefix: $_dllPrefix.*.dll..." true

    find /mingw/lib -regex "/mingw/lib/$_dllPrefix.*\.dll" | while read line; do
        echo "Copying ${line} to /mingw/bin..."
        cp -u ${line} "/mingw/bin" || mingleError $? "ad_relocate_bin_dlls failed, aborting"
    done
}

ad_fix_pkg_cfg() {
    local _pkgconfigfile=/mingw/lib/pkgconfig/$1

     sed 's/\\/\//g' $_pkgconfigfile>$_pkgconfigfile-2
     mv $_pkgconfigfile-2 $_pkgconfigfile
}

ad_create_libtool_la() {
local _libraryName=$1

mingleLog "Generating /mingw/lib/lib$_libraryName.la..." true

cat > /mingw/lib/lib$_libraryName.la << EOF
# lib${_libraryName}.la - a libtool library file
# Generated by libtool (GNU libtool) 2.4.2
#
# Please DO NOT delete this file!
# It is necessary for linking the library.
EOF

echo "# The name that we can dlopen(3)." >> /mingw/lib/lib$_libraryName.la
if [ -e "/mingw/bin/lib${_libraryName}.dll" ]; then
  echo "dlname='../bin/lib${_libraryName}.dll'" >> /mingw/lib/lib$_libraryName.la
elif [ -e "/mingw/bin/${_libraryName}.dll" ]; then
  echo "dlname='../bin/${_libraryName}.dll'" >> /mingw/lib/lib$_libraryName.la
else
  echo "dlname=''" >> /mingw/lib/lib$_libraryName.la
fi

echo >> /mingw/lib/lib$_libraryName.la
echo "# Names of this library." >> /mingw/lib/lib$_libraryName.la
if [ -e "/mingw/lib/lib${_libraryName}.dll.a" ]; then
  echo "library_names='lib${_libraryName}.dll.a'" >> /mingw/lib/lib$_libraryName.la
else
  echo "library_names=''" >> /mingw/lib/lib$_libraryName.la
fi

echo >> /mingw/lib/lib$_libraryName.la
echo "# The name of the static archive." >> /mingw/lib/lib$_libraryName.la
if [ -e "/mingw/lib/lib${_libraryName}.a" ]; then
  echo "old_library='lib${_libraryName}.a'" >> /mingw/lib/lib$_libraryName.la
else
  echo "old_library=''" >> /mingw/lib/lib$_libraryName.la
fi


cat >> /mingw/lib/lib$_libraryName.la << EOF

# Linker flags that can not go in dependency_libs.
inherited_linker_flags=''

# Libraries that this one depends upon.
dependency_libs=''

# Names of additional weak libraries provided by this library
weak_library_names='lib${_libraryName}.dll.a'

# Version information for lib${_libraryName}.
current=4
age=4
revision=8

# Is this an already installed library?
installed=yes

# Should we warn about portability when linking against -modules?
shouldnotlink=no

# Files to dlopen/dlpreopen
dlopen=''
dlpreopen=''

# Directory that this library needs to be installed in:
libdir='/mingw/lib'
EOF

}

ad_fix_shared_lib() {  
    local _origPath=`pwd`
    cd /mingw/lib || mingleError $? "ad_fix_shared_lib cd failed, aborting"
    
    local _libraryName=`ls $1*.a|sed -e 's/\.dll\.a//' -e 's/\.a//'|uniq|sort|head -1`
    
    echo "Parsed library name: $_libraryName"    
    
    if [ ! -e "$_libraryName".dll.a ] && [ -e "$_libraryName".a ]; then
        cp -f "$_libraryName".a "$_libraryName".dll.a
    fi
    
    #ad_rename "./icu.*.dll" "s/^icu/libicu/g"

    if [ -e "$_libraryName.la" ]; then
        echo "Updating $_libraryName.la..."
        
        sed -e "s/dlname='.*/dlname='..\/bin\/$_libraryName.dll'/g" $_libraryName.la>$_libraryName-2
        mv $_libraryName-2 $_libraryName.la

        sed -e "s/\(library_names='\).*/\1$_libraryName.dll.a'/g" $_libraryName.la>$_libraryName-2
        mv $_libraryName-2 $_libraryName.la

        sed -e "s/\(old_library='\).*/\1$_libraryName.a'/g" $_libraryName.la>$_libraryName-2
        mv $_libraryName-2 $_libraryName.la
    else
        echo "$_libraryName.la doesn't exist!. Generating..."
    fi
    
    ad_cd "$_origPath" || mingleError $? "ad_fix_shared_lib cd failed, aborting"
}

ad_generateImportLibraryForDLL() {
    local _dll=$1
    local _importName=`echo $_dll|sed 's/\.dll//'`
    local _searchPath=''
    
    mingleLog "Generate Import Library..." true
    
    if ! echo $_dll|grep '^lib' ; then
        _importName="lib$_importName"
    fi
    
    if [ -e /mingw/lib/$_dll ]; then
        _searchPath=/mingw/lib
    else
        _searchPath=/mingw/bin
    fi
    
    mingleLog "Generating import library for dll: $_dll, import library: $_importName.a..." true
    
    pexports $_searchPath/$_dll |sed "s/^_//">$_importName.def || mingleError $? "ad_generateImportLibraryForDLL failed to pexport $_importName.a, aborting"
    dlltool -U -d $_importName.def -l $_importName.a || mingleError $? "ad_generateImportLibraryForDLL failed to generate def file for $_importName.a, aborting"
    mv $_importName.a /mingw/lib || mingleError $? "ad_generateImportLibraryForDLL failed to generate $_importName.a, aborting"
}

ad_clearEnv() {
    mingleLog "Resetting environment flags..." true

    unset PKG_CONFIG_PATH; unset CFLAGS; unset LDFLAGS; unset CPPFLAGS; unset CRYPTO; unset CC; unset CXX; unset LIBS

    ad_cd $MINGLE_BUILD_DIR
}

ad_setDefaultEnv() {
    mingleLog "Resetting environment flags to default..." true
    
    # Additional optimizations can be found here: http://gcc.gnu.org/onlinedocs/gcc-4.4.2/gcc/i386-and-x86_002d64-Options.html
    # used so far -mtune=amdfam10
    #
    
    #_POSIX_C_SOURCE=199309L or 200112L
    # -D_POSIX_C_SOURCE=200112L -D_GNU_SOURCE=200112L
    # -D_POSIX_TIMEOUTS -D_GLIBCXX__PTHREADS -D_GLIBCXX_HAS_GTHREADS
    export "PKG_CONFIG_PATH=/mingw/lib/pkgconfig"
    #for debugging: CFLAGS=-g -fno-inline -fno-strict-aliasing
    export "CFLAGS=-I/mingw/include -D_WIN64 -D__WIN64 -DMS_WIN64 -D__USE_MINGW_ANSI_STDIO -Ofast -funroll-all-loops"
    export "LDFLAGS=-L/mingw/lib"
    export "CPPFLAGS=-I/mingw/include -D_WIN64 -D__WIN64 -DMS_WIN64 -D__USE_MINGW_ANSI_STDIO -O2 -funroll-all-loops"
    export "CXXFLAGS=$CPPFLAGS"
    export "CRYPTO=POLARSSL"
    export "CC=x86_64-w64-mingw32-gcc"
    export "CXX=x86_64-w64-mingw32-g++"
    unset LIBS

    ad_cd $MINGLE_BUILD_DIR
}

ad_patch() {
    local _patchFile=$1
    local _workingDir=`pwd`
    
    mingleLog "Patching..." true

    if [ "$MINGLE_BUILD_DIR" == "$_workingDir" ]; then
        mingleLog "Patching failed! Patch should be ran from project directory." true

        mingleError -1 "Patching failed! Patch should be ran from project directory."
    fi

    patch --ignore-whitespace -f -p1 < $_patchFile
}

ad_configure() {
    local _project=$1
    local _runAutoGenIfExists=$2 #true/false
    local _runACLocal=$3 #true/false
    local _aclocalFlags=$4
    local _runAutoconf=$5 #true/false
    local _options="--prefix=/mingw --host=x86_64-w64-mingw32 --build=x86_64-w64-mingw32"
    local _additionFlags=$6
    
    mingleLog "Configuring..." true
    
    local _projectDir=$(ad_getDirFromWC "$_project")

    ad_cd $_projectDir
    
    if [ -e "autogen.sh" ] && $_runAutoGenIfExists; then
        mingleLog
        mingleLog "Autgen.sh script found, executing script..."
        mingleLog "  _options=$_options"
        mingleLog "  _additionFlags=$_additionFlags"

        ./autogen.sh $_options $_additionFlags
        
        if [ $? -ge 1 ]; then
            Echo "autogen failed. Trying without options."
            ./autogen.sh
        fi
    elif [ -e "configure.ac" ] || [ -e "configure.in" ]; then
        if [ -e "/mingw/bin/autoconf" ];then
            if $_runACLocal; then
                mingleLog "Executing aclocal $_aclocalFlags..." true
                
                if [ -n "$_aclocalFlags" ]; then
                    aclocal $_aclocalFlags || mingleError $? "ad_configure aclocal failed, aborting!"
                else
                    aclocal || mingleError $? "ad_configure aclocal failed, aborting!"
                fi
            fi

            if $_runAutoconf; then
                mingleLog "Executing autoconf..." true
                autoconf || mingleError $? "ad_configure autoconf failed, aborting!"
                
                mingleLog "Executing autoheader..." true
                autoheader               
            fi
        fi
    fi
        
    if [ -e "configure" ]; then
        local _counter=1
        local _retries=3
        local _configFailed=false

        mingleLog
        mingleLog "Using CFLAGS: $CFLAGS"
        mingleLog "Using CPPFLAGS: $CPPFLAGS"
        mingleLog "Using LDFLAGS: $LDFLAGS"

        mingleLog "executing: ./configure $_options $_additionFlags" true

        local _newflags="$_options $_additionFlags"

        ./configure $_newflags &>out.txt
        while [ $? -ge 1 ]
        do
            if [ $_counter -gt $_retries ]; then
                mingleError 9999 "Max configure retries reached. Build Failed!"
            fi

            local _test=`cat out.txt|grep "unrecognized option"|sed -e "s/^.*\(--.*\)/\1/"`

            if [ -z "$_test" ]; then
                _test=`cat out.txt|grep -i "error: no such option:"|sed -e "s/^.*\(--.*\)/\1/"`
                if [ -z "$_test" ]; then
                    _test=`cat out.txt|grep -i "Unknown option:"|sed -e "s/^.*\(--.*\)/\1/"`
                    if [ -z "$_test" ]; then
                        #--host=x86_64-w64-mingw32: invalid command-line switch
                        _test=`cat out.txt|grep -i "invalid command-line switch"|sed -e "s/\(--.*\): invalid.*/\1/"`
                        if [ -z "$_test" ]; then
                            _configFailed=true
                        fi
                    fi
                fi
            fi

            if $_configFailed; then
                cat out.txt
                mingleError 9999 "Configuration Failed for $_project!"
            fi

            _newflags=`echo "$_newflags "|sed -e "s/$_test[^ ]* //"`
            _counter=$(( $_counter + 1 ))

            mingleLog "Retrying without option: $_test..." true
            mingleLog "Executing: ./configure $_newflags" true
            
            ./configure $_newflags &>out.txt
        done

        cat out.txt

        if [ -e "out.txt" ]; then
            rm out.txt
        fi
    fi
    
    if [ -e "./libtool" ]; then
        echo
        echo "Adjusting libtool LTCC setting"
        sed 's/\(LTC[CFLAGS]*=.*\)\s\-I.mingw.include.mingle/\1/g' ./libtool>libtool2
        mv -f libtool2 libtool
    fi
        
    ad_cd $MINGLE_BUILD_DIR
}

ad_make_clean() {
    local _project=$1

    mingleLog "Executing make clean for $_project..." true
    
    local _projectDir=$(ad_getDirFromWC "$_project")

    cd $_projectDir || mingleError $? "cd failed, aborting"
    
    make distclean || make clean

    ad_cd ".."
}

# Use single quotes for parameter defines, ex: TEST='cmd -h'
ad_make() {
    local _project=$1
    local _makeParameters="$2"
    
    local _projectDir=$(ad_getDirFromWC "$_project")
	
    ad_cd $_projectDir

    mingleLog "GCC Version Information:" true
    gcc --version

    mingleLog "Executing make $_makeParameters..." true

    if [ -n "$_makeParameters" ]; then
        IFS=';'
        local _args=(`echo $_makeParameters|sed -e 's/\([^=]\)\" /\1\";/g' -e s/\"//g`)
        IFS=' '
        make "${_args[@]}" || mingleError $? "make failed, aborting!"
        mingleLog "Executing make install $_makeParameters..." true
        make install "${_args[@]}" || mingleError $? "make install failed, aborting"
    else
        make || mingleError $? "make failed, aborting!"
        mingleLog "Executing make install $_makeParameters..." true
        make install || mingleError $? "make install failed, aborting"
    fi

    ad_cd ".."
}

ad_boost_jam() {
    local _project=$1
    
    local _projectDir=$(ad_getDirFromWC "$_project")
    cd $_projectDir || mingleError $? "ad_boost_jam cd failed, aborting!"
    
    #this is needed for boost https://svn.boost.org/trac/boost/ticket/6350
    cp $MINGLE_BASE/mingle/mingw.jam tools/build/v2/tools || mingleError $? "ad_boost_jam mingw.jam copy failed, aborting!"

    
   ./bootstrap.sh --with-icu --prefix=/mingw --with-toolset=mingw || mingleError $? "ad_boost_jam boostrap failed, aborting"
   
    bjam --prefix=/mingw -sICU_PATH=/mingw -sICONV_PATH=/mingw toolset=mingw address-model=64 threadapi=win32 variant=debug,release link=static,shared threading=multi define=MS_WIN64 define=BOOST_USE_WINDOWS_H --define=__MINGW32__ --define=_WIN64 --define=MS_WIN64 install || mingleError $? "ad_boost_jam bjam failed, aborting"
    
    ad_cd ".."
}

ad_build() {
    local _project=$1
    
    local _projectDir=$(ad_getDirFromWC "$_project")
    cd $_projectDir || mingleError $? "cd failed, aborting"
    
    ./build.sh  || mingleError $? "ad_build build.sh failed, aborting"
    
    ad_cd ".."
}

ad_exec_script() {
    local _project="$1"
    local _postBuildCommand="$2"
    
    local _projectDir=$(ad_getDirFromWC "$_project")
    cd $_projectDir || mingleError $? "cd failed, aborting"
        
    if [ ! -z "$_postBuildCommand" ]; then
        mingleLog "Executing post command: '$_postBuildCommand'" true
        `$_postBuildCommand`
    fi
        
    ad_cd ".."
}

ad_run_test() {
    local _exeToTest=$1
    
    if [ ! -z "$_exeToTest" ]; then
        mingleLog "Executing $_exeToTest..." true
        if ! $_exeToTest; then
            mingleError -1 "Build failed, aborting!"
        fi 
    fi    
}

ad_getShortLibName() {
    local _project="$1"
    local _shortProjectName=`echo $_project|sed s/-.*//g`
    
    local _sub=`echo ${_project[@]:0:3}`
    
    if [ "$_sub" != "lib" ]; then
        _shortProjectName="lib$_shortProjectName"
    fi
    
    echo $_shortProjectName
}

mingleAutoBuild() {
    local _projectName="$1"
    local _version="$2"
    local _url="$3"
    local _target="$4"
    local _projectSearchName="$5"
    local _cleanEnv=$6 #true/false
    local _runAutoGenIfExists=$7 #true/false
    local _runACLocal=$8 #true/false
    local _aclocalFlags="$9"
    local _runAutoconf=${10} #true/false
    local _runConfigure=${11} #true/false
    local _configureFlags="${12}"
    local _makeParameters="${13}"
    local _binCheck="${14}"
    local _postBuildCommand="${15}"
    local _exeToTest="${16}"
    
    mingleLog "Auto-check for binary $_binCheck..." true
    
    if ! ( [ -e "/mingw/lib/$_binCheck" ] || [ -e "/mingw/bin/$_binCheck" ] );then
        mingleCategoryDownload $_projectName $_version $_url $_target
        mingleCategoryDecompress $_projectName $_version "$_projectSearchName"
        buildInstallGeneric "$_projectSearchName" $_cleanEnv $_runAutoGenIfExists $_runACLocal "$_aclocalFlags" $_runAutoconf $_runConfigure "$_configureFlags" "$_makeParameters" "$_binCheck" "$_postBuildCommand" "$_exeToTest"
    fi
}

buildInstallGeneric() {
    local _project="$1"
    local _cleanEnv=$2 #true/false
    local _runAutoGenIfExists=$3 #true/false
    local _runACLocal=$4 #true/false
    local _aclocalFlags="$5"
    local _runAutoconf=$6 #true/false
    local _runConfigure=$7 #true/false
    local _configureFlags="$8"
    local _makeParameters="$9"
    local _binCheck="${10}"
    local _postBuildCommand="${11}"
    local _exeToTest="${12}"

    ad_cd $MINGLE_BUILD_DIR

    mingleLog
    mingleLog "Generic Build Initiated:"
    mingleLog "  _project:          $_project"
    mingleLog "  _cleanEnv:         $_cleanEnv"
    mingleLog "  _runACLocal:       $_runACLocal"
    mingleLog "  _aclocalFlags:     $_aclocalFlags"
    mingleLog "  _runAutoconf:      $_runAutoconf"
    mingleLog "  _runConfigure:     $_runConfigure"
    mingleLog "  _configureFlags:   $_configureFlags"
    mingleLog "  _makeParameters:   $_makeParameters"
    mingleLog "  _binCheck:         $_binCheck"
    mingleLog "  _postBuildCommand: $_postBuildCommand"
    mingleLog "  _exeToTest:        $_exeToTest"
    mingleLog "Checking for binary $_binCheck..." true
    
    if ! ( [ -e "/mingw/lib/$_binCheck" ] || [ -e "/mingw/bin/$_binCheck" ] );then
        mingleLog "Building $_project..." true

        if $_cleanEnv; then
            ad_setDefaultEnv
        fi

        mingleDecompress "$_project"

        local _projectDir=$(ad_getDirFromWC "$_project")

        if $_runConfigure; then
            ad_configure "$_project" $_runAutoGenIfExists $_runACLocal "$_aclocalFlags" $_runAutoconf "$_configureFlags"
        fi

        local _jamCheck=`grep -i BJAM "$_projectDir/bootstrap.sh"`

        if [ -e "$_projectDir/bootstrap.sh" ] && [ ! -z "$_jamCheck" ]; then
            ad_boost_jam "$_project"
        elif [ -e "$_projectDir/build.sh" ]; then
            ad_build "$_project"
        else
            ad_make "$_project" "$_makeParameters"
        fi
        
        local _result=`echo "$_configureFlags"|grep "\-\-enable\-shared"`
        
        if [ ! -z "$_result" ]; then
            echo "Shared Library Enabled."
            
            local _shortProjectName=$(ad_getShortLibName $_project)
            
            mingleLog "Short Name: $_shortProjectName"
            
            ad_fix_shared_lib "$_shortProjectName"
        fi
        
        ad_exec_script "$_project" "$_postBuildCommand"

        ad_cd $MINGLE_BUILD_DIR
    else
        mingleLog "Already Installed."
    fi
    
    ad_run_test "$_exeToTest"
    
    echo    
}

mingleLog() {
    local _msg="$1"
    local _dblSpace=$2
    
    if [ -z "$_dblSpace" ]; then
        _dblSpace=false
    fi
    
    if $_dblSpace; then
        echo
        echo $_msg
    else
        echo $_msg
    fi
}

mingleThrowIfError() {
    local _errorNum=$1
    local _errorMsg="$2"
    
    if [ $_errorNum -ne 0 ]; then
        mingleError $_errorNum "$_errorMsg"
    fi
}

mingleError() {
    local _errorNum=$1
    local _errorMsg="$2"

    if [ -z "$_errorMsg" ]; then
        _errorMsg="The build failed."
    fi

    if [ $_errorNum -eq 0 ]; then
        _errorNum=9999
    fi

    mingleLog "Current Project Dir: `pwd`" true
    
    mingleStackTrace "`date +%m-%d-%y\ %T`, $_errorNum $_errorMsg"
    
    echo
    echo "`date +%m-%d-%y\ %T`, \"$_errorNum\", \"$_errorMsg\"">$MINGLE_BUILD_DIR/mingle_error.log
    echo

    exit $_errorNum
}

mingleStackTrace() {
  local frame=0
  
  echo
  echo "====================================================================="
  echo " Stacktrace:"
  echo "====================================================================="
  echo
  
  while caller $frame; do
    ((frame++));
  done
 
  echo
  echo "====================================================================="
  echo " ERROR:"
  echo "====================================================================="
  echo
  echo "$*"
  echo
}

mingleReportToolVersions() {
    echo
    echo "Running Bash Version:"
    echo
    bash --version
    echo
}

mingleInitialize() {
    if ! $MINGLE_INITIALIZE; then
        config="/mingw/etc/mingle.cfg"
        STOREPATH=`pwd`

        mingleReportToolVersions

        if [ -z "$MINGLE_CACHE" ] && [ -z "$MINGLE_BUILD_DIR" ]; then
            mingleLog "Exporting Configuration:"

            while read line
            do
                LINE="$line"
                if [ "${LINE:0:1}" = "#" ] ; then
                    echo "Skipping disabled variable: $LINE"
                else
                    BASHEXPORT=`echo $LINE|sed -e '0,/RE/s/\%/\$/' -e 's/\%//'`
                    echo "Exporting: $BASHEXPORT"
                    export "`eval echo $BASHEXPORT`"
                fi
            done <"$config"
        fi

        MINGLE_CACHE=`echo "$MINGLE_CACHE" | sed -e 's/\([a-xA-X]\):\\\/\/\1\//' -e 's/\\\/\//g'`

        if [ -n "$altPath" ]; then
            export "MINGLE_BUILD_DIR=$altPath"
        fi

        echo MINGLE_BASE=$MINGLE_BASE
        echo MINGLE_BUILD_DIR=$MINGLE_BUILD_DIR
        echo MINGLE_CACHE=$MINGLE_CACHE

        if [ ! -e "$MINGLE_CACHE" ]; then
            mkdir -p $MINGLE_CACHE || mingleError $? "failed to create cache directory, aborting!"
        fi

        if [ ! -e "$MINGLE_BUILD_DIR" ]; then
            mkdir -p $MINGLE_BUILD_DIR || mingleError $? "failed to create build directory, aborting!"
        fi

        if [ ! -e "/usr/local" ]; then
            mkdir /usr/local || mingleError $? "failed to create directory, aborting!"
        fi

        if [ ! -e "/usr/local/bin" ]; then
            mkdir /usr/local/bin || mingleError $? "failed to create directory, aborting!"
        fi

        if [ ! -e "/usr/local/include" ]; then
            mkdir /usr/local/include || mingleError $? "failed to create directory, aborting!"
        fi

        if [ ! -e "/usr/local/lib" ]; then
            mkdir /usr/local/lib || mingleError $? "failed to create directory, aborting!"
        fi
        
        if [ ! -e "/tmp" ]; then
            mkdir /tmp || mingleError $? "failed to create tmp, aborting!"
        fi
        
        if [ ! -e "$MINGLE_BUILD_DIR/temp" ]; then
            mkdir $MINGLE_BUILD_DIR/temp || mingleError $? "failed to create tmp, aborting!"
        fi
        
        export "TMPDIR=$MINGLE_BUILD_DIR/temp"
        export "TEMP=$TMPDIR"
        export "TMP=$TMPDIR"

        MINGLE_INITIALIZE=true
    fi

    ad_cd $MINGLE_BUILD_DIR

    if [ -e "mingle_error.log" ]; then
        rm mingle_error.log
    fi
}

mingleDownload() {
    local _url="$1"
    local _outputFile="$2"
    local _file="`echo $_url|sed 's/.*\///'`"
    local _alreadyDownloaded=false

    if [ -z "$_outputFile" ]; then
        _outputFile=$_file
    fi

    mingleInitialize

    local _savedir=`pwd`

    ad_cd $MINGLE_CACHE

    mingleLog "Checking for previous output, $_outputFile..." true

    if [ -e "$_outputFile" ]; then
        local _filesize=$(stat -c%s "$_outputFile")

        if [ "$_filesize" -eq "0" ]; then
            echo
            echo "Removing 0 byte file: $_outputFile..."
            rm $_outputFile
        else
            _alreadyDownloaded=true
        fi
    fi
    
    if ! $_alreadyDownloaded; then
        local _tarcheck="`echo $_outputFile|sed 's/\(.*\)\..*/\1/'`"
        if [ ${_tarcheck: -4} == ".tar" ] && [ -e "$_tarcheck" ]; then
            _alreadyDownloaded=true
        fi
    fi

    if ! $_alreadyDownloaded; then
        mingleLog "Downloading $_url..." true
        
        if echo $_url|grep -i 'https://'; then
            wget  --no-check-certificate $_url -O $_outputFile || mingleError $? "Download failed for $_file, aborting!"
        else
            wget $_url -O $_outputFile || mingleError $? "Download failed for $_file, aborting!"
        fi
    else
        echo
        echo "$_outputFile has already been downloaded."
    fi

    echo

    ad_cd $_savedir
}

mingleDecompress() {
    local _project="$1"
    local _sourceDir="$2"
    local _targetDir="$3"
    local _projectDir=""
    local _decompFile=""
    local _tarcheck=false
    
    mingleLog "mingleDecompress: Checking _project=$_project, _sourceDir=$_sourceDir..." true
    
    if [ -n "$_sourceDir" ]; then
        _projectDir=$(ad_getDirFromLocWC "$_project" "$_sourceDir")
    else
        _projectDir=$(ad_getDirFromWC "$_project")
    fi
    
    if [ -z "$_projectDir" ]; then
        if [ -n "$_sourceDir" ]; then
            _decompFile=$(ad_getArchiveFromLocWC "$_project" "$_sourceDir")
        else
            _decompFile=$(ad_getArchiveFromWC "$_project")
        fi

        if [ ! -e "$_decompFile" ]; then
            mingleError $? "Failed to find archive for: $_sourceDir $_project, aborting!"
        fi

        if [ -n "$_targetDir" ]; then
            if [ "`dirname $_targetDir`" == "." ]; then
                echo "updating path..."
                _targetDir=$MINGLE_BUILD_DIR/$_targetDir
            fi
            ad_mkdir $_targetDir
            ad_cd $_targetDir
        else
            ad_cd $MINGLE_BUILD_DIR
        fi
        
        _removePath="${_decompFile##*/}"
        _targetdircheck="${_removePath%.*}"

        if [ -d "$_targetdircheck" ]; then
            mingleLog "$_targetdircheck already decompressed. Using..." true
            return
        fi
            
        mingleLog "Decompressing $_decompFile to `pwd`..."
            
        if [ ${_decompFile: -4} == ".tgz" ]; then
            tar xzvf "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
        elif [ ${_decompFile: -3} == ".gz" ]; then
            gzip -d "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
            _tarcheck=true
        elif [ ${_decompFile: -3} == ".xz" ]; then
            xz -d "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
            _tarcheck=true
        elif [ ${_decompFile: -4} == ".bz2" ]; then
            bzip2 -d "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
            _tarcheck=true
        elif [ ${_decompFile: -3} == ".7z" ]; then
            7za x "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
        elif [ ${_decompFile: -4} == ".zip" ]; then
            unzip -q -n "$_decompFile"
            local _result=$?
	    if ! ( [ "$_result" == 0 ] || [ "$_result" == 3 ] );then
                echo _result=$_result
                mingleError $? "Decompression failed for $_decompFile, aborting!"
            fi
        elif [ ${_decompFile: -5} == ".lzma" ]; then
            lzma -d "$_decompFile" || mingleError $? "Decompression failed for $_decompFile, aborting!"
            _tarcheck=true
        elif [ "${_decompFile: -4}" == ".tar" ]; then
            tar xvf "$_decompFile" || mingleError $? "Failed to unarchive $_decompFile, aborting!"
        fi
        
        if $_tarcheck; then
            if [ -n "$_sourceDir" ]; then
                _decompFile=$(ad_getArchiveFromLocWC "$_project" "$_sourceDir")
            else
                _decompFile=$(ad_getArchiveFromWC "$_project")
            fi
        
            if [ "${_decompFile: -4}" == ".tar" ]; then
                tar xvf "$_decompFile" || mingleError $? "Failed to unarchive extracted $_decompFile, aborting!"
            fi
        fi

        if [ -n "$_targetDir" ]; then
            ad_cd $MINGLE_BUILD_DIR
        fi
    fi
}

mingleCategoryDownload() {
  local _projectName="$1"
  local _version="$2"
  local _url="$3"
  local _overidename=$4
  local _file="`echo $_url|sed 's/.*\///'`"
  
  mingleLog "Checking ${_projectName} for $_version" true
  
  if [ ! -e "$MINGLE_CACHE/$_projectName/$_version" ]; then
      ad_mkdir $MINGLE_CACHE/$_projectName/$_version
  elif [ "$_version" == "master" ]; then
      mingleLog
      mingleLog "I see you're using a git master branch."
      mingleLog "I will remove any old remnants and download "
      mingleLog "the head of master again."
      mingleLog
      ad_rmdir $MINGLE_CACHE/$_projectName/$_version
      ad_mkdir $MINGLE_CACHE/$_projectName/$_version
  fi
  
  if [ -z "$_overidename" ]; then
      _outputfile=$MINGLE_CACHE/$_projectName/$_version/$_file
  else
      _outputfile=$MINGLE_CACHE/$_projectName/$_version/$_overidename
  fi
  
  mingleDownload $_url $_outputfile
}

mingleCategoryDecompress() {
  local _projectName="$1"
  local _version="$2"
  local _project="$3"
  local _sourceDir=$MINGLE_CACHE/$_projectName/$_version
  local _targetDir="$4"
  
  mingleDecompress "$_project" "$_sourceDir" "$_targetDir"
}

mingleCleanup() {
    ad_cd "$STOREPATH"

    echo
    echo "Finished Building Modules."
    echo
}