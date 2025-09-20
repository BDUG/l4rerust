#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
else
  set -eo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

# Ensure l4re-core is present and up to date
"$SCRIPT_DIR/update_l4re_core.sh"

# Ensure the ham build tool is available
HAM_PATH="$SCRIPT_DIR/../ham"
HAM_BIN="$HAM_PATH/ham"
if [ ! -x "$HAM_BIN" ]; then
  echo "ham binary not found, fetching..."
  if [ ! -d "$HAM_PATH" ]; then
    git clone https://github.com/kernkonzept/ham.git "$HAM_PATH"
  fi
  if [ ! -x "$HAM_BIN" ]; then
    (cd "$HAM_PATH" && gmake >/dev/null 2>&1 || true)
  fi
fi

# Ensure the Perl dependencies required by ham are available. If Git::Repository
# is missing we bootstrap a local installation using cpanminus so that the
# script can continue without requiring system-wide package management tools.
ensure_perl_module() {
  local module=$1

  if perl "-M${module}" -e1 >/dev/null 2>&1; then
    return 0
  fi

  local cpanm="$HAM_PATH/cpanm"
  local perl_lib="$HAM_PATH/perl5"

  echo "Perl module ${module} missing, installing locally via cpanm..."

  if [ ! -x "$cpanm" ]; then
    if ! curl -fsSL "https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm" -o "$cpanm"; then
      echo "Failed to download cpanm helper required to install Perl modules." >&2
      return 1
    fi
    chmod +x "$cpanm"
  fi

  mkdir -p "$perl_lib"

  if ! "$cpanm" --quiet --notest --local-lib "$perl_lib" "$module"; then
    echo "cpanm failed to install Perl module ${module}." >&2
    return 1
  fi

  export PERL5LIB="$perl_lib/lib/perl5${PERL5LIB:+:$PERL5LIB}"
  export PATH="$perl_lib/bin${PATH:+:$PATH}"
  export PERL_LOCAL_LIB_ROOT="$perl_lib${PERL_LOCAL_LIB_ROOT:+:$PERL_LOCAL_LIB_ROOT}"
  export PERL_MB_OPT="--install_base '$perl_lib'"
  export PERL_MM_OPT="INSTALL_BASE=$perl_lib"

  if perl "-M${module}" -e1 >/dev/null 2>&1; then
    return 0
  fi

  echo "Perl module ${module} still unavailable after installation attempt." >&2
  return 1
}

for module in Git::Repository XML::Parser; do
  if ! ensure_perl_module "$module"; then
    echo "Failed to provision Perl dependency $module automatically."
    echo "Install it manually (e.g. via your package manager or CPAN) and rerun setup." >&2
    exit 1
  fi
done

chmod +x "$HAM_BIN"
