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
	echo 태그가 비어있습니다!
	goto :EOF
)

goto %1

:NOT_EXIST
echo 파일이 존재하지 않습니다: %~2
goto :EOF

:UNDEFINE
echo 환경 변수 %~2가 정의되지 않았습니다!
goto :EOF

:TITLE
title SHELL_Web 패키지
goto :EOF

:PACKAGE_START
echo SHELL_Web out\web (bvn.swf + assets) 조립 중...
goto :EOF

:OUT_INFO
echo 출력: %~2
goto :EOF

:COPY_FAIL
echo 복사 실패: %~2
goto :EOF

:PACKAGE_SUCCESS
echo 조립 성공: %~2
goto :EOF
