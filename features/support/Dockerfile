FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and dependencies
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    dbus \
    ruby \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd units that cause issues in containers
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
    /lib/systemd/system/systemd-update-utmp*

# Create a test user that can run sudo without password and read journal logs
RUN useradd -m -s /bin/bash testuser && \
    usermod -aG systemd-journal testuser && \
    echo "testuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/testuser

# Configure journald for persistent storage
RUN mkdir -p /etc/systemd/journald.conf.d && \
    echo -e "[Journal]\nStorage=persistent" > /etc/systemd/journald.conf.d/storage.conf

# Create journal directory with correct group ownership upfront
RUN mkdir -p /var/log/journal && \
    chgrp systemd-journal /var/log/journal && \
    chmod 2755 /var/log/journal

# Install gems needed by procsd
RUN gem install thor dotenv simplecov --no-document

# Create app directory
RUN mkdir -p /home/testuser/myapp && chown testuser:testuser /home/testuser/myapp

VOLUME ["/sys/fs/cgroup"]

STOPSIGNAL SIGRTMIN+3

CMD ["/lib/systemd/systemd"]
