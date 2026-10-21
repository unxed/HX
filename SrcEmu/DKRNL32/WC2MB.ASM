
;--- implements MultiByteToWideChar() and WideCharToMultiByte();
;--- also dummies: IsValidCodePage(), IsDBCSLeadByte(), IsDBCSLeadByteEx().
;--- CP_UTF8 is converted to/from UTF-16 (with surrogate pairs);
;--- all other code pages still map bytes 1:1 to 0000h-00FFh.

	.386
if ?FLAT
	.MODEL FLAT, stdcall
else
	.MODEL SMALL, stdcall
endif
	option proc:private
	option casemap:none

	include winbase.inc
	include winerror.inc
	include macros.inc

ifndef CP_UTF8
CP_UTF8 equ 65001
endif
ifndef WC_ERR_INVALID_CHARS
WC_ERR_INVALID_CHARS equ 80h
endif

	.CONST

;--- first byte of a UTF-8 sequence, indexed by the sequence length

u8lead db 0, 0, 0C0h, 0E0h, 0F0h

	.CODE

;--- UTF-8 -> UTF-16.
;--- returns number of WCHARs written to pDst (or required, if cchDst == 0);
;--- 0 on error. An ill-formed sequence (overlong, surrogate, > 10FFFFh,
;--- truncated) is replaced by U+FFFD the way Windows does it: one U+FFFD
;--- for the lead byte and the continuation bytes that fit, and one for
;--- the lead byte and a second byte in 80h-BFh that is out of the range
;--- allowed after E0h, EDh, F0h, F4h. With MB_ERR_INVALID_CHARS the whole
;--- input is still converted first (ERROR_INSUFFICIENT_BUFFER wins), then
;--- the call fails with ERROR_NO_UNICODE_TRANSLATION, as on Windows.

Utf8ToWide proc uses ebx esi edi pSrc:ptr BYTE, cbSrc:dword, pDst:ptr WORD,
							cchDst:dword, flags:dword

local nCont:dword
local bLo:dword
local bHi:dword
local bBad:dword

	mov esi, pSrc
	mov ecx, cbSrc
	mov edi, pDst
	xor ebx, ebx
	mov bBad, ebx
	.while (ecx)
		movzx eax, byte ptr [esi]
		inc esi
		dec ecx
		.if (eax < 80h)
			jmp u8_emit
		.endif
		mov bLo, 80h
		mov bHi, 0BFh
		.if (eax >= 0C2h && eax <= 0DFh)
			and eax, 1Fh
			mov nCont, 1
		.elseif (eax >= 0E0h && eax <= 0EFh)
			.if (eax == 0E0h)
				mov bLo, 0A0h
			.elseif (eax == 0EDh)
				mov bHi, 9Fh
			.endif
			and eax, 0Fh
			mov nCont, 2
		.elseif (eax >= 0F0h && eax <= 0F4h)
			.if (eax == 0F0h)
				mov bLo, 90h
			.elseif (eax == 0F4h)
				mov bHi, 8Fh
			.endif
			and eax, 07h
			mov nCont, 3
		.else
			jmp u8_invalid
		.endif
		.while (nCont)
			.if (!ecx)
				jmp u8_invalid
			.endif
			movzx edx, byte ptr [esi]
			.if (edx < 80h || edx > 0BFh)
				jmp u8_invalid
			.endif
			.if (edx < bLo || edx > bHi)
				inc esi
				dec ecx
				jmp u8_invalid
			.endif
			inc esi
			dec ecx
			shl eax, 6
			and edx, 3Fh
			or eax, edx
			mov bLo, 80h
			mov bHi, 0BFh
			dec nCont
		.endw
		jmp u8_emit
u8_invalid:
		mov bBad, 1
		mov eax, 0FFFDh
u8_emit:
		.if (eax >= 10000h)
			.if (cchDst)
				lea edx, [ebx+2]
				.if (edx > cchDst)
					jmp u8_nospace
				.endif
				sub eax, 10000h
				mov edx, eax
				shr eax, 10
				add eax, 0D800h
				and edx, 3FFh
				add edx, 0DC00h
				mov [edi+0], ax
				mov [edi+2], dx
				add edi, 4
			.endif
			add ebx, 2
		.else
			.if (cchDst)
				.if (ebx >= cchDst)
					jmp u8_nospace
				.endif
				mov [edi], ax
				add edi, 2
			.endif
			inc ebx
		.endif
	.endw
	mov eax, ebx
	.if (bBad && (flags & MB_ERR_INVALID_CHARS))
		invoke SetLastError, ERROR_NO_UNICODE_TRANSLATION
		xor eax, eax
	.endif
u8_exit:
	ret
u8_nospace:
	invoke SetLastError, ERROR_INSUFFICIENT_BUFFER
	xor eax, eax
	jmp u8_exit
	align 4

Utf8ToWide endp

;--- UTF-16 -> UTF-8.
;--- returns number of bytes written to pDst (or required, if cbDst == 0);
;--- 0 on error. An unpaired surrogate is replaced by U+FFFD; with
;--- WC_ERR_INVALID_CHARS the call then fails with ERROR_NO_UNICODE_TRANSLATION
;--- (after the whole input is converted, as in Utf8ToWide).

WideToUtf8 proc uses ebx esi edi pSrc:ptr WORD, cchSrc:dword, pDst:ptr BYTE,
							cbDst:dword, flags:dword

local nLeft:dword
local bBad:dword

	mov esi, pSrc
	mov eax, cchSrc
	mov nLeft, eax
	mov edi, pDst
	xor ebx, ebx
	mov bBad, ebx
	.while (nLeft)
		movzx eax, word ptr [esi]
		add esi, 2
		dec nLeft
		.if (eax >= 0D800h && eax <= 0DBFFh)
			.if (nLeft)
				movzx edx, word ptr [esi]
				.if (edx >= 0DC00h && edx <= 0DFFFh)
					add esi, 2
					dec nLeft
					sub eax, 0D800h
					shl eax, 10
					sub edx, 0DC00h
					add eax, edx
					add eax, 10000h
					jmp w8_emit
				.endif
			.endif
			jmp w8_invalid
		.elseif (eax >= 0DC00h && eax <= 0DFFFh)
			jmp w8_invalid
		.endif
		jmp w8_emit
w8_invalid:
		mov bBad, 1
		mov eax, 0FFFDh
w8_emit:
		.if (eax < 80h)
			mov edx, 1
		.elseif (eax < 800h)
			mov edx, 2
		.elseif (eax < 10000h)
			mov edx, 3
		.else
			mov edx, 4
		.endif
		.if (cbDst)
			lea ecx, [ebx+edx]
			.if (ecx > cbDst)
				jmp w8_nospace
			.endif
			mov ecx, edx
			.while (ecx > 1)
				dec ecx
				push eax
				and al, 3Fh
				or al, 80h
				mov [edi+ecx], al
				pop eax
				shr eax, 6
			.endw
			or al, [edx+u8lead]
			mov [edi], al
			add edi, edx
		.endif
		add ebx, edx
	.endw
	mov eax, ebx
	.if (bBad && (flags & WC_ERR_INVALID_CHARS))
		invoke SetLastError, ERROR_NO_UNICODE_TRANSLATION
		xor eax, eax
	.endif
w8_exit:
	ret
w8_nospace:
	invoke SetLastError, ERROR_INSUFFICIENT_BUFFER
	xor eax, eax
	jmp w8_exit
	align 4

WideToUtf8 endp

;--- returns number of characters written to pMultByte
;--- if cWideChar == -1, pWideChar is assumed to be zero-terminated.
;--- if nBuffSize == 0 pMultByte is not used
;--- and eax return the number of bytes required for the buffer

WideCharToMultiByte proc public uses esi edi codepage:dword,
							flags:dword,
							pWideChar:ptr WORD,
							cWideChar:dword,
							pMultByte:ptr BYTE,
							nBuffSize:dword,
							pDefaultChar:dword,
							pUsedDefaultChar:dword

	mov esi, pWideChar
	mov edi, pMultByte
	cmp esi, edi
	jz error1
	mov ecx, cWideChar
	.if (ecx == -1)
		invoke lstrlenW, esi
		inc eax
		mov ecx, eax
	.endif
	.if (codepage == CP_UTF8)
		.if (!ecx)
			jmp error1
		.endif
		invoke WideToUtf8, esi, ecx, edi, nBuffSize, flags
		jmp done
	.endif
	.if (!nBuffSize)
		mov eax, ecx
		jmp done
	.endif
	.if (ecx > nBuffSize)
		invoke SetLastError, ERROR_INSUFFICIENT_BUFFER
		xor eax,eax
		jmp done
	.endif
	xor eax, eax
	.while (ecx)
		lodsw
		stosb
		dec ecx
	.endw
	mov eax, edi
	sub eax, pMultByte
done:
ifdef _DEBUG
	@trace <"WideCharToMultiByte(">
	@tracedw codepage
	@trace <", ">
	@tracedw flags
	@trace <", ">
	@tracedw pWideChar
	@trace <", ">
	@tracedw cWideChar
	@trace <", ">
	.if (pMultByte)
		@traceN pMultByte, eax
	.else
		@trace <"NULL">
	.endif
	@trace <", ">
	@tracedw nBuffSize
	@trace <")=">
	@tracedw eax
	@trace <13,10>
endif
	ret
error1:
	invoke SetLastError, ERROR_INVALID_PARAMETER
	xor eax,eax
	jmp done
	align 4

WideCharToMultiByte endp

;--- returns number of characters written to pWideCharString
;--- if nMultByte == -1, pMultiByteString is assumed to be zero terminated.
;--- if nBuffSize == 0 pWideCharString is not used
;--- and eax return the number of wide chars required for the buffer


MultiByteToWideChar proc public uses esi edi codepage:dword,
							flags:dword,
							pMultiByteString:ptr BYTE,
							nMultByte:dword,
							pWideCharString:ptr WORD,
							nBuffSize:dword

	mov esi, pMultiByteString
	mov edi, pWideCharString
	cmp esi, edi
	jz error1
	mov ecx, nMultByte
	.if (ecx == -1)
		invoke lstrlenA, esi
		inc eax
		mov ecx, eax
	.endif
	.if (codepage == CP_UTF8)
		.if (!ecx)
			jmp error1
		.endif
		invoke Utf8ToWide, esi, ecx, edi, nBuffSize, flags
		jmp done
	.endif
	.if (!nBuffSize)
		mov eax, ecx
		jmp done
	.endif
	.if (ecx > nBuffSize)
		invoke SetLastError, ERROR_INSUFFICIENT_BUFFER
		xor eax,eax
		jmp done
	.endif
	xor eax, eax
	.while (ecx)
		lodsb
		stosw
		dec ecx
	.endw
	mov eax, esi
	sub eax, pMultiByteString
done:
ifdef _DEBUG
	@trace <"MultiByteToWideChar(">
	@tracedw codepage
	@trace <", ">
	@tracedw flags
	@trace <", ">
	@traceN pMultiByteString, eax
	@strace <", ", nMultByte, ", ^wc=", pWideCharString, ", ", nBuffSize, ")=", eax, " esp=", esp>
endif
	ret
error1:
	invoke SetLastError, ERROR_INVALID_PARAMETER
	xor eax,eax
	jmp done
	align 4

MultiByteToWideChar endp

IsValidCodePage proc public codepage:dword
	mov eax,1
	@strace <"IsValidCodePage(", codepage, ")=", eax, " *** unsupp ***">
	ret
	align 4
IsValidCodePage endp

IsDBCSLeadByte proc public testchar:dword
	xor eax, eax
	@strace <"IsDBCSLeadByte(", testchar, ")=", eax, " *** unsupp ***">
	ret
	align 4
IsDBCSLeadByte endp

IsDBCSLeadByteEx proc public codepage:dword, testchar:dword
	xor eax, eax
	@strace <"IsDBCSLeadByteEx(", codepage, ", ", testchar, ")=", eax, " *** unsupp ***">
	ret
	align 4
IsDBCSLeadByteEx endp

	end

