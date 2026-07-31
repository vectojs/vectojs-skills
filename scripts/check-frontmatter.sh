#!/usr/bin/env bash
#
# Validate the YAML frontmatter of every skills/*/SKILL.md.
#
# This exists because a text reflow once collapsed a whole frontmatter block
# onto a single line (`--- name: x description: y ---`), which is still valid
# Markdown and reads fine to a human, but leaves the skill with no parseable
# name or description. It went unnoticed because the already-installed copy of
# the skill kept its correct frontmatter, so the skill still loaded locally
# while the repository source was broken.
#
# Checks, per skill:
#   1. line 1 is exactly `---`
#   2. a closing `---` exists on its own line
#   3. `name:` and `description:` are each present on their own line, non-empty
#   4. `name:` matches the containing directory name
#
# Structural checks only, so this needs no YAML library and runs anywhere.
# When `yq` is on PATH it additionally parses the block as real YAML.
#
# Usage: scripts/check-frontmatter.sh
# Exit:  0 all valid, 1 one or more invalid

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

bad=0
checked=0

for file in skills/*/SKILL.md; do
	[ -e "$file" ] || continue
	checked=$((checked + 1))
	dir=$(basename "$(dirname "$file")")

	if [ "$(sed -n '1p' "$file")" != "---" ]; then
		printf 'FAIL %s: line 1 must be exactly "---", got: %s\n' \
			"$file" "$(sed -n '1p' "$file")"
		bad=$((bad + 1))
		continue
	fi

	end=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
	if [ -z "$end" ]; then
		printf 'FAIL %s: no closing "---" on its own line\n' "$file"
		bad=$((bad + 1))
		continue
	fi

	block=$(sed -n "2,$((end - 1))p" "$file")

	name=$(printf '%s\n' "$block" | sed -n 's/^name:[[:space:]]*\(.*\)$/\1/p')
	desc=$(printf '%s\n' "$block" | sed -n 's/^description:[[:space:]]*\(.*\)$/\1/p')

	if [ -z "$name" ]; then
		printf 'FAIL %s: no non-empty "name:" line in the frontmatter\n' "$file"
		bad=$((bad + 1))
		continue
	fi

	if [ -z "$desc" ]; then
		printf 'FAIL %s: no non-empty "description:" line in the frontmatter\n' "$file"
		bad=$((bad + 1))
		continue
	fi

	if [ "$name" != "$dir" ]; then
		printf 'FAIL %s: name "%s" does not match directory "%s"\n' \
			"$file" "$name" "$dir"
		bad=$((bad + 1))
		continue
	fi

	if command -v yq >/dev/null 2>&1; then
		if ! printf '%s\n' "$block" | yq -e '.name and .description' >/dev/null 2>&1; then
			printf 'FAIL %s: frontmatter is not valid YAML with name+description\n' "$file"
			bad=$((bad + 1))
			continue
		fi
	fi

	printf 'ok   %s (frontmatter lines 1-%s, description %s chars)\n' \
		"$name" "$end" "${#desc}"
done

if [ "$checked" -eq 0 ]; then
	echo 'FAIL: no skills/*/SKILL.md files found'
	exit 1
fi

echo
if [ "$bad" -gt 0 ]; then
	printf '%s of %s skills have invalid frontmatter\n' "$bad" "$checked"
	exit 1
fi

printf 'all %s skills have valid frontmatter\n' "$checked"
