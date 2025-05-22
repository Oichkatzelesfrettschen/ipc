#!/usr/bin/env bash
set -euo pipefail
LOG_FILE=/var/log/setup_failures.log
touch "$LOG_FILE"
export DEBIAN_FRONTEND=noninteractive

#— helper to pin to the repo’s exact version if it exists
apt_pin_install(){
  pkg="$1"
  ver=$(apt-cache show "$pkg" 2>/dev/null \
        | awk '/^Version:/{print $2; exit}')
  if [ -n "$ver" ]; then
    set +e
    apt-get install -y "${pkg}=${ver}"
    status=$?
    set -e
  else
    set +e
    apt-get install -y "$pkg"
    status=$?
    set -e
  fi
  if [ $status -ne 0 ]; then
    echo "apt install failed: $pkg" | tee -a "$LOG_FILE"
    if [[ "$pkg" == python3-* ]]; then
      pip_pkg="${pkg#python3-}"
      echo "attempting pip install: $pip_pkg" | tee -a "$LOG_FILE"
      if ! pip3 install --no-cache-dir "$pip_pkg" >>"$LOG_FILE" 2>&1; then
        echo "pip install failed: $pip_pkg" | tee -a "$LOG_FILE"
      fi
    fi
  fi
}

#— enable foreign architectures for cross-compilation
for arch in i386 armel armhf arm64 riscv64 powerpc ppc64el ia64; do
  dpkg --add-architecture "$arch"
done

set +e
apt-get update -y
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "apt-get update failed" | tee -a "$LOG_FILE"
fi

#— core build tools, formatters, analysis, science libs
for pkg in \
  build-essential gcc g++ clang lld llvm \
  clang-format uncrustify astyle editorconfig pre-commit \
  make bmake ninja-build cmake meson \
  autoconf automake libtool m4 gawk flex bison byacc \
  pkg-config file ca-certificates curl git unzip \
  libopenblas-dev liblapack-dev libeigen3-dev \
  strace ltrace linux-perf systemtap systemtap-sdt-dev crash \
  valgrind kcachegrind trace-cmd kernelshark \
  libasan6 libubsan1 likwid hwloc; do
  apt_pin_install "$pkg"
done

#— Python & deep-learning / MLOps
for pkg in \
  python3 python3-pip python3-dev python3-venv python3-wheel \
  python3-numpy python3-scipy python3-pandas \
  python3-matplotlib python3-scikit-learn \
  python3-torch python3-torchvision python3-torchaudio \
  python3-onnx python3-onnxruntime; do
  apt_pin_install "$pkg"
done

set +e
pip3 install --no-cache-dir \
  tensorflow-cpu jax jaxlib \
  tensorflow-model-optimization mlflow onnxruntime-tools \
  cffi
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "pip install failed" | tee -a "$LOG_FILE"
fi

#— QEMU emulation for foreign binaries
for pkg in \
  qemu-user-static \
  qemu-system-x86 qemu-system-arm qemu-system-aarch64 \
  qemu-system-riscv64 qemu-system-ppc qemu-system-ppc64 qemu-utils; do
  apt_pin_install "$pkg"
done

#— multi-arch cross-compilers
for pkg in \
  bcc bin86 elks-libc \
  gcc-ia64-linux-gnu g++-ia64-linux-gnu \
  gcc-i686-linux-gnu g++-i686-linux-gnu \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  gcc-arm-linux-gnueabi g++-arm-linux-gnueabi \
  gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
  gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
  gcc-powerpc-linux-gnu g++-powerpc-linux-gnu \
  gcc-powerpc64-linux-gnu g++-powerpc64-linux-gnu \
  gcc-powerpc64le-linux-gnu g++-powerpc64le-linux-gnu \
  gcc-m68k-linux-gnu g++-m68k-linux-gnu \
  gcc-hppa-linux-gnu g++-hppa-linux-gnu \
  gcc-loongarch64-linux-gnu g++-loongarch64-linux-gnu \
  gcc-mips-linux-gnu g++-mips-linux-gnu \
  gcc-mipsel-linux-gnu g++-mipsel-linux-gnu \
  gcc-mips64-linux-gnuabi64 g++-mips64-linux-gnuabi64 \
  gcc-mips64el-linux-gnuabi64 g++-mips64el-linux-gnuabi64; do
  apt_pin_install "$pkg"
done

#— high-level language runtimes and tools
for pkg in \
  golang-go nodejs npm typescript \
  rustc cargo clippy rustfmt \
  lua5.4 liblua5.4-dev luarocks \
  ghc cabal-install hlint stylish-haskell \
  sbcl ecl clisp cl-quicklisp slime cl-asdf \
  ldc gdc dmd-compiler dub libphobos-dev \
  chicken-bin libchicken-dev chicken-doc \
  openjdk-17-jdk maven gradle dotnet-sdk-8 mono-complete \
  swift swift-lldb swiftpm kotlin gradle-plugin-kotlin \
  ruby ruby-dev gem bundler php-cli php-dev composer phpunit \
  r-base r-base-dev dart flutter gnat gprbuild gfortran gnucobol \
  fpc lazarus zig nim nimble crystal shards gforth; do
  apt_pin_install "$pkg"
done

#— Install the latest Go (>=1.23)
set +e
GO_STABLE=$(curl -fsSL https://go.dev/VERSION?m=stable | tr -d '\n' | sed 's/^go//')
status=$?
if [ $status -ne 0 ]; then
  GO_VERSION="go1.23.0"
else
  if dpkg --compare-versions "$GO_STABLE" ge "1.23"; then
    GO_VERSION="go${GO_STABLE}"
  else
    GO_VERSION="go1.23.0"
  fi
fi
curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz
status=$?
if [ $status -eq 0 ]; then
  rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz
  rm /tmp/go.tgz
  echo 'export PATH=/usr/local/go/bin:$PATH' > /etc/profile.d/go.sh
  export PATH=/usr/local/go/bin:$PATH
else
  echo "Go download failed" | tee -a "$LOG_FILE"
fi
set -e
export GOBIN=/usr/local/bin

#— Go development tools
for tool in \
  golang.org/x/tools/cmd/goimports@latest \
  github.com/golangci/golangci-lint/cmd/golangci-lint@latest \
  github.com/go-delve/delve/cmd/dlv@latest \
  github.com/google/gofuzz@latest \
  honnef.co/go/tools/cmd/staticcheck@latest; do
  set +e
  go install "$tool"
  status=$?
  set -e
  if [ $status -ne 0 ]; then
    echo "go install failed: $tool" | tee -a "$LOG_FILE"
  fi
done

#— GUI & desktop-dev frameworks
for pkg in \
  libqt5-dev qtcreator libqt6-dev \
  libgtk1.2-dev libgtk2.0-dev libgtk-3-dev libgtk-4-dev \
  libfltk1.3-dev xorg-dev libx11-dev libxext-dev \
  libmotif-dev openmotif cde \
  xfce4-dev-tools libxfce4ui-2-dev lxde-core lxqt-dev-tools \
  libefl-dev libeina-dev \
  libwxgtk3.0-dev libwxgtk3.0-gtk3-dev \
  libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev \
  libglfw3-dev libglew-dev; do
  apt_pin_install "$pkg"
done

#— containers, virtualization, HPC, debug
for pkg in \
  docker.io podman buildah virt-manager libvirt-daemon-system qemu-kvm \
  gdb lldb perf gcovr lcov bcc-tools bpftrace \
  openmpi-bin libopenmpi-dev mpich; do
  apt_pin_install "$pkg"
done

#— IA-16 (8086/286) cross-compiler
set +e
IA16_VER=$(curl -fsSL https://api.github.com/repos/tkchia/gcc-ia16/releases/latest \
           | awk -F"\"" '/tag_name/{print $4; exit}')
curl -fsSL "https://github.com/tkchia/gcc-ia16/releases/download/${IA16_VER}/ia16-elf-gcc-linux64.tar.xz" \
  | tar -Jx -C /opt
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "IA-16 cross-compiler install failed" | tee -a "$LOG_FILE"
else
  echo 'export PATH=/opt/ia16-elf-gcc/bin:$PATH' > /etc/profile.d/ia16.sh
  export PATH=/opt/ia16-elf-gcc/bin:$PATH
fi

#— protoc installer (pinned)
PROTO_VERSION=25.1
set +e
curl -fsSL "https://raw.githubusercontent.com/protocolbuffers/protobuf/v${PROTO_VERSION}/protoc-${PROTO_VERSION}-linux-x86_64.zip" \
  -o /tmp/protoc.zip
status=$?
if [ $status -eq 0 ]; then
  unzip -d /usr/local /tmp/protoc.zip
  rm /tmp/protoc.zip
else
  echo "protoc install failed" | tee -a "$LOG_FILE"
fi
set -e

#— gmake alias

command -v gmake >/dev/null 2>&1 || ln -s "$(command -v make)" /usr/local/bin/gmake

#— fetch go modules for the repository
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/go.mod" ]; then
  set +e
  (cd "$SCRIPT_DIR" && go mod download)
  status=$?
  set -e
  if [ $status -ne 0 ]; then
    echo "go mod download failed" | tee -a "$LOG_FILE"
  fi
fi

#— clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

exit 0
