#!/bin/bash 

set -e

function install_nix {
  # Source: https://github.com/cachix/install-nix-action/blob/master/lib/install-nix.sh
  if [ -d "/nix/store" ]; then
      echo "The folder /nix/store exists; assuming Nix was restored from cache"
      export CACHE_HIT=true
      export PATH=$PATH:/run/current-system/sw/bin
      set_paths
      exit 0
  fi

  add_config() {
    echo "$1" | sudo tee -a /tmp/nix.conf >/dev/null
  }
  add_config "max-jobs = auto"
  # Allow binary caches for runner user.
  add_config "trusted-users = root $USER"

  installer_options=(
    --daemon
    --daemon-user-count 4
    --darwin-use-unencrypted-nix-store-volume
    --nix-extra-conf-file /tmp/nix.conf
  )

  INPUT_NIX_PATH="nixpkgs=channel:$INPUT_NIX_VERSION"
  if [[ "$INPUT_NIX_PATH" != "" ]]; then
    installer_options+=(--no-channel-add)
  else
    INPUT_NIX_PATH="/nix/var/nix/profiles/per-user/root/channels"
  fi

  sh <(curl --silent --retry 5 --retry-connrefused -L "${INPUT_INSTALL_URL:-https://nixos.org/nix/install}") \
    "${installer_options[@]}"

  if [[ $OSTYPE =~ darwin ]]; then
    # Disable spotlight indexing of /nix to speed up performance
    sudo mdutil -i off /nix

    # macOS needs certificates hints
    cert_file=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
    echo "NIX_SSL_CERT_FILE=$cert_file" >> $GITHUB_ENV
    export NIX_SSL_CERT_FILE=$cert_file
    sudo launchctl setenv NIX_SSL_CERT_FILE "$cert_file"
  fi
}

function build_via_nix {
  # Path is set correctly by set_paths but that is only available outside of this Action.
  PATH=/nix/var/nix/profiles/default/bin/:$PATH
  nix build --extra-experimental-features nix-command --extra-experimental-features flakes $INPUT_FLAKE_PATHS
}

function set_paths {
  echo "/nix/var/nix/profiles/per-user/$USER/profile/bin" >> $GITHUB_PATH
  echo "/nix/var/nix/profiles/default/bin" >> $GITHUB_PATH
}

function prepare {
  sudo mkdir -p --verbose /nix
  sudo chown --verbose "$USER:" /nix 
}

function undo_prepare {
  sudo rm -rf /nix
}

TASK="$1"
if [ "$TASK" == "prepare-restore" ]; then
  prepare
elif [ "$TASK" == "build-with-nix" ]; then
  undo_prepare
  install_nix
  set_paths
  build_via_nix
elif [ "$TASK" == "install-from-cache" ]; then
  set_paths
elif [ "$TASK" == "prepare-save" ]; then
  prepare
else
  echo "Unknown argument given to core.sh: $TASK"
  exit 1
fi
