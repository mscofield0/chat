FROM ubuntu:focal

ENV TZ=Europe/Warsaw
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ========== Bootstrap
## Install essentials 
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        software-properties-common wget curl git gpg-agent file \
        python3 python3-pip

# ========== Install compilers
## User-settable versions:
## This Dockerfile should support gcc-[7, 8, 9, 10] and clang-[10, 11]
## Earlier versions of clang will require significant modifications to the IWYU section
ARG GCC_VER="10"
ARG LLVM_VER="11"

## Add gcc-${GCC_VER}
RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends gcc-${GCC_VER} g++-${GCC_VER}

## Add clang-${LLVM_VER}
RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - 2>/dev/null && \
    add-apt-repository -y "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-${LLVM_VER} main" && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        clang-${LLVM_VER} lldb-${LLVM_VER} lld-${LLVM_VER} clangd-${LLVM_VER} \
        llvm-${LLVM_VER}-dev libclang-${LLVM_VER}-dev clang-tidy-${LLVM_VER} \
        clang-format-${LLVM_VER}

# ========== Install Ninja and cmake_format
RUN python3 -m pip install ninja cmakelang && \
    ninja --version && \
    cmake-format --version

# ========== Install CMake
## Add current cmake/ccmake, from Kitware
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
        | gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ focal main' && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends cmake cmake-curses-gui

# ========== Make clang-extra-tools visible
RUN update-alternatives --install /usr/bin/clang-tidy clang-tidy $(which clang-tidy-${LLVM_VER}) 1
RUN update-alternatives --install /usr/bin/clangd clangd $(which clangd-${LLVM_VER}) 1
RUN update-alternatives --install /usr/bin/clang-format clang-format $(which clang-format-${LLVM_VER}) 1
RUN update-alternatives --install /usr/bin/lldb-vscode lldb-vscode $(which lldb-vscode-${LLVM_VER}) 1

# ========== Install include-what-you-use
ENV IWYU /home/iwyu
ENV IWYU_BUILD ${IWYU}/build
ENV IWYU_SRC ${IWYU}/include-what-you-use
RUN mkdir -p ${IWYU_BUILD} && \
    git clone --branch clang_${LLVM_VER} \
        https://github.com/include-what-you-use/include-what-you-use.git \
        ${IWYU_SRC}
RUN CC=clang-${LLVM_VER} CXX=clang++-${LLVM_VER} cmake -S ${IWYU_SRC} \
        -B ${IWYU_BUILD} \
        -G Ninja -DCMAKE_PREFIX_PATH=/usr/lib/llvm-${LLVM_VER} && \
    cmake --build ${IWYU_BUILD} -j && \
    cmake --install ${IWYU_BUILD}

## Per https://github.com/include-what-you-use/include-what-you-use#how-to-install:
## `You need to copy the Clang include directory to the expected location before
##  running (similarly, use include-what-you-use -print-resource-dir to learn
##  exactly where IWYU wants the headers).`
RUN mkdir -p $(include-what-you-use -print-resource-dir 2>/dev/null)
RUN ln -s $(readlink -f /usr/lib/clang/${LLVM_VER}/include) \
    $(include-what-you-use -print-resource-dir 2>/dev/null)/include


# ========== Set gcc-${GCC_VER} as default gcc
RUN update-alternatives --install /usr/bin/gcc gcc $(which gcc-${GCC_VER}) 100
RUN update-alternatives --install /usr/bin/g++ g++ $(which g++-${GCC_VER}) 100

# ========== Set clang-${LLVM_VER} as default clang
RUN update-alternatives --install /usr/bin/clang clang $(which clang-${LLVM_VER}) 100
RUN update-alternatives --install /usr/bin/clang++ clang++ $(which clang++-${LLVM_VER}) 100

# ========== Allow the user to set compiler defaults
ARG USE_CLANG

## if --build-arg USE_CLANG=1, set CC to 'clang' or set to null otherwise.
ENV CC=${USE_CLANG:+"clang"}
ENV CXX=${USE_CLANG:+"clang++"}

## if CC is null, set it to 'gcc' (or leave as is otherwise).
ENV CC=${CC:-"gcc"}
ENV CXX=${CXX:-"g++"}

# ========== Install Conan
RUN python3 -m pip install --upgrade pip setuptools && \
    python3 -m pip install conan && \
    conan --version

# ========== Install ccache
RUN apt-get install -y --no-install-recommends \ 
    ccache
    
# ========== Install cppcheck
RUN apt-get install -y --no-install-recommends \ 
    cppcheck

# ========== Install doxygen and its dependencies
RUN apt-get install -y --no-install-recommends \ 
    doxygen graphviz

# ========== Disable Conan sudo-prepending
## By default, anything you run in Docker is done as superuser.
## Conan runs some install commands as superuser, and will prepend `sudo` to
## these commands, unless `CONAN_SYSREQUIRES_SUDO=0` is in your env variables.
ENV CONAN_SYSREQUIRES_SUDO 0

# ========== Enable Conan system package manager installations
# Some packages request that Conan use the system package manager to install
# a few dependencies. This flag allows Conan to proceed with these installations;
# leaving this flag undefined can cause some installation failures.
ENV CONAN_SYSREQUIRES_MODE enabled

# ========== Set default Conan generator
ENV CONAN_CMAKE_GENERATOR Ninja

# ========== Setup dev environment
## Set locales
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV LC_LANG C.UTF-8

## Install: 
## - neovim -- text editor/IDE 
## - ripgrep -- fast text search
## - fzf -- fast file search
## - tree -- file tree visualization
## - xclip -- for clipboard handling
## - Lazygit -- CLI visual Git client
## - clangd support
RUN add-apt-repository -y ppa:lazygit-team/release && \
    add-apt-repository -y ppa:neovim-ppa/stable && \
    apt-get install -y --no-install-recommends \
        neovim ripgrep fzf tree lazygit
        
## Make Neovim work with Python3
RUN python3 -m pip install pynvim

## Configure Neovim
RUN git clone https://github.com/mscofield0/nvim-ide /root/.config/nvim
RUN bash -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# Include project
ADD . /chat
WORKDIR /chat

CMD ["/bin/bash"]