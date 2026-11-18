@echo off
rem Virtual Desktop's VR route is built on DirectX, so the game draws with DirectX 12 for it (v1.19.4).
rem Quest Link (and anything else) keeps the standard Vulkan graphics.
reg query "HKLM\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime 2>nul | find /i "VirtualDesktop" >nul
if not errorlevel 1 goto vd
start "" "%~dp0SmartMotionFlight.exe" --xr-mode on -- --vr --xr
goto :eof
:vd
start "" "%~dp0SmartMotionFlight.exe" --rendering-driver d3d12 --xr-mode on -- --vr --xr --d3d12_tried
