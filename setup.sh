#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LICENSE="DLS2eyJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSJ9"

get_profile_file() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    echo "$HOME/.bashrc"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    echo "$HOME/.zshrc"
  else
    echo "$HOME/.profile"
  fi
}

ensure_profile_comment() {
  local profile="$1"
  local comment="# Added by barcode-reader-java-samples/setup.sh"
  if [[ ! -f "$profile" ]]; then
    touch "$profile"
  fi
  if ! grep -Fx "$comment" "$profile" >/dev/null 2>&1; then
    echo "$comment" >> "$profile"
  fi
}

print_section() {
  echo
  echo "============================================================"
  echo "${1}"
  echo "============================================================"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root_or_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if ! command_exists sudo; then
      echo "Error: this script must be run as root or with sudo available." >&2
      exit 1
    fi
  fi
}

apt_install() {
  require_root_or_sudo
  local pkgs=("openjdk-17-jdk" "maven" "libxi6" "libxtst6")
  print_section "Updating apt package index"
  if [[ $EUID -ne 0 ]]; then
    sudo apt-get update
    sudo apt-get install -y "${pkgs[@]}"
  else
    apt-get update
    apt-get install -y "${pkgs[@]}"
  fi
}

brew_install() {
  local pkgs=("openjdk@17" "maven")
  if ! command_exists brew; then
    echo "Homebrew is required on macOS but was not found." >&2
    echo "Install Homebrew from https://brew.sh/ and re-run this script." >&2
    exit 1
  fi
  print_section "Installing packages with Homebrew"
  brew update
  for pkg in "${pkgs[@]}"; do
    if brew list "$pkg" >/dev/null 2>&1; then
      echo "Package $pkg already installed."
    else
      brew install "$pkg"
    fi
  done

  # Ensure Java 17 is linked for the current shell session.
  if [[ "${pkgs[*]}" == *"openjdk@17"* ]]; then
    local java_home
    java_home="$(/usr/libexec/java_home -v17 2>/dev/null || true)"
    if [[ -n "${java_home}" ]]; then
      export JAVA_HOME="${java_home}"
      if ! grep -q "JAVA_HOME" "$HOME/.bash_profile" 2>/dev/null; then
        {
          echo "# Added by barcode-reader-java-samples/setup.sh"
          echo "export JAVA_HOME=\"${java_home}\""
          echo 'export PATH="$JAVA_HOME/bin:$PATH"'
        } >> "$HOME/.bash_profile"
      fi
    fi
  fi
}

install_dependencies() {
  if command_exists javac && command_exists mvn; then
    echo "Java compiler and Maven already installed. Skipping installation."
    return
  fi

  case "$(uname -s)" in
    Linux)
      if command_exists apt-get; then
        apt_install
      else
        echo "Unsupported Linux distribution. Please install OpenJDK 17 and Maven manually." >&2
        exit 1
      fi
      ;;
    Darwin)
      brew_install
      ;;
    *)
      echo "Unsupported operating system $(uname -s)." >&2
      exit 1
      ;;
  esac
}

ensure_license_variable() {
  local current="${DYNAMSOFT_LICENSE:-}"
  if [[ -z "$current" ]]; then
    export DYNAMSOFT_LICENSE="$DEFAULT_LICENSE"
    current="$DEFAULT_LICENSE"
  fi

  local profile_file
  profile_file="$(get_profile_file)"
  ensure_profile_comment "$profile_file"
  if ! grep -Fx "export DYNAMSOFT_LICENSE=\"$current\"" "$profile_file" >/dev/null 2>&1; then
    echo "export DYNAMSOFT_LICENSE=\"$current\"" >> "$profile_file"
    echo "Configured DYNAMSOFT_LICENSE in $profile_file"
  else
    echo "DYNAMSOFT_LICENSE already configured in $profile_file"
  fi
}

configure_java_runtime() {
  if ! command_exists java; then
    echo "Java runtime not found. Skipping JAVA_HOME configuration."
    return
  fi

  local java_bin
  java_bin="$(command -v java)"
  local java_home
  local uname_out
  uname_out="$(uname -s)"

  if [[ "$uname_out" == "Darwin" ]]; then
    java_home="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
    if [[ -z "$java_home" ]]; then
      java_home="$(cd "$(dirname "$java_bin")/.." && pwd)"
    fi
  else
    java_home="$(dirname "$(dirname "$(readlink -f "$java_bin")")")"
  fi

  if [[ -z "$java_home" ]]; then
    echo "Unable to determine JAVA_HOME."
    return
  fi

  export JAVA_HOME="$java_home"

  local profile_file
  profile_file="$(get_profile_file)"
  ensure_profile_comment "$profile_file"

  if ! grep -Fx "export JAVA_HOME=\"$JAVA_HOME\"" "$profile_file" >/dev/null 2>&1; then
    echo "export JAVA_HOME=\"$JAVA_HOME\"" >> "$profile_file"
    echo "Configured JAVA_HOME in $profile_file"
  else
    echo "JAVA_HOME already configured in $profile_file"
  fi

  if [[ "$uname_out" == "Linux" ]]; then
    local ld_entry="export LD_LIBRARY_PATH=\"$JAVA_HOME/lib:$JAVA_HOME/lib/server:${LD_LIBRARY_PATH:-}\""
    if ! grep -Fx "$ld_entry" "$profile_file" >/dev/null 2>&1; then
      echo "$ld_entry" >> "$profile_file"
      echo "Configured LD_LIBRARY_PATH in $profile_file"
    else
      echo "LD_LIBRARY_PATH already configured in $profile_file"
    fi

    export LD_LIBRARY_PATH="$JAVA_HOME/lib:$JAVA_HOME/lib/server:${LD_LIBRARY_PATH:-}"
  fi
}

prepare_helloworld_sample() {
  print_section "Preparing HelloWorld sample"
  mvn -q -f "$ROOT_DIR/Samples/HelloWorld/pom.xml" dependency:go-offline
  mvn -q -f "$ROOT_DIR/Samples/HelloWorld/pom.xml" -DskipTests package
}

main() {
  print_section "Installing Java and Maven"
  install_dependencies

  print_section "Setting up Dynamsoft license"
  ensure_license_variable

  print_section "Configuring Java runtime paths"
  configure_java_runtime

  prepare_helloworld_sample

  cat <<'EOM'

Setup complete. You can now run the HelloWorld sample with:
  cd Samples/HelloWorld
  mvn -q exec:java -Dexec.mainClass=ReadAnImage
EOM
}

main "$@"
