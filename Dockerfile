FROM centos:7

# Install DHCP server
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 && \
    yum -y --setopt=tsflags=nodocs install dhcp && \
    yum -y --setopt=tsflags=nodocs update && \
    yum clean all && \
    rm -rf /var/cache/yum

# Install latest release of dumb-init
RUN url=$(curl https://api.github.com/repos/Yelp/dumb-init/releases/latest | grep '"browser_' | grep 'amd64"' | awk '{print $2}' | sed -e 's/^"//' -e 's/"$//') && \
    curl -L $url -o dumb-init && \
    chmod +x dumb-init && \
    mv dumb-init /usr/bin/dumb-init

# Set up run command to start DHCP server via dumb-init
CMD ["/usr/bin/dumb-init", "/usr/sbin/dhcpd", "-f", "-d", "-cf", "/etc/dhcp/dhcpd.conf", "-user", "dhcpd", "-group", "dhcpd", "--no-pid"]
