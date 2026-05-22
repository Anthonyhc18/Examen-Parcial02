FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color

# ── Build tools ────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Kernel compilation
    git vim make gcc gcc-12 g++ \
    libncurses-dev flex bison bc \
    cpio libelf-dev libssl-dev \
    libdw-dev libunwind-dev \
    pahole dwarves \
    # QEMU y virtualización
    qemu-system-x86 qemu-utils \
    # BusyBox
    musl-tools musl-dev \
    # Red y herramientas generales
    iproute2 net-tools curl wget \
    openssh-client openssh-server \
    socat netcat-openbsd \
    # Python para el PoC
    python3 python3-pip \
    # Herramientas de análisis
    strace ltrace gdb \
    binutils elfutils \
    bsdextrautils xxd \
    # Git y calificación
    git jq bzip2 \
    && rm -rf /var/lib/apt/lists/*

# Python 3.10+ ya está en ubuntu:24.04; verificamos os.splice
RUN python3 -c "import sys; assert sys.version_info >= (3,10), 'Need Python 3.10+'"

# ── SSH server (para acceso al guest QEMU via port-forward) ────────────────────
RUN mkdir /var/run/sshd
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# ── Usuario de trabajo (imita usuario sin privilegios del reto) ────────────────
RUN useradd -m -s /bin/bash student && \
    echo "student:student" | chpasswd && \
    usermod -aG sudo student

# ── Directorio de trabajo ──────────────────────────────────────────────────────
WORKDIR /workspaces/copy-fail-challenge

# Punto de entrada por defecto
CMD ["/bin/bash"]
