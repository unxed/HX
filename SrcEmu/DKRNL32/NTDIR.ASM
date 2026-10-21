
;--- NT directory access, as Far Manager 2 and 3 use it:
;--- - CreateFileA of a directory with FILE_FLAG_BACKUP_SEMANTICS gives a
;---   directory object (_OpenDirHandle, called from CreateFileA);
;--- - NtQueryDirectoryFile (FileBothDirectoryInformation only) lists such a
;---   directory through FindFirstFileA/FindNextFileA. The position is the
;---   number of entries already returned, so no find handle stays open
;---   between calls (CloseHandle just frees the object);
;--- - RtlNtStatusToDosError, RtlGetLastNtStatus, NtClose.

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

SYNCTYPE_DIR	textequ <"DIR ">

DIROBJ struct
		SYNCOBJECT <>
dwNext	dd ?			;entries returned so far
bMask	db ?			;1 = szMask is set
szPath	db 260 dup (?)	;directory, no trailing backslash (except "X:\")
szMask	db 260 dup (?)
DIROBJ ends

STATUS_SUCCESS				equ 0
STATUS_BUFFER_OVERFLOW		equ 80000005h
STATUS_NO_MORE_FILES		equ 80000006h
STATUS_NOT_IMPLEMENTED		equ 0C0000002h
STATUS_INVALID_INFO_CLASS	equ 0C0000003h
STATUS_INVALID_HANDLE		equ 0C0000008h
STATUS_INVALID_PARAMETER	equ 0C000000Dh
STATUS_NO_SUCH_FILE			equ 0C000000Fh
STATUS_ACCESS_DENIED		equ 0C0000022h
STATUS_OBJECT_NAME_NOT_FOUND equ 0C0000034h
STATUS_OBJECT_PATH_NOT_FOUND equ 0C000003Ah

FileBothDirectoryInformation equ 3

;--- FILE_BOTH_DIR_INFORMATION: fixed part is 94 bytes, then the name

FBDI_NAME	equ 94

	.CONST

;--- NTSTATUS -> Win32 error

stattab label dword
	dd STATUS_SUCCESS, 0
	dd STATUS_BUFFER_OVERFLOW, 234			;ERROR_MORE_DATA
	dd STATUS_NO_MORE_FILES, 18				;ERROR_NO_MORE_FILES
	dd STATUS_NOT_IMPLEMENTED, 1			;ERROR_INVALID_FUNCTION
	dd STATUS_INVALID_INFO_CLASS, 87		;ERROR_INVALID_PARAMETER
	dd STATUS_INVALID_HANDLE, 6				;ERROR_INVALID_HANDLE
	dd STATUS_INVALID_PARAMETER, 87
	dd STATUS_NO_SUCH_FILE, 2				;ERROR_FILE_NOT_FOUND
	dd STATUS_ACCESS_DENIED, 5				;ERROR_ACCESS_DENIED
	dd STATUS_OBJECT_NAME_NOT_FOUND, 2
	dd STATUS_OBJECT_PATH_NOT_FOUND, 3		;ERROR_PATH_NOT_FOUND
stattabend label dword

	.CODE

;--- returns a directory object, or -1 if pszPath is not a directory

_OpenDirHandle proc public uses esi edi pszPath:ptr BYTE

	invoke lstrlenA, pszPath
	.if (eax == 0 || eax >= 260)
		jmp notdir
	.endif
	mov esi, eax
	invoke KernelHeapAlloc, sizeof DIROBJ
	.if (!eax)
		jmp notdir
	.endif
	mov edi, eax
	mov [edi].DIROBJ.dwType, SYNCTYPE_DIR
	mov [edi].DIROBJ.dwNext, 0
	mov [edi].DIROBJ.bMask, 0
	lea eax, [edi].DIROBJ.szPath
	invoke lstrcpynA, eax, pszPath, 260
	lea edx, [edi].DIROBJ.szPath
	.if (esi > 3)
		mov al, [edx+esi-1]
		.if (al == '\' || al == '/')
			mov byte ptr [edx+esi-1], 0
		.endif
	.endif
	.if (esi <= 3 && byte ptr [edx+1] == ':')
		jmp isdir				;"X:\" or "X:"
	.endif
	invoke GetFileAttributesA, edx
	.if (eax == -1 || !(eax & FILE_ATTRIBUTE_DIRECTORY))
		invoke KernelHeapFree, edi
		jmp notdir
	.endif
isdir:
	mov eax, edi
	@strace <"_OpenDirHandle(", pszPath, ")=", eax>
	ret
notdir:
	or eax, -1
	ret
	align 4

_OpenDirHandle endp

NtQueryDirectoryFile proc public uses ebx esi edi hFile:dword, hEvent:dword, pApc:dword, pApcCtx:dword,
		pIosb:ptr, pInfo:ptr, dwLength:dword, dwClass:dword, bSingle:dword, pName:ptr, bRestart:dword

local wfd:WIN32_FIND_DATAA
local hFind:dword
local dwIdx:dword
local pLast:dword
local status:dword
local szSpec[524]:byte

	mov edi, pInfo
	mov pLast, 0
	mov ebx, hFile
	mov status, STATUS_INVALID_HANDLE
	.if (ebx < 10000h || ebx >= -30)
		jmp setiosb
	.endif
	.if ([ebx].DIROBJ.dwType != SYNCTYPE_DIR)
		jmp setiosb
	.endif
	mov status, STATUS_INVALID_INFO_CLASS
	.if (dwClass != FileBothDirectoryInformation)
		jmp setiosb
	.endif

;--- the mask is taken on the first call (or on restart)

	.if (byte ptr bRestart)
		mov [ebx].DIROBJ.dwNext, 0
		mov [ebx].DIROBJ.bMask, 0
	.endif
	.if (![ebx].DIROBJ.bMask)
		mov eax, pName
		lea edi, [ebx].DIROBJ.szMask
		.if (eax)
			movzx ecx, word ptr [eax]	;UNICODE_STRING.Length (bytes)
			shr ecx, 1
			.if (ecx > 259)
				mov ecx, 259
			.endif
			mov esi, [eax+4]			;UNICODE_STRING.Buffer
			.while (ecx)
				lodsw
				stosb
				dec ecx
			.endw
			mov byte ptr [edi], 0
		.else
			mov dword ptr [edi], '*'
		.endif
		mov [ebx].DIROBJ.bMask, 1
		mov edi, pInfo
	.endif

;--- spec = path + "\" + mask

	lea edx, [ebx].DIROBJ.szPath
	invoke lstrcpyA, addr szSpec, edx
	invoke lstrlenA, addr szSpec
	.if (eax && byte ptr szSpec[eax-1] != '\')
		mov word ptr szSpec[eax], '\'
	.endif
	lea edx, [ebx].DIROBJ.szMask
	invoke lstrcatA, addr szSpec, edx

	invoke FindFirstFileA, addr szSpec, addr wfd
	mov hFind, eax
	.if (eax == -1)
		mov status, STATUS_NO_MORE_FILES
		.if ([ebx].DIROBJ.dwNext == 0)
			mov status, STATUS_NO_SUCH_FILE
		.endif
		jmp setiosb
	.endif
	mov dwIdx, 0
	.while (1)
		mov eax, dwIdx
		.break .if (eax >= [ebx].DIROBJ.dwNext)
		invoke FindNextFileA, hFind, addr wfd
		.if (!eax)
			invoke FindClose, hFind
			mov status, STATUS_NO_MORE_FILES
			jmp setiosb
		.endif
		inc dwIdx
	.endw

	mov status, STATUS_SUCCESS
	.while (1)
		invoke lstrlenA, addr wfd.cFileName
		mov esi, eax			;name length (chars)
		mov edx, pInfo
		add edx, dwLength
		sub edx, edi			;bytes left
		lea eax, [esi*2+FBDI_NAME]
		.if (eax > edx)
			.if (!pLast)
				mov status, STATUS_BUFFER_OVERFLOW
			.endif
			.break
		.endif
		.if (pLast)
			mov eax, edi
			sub eax, pLast
			mov edx, pLast
			mov [edx], eax		;NextEntryOffset of the previous entry
		.endif
		mov pLast, edi
		push edi
		xor eax, eax
		mov ecx, FBDI_NAME/2
		rep stosw
		pop edi
		mov eax, dword ptr wfd.ftCreationTime
		mov [edi+8], eax
		mov eax, dword ptr wfd.ftCreationTime+4
		mov [edi+12], eax
		mov eax, dword ptr wfd.ftLastAccessTime
		mov [edi+16], eax
		mov eax, dword ptr wfd.ftLastAccessTime+4
		mov [edi+20], eax
		mov eax, dword ptr wfd.ftLastWriteTime
		mov [edi+24], eax
		mov [edi+32], eax		;ChangeTime
		mov eax, dword ptr wfd.ftLastWriteTime+4
		mov [edi+28], eax
		mov [edi+36], eax
		mov eax, wfd.nFileSizeLow
		mov [edi+40], eax		;EndOfFile
		mov [edi+48], eax		;AllocationSize
		mov eax, wfd.nFileSizeHigh
		mov [edi+44], eax
		mov [edi+52], eax
		mov eax, wfd.dwFileAttributes
		mov [edi+56], eax
		lea eax, [esi*2]
		mov [edi+60], eax		;FileNameLength
		push esi
		push edi
		lea esi, wfd.cAlternateFileName
		add edi, 70				;ShortName
		xor ecx, ecx
		.while (ecx < 12)
			lodsb
			.break .if (!al)
			movzx eax, al
			stosw
			inc ecx
		.endw
		pop edi
		add ecx, ecx
		mov [edi+68], cl		;ShortNameLength (bytes)
		pop ecx					;name length
		push edi
		lea esi, wfd.cFileName
		add edi, FBDI_NAME
		.while (ecx)
			lodsb
			movzx eax, al
			stosw
			dec ecx
		.endw
		pop edi
		mov eax, [edi+60]		;FileNameLength
		add eax, FBDI_NAME+7
		and eax, not 7
		add edi, eax
		inc [ebx].DIROBJ.dwNext
		.break .if (byte ptr bSingle)
		invoke FindNextFileA, hFind, addr wfd
		.break .if (!eax)
	.endw
	invoke FindClose, hFind
	.if (!pLast && status == STATUS_SUCCESS)
		mov status, STATUS_NO_MORE_FILES
	.endif

setiosb:
	mov ecx, pIosb
	.if (ecx)
		mov eax, status
		mov [ecx], eax
		xor eax, eax
		.if (pLast)
			mov eax, edi
			sub eax, pInfo
			.if (eax > dwLength)
				mov eax, dwLength
			.endif
		.endif
		mov [ecx+4], eax
	.endif
	mov eax, status
	@strace <"NtQueryDirectoryFile(", hFile, ", ", pInfo, ", ", dwLength, ", ", dwClass, ", ", bSingle, ", ", pName, ", ", bRestart, ")=", eax>
	ret
	align 4

NtQueryDirectoryFile endp

RtlNtStatusToDosError proc public uses esi dwStatus:dword

	mov esi, offset stattab
	mov eax, dwStatus
	.while (esi < offset stattabend)
		.if (eax == [esi])
			mov eax, [esi+4]
			jmp exit
		.endif
		add esi, 8
	.endw
	mov eax, 317		;ERROR_MR_MID_NOT_FOUND, as Windows does
exit:
	@strace <"RtlNtStatusToDosError(", dwStatus, ")=", eax>
	ret
	align 4

RtlNtStatusToDosError endp

RtlGetLastNtStatus proc public

	xor eax, eax
	ret
	align 4

RtlGetLastNtStatus endp

NtClose proc public hObj:dword

	invoke CloseHandle, hObj
	.if (eax)
		xor eax, eax
	.else
		mov eax, STATUS_INVALID_HANDLE
	.endif
	ret
	align 4

NtClose endp

	end
