
;--- Win32 functions of Windows 2000/XP that DKRNL32 did not have, as far as
;--- Far Manager 2 imports them. GetProcessHeaps, GlobalMemoryStatusEx,
;--- GetLogicalDriveStringsW, FindFirstChangeNotificationW, GetCPInfoExW and
;--- CopyFileExW work through existing functions; the others are stubs that
;--- fail with ERROR_CALL_NOT_IMPLEMENTED.

	.386
if ?FLAT
	.MODEL FLAT, stdcall
else
	.MODEL SMALL, stdcall
endif
	option proc:private
	option casemap:none

	include winbase.inc
	include dkrnl32.inc
	include macros.inc

FindFirstChangeNotificationA proto stdcall :ptr BYTE, :DWORD, :DWORD
GetLogicalDriveStringsA proto stdcall :DWORD, :ptr BYTE
GetCPInfo proto stdcall :DWORD, :ptr
CopyFileW proto stdcall :ptr WORD, :ptr WORD, :DWORD

MEMORYSTATUSEX struct
dwLength                dd ?
dwMemoryLoad            dd ?
ullTotalPhys            dq ?
ullAvailPhys            dq ?
ullTotalPageFile        dq ?
ullAvailPageFile        dq ?
ullTotalVirtual         dq ?
ullAvailVirtual         dq ?
ullAvailExtendedVirtual dq ?
MEMORYSTATUSEX ends

;--- a function that fails: SetLastError(ERROR_CALL_NOT_IMPLEMENTED), eax = result

@unsupp macro name, result, params:VARARG
name proc public params
	invoke SetLastError, ERROR_CALL_NOT_IMPLEMENTED
	mov eax, result
	ret
	align 4
name endp
	endm

	.CODE

GetProcessHeaps proc public nHeaps:DWORD, pHeaps:ptr DWORD

	invoke GetProcessHeap
	.if (eax)
		.if (nHeaps)
			mov ecx, pHeaps
			mov [ecx], eax
		.endif
		mov eax, 1
	.endif
	@strace <"GetProcessHeaps(", nHeaps, ", ", pHeaps, ")=", eax>
	ret
	align 4

GetProcessHeaps endp

GlobalMemoryStatusEx proc public uses esi edi pMemEx:ptr MEMORYSTATUSEX

local ms:MEMORYSTATUS

	mov ms.dwLength, sizeof MEMORYSTATUS
	invoke GlobalMemoryStatus, addr ms
	mov edi, pMemEx
	mov eax, ms.dwMemoryLoad
	mov [edi].MEMORYSTATUSEX.dwMemoryLoad, eax
	lea esi, ms.dwTotalPhys
	lea edi, [edi].MEMORYSTATUSEX.ullTotalPhys
	mov ecx, 6
	.repeat
		lodsd
		stosd
		xor eax, eax
		stosd
		dec ecx
	.until (ecx == 0)
	stosd		;ullAvailExtendedVirtual = 0
	stosd
	mov eax, 1
	@strace <"GlobalMemoryStatusEx(", pMemEx, ")=", eax>
	ret
	align 4

GlobalMemoryStatusEx endp

;--- returns the length without the final 0, or the size needed if the
;--- buffer is too small

GetLogicalDriveStringsW proc public nBufferLength:DWORD, lpBuffer:ptr WORD

local buf[128]:byte

	invoke GetLogicalDriveStringsA, sizeof buf, addr buf
	.if (eax && eax < sizeof buf)
		lea ecx, [eax+1]
		.if (ecx > nBufferLength || !lpBuffer)
			mov eax, ecx
		.else
			push eax
			push esi
			push edi
			lea esi, buf
			mov edi, lpBuffer
			.repeat
				movzx edx, byte ptr [esi]
				mov [edi], dx
				inc esi
				add edi, 2
				dec ecx
			.until (ecx == 0)
			pop edi
			pop esi
			pop eax
		.endif
	.endif
	@strace <"GetLogicalDriveStringsW(", nBufferLength, ", ", lpBuffer, ")=", eax>
	ret
	align 4

GetLogicalDriveStringsW endp

FindFirstChangeNotificationW proc public lpPathName:ptr WORD, bWatchSubtree:DWORD, dwNotifyFilter:DWORD

	mov eax, lpPathName
	invoke ConvertWStr
	invoke FindFirstChangeNotificationA, eax, bWatchSubtree, dwNotifyFilter
	@strace <"FindFirstChangeNotificationW(", lpPathName, ", ", bWatchSubtree, ", ", dwNotifyFilter, ")=", eax>
	ret
	align 4

FindFirstChangeNotificationW endp

;--- CPINFOEXW: CPINFO (18 bytes), UnicodeDefaultChar at 18, CodePage at 20,
;--- CodePageName (MAX_PATH WCHARs) at 24. The name is the number.

GetCPInfoExW proc public uses ebx edi CodePage:DWORD, dwFlags:DWORD, lpCPInfoEx:ptr

	mov eax, CodePage
	.if (eax == CP_ACP)
		invoke GetACP
	.elseif (eax == CP_OEMCP)
		invoke GetOEMCP
	.endif
	mov CodePage, eax
	invoke GetCPInfo, eax, lpCPInfoEx
	.if (eax)
		mov edi, lpCPInfoEx
		mov word ptr [edi+18], '?'
		mov eax, CodePage
		mov [edi+20], eax
		add edi, 24
		mov ebx, 10
		xor ecx, ecx
		.repeat
			xor edx, edx
			div ebx
			push edx
			inc ecx
		.until (eax == 0)
		.repeat
			pop eax
			add eax, '0'
			stosw
			dec ecx
		.until (ecx == 0)
		xor eax, eax
		stosw
		inc eax
	.endif
	@strace <"GetCPInfoExW(", CodePage, ", ", dwFlags, ", ", lpCPInfoEx, ")=", eax>
	ret
	align 4

GetCPInfoExW endp

;--- progress routine and cancel flag are not supported

CopyFileExW proc public lpExisting:ptr WORD, lpNew:ptr WORD, lpProgress:DWORD, lpData:DWORD, pbCancel:DWORD, dwCopyFlags:DWORD

	mov eax, dwCopyFlags
	and eax, 1		;COPY_FILE_FAIL_IF_EXISTS
	invoke CopyFileW, lpExisting, lpNew, eax
	@strace <"CopyFileExW(", lpExisting, ", ", lpNew, ", ", dwCopyFlags, ")=", eax>
	ret
	align 4

CopyFileExW endp

	@unsupp CreateHardLinkW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp CreateNamedPipeW, -1, p1:DWORD, p2:DWORD, p3:DWORD, p4:DWORD, p5:DWORD, p6:DWORD, p7:DWORD, p8:DWORD
	@unsupp DefineDosDeviceW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp EnumSystemCodePagesW, 0, p1:DWORD, p2:DWORD
	@unsupp FindFirstVolumeW, -1, p1:DWORD, p2:DWORD
	@unsupp FindNextVolumeW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp FindVolumeClose, 0, p1:DWORD
	@unsupp GetCalendarInfoW, 0, p1:DWORD, p2:DWORD, p3:DWORD, p4:DWORD, p5:DWORD, p6:DWORD
	@unsupp GetCompressedFileSizeW, -1, p1:DWORD, p2:DWORD
	@unsupp GetComputerNameExW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp GetConsoleAliasW, 0, p1:DWORD, p2:DWORD, p3:DWORD, p4:DWORD
	@unsupp GetConsoleDisplayMode, 0, p1:DWORD
	@unsupp GetConsoleWindow, 0
	@unsupp GetVolumeNameForVolumeMountPointW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp HeapQueryInformation, 0, p1:DWORD, p2:DWORD, p3:DWORD, p4:DWORD, p5:DWORD
	@unsupp QueryDosDeviceW, 0, p1:DWORD, p2:DWORD, p3:DWORD
	@unsupp SetThreadExecutionState, 0, p1:DWORD
	@unsupp SetVolumeMountPointW, 0, p1:DWORD, p2:DWORD
	@unsupp WaitNamedPipeW, 0, p1:DWORD, p2:DWORD

	end
