#!/usr/bin/env bash
# release-notes.sh: the release notes for a build, as Markdown on stdout.
#
# Environment: WHAT ("Prerelease (beta) build", ...), VERSION (11.21), WINE_REPO (git URL),
# BRANCH, COMMIT (full hash), NAME (file name without extension), DXVK_VERSION and
# DXVK_REF (empty without DXVK), GH_TOKEN (for the GitHub API).
#
# The patch table lists every commit on the branch that isn't on the Wine repository's
# master branch (FaithLife-Community/wine's master mirrors upstream Wine), merges left
# out, oldest first: exactly our changes on top of upstream, whatever upstream commit the
# branch is based on.
set -uo pipefail
HERE=$(dirname "$(readlink -f "$0")")
short=${COMMIT:0:12}
repo=$(printf '%s' "$WINE_REPO" | sed -nE 's#^https://github\.com/([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')

cat <<EOF
${WHAT} of **Wine ${VERSION}** from \`${BRANCH}\` (commit [\`${short}\`](${WINE_REPO%.git}/commit/${COMMIT})), with our patches for Logos Bible Software.

| Download | |
|---|---|
| \`${NAME}.AppImage\` | One file, runs on almost any distro. |
| \`${NAME}.tar.xz\` | The Wine folder only: starts Logos faster. OuDedetai's *Recommended Bundled* choice. |
EOF
if [ -n "${DXVK_VERSION:-}" ]; then
	cat <<EOF

**DXVK:** both carry our DXVK \`${DXVK_VERSION}\` ([FaithLife-Community/dxvk](https://github.com/FaithLife-Community/dxvk) \`${DXVK_REF}\`). \`dxvk-install\` puts it into a prefix when the GPU has Vulkan 1.4, and otherwise sets Wine's OpenGL renderer (see the usage guide below).
EOF
fi

echo
echo "## Patches"
echo
if [ -n "$repo" ] && base=$(gh api "repos/$repo/compare/master...$COMMIT" \
		--jq '"\(.merge_base_commit.sha[0:12]) \(.merge_base_commit.commit.message | split("\n")[0])"' 2>/dev/null); then
	echo "On top of upstream Wine at \`${base%% *}\` (${base#* }). Every commit not in upstream, oldest first;"
	echo "see [docs/patches.md](https://github.com/FaithLife-Community/wine-appimages/blob/main/docs/patches.md) for what each fixes and its upstream status."
	echo
	echo "| # | Commit | Change | Author |"
	echo "|---|---|---|---|"
	gh api --paginate "repos/$repo/compare/master...$COMMIT?per_page=100" \
		--jq '.commits[] | select(.parents | length == 1) | [.sha, (.commit.message | split("\n")[0]), .commit.author.name] | @tsv' |
	awk -F'\t' -v url="https://github.com/$repo/commit/" '{
		gsub(/\|/, "\\|", $2)
		printf "| %d | [`%s`](%s%s) | %s | %s |\n", NR, substr($1, 1, 9), url, $1, $2, $3
	}'
else
	echo "(Patch list unavailable: ${WINE_REPO} isn't a GitHub repository, or the GitHub API didn't answer.)"
fi

echo
echo "# Usage"
echo
# @NAME@ in the guide becomes this build's file name (without extension).
sed "s/@NAME@/${NAME}/g" "$HERE/../docs/release-usage.md"
