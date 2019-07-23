#!/usr/bin/env bash

# Set sane environment for bash scripts. ---------------------------------------
set -e
set -o pipefail
set -C
set -u

# Constants --------------------------------------------------------------------
## Image, sources and VM
IMAGE_VERSION="70-minimal"
VM_VERSION="vm70"
SOURCES_VERSION="V60"
## URLs
PHARO_URL="github://pharo-project/pharo:Pharo7.0/src"
TONEL_URL="github://pharo-vcs/tonel"
## Baselines
PHARO_BOOSTRAP_BASELINE="BaselineOfPharoBootstrap"
UFFI_BASELINE="BaselineOfUnifiedFFI"
TONEL_BASELINE="BaselineOfTonel"
## Commands
PHARO_CMD="./pharo Pharo.image"
METACELLO_CMD="$PHARO_CMD metacello"
EVAL_CMD="$PHARO_CMD eval --save"

# Error codes ------------------------------------------------------------------
SETUP_FAILED="1"
METACELLO_INSTALL_FAILED="2"

# Functions --------------------------------------------------------------------

download_image(){
  [[ $# -eq 1 ]] || "Usage: ${FUNCNAME[0]} image_version"
  local image_version="$1"
  set +e # Hack, there is a problem in the script downloaded, a mv call fails
  curl "https://get.pharo.org/$image_version" | bash
  set -e # Back to sane mode
}

download_vm(){
  [[ $# -eq 1 ]] || "Usage: ${FUNCNAME[0]} vm_version"
  local vm_version="$1"
  curl "https://get.pharo.org/$vm_version" | bash
}

download_sources(){
  [[ $# -eq 1 ]] || "Usage: ${FUNCNAME[0]} sources_version"
  local sources_version="$1"
  wget "http://files.pharo.org/sources/Pharo$sources_version.sources"
}

prepare_image(){
  eval "$EVAL_CMD" 'NoChangesLog install.'
  eval "$EVAL_CMD" 'NoPharoFilesOpener install.'
  eval "$EVAL_CMD" 'FFICompilerPlugin install.'
  eval "$EVAL_CMD" '5 timesRepeat: [ Smalltalk garbageCollect ].'
  eval "$EVAL_CMD" 'PharoCommandLineHandler forcePreferencesOmission: true.'
}

metacello_install(){
  [[ $# -eq 3 ]] || "Usage: ${FUNCNAME[0]} url baseline groups"
  local url="$1" baseline="$2" groups="$3"
  eval "$METACELLO_CMD install $url $baseline --groups=$groups" \
    || exit "$METACELLO_INSTALL_FAILED"
}

setup(){
  [[ $# -eq 4 ]] || "Usage: ${FUNCNAME[0]} project_name project_repository project_baseline project_groups"
  local project_name="$1" project_repository="$2" project_baseline="$3" \
  project_groups="$4"
  # Create directory and enter it.
  mkdir "$project_name" || exit "$SETUP_FAILED"
  cd "$project_name"

  # Download image, vm and sources files.
  download_image $IMAGE_VERSION
  download_vm $VM_VERSION
  download_sources "$SOURCES_VERSION"

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

clean(){
  [[ $# -eq 1 ]] || "Usage: ${FUNCNAME[0]} directory_to_clean"
  local directory_to_clean="$1"
  local temp_dir="$directory_to_clean.tmp"
  mkdir "$temp_dir"
  #mv "$directory_to_clean/Pharo.changes" "$temp_dir"
  #mv $directory_to_clean/PharoV*.sources "$temp_dir"
  mv "$directory_to_clean/Pharo.image" "$temp_dir"
  mv "$directory_to_clean/pharo-vm" "$temp_dir"
  rm -rf $directory_to_clean/*
  mv $temp_dir/* "$directory_to_clean"
  rmdir "$temp_dir"
}

generate_script(){
  [[ $# -eq 2 ]] || "Usage: ${FUNCNAME[0]} directory tool_name"
  local directory="$1"
  local tool_name="$2"
  local script_file="$directory/$tool_name"
  echo '#!/usr/bin/env bash' >> "$script_file"
  echo 'DIR=`readlink "$0"` || DIR="$0";' >> "$script_file"
  echo 'DIR=`dirname "$DIR"`;' >> "$script_file"
  echo 'cd "$DIR"' >> "$script_file"
  echo 'DIR=`pwd`' >> "$script_file"
  echo 'cd - > /dev/null' >> "$script_file"
  echo 'set -f' >> "$script_file"
  echo '# run the VM and pass along all arguments as is' >> "$script_file"
  echo '"$DIR"/"pharo-vm/Pharo.app/Contents/MacOS/Pharo" --headless "$DIR/Pharo.image" "'$tool_name'" "$@"' >> "$script_file"
  chmod u+x "$script_file"
}

print_final_help(){
  [[ $# -eq 1 ]] || "Usage: ${FUNCNAME[0]} tool_name"
  local tool_name="$1"
  # Help user to set-up.
  echo "Installation is complete, to make jpp available from everywhere, add it to the PATH."
  echo 'If you run this script in $HOME directory, add EXPORT commands similar to the following in your .bashrc/.zshrc:'
  echo "# $tool_name"
  echo 'export '$(echo $tool_name | tr '[:lower:]' '[:upper:]')'_HOME="$HOME/jpp"'
  echo 'export PATH="$PATH:$JPP_HOME"'
}

build(){
  [[ $# -eq 4 ]] || "Usage: ${FUNCNAME[0]} tool_name repository_url baseline groups"
  local tool_name="$1" repository_url="$2" baseline="$3" groups="$4"
  local install_directory="$tool_name"
  setup "$install_directory" "$repository_url" "$baseline" "$groups"
  clean "$install_directory"
  generate_script "$install_directory" "$tool_name"
  print_final_help "$tool_name"
}

main(){
  build $@
}

# Execute main -----------------------------------------------------------------
main $@
