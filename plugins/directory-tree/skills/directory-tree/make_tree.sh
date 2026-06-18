#!/bin/zsh

make_tree() {
	local fileName='directory_tree.md'
	local gitignore_file='.gitignore'

	local -a include_overrides=()
	while [[ $# -gt 0 ]]; do
		case $1 in
			--include|-i)
				shift
				[[ -n "$1" ]] && include_overrides+=(${(s:,:)1})
				;;
			--help|-h)
				echo "Usage: $0 [--include name1,name2,...]"
				return 0
				;;
			*)
				echo "Unknown option: $1" >&2
				return 1
				;;
		esac
		shift
	done

	# Build exclude pattern from .gitignore entries plus core exclusions
	local -a exclude_list=(.git .DS_Store)
	if [[ -f "$gitignore_file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -z "$line" || "$line" == \#* || "$line" == !* ]] && continue
			line=${line%%#*}
			line=${line%%[[:space:]]*}
			line=${line#./}
			line=${line#/}
			[[ -z "$line" ]] && continue
			if [[ "$line" == */ ]]; then
				exclude_list+="${line%/}"
			elif [[ "$line" != *\** && "$line" != *\?* && "$line" != *\[* && "$line" != *\]* && "$line" != *\{* && "$line" != *\}* && "$line" != *\\* ]]; then
				exclude_list+="$line"
			fi
		done < "$gitignore_file"
	fi

	local -a unique_excludes=(${(u)exclude_list})
	for inc in ${include_overrides[@]}; do
		unique_excludes=(${unique_excludes:#$inc})
	done
	local excludeDirs="${(j:|:)unique_excludes}"
	local -a tree_ignore_args=()
	[[ -n "$excludeDirs" ]] && tree_ignore_args=(-I "$excludeDirs")

	# Create the tree output (exclude patterns derived from .gitignore)
	tree -a -L 10 ${tree_ignore_args[@]} --dirsfirst -sD --timefmt "%Y-%m-%d" -o "$fileName"

	# Add markdown formatting
	echo "\`\`\`bash" | cat - "$fileName" > temp && mv temp "$fileName"
	echo "\`\`\`" >> "$fileName"

	echo "Directory tree created as $fileName"
}

make_tree "$@"
