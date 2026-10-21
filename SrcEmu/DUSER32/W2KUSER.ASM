
;--- user32 functions of Windows 2000/XP that DUSER32 did not have, as far as
;--- Far Manager 2 imports them: ToUnicodeEx, MapVirtualKeyW, VkKeyScanW,
;--- RegisterClipboardFormatW (through the existing ...A / non-Ex versions,
;--- the keyboard layout is ignored as in those) and FlashWindowEx (does
;--- nothing, there is no window).

	.386
if ?FLAT
	.MODEL FLAT, stdcall
else
	.MODEL SMALL, stdcall
endif
	option casemap:none
	option proc:private

	include winbase.inc
	include winuser.inc
	include macros.inc
	include duser32.inc

ToUnicode proto stdcall :dword, :dword, :ptr, :ptr word, :dword, :dword
MapVirtualKeyA proto stdcall :dword, :dword
VkKeyScanA proto stdcall :dword
RegisterClipboardFormatA proto stdcall :ptr byte

	.CODE

ToUnicodeEx proc public uVirtKey:dword, uScanCode:dword, lpKeyState:ptr, lpChar:ptr word, cchBuff:dword, uFlags:dword, dwhkl:dword

	invoke ToUnicode, uVirtKey, uScanCode, lpKeyState, lpChar, cchBuff, uFlags
	@strace <"ToUnicodeEx(", uVirtKey, ", ", uScanCode, ", ", lpKeyState, ", ", lpChar, ", ", cchBuff, ", ", uFlags, ", ", dwhkl, ")=", eax>
	ret
	align 4

ToUnicodeEx endp

MapVirtualKeyW proc public uCode:DWORD, uMapType:DWORD

	invoke MapVirtualKeyA, uCode, uMapType
	@strace <"MapVirtualKeyW(", uCode, ", ", uMapType, ")=", eax>
	ret
	align 4

MapVirtualKeyW endp

;--- characters above 0FFh have no key: -1

VkKeyScanW proc public ch_:dword

	movzx eax, word ptr ch_
	.if (eax > 0FFh)
		or eax, -1
	.else
		invoke VkKeyScanA, eax
	.endif
	@strace <"VkKeyScanW(", ch_, ")=", eax>
	ret
	align 4

VkKeyScanW endp

RegisterClipboardFormatW proc public lpszFormat:ptr word

	mov eax, lpszFormat
	call ConvertWStr
	invoke RegisterClipboardFormatA, eax
	@strace <"RegisterClipboardFormatW(", lpszFormat, ")=", eax>
	ret
	align 4

RegisterClipboardFormatW endp

FlashWindowEx proc public pfwi:ptr

	xor eax, eax
	@strace <"FlashWindowEx(", pfwi, ")=", eax, " *** unsupp ***">
	ret
	align 4

FlashWindowEx endp

	end
