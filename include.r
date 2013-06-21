REBOL [
	Title: "Include"
	File: %include.r
	Author: "Ladislav Mecir"
	WWW: http://www.rebol.net/wiki/INCLUDE_documentation
	License: {
		Licensed under the Apache License, Version 2.0 (the "License");
		you may not use this file except in compliance with the License.
		You may obtain a copy of the License at

		http://www.apache.org/licenses/LICENSE-2.0
	}
	Purpose: {A REBOL script processor: loader, preprocessor and evaluator.}
	Notes: {
		Global variables used:

			INCLUDE			the function

			INCLUDE-CTX		the context defining useful variables
							and functions

		INCLUDE-CTX functions:

			INCLUDE-SCRIPT	function used by INCLUDE and by directives
							to preprocess a script

			INCLUDE-BLOCK	generated by the SET-DIRECTIVES function,
							used by INCLUDE-SCRIPT and by directives
							to preprocess a block or a paren

			GET-DIRECTIVES	used to get the current directives

			SET-DIRECTIVES	used to define the current directives

			UPDATE-DIRECTIVES	used to update the current directives

			PUSH			saves the current PATH,
							replacing it temporarily by a new one

			POP				restores the PATH
							previously saved by the POP function

			DO-NEXT			do next expression,
							using the "R3 convention",
							compatible with R2 and R3

			LOAD-NEXT		load the next value,
							compatible with R2 and R3

			READ-BINARY		read the source as binary
							compatible with R2 and R3

			MAKE-ERROR		make the error according to the given SPEC,
							compatible with R2 and R3,
							allows setting the NEAR and WHERE attributes
							even in R2

			DISARM-ERROR	disarm the error,
							compatible with R2 and R3

			REDO-ERROR		"enhance" (if needed) and redo the given error

			INCLUDE-ERROR	create and trigger a new INCLUDE-type error

			SPLIT-PATH		a function splitting the given path

			FINDPFILE		find the given file using the given search path

			FIND-FILE		find a file
							(using INCLUDE-CTX/PATH if desired)

		INCLUDE-CTX variables:

			PATH			the search path used by the INCLUDE function,
							user-modifiable

			LOG				a block listing included files,
							user-modifiable

			STACK			used by the PUSH/POP functions
							to save/restore the current PATH

			BLOCK-DIRECTIVE	a directive handling a subblock or paren

			STANDARD-DIRECTIVES	the block contains the definitions of the
								standard directives except for the
								conditional directives and special includes

			SPECIAL-INCLUDES	the block contains the definitions of
								#include-binary, #include-string
								and #include-files

			CONDITIONAL-DIRECTIVES	the block contains the definitions of the
									conditional directives

			DIRECTIVES		the block contains the currently used definitions
							of INCLUDE directives
							Do not use directly!

			STANDARD-HEADER the script header prototype object

			FILE			the file processed by INCLUDE

		New INCLUDE error type defined, with following ids:

			ENHANCED		an, otherwise "normal" error,
							that occurred during code preprocessing;
							enhanced to "know" the file in which it occurred

			FILE-OR-URL-IN-PATH	a file or a URL was expected in the PATH

			STACK-EMPTY		the POP function found the STACK to be empty

			FILE-NOT-FOUND	file to be included was not found

			EXPECTED		the directive expected an argument

			INVALID-DIRECTIVE	the UPDATE-DIRECTIVES function obtained
								an invalid directive
								in the DIRECTIVES-TO-UPDATE block

		Global variables used by directives:

			KEEP-COMMENTS	if defined, COMMENTs are kept

		Patches:

			SCRIPT?			patched to handle strings
	}
]

comment [
	; Usage

	; to find and do a file %myfile.r:
	include %myfile.r

	; to append a URL or a directory to the search path:
	append include-ctx/path url-or-directory

	; to find out, how the include-ctx/path looks:
	print include-ctx/path

	; if you want to start using a totally new include-ctx/path:
	include-ctx/path: [%/my-search-dir/ %/etc/ http://www.myserv.dom/]

	; to include %somefile.r if not included before:
	include/check %somefile.r

	; to obtain a linked file:
	include/link %somefile.r %outfile.r

	; to obtain a Rebol block:
	include/only %somefile.r
]

unless value? 'include [
	; patch the SCRIPT? function if needed
	if error? try [script? ""] [
		script?: func [
			{Checks file, url, or string for a valid script header.}
			source [file! url! binary! string!]
		] [
			switch type?/word source [
				file! url! [source: read source]
				string! [source: to binary! source]
			]
			find-script source
		]
	]

	; definitions of directives, guarded against INCLUDE
	do if (#do [false]) [func [a b] [do first b]] #do [[
		include-ctx: make object! [
			; for compatibility with R2 and R3
			make-error: none
	
			; for compatibility with R2 and R3
			disarm-error: none
	
			; the currently processed file
			file: none
	
			; enhance the encountered error if needed and redo it
			redo-error: func [
				error [error!]
				/local disarmed
			] [
				disarmed: disarm-error error
				either disarmed/type = 'include [do error] [
					do make-error 'include 'enhanced compose/only/deep [
						(disarmed/arg1)
						(rejoin ["" disarmed/type " " disarmed/id " in " file])
						[
							file: (file)
							type: (disarmed/type)
							id: (disarmed/id)
							arg2: (disarmed/arg2)
							arg3: (disarmed/arg3)
						]
						(disarmed/near)
						(disarmed/where)
					]
				]
			]
	
			; cause INCLUDE error
			include-error: func [
				{Cause INCLUDE error}
				id
				near [block!]
				/expected
					arg3
				/local
					arg2
			] [
				if expected [
					arg2: id
					id: 'expected
				]
				do make-error 'include id compose/deep/only [
					(file)
					(arg2)
					(arg3)
					(near)
				]
			]
	
			; for compatibility with R2 and R3
			do-next: none
			load-next: none
			read-binary: none
			standard-header: none
	
			include-error-type-spec: [
				type: "include error"
				enhanced: [:arg2]
				file-or-URL-in-path: [
					"A file or URL expected in INCLUDE-CTX/PATH, a" :arg1 "obtained"
				]
				stack-empty: ["POP stack empty"]
				file-not-found: [
					"File" :arg1 "to be included from" :arg2 "was not found"
				]
				expected: [
					"A" :arg2 "was expected by the directive in" :arg1 ","
						:arg3 "obtained"
				]
				unexpected-directive: ["Unexpected directive found in" :arg1]
				invalid-directive: ["UPDATE-DIRECTIVES found an invalid directive"]
			]
	
			either in system 'error [
				make-error: func [
					type [word!]
					id [word!]
					args
					/local error disarmed
				] [
					disarmed: disarm error: make error! compose [
						(type) (id) (args)
					]
					disarmed/near: pick args 4
					disarmed/where: pick args 5
					return :error
				]
	
				disarm-error: :disarm
	
				do-next: func [
					block [block!]
					var [word!]
					/local result
				] [
					set/any reduce ['result var] do/next block
					return get/any 'result
				]
	
				load-next: func [
					{load the next value}
					[catch]
					'source [word!] {source position (modified)}
					/local result
				] [
					throw-on-error [
						set/any reduce ['result source] load/next get/any source
					]
					return get/any 'result
				]
	
				read-binary: func [
					{Reads from a file, url, or port-spec (block or object).}
					source [file! url! object! block!]
				] [
					read/binary source
				]
	
				unless value? 'body-of [
					body-of: func [
						"Returns a copy of the body of a function or object."
						value
					] [
						case [
							object? :value [third :value]
							function? :value [
								copy/deep second :value ; Note: Still bound!
							]
							any-function? :value [none] ; none if native
							'else [
								do make error! reduce [
									'script 'cannot-use 'reflect type? :value
								]
							]
						]
					]
				]
	
				system/error: make system/error [
					include: make object! compose [
						code: system/error/script/code + 50
						(include-error-type-spec)
					]
				]
	
				standard-header: system/standard/script
			] [
				make-error: func [
					err-type [word!]
					err-id [word!]
					args
				] [
					make error! [
						type: err-type
						id: err-id
						arg1: pick args 1
						arg2: pick args 2
						arg3: pick args 3
						near: pick args 4
						where: pick args 5
					]
				]
	
				disarm-error: func [error] [:error]
	
				do-next: func [
					block [block!]
					var [word!]
					/local result
				] [
					set/any 'result do/next block var
					return get/any 'result
				]
	
				load-next: func [
					{load the next value}
					'source [word!] {word referring to source position (modified)}
					/local result
				] [
					set/any reduce ['result source] transcode/next get/any source
					:result
				]
	
				read-binary: :read
	
				append system/catalog/errors compose [
					include: (
						make object! compose [
							code: system/catalog/errors/script/code + 50
							(include-error-type-spec)
						]
					)
				]
	
				standard-header: system/standard/header
			]
	
			split-path: function [
				{
					Splits a file or URL.
					Returns a block containing path and target.
	
					Overcomes some limitations of the Rebol/Core 2.2 split-path,
					like strange results for:
	
						split-path %file.r
						split-path %""
	
					The following equality holds:
	
						file = append first split-path file second split-path file
	
				}
				file [file! url!]
			] [target] [
				target: tail file
				if (pick target -1) = #"/" [target: back target]
				target: find/reverse target #"/"
				target: either target [next target] [file]
				reduce [copy/part file target to file! target]
			]
	
			findpfile: function [
				{Find a file using the given search path}
				path [block!]
				file [file! url!]
			] [dir found] [
				while [not empty? path] [
					unless any [file? first :path url? first :path] [
						do make-error 'include 'file-or-URL reduce [
							type? first :path
						]
					]
					if exists? found: append dirize copy dir: first :path :file [
						return found
					]
					path: next :path
				]
				none
			]
	
			find-file: func [
				{Find a file using an appropriate search path}
				file [file! url!]
				/local dir target
			] [
				set [dir target] split-path file
				case [
					empty? :dir [findpfile include-ctx/path target]
					exists? file [file]
				]
			]
	
			; include-ctx/path is initialized to contain the %. directory
			; and the directory, where the %include.r was run from
	
			path: reduce [%. what-dir]
	
			; to prevent multiple includes and create a log
			log: copy []
	
			; push/pop operation support
			stack: copy []
	
			push: func [
				{use the NEW-PATH temporarily}
				new-path [block!]
			] [
				append/only stack path
				path: new-path
			]
	
			pop: func [
				{restore the old INCLUDE-CTX/PATH}
			] [
				if empty? stack [
					do make-error 'include 'stack-empty []
				]
				path: last stack
				remove back tail stack
				path
			]
	
			; support for user-defined directives
			directives: copy []
	
			get-directives: func [
				{Returns the INCLUDE-CTX/DIRECTIVES block}
			] [
				directives
			]
	
			; the function used to preprocess a block or a paren,
			; generated by the SET-DIRECTIVES function
			include-block: none
	
			set-directives: func [
				{
					Sets the INCLUDE-CTX/DIRECTIVES block
					, and generates the INCLUDE-BLOCK function
				}
				new-directives [block!]
			] [
				directives: new-directives
				include-block: func [
					linked [block! paren!] {block containing the preprocessed code}
					pos1 [block! paren!] {block or paren to be preprocessed}
					/local pos2 value1 value2 value3
				] compose/deep [
					parse pos1 [
						any [(
							append copy directives [
								|
									set value1 skip
									(insert/only tail linked get/any 'value1)
							]
						)]
					]
					linked
				]
			]
	
			update-directives: func [
				{
					Updates INCLUDE DIRECTIVES.
					If a directive in the DIRECTIVES-TO-UPDATE block already exists,
					it is updated.
					If the directive does not exist, it is appended.
				}
				directives-to-update [block!]
				/only {change the DIRECTIVES block only}
				/local directive dir-start dir-end cont finish
					define-directive update-directive to-next-directive
			] [
				; make sure the block is not modified
				directives: copy directives
	
				; define the directive, if not found:
				define-directive: [(
					append directives '|
					append directives directive
				)]
	
				; update the directive, if found, and stop searching
				update-directive: [
					; find the end of the directive
					[to '| | to end] dir-end:
					(change/part dir-start directive dir-end)
					end skip
				]
	
				; used when the directive has not been found yet
				to-next-directive: [thru '| | to end]
	
				parse directives-to-update [
					any [
							'|
							(
								; invalid directive found
								do make-error 'include 'invalid-directive []
							)
						|
							[copy directive to '| '| | copy directive [skip to end]]
							(
								finish: define-directive
								cont: to-next-directive
		
								; look for the directive
								parse directives [
									any [
											dir-start: skip (
												if equal? first dir-start first directive [
													; directive found
													cont: update-directive
													finish: none
												]
											) cont
										|
											finish end skip
									]
								]
							)
					]
				]
	
				unless only [set-directives directives] 
			]
	
			set 'include func [
				{A script processor}
				[catch]
				file [file! url!] {the file to process}
				/check {include if the script hasn't been included yet}
				/link {create a linked file}
				output [file!]
				/only {create a Rebol block}
			] [
				include-script/start copy [] file check output only
			]
	
			include-script: func [
				{Include a script file}
				linked [block!] {block to append the processed code to (modified)}
				source [file! url!] {the file to process}
				check [none! logic!] {include if the script hasn't been included yet}
				/start {used by INCLUDE}
					output {create a linked file}
					only {create a REBOL block}
				/local
					file-name file-path dir binary-base result old-header err
					old-file
			] [
				; find the file
				unless result: find-file source [
					do make-error 'include 'file-not-found reduce [source file]
				]
				result: clean-path result
	
				; prevent multiple includes
				either all [find log :result check] [linked] [
					append log lowercase :result
					set [file-path file-name] split-path result
	
					; remember the old FILE before change
					old-file: file
					file: result
	
					; remember the old DIR before change
					dir: what-dir
					if file? file-path [
						change-dir file-path
						result: file-name
					]
	
					if error? err: try [
						; read the file
						result: read result
	
						; skip the preface
						result: any [script? result result]
	
						; load the script
						result: either #"[" = pick result 1 [
							; embedded script
							load-next result
						] [
							; script not embedded
							load/all result
						]
					] [redo-error err]
	
					; skip the header if it is not needed
					unless start [parse result ['REBOL block! result:]]
	
					; preprocess
					if error? result: try [include-block linked result] [
						redo-error result
					]
	
					; finish the job
					case [
						output [
							binary-base: system/options/binary-base
							system/options/binary-base: 64
							write output mold/only/all/flat result
							system/options/binary-base: binary-base
						]
						all [start not only] [
							; save the old header before setting the new one 
							old-header: system/script/header
	
							either parse result ['rebol block! to end] [
								system/script/header: construct/with second result standard-header
								result: skip result 2
							] [
								system/script/header: none
							]
	
							set/any 'result do result
	
							; restore the header
							system/script/header: old-header
						]
					]
	
					; return to the "original" DIR
					change-dir dir
	
					; return to the "original" FILE
					file: old-file
	
					get/any 'result
				]
			]
	
			set-directives block-directive: [
				[set value1 [block! | paren!]]
				(append/only linked include-block make value1 0 value1)
			]
	
			update-directives standard-directives: [
					#include-check pos1: (
						set/any 'value1 do-next pos1 'pos2
						any [
							file? get/any 'value1
							url? get/any 'value1
							include-error/expected "file or URL" pos1
								type? get/any 'value1
						]
						include-script linked value1 true
					) :pos2
				|
					#include pos1: (
						set/any 'value1 do-next pos1 'pos2
						any [
							file? get/any 'value1
							url? get/any 'value1
							include-error/expected "file or URL" pos1
								type? get/any 'value1
						]
						include-script linked value1 none
					) :pos2
				|
					#do pos1: [
							set value1 block!
						|
							(include-error/expected "do-block" pos1 none)
					] (insert tail linked do value1)
				|
					'comment pos1: (
						set/any 'value1 do-next pos1 'pos2
						if value? 'keep-comments [
							append linked 'comment
							insert/only tail linked get/any 'value1
						]
					) :pos2
			]
	
			update-directives conditional-directives: [
					#if pos1: [
							set value1 block!
						|
							(include-error/expected "condition-block" pos1 none)
					]
					[
							set value2 block!
						|
							(include-error/expected "then-block" pos1 none)
					]
					(
						case [
							unset? set/any 'value1 do value1 [
								include-error/expected "condition" pos1 "#[unset!]"
							]
							:value1 [include-block linked value2]
						]
					)
				|
					#either pos1: [
							set value1 block!
						|
							(include-error/expected "condition-block" pos1 none)
					]
					[
							set value2 block!
						|
							(include-error/expected "then-block" pos1 none)
					]
					[
							set value3 block!
						|
							(include-error/expected "else-block" pos1 none)
					]
					(
						if unset? set/any 'value1 do value1 [
							include-error/expected "condition" pos1 "#[unset!]"
						]
						include-block linked either :value1 [value2] [value3]
					)
			]
	
			update-directives special-includes: [
					#include-string pos1: (
						set/any 'value1 do-next pos1 'pos2
						any [
							file? get/any 'value1
							url? get/any 'value1
							include-error/expected "file or URL" pos1
								type? get/any 'value1
						]
						unless value2: find-file value1 [
							do make-error 'include 'file-not-found reduce [
								value1
								file
							]
						]
						append linked read value2
					) :pos2
				|
					#include-binary pos1: (
						set/any 'value1 do-next pos1 'pos2
						any [
							file? get/any 'value1
							url? get/any 'value1
							include-error/expected "file or URL" file pos1
								type? get/any 'value1
						]
						unless value2: find-file value1 [
							do make-error 'include 'file-not-found reduce [
								value1
								file
							]
						]
						append linked read-binary value2
					) :pos2
				|
					#include-files pos1: [
							set value1 file!
						|
							(include-error/expected "path" pos1 none)
					]
					[
							set value2 block!
						|
							(include-error/expected "path and a block" pos1 none)
					]
					(
						value3: make block! length? value2
						foreach file value2 [
							append value3 file
							append value3 read-binary value1/:file
						]
						append/only linked value3
					)
			]
		]
	]]
]
