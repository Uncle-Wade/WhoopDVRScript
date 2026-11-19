@echo off
setlocal EnableExtensions

REM ========ANALOG VIDEO FIXER SCRIPT - WGD======
REM >>> TUNE 1: COLOR AND CONTRAST <<<
set "CONTRAST=1.0"
set "GAMMA=1.00"
set "VIBRANCE=0.15"
set "SATURATION=1.00"


REM >>> TUNE 2: SHARPENING <<<
REM Light, plain 5x5 unsharp on brightness only. No masks, no smoothing.
set "SHARPEN=0.45"
rem ^^^ 0 = off, 0.3 = subtle, 0.6 = more punch  (6.5.1 was 7x7 0.9 = too harsh)

REM >>> TUNE 3: RAINBOW / COLOR NOISE CLEANUP <<<
REM Chroma-only median (sensor false color) + light chroma blur + chromanr.
REM Set slightly light on purpose: a few rainbows survive, colors stay real.
set "RAINBOW_RADIUS=1.7"
set "RAINBOW_BLUR=1.1"
rem ^^^ 6.5.0 was radius 2 / blur 1.2 (removes all rainbows, washes leaves out)
rem ^^ 6.5.1 had 1/0.8. i incresed slightly
set "CHROMA_THRESHOLD=12"

REM >>> TUNE 4: COLOR NOISE REDUCTION (temporal, color only) <<<
REM Averages only the COLOR channels over neighbouring frames. This is part of
REM the rainbow removal. Brightness is never time-averaged (no smearing).
set "COLOR_DENOISE=7"
rem ^^^ 0 = off, 5 = lighter, 10 = stronger

REM >>> TUNE 5: CONSOLE OUTPUT (useful for debug) <<<
set "LOGLEVEL=fatal"

REM >>> TUNE 6: DAMAGED FRAMES <<<
set "DISCARD_CORRUPT=1"

REM >>> TUNE 7: OUTPUT SIZE / COMPATIBILITY <<<
set "PREFER_HEVC=1"
rem #### larger CRF number means more compression
set "HEVC_CRF=27"
rem ^^^ 26 = more detail, bigger. 28-29 = smaller, more compressed-looking
set "HEVC_MAXRATE=12000"
set "HEVC_BUFSIZE=24000"
rem ^^^ bitrate cap (kbps). 6500 starved busy scenes (leaves at 60fps) and caused the
rem     "over-compressed" smear no matter what CRF was. Lower it only if files are too big.
set "HEVC_PRESET=slow"
rem ^^^ fast, slow, and medium are options
set "H264_CRF=23"
set "H264_PRESET=medium"

REM >>> TUNE 8: PLAYBACK <<<
REM DVR files say "square pixels", so players show 720x480 as 3:2. The Air cam
REM is 16:9, so that squeezes it. This fixes it as a tag only: all
REM 720x480 pixels are kept, players show it at 853x480.
set "ASPECT=16:9"
rem ^^^ 16:9 for 16:9 cameras, 4:3 for 4:3 cameras, or keep
REM A tiny silent audio track stops Telegram etc. treating the clip as a GIF.
set "SILENT_AUDIO=1"
REM Blank = keep 60fps. 30000/1001 = 30fps, about 30%% smaller files.
set "OUT_FPS="


REM ======below is the  block that makes a nice progress report while script is running==========
set "ETA_PS=$d=0.0;[void][double]::TryParse($env:DUR,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d);$t=0.0;$fr='0';$end=$false;$sw=[Diagnostics.Stopwatch]::StartNew();while(($l=[Console]::In.ReadLine()) -ne $null){if($l -like 'out_time_us=*'){$v=$l.Substring(12);if($v -match '^\d+$'){$t=[double]$v/1e6}}elseif($l -like 'frame=*'){$fr=$l.Substring(6)}elseif($l -eq 'progress=end'){$end=$true};if($l -like 'progress=*'){$el=$sw.Elapsed.TotalSeconds;$sp=if($el -gt 0 -and $t -gt 0){('{0:N3}' -f ($t/$el))+'x'}else{'0x'};$m='frame '+$fr+' | '+[math]::Round($t,1)+'s | '+$sp;if($d -gt 0 -and $t -gt 1){$p=[math]::Min(100,$t/$d*100);$eta=[TimeSpan]::FromSeconds([math]::Max(0,($d-$t)*$el/$t));$m=('{0:N1}' -f $p)+[char]37+' | '+$m+' | ETA '+$eta.ToString('hh\:mm\:ss')};[Console]::Write([string][char]13+$m.PadRight(78))}};[Console]::WriteLine();exit 0"

REM ============================================================
REM  FIND FFMPEG (portable first, then system PATH)
REM  Put ffmpeg.exe + ffprobe.exe beside this script, or in a
REM  "bin" or "ffmpeg\bin" subfolder. No install/admin needed.
REM ============================================================

set "FFMPEG="
set "FFPROBE="
for %%P in ("%~dp0" "%~dp0bin\" "%~dp0ffmpeg\bin\") do (
    if not defined FFMPEG if exist "%%~Pffmpeg.exe" (
        set "FFMPEG=%%~Pffmpeg.exe"
        set "FFPROBE=%%~Pffprobe.exe"
    )
)

if not defined FFMPEG (
    for /f "delims=" %%X in ('where ffmpeg 2^>nul') do if not defined FFMPEG set "FFMPEG=%%X"
    for /f "delims=" %%X in ('where ffprobe 2^>nul') do if not defined FFPROBE set "FFPROBE=%%X"
)

if not defined FFMPEG (
    echo ERROR: FFmpeg was not found.
    echo Put ffmpeg.exe and ffprobe.exe in the same folder as this script:
    echo   %~dp0
    pause
    exit /b 1
)
if not exist "%FFPROBE%" (
    echo WARNING: ffprobe.exe not found - progress percent/ETA will be unavailable.
    set "FFPROBE="
)
echo Using FFmpeg: "%FFMPEG%"

set "AWAKE_LOCK=%TEMP%\dvr_cleaner_awake_%RANDOM%.lock"
echo.>"%AWAKE_LOCK%"
set "AWAKE_PS=Add-Type -Namespace W -Name K -MemberDefinition ('[DllImport('+[char]34+'kernel32.dll'+[char]34+')] public static extern uint SetThreadExecutionState(uint f);'); [void][W.K]::SetThreadExecutionState(2147483649); $pp=(Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID)).ParentProcessId; while((Test-Path $env:AWAKE_LOCK) -and (Get-Process -Id $pp -ErrorAction SilentlyContinue)){Start-Sleep 2}"
start "" /b powershell -NoProfile -WindowStyle Hidden -Command "%AWAKE_PS%"

REM ============================================================
REM  INPUT FLAGS
REM ============================================================

set "INFLAGS=-fflags +genpts -err_detect ignore_err"
if "%DISCARD_CORRUPT%"=="1" set "INFLAGS=-fflags +discardcorrupt+genpts -err_detect ignore_err"

REM ============================================================
REM  CHOOSE THE ENCODER
REM ============================================================

if "%PREFER_HEVC%"=="1" (
    "%FFMPEG%" -hide_banner -encoders 2>nul | findstr /i /c:"libx265" >nul
    if not errorlevel 1 (
        set "VCODEC=libx265"
        set "ENCODE_ARGS=-preset %HEVC_PRESET% -crf %HEVC_CRF% -tag:v hvc1 -profile:v main -x265-params log-level=error:aq-mode=3:psy-rd=1.0:no-sao=1:deblock=-1,-1:vbv-maxrate=%HEVC_MAXRATE%:vbv-bufsize=%HEVC_BUFSIZE%:pools=*"
        goto :CODEC_READY
    )
)

set "VCODEC=libx264"
set "ENCODE_ARGS=-preset %H264_PRESET% -crf %H264_CRF% -profile:v main"

:CODEC_READY

REM TO INVESTIGATE FOR USAGE: photosensitivity, normalize
REM ============================================================
REM  VIDEO FILTERS (not sure of order, maybe flip the [#] ones)
REM  Order: even dims > Chroma denoise [#]  > temporal denoise [#]> sharpen > other color adjustments > vibrance
REM  
REM ============================================================ 
set "DNF="
if not "%COLOR_DENOISE%"=="0" set "DNF=fftdnoiz=sigma=%COLOR_DENOISE%:prev=1:next=1:planes=6,"
set "SHARP="
if not "%SHARPEN%"=="0" set "SHARP=unsharp=5:5:%SHARPEN%:3:3:0,"
set "FPSF="
if defined OUT_FPS set "FPSF=,fps=%OUT_FPS%"
set "FILTERS=scale=trunc(iw/2)*2:trunc(ih/2)*2,median=radius=%RAINBOW_RADIUS%:planes=6,gblur=sigma=%RAINBOW_BLUR%:sigmaV=0.5:planes=6,chromanr=thres=%CHROMA_THRESHOLD%:sizew=3:sizeh=3,%DNF%%SHARP%eq=contrast=%CONTRAST%:brightness=0:saturation=%SATURATION%:gamma=%GAMMA%,vibrance=intensity=%VIBRANCE%%FPSF%"

set "OUT_ARGS="
if /i not "%ASPECT%"=="keep" set "OUT_ARGS=-aspect %ASPECT%"
set "AUDIO_IN="
set "AUDIO_ARGS=-an"
if "%SILENT_AUDIO%"=="1" (
    set "AUDIO_IN=-f lavfi -i anullsrc=channel_layout=mono:sample_rate=22050"
    set "AUDIO_ARGS=-map 1:a -c:a aac -b:a 16k -shortest"
)

echo.
echo ==========================================
echo  FPV DVR CLEANUP
echo ==========================================
echo Encoder: %VCODEC%
echo Filters: gentle denoise + chroma cleanup + analog curves
echo Contrast: %CONTRAST%
echo Gamma: %GAMMA%
echo Vibrance: %VIBRANCE%
echo Sharpening: %SHARPEN%   Color denoise: %COLOR_DENOISE%   Rainbow: radius %RAINBOW_RADIUS% blur %RAINBOW_BLUR%
echo Quality: CRF %HEVC_CRF%   Aspect: %ASPECT%   FPS: %OUT_FPS%
echo Damaged frames: discard=%DISCARD_CORRUPT% ^(0 = keep^)
echo Silent audio track: %SILENT_AUDIO%
echo ==========================================
echo.

if "%~1"=="" goto :FOLDER_MODE

:ARG_LOOP
if "%~1"=="" goto :DONE
call :PROCESS "%~f1"
shift
goto :ARG_LOOP

:FOLDER_MODE
set "FOUND_ANY="
for %%E in (mov avi mp4 mkv) do (
    for %%F in ("%~dp0*.%%E") do call :FOLDER_ITEM "%%~fF"
)
if not defined FOUND_ANY echo No video files found beside this script.
goto :DONE

:FOLDER_ITEM
set "NAME=%~n1"
if /i "%NAME:~-4%"=="-opt" exit /b 0
set "FOUND_ANY=1"
call :PROCESS "%~f1"
exit /b 0

REM ============================================================
REM  PROCESS ONE FILE
REM ============================================================

:PROCESS
set "INPUT=%~1"
set "OUTPUT=%~dpn1-opt.mp4"

if not exist "%INPUT%" (
    echo Skipping missing file: "%INPUT%"
    exit /b 1
)

if exist "%OUTPUT%" (
    echo Skipping; output already exists: "%OUTPUT%"
    exit /b 0
)

echo.
echo Processing: "%INPUT%"
echo Output:     "%OUTPUT%"

"%FFMPEG%" -hide_banner -i "%INPUT%" 2>&1 | findstr /c:"Input #" /c:"Duration:" /c:"Stream #"
echo.

set "DURATION="
if defined FFPROBE for /f "delims=" %%D in ('call "%FFPROBE%" -v error -show_entries format^=duration -of csv^=p^=0 "%INPUT%" 2^>nul') do set "DURATION=%%D"
set "DUR=%DURATION%"

"%FFMPEG%" -hide_banner -loglevel %LOGLEVEL% -nostats -progress pipe:1 -stats_period 1 %INFLAGS% -i "%INPUT%" %AUDIO_IN% -map 0:v:0 %AUDIO_ARGS% -sn -dn -vf "%FILTERS%" -fps_mode cfr -threads 0 -c:v %VCODEC% %ENCODE_ARGS% -pix_fmt yuv420p %OUT_ARGS% -movflags +faststart -n "%OUTPUT%" | powershell -NoProfile -Command "%ETA_PS%"

if not "%errorlevel%"=="0" (
    echo ERROR converting: "%INPUT%"
    echo Set LOGLEVEL=error near the top of this script to see why.
    if exist "%OUTPUT%" del "%OUTPUT%" >nul 2>&1
    exit /b 1
)

echo Finished: "%OUTPUT%"
exit /b 0

:DONE
del "%AWAKE_LOCK%" >nul 2>&1
echo.
echo Processing attempts complete.
echo Review the output clips before deleting originals.
pause
exit /b 0