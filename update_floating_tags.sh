#!/usr/bin/env bash

# This script is based on the documentation available at [1].
#
# [1]: https://git-scm.com/book/en/v2/Git-Basics-Tagging

echo_create_tag(){
  # Args
  local tag_name="$1"
  local remote="$2"
  # Create tag locally
  echo "git tag $tag_name"
  # Create tag on remote
  echo "git push $remote $tag_name"
}

echo_delete_tag(){
  # Args
  local tag_name="$1"
  local remote="$2"
  # Delete tag locally
  echo "git tag -d $tag_name"
  # Delete tag on remote
  echo "git push $remote :refs/tags/$tag_name"
}

is_floating_tag(){
  # Args
  candidate_tag="$1"
  [[ $tag == *"x"* ]] && return 0 || return 1
}

is_floating_tag_for(){
  # Args
  local candidate_tag="$1"
  local release_tag="$2"
  # Others
  local tag_regex=""
  tag_regex=$(echo $candidate_tag | sed -e 's/\./\\./g' | sed -e 's/x/[0-9]+/g')
  is_floating_tag $candidate_tag && [[ $release_tag =~ $tag_regex ]] \
    && [[ ! $(commit_pointed_by_tag $release_tag) = $(commit_pointed_by_tag $candidate_tag) ]]
}

floating_tags_for(){
  # Args
  local release_tag="$1"
  # Loop's variable
  local tag=""
  # Others
  local tag_regex=""
  for tag in $(git tag -l)
  do
    is_floating_tag_for $tag $release_tag &&  echo $tag
  done
}

tag_exists(){
  # Args
  local tag_to_check="$1"
  # Loop's variable
  local tag=""
  for tag in $(git tag -l)
  do
    [[ $tag = $tag_to_check ]] && return 0
  done
  return 1
}

commit_pointed_by_tag(){
  # Args
  local tag="$1"
  git rev-list -n 1 "$tag"
}

print_tag(){
  # Args
  local tag="$1"
  echo "$tag -> $(commit_pointed_by_tag $tag)"
}

show(){
  # Args
  local release_tag="$1"
  # Loop's variable
  local floating_tag=""
  if ! tag_exists $release_tag
  then
    echo "Tag '$release_tag' does not exists"
    return 1
  fi
  echo "Release tag:"
  print_tag "$release_tag"

  echo "Floating tags to update for '$release_tag':"

  for floating_tag in $(floating_tags_for "$release_tag")
  do
    print_tag "$floating_tag"
  done
}

generate(){
  # Args
  local release_tag="$1"
  local remote="$2"
  # Loop's variable
  local floating_tag=""
  if ! tag_exists $release_tag
  then
    echo "Tag '$release_tag' does not exists"
    return 1
  fi

  echo "git checkout $release_tag"

  for floating_tag in $(floating_tags_for "$release_tag")
  do
    echo_delete_tag "$floating_tag" "$remote"
    echo_create_tag "$floating_tag" "$remote"
  done

  echo "git checkout $(commit_pointed_by_tag HEAD)"
}

main(){
  local command="$1"
  local release_tag="$2"
  local remote="$3"
  if [[ $command = "show" ]]
  then
    show "$release_tag" || return 1
    return 0
  fi

  if [[ $command = "generate" ]]
  then
    generate "$release_tag" "$remote" || return 1
    return 0
  fi

  echo "Unknown command: $command"
  return 1
}

main $@
