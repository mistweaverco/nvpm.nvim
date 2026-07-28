#!/usr/bin/env bash

if [ -z "$VERSION" ]; then echo "Error: VERSION is not set"; exit 1; fi

GH_TAG="v$VERSION"

set_release_action() {
  if gh release view "$GH_TAG" --json id --jq .id > /dev/null 2>&1; then
    echo "Release $GH_TAG already exists, replace it"
    RELEASE_ACTION="replace"
  else
    echo "Release $GH_TAG does not exist, creating it"
    RELEASE_ACTION="create"
  fi
}

do_gh_release() {
  if [ "$RELEASE_ACTION" == "replace" ]; then
    echo "Replacing existing release $GH_TAG"
    gh release delete "$GH_TAG"
  else
    echo "Creating new release $GH_TAG"
  fi
  gh release create --generate-notes "$GH_TAG"
}

release() {
  set_release_action
  do_gh_release
}

boot() {
    release
}

boot
