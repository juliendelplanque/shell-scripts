#!/usr/bin/env bash

# Set sane environment for bash scripts. ---------------------------------------
set -e
set -o pipefail
set -C
set -u

# Parameters -------------------------------------------------------------------
## Image, sources and VM
: ${IMAGE_VERSION:="70"}
: ${ARCHITECTURE:="32"}
: ${VM_VERSION:="vm70"}
: ${SOURCES_VERSION:="V60"}
: ${VERBOSE:="false"}
: ${MINIMAL:="minimal-"}
# Constants --------------------------------------------------------------------
## URLs
PHARO_URL="github://pharo-project/pharo:Pharo7.0/src"
TONEL_URL="github://pharo-vcs/tonel"
## Baselines
PHARO_BOOSTRAP_BASELINE="BaselineOfPharoBootstrap"
UFFI_BASELINE="BaselineOfUnifiedFFI"
TONEL_BASELINE="BaselineOfTonel"
## Commands
PHARO_CMD="./pharo Pharo.image"

# Functions --------------------------------------------------------------------

function die() {
    echo "$@" 1>&2
    exit 1
}

# Log what is piped to this function using the strategy chosen by user.
function log_message(){
  [[ $# -le 1 ]] || die "Usage: ${FUNCNAME[0]} [message_to_log]"

  # If message_to_log is passed, echo it.
  if [[ $# -eq 1 ]]; then echo "[$(date "+%Y/%m/%d-%H:%M:%S")] $1"; fi

  # If verbose mode is on, log what is coming from stdin.
  if [[ "$VERBOSE" = "true" ]]
  then
    cat </dev/stdin
  else
    cat </dev/stdin &> /dev/null
  fi
}

function download_image(){
  [[ $# -eq 2 ]] || die "Usage: ${FUNCNAME[0]} image_version directory"
  local image_version="$1" directory="$2"
  cd "$directory"
  wget "http://files.pharo.org/image/$image_version/latest-$MINIMAL$ARCHITECTURE.zip"
  unzip "latest-$MINIMAL$ARCHITECTURE.zip"
  rm "latest-$MINIMAL$ARCHITECTURE.zip"
  mv $(ls *.image) "Pharo.image"
  mv $(ls *.changes) "Pharo.changes"
  cd ..
}

function download_vm(){
  [[ $# -eq 2 ]] || die "Usage: ${FUNCNAME[0]} vm_version directory"
  local vm_version="$1" directory="$2"
  cd "$directory"
  curl "https://get.pharo.org/$ARCHITECTURE/$vm_version" | bash
  cd ..
}

function download_sources(){
  [[ $# -eq 2 ]] || die "Usage: ${FUNCNAME[0]} sources_version directory"
  local sources_version="$1" directory="$2"
  cd "$directory"
  wget "http://files.pharo.org/sources/Pharo$sources_version.sources"
  cd ..
}

function pharo_eval(){
  [[ $# -eq 1 ]] || die "Usage: ${FUNCNAME[0]} pharo_expression"
  local pharo_expression="$1"
  eval "$PHARO_CMD eval --save $pharo_expression"
}

function metacello_install(){
  [[ $# -eq 3 ]] || die "Usage: ${FUNCNAME[0]} url baseline groups"
  local url="$1" baseline="$2" groups="$3"
  eval "$PHARO_CMD metacello install $url $baseline --groups=$groups"
}

function prepare_image(){
  [[ $# -eq 0 ]] || die "Usage: ${FUNCNAME[0]}"
  pharo_eval 'NoChangesLog install.'
  pharo_eval 'NoPharoFilesOpener install.'
  pharo_eval 'FFICompilerPlugin install.'
  pharo_eval '5 timesRepeat: [ Smalltalk garbageCollect ].'
  pharo_eval 'PharoCommandLineHandler forcePreferencesOmission: true.'
}

function setup(){
  [[ $# -eq 4 ]] || die "Usage: ${FUNCNAME[0]} project_name project_repository project_baseline project_groups"
  local project_name="$1" project_repository="$2" project_baseline="$3" \
  project_groups="$4"
  # Create directory and enter it.
  mkdir "$project_name"

  # Download image, vm and sources files.
  download_image "$IMAGE_VERSION" "$project_name"
  download_vm "$VM_VERSION" "$project_name"
  download_sources "$SOURCES_VERSION" "$project_name"

  cd "$project_name"

  # Install Tonel (required for projects in Tonel format).
  metacello_install "$TONEL_URL" "$TONEL_BASELINE" "core"
  # Install KernelGroup
  metacello_install "$PHARO_URL" "$PHARO_BOOSTRAP_BASELINE" "KernelGroup"
  # Install UFFI (required for os stuff).
  metacello_install "$PHARO_URL" "$UFFI_BASELINE" "minimal"
  # Install jpp.
  metacello_install "$project_repository" "$project_baseline" "$project_groups"

  prepare_image

  # Go back to original directory.
  cd ..
}

function clean(){
  [[ $# -eq 1 ]] || die "Usage: ${FUNCNAME[0]} directory_to_clean"
  local directory_to_clean="$1"
  local temp_dir="$directory_to_clean.tmp"
  mkdir "$temp_dir"
  mv "$directory_to_clean/Pharo.image" "$temp_dir"
  mv "$directory_to_clean/pharo-vm" "$temp_dir"
  rm -rf $directory_to_clean/*
  mv $temp_dir/* "$directory_to_clean"
  rmdir "$temp_dir"
}

function generate_script(){
  [[ $# -eq 2 ]] || die "Usage: ${FUNCNAME[0]} directory tool_name"
  local directory="$1"
  local tool_name="$2"
  local script_file="$directory/$tool_name"
  printf '#!/usr/bin/env bash\n' >> "$script_file"
  printf 'DIR=`readlink "$0"` || DIR="$0";\n' >> "$script_file"
  printf 'DIR=`dirname "$DIR"`;\n' >> "$script_file"
  printf 'cd "$DIR"\n' >> "$script_file"
  printf 'DIR=`pwd`\n' >> "$script_file"
  printf 'cd - > /dev/null\n' >> "$script_file"
  printf 'set -f\n' >> "$script_file"
  printf '# run the VM and pass along all arguments as is\n' >> "$script_file"
  if [[ $(uname -s) = 'Darwin' ]]
  then
    printf '"$DIR"/"pharo-vm/Pharo.app/Contents/MacOS/Pharo"' >> "$script_file"
  else
    printf '"$DIR"/"pharo-vm/pharo"' >> "$script_file"
  fi
  printf ' --headless "$DIR/Pharo.image" "'$tool_name'" "$@"' >> "$script_file"
  chmod u+x "$script_file"
}

function print_final_help(){
  [[ $# -eq 1 ]] || die "Usage: ${FUNCNAME[0]} tool_name"
  local tool_name="$1"
  # Help user to set-up.
  echo "Installation is complete, to make jpp available from everywhere, add it to the PATH."
  echo 'If you run this script in $HOME directory, add EXPORT commands similar to the following in your .bashrc/.zshrc:'
  echo "# $tool_name"
  echo 'export '$(echo $tool_name | tr '[:lower:]' '[:upper:]')'_HOME="$HOME/jpp"'
  echo 'export PATH="$PATH:$JPP_HOME"'
}

function build(){
  [[ $# -eq 4 ]] || die "Usage: ${FUNCNAME[0]} tool_name repository_url baseline groups"
  local tool_name="$1" repository_url="$2" baseline="$3" groups="$4"
  local install_directory="$tool_name"
  setup "$install_directory" "$repository_url" "$baseline" "$groups"
  clean "$install_directory"
  generate_script "$install_directory" "$tool_name"
  print_final_help "$tool_name"
}

function main(){
  build $@
}

# Execute main -----------------------------------------------------------------
main $@
