@echo off

:: Init Script for cmd.exe
:: Created as part of cmder project

:: !!! THIS FILE IS OVERWRITTEN WHEN CMDER IS UPDATED
:: !!! Use "%CMDER_ROOT%\config\user-profile.cmd" to add your own startup commands

:: Use /v command line arg or set to > 0 for verbose output to aid in debugging.
set verbose-output=0
set debug-output=0
set max_depth=1

:: Find root dir
if not defined CMDER_ROOT (
    if defined ConEmuDir (
        for /f "delims=" %%i in ("%ConEmuDir%\..\..") do (
            set "CMDER_ROOT=%%~fi"
        )
    ) else (
        for /f "delims=" %%i in ("%~dp0\..") do (
            set "CMDER_ROOT=%%~fi"
        )
    )
)

:: Remove trailing '\' from %CMDER_ROOT%
if "%CMDER_ROOT:~-1%" == "\" SET "CMDER_ROOT=%CMDER_ROOT:~0,-1%"

:var_loop
    if "%~1" == "" (
        goto :start
    ) else if "%1"=="/v" (
        set verbose-output=1
    ) else if "%1"=="/d" (
        set debug-output=1
    ) else if "%1" == "/max_depth" (
        if "%~2" geq "1" if "%~2" leq "5" (
            set "max_depth=%~2"
            shift
        ) else (
            call :show_error '/max_depth' requires a number between 1 and 5!
            exit /b
        )
    ) else if "%1" == "/c" (
        if exist "%~2" (
            if not exist "%~2\bin" mkdir "%~2\bin"
            set "cmder_user_bin=%~2\bin"
            if not exist "%~2\config\profile.d" mkdir "%~2\config\profile.d"
            set "cmder_user_config=%~2\config"
            shift
        )
    ) else if "%1" == "/user_aliases" (
        if exist "%~2" (
            set "user-aliases=%~2"
            shift
        )
    ) else if "%1" == "/git_install_root" (
        if exist "%~2" (
            set "GIT_INSTALL_ROOT=%~2"
            shift
        ) else (
            call :show_error The Git install root folder "%2", you specified does not exist!
            exit /b
        )
    ) else if "%1" == "/home" (
        if exist "%~2" (
            set "HOME=%~2"
            shift
        ) else (
            call :show_error The home folder "%2", you specified does not exist!
            exit /b
        )
    ) else if "%1" == "/svn_ssh" (
        set SVN_SSH=%2
        shift
    )
    shift
goto var_loop

:start

call :debug-output init.bat - Env Var - CMDER_ROOT=%CMDER_ROOT%
call :debug-output init.bat - Env Var - debug-output=%debug-output%

if defined CMDER_USER_CONFIG (
    call :debug-output init.bat - CMDER IS ALSO USING INDIVIDUAL USER CONFIG FROM '%CMDER_USER_CONFIG%'!
)

:: Pick right version of clink
if "%PROCESSOR_ARCHITECTURE%"=="x86" (
    set architecture=86
    set architecture_bits=32
) else (
    set architecture=64
    set architecture_bits=64
)

:: Tell the user about the clink config files...
if defined "%CMDER_USER_CONFIG%\settings" if not exist "%CMDER_USER_CONFIG%\settings" (
    echo Generating clink initial settings in "%CMDER_USER_CONFIG%\settings"
    echo Additional *.lua files in "%CMDER_USER_CONFIG%" are loaded on startup.\

} else if not exist "%CMDER_ROOT%\config\settings" (
    echo Generating clink initial settings in "%CMDER_ROOT%\config\settings"
    echo Additional *.lua files in "%CMDER_ROOT%\config" are loaded on startup.
)

:: Run clink
if defined CMDER_USER_CONFIG (
    "%CMDER_ROOT%\vendor\clink\clink_x%architecture%.exe" inject --quiet --profile "%CMDER_USER_CONFIG%" --scripts "%CMDER_ROOT%\vendor"
) else (
    "%CMDER_ROOT%\vendor\clink\clink_x%architecture%.exe" inject --quiet --profile "%CMDER_ROOT%\config" --scripts "%CMDER_ROOT%\vendor"
)

:: Prepare for git-for-windows

:: I do not even know, copypasted from their .bat
set PLINK_PROTOCOL=ssh
if not defined TERM set TERM=cygwin

:: The idea:
:: * if the users points as to a specific git, use that
:: * test if a git is in path and if yes, use that
:: * last, use our vendored git
:: also check that we have a recent enough version of git by examining the version string
if defined GIT_INSTALL_ROOT (
    if exist "%GIT_INSTALL_ROOT%\cmd\git.exe" (goto :FOUND_GIT)
)

:: get the version information for vendored git binary
setlocal enabledelayedexpansion
call :read_version VENDORED "%CMDER_ROOT%\vendor\git-for-windows\cmd"

:: check if git is in path...
for /F "delims=" %%F in ('where git.exe 2^>nul') do (
    :: get the absolute path to the user provided git binary
    pushd %%~dpF
    set "test_dir=!CD!"
    popd

    :: get the version information for the user provided git binary
    call :read_version USER "!test_dir!"

    if !errorlevel! geq 0 (
        :: compare the user git version against the vendored version
        call :compare_versions USER VENDORED

        :: use the user provided git if its version is greater than, or equal to the vendored git
        if !errorlevel! geq 0 if exist "!test_dir:~0,-4!\cmd\git.exe" (
            set "GIT_INSTALL_ROOT=!test_dir:~0,-4!"
            set test_dir=
            goto :FOUND_GIT
        ) else if !errorlevel! geq 0 (
            set "GIT_INSTALL_ROOT=!test_dir!"
            set test_dir=
            goto :FOUND_GIT
        ) else (
            call :verbose-output Found old !GIT_VERSION_USER! in "!test_dir!", but not using...
            set test_dir=
        )
    ) else (

        :: if the user provided git executable is not found
        if !errorlevel! equ -255 (
            call :verbose-output No git at "!git_executable!" found.
            set test_dir=
        )

    )

)

:: our last hope: our own git...
:VENDORED_GIT
if exist "%CMDER_ROOT%\vendor\git-for-windows" (
    set "GIT_INSTALL_ROOT=%CMDER_ROOT%\vendor\git-for-windows"
    call :enhance_path "!GIT_INSTALL_ROOT!\cmd" 
) else (
    goto :NO_GIT
)

:FOUND_GIT
:: Add git to the path
if defined GIT_INSTALL_ROOT (
    rem add the unix commands at the end to not shadow windows commands like more
    if exist "!GIT_INSTALL_ROOT!\cmd\git.exe" call :enhance_path "!GIT_INSTALL_ROOT!\cmd" append
    if exist "!GIT_INSTALL_ROOT!\mingw32" (
        call :enhance_path "!GIT_INSTALL_ROOT!\mingw32" append
    ) else if exist "!GIT_INSTALL_ROOT!\mingw64" (
        call :enhance_path "!GIT_INSTALL_ROOT!\mingw64" append
    )
    if exist "!GIT_INSTALL_ROOT!\usr\bin" call :enhance_path "%GIT_INSTALL_ROOT%\usr\bin" append
    :: define SVN_SSH so we can use git svn with ssh svn repositories
    if not defined SVN_SSH set "SVN_SSH=%GIT_INSTALL_ROOT:\=\\%\\bin\\ssh.exe"
)

:NO_GIT
endlocal & set "PATH=%PATH%" & set "SVN_SSH=%SVN_SSH%" & set "GIT_INSTALL_ROOT=%GIT_INSTALL_ROOT%"
call :debug-output init.bat - Env Var - GIT_INSTALL_ROOT=%GIT_INSTALL_ROOT%

:: Enhance Path
call :enhance_path_recursive "%CMDER_ROOT%\bin" %max_depth%
if defined CMDER_USER_BIN (
  call :enhance_path "%CMDER_USER_BIN%" %max_depth%
)
call :enhance_path "%CMDER_ROOT%" append

:: Drop *.bat and *.cmd files into "%CMDER_ROOT%\config\profile.d"
:: to run them at startup.
call :run_profile_d "%CMDER_ROOT%\config\profile.d"
if defined CMDER_USER_CONFIG (
  call :run_profile_d "%CMDER_USER_CONFIG%\profile.d"
)

:: Allows user to override default aliases store using profile.d
:: scripts run above by setting the 'aliases' env variable.
::
:: Note: If overriding default aliases store file the aliases
:: must also be self executing, see '.\user-aliases.cmd.example',
:: and be in profile.d folder.
if not defined user-aliases (
  if defined CMDER_USER_CONFIG (
     set "user-aliases=%CMDER_USER_CONFIG%\user-aliases.cmd"
  ) else (
     set "user-aliases=%CMDER_ROOT%\config\user-aliases.cmd"
  )
)

:: The aliases environment variable is used by alias.bat to id
:: the default file to store new aliases in.
if not defined aliases (
  set "aliases=%user-aliases%"
)

:: Make sure we have a self-extracting user-aliases.cmd file
setlocal enabledelayedexpansion
if not exist "%user-aliases%" (
    echo Creating initial user-aliases store in "%user-aliases%"...
    copy "%CMDER_ROOT%\vendor\user-aliases.cmd.example" "%user-aliases%"
) else (
    type "%user-aliases%" | findstr /i ";= Add aliases below here" >nul
    if "!errorlevel!" == "1" (
        echo Creating initial user-aliases store in "%user-aliases%"...
        if defined CMDER_USER_CONFIG (
            copy "%user-aliases%" "%user-aliases%.old_format"
            copy "%CMDER_ROOT%\vendor\user-aliases.cmd.example" "%user-aliases%"
        ) else (
            copy "%user-aliases%" "%user-aliases%.old_format"
            copy "%CMDER_ROOT%\vendor\user-aliases.cmd.example" "%user-aliases%"
        )
    )
)

:: Update old 'user-aliases' to new self executing 'user-aliases.cmd'
if exist "%CMDER_ROOT%\config\aliases" (
  echo Updating old "%CMDER_ROOT%\config\aliases" to new format...
  type "%CMDER_ROOT%\config\aliases" >> "%user-aliases%" && del "%CMDER_ROOT%\config\aliases"
) else if exist "%user-aliases%.old_format" (
  echo Updating old "%user-aliases%" to new format...
  type "%user-aliases%.old_format" >> "%user-aliases%" && del "%user-aliases%.old_format"
)
endlocal

:: Add aliases to the environment
call "%user-aliases%"

:: See vendor\git-for-windows\README.portable for why we do this
:: Basically we need to execute this post-install.bat because we are
:: manually extracting the archive rather than executing the 7z sfx
if exist "%GIT_INSTALL_ROOT%\post-install.bat" (
    call :verbose-output Running Git for Windows one time Post Install....
    pushd "%GIT_INSTALL_ROOT%\"
    "%GIT_INSTALL_ROOT%\git-bash.exe" --no-needs-console --hide --no-cd --command=post-install.bat
    popd
)

:: Set home path
if not defined HOME set "HOME=%USERPROFILE%"
call :debug-output init.bat - Env Var - HOME=%HOME%

if exist "%CMDER_ROOT%\config\user-profile.cmd" (
    REM Create this file and place your own command in there
    call "%CMDER_ROOT%\config\user-profile.cmd"
)

if defined CMDER_USER_CONFIG if exist "%CMDER_USER_CONFIG%\user-profile.cmd" (
    REM Create this file and place your own command in there
    call "%CMDER_USER_CONFIG%\user-profile.cmd"
) else (
    echo Creating user startup file: "%CMDER_ROOT%\config\user-profile.cmd"
    (
echo :: use this file to run your own startup commands
echo :: use  in front of the command to prevent printing the command
echo.
echo :: uncomment this to have the ssh agent load when cmder starts
echo :: call "%%GIT_INSTALL_ROOT%%/cmd/start-ssh-agent.cmd"
echo.
echo :: uncomment this next two lines to use pageant as the ssh authentication agent
echo :: SET SSH_AUTH_SOCK=/tmp/.ssh-pageant-auth-sock
echo :: call "%%GIT_INSTALL_ROOT%%/cmd/start-ssh-pageant.cmd"
echo.
echo :: you can add your plugins to the cmder path like so
echo :: set "PATH=%%CMDER_ROOT%%\vendor\whatever;%%PATH%%"
echo.
echo @echo off
) >"%temp%\user-profile.tmp"

  if defined CMDER_USER_CONFIG (
    copy "%temp%\user-profile.tmp" "%CMDER_USER_CONFIG%\user-profile.cmd"
  ) else (
    copy "%temp%\user-profile.tmp" "%CMDER_ROOT%\config\user-profile.cmd"
  )
)

exit /b

::
:: sub-routines below here
::
:debug-output
    if %debug-output% gtr 0 echo %* & echo.
    exit /b

:verbose-output
    if %debug-output% gtr 0 (
      call :debug-output :verbose-output - %*
    ) else if %verbose-output% gtr 0 (
      echo %*
    )
    exit /b

:show_error
    echo ERROR: %*
    echo CMDER Shell Initialization has Failed!
    exit /b

:run_profile_d
  if not exist "%~1" (
    mkdir "%~1"
  )
  
  pushd "%~1"
  for /f "usebackq" %%x in ( `dir /b *.bat *.cmd 2^>nul` ) do (
    call :verbose-output Calling "%~1\%%x"...
    call "%~1\%%x"
  )
  popd
  exit /b

::
:: specific to git version comparing
::
:read_version
    :: clear the variables
    set GIT_VERSION_%~1=

    :: set the executable path
    set "git_executable=%~2\git.exe"
    call :debug-output :read_version - Env Var - git_executable=%git_executable%

    :: check if the executable actually exists
    if not exist "%git_executable%" (
        call :verbose-output "%git_executable%" does not exist!
        exit /b -255
    )

    :: get the git version in the provided directory
    for /F "tokens=1,2,3 usebackq" %%F in (`"%git_executable%" --version 2^>nul`) do (
        if "%%F %%G" == "git version" (
            set "GIT_VERSION_%~1=%%H"
            call :debug-output :read_version - Env Var - GIT_VERSION_%~1=%%H
        ) else (
            echo "git --version" returned an inproper version string!
            pause
            exit /b
        )
    )

    :: parse the returned string
    call :debug-output :read_version - Calling - :validate_version "%~1" !GIT_VERSION_%~1!
    call :validate_version "%~1" !GIT_VERSION_%~1!
    exit /b

:parse_version
    :: process a `x.x.x.xxxx.x` formatted string
    for /F "tokens=1-3* delims=.,-" %%A in ("%2") do (
        set "%~1_MAJOR=%%A"
        set "%~1_MINOR=%%B"
        set "%~1_PATCH=%%C"
        set "%~1_BUILD=%%D"
    )
    exit /b

:validate_version
    :: now parse the version information into the corresponding variables
    call :parse_version %~1 %~2

    :: ... and maybe display it, for debugging purposes.
    call :debug-output :validate_version - Found Git Version for %~1: !%~1_MAJOR!.!%~1_MINOR!.!%~1_PATCH!.!%~1_BUILD!
    exit /b

:compare_versions
    :: checks all major, minor, patch and build variables for the given arguments.
    :: whichever binary that has the most recent version will be used based on the return code.

    :: call :debug-output Comparing:
    :: call :debug-output %~1: !%~1_MAJOR!.!%~1_MINOR!.!%~1_PATCH!.!%~1_BUILD!
    :: call :debug-output %~2: !%~2_MAJOR!.!%~2_MINOR!.!%~2_PATCH!.!%~2_BUILD!

    if !%~1_MAJOR! GTR !%~2_MAJOR! (exit /b  1)
    if !%~1_MAJOR! LSS !%~2_MAJOR! (exit /b -1)

    if !%~1_MINOR! GTR !%~2_MINOR! (exit /b  1)
    if !%~1_MINOR! LSS !%~2_MINOR! (exit /b -1)

    if !%~1_PATCH! GTR !%~2_PATCH! (exit /b  1)
    if !%~1_PATCH! LSS !%~2_PATCH! (exit /b -1)

    if !%~1_BUILD! GTR !%~2_BUILD! (exit /b  1)
    if !%~1_BUILD! LSS !%~2_BUILD! (exit /b -1)

    :: looks like we have the same versions.
    exit /b 0

:enhance_path
    setlocal enabledelayedexpansion
    if "%~1" neq "" (
        if exist "%~1" (
            set "add_path=%~1"
        ) else (
            call :show_error :enhance_path - The path specified. "%~1", does not exist!
            exit 1
        )
    ) else (
        call :show_error You must specify a directory to add to the path!
        exit 1
    )
    
    if "%~2" neq "" if /i "%~2" == "append" (
        set "position=%~2"
    ) else (
        set "position="
    )

    set "find_query=%add_path%"
    set "find_query=%find_query:\=\\%"
    set "find_query=%find_query: =\ %"
    set found=0

    call :debug-output  :enhance_path "Env Var - find_query=%find_query%"
    echo "%PATH%"|findstr >nul /I /R ";%find_query%\"$"
    if "!ERRORLEVEL!" == "0" set found=1

    call :debug-output  :enhance_path "Env Var 1 - found=!found!"
    if "!found!" == "0" (
        echo "%PATH%"|findstr >nul /i /r ";%find_query%;"
        if "!ERRORLEVEL!" == "0" set found=1
        call :debug-output  :enhance_path "Env Var 2 - found=!found!"
    )

    if "%found%" == "0" (
        call :debug-output :enhance_path "BEFORE Env Var - PATH=!path!"
        if /i "%position%" == "append" (
            call :debug-output :enhance_path "Appending '%add_path%'"
            set "PATH=%PATH%;%add_path%"
        ) else (
            call :debug-output :enhance_path "Prepending '%add_path%'"
            set "PATH=%add_path%;%PATH%"
        )

        call :debug-output  :enhance_path "AFTER Env Var - PATH=!path!"
    )

    endlocal & set "PATH=%PATH%"
    exit /b

:enhance_path_recursive
::: ==============================================================================
:::enhance_path_recursive - Add a directory and subs to the path env variable if
:::                         required.
::: 
:::include: 
::: 
:::  call "$0"
:::
:::usage: 
::: 
:::  call "%~DP0lib_path" enhance_path_recursive "[dir_path]" [max_depth] [append]
::: 
:::required: 
::: 
:::  [dir_path] <in> Fully qualified directory path. Ex: "c:\bin"
::: 
:::dptions: 
::: 
:::  [max_depth] <in> Max recuse depth.  Default: 1
:::
:::  append      <in> Append instead rather than pre-pend "[dir_path]"
::: 
:::output:
::: 
:::  path       <out> Sets the path env variable if required. 
::: ------------------------------------------------------------------------------

    setlocal enabledelayedexpansion
    if "%~1" neq "" (
        set "add_path=%~1"
    ) else (
        call :directory to add to the path!"
        exit 1
    )
    
    if "%~2" gtr "1" (
        set "max_depth=%~2"
    ) else (
        set "max_depth=1"
    )

    if "%~3" neq "" if /i "%~3" == "append" (
        set "position=%~3"
    ) else (
        set "position="
    )

    if "%depth%" == "" set depth=0

    call :debug-output  :enhance_path_recursive "Env Var - add_path=%add_path%"
    call :debug-output  :enhance_path_recursive "Env Var - position=%position%"
    call :debug-output  :enhance_path_recursive "Env Var - max_depth=%max_depth%"

    if %max_depth% gtr !depth! (
        call :debug-output :enhance_path_recursive "Adding parent directory - '%add_path%'"
        call :enhance_path "%add_path%" %position%
        set /a "depth=!depth!+1"

        for /d %%i in ("%add_path%\*") do (
            call :debug-output  :enhance_path_recursive "Env Var BEFORE - depth=!depth!"
            call :debug-output :enhance_path_recursive "Found Subdirectory - '%%~fi'"
            call :enhance_path_recursive "%%~fi" %max_depth% %position%
            call :debug-output  :enhance_path_recursive "Env Var AFTER- depth=!depth!"
        )
    )

    endlocal & set "PATH=%PATH%"
    exit /b
