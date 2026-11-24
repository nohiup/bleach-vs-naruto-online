::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::
:: Copyright (C) 2021-2026, 5DPLAY Game Studio
:: All rights reserved.
::
:: This program is free software: you can redistribute it and/or modify
:: it under the terms of the GNU General Public License as published by
:: the Free Software Foundation, either version 3 of the License, or
:: (at your option) any later version.
::
:: This program is distributed in the hope that it will be useful,
:: but WITHOUT ANY WARRANTY; without even the implied warranty of
:: MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
:: GNU General Public License for more details.
::
:: You should have received a copy of the GNU General Public License
:: along with this program.  If not, see <http://www.gnu.org/licenses/>.
::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::
:: 用途
::   把浏览器壳 SHELL_Web 的 bvn.swf 与运行时素材组装为 out\web，供静态站点直接托管。
::   不依赖 AIR / adt；素材来自 shared\assets\assets（排除仅 AIR 使用的 mods 目录）。
::
:: 用法
::   tools\script\package_shell_web.bat
::   （build.bat 与 VSCode 任务会先编译 SHELL_Web）
::
:: 前置条件
::   - 已生成 out\production\SHELL_Web\bvn.swf
::   - shared\assets\assets 存在
::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

@echo off
setlocal enabledelayedexpansion

set "BAT_HOME=%~dp0"
set "FUNC_COMMON=%BAT_HOME%func\common.bat"
call "%FUNC_COMMON%" INIT_LANG "%~n0"
call "%FUNC_COMMON%" ECHO_LANG :TITLE ""

set "REPO_ROOT=%BAT_HOME%..\.."
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"

set "OUT_SWF=%REPO_ROOT%\out\production\SHELL_Web\bvn.swf"
set "ASSETS_DIR=%REPO_ROOT%\shared\assets\assets"
set "OUT_WEB=%REPO_ROOT%\out\web"
set "OUT_WEB_SWF=%OUT_WEB%\bvn.swf"
set "OUT_WEB_ASSETS=%OUT_WEB%\assets"

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: 1) 输入校验
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call "%FUNC_COMMON%" EXIST "%OUT_SWF%"
if errorlevel 1 goto END
call "%FUNC_COMMON%" EXIST "%ASSETS_DIR%"
if errorlevel 1 goto END

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: 2) 组装 out\web（仅替换 bvn.swf 与 assets，不动目录内其它文件）
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call "%FUNC_COMMON%" ECHO_LANG :PACKAGE_START ""
call "%FUNC_COMMON%" ECHO_LANG :OUT_INFO "%OUT_WEB%"

if not exist "%OUT_WEB%" mkdir "%OUT_WEB%"
if exist "%OUT_WEB_ASSETS%" rd /s /q "%OUT_WEB_ASSETS%"

copy /Y "%OUT_SWF%" "%OUT_WEB_SWF%" >nul
if errorlevel 1 (
	call "%FUNC_COMMON%" ECHO_LANG :COPY_FAIL "bvn.swf"
	goto END
)

:: robocopy 返回码 0-7 均表示成功
robocopy "%ASSETS_DIR%" "%OUT_WEB_ASSETS%" /E /XD mods /NFL /NDL /NJH /NJS /NP >nul
if !errorlevel! geq 8 (
	call "%FUNC_COMMON%" ECHO_LANG :COPY_FAIL "assets"
	goto END
)

call "%FUNC_COMMON%" ECHO_LANG :PACKAGE_SUCCESS "%OUT_WEB%"
exit /b 0

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:END
exit /b 1
