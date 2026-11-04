#!/bin/bash
# Offline tests: each case builds a fixture /etc/apt under a temp root and
# runs the scripts against it via APT_REPO_POLICY_ROOT.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
AUDIT=$HERE/sbin/apt-repo-audit
ALLOW=$HERE/sbin/apt-repo-allow
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
pass=0 failed=0

fixture() {   # clean tree: Debian pins, one scoped repo with key and allow-list
	R=$WORK/$1; mkdir -p $R/etc/apt/{sources.list.d,preferences.d,trusted.gpg.d,keyrings}
	cp "$HERE"/etc/apt/preferences.d/*.pref $R/etc/apt/preferences.d/
	touch $R/etc/apt/trusted.gpg.d/debian-archive-trixie-stable.asc $R/etc/apt/keyrings/acme.asc
	printf 'deb http://deb.debian.org/debian/ trixie main\n' >$R/etc/apt/sources.list
	cat >$R/etc/apt/sources.list.d/acme.sources <<-EOF
	Types: deb
	URIs: https://apt.acme.example/debian
	Suites: stable
	Components: main
	Signed-By: /etc/apt/keyrings/acme.asc
	EOF
	printf 'Package: acme-tool\nPin: origin "apt.acme.example"\nPin-Priority: 500\n' >$R/etc/apt/preferences.d/50-acme.pref
}

expect() {    # expect <exit-code> <grep-pattern|-> <description> -- cmd...
	local want=$1 pat=$2 desc=$3; shift 4
	out=$("$@" 2>&1); got=$?
	if [ $got -eq $want ] && { [ "$pat" = - ] || grep -q -- "$pat" <<<"$out"; }; then
		pass=$((pass + 1)); echo "ok   $desc"
	else
		failed=$((failed + 1)); echo "FAIL $desc (exit $got, want $want)"; sed 's/^/     /' <<<"$out"
	fi
}
audit() { APT_REPO_POLICY_ROOT=$R "$AUDIT"; }
allow() { APT_REPO_POLICY_ROOT=$R APT_REPO_POLICY_LISTS=$R/lists "$ALLOW" "$@"; }

fixture clean;     expect 0 'OK (1 third-party'  "clean tree passes" -- audit

fixture list;      printf 'deb [signed-by=/x] https://a.example/ stable main\n' >$R/etc/apt/sources.list.d/a.list
                   expect 1 'one-line format' "one-line .list file is rejected" -- audit

fixture mainlist;  printf 'deb https://evil.example/ stable main\n' >>$R/etc/apt/sources.list
                   expect 1 'third-party entry evil.example' "third-party line in sources.list is rejected" -- audit

fixture nosig;     sed -i '/Signed-By/d' $R/etc/apt/sources.list.d/acme.sources
                   expect 1 'no Signed-By' "repo without Signed-By is rejected" -- audit

fixture badsig;    sed -i 's|keyrings/acme.asc|trusted.gpg.d/acme.asc|' $R/etc/apt/sources.list.d/acme.sources
                   expect 1 'points into global trust' "Signed-By into trusted.gpg.d is rejected" -- audit

fixture nokey;     rm $R/etc/apt/keyrings/acme.asc
                   expect 1 'does not exist' "missing keyring file is rejected" -- audit

fixture nocomp;    sed -i '/Components/d' $R/etc/apt/sources.list.d/acme.sources
                   expect 1 'no Components' "flat repo (no Components) is rejected" -- audit

fixture globalkey; touch $R/etc/apt/trusted.gpg.d/acme.gpg
                   expect 1 'third-party key in global trust' "third-party key in trusted.gpg.d is rejected" -- audit

fixture legacy;    touch $R/etc/apt/trusted.gpg
                   expect 1 'trusted.gpg exists' "legacy trusted.gpg is rejected" -- audit

fixture nodeny;    rm $R/etc/apt/preferences.d/zz-default-deny.pref
                   expect 1 'zz-default-deny.pref missing' "missing default-deny pin is rejected" -- audit

fixture nodebian;  rm $R/etc/apt/preferences.d/00-debian.pref
                   expect 1 '00-debian.pref missing' "missing Debian pin is rejected" -- audit

fixture noallow;   rm $R/etc/apt/preferences.d/50-acme.pref
                   expect 0 'has no allow-list' "repo without allow-list only warns (it is inert)" -- audit

fixture disabled;  printf '\nEnabled: no\nTypes: deb\nURIs: https://off.example/\nSuites: x\n' >>$R/etc/apt/sources.list.d/acme.sources
                   expect 0 'OK (1 third-party' "disabled stanza is ignored" -- audit

fixture twofiles;  printf 'Types: deb\nURIs: https://b.example/\nSuites: s\nComponents: main\n' >$R/etc/apt/sources.list.d/b.sources
                   expect 1 'b.sources: no Signed-By' "stanzas in separate files are not merged" -- audit
                   expect 1 'b.example has no allow-list' "every file's host is counted" -- audit

fixture hook;     expect 0 '^$' "--hook is silent when clean" -- env APT_REPO_POLICY_ROOT=$R "$AUDIT" --hook

fixture allow1
expect 1 'globs are refused' "allow refuses globs"           -- allow acme apt.acme.example 'acme-*'
expect 1 'shipped by Debian' "allow refuses a Debian name"   -- allow acme apt.acme.example bash
expect 1 'bare hostname'     "allow refuses a URL as host"   -- allow acme https://apt.acme.example acme-tool
expect 0 'wrote'             "allow writes the pref"         -- allow acme apt.acme.example acme-tool acme-agent
expect 0 'acme-agent'        "pref lists both packages"      -- cat $R/etc/apt/preferences.d/50-acme.pref
mkdir -p $R/lists; printf 'Package: acme-tool\n\nPackage: acme-extra\n\nPackage: bash\n' >$R/lists/apt.acme.example_debian_dists_stable_main_binary-amd64_Packages
expect 0 'acme-extra *blocked' "--list shows unlisted package as blocked" -- allow --list apt.acme.example
expect 0 'acme-tool *allowed'  "--list shows allowed package"             -- allow --list apt.acme.example
expect 0 'bash *COLLIDES'      "--list flags Debian collisions"           -- allow --list apt.acme.example

echo "$pass passed, $failed failed"; [ $failed -eq 0 ]
