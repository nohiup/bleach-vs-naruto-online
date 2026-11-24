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

@echo off

if "%1"=="" (
	echo 标签为空！
	goto :EOF
)

goto %1

:NOT_EXIST
echo 文件不存在：%~2
goto :EOF

:UNDEFINE
echo 环境变量 %~2 未定义！
goto :EOF

:TITLE
title 打包 SHELL_Web
goto :EOF

:PACKAGE_START
echo 正在组装 SHELL_Web 的 out\web（bvn.swf + assets）...
goto :EOF

:OUT_INFO
echo 输出：%~2
goto :EOF

:COPY_FAIL
echo 复制失败：%~2
goto :EOF

:PACKAGE_SUCCESS
echo 组装成功：%~2
goto :EOF
